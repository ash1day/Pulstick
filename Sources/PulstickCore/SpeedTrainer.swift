/// 一定小節ごとにテンポを上げていく練習モードの設定。保存対象
public struct SpeedTrainer: Codable, Equatable {
    public var measuresPerStep: Int
    public var bpmIncrement: Int
    public var targetBPM: Int
    public var loops: Bool

    public init(measuresPerStep: Int = 4, bpmIncrement: Int = 2, targetBPM: Int = 160, loops: Bool = false) {
        self.measuresPerStep = measuresPerStep
        self.bpmIncrement = bpmIncrement
        self.targetBPM = targetBPM
        self.loops = loops
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

    /// 次にテンポを変えるまでの小節数。目標に達して繰り返しもしないなら、もう変えないので nil
    public func barsUntilStep(_ settings: SpeedTrainer, currentBPM: Double, startBPM: Double? = nil) -> Int? {
        let reachedTarget = currentBPM >= Double(settings.targetBPM)
        guard !reachedTarget || (settings.loops && startBPM != nil) else { return nil }
        return max(1, settings.measuresPerStep - measuresSinceStep)
    }

    /// 小節が1つ終わるたびに呼ぶ。テンポを上げるべきときは新しい BPM を返す
    public mutating func measureCompleted(_ settings: SpeedTrainer, currentBPM: Double, startBPM: Double? = nil) -> Double? {
        let target = Double(settings.targetBPM)
        // 目標に達したら、繰り返しモードなら同じ小節数を弾いた後に開始テンポへ戻り、そうでなければ維持する
        let restartBPM = currentBPM >= target ? (settings.loops ? startBPM : nil) : nil
        guard currentBPM < target || restartBPM != nil else { return nil }
        measuresSinceStep += 1
        guard measuresSinceStep >= settings.measuresPerStep else { return nil }
        measuresSinceStep = 0
        return restartBPM ?? min(currentBPM + Double(settings.bpmIncrement), target)
    }
}
