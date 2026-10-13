/// 1拍をいくつに刻むか
public enum Subdivision: Int, CaseIterable, Codable, Sendable {
    case quarter = 1
    case eighth = 2
    case triplet = 3
    /// 3 連符の真ん中を抜いた跳ねるリズム。選択肢では 3 連符の隣に並べる。
    /// rawValue は保存用の識別子なので、刻みの数は stepsPerBeat を使う
    case swing = 6
    case sixteenth = 4

    /// 1 拍を何個の等しい刻みに分けて進むか
    public var stepsPerBeat: Int {
        self == .swing ? 3 : rawValue
    }

    /// 拍の中の step 番目（0 が拍頭）の刻みを鳴らすか。スイングは 3 連の真ん中を抜く
    public func soundsStep(_ step: Int) -> Bool {
        !(self == .swing && step == 1)
    }
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
    /// 休符にした拍。拍の表示は進むが音は鳴らさない（音の種類ではないので ClickKind とは分けている）
    public var isRest = false
}

/// 拍・細分の進行を管理する純粋なロジック。オーディオやタイマーには依存しない
public struct BeatSequencer {
    public var beatsPerMeasure: Int
    public var accents: Set<Int>
    /// 休符にした拍。「2 拍目と 4 拍目だけ鳴らす」ジャズの練習などに使う
    public var rests: Set<Int> = []
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
        return beatTick(0)
    }

    public mutating func advance() -> Tick {
        step += 1
        if step < subdivision.stepsPerBeat {
            // 休符にした拍は、その拍の中の細分音も鳴らさない
            let isRest = rests.contains(beat) || !subdivision.soundsStep(step)
            return Tick(beat: beat, click: .subdivision, startsMeasure: false, isRest: isRest)
        }
        step = 0
        // 再生中に拍数が減って beat が範囲外になっていたら、小節頭に戻る（2 拍目などへ飛ばさない）
        beat = beat + 1 >= beatsPerMeasure ? 0 : beat + 1
        return beatTick(beat)
    }

    /// 拍頭の tick
    private func beatTick(_ beat: Int) -> Tick {
        Tick(
            beat: beat, click: accents.contains(beat) ? .accent : .normal,
            startsMeasure: beat == 0, isRest: rests.contains(beat)
        )
    }
}
