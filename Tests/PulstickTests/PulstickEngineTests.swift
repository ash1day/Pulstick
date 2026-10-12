import Foundation
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
        let engine = makeEngine()
        engine.setBeats(4)
        engine.addBeat()
        #expect(engine.beatsPerMeasure == 5)
    }

    @Test func addBeatDoesNotExceed16() {
        let engine = makeEngine()
        engine.setBeats(16)
        engine.addBeat()
        #expect(engine.beatsPerMeasure == 16)
    }

    @Test func removeBeatDecrementsCount() {
        let engine = makeEngine()
        engine.setBeats(4)
        engine.removeBeat()
        #expect(engine.beatsPerMeasure == 3)
    }

    @Test func removeBeatDoesNotGoBelowOne() {
        let engine = makeEngine()
        engine.setBeats(1)
        engine.removeBeat()
        #expect(engine.beatsPerMeasure == 1)
    }

    @Test func removeBeatCleansUpAccent() {
        let engine = makeEngine()
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
        let engine = makeEngine()
        engine.setBeats(4)
        engine.toggleAccent(1)
        #expect(engine.accentBeats.contains(1))
    }

    @Test func toggleAccentRemovesWhenPresent() {
        let engine = makeEngine()
        engine.setBeats(4)         // accentBeats = [0]
        engine.toggleAccent(0)     // 0を消す
        #expect(!engine.accentBeats.contains(0))
    }

    @Test func setBeatsResetsAccentToFirstBeatOnly() {
        let engine = makeEngine()
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
        let engine = makeEngine()
        engine.bpm = 999
        #expect(engine.bpm == 240)
    }

    @Test func bpmClampedAtMinimum() {
        let engine = makeEngine()
        engine.bpm = 1
        #expect(engine.bpm == 40)
    }

    @Test func incrementBPMAddsOne() {
        let engine = makeEngine()
        engine.bpm = 120
        engine.incrementBPM()
        #expect(engine.bpm == 121)
    }

    @Test func decrementBPMSubtractsOne() {
        let engine = makeEngine()
        engine.bpm = 120
        engine.decrementBPM()
        #expect(engine.bpm == 119)
    }

    @Test func incrementDoesNotExceedMax() {
        let engine = makeEngine()
        engine.bpm = 240
        engine.incrementBPM()
        #expect(engine.bpm == 240)
    }

    @Test func decrementDoesNotGoBelowMin() {
        let engine = makeEngine()
        engine.bpm = 40
        engine.decrementBPM()
        #expect(engine.bpm == 40)
    }
}

// MARK: - PulstickEngine: プリセット管理

@Suite("PulstickEngine: プリセット管理")
struct PresetManagementTests {
    @Test func engineLoadsDefaultPresets() {
        let engine = makeEngine()
        #expect(engine.presets.count == BeatPreset.defaults.count)
    }

    @Test func applyPresetSetsBeatsAndAccents() {
        let engine = makeEngine()
        engine.applyPreset(at: 2)  // 6/8: beats=6, accents=[0,3]
        #expect(engine.beatsPerMeasure == 6)
        #expect(engine.accentBeats == [0, 3])
    }

    @Test func applyPresetOutOfBoundsIsIgnored() {
        let engine = makeEngine()
        engine.setBeats(4)
        engine.applyPreset(at: 99)  // 範囲外
        #expect(engine.beatsPerMeasure == 4)
    }

    @Test func saveCurrentAsPresetStoresPattern() {
        let engine = makeEngine()
        // 8/8 裏拍強パターンをセット
        engine.setBeats(8)
        engine.accentBeats = [1, 3, 5, 7]
        engine.saveCurrentAsPreset(at: 0)

        #expect(engine.presets[0].beats == 8)
        #expect(engine.presets[0].accentSet == [1, 3, 5, 7])
    }

    @Test func saveCurrentAsPresetOutOfBoundsIsIgnored() {
        let engine = makeEngine()
        let before = engine.presets
        engine.saveCurrentAsPreset(at: 99)
        #expect(engine.presets == before)
    }

    @Test func resetPresetRestoresDefault() {
        let engine = makeEngine()
        engine.setBeats(8)
        engine.accentBeats = [1, 3, 5, 7]
        engine.saveCurrentAsPreset(at: 0)  // 上書き
        engine.resetPreset(at: 0)          // リセット
        #expect(engine.presets[0] == BeatPreset.defaults[0])
    }
}

// MARK: - PulstickEngine: 設定の永続化

/// テストごとに独立したメモリ上のストアを使い、実アプリの設定やディスクを汚さない
func makeEngine() -> PulstickEngine {
    PulstickEngine(defaults: InMemorySettingsStore())
}

