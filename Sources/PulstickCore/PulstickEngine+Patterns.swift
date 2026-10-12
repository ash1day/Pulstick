import Foundation

// テンポ・拍・アクセント・休符・プリセットの操作（曲は PulstickEngine+Songs.swift）
extension PulstickEngine {
    var currentPattern: BeatPreset {
        BeatPreset(beats: beatsPerMeasure, accents: Array(accentBeats).sorted(), rests: Array(restBeats).sorted())
    }

    /// いまのテンポをスピードトレーナーの起点にし、小節の数え直しを始める
    func restartSession() {
        sessionStartBPM = bpm
        speedTrainerProgress.restart()
    }

    /// 保存データや曲から読んだ拍の位置（アクセント・休符）のうち、いまの拍数の範囲にあるものだけを残す
    func validBeatIndices(_ accents: [Int]) -> Set<Int> {
        Set(accents.filter { (0..<beatsPerMeasure).contains($0) })
    }

    public func applyPreset(at index: Int) {
        guard index < presets.count else { return }
        let preset = presets[index]
        beatsPerMeasure = preset.beats
        accentBeats = preset.accentSet
        restBeats = preset.restSet
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
        if let tapped = tapTempoEstimator.tap(at: now) {
            bpm = tapped
        }
    }

    public func setBeats(_ beats: Int) {
        beatsPerMeasure = beats.clamped(to: Self.beatsRange)
        accentBeats = [0]
        restBeats = []
    }

    public func addBeat() {
        guard beatsPerMeasure < Self.beatsRange.upperBound else { return }
        beatsPerMeasure += 1
        // 追加した拍はデフォルトで弱（accentBeats に追加しない）
    }

    public func removeBeat() {
        guard beatsPerMeasure > Self.beatsRange.lowerBound else { return }
        let last = beatsPerMeasure - 1
        accentBeats.remove(last)
        restBeats.remove(last)
        beatsPerMeasure -= 1
        if beatClock.current >= beatsPerMeasure {
            beatClock.current = 0
        }
    }

    /// 拍をタップしたときの切り替え: 弱 → 強 → 休み → 弱
    public func cycleBeat(_ beat: Int) {
        if restBeats.contains(beat) {
            restBeats.remove(beat)
        } else if accentBeats.contains(beat) {
            accentBeats.remove(beat)
            restBeats.insert(beat)
        } else {
            accentBeats.insert(beat)
        }
    }

    public func toggleAccent(_ beat: Int) {
        if accentBeats.contains(beat) {
            accentBeats.remove(beat)
        } else {
            // 強と休みを同時に持たせない
            restBeats.remove(beat)
            accentBeats.insert(beat)
        }
    }
}
