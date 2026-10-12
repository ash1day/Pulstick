import Foundation

// 再生・停止とタイマー駆動。タイマーキュー上の状態（sequencer など）はこのファイルの関数からだけ触る
extension PulstickEngine {
    public func toggle() {
        if isPlaying {
            stop()
        } else {
            start()
        }
    }

    public func start() {
        guard !isPlaying else { return }
        isPlaying = true
        playbackGeneration += 1
        let generation = playbackGeneration
        beatClock.current = 0
        playStartedAt = now()
        practiceTimerStartedAt = playStartedAt
        practiceHasBegun = countInBars == 0
        restartSession()
        songPractice.start(currentSong?.id, at: now(), bpm: bpm)

        output.prepare()
        schedulePracticeTimer()

        // カウントインの小節は負の番号にし、練習の小節は 0 から数える
        let firstMeasure = -countInBars
        timerQueue.async { [self] in
            lastFireTime = DispatchTime.now().uptimeNanoseconds
            measureIndex = firstMeasure
            play(sequencer.reset(), countsMeasure: false, generation: generation)
        }
        scheduleTimer(generation: generation)
    }

    /// 音色を選んだときの試聴。再生中は鳴らさない（次の拍で新しい音が聞こえるため）
    public func previewClick() {
        guard !isPlaying else { return }
        output.prepare()
        timerQueue.async { [output] in
            output.play(.accent)
        }
    }

    /// 次の段で上がる BPM。目標で頭打ちになる最後の段は、残りの分だけ
    public var nextTempoIncrease: Int {
        Int((min(bpm + Double(speedTrainer.bpmIncrement), Double(speedTrainer.targetBPM)) - bpm).rounded())
    }

    /// トレーナーがテンポを開始時から変えていて、↶（R キー）で戻せる状態か
    public var canReturnToSessionStartBPM: Bool {
        guard speedTrainerEnabled, let start = sessionStartBPM else { return false }
        return bpm != start
    }

    /// スピードトレーナーで上げたテンポを再生開始時の値に戻す
    public func returnToSessionStartBPM() {
        guard canReturnToSessionStartBPM, let start = sessionStartBPM else { return }
        bpm = start
        restartSession()
    }

    /// 停止し、再生していた時間を練習ログに記録する。アプリ終了時にも呼ぶ
    public func stop() {
        let isLongEnough = isLongEnoughToLog
        if isLongEnough, let startedAt = playStartedAt {
            practiceLog.record(from: startedAt, to: now())
        }
        finishSongPractice(record: isLongEnough)
        isPlaying = false
        playbackGeneration += 1
        practiceTimer?.cancel()
        practiceTimer = nil
        practiceTimerStartedAt = nil
        playStartedAt = nil
        sessionStartBPM = nil
        timerSource?.cancel()
        timerSource = nil
        // キャンセル時点で実行中だったハンドラの終了を待ってから音を止め、停止後に 1 回鳴るのを防ぐ。
        // タイマー側はメインスレッドへ async でしか送らないので、ここで sync してもデッドロックしない
        timerQueue.sync {}
        output.stopAll()
        beatClock.current = 0
        beatClock.isInSilentBar = false
        beatClock.isCountingIn = false
        beatClock.barsUntilTempoStep = nil
    }

    /// カウントインが終わって練習の 1 小節目に入ったとき。カウントインの時間を練習に含めないよう、
    /// 経過時間・練習タイマー・曲の練習時間をここから数え直す
    func practiceDidBegin() {
        practiceHasBegun = true
        // カウントイン中にテンポを変えていたら、それを練習の起点（↶ や繰り返しで戻る先）にする
        restartSession()
        playStartedAt = now()
        practiceTimerStartedAt = playStartedAt
        schedulePracticeTimer()
        songPractice = SongPracticeTracker()
        songPractice.start(currentSong?.id, at: now(), bpm: bpm)
    }

