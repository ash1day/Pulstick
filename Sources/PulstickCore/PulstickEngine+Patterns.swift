import Foundation

// テンポ・拍・アクセント・休符・プリセットの操作（曲は PulstickEngine+Songs.swift）
extension PulstickEngine {
    /// 拍のパターンを反映する。プリセットと曲で共通。
    /// 保存データが壊れていても拍数 0（ゼロ除算）や範囲外の拍にならないよう検証する。
    /// 拍数を先に決めてから、その範囲でアクセントと休符を絞り込む
    func applyPattern(_ pattern: BeatPreset) {
        beatsPerMeasure = pattern.beats.clamped(to: Self.beatsRange)
        accentBeats = validBeatIndices(pattern.accents)
        restBeats = validBeatIndices(pattern.rests)
    }

    /// いまの拍のパターンがこのパターンと同じか（プリセットの選択表示や曲の判定に使う）
    public func matchesCurrentPattern(_ pattern: BeatPreset) -> Bool {
        pattern.beats == beatsPerMeasure && pattern.accentSet == accentBeats && pattern.restSet == restBeats
    }

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
    public func cycleBeat(_ beat: Int) {
        // 強 → 休み のように 2 つの集合を変えるので、途中の状態を反映しないよう 1 回の変更として扱う
        batchPatternChange {
            if restBeats.contains(beat) {
                restBeats.remove(beat)
            } else if accentBeats.contains(beat) {
                accentBeats.remove(beat)
                restBeats.insert(beat)
            } else {
                accentBeats.insert(beat)
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
