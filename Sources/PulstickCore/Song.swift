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
    /// この曲で鳴らした最高のテンポ（練習の到達点）。まだ記録がなければ nil
    public var bestBPM: Double?

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
        bestBPM = try container.decodeIfPresent(Double.self, forKey: .bestBPM)
    }
}

/// 共有用のセットリスト。曲の設定だけを持ち、練習の記録は含めない
struct SharedSetlist: Codable {
    static let version = 1

    struct Entry: Codable {
        var name: String
        var bpm: Double
        var pattern: BeatPreset
        var subdivision: Subdivision
    }

    /// Pulstick のセットリストであることを示す印と形式の版
    var pulstick = SharedSetlist.version
    var songs: [Entry]

    /// 版だけを先に読む（新しい版なら「アップデートが必要」と伝えるため）
    struct Header: Codable {
        var pulstick: Int
    }

    /// 前後の文章を取り除き、チャットなどで “ ” に置き換わった引用符を戻して、JSON の部分を取り出す
    static func extractJSON(from text: String) -> Data? {
        let normalized = text
            .replacingOccurrences(of: "“", with: "\"")
            .replacingOccurrences(of: "”", with: "\"")
            .replacingOccurrences(of: "„", with: "\"")
        guard let start = normalized.firstIndex(of: "{"), let end = normalized.lastIndex(of: "}"), start < end else {
            return nil
        }
        return String(normalized[start...end]).data(using: .utf8)
    }
}

/// セットリストを取り込んだ結果
public enum SetlistImportResult: Equatable {
    /// 追加・更新した曲の数
    case imported(Int)
    /// Pulstick のセットリストではなかった
    case notASetlist
    /// 新しい版の Pulstick で書き出されたもの
    case needsNewerVersion
}
