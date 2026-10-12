/// BPM に対応するイタリア語のテンポ記号。境界は一般的な目安で、流派により前後する
public enum TempoMarking {
    /// 各記号の下限 BPM。昇順に並べる
    private static let thresholds: [(lowerBound: Double, name: String)] = [
        (0, "Grave"),
        (40, "Largo"),
        (60, "Larghetto"),
        (66, "Adagio"),
        (76, "Andante"),
        (108, "Moderato"),
        (120, "Allegro"),
        (156, "Vivace"),
        (176, "Presto"),
        (200, "Prestissimo"),
    ]

    public static func name(for bpm: Double) -> String {
        thresholds.last { bpm >= $0.lowerBound }!.name
    }
}
