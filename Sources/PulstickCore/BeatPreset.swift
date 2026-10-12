/// 1小節の拍数とアクセント・休符の位置。プリセットと曲の拍子に使う
public struct BeatPreset: Codable, Equatable {
    public var beats: Int
    public var accents: [Int]
    public var rests: [Int]

    public var accentSet: Set<Int> { Set(accents) }
    public var restSet: Set<Int> { Set(rests) }

    public init(beats: Int, accents: [Int], rests: [Int] = []) {
        self.beats = beats
        self.accents = accents
        self.rests = rests
    }

    /// rests は後から加えた項目。プリセットは配列で保存しているので SettingsStore の
    /// 既定値への重ね合わせが効かず、ここで欠けていても読めるようにしないと保存済みのプリセットが消える
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        beats = try container.decode(Int.self, forKey: .beats)
        accents = try container.decode([Int].self, forKey: .accents)
        rests = try container.decodeIfPresent([Int].self, forKey: .rests) ?? []
    }

    public static let defaults: [BeatPreset] = [
        BeatPreset(beats: 4, accents: [0]),
        BeatPreset(beats: 3, accents: [0]),
        BeatPreset(beats: 6, accents: [0, 3]),
        BeatPreset(beats: 9, accents: [0, 3, 6]),
    ]
}
