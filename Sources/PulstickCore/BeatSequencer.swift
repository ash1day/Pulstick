/// 1拍をいくつに刻むか
public enum Subdivision: Int, CaseIterable, Codable {
    case quarter = 1
    case eighth = 2
    case triplet = 3
    case sixteenth = 4
}

public enum ClickKind: Equatable, Sendable {
    case accent
    case normal
    case subdivision
}

public struct Tick: Equatable {
    public var beat: Int
    public var click: ClickKind
    /// この tick で新しい小節に入ったか（小節頭の tick で true）
    public var startsMeasure: Bool
}

/// 拍・細分の進行を管理する純粋なロジック。オーディオやタイマーには依存しない
public struct BeatSequencer {
    public var beatsPerMeasure: Int
    public var accents: Set<Int>
    public var subdivision: Subdivision

    public private(set) var beat = 0
    public private(set) var step = 0

    public init(beatsPerMeasure: Int, accents: Set<Int>, subdivision: Subdivision = .quarter) {
        self.beatsPerMeasure = beatsPerMeasure
        self.accents = accents
        self.subdivision = subdivision
    }

    /// 小節頭に戻し、再生開始時に鳴らす最初の tick を返す
    public mutating func reset() -> Tick {
        beat = 0
        step = 0
        return Tick(beat: 0, click: accentClick(for: 0), startsMeasure: true)
    }

    public mutating func advance() -> Tick {
        step += 1
        if step < subdivision.rawValue {
            return Tick(beat: beat, click: .subdivision, startsMeasure: false)
        }
        step = 0
        beat = (beat + 1) % beatsPerMeasure
        return Tick(beat: beat, click: accentClick(for: beat), startsMeasure: beat == 0)
    }

    private func accentClick(for beat: Int) -> ClickKind {
        accents.contains(beat) ? .accent : .normal
    }
}
