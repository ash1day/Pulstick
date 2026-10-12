import Foundation
import Combine

public struct BeatPreset: Codable, Equatable {
    public var beats: Int
    public var accents: [Int]

    public var accentSet: Set<Int> { Set(accents) }

    public init(beats: Int, accents: [Int]) {
        self.beats = beats
        self.accents = accents
    }

    public static let defaults: [BeatPreset] = [
        BeatPreset(beats: 4, accents: [0]),
        BeatPreset(beats: 3, accents: [0]),
        BeatPreset(beats: 6, accents: [0, 3]),
        BeatPreset(beats: 9, accents: [0, 3, 6]),
    ]
}

/// メトロノームのオーディオ再生とタイミング制御を担当するエンジン。
/// DispatchSourceTimer で正確なビート間隔を維持し、ClickOutput に音を鳴らさせる。
public final class PulstickEngine: ObservableObject {
    public static let bpmRange: ClosedRange<Double> = 30...300
    public static let beatsRange: ClosedRange<Int> = 1...16

    /// UserDefaults のキー。フィールドの追加は codable(forKey:default:) が吸収するが、
    /// 既存フィールドの型や意味を変えるときはキー名も変えて旧データと衝突させないこと
    private enum Keys {
        static let presets = "pulstick.presets"
        static let bpm = "pulstick.bpm"
        static let beats = "pulstick.beats"
        static let accents = "pulstick.accents"
        static let accentVolume = "pulstick.accentVolume"
        static let normalVolume = "pulstick.normalVolume"
        static let subdivision = "pulstick.subdivision"
        static let speedTrainerEnabled = "pulstick.speedTrainerEnabled"
        static let speedTrainer = "pulstick.speedTrainer"
        static let gapTrainerEnabled = "pulstick.gapTrainerEnabled"
        static let gapTrainer = "pulstick.gapTrainer"
        static let practiceLog = "pulstick.practiceLog"
        static let clickSound = "pulstick.clickSound"
        static let songs = "pulstick.songs"
    }

    /// 起動時の復元中は didSet の副作用（保存・タイマーキューへの反映・音色生成）を止め、
    /// 復元後に一度だけまとめて反映する
    private var isRestoring = false

    @Published public var presets: [BeatPreset] = []
    /// 名前順に並んだ状態を保つ（追加は saveCurrentAsSong が並び順の位置に挿入する）
    @Published public private(set) var songs: [Song] = [] {
        didSet {
            guard !isRestoring else { return }
            defaults.setCodable(songs, forKey: Keys.songs)
        }
    }

    @Published public var bpm: Double = 120 {
        // didSet 内で clamp して再代入すると didSet が再発火するため、
        // 値が変わった場合のみ return で抜けてループを防ぐ
        didSet {
            // NaN は比較が常に不一致になり clamp の再代入が止まらなくなるため、非有限値は元に戻す
            guard bpm.isFinite else {
                bpm = oldValue
                return
            }
            let clamped = bpm.clamped(to: Self.bpmRange)
            if bpm != clamped {
                bpm = clamped
                return
            }
            guard !isRestoring, bpm != oldValue else { return }
            defaults.set(bpm, forKey: Keys.bpm)
            retimeIfPlaying()
        }
    }
    @Published public var isPlaying: Bool = false
    /// 再生開始時刻。練習時間の表示に使う
    @Published public private(set) var playStartedAt: Date?
    /// 再生開始時の BPM。スピードトレーナーで上がったテンポを元に戻すために使う
    @Published public private(set) var sessionStartBPM: Double?
    @Published public var beatsPerMeasure: Int = 4 {
        didSet {
            guard !isRestoring else { return }
            defaults.set(beatsPerMeasure, forKey: Keys.beats)
            syncSequencer()
        }
    }
    /// 拍ごとに変わる表示用の状態。このオブジェクト自体の変更通知とは分けてある
    public let beatClock = BeatClock()
    public var currentBeat: Int { beatClock.current }
    /// ユーザーが選択したアクセント拍の位置。タップで自由にon/off可能
    @Published public var accentBeats: Set<Int> = [0] {
        didSet {
            guard !isRestoring else { return }
            defaults.set(Array(accentBeats).sorted(), forKey: Keys.accents)
            syncSequencer()
        }
    }

    @Published public var subdivision: Subdivision = .quarter {
        didSet {
            guard !isRestoring, subdivision != oldValue else { return }
            defaults.set(subdivision.rawValue, forKey: Keys.subdivision)
            syncSequencer()
            retimeIfPlaying()
        }
    }

