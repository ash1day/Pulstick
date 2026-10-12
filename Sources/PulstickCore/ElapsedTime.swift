import Foundation

public enum ElapsedTime {
    /// 練習時間を "m:ss"、1時間以上なら "h:mm:ss" で表す
    public static func format(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }
}
