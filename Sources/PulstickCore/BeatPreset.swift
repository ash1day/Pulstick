/// 1小節の拍数とアクセント位置。プリセットと曲の拍子に使う
public struct BeatPreset: Codable, Equatable {
    public var beats: Int
    public var accents: [Int]

    public var accentSet: Set<Int> { Set(accents) }

    public init(beats: Int, accents: [Int]) {
        self.beats = beats
        self.accents = accents
    }

    public static let defaults: [BeatPreset] = [
        BeatPreset(beats: 4, accents: [0]),
        BeatPreset(beats: 3, accents: [0]),
        BeatPreset(beats: 6, accents: [0, 3]),
        BeatPreset(beats: 9, accents: [0, 3, 6]),
    ]
}