    @Published public var speedTrainerEnabled = false {
        didSet {
            guard !isRestoring else { return }
            defaults.set(speedTrainerEnabled, forKey: Keys.speedTrainerEnabled)
            speedTrainerProgress.restart()
        }
    }
    @Published public var speedTrainer = SpeedTrainer() {
        didSet {
            guard !isRestoring else { return }
            defaults.setCodable(speedTrainer, forKey: Keys.speedTrainer)
        }
    }
    /// 設定と違い毎小節変わるので @Published にも保存対象にもしない
    private var speedTrainerProgress = SpeedTrainerProgress()

    @Published public var gapTrainerEnabled = false {
        didSet {
            guard !isRestoring else { return }
            defaults.set(gapTrainerEnabled, forKey: Keys.gapTrainerEnabled)
            syncSequencer()
        }
    }
    @Published public var gapTrainer = GapTrainer() {
        didSet {
            guard !isRestoring else { return }
            defaults.setCodable(gapTrainer, forKey: Keys.gapTrainer)
            syncSequencer()
        }
    }

    @Published public private(set) var practiceLog = PracticeLog() {
        didSet {
            guard !isRestoring else { return }
            defaults.setCodable(practiceLog, forKey: Keys.practiceLog)
        }
    }
    /// これより短い再生は練習として記録しない（うっかり押しただけで連続日数が伸びないように）
    var minimumLoggedSession: TimeInterval = 5

    /// 練習タイマー。設定すると、再生開始からこの秒数で自動的に止まる。nil なら止まらない
    @Published public var stopAfter: TimeInterval? {
        didSet { schedulePracticeTimer() }
    }
    private var practiceTimer: DispatchWorkItem?

    /// 音だけを止める。拍の表示や練習時間の記録は続く。誤操作で無音のまま起動しないよう保存しない
    @Published public var isMuted = false {
        didSet { syncSequencer() }
    }

    @Published public var clickSound: ClickSound = .beep {
        didSet {
            guard !isRestoring, clickSound != oldValue else { return }
            defaults.set(clickSound.rawValue, forKey: Keys.clickSound)
            output.setSound(clickSound)
        }
    }

    /// スライダーのドラッグ中は値が細かく変わり続けるため、同じ値の書き込みは省く
    @Published public var accentVolume: Double = 1.0 {
        didSet {
            guard !isRestoring, accentVolume != oldValue else { return }
            output.setVolumes(accent: accentVolume, normal: normalVolume)
            defaults.set(accentVolume, forKey: Keys.accentVolume)
        }
    }
    @Published public var normalVolume: Double = 0.7 {
        didSet {
            guard !isRestoring, normalVolume != oldValue else { return }
            output.setVolumes(accent: accentVolume, normal: normalVolume)
            defaults.set(normalVolume, forKey: Keys.normalVolume)
        }
    }

    private let output: ClickOutput
    /// 直前に鳴らした時刻。タイマーキュー上でのみ読み書きする
    private var lastFireTime: UInt64 = 0
    /// 再生開始からの小節番号と、無音小節の設定。タイマーキュー上でのみ読み書きする
    private var measureIndex = 0
    private var activeGap: GapTrainer?
    private var activeMute = false
    /// 再生のたびに増える番号。停止直後に届いた前の再生の拍を、次の再生に反映しないために使う
    private var playbackGeneration = 0
    /// タイマーキュー上でのみ読み書きする
    private var sequencer = BeatSequencer(beatsPerMeasure: 4, accents: [0])
    private var timerSource: DispatchSourceTimer?
    /// メインスレッドとは別のキューでタイマーを駆動する。
    /// メインスレッドは UI 描画で占有されるため、そこにタイマーを載せると
    /// 描画負荷に引きずられてビートが遅延する可能性がある。
    /// .userInteractive は OS に最高優先度の CPU 割り当てを要求し、
    /// 他アプリのバックグラウンド処理（Spotlight 等）よりタイマー発火を優先させる。
    private let timerQueue = DispatchQueue(label: "com.pulstick.metronome", qos: .userInteractive)

    private var tapTempoEstimator = TapTempo()

    private let defaults: SettingsStore

    /// - Parameter output: 本番は AudioClickOutput、テストは SilentClickOutput。
    ///   テストで誤って音が鳴らないよう、あえてデフォルト値を持たせていない
    public init(defaults: SettingsStore = UserDefaults.standard, output: ClickOutput) {
        self.defaults = defaults
        self.output = output
        isRestoring = true
        loadPresets()
        restoreSettings()
        isRestoring = false
        syncSequencer()
        output.setVolumes(accent: accentVolume, normal: normalVolume)
        output.setSound(clickSound)
    }

