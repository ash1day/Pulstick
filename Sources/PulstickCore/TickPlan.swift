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
    /// カウントインで鳴らす音。小節の区切りが分かるよう頭だけ強拍、ほかは弱拍にするが、
    /// どちらかの音量が 0 なら聞こえる方の音で揃える（入りのテンポが必ずつかめるように）
    struct CountInSounds: Equatable {
        var downbeat: ClickKind = .accent
        var otherBeats: ClickKind = .normal

        init() {}

        init(accentVolume: Double, normalVolume: Double) {
            if normalVolume <= 0 {
                otherBeats = .accent
            } else if accentVolume <= 0 {
                downbeat = .normal
            }
        }
    }

    static func plan(
        for tick: Tick, measureIndex: Int, countsMeasure: Bool, gap: GapTrainer?, muted: Bool,
        countIn: CountInSounds = CountInSounds()
    ) -> TickPlan {
        if measureIndex < 0 {
            // カウントイン: 休符や細分の設定に関係なく拍ごとに鳴らす
            let sound: ClickKind? = tick.click == .subdivision || muted ? nil
                : (tick.startsMeasure ? countIn.downbeat : countIn.otherBeats)
            return TickPlan(sound: sound, isCountingIn: true)
        }
        let silentBar = gap?.isMuted(measure: measureIndex) ?? false
        let sound: ClickKind? = silentBar || muted || tick.isRest ? nil : tick.click
        // 練習の 1 小節目に入った瞬間は、まだ練習の小節は 1 つも終わっていない
        let completes = countsMeasure && tick.startsMeasure && measureIndex > 0
        return TickPlan(sound: sound, isSilentBar: silentBar, completesPracticeMeasure: completes)
    }
}