@Suite("PulstickEngine: 設定の永続化")
struct PersistenceTests {
    @Test func bpmIsRestoredOnNextLaunch() {
        let defaults = InMemorySettingsStore()
        let first = PulstickEngine(defaults: defaults)
        first.bpm = 96
        let second = PulstickEngine(defaults: defaults)
        #expect(second.bpm == 96)
    }

    @Test func beatPatternIsRestoredOnNextLaunch() {
        let defaults = InMemorySettingsStore()
        let first = PulstickEngine(defaults: defaults)
        first.setBeats(5)
        first.toggleAccent(2)
        let second = PulstickEngine(defaults: defaults)
        #expect(second.beatsPerMeasure == 5)
        #expect(second.accentBeats == [0, 2])
    }

    @Test func volumesAreRestoredOnNextLaunch() {
        let defaults = InMemorySettingsStore()
        let first = PulstickEngine(defaults: defaults)
        first.accentVolume = 0.4
        first.normalVolume = 0.2
        let second = PulstickEngine(defaults: defaults)
        #expect(second.accentVolume == 0.4)
        #expect(second.normalVolume == 0.2)
    }

    @Test func subdivisionIsRestoredOnNextLaunch() {
        let defaults = InMemorySettingsStore()
        let first = PulstickEngine(defaults: defaults)
        first.subdivision = .triplet
        let second = PulstickEngine(defaults: defaults)
        #expect(second.subdivision == .triplet)
    }

    @Test func presetsAreStoredInInjectedDefaults() {
        let defaults = InMemorySettingsStore()
        let first = PulstickEngine(defaults: defaults)
        first.setBeats(7)
        first.saveCurrentAsPreset(at: 1)
        let second = PulstickEngine(defaults: defaults)
        #expect(second.presets[1].beats == 7)
        // 別の defaults を使うエンジンには漏れない
        let other = PulstickEngine(defaults: InMemorySettingsStore())
        #expect(other.presets[1] == BeatPreset.defaults[1])
    }
}

// MARK: - BeatSequencer

@Suite("BeatSequencer")
struct BeatSequencerTests {
    @Test func quarterNotesAdvanceOneBeatPerTick() {
        var seq = BeatSequencer(beatsPerMeasure: 4, accents: [0])
        #expect(seq.advance() == Tick(beat: 1, click: .normal, startsMeasure: false))
        #expect(seq.advance() == Tick(beat: 2, click: .normal, startsMeasure: false))
    }
}

@Suite("BeatSequencer: アクセントと小節")
struct BeatSequencerMeasureTests {
    @Test func wrapsToAccentedDownbeatAndReportsNewMeasure() {
        var seq = BeatSequencer(beatsPerMeasure: 3, accents: [0])
        _ = seq.advance()
        _ = seq.advance()
        #expect(seq.advance() == Tick(beat: 0, click: .accent, startsMeasure: true))
    }

    @Test func accentedOffBeatIsAccent() {
        var seq = BeatSequencer(beatsPerMeasure: 4, accents: [0, 2])
        _ = seq.advance()
        #expect(seq.advance().click == .accent)
    }
}

@Suite("BeatSequencer: 細分化")
struct BeatSequencerSubdivisionTests {
    @Test func eighthNotesInsertSubdivisionClickBetweenBeats() {
        var seq = BeatSequencer(beatsPerMeasure: 2, accents: [0], subdivision: .eighth)
        #expect(seq.advance() == Tick(beat: 0, click: .subdivision, startsMeasure: false))
        #expect(seq.advance() == Tick(beat: 1, click: .normal, startsMeasure: false))
        #expect(seq.advance() == Tick(beat: 1, click: .subdivision, startsMeasure: false))
        #expect(seq.advance() == Tick(beat: 0, click: .accent, startsMeasure: true))
    }

    @Test func tripletsHaveTwoSubdivisionClicksPerBeat() {
        var seq = BeatSequencer(beatsPerMeasure: 4, accents: [0], subdivision: .triplet)
        let clicks = (0..<3).map { _ in seq.advance().click }
        #expect(clicks == [.subdivision, .subdivision, .normal])
    }
}

@Suite("BeatSequencer: リセット")
struct BeatSequencerResetTests {
    @Test func resetReturnsDownbeatTick() {
        var seq = BeatSequencer(beatsPerMeasure: 4, accents: [0], subdivision: .eighth)
        _ = seq.advance()
        _ = seq.advance()
        #expect(seq.reset() == Tick(beat: 0, click: .accent, startsMeasure: true))
        #expect(seq.advance() == Tick(beat: 0, click: .subdivision, startsMeasure: false))
    }

    @Test func resetWithUnaccentedDownbeatIsNormal() {
        var seq = BeatSequencer(beatsPerMeasure: 4, accents: [1])
        #expect(seq.reset().click == .normal)
    }
}