    private func restoreSettings() {
        if let saved = defaults.object(forKey: Keys.bpm) as? Double {
            bpm = saved
        }
        if let saved = defaults.object(forKey: Keys.beats) as? Int {
            beatsPerMeasure = saved.clamped(to: Self.beatsRange)
        }
        if let saved = defaults.object(forKey: Keys.accents) as? [Int] {
            accentBeats = validAccents(saved)
        }
        if let saved = defaults.object(forKey: Keys.accentVolume) as? Double {
            accentVolume = saved.clamped(to: 0...1)
        }
        if let saved = defaults.object(forKey: Keys.normalVolume) as? Double {
            normalVolume = saved.clamped(to: 0...1)
        }
        if let raw = defaults.object(forKey: Keys.subdivision) as? Int, let saved = Subdivision(rawValue: raw) {
            subdivision = saved
        }
        if let raw = defaults.object(forKey: Keys.clickSound) as? String, let saved = ClickSound(rawValue: raw) {
            clickSound = saved
        }
        speedTrainer = defaults.codable(forKey: Keys.speedTrainer, default: speedTrainer)
        speedTrainerEnabled = defaults.object(forKey: Keys.speedTrainerEnabled) as? Bool ?? false
        gapTrainer = defaults.codable(forKey: Keys.gapTrainer, default: gapTrainer)
        gapTrainerEnabled = defaults.object(forKey: Keys.gapTrainerEnabled) as? Bool ?? false
        practiceLog = defaults.codable(forKey: Keys.practiceLog, default: practiceLog)
        songs = defaults.codable([Song].self, forKey: Keys.songs) ?? []
    }

    /// プレビューやスクリーンショット用に、見本の練習記録で置き換える
    public func seedPracticeLog(_ log: PracticeLog) {
        practiceLog = log
    }

    private func loadPresets() {
        if let saved = defaults.codable([BeatPreset].self, forKey: Keys.presets),
           saved.count == BeatPreset.defaults.count
        {
            presets = saved
        } else {
            presets = BeatPreset.defaults
        }
    }

    private func persistPresets() {
        defaults.setCodable(presets, forKey: Keys.presets)
    }

    /// 現在のテンポと拍子を曲として保存する。同じ名前（大文字小文字は区別しない）があれば上書き
    public func saveCurrentAsSong(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var song = Song(name: trimmed, bpm: bpm, pattern: currentPattern, subdivision: subdivision)
        if let index = songs.firstIndex(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            song.id = songs[index].id
            songs[index] = song
        } else {
            let index = songs.firstIndex { trimmed.localizedStandardCompare($0.name) == .orderedAscending } ?? songs.endIndex
            songs.insert(song, at: index)
        }
    }

    public func applySong(_ song: Song) {
        bpm = song.bpm
        beatsPerMeasure = song.pattern.beats.clamped(to: Self.beatsRange)
        accentBeats = validAccents(song.pattern.accents)
        subdivision = song.subdivision
        // 再生中に曲を切り替えたら、そこを新しい起点にする（↶ ボタンが前の曲のテンポに戻さないように）
        if isPlaying {
            restartSession()
        }
    }

    private var currentPattern: BeatPreset {
        BeatPreset(beats: beatsPerMeasure, accents: Array(accentBeats).sorted())
    }

    /// いまのテンポをスピードトレーナーの起点にし、小節の数え直しを始める
    private func restartSession() {
        sessionStartBPM = bpm
        speedTrainerProgress.restart()
    }

    /// 保存データや曲から読んだアクセント位置のうち、いまの拍数の範囲にあるものだけを残す
    private func validAccents(_ accents: [Int]) -> Set<Int> {
        Set(accents.filter { (0..<beatsPerMeasure).contains($0) })
    }

    /// 曲リストで「いま使っている曲」を強調するための判定
    public func matchesCurrentSettings(_ song: Song) -> Bool {
        song.bpm == bpm && song.pattern.beats == beatsPerMeasure
            && song.pattern.accentSet == accentBeats && song.subdivision == subdivision
    }

    public func deleteSong(_ song: Song) {
        songs.removeAll { $0.id == song.id }
    }

    public func applyPreset(at index: Int) {
        guard index < presets.count else { return }
        let preset = presets[index]
        beatsPerMeasure = preset.beats
        accentBeats = preset.accentSet
    }

    public func saveCurrentAsPreset(at index: Int) {
        guard index < presets.count else { return }
        presets[index] = currentPattern
        persistPresets()
    }

    public func resetPreset(at index: Int) {
        guard index < BeatPreset.defaults.count else { return }
        presets[index] = BeatPreset.defaults[index]
        persistPresets()
    }

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
        playStartedAt = Date()
        restartSession()

        output.prepare()
        schedulePracticeTimer()

