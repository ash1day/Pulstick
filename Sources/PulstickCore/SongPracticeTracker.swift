import Foundation

/// 再生中に「いまどの曲の練習として数えているか」と、まだ確定していない時間を管理する。
/// 時刻は呼び出し側から渡すので、テストでは時間経過を自由に再現できる
public struct SongPracticeTracker {
    public private(set) var activeSongID: UUID?
    /// いまの区間を数え始めた時刻。nil なら数えていない（停止中）
    private var since: Date?
    private var pending: [UUID: Double] = [:]

    public init() {}

    /// 再生開始。id が nil（どの曲でもない設定）でも、後で名前を付けられるよう時間は数える
    public mutating func start(_ id: UUID?, at now: Date) {
        activeSongID = id
        since = now
    }

    /// 数える曲を切り替える。それまでの時間は前の曲の未確定分に積む
    public mutating func switchTo(_ id: UUID?, at now: Date) {
        closeStretch(at: now)
        activeSongID = id
        since = now
    }

    /// どの曲でもない設定を弾いていた時間を、いま名前を付けた曲として引き取る
    public mutating func adopt(_ id: UUID) {
        guard activeSongID == nil else { return }
        activeSongID = id
    }

    /// 数えていた曲が削除されたとき、その曲の未確定分と数えている途中の時間を別の曲（または無し）に付け替える
    public mutating func adoptReplacing(_ removed: UUID, with replacement: UUID?) {
        let carried = pending.removeValue(forKey: removed)
        if activeSongID == removed { activeSongID = replacement }
        if let replacement, let carried { pending[replacement, default: 0] += carried }
    }

    /// 曲の未確定分と、いま数えている途中の時間の合計
    public func unsavedSeconds(for id: UUID, at now: Date) -> Double {
        var total = pending[id] ?? 0
        if id == activeSongID, let since {
            total += now.timeIntervalSince(since)
        }
        return total
    }

    /// 確定させる時間を取り出して空にする
    public mutating func takePending() -> [UUID: Double] {
        defer { pending = [:] }
        return pending
    }

    /// 再生終了。数えていた時間を未確定分に積んで止める
    public mutating func stop(at now: Date) {
        closeStretch(at: now)
        activeSongID = nil
        since = nil
    }

    private mutating func closeStretch(at now: Date) {
        if let id = activeSongID, let since {
            pending[id, default: 0] += now.timeIntervalSince(since)
        }
    }
}