    /// 再生開始時と、再生中に時間を変えたときに、止める時刻へ一度だけ発火するタイマーを仕掛け直す。
    /// 拍ごとに確かめる方式だと、遅いテンポでは最大 1 拍（30 BPM で 2 秒）遅れて止まるため
    func schedulePracticeTimer() {
        practiceTimer?.cancel()
        practiceTimer = nil
        guard isPlaying, let limit = stopAfter, let startedAt = practiceTimerStartedAt else { return }
        let generation = playbackGeneration
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.isPlaying, self.playbackGeneration == generation else { return }
            self.stop()
        }
        practiceTimer = item
        let remaining = max(0, limit - now().timeIntervalSince(startedAt))
        // スリープ中も時間が進むよう、起動時間ではなく実時間（wallDeadline）で指定する
        DispatchQueue.main.asyncAfter(wallDeadline: .now() + remaining, execute: item)
    }

    /// 小節の終わりごとにメインスレッドで呼ばれる
    func handleMeasureCompleted() {
        defer { updateTempoStepCountdown() }
        guard speedTrainerEnabled,
              let next = speedTrainerProgress.measureCompleted(speedTrainer, currentBPM: bpm, startBPM: sessionStartBPM)
        else { return }
        bpm = next
    }

    /// スピードトレーナーが次にテンポを変えるまでの小節数を、表示用に BeatClock へ反映する。
    /// 小節ごとに変わる値なので、エンジン本体ではなく BeatClock に置いてポップオーバー全体の再評価を避ける
    func updateTempoStepCountdown() {
        let bars = isPlaying && speedTrainerEnabled
            ? speedTrainerProgress.barsUntilStep(speedTrainer, currentBPM: bpm, startBPM: sessionStartBPM)
            : nil
        if beatClock.barsUntilTempoStep != bars {
            beatClock.barsUntilTempoStep = bars
        }
    }

    var tickInterval: Double {
        60.0 / bpm / Double(subdivision.rawValue)
    }

    /// テンポや細分が変わったとき、タイマーを作り直さず次の発火時刻だけ組み直す。
    /// 作り直すと「今から1間隔後」に戻ってしまい、ドラッグ中に音が止まるため
    func retimeIfPlaying() {
        guard isPlaying, let source = timerSource else { return }
        let interval = tickInterval
        timerQueue.async { [weak self] in
            guard let self else { return }
            let next = TickSchedule.nextDeadline(
                lastFire: self.lastFireTime, interval: interval, now: DispatchTime.now().uptimeNanoseconds
            )
            source.schedule(
                deadline: DispatchTime(uptimeNanoseconds: next),
                repeating: interval,
                leeway: .milliseconds(1)
            )
        }
    }

    /// DispatchSourceTimer を高優先度キューで駆動する。
    /// タイマーコールバック内で次のビートとアクセントを先に確定し、
    /// 音を鳴らしてから UI 更新をメインスレッドに送ることで、
    /// 音とビート表示のズレを防ぐ。
    func scheduleTimer(generation: Int) {
        let interval = tickInterval
        // .strict: macOS は省電力のために複数タイマーの発火をまとめる（timer coalescing）が、
        // メトロノームでは数ms のズレも体感できるため、まとめずに即発火させる。
        let source = DispatchSource.makeTimerSource(flags: .strict, queue: timerQueue)
        // leeway は OS がタイマー発火を遅延させてよい許容幅。
        // デフォルトだと数十ms 遅れうるため、1ms に制限して精度を確保する。
        source.schedule(
            deadline: .now() + interval,
            repeating: interval,
            leeway: .milliseconds(1)
        )
        source.setEventHandler { [weak self] in
            guard let self else { return }
            // 音の再生はタイマーキュー上で即実行する。
            // メインスレッドに送ると UI 処理の順番待ちで音が遅延するため。
            // 人間は視覚より聴覚のズレに敏感なので、音を優先し UI 更新だけ非同期で送る。
            self.lastFireTime = DispatchTime.now().uptimeNanoseconds
            self.play(self.sequencer.advance(), countsMeasure: true, generation: generation)
        }
        source.resume()
        timerSource = source
    }

    /// 拍のパターンや練習設定が変わったときに didSet から呼ぶ。まとめて変更している最中は反映を後回しにする
    func patternDidChange() {
        guard patternBatchDepth == 0 else { return }
        syncSequencer()
        // 一括変更の中でテンポも変わっていた場合、曲の切り替えが済んでから記録する
        if isPlaying { songPractice.notePlaying(bpm: bpm) }
    }

    /// 拍数・アクセント・休符・細分などを続けて変えるときに使う。
    /// 1 つ変えるたびにタイマーキューへの反映や曲の切り替え（とそれに伴う曲の保存）が走らないよう、最後に 1 回だけ反映する。
    /// 各設定値の UserDefaults への書き込みは、それぞれの didSet でそのまま行う
    func batchPatternChange(_ changes: () -> Void) {
        patternBatchDepth += 1
        changes()
        patternBatchDepth -= 1
        patternDidChange()
    }

    /// sequencer はタイマーキュー専用。メインスレッドの設定変更はここで非同期に反映し、
    /// タイマーキューとメインスレッドから同じ Set を同時に触るデータ競合を避ける
    func syncSequencer() {
        followCurrentSongIfPlaying()
        let beats = beatsPerMeasure
        let accents = accentBeats
        let rests = restBeats
        let subdivision = subdivision
        let gap = gapTrainerEnabled ? gapTrainer : nil
        let muted = isMuted
        syncCountInSounds()
        timerQueue.async { [weak self] in
            self?.activeGap = gap
            self?.activeMute = muted
            self?.sequencer.beatsPerMeasure = beats
            self?.sequencer.accents = accents
            self?.sequencer.rests = rests
            self?.sequencer.subdivision = subdivision
        }
    }

    /// 音量が変わるとカウントインで鳴らす音の選び方も変わるので、タイマーキューへ反映する
    func syncCountInSounds() {
        let countIn = TickPlan.CountInSounds(accentVolume: accentVolume, normalVolume: normalVolume)
        timerQueue.async { [weak self] in
            self?.activeCountIn = countIn
        }
    }

    /// タイマーキュー上で呼ぶ。音を先に鳴らし、UI 更新だけメインスレッドへ送る
    func play(_ tick: Tick, countsMeasure: Bool, generation: Int) {
        if countsMeasure, tick.startsMeasure {
            measureIndex += 1
        }
        let plan = TickPlan.plan(
            for: tick, measureIndex: measureIndex, countsMeasure: countsMeasure, gap: activeGap, muted: activeMute,
            countIn: activeCountIn
        )
        if let sound = plan.sound {
            output.play(sound)
        }
        guard tick.click != .subdivision else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isPlaying, self.playbackGeneration == generation else { return }
            self.beatClock.current = tick.beat
            if self.beatClock.isInSilentBar != plan.isSilentBar {
                self.beatClock.isInSilentBar = plan.isSilentBar
            }
            if self.beatClock.isCountingIn != plan.isCountingIn {
                if !plan.isCountingIn {
                    self.practiceDidBegin()
                }
                self.beatClock.isCountingIn = plan.isCountingIn
            }
            if plan.completesPracticeMeasure {
                self.handleMeasureCompleted()
            }
        }
    }
}
