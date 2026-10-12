/// 1 つの tick をどう扱うか（鳴らす音・無音小節か・カウントイン中か・練習の小節が 1 つ終わったか）。
/// タイマーキュー上の判断を純粋な関数にして、音を鳴らさずにテストできるようにする
struct TickPlan: Equatable {
    /// 鳴らす音。nil なら鳴らさない
    var sound: ClickKind?
    var isSilentBar = false
    var isCountingIn = false
    /// この tick で練習の小節が 1 つ終わった（スピードトレーナーが数える）
    var completesPracticeMeasure = false

    /// - Parameter measureIndex: この tick が属する小節の番号。カウントインの小節は負（-1, -2…）、練習の小節は 0 から。
    ///   再生開始時に -カウントインの小節数 から数え始めることが前提（PulstickEngine.start）
    /// - Parameter countsMeasure: 再生開始の最初の tick では false（小節の終わりではない）
    static func plan(for tick: Tick, measureIndex: Int, countsMeasure: Bool, gap: GapTrainer?, muted: Bool) -> TickPlan {
        if measureIndex < 0 {
            // カウントイン: 休符や細分の設定に関係なく拍ごとに鳴らす。小節の区切りが分かるよう頭だけ強拍にし、
            // ほかは弱拍の音にする（強拍の音量を 0 にしていても聞こえるように）
            let sound: ClickKind? = tick.click == .subdivision || muted ? nil : (tick.startsMeasure ? .accent : .normal)
            return TickPlan(sound: sound, isCountingIn: true)
        }
        let silentBar = gap?.isMuted(measure: measureIndex) ?? false
        let sound: ClickKind? = silentBar || muted || tick.isRest ? nil : tick.click
        // 練習の 1 小節目に入った瞬間は、まだ練習の小節は 1 つも終わっていない
        let completes = countsMeasure && tick.startsMeasure && measureIndex > 0
        return TickPlan(sound: sound, isSilentBar: silentBar, completesPracticeMeasure: completes)
    }
}