        timerQueue.async { [self] in
            lastFireTime = DispatchTime.now().uptimeNanoseconds
            measureIndex = 0
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

    /// スピードトレーナーで上げたテンポを再生開始時の値に戻す
    public func returnToSessionStartBPM() {
        guard let start = sessionStartBPM else { return }
        bpm = start
        restartSession()
    }

    /// 停止し、再生していた時間を練習ログに記録する。アプリ終了時にも呼ぶ
    public func stop() {
        if let startedAt = playStartedAt, Date().timeIntervalSince(startedAt) >= minimumLoggedSession {
            practiceLog.record(from: startedAt, to: Date())
        }
        isPlaying = false
        playbackGeneration += 1
        practiceTimer?.cancel()
        practiceTimer = nil
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
    }

    /// 範囲外は bpm の didSet で丸められる
    public func incrementBPM(by step: Double = 1) {
        bpm += step
    }

    public func decrementBPM(by step: Double = 1) {
        bpm -= step
    }

    public func tapTempo(at now: Date = Date()) {
        if let tapped = tapTempoEstimator.tap(at: now) {
            bpm = tapped
        }
    }

    public func setBeats(_ beats: Int) {
        beatsPerMeasure = beats.clamped(to: Self.beatsRange)
        accentBeats = [0]
    }

    public func addBeat() {
        guard beatsPerMeasure < Self.beatsRange.upperBound else { return }
        beatsPerMeasure += 1
        // 追加した拍はデフォルトで弱（accentBeats に追加しない）
    }

    public func removeBeat() {
        guard beatsPerMeasure > Self.beatsRange.lowerBound else { return }
        let last = beatsPerMeasure - 1
        accentBeats.remove(last)
        beatsPerMeasure -= 1
        if beatClock.current >= beatsPerMeasure {
            beatClock.current = 0
        }
    }

    public func toggleAccent(_ beat: Int) {
        if accentBeats.contains(beat) {
            accentBeats.remove(beat)
        } else {
            accentBeats.insert(beat)
        }
    }

    /// 再生開始時と、再生中に時間を変えたときに、止める時刻へ一度だけ発火するタイマーを仕掛け直す。
    /// 拍ごとに確かめる方式だと、遅いテンポでは最大 1 拍（30 BPM で 2 秒）遅れて止まるため
    private func schedulePracticeTimer() {
        practiceTimer?.cancel()
        practiceTimer = nil
        guard isPlaying, let limit = stopAfter, let startedAt = playStartedAt else { return }
        let generation = playbackGeneration
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.isPlaying, self.playbackGeneration == generation else { return }
            self.stop()
        }
        practiceTimer = item
        let remaining = max(0, limit - Date().timeIntervalSince(startedAt))
        DispatchQueue.main.asyncAfter(deadline: .now() + remaining, execute: item)
    }

    /// 小節の終わりごとにメインスレッドで呼ばれる
    func handleMeasureCompleted() {
        guard speedTrainerEnabled,
              let next = speedTrainerProgress.measureCompleted(speedTrainer, currentBPM: bpm, startBPM: sessionStartBPM)
        else { return }
        bpm = next
    }

    private var tickInterval: Double {
        60.0 / bpm / Double(subdivision.rawValue)
    }

    /// テンポや細分が変わったとき、タイマーを作り直さず次の発火時刻だけ組み直す。
    /// 作り直すと「今から1間隔後」に戻ってしまい、ドラッグ中に音が止まるため
    private func retimeIfPlaying() {
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
    private func scheduleTimer(generation: Int) {
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

    /// sequencer はタイマーキュー専用。メインスレッドの設定変更はここで非同期に反映し、
    /// タイマーキューとメインスレッドから同じ Set を同時に触るデータ競合を避ける
    private func syncSequencer() {
        let beats = beatsPerMeasure
        let accents = accentBeats
        let subdivision = subdivision
        let gap = gapTrainerEnabled ? gapTrainer : nil
        let muted = isMuted
        timerQueue.async { [weak self] in
            self?.activeGap = gap
            self?.activeMute = muted
            self?.sequencer.beatsPerMeasure = beats
            self?.sequencer.accents = accents
            self?.sequencer.subdivision = subdivision
        }
    }

    /// タイマーキュー上で呼ぶ。音を先に鳴らし、UI 更新だけメインスレッドへ送る
    private func play(_ tick: Tick, countsMeasure: Bool, generation: Int) {
        if countsMeasure, tick.startsMeasure {
            measureIndex += 1
        }
        let silent = activeGap?.isMuted(measure: measureIndex) ?? false
        if !silent, !activeMute {
            output.play(tick.click)
        }
        guard tick.click != .subdivision else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isPlaying, self.playbackGeneration == generation else { return }
            self.beatClock.current = tick.beat
            if self.beatClock.isInSilentBar != silent {
                self.beatClock.isInSilentBar = silent
            }
            if countsMeasure, tick.startsMeasure {
                self.handleMeasureCompleted()
            }
        }
    }

    deinit {
        timerSource?.cancel()
    }
}

