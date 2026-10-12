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

// MARK: - PulstickEngine: 休符

@Suite("PulstickEngine: 休符")
struct RestBeatTests {
    @Test func tappingABeatCyclesNormalAccentRest() {
        let engine = makeEngine()
        engine.setBeats(4)  // 1 拍目だけアクセント
        engine.cycleBeat(1)
        #expect(engine.accentBeats.contains(1))
        engine.cycleBeat(1)
        #expect(!engine.accentBeats.contains(1))
        #expect(engine.restBeats.contains(1))
        engine.cycleBeat(1)
        #expect(!engine.restBeats.contains(1))
    }

    @Test func accentingARestBeatClearsTheRest() {
        let engine = makeEngine()
        engine.setBeats(4)
        engine.cycleBeat(1); engine.cycleBeat(1)  // 2 拍目を休みに
        engine.toggleAccent(1)
        #expect(engine.accentBeats.contains(1))
        #expect(!engine.restBeats.contains(1))
    }

    @Test func restBeatsSurviveRelaunchAndPresets() {
        let defaults = InMemorySettingsStore()
        let first = PulstickEngine(defaults: defaults, output: SilentClickOutput())
        first.setBeats(4)
        first.cycleBeat(0)  // 1 拍目: 強 → 休み
        first.cycleBeat(2); first.cycleBeat(2)  // 3 拍目: 弱 → 強 → 休み
        first.saveCurrentAsPreset(at: 3)
        let second = PulstickEngine(defaults: defaults, output: SilentClickOutput())
        #expect(second.restBeats == [0, 2])
        second.setBeats(3)
        #expect(second.restBeats.isEmpty)
        second.applyPreset(at: 3)
        #expect(second.restBeats == [0, 2])
    }

    @Test func presetsSavedBeforeRestsExistedStillLoad() {
        let defaults = InMemorySettingsStore()
        let old = #"[{"beats":5,"accents":[0]},{"beats":3,"accents":[0]},{"beats":6,"accents":[0,3]},{"beats":9,"accents":[0,3,6]}]"#
        defaults.set(old.data(using: .utf8), forKey: "pulstick.presets")
        let engine = PulstickEngine(defaults: defaults, output: SilentClickOutput())
        #expect(engine.presets[0].beats == 5)
    }
}

// MARK: - PulstickEngine: BPM

@Suite("PulstickEngine: BPM")
struct BPMTests {
    @Test func bpmClampedAtMaximum() {
        let engine = makeEngine()
        engine.bpm = 999
        #expect(engine.bpm == 300)
    }

    @Test func bpmClampedAtMinimum() {
        let engine = makeEngine()
        engine.bpm = 1
        #expect(engine.bpm == 30)
    }

    @Test(arguments: [Double.nan, .infinity, -.infinity])
    func nonFiniteTempoIsRejected(value: Double) {
        let engine = makeEngine()
        engine.bpm = 100
        engine.bpm = value
        #expect(engine.bpm == 100)
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
        engine.bpm = 300
        engine.incrementBPM()
        #expect(engine.bpm == 300)
    }

    @Test func decrementDoesNotGoBelowMin() {
        let engine = makeEngine()
        engine.bpm = 30
        engine.decrementBPM()
        #expect(engine.bpm == 30)
    }
}

// MARK: - PulstickEngine: タップテンポ

@Suite("PulstickEngine: タップテンポ")
struct TapTempoTests {
    @Test func tappedTempoIsRoundedToWholeBPM() {
        let engine = makeEngine()
        let t0 = Date()
        engine.tapTempo(at: t0)
        engine.tapTempo(at: t0.addingTimeInterval(0.502))  // 119.52 BPM 相当
        #expect(engine.bpm == 120)
    }

    @Test func pauseLongerThanTimeoutStartsOver() {
        let engine = makeEngine()
        engine.bpm = 100
        let t0 = Date()
        engine.tapTempo(at: t0)
        engine.tapTempo(at: t0.addingTimeInterval(3))  // 2秒以上空いたので最初のタップ扱い
        #expect(engine.bpm == 100)
    }
}

// MARK: - PulstickEngine: 曲ごとの設定

@Suite("PulstickEngine: 曲")
struct SongTests {
    @Test func savingCurrentSettingsAsSongKeepsTempoAndPattern() throws {
        let engine = makeEngine()
        engine.bpm = 132
        engine.setBeats(3)
        engine.subdivision = .triplet
        engine.saveCurrentAsSong(named: "  Waltz  ")
        let song = try #require(engine.songs.first)
        #expect(song.name == "Waltz")
        #expect(song.bpm == 132)
        #expect(song.pattern == BeatPreset(beats: 3, accents: [0]))
        #expect(song.subdivision == .triplet)
    }

