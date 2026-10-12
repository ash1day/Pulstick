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

    /// loops は後から追加した項目。保存済みの古いデータに無くても設定を失わないよう、無ければ false とする
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        measuresPerStep = try container.decode(Int.self, forKey: .measuresPerStep)
        bpmIncrement = try container.decode(Int.self, forKey: .bpmIncrement)
        targetBPM = try container.decode(Int.self, forKey: .targetBPM)
        loops = try container.decodeIfPresent(Bool.self, forKey: .loops) ?? false
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
    public mutating func measureCompleted(_ settings: SpeedTrainer, currentBPM: Double, startBPM: Double? = nil) -> Double? {
        let target = Double(settings.targetBPM)
        let atTarget = currentBPM >= target
        // 目標に達したら、繰り返しモードでなければそのまま維持する
        guard !atTarget || (settings.loops && startBPM != nil) else { return nil }
        measuresSinceStep += 1
        guard measuresSinceStep >= settings.measuresPerStep else { return nil }
        measuresSinceStep = 0
        if atTarget, let startBPM {
            // 目標テンポでも同じ小節数を弾いたら、開始テンポからやり直す
            return startBPM
        }
        return min(currentBPM + Double(settings.bpmIncrement), target)
    }
}
