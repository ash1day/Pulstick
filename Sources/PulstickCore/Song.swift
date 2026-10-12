import Foundation

/// 曲ごとのテンポと拍子の設定。バンドのセットリストや教室の課題曲を想定
public struct Song: Codable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var bpm: Double
    public var pattern: BeatPreset
    public var subdivision: Subdivision

    public init(id: UUID = UUID(), name: String, bpm: Double, pattern: BeatPreset, subdivision: Subdivision) {
        self.id = id
        self.name = name
        self.bpm = bpm
        self.pattern = pattern
        self.subdivision = subdivision
    }
}