    @Test func blankNameIsIgnored() {
        let engine = makeEngine()
        engine.saveCurrentAsSong(named: "   ")
        #expect(engine.songs.isEmpty)
    }

    @Test func applyingSongRestoresItsSettings() throws {
        let engine = makeEngine()
        engine.bpm = 96
        engine.setBeats(6)
        engine.accentBeats = [0, 3]
        engine.saveCurrentAsSong(named: "6/8 ballad")
        engine.bpm = 150
        engine.setBeats(4)
        engine.applySong(try #require(engine.songs.first))
        #expect(engine.bpm == 96)
        #expect(engine.beatsPerMeasure == 6)
        #expect(engine.accentBeats == [0, 3])
    }

    @Test func songsKeepSetlistOrderAndCanBeDeleted() throws {
        let engine = makeEngine()
        engine.saveCurrentAsSong(named: "Opener")
        engine.saveCurrentAsSong(named: "Ballad")
        #expect(engine.songs.map(\.name) == ["Opener", "Ballad"])
        engine.deleteSong(try #require(engine.songs.first))
        #expect(engine.songs.map(\.name) == ["Ballad"])
    }

    @Test func songsCanBeMovedWithinTheSetlist() throws {
        let engine = makeEngine()
        for name in ["A", "B", "C"] { engine.saveCurrentAsSong(named: name) }
        engine.moveSong(try #require(engine.songs.last), by: -1)
        #expect(engine.songs.map(\.name) == ["A", "C", "B"])
        engine.moveSong(try #require(engine.songs.first), by: -1)  // 先頭より前には動かない
        #expect(engine.songs.map(\.name) == ["A", "C", "B"])
    }

    @Test func nextAndPreviousSongStepThroughTheSetlist() {
        let engine = makeEngine()
        for (name, bpm) in [("A", 100.0), ("B", 120), ("C", 140)] {
            engine.bpm = bpm
            engine.saveCurrentAsSong(named: name)
        }
        engine.bpm = 90  // どの曲とも一致しない状態からは先頭へ
        engine.applyAdjacentSong(1)
        #expect(engine.bpm == 100)
        engine.applyAdjacentSong(1)
        #expect(engine.bpm == 120)
        engine.applyAdjacentSong(-1)
        #expect(engine.bpm == 100)
        engine.applyAdjacentSong(-1)  // 先頭からさらに前へは行かない
        #expect(engine.bpm == 100)
    }

    @Test func savingWithExistingNameUpdatesThatSong() {
        let engine = makeEngine()
        engine.bpm = 100
        engine.saveCurrentAsSong(named: "Etude")
        engine.bpm = 110
        engine.saveCurrentAsSong(named: "etude")
        #expect(engine.songs.count == 1)
        #expect(engine.songs.first?.bpm == 110)
    }

    @Test func applyingSongWhilePlayingMakesItTheNewStartingTempo() throws {
        let engine = makeEngine()
        engine.bpm = 150
        engine.saveCurrentAsSong(named: "Fast")
        engine.bpm = 100
        engine.start()
        engine.applySong(try #require(engine.songs.first))
        #expect(engine.sessionStartBPM == 150)
        engine.stop()
    }

    @Test func songMatchesOnlyWhileSettingsAreUnchanged() throws {
        let engine = makeEngine()
        engine.bpm = 90
        engine.saveCurrentAsSong(named: "Groove")
        let song = try #require(engine.songs.first)
        #expect(engine.matchesCurrentSettings(song))
        engine.subdivision = .eighth
        #expect(!engine.matchesCurrentSettings(song))
    }

    @Test func resavingASongKeepsItsPracticeTime() {
        let engine = makeEngine()
        engine.saveCurrentAsSong(named: "Etude")
        engine.beginSongPractice(engine.songs.first?.id)
        engine.activeSongSince = Date().addingTimeInterval(-600)
        engine.creditSongPractice()
        engine.bpm = 132
        engine.saveCurrentAsSong(named: "Etude")  // テンポを変えて上書き
        #expect((engine.songs.first?.practiceSeconds ?? 0) >= 600)
    }

    @Test func songsSavedBeforePracticeTimeExistedStillLoad() {
        let defaults = InMemorySettingsStore()
        let old = #"[{"id":"7C9E6B1E-1D1F-4B7A-9C1E-2A3B4C5D6E7F","name":"Old","bpm":90,"pattern":{"beats":3,"accents":[0]},"subdivision":1}]"#
        defaults.set(old.data(using: .utf8), forKey: "pulstick.songs")
        let engine = PulstickEngine(defaults: defaults, output: SilentClickOutput())
        #expect(engine.songs.map(\.name) == ["Old"])
    }

    @Test func songsAreRestoredOnNextLaunch() {
        let defaults = InMemorySettingsStore()
        let first = PulstickEngine(defaults: defaults, output: SilentClickOutput())
        first.saveCurrentAsSong(named: "Setlist #1")
        let second = PulstickEngine(defaults: defaults, output: SilentClickOutput())
        #expect(second.songs == first.songs)
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
    PulstickEngine(defaults: InMemorySettingsStore(), output: SilentClickOutput())
}

@Suite("PulstickEngine: 設定の永続化")
struct PersistenceTests {
    @Test func bpmIsRestoredOnNextLaunch() {
        let defaults = InMemorySettingsStore()
        let first = PulstickEngine(defaults: defaults, output: SilentClickOutput())
        first.bpm = 96
        let second = PulstickEngine(defaults: defaults, output: SilentClickOutput())
        #expect(second.bpm == 96)
    }

    @Test func beatPatternIsRestoredOnNextLaunch() {
        let defaults = InMemorySettingsStore()
        let first = PulstickEngine(defaults: defaults, output: SilentClickOutput())
        first.setBeats(5)
        first.toggleAccent(2)
        let second = PulstickEngine(defaults: defaults, output: SilentClickOutput())
        #expect(second.beatsPerMeasure == 5)
        #expect(second.accentBeats == [0, 2])
    }

    @Test func savedSettingsMissingNewerFieldsKeepTheRest() {
        // 将来フィールドを足しても、それ以前に保存された値が既定値に戻らないこと
        let defaults = InMemorySettingsStore()
        defaults.set(#"{"playBars":5}"#.data(using: .utf8), forKey: "pulstick.gapTrainer")
        let engine = PulstickEngine(defaults: defaults, output: SilentClickOutput())
        #expect(engine.gapTrainer.playBars == 5)
        #expect(engine.gapTrainer.muteBars == GapTrainer().muteBars)
    }

    @Test func invalidSavedAccentsAreDropped() {
        let defaults = InMemorySettingsStore()
        defaults.set(4, forKey: "pulstick.beats")
        defaults.set([-1, 0, 2, 9], forKey: "pulstick.accents")
        let engine = PulstickEngine(defaults: defaults, output: SilentClickOutput())
        #expect(engine.accentBeats == [0, 2])
    }

    @Test func volumesAreRestoredOnNextLaunch() {
        let defaults = InMemorySettingsStore()
        let first = PulstickEngine(defaults: defaults, output: SilentClickOutput())
        first.accentVolume = 0.4
        first.normalVolume = 0.2
        let second = PulstickEngine(defaults: defaults, output: SilentClickOutput())
        #expect(second.accentVolume == 0.4)
        #expect(second.normalVolume == 0.2)
    }

    @Test func subdivisionIsRestoredOnNextLaunch() {
        let defaults = InMemorySettingsStore()
        let first = PulstickEngine(defaults: defaults, output: SilentClickOutput())
        first.subdivision = .triplet
        let second = PulstickEngine(defaults: defaults, output: SilentClickOutput())
        #expect(second.subdivision == .triplet)
    }

    @Test func clickSoundIsRestoredAndAppliedToOutput() {
        let defaults = InMemorySettingsStore()
        let first = PulstickEngine(defaults: defaults, output: SilentClickOutput())
        first.clickSound = .wood
        let output = SilentClickOutput()
        let second = PulstickEngine(defaults: defaults, output: output)
        #expect(second.clickSound == .wood)
        #expect(output.sound == .wood)
    }

    @Test func presetsAreStoredInInjectedDefaults() {
        let defaults = InMemorySettingsStore()
        let first = PulstickEngine(defaults: defaults, output: SilentClickOutput())
        first.setBeats(7)
        first.saveCurrentAsPreset(at: 1)
        let second = PulstickEngine(defaults: defaults, output: SilentClickOutput())
        #expect(second.presets[1].beats == 7)
        // 別の defaults を使うエンジンには漏れない
        let other = PulstickEngine(defaults: InMemorySettingsStore(), output: SilentClickOutput())
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

@Suite("BeatSequencer: 休符")
struct BeatSequencerRestTests {
    @Test func restBeatsAreSilentButStillAdvance() {
        // 2 拍目と 4 拍目だけ鳴らす（1・3 拍目を休符に）
        var seq = BeatSequencer(beatsPerMeasure: 4, accents: [])
        seq.rests = [0, 2]
        #expect(seq.reset().isRest)
        #expect(seq.advance() == Tick(beat: 1, click: .normal, startsMeasure: false))
        #expect(seq.advance() == Tick(beat: 2, click: .normal, startsMeasure: false, isRest: true))
        #expect(seq.advance() == Tick(beat: 3, click: .normal, startsMeasure: false))
    }

    @Test func subdivisionsInsideARestBeatAreSilentToo() {
        var seq = BeatSequencer(beatsPerMeasure: 2, accents: [], subdivision: .eighth)
        seq.rests = [0]
        _ = seq.reset()
        #expect(seq.advance().isRest)   // 1 拍目のウラ
        #expect(!seq.advance().isRest)  // 2 拍目
        #expect(!seq.advance().isRest)  // 2 拍目のウラ
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

// MARK: - SpeedTrainer

@Suite("SpeedTrainer")
struct SpeedTrainerTests {
    @Test func raisesTempoAfterConfiguredMeasures() {
        let settings = SpeedTrainer(measuresPerStep: 2, bpmIncrement: 5, targetBPM: 200)
        var progress = SpeedTrainerProgress()
        #expect(progress.measureCompleted(settings, currentBPM: 100) == nil)
        #expect(progress.measureCompleted(settings, currentBPM: 100) == 105)
    }

    @Test func stopsAtTargetTempo() {
        let settings = SpeedTrainer(measuresPerStep: 1, bpmIncrement: 5, targetBPM: 103)
        var progress = SpeedTrainerProgress()
        #expect(progress.measureCompleted(settings, currentBPM: 100) == 103)
        #expect(progress.measureCompleted(settings, currentBPM: 103) == nil)
    }

    @Test func countsAgainFromZeroAfterRaising() {
        let settings = SpeedTrainer(measuresPerStep: 2, bpmIncrement: 1, targetBPM: 200)
        var progress = SpeedTrainerProgress()
        _ = progress.measureCompleted(settings, currentBPM: 100)
        _ = progress.measureCompleted(settings, currentBPM: 100)  // 101 へ
        #expect(progress.measureCompleted(settings, currentBPM: 101) == nil)
        #expect(progress.measureCompleted(settings, currentBPM: 101) == 102)
    }

    @Test func loopingReturnsToStartTempoAfterHoldingTheTarget() {
        let settings = SpeedTrainer(measuresPerStep: 2, bpmIncrement: 10, targetBPM: 110, loops: true)
        var progress = SpeedTrainerProgress()
        #expect(progress.measureCompleted(settings, currentBPM: 100, startBPM: 100) == nil)
        #expect(progress.measureCompleted(settings, currentBPM: 100, startBPM: 100) == 110)
        // 目標テンポでも同じ小節数を弾いたら、開始テンポに戻る
        #expect(progress.measureCompleted(settings, currentBPM: 110, startBPM: 100) == nil)
        #expect(progress.measureCompleted(settings, currentBPM: 110, startBPM: 100) == 100)
    }

    @Test func settingsSavedBeforeLoopingExistedStillLoad() {
        let defaults = InMemorySettingsStore()
        defaults.set(#"{"measuresPerStep":8,"bpmIncrement":3,"targetBPM":180}"#.data(using: .utf8), forKey: "pulstick.speedTrainer")
        let engine = PulstickEngine(defaults: defaults, output: SilentClickOutput())
        #expect(engine.speedTrainer == SpeedTrainer(measuresPerStep: 8, bpmIncrement: 3, targetBPM: 180, loops: false))
    }

    @Test func restartResetsMeasureCount() {
        let settings = SpeedTrainer(measuresPerStep: 2, bpmIncrement: 1, targetBPM: 200)
        var progress = SpeedTrainerProgress()
        _ = progress.measureCompleted(settings, currentBPM: 100)
        progress.restart()
        #expect(progress.measureCompleted(settings, currentBPM: 100) == nil)
    }
}

@Suite("PulstickEngine: スピードトレーナー")
struct EngineSpeedTrainerTests {
    @Test func raisesBPMWhenEnabled() {
        let engine = makeEngine()
        engine.bpm = 100
        engine.speedTrainer = SpeedTrainer(measuresPerStep: 1, bpmIncrement: 5, targetBPM: 200)
        engine.speedTrainerEnabled = true
        engine.handleMeasureCompleted()
        #expect(engine.bpm == 105)
    }

    @Test func keepsBPMWhenDisabled() {
        let engine = makeEngine()
        engine.bpm = 100
        engine.speedTrainer = SpeedTrainer(measuresPerStep: 1, bpmIncrement: 5, targetBPM: 200)
        engine.handleMeasureCompleted()
        #expect(engine.bpm == 100)
    }

    @Test func settingsAreRestoredOnNextLaunch() {
        let defaults = InMemorySettingsStore()
        let first = PulstickEngine(defaults: defaults, output: SilentClickOutput())
        first.speedTrainer = SpeedTrainer(measuresPerStep: 8, bpmIncrement: 3, targetBPM: 180)
        first.speedTrainerEnabled = true
        let second = PulstickEngine(defaults: defaults, output: SilentClickOutput())
        #expect(second.speedTrainer == SpeedTrainer(measuresPerStep: 8, bpmIncrement: 3, targetBPM: 180))
        #expect(second.speedTrainerEnabled)
    }

    @Test func gapTrainerSettingsAreRestoredOnNextLaunch() {
        let defaults = InMemorySettingsStore()
        let first = PulstickEngine(defaults: defaults, output: SilentClickOutput())
        first.gapTrainer = GapTrainer(playBars: 3, muteBars: 1)
        first.gapTrainerEnabled = true
        let second = PulstickEngine(defaults: defaults, output: SilentClickOutput())
        #expect(second.gapTrainer == GapTrainer(playBars: 3, muteBars: 1))
        #expect(second.gapTrainerEnabled)
    }
}

// MARK: - TempoMarking

@Suite("TempoMarking")
struct TempoMarkingTests {
    @Test(arguments: [
        (30.0, "Grave"), (39.0, "Grave"),
        (40.0, "Largo"), (59.0, "Largo"),
        (60.0, "Larghetto"),
        (66.0, "Adagio"),
        (76.0, "Andante"), (107.0, "Andante"),
        (108.0, "Moderato"),
        (120.0, "Allegro"), (155.0, "Allegro"),
        (156.0, "Vivace"),
        (176.0, "Presto"),
        (200.0, "Prestissimo"), (300.0, "Prestissimo"),
    ])
    func nameMatchesTempoRange(bpm: Double, expected: String) {
        #expect(TempoMarking.name(for: bpm) == expected)
    }
}

// MARK: - ElapsedTime

@Suite("ElapsedTime")
struct ElapsedTimeTests {
    @Test(arguments: [
        (0.0, "0:00"), (5.9, "0:05"), (65.0, "1:05"), (3600.0, "1:00:00"), (3725.0, "1:02:05"), (-3.0, "0:00"),
    ])
    func formatsAsClock(seconds: Double, expected: String) {
        #expect(ElapsedTime.format(seconds) == expected)
    }
}

// MARK: - TickSchedule

@Suite("TickSchedule")
struct TickScheduleTests {
    @Test func nextDeadlineIsMeasuredFromLastFireNotFromNow() {
        // 0.5秒間隔で 1_000ms に鳴った直後(1_100ms)にテンポ変更 → 次は 1_000 + 400ms
        let next = TickSchedule.nextDeadline(lastFire: 1_000_000_000, interval: 0.4, now: 1_100_000_000)
        #expect(next == 1_400_000_000)
    }

    @Test func overdueDeadlineFiresImmediately() {
        // 新しい間隔だと既に過ぎている場合は待たずに今鳴らす
        let next = TickSchedule.nextDeadline(lastFire: 1_000_000_000, interval: 0.2, now: 1_300_000_000)
        #expect(next == 1_300_000_000)
    }
}

// MARK: - PulstickEngine: 実際のタイマーを使った統合テスト
// MainActor 上で await している間にメインキューへの dispatch が処理される

@MainActor
@Suite("PulstickEngine: 再生中の挙動", .serialized)
struct PlaybackIntegrationTests {
    private func spin(_ seconds: Double) async throws {
        try await Task.sleep(for: .seconds(seconds))
    }

    @Test func speedTrainerRaisesTempoWhilePlaying() async throws {
        let engine = makeEngine()
        engine.setBeats(1)
        engine.bpm = 200
        engine.speedTrainer = SpeedTrainer(measuresPerStep: 1, bpmIncrement: 1, targetBPM: 240)
        engine.speedTrainerEnabled = true
        engine.start()
        try await spin(0.8)
        #expect(engine.sessionStartBPM == 200)
        engine.stop()
        #expect(engine.bpm > 200)
        #expect(engine.sessionStartBPM == nil)
        #expect(engine.playStartedAt == nil)
    }

    @Test func beatsKeepComingWhileTempoIsDragged() async throws {
        let engine = makeEngine()
        engine.setBeats(4)
        engine.bpm = 240
        var beatChanges = 0
        let cancellable = engine.beatClock.$current.removeDuplicates().dropFirst().sink { _ in beatChanges += 1 }
        engine.start()
        // スライダーのドラッグを模して 20ms ごとにテンポを変え続ける（間隔 250ms より短い）
        for i in 0..<40 {
            engine.bpm = i.isMultiple(of: 2) ? 239 : 240
            try await spin(0.02)
        }
        engine.stop()
        cancellable.cancel()
        #expect(beatChanges >= 2)
    }

    @Test func gapTrainerSilencesEveryOtherBar() async throws {
        let output = SilentClickOutput()
        let engine = PulstickEngine(defaults: InMemorySettingsStore(), output: output)
        engine.setBeats(1)
        engine.bpm = 240  // 1小節 = 250ms
        engine.gapTrainer = GapTrainer(playBars: 1, muteBars: 1)
        engine.gapTrainerEnabled = true
        engine.start()
        try await spin(1.1)  // 小節 0〜4 → 鳴るのは 0, 2, 4
        engine.stop()
        #expect((2...3).contains(output.played.count))
    }

    @Test func stoppingRecordsPracticeTime() async throws {
        let defaults = InMemorySettingsStore()
        let engine = PulstickEngine(defaults: defaults, output: SilentClickOutput())
        engine.minimumLoggedSession = 0
        engine.start()
        let startedAt = engine.playStartedAt!
        try await spin(0.2)
        engine.stop()
        engine.stop()  // 二度止めても二重に記録しない
        let elapsed = Date().timeIntervalSince(startedAt)
        let logged = engine.practiceLog.seconds(on: startedAt)
        #expect(logged >= 0.2)
        #expect(logged <= elapsed)
        let relaunched = PulstickEngine(defaults: defaults, output: SilentClickOutput())
        #expect(relaunched.practiceLog == engine.practiceLog)
    }

    @Test func stoppingClearsTheSessionStartTempo() {
        let engine = makeEngine()
        engine.start()
        engine.stop()
        #expect(engine.sessionStartBPM == nil)
    }

    @Test func veryShortSessionsAreNotLogged() async throws {
        let engine = makeEngine()
        engine.start()
        try await spin(0.1)
        engine.stop()
        #expect(engine.practiceLog.seconds(on: Date()) == 0)
    }

    @Test func mutedEngineKeepsTimeButPlaysNothing() async throws {
        let output = SilentClickOutput()
        let engine = PulstickEngine(defaults: InMemorySettingsStore(), output: output)
        engine.setBeats(4)
        engine.bpm = 240
        engine.isMuted = true
        var beatChanges = 0
        let cancellable = engine.beatClock.$current.removeDuplicates().dropFirst().sink { _ in beatChanges += 1 }
        engine.start()
        try await spin(0.6)
        engine.stop()
        cancellable.cancel()
        #expect(output.played.isEmpty)
        #expect(beatChanges >= 1)
    }

    @Test func beatsDoNotInvalidateViewsObservingTheWholeEngine() async throws {
        let engine = makeEngine()
        engine.setBeats(4)
        engine.bpm = 240  // 0.8 秒で 3 拍以上進む
        engine.start()
        try await spin(0.05)
        var engineChanges = 0
        var beatChanges = 0
        let engineSub = engine.objectWillChange.sink { engineChanges += 1 }
        let beatSub = engine.beatClock.$current.dropFirst().sink { _ in beatChanges += 1 }
        try await spin(0.8)
        engineSub.cancel()
        beatSub.cancel()
        engine.stop()
        // 拍は BeatClock だけが通知し、エンジン全体（ポップオーバーやメニューバー）は再評価させない
        #expect(beatChanges >= 3)
        #expect(engineChanges == 0)
    }

    @Test func noClicksArePlayedAfterStop() async throws {
        let output = SilentClickOutput()
        let engine = PulstickEngine(defaults: InMemorySettingsStore(), output: output)
        engine.bpm = 300
        engine.subdivision = .sixteenth  // 50ms 間隔で、停止の瞬間にハンドラが走っている確率を上げる
        engine.start()
        try await spin(0.12)
        engine.stop()
        let playedAtStop = output.played.count
        try await spin(0.2)
        #expect(output.played.count == playedAtStop)
    }

    @Test func practiceTimerStopsPlaybackWhenTimeIsUp() async throws {
        let engine = makeEngine()
        engine.bpm = 300
        engine.stopAfter = 0.05
        engine.start()
        try await spin(0.45)  // 300 BPM の 1 拍は 200ms。拍ごとに確かめるので 2 拍以内に止まる
        #expect(!engine.isPlaying)
    }

    @Test func practiceTimerStopsOnTimeEvenAtSlowTempo() async throws {
        let engine = makeEngine()
        engine.bpm = 30  // 1 拍 2 秒。拍の合間でも時間どおりに止まること
        engine.start()
        engine.stopAfter = 0.3  // 再生中に設定しても効く
        try await spin(0.6)
        #expect(!engine.isPlaying)
    }

    @Test func playbackContinuesWithoutPracticeTimer() async throws {
        let engine = makeEngine()
        engine.bpm = 300
        engine.start()
        try await spin(0.5)
        #expect(engine.isPlaying)
        engine.stop()
    }

    @Test func restBeatsPlayNothing() async throws {
        let output = SilentClickOutput()
        let engine = PulstickEngine(defaults: InMemorySettingsStore(), output: output)
        engine.setBeats(1)
        engine.cycleBeat(0)  // 唯一の拍を休みに
        engine.bpm = 240
        engine.start()
        try await spin(0.4)
        engine.stop()
        #expect(output.played.isEmpty)
    }

    @Test func playingASongAddsToItsPracticeTime() async throws {
        let engine = makeEngine()
        engine.minimumLoggedSession = 0
        engine.bpm = 200
        engine.saveCurrentAsSong(named: "Etude")
        engine.speedTrainer = SpeedTrainer(measuresPerStep: 1, bpmIncrement: 1, targetBPM: 240)
        engine.speedTrainerEnabled = true  // 途中でテンポが変わっても同じ曲として数える
        engine.start()
        try await spin(0.3)
        engine.stop()
        let song = try #require(engine.songs.first)
        #expect(song.practiceSeconds >= 0.3)
    }

    @Test func playingWithoutAMatchingSongCreditsNoSong() async throws {
        let engine = makeEngine()
        engine.minimumLoggedSession = 0
        engine.bpm = 100
        engine.saveCurrentAsSong(named: "Slow")
        engine.bpm = 140
        engine.start()
        try await spin(0.1)
        engine.stop()
        #expect(engine.songs.first?.practiceSeconds == 0)
    }

    @Test func subdivisionClicksReachTheOutput() async throws {
        let output = SilentClickOutput()
        let engine = PulstickEngine(defaults: InMemorySettingsStore(), output: output)
        engine.setBeats(4)
        engine.bpm = 240
        engine.subdivision = .eighth
        engine.start()
        try await spin(0.4)  // 8分は 125ms 間隔 → 先頭 + 3回前後
        engine.stop()
        #expect(output.played.first == .accent)
        #expect(output.played.contains(.subdivision))
        #expect(output.played.contains(.normal))
    }
}

// MARK: - GapTrainer

@Suite("GapTrainer")
struct GapTrainerTests {
    @Test func mutesBarsAfterPlayedBarsAndRepeats() {
        let gap = GapTrainer(playBars: 2, muteBars: 1)
        let pattern = (0..<6).map { gap.isMuted(measure: $0) }
        #expect(pattern == [false, false, true, false, false, true])
    }

    @Test func zeroMuteBarsNeverMutes() {
        let gap = GapTrainer(playBars: 1, muteBars: 0)
        #expect((0..<4).allSatisfy { !gap.isMuted(measure: $0) })
    }
}

// MARK: - PracticeLog

@Suite("PracticeLog")
struct PracticeLogTests {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return c
    }

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    @Test func recordsSessionLengthOnItsDay() {
        var log = PracticeLog()
        log.record(from: date(12, 20), to: date(12, 20, 25), calendar: calendar)
        #expect(log.seconds(on: date(12, 9), calendar: calendar) == 25 * 60)
    }

    @Test func sessionCrossingMidnightIsSplitBetweenDays() {
        var log = PracticeLog()
        log.record(from: date(12, 23, 50), to: date(13, 0, 20), calendar: calendar)
        #expect(log.seconds(on: date(12, 12), calendar: calendar) == 10 * 60)
        #expect(log.seconds(on: date(13, 12), calendar: calendar) == 20 * 60)
    }

    @Test func streakCountsConsecutiveDaysEndingToday() {
        var log = PracticeLog()
        for day in [9, 10, 11, 12] {
            log.record(from: date(day, 20), to: date(day, 20, 10), calendar: calendar)
        }
        log.record(from: date(7, 20), to: date(7, 20, 10), calendar: calendar)  // 8日が空くので数えない
        #expect(log.streak(endingAt: date(12, 22), calendar: calendar) == 4)
    }

    @Test func recentDaysListsOldestFirstWithZerosForMissedDays() {
        var log = PracticeLog()
        log.record(from: date(10, 20), to: date(10, 20, 30), calendar: calendar)
        log.record(from: date(12, 20), to: date(12, 20, 10), calendar: calendar)
        #expect(log.recentDays(3, endingAt: date(12, 22), calendar: calendar) == [1800, 0, 600])
    }

    @Test func practisingRightNowCountsTodayInTheStreak() {
        var log = PracticeLog()
        log.record(from: date(11, 20), to: date(11, 20, 10), calendar: calendar)
        #expect(log.streak(endingAt: date(12, 8), practisingNow: true, calendar: calendar) == 2)
    }

    @Test func streakStillCountsWhenTodayHasNoPracticeYet() {
        var log = PracticeLog()
        log.record(from: date(11, 20), to: date(11, 20, 10), calendar: calendar)
        #expect(log.streak(endingAt: date(12, 8), calendar: calendar) == 1)
        #expect(log.streak(endingAt: date(13, 8), calendar: calendar) == 0)
    }
}

// MARK: - ClickSynth
// 実際に音を鳴らさず、波形の性質（長さ・端の連続性・クリップしないこと）を検証する

@Suite("ClickSynth")
struct ClickSynthTests {
    @Test(arguments: ClickSound.allCases)
    func everySoundIsShortAndStartsAndEndsSilently(sound: ClickSound) {
        for kind in [ClickKind.accent, .normal, .subdivision] {
            let wave = ClickSynth.samples(sound, kind)
            #expect((441...4410).contains(wave.count), "\(sound) \(kind): 10〜100ms に収める")
            // 端が 0 から離れていると再生開始・終了時にプチッと鳴る
            #expect(abs(wave.first ?? 1) < 0.01)
            #expect(abs(wave.last ?? 1) < 0.01)
            #expect(wave.allSatisfy { abs($0) <= 0.9 }, "\(sound) \(kind): クリップしない")
        }
    }

    private func zeroCrossings(_ wave: [Float]) -> Int {
        zip(wave, wave.dropFirst()).filter { ($0 < 0) != ($1 < 0) }.count
    }

    @Test(arguments: [ClickSound.beep, .wood])
    func accentIsHigherPitchedThanNormalBeat(sound: ClickSound) {
        // 先頭 10ms のゼロ交差数でおおよその音程を比べる
        let accent = Array(ClickSynth.samples(sound, .accent).prefix(441))
        let normal = Array(ClickSynth.samples(sound, .normal).prefix(441))
        #expect(zeroCrossings(accent) > zeroCrossings(normal))
    }

    @Test(arguments: ClickSound.allCases)
    func soundDecaysOverTime(sound: ClickSound) {
        let wave = ClickSynth.samples(sound, .normal)
        let quarter = wave.count / 4
        let energy = { (part: ArraySlice<Float>) in part.reduce(0) { $0 + $1 * $1 } }
        #expect(energy(wave.suffix(quarter)) < energy(wave.prefix(quarter)))
    }
}

// MARK: - SentenceTemplate

@Suite("SentenceTemplate")
struct SentenceTemplateTests {
    @Test func splitsTextAndPositionalSlots() {
        #expect(SentenceTemplate.parse("%1$@ BPM every %2$@ bars") == [
            .slot(0), .text("BPM every"), .slot(1), .text("bars"),
        ])
    }

    @Test func slotsCanAppearInAnyOrder() {
        #expect(SentenceTemplate.parse("%2$@ 小節ごとに %1$@ BPM（上限 %3$@）") == [
            .slot(1), .text("小節ごとに"), .slot(0), .text("BPM（上限"), .slot(2), .text("）"),
        ])
    }
}

// MARK: - TapTempo

@Suite("TapTempo")
struct TapTempoLogicTests {
    private func taps(_ intervals: [Double]) -> Double? {
        var tempo = TapTempo()
        var time = Date(timeIntervalSinceReferenceDate: 0)
        var result = tempo.tap(at: time)
        for interval in intervals {
            time = time.addingTimeInterval(interval)
            result = tempo.tap(at: time)
        }
        return result
    }

    @Test func oneSloppyTapDoesNotThrowOffTheTempo() {
        // 120 BPM (0.5 秒間隔) の途中で 1 回だけ大きく遅れた
        #expect(taps([0.5, 0.5, 0.8, 0.5, 0.5]) == 120)
    }

    @Test func followsATempoChangeWithinThreeTaps() {
        // 120 BPM で 7 回叩いた後、休まずに 90 BPM へ切り替える
        #expect(taps([0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.667, 0.667, 0.667]) == 90)
    }

    @Test func firstTapGivesNoTempo() {
        #expect(taps([]) == nil)
    }

    @Test func pauseStartsANewMeasurement() {
        // 90 BPM で叩いた後、3 秒空けて 150 BPM で 2 回
        #expect(taps([0.667, 0.667, 3.0, 0.4]) == 150)
    }
}
