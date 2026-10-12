/// 一定小節ごとにテンポを上げていく練習モードの設定。保存対象
public struct SpeedTrainer: Codable, Equatable {
    public var measuresPerStep: Int
    public var bpmIncrement: Int
    public var targetBPM: Int

    public init(measuresPerStep: Int = 4, bpmIncrement: Int = 2, targetBPM: Int = 160) {
        self.measuresPerStep = measuresPerStep
        self.bpmIncrement = bpmIncrement
        self.targetBPM = targetBPM
    }
}

/// スピードトレーナーの進行状況。再生ごとに変わる実行時の値なので設定とは分けて保存しない
public struct SpeedTrainerProgress {
    /// 前回テンポを上げてから経過した小節数
    private var measuresSinceStep = 0

    public init() {}

    public mutating func restart() {
        measuresSinceStep = 0
    }

    /// 小節が1つ終わるたびに呼ぶ。テンポを上げるべきときは新しい BPM を返す
    public mutating func measureCompleted(_ settings: SpeedTrainer, currentBPM: Double) -> Double? {
        let target = Double(settings.targetBPM)
        guard currentBPM < target else { return nil }
        measuresSinceStep += 1
        guard measuresSinceStep >= settings.measuresPerStep else { return nil }
        measuresSinceStep = 0
        return min(currentBPM + Double(settings.bpmIncrement), target)
    }
}
