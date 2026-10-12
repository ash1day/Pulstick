import Combine

/// 拍ごとに変わる表示用の状態。エンジン本体と分けておくことで、
/// 拍のたびにポップオーバー全体やメニューバーが再評価されないようにする
public final class BeatClock: ObservableObject {
    @Published public internal(set) var current = 0
    /// いま無音の小節を再生中か。UI で「心の中で数えて」と示すために使う
    @Published public internal(set) var isInSilentBar = false

    public init() {}
}
