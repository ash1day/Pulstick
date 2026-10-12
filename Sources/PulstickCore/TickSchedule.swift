/// テンポ変更時に次の発火時刻を決める。時刻はすべてナノ秒（DispatchTime.uptimeNanoseconds）
public enum TickSchedule {
    /// 「今から1間隔後」ではなく「前回鳴った時刻から新しい1間隔後」にすることで、
    /// スライダーをドラッグし続けても音が途切れず、テンポ変更時のもたつきも出ない
    public static func nextDeadline(lastFire: UInt64, interval: Double, now: UInt64) -> UInt64 {
        let candidate = lastFire + UInt64(interval * 1_000_000_000)
        return max(candidate, now)
    }
}
