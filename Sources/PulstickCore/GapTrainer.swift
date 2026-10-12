/// 「N 小節鳴らして M 小節は無音」を繰り返し、自分の中のテンポ感を鍛える練習モード
public struct GapTrainer: Codable, Equatable {
    public var playBars: Int
    public var muteBars: Int

    public init(playBars: Int = 2, muteBars: Int = 2) {
        self.playBars = playBars
        self.muteBars = muteBars
    }

    /// 再生開始からの小節番号（0 始まり）が無音区間か
    public func isMuted(measure: Int) -> Bool {
        let cycle = playBars + muteBars
        guard cycle > 0 else { return false }
        return measure % cycle >= playBars
    }
}
