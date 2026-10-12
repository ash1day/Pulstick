import Foundation

// テンポ・拍・アクセント・休符・プリセットの操作（曲は PulstickEngine+Songs.swift、スピードトレーナーは PulstickEngine+Trainer.swift）
extension PulstickEngine {
    /// 拍のパターンを反映する。プリセットと曲で共通。保存データが壊れていても使えるよう検証してから入れる
    func applyPattern(_ pattern: BeatPreset) {
        let valid = pattern.sanitized
        beatsPerMeasure = valid.beats
        accentBeats = valid.accentSet
        restBeats = valid.restSet
    }

    /// いまの拍のパターンがこのパターンと同じか（プリセットの選択表示や曲の判定に使う）
    public func matchesCurrentPattern(_ pattern: BeatPreset) -> Bool {
        pattern.beats == beatsPerMeasure && pattern.accentSet == accentBeats && pattern.restSet == restBeats
    }

    var currentPattern: BeatPreset {
        BeatPreset(beats: beatsPerMeasure, accents: Array(accentBeats).sorted(), rests: Array(restBeats).sorted())
    }

    public func applyPreset(at index: Int) {
        guard index < presets.count else { return }
        let preset = presets[index]
        batchPatternChange {
            applyPattern(preset)
        }
    }

    public func saveCurrentAsPreset(at index: Int) {
        guard index < presets.count else { return }
        presets[index] = currentPattern
        persistPresets()
    }

    public func resetPreset(at index: Int) {
        guard index < BeatPreset.defaults.count else { return }
        presets[index] = BeatPreset.defaults[index]
        persistPresets()
    }

    /// 範囲外は bpm の didSet で丸められる
    public func incrementBPM(by step: Double = 1) {
        bpm += step
    }

    public func decrementBPM(by step: Double = 1) {
        bpm -= step
    }

    public func tapTempo(at now: Date = Date()) {
        lastTapAt = now
        if let tapped = tapTempoEstimator.tap(at: now) {
            bpm = tapped
        }
    }

    public func setBeats(_ beats: Int) {
        batchPatternChange {
            beatsPerMeasure = beats.clamped(to: Self.beatsRange)
            accentBeats = [0]
            restBeats = []
        }
    }

    public func addBeat() {
        guard beatsPerMeasure < Self.beatsRange.upperBound else { return }
        beatsPerMeasure += 1
        // 追加した拍はデフォルトで弱（accentBeats に追加しない）
    }

    public func removeBeat() {
        guard beatsPerMeasure > Self.beatsRange.lowerBound else { return }
        batchPatternChange {
            let last = beatsPerMeasure - 1
            accentBeats.remove(last)
            restBeats.remove(last)
            beatsPerMeasure -= 1
            if beatClock.current >= beatsPerMeasure {
                beatClock.current = 0
            }
        }
    }

    /// 拍をタップしたときの切り替え: 弱 → 強 → 休み → 弱
    /// 拍の状態。強と休みを同時に持つことはないので、休みを先に見る
    public func beatState(_ beat: Int) -> BeatState {
        if restBeats.contains(beat) { return .rest }
        return accentBeats.contains(beat) ? .accent : .normal
    }

    /// クリックで 弱 → 強 → 休み → 弱 と巡回する
    public func cycleBeat(_ beat: Int) {
        setBeat(beat, to: beatState(beat).next)
    }

    /// 右クリックから状態を直接選ぶ。cycleBeat と違い、休みにするとき強拍を経由しない
    public func setBeat(_ beat: Int, to state: BeatState) {
        // 強 → 休み のように 2 つの集合を変えるので、途中の状態を反映しないよう 1 回の変更として扱う
        batchPatternChange {
            accentBeats.remove(beat)
            restBeats.remove(beat)
            switch state {
            case .normal: break
            case .accent: accentBeats.insert(beat)
            case .rest: restBeats.insert(beat)
            }
        }
    }

    public func toggleAccent(_ beat: Int) {
        batchPatternChange {
            if accentBeats.contains(beat) {
                accentBeats.remove(beat)
            } else {
                // 強と休みを同時に持たせない
                restBeats.remove(beat)
                accentBeats.insert(beat)
            }
        }
    }
}

/// 1 つの拍の状態。拍の表示で切り替える 3 つ
public enum BeatState: Sendable {
    case normal
    case accent
    case rest

    /// クリックで巡回するときの次の状態
    var next: BeatState {
        switch self {
        case .normal: .accent
        case .accent: .rest
        case .rest: .normal
        }
    }
}
