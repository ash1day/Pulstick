import Testing
@testable import PulstickCore

// MARK: - BeatPreset

@Suite("BeatPreset")
struct BeatPresetTests {
    @Test func accentSetConvertsArrayToSet() {
        let preset = BeatPreset(beats: 6, accents: [0, 3])
        #expect(preset.accentSet == [0, 3])
    }

    @Test func defaultsHasFourPresets() {
        #expect(BeatPreset.defaults.count == 4)
    }

    @Test func defaultPresetsMatchExpected() {
        #expect(BeatPreset.defaults[0] == BeatPreset(beats: 4, accents: [0]))
        #expect(BeatPreset.defaults[1] == BeatPreset(beats: 3, accents: [0]))
        #expect(BeatPreset.defaults[2] == BeatPreset(beats: 6, accents: [0, 3]))
        #expect(BeatPreset.defaults[3] == BeatPreset(beats: 9, accents: [0, 3, 6]))
    }
}

// MARK: - PulstickEngine: 拍数管理

@Suite("PulstickEngine: 拍数管理")
struct BeatManagementTests {
    @Test func addBeatIncrementsCount() {
        let engine = PulstickEngine()
        engine.setBeats(4)
        engine.addBeat()
        #expect(engine.beatsPerMeasure == 5)
    }

    @Test func addBeatDoesNotExceed16() {
        let engine = PulstickEngine()
        engine.setBeats(16)
        engine.addBeat()
        #expect(engine.beatsPerMeasure == 16)
    }

    @Test func removeBeatDecrementsCount() {
        let engine = PulstickEngine()
        engine.setBeats(4)
        engine.removeBeat()
        #expect(engine.beatsPerMeasure == 3)
    }

    @Test func removeBeatDoesNotGoBelowOne() {
        let engine = PulstickEngine()
        engine.setBeats(1)
        engine.removeBeat()
        #expect(engine.beatsPerMeasure == 1)
    }

    @Test func removeBeatCleansUpAccent() {
        let engine = PulstickEngine()
        engine.setBeats(4)
        engine.toggleAccent(3)  // 4拍目を強に
        engine.removeBeat()     // 4拍目を削除
        #expect(!engine.accentBeats.contains(3))
    }
}

// MARK: - PulstickEngine: アクセント管理

@Suite("PulstickEngine: アクセント管理")
struct AccentManagementTests {
    @Test func toggleAccentAddsWhenAbsent() {
        let engine = PulstickEngine()
        engine.setBeats(4)
        engine.toggleAccent(1)
        #expect(engine.accentBeats.contains(1))
    }

    @Test func toggleAccentRemovesWhenPresent() {
        let engine = PulstickEngine()
        engine.setBeats(4)         // accentBeats = [0]
        engine.toggleAccent(0)     // 0を消す
        #expect(!engine.accentBeats.contains(0))
    }

    @Test func setBeatsResetsAccentToFirstBeatOnly() {
        let engine = PulstickEngine()
        engine.toggleAccent(1)
        engine.toggleAccent(2)
        engine.setBeats(4)
        #expect(engine.accentBeats == [0])
    }
}

// MARK: - PulstickEngine: BPM

@Suite("PulstickEngine: BPM")
struct BPMTests {
    @Test func bpmClampedAtMaximum() {
        let engine = PulstickEngine()
        engine.bpm = 999
        #expect(engine.bpm == 240)
    }

    @Test func bpmClampedAtMinimum() {
        let engine = PulstickEngine()
        engine.bpm = 1
        #expect(engine.bpm == 40)
    }

    @Test func incrementBPMAddsOne() {
        let engine = PulstickEngine()
        engine.bpm = 120
        engine.incrementBPM()
        #expect(engine.bpm == 121)
    }

    @Test func decrementBPMSubtractsOne() {
        let engine = PulstickEngine()
        engine.bpm = 120
        engine.decrementBPM()
        #expect(engine.bpm == 119)
    }

    @Test func incrementDoesNotExceedMax() {
        let engine = PulstickEngine()
        engine.bpm = 240
        engine.incrementBPM()
        #expect(engine.bpm == 240)
    }

    @Test func decrementDoesNotGoBelowMin() {
        let engine = PulstickEngine()
        engine.bpm = 40
        engine.decrementBPM()
        #expect(engine.bpm == 40)
    }
}

// MARK: - PulstickEngine: プリセット管理

@Suite("PulstickEngine: プリセット管理")
struct PresetManagementTests {
    @Test func engineLoadsDefaultPresets() {
        let engine = PulstickEngine()
        #expect(engine.presets.count == BeatPreset.defaults.count)
    }

    @Test func applyPresetSetsBeatsAndAccents() {
        let engine = PulstickEngine()
        engine.applyPreset(at: 2)  // 6/8: beats=6, accents=[0,3]
        #expect(engine.beatsPerMeasure == 6)
        #expect(engine.accentBeats == [0, 3])
    }

    @Test func applyPresetOutOfBoundsIsIgnored() {
        let engine = PulstickEngine()
        engine.setBeats(4)
        engine.applyPreset(at: 99)  // 範囲外
        #expect(engine.beatsPerMeasure == 4)
    }

    @Test func saveCurrentAsPresetStoresPattern() {
        let engine = PulstickEngine()
        // 8/8 裏拍強パターンをセット
        engine.setBeats(8)
        engine.accentBeats = [1, 3, 5, 7]
        engine.saveCurrentAsPreset(at: 0)

        #expect(engine.presets[0].beats == 8)
        #expect(engine.presets[0].accentSet == [1, 3, 5, 7])
    }

    @Test func saveCurrentAsPresetOutOfBoundsIsIgnored() {
        let engine = PulstickEngine()
        let before = engine.presets
        engine.saveCurrentAsPreset(at: 99)
        #expect(engine.presets == before)
    }

    @Test func resetPresetRestoresDefault() {
        let engine = PulstickEngine()
        engine.setBeats(8)
        engine.accentBeats = [1, 3, 5, 7]
        engine.saveCurrentAsPreset(at: 0)  // 上書き
        engine.resetPreset(at: 0)          // リセット
        #expect(engine.presets[0] == BeatPreset.defaults[0])
    }
}
