import Foundation

/// タップの間隔から BPM を推定する。
/// 人のタップはばらつくので、平均ではなく直近の間隔の中央値を使い、1 回のもたつきに引きずられないようにする
public struct TapTempo {
    private var taps: [Date] = []
    /// 直近 8 回のタップ（7 間隔）まで使う
    private let maxTaps = 8
    /// これ以上間が空いたら新しいテンポを取り始めたとみなす
    private let timeout: TimeInterval = 2.0

    public init() {}

    /// タップを記録し、推定できれば BPM（整数に丸めたもの）を返す
    public mutating func tap(at time: Date) -> Double? {
        if let last = taps.last, time.timeIntervalSince(last) > timeout {
            taps.removeAll()
        }
        taps.append(time)
        if taps.count > maxTaps {
            taps.removeFirst(taps.count - maxTaps)
        }
        guard taps.count >= 2 else { return nil }

        let intervals = zip(taps.dropFirst(), taps).map { $0.timeIntervalSince($1) }.sorted()
        let middle = intervals.count / 2
        let median = intervals.count.isMultiple(of: 2)
            ? (intervals[middle - 1] + intervals[middle]) / 2
            : intervals[middle]
        // 小数の BPM は表示と食い違い、±ボタンでも端数が残るため整数に丸める
        return (60 / median).rounded()
    }
}
