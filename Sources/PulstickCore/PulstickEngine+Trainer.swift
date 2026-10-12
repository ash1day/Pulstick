import Foundation

// スピードトレーナー: 小節ごとのテンポの上げ下げ、次の段の予告、開始テンポへの戻し
extension PulstickEngine {
    /// いまのテンポをスピードトレーナーの起点にし、小節の数え直しを始める
    func restartSession() {
        sessionStartBPM = bpm
        speedTrainerProgress.restart()
        updateTempoStepCountdown()
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

    /// 小節の終わりごとにメインスレッドで呼ばれる
    func handleMeasureCompleted() {
        defer { updateTempoStepCountdown() }
        guard speedTrainerEnabled,
              let next = speedTrainerProgress.measureCompleted(speedTrainer, currentBPM: bpm, startBPM: sessionStartBPM)
        else { return }
        bpm = next
        onTempoStep?(bpm)
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
}
