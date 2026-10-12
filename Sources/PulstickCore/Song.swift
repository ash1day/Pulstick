import Foundation

/// 曲ごとのテンポと拍子の設定。バンドのセットリストや教室の課題曲を想定
public struct Song: Codable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var bpm: Double
    public var pattern: BeatPreset
    public var subdivision: Subdivision
    /// この曲を鳴らしていた時間の合計（秒）
    public var practiceSeconds: Double = 0

    public init(id: UUID = UUID(), name: String, bpm: Double, pattern: BeatPreset, subdivision: Subdivision) {
        self.id = id
        self.name = name
        self.bpm = bpm
        self.pattern = pattern
        self.subdivision = subdivision
    }

    /// practiceSeconds は後から加えた項目。曲は配列で保存しているので SettingsStore の
    /// 既定値への重ね合わせが効かず、ここで欠けていても読めるようにしないと曲リストが消える
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        bpm = try container.decode(Double.self, forKey: .bpm)
        pattern = try container.decode(BeatPreset.self, forKey: .pattern)
        subdivision = try container.decode(Subdivision.self, forKey: .subdivision)
        practiceSeconds = try container.decodeIfPresent(Double.self, forKey: .practiceSeconds) ?? 0
    }
}
