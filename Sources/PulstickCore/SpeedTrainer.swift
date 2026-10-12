/// 一定小節ごとにテンポを上げていく練習モードのロジック
public struct SpeedTrainer: Codable, Equatable {
    public var measuresPerStep: Int
    public var bpmIncrement: Int
    public var targetBPM: Int
    /// 前回テンポを上げてから経過した小節数。保存対象外
    private var measuresSinceStep = 0

    private enum CodingKeys: String, CodingKey {
        case measuresPerStep, bpmIncrement, targetBPM
    }

    public init(measuresPerStep: Int = 4, bpmIncrement: Int = 2, targetBPM: Int = 160) {
        self.measuresPerStep = measuresPerStep
        self.bpmIncrement = bpmIncrement
        self.targetBPM = targetBPM
    }

    public mutating func restart() {
        measuresSinceStep = 0
    }

    /// 小節が1つ終わるたびに呼ぶ。テンポを上げるべきときは新しい BPM を返す
    public mutating func measureCompleted(currentBPM: Double) -> Double? {
        let target = Double(targetBPM)
        guard currentBPM < target else { return nil }
        measuresSinceStep += 1
        guard measuresSinceStep >= measuresPerStep else { return nil }
        measuresSinceStep = 0
        return min(currentBPM + Double(bpmIncrement), target)
    }
}
