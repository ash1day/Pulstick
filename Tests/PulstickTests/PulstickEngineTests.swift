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
            engine.saveCurrentAsSong(named: name)  // 最後に保存した C が選択中になる
        }
        engine.applyAdjacentSong(-1)
        #expect(engine.bpm == 120)
        engine.applyAdjacentSong(-1)
        #expect(engine.bpm == 100)
        engine.applyAdjacentSong(-1)  // 先頭からさらに前へは行かない
        #expect(engine.bpm == 100)
        engine.applyAdjacentSong(1)
        #expect(engine.bpm == 120)
    }

    @Test func nextSongStartsFromTheTopWhenNothingIsSelected() {
        let engine = makeEngine()
        for (name, bpm) in [("A", 100.0), ("B", 120), ("C", 140)] {
            engine.bpm = bpm
            engine.saveCurrentAsSong(named: name)
        }
        engine.deleteSong(engine.songs[2])  // 選択中の曲を消すと、何も選ばれていない状態になる
        engine.setBeats(3)  // どの曲とも違う拍子を弾いている
        engine.applyAdjacentSong(1)
        #expect(engine.bpm == 100)
    }

    @Test func nextSongMovesOnEvenWhenSongsShareSettings() {
        let engine = makeEngine()
        for name in ["A", "B"] { engine.saveCurrentAsSong(named: name) }  // 同じ設定の 2 曲
        engine.bpm = 140
        engine.saveCurrentAsSong(named: "C")
        engine.applySong(engine.songs[0])
        engine.applyAdjacentSong(1)
        #expect(engine.selectedSongID == engine.songs[1].id)
        engine.applyAdjacentSong(1)
        #expect(engine.selectedSongID == engine.songs[2].id)
    }

    @Test func nextSongFollowsTheSelectionAfterTheTempoDrifts() {
        let engine = makeEngine()
        for (name, bpm) in [("A", 100.0), ("B", 120)] {
            engine.bpm = bpm
            engine.saveCurrentAsSong(named: name)
        }
        engine.applySong(engine.songs[0])
        engine.bpm = 104  // トレーナーや ↑ キーでテンポが変わった
        engine.applyAdjacentSong(1)
        #expect(engine.bpm == 120)
    }

    @Test func steppingPastTheLastSongChangesNothing() {
        let engine = makeEngine()
        engine.bpm = 100
        engine.saveCurrentAsSong(named: "Only")
        engine.applySong(engine.songs[0])
        engine.bpm = 110  // 練習中に上がったテンポを、端で押した ] が戻してしまわないこと
        engine.applyAdjacentSong(1)
        #expect(engine.bpm == 110)
    }

    @Test func unsavedPracticeTodayFollowsTheLoggingRules() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let clock = TestClock()
        clock.date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 23, minute: 50))!
        let engine = makeEngine(clock: clock)
        engine.start()
        clock.advance(3)
        #expect(engine.unsavedPracticeToday(calendar: calendar) == 0)  // 5 秒未満はまだ数えない
        clock.advance(20 * 60 - 3)  // 0:10 まで
        #expect(engine.unsavedPracticeToday(calendar: calendar) == 10 * 60)  // 日付が変わってからの分だけ
        engine.stop()
    }

    @Test func resettingPracticeHistoryClearsTheLogAndSongTimesButKeepsSongs() {
        let clock = TestClock()
        let engine = makeEngine(clock: clock)
        engine.saveCurrentAsSong(named: "Etude")
        engine.start()
        clock.advance(600)
        engine.stop()
        engine.resetPracticeHistory()
        #expect(engine.practiceLog.secondsByDay.isEmpty)
        #expect(engine.songs.map(\.name) == ["Etude"])
        #expect(engine.songs[0].practiceSeconds == 0)
        #expect(engine.songs[0].bestBPM == nil)
    }

    @Test func theFastestTempoPlayedIsRememberedPerSong() {
        let clock = TestClock()
        let engine = makeEngine(clock: clock)
        engine.bpm = 100
        engine.saveCurrentAsSong(named: "Etude")
        engine.start()
        clock.advance(30)
        engine.bpm = 112  // トレーナーや ↑ キーで上がった
        clock.advance(30)
        engine.bpm = 108
        engine.stop()
        #expect(engine.songs[0].bestBPM == 112)
    }

    @Test func switchingSongsDoesNotGiveTheOldSongTheNewTempo() {
        let clock = TestClock()
        let engine = makeEngine(clock: clock)
        engine.bpm = 100
        engine.saveCurrentAsSong(named: "A")
        engine.bpm = 180
        engine.saveCurrentAsSong(named: "B")
        engine.applySong(engine.songs[0])
        engine.start()
        clock.advance(60)
        engine.applySong(engine.songs[1])
        clock.advance(60)
        engine.stop()
        #expect(engine.songs[0].bestBPM == 100)
        #expect(engine.songs[1].bestBPM == 180)
    }

    @Test func savingWhilePlayingRecordsTheTempoForTheNewSong() {
        let clock = TestClock()
        let engine = makeEngine(clock: clock)
        engine.bpm = 120
        engine.start()
        clock.advance(60)
        engine.saveCurrentAsSong(named: "Etude")
        engine.stop()
        #expect(engine.songs[0].bestBPM == 120)
    }

    @Test func deletingASongDoesNotPassItsBestTempoOn() {
        let clock = TestClock()
        let engine = makeEngine(clock: clock)
        for name in ["A", "B"] { engine.saveCurrentAsSong(named: name) }  // 同じ設定 (120)
        engine.applySong(engine.songs[0])
        engine.start()
        engine.bpm = 200  // A で 200 まで上げてから戻す
        clock.advance(30)
        engine.bpm = 120
        engine.deleteSong(engine.songs[0])
        clock.advance(30)
        engine.stop()
        #expect(engine.songs[0].bestBPM == 120)
    }

    @Test func resettingWhilePlayingDoesNotBringTheHistoryBack() {
        let clock = TestClock()
        let engine = makeEngine(clock: clock)
        engine.saveCurrentAsSong(named: "Etude")
        engine.start()
        clock.advance(600)
        engine.resetPracticeHistory()
        clock.advance(60)
        engine.stop()
        // リセット後の 1 分だけが残る
        #expect(engine.practiceLog.seconds(on: clock.date) == 60)
        #expect(engine.songs[0].practiceSeconds == 60)
    }

    @Test func aShortRunDoesNotSetTheBestTempo() {
        let clock = TestClock()
        let engine = makeEngine(clock: clock)
        engine.bpm = 100
        engine.saveCurrentAsSong(named: "Etude")
        engine.start()
        engine.bpm = 180  // 間違えて上げてすぐ止めた
        clock.advance(2)
        engine.stop()
        #expect(engine.songs[0].bestBPM == nil)
    }

    @Test func weeklyGoalIsRememberedAndKeptInRange() {
        let defaults = InMemorySettingsStore()
        let first = PulstickEngine(defaults: defaults, output: SilentClickOutput())
        first.weeklyGoalMinutes = 120
        let second = PulstickEngine(defaults: defaults, output: SilentClickOutput())
        #expect(second.weeklyGoalMinutes == 120)
        second.weeklyGoalMinutes = -5
        #expect(second.weeklyGoalMinutes == 0)
    }

    @Test func weekProgressIncludesTheSessionPlayingNow() {
        let clock = TestClock()
        let engine = makeEngine(clock: clock)
        var log = PracticeLog()
        log.record(from: clock.date.addingTimeInterval(-2 * 86_400 - 1800), to: clock.date.addingTimeInterval(-2 * 86_400))
        engine.seedPracticeLog(log)
        engine.start()
        clock.advance(600)
        #expect(engine.practiceSecondsThisWeek() == 1800 + 600)
        engine.stop()
    }

    @Test func weekProgressCountsASessionPlayingAcrossMidnight() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let clock = TestClock()
        clock.date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 23, minute: 30))!
        let engine = makeEngine(clock: clock)
        engine.start()
        clock.advance(50 * 60)  // 0:20 まで弾き続けている
        #expect(engine.practiceSecondsThisWeek(calendar: calendar) == 50 * 60)
        engine.stop()
    }

    @Test func aSessionSpanningSeveralMidnightsIsSplitByDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let clock = TestClock()
        clock.date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: 22))!
        let engine = makeEngine(clock: clock)
        engine.start()
        clock.advance(28 * 3600)  // 12 日の 2 時まで流しっぱなし
        let log = engine.practiceLogIncludingCurrentSession(calendar: calendar)
        #expect(log.recentDays(3, endingAt: clock.date, calendar: calendar) == [2.0 * 3600, 24.0 * 3600, 2.0 * 3600])
        engine.stop()
    }

    @Test func weekProgressLeavesOutDaysOlderThanSeven() {
        let clock = TestClock()
        let engine = makeEngine(clock: clock)
        var log = PracticeLog()
        let eightDaysAgo = clock.date.addingTimeInterval(-8 * 86_400)
        log.record(from: eightDaysAgo, to: eightDaysAgo.addingTimeInterval(3600))
        engine.seedPracticeLog(log)
        #expect(engine.practiceSecondsThisWeek() == 0)
    }

    @Test func weeklyGoalSnapsToAMenuOption() {
        let engine = makeEngine()
        engine.weeklyGoalMinutes = 100
        #expect(PulstickEngine.weeklyGoalOptions.contains(engine.weeklyGoalMinutes))
    }

    @Test func stoppingDuringTheCountInRecordsNoPractice() async throws {
        let engine = makeEngine()
        engine.minimumLoggedSession = 0
        engine.setBeats(4)
        engine.bpm = 60  // カウントインの 1 小節は 4 秒
        engine.countInBars = 1
        engine.start()
        try await Task.sleep(for: .milliseconds(300))
        engine.stop()
        #expect(engine.practiceLog.secondsByDay.isEmpty)
    }

    @Test func savingWhilePlayingStartsCountingThatSong() {
        let clock = TestClock()
        let engine = makeEngine(clock: clock)
        engine.start()
        engine.saveCurrentAsSong(named: "New")
        clock.advance(120)
        engine.stop()
        #expect(engine.songs.first?.practiceSeconds == 120)
    }

    @Test func shortSessionsCreditNoSongEvenAfterSwitching() {
        let clock = TestClock()
        let engine = makeEngine(clock: clock)
        engine.bpm = 100
        engine.saveCurrentAsSong(named: "A")
        engine.bpm = 120
        engine.saveCurrentAsSong(named: "B")
        engine.applySong(engine.songs[0])
        engine.start()
        clock.advance(3)
        engine.applySong(engine.songs[1])
        engine.stop()  // セッション全体が 5 秒未満
        #expect(engine.songs.allSatisfy { $0.practiceSeconds == 0 })
    }

    @Test func practiceTimeIncludesTheSongPlayingNow() {
        let clock = TestClock()
        let engine = makeEngine(clock: clock)
        engine.saveCurrentAsSong(named: "Etude")
        engine.applySong(engine.songs[0])
        engine.start()
        clock.advance(90)
        #expect(engine.practiceSeconds(for: engine.songs[0]) == 90)
        engine.stop()
    }

    @Test func choosingASongCreditsItEvenIfAnotherHasTheSameSettings() {
        let clock = TestClock()
        let engine = makeEngine(clock: clock)
        for name in ["Warmup", "Ballad"] { engine.saveCurrentAsSong(named: name) }
        engine.applySong(engine.songs[1])
        engine.start()
        clock.advance(60)
        engine.stop()
        #expect(engine.songs[0].practiceSeconds == 0)
        #expect(engine.songs[1].practiceSeconds == 60)
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

    @Test func theChosenSongStaysCurrentWhenItsTempoDriftsOntoAnother() {
        // スピードトレーナーなどで A のテンポが B と同じになっても、選んだ A のまま（B に乗っ取られない）
        let engine = makeEngine()
        engine.bpm = 100
        engine.saveCurrentAsSong(named: "A")
        engine.bpm = 120
        engine.saveCurrentAsSong(named: "B")
        engine.applySong(engine.songs[0])
        engine.bpm = 120
        #expect(engine.currentSong?.name == "A")
    }

    @Test func anExactMatchIsUsedWhenTheChosenSongNoLongerFits() {
        let engine = makeEngine()
        engine.bpm = 100
        engine.saveCurrentAsSong(named: "A")
        engine.setBeats(3)
        engine.bpm = 120
        engine.saveCurrentAsSong(named: "B")  // 3 拍子
        engine.applySong(engine.songs[0])
        engine.setBeats(3)
        engine.bpm = 120  // A の拍子から外れ、B と完全一致
        #expect(engine.currentSong?.name == "B")
    }

    @Test func deletingTheSongBeingPractisedKeepsCountingTheSongThatMatches() {
        let clock = TestClock()
        let engine = makeEngine(clock: clock)
        for name in ["A", "B"] { engine.saveCurrentAsSong(named: name) }  // 同じ設定
        engine.applySong(engine.songs[0])
        engine.start()
        engine.deleteSong(engine.songs[0])
        clock.advance(60)
        engine.stop()
        #expect(engine.songs.first?.practiceSeconds == 60)
    }

    @Test func corruptPresetsCannotSetZeroBeats() {
        let defaults = InMemorySettingsStore()
        let bad = #"[{"beats":0,"accents":[0]},{"beats":3,"accents":[0]},{"beats":6,"accents":[0,3]},{"beats":9,"accents":[0,3,6]}]"#
        defaults.set(bad.data(using: .utf8), forKey: "pulstick.presets")
        let engine = PulstickEngine(defaults: defaults, output: SilentClickOutput())
        engine.applyPreset(at: 0)
        #expect(engine.beatsPerMeasure >= 1)
    }

    @Test func songsCanMoveMoreThanOneStep() {
        let engine = makeEngine()
        for name in ["A", "B", "C"] { engine.saveCurrentAsSong(named: name) }
        engine.moveSong(engine.songs[0], by: 2)
        #expect(engine.songs.map(\.name) == ["B", "C", "A"])
    }

    @Test func steppingWorksFromASongThatCannotMatch() {
        let engine = makeEngine()
        engine.saveCurrentAsSong(named: "A")
        engine.saveCurrentAsSong(named: "B")
        engine.applySong(engine.songs[0])
        engine.toggleAccent(2)  // 選んだ曲から拍のパターンが外れた
        engine.applyAdjacentSong(1)
        #expect(engine.selectedSongID == engine.songs[1].id)
    }

    @Test func switchingSongsAfterALongEnoughSessionSavesRightAway() {
        let clock = TestClock()
        let engine = makeEngine(clock: clock)
        engine.bpm = 100
        engine.saveCurrentAsSong(named: "A")
        engine.bpm = 120
        engine.saveCurrentAsSong(named: "B")
        engine.applySong(engine.songs[0])
        engine.start()
        clock.advance(600)
        engine.applySong(engine.songs[1])
        // 停止前（アプリが落ちても）A の 10 分はもう保存されている
        #expect(engine.songs[0].practiceSeconds == 600)
        engine.stop()
    }

    @Test func savingAfterChangingThePatternCreditsTheNewSongFromTheChange() {
        let clock = TestClock()
        let engine = makeEngine(clock: clock)
        engine.saveCurrentAsSong(named: "A")
        engine.applySong(engine.songs[0])
        engine.start()
        clock.advance(60)
        engine.setBeats(3)  // 別の拍子を弾き始めた
        clock.advance(300)
        engine.saveCurrentAsSong(named: "Waltz")
        engine.stop()
        #expect(engine.songs[0].practiceSeconds == 60)
        #expect(engine.songs[1].practiceSeconds == 300)
    }

    @Test func switchingSongsWhilePlayingSavesSongsOnce() {
        let clock = TestClock()
        let engine = makeEngine(clock: clock)
        engine.bpm = 100
        engine.saveCurrentAsSong(named: "A")
        engine.setBeats(3)
        engine.bpm = 120
        engine.saveCurrentAsSong(named: "B")
        engine.applySong(engine.songs[0])
        engine.start()
        clock.advance(600)  // 記録に値する長さの再生
        var writes = 0
        let subscription = engine.$songs.dropFirst().sink { _ in writes += 1 }
        engine.applySong(engine.songs[1])  // 拍子も変わる曲への切り替え
        subscription.cancel()
        engine.stop()
        #expect(writes == 1)
    }

    @Test func resavingASongKeepsItsPracticeTime() {
        let engine = makeEngine()
        engine.saveCurrentAsSong(named: "Etude")
        engine.seedSongPractice(600, forSongAt: 0)
        engine.songs[0].bestBPM = 150
        engine.bpm = 132
        engine.saveCurrentAsSong(named: "Etude")  // テンポを変えて上書き
        #expect((engine.songs.first?.practiceSeconds ?? 0) >= 600)
        #expect(engine.songs.first?.bestBPM == 150)
    }

    @Test func songsSavedBeforePracticeTimeExistedStillLoad() {
        let defaults = InMemorySettingsStore()
        let old = #"[{"id":"7C9E6B1E-1D1F-4B7A-9C1E-2A3B4C5D6E7F","name":"Old","bpm":90,"pattern":{"beats":3,"accents":[0]},"subdivision":1}]"#
        defaults.set(old.data(using: .utf8), forKey: "pulstick.songs")
        let engine = PulstickEngine(defaults: defaults, output: SilentClickOutput())
        #expect(engine.songs.map(\.name) == ["Old"])
    }

    @Test func theChosenSongIsRememberedAcrossLaunches() {
        let defaults = InMemorySettingsStore()
        let first = PulstickEngine(defaults: defaults, output: SilentClickOutput())
        for (name, bpm) in [("A", 100.0), ("B", 120), ("C", 140)] {
            first.bpm = bpm
            first.saveCurrentAsSong(named: name)
        }
        first.applySong(first.songs[1])
        let second = PulstickEngine(defaults: defaults, output: SilentClickOutput())
        #expect(second.selectedSongID == second.songs[1].id)
        second.applyAdjacentSong(1)  // 前回の続きから
        #expect(second.bpm == 140)
    }

    @Test func aRestoredChoiceIsOnlyCurrentWhenTheSettingsStillMatch() {
        let defaults = InMemorySettingsStore()
        let first = PulstickEngine(defaults: defaults, output: SilentClickOutput())
        first.bpm = 132
        first.saveCurrentAsSong(named: "Autumn Leaves")
        first.bpm = 80  // 曲とは関係ない練習をしたまま終了
        let second = PulstickEngine(defaults: defaults, output: SilentClickOutput())
        #expect(second.currentSong == nil)  // 次に起動したとき、別の 4/4 の練習をその曲として数えない
    }

    @Test func theSetlistPositionSurvivesSeveralLaunchesOfUnrelatedPractice() {
        let defaults = InMemorySettingsStore()
        let first = PulstickEngine(defaults: defaults, output: SilentClickOutput())
        for (name, bpm) in [("A", 100.0), ("B", 120), ("C", 140)] {
            first.bpm = bpm
            first.saveCurrentAsSong(named: name)
        }
        first.applySong(first.songs[1])
        first.bpm = 80  // 曲と関係ない練習をして終了、を 2 回
        _ = PulstickEngine(defaults: defaults, output: SilentClickOutput())
        let third = PulstickEngine(defaults: defaults, output: SilentClickOutput())
        #expect(third.currentSong == nil)
        third.applyAdjacentSong(1)  // それでも B の次から
        #expect(third.bpm == 140)
    }

    @Test func aSongCanBePractisedAtAFractionOfItsTempo() {
        let engine = makeEngine()
        engine.bpm = 160
        engine.saveCurrentAsSong(named: "Etude")
        engine.bpm = 100
        engine.applySong(engine.songs[0], tempoPercent: 80)
        #expect(engine.bpm == 128)
        #expect(engine.currentSong?.name == "Etude")  // テンポを落としても同じ曲の練習
    }

    @Test func practisingAtAFractionRecordsTheSlowerTempoAsBest() {
        let clock = TestClock()
        let engine = makeEngine(clock: clock)
        engine.bpm = 160
        engine.saveCurrentAsSong(named: "Etude")
        engine.setBeats(3)  // 別の曲を弾いている状態から
        engine.start()
        engine.applySong(engine.songs[0], tempoPercent: 80)
        clock.advance(60)
        engine.stop()
        #expect(engine.songs[0].bestBPM == 128)  // 本来の 160 を一瞬でも記録しない
    }

    @Test func rampingUpASongAtTheSlowestTempoJustAppliesIt() {
        let engine = makeEngine()
        engine.bpm = 30
        engine.saveCurrentAsSong(named: "Largo")
        engine.speedTrainer = SpeedTrainer(targetBPM: 160)
        engine.rampUp(engine.songs[0], fromPercent: 70)
        #expect(engine.bpm == 30)
        #expect(!engine.speedTrainerEnabled)  // 上げる余地がないのでトレーナーは使わない
        #expect(engine.speedTrainer.targetBPM == 160)
    }

    @Test func rampingUpASongStartsSlowAndTargetsItsTempo() {
        let engine = makeEngine()
        engine.bpm = 160
        engine.saveCurrentAsSong(named: "Etude")
        engine.rampUp(engine.songs[0], fromPercent: 70)
        #expect(engine.bpm == 112)
        #expect(engine.speedTrainerEnabled)
        #expect(engine.speedTrainer.targetBPM == 160)
    }

    @Test func rampingUpWhilePlayingClimbsFromSeventyPercentToTheSongTempo() {
        let engine = makeEngine()
        engine.bpm = 160
        engine.saveCurrentAsSong(named: "Etude")
        engine.setBeats(3)
        engine.bpm = 90
        engine.start()  // 別の練習をしている途中で
        engine.rampUp(engine.songs[0], fromPercent: 70)
        #expect(engine.sessionStartBPM == 112)  // ↶ で戻る先も 70% のテンポ
        for _ in 0..<200 { engine.handleMeasureCompleted() }
        #expect(engine.bpm == 160)  // 曲のテンポまで上がって止まる
        engine.stop()
    }

    @Test func aSetlistCanBeSharedWithoutPracticeData() throws {
        let mine = makeEngine()
        mine.bpm = 132
        mine.saveCurrentAsSong(named: "Autumn Leaves")
        mine.setBeats(3)
        mine.bpm = 96
        mine.saveCurrentAsSong(named: "Waltz")
        mine.seedSongPractice(3600, bestBPM: 140, forSongAt: 0)
        let text = try #require(mine.exportSetlist())

        let bandmate = makeEngine()
        bandmate.bpm = 120
        bandmate.saveCurrentAsSong(named: "waltz")  // 同じ名前の曲は上書きされる
        #expect(bandmate.importSetlist(text) == .imported(2))
        #expect(bandmate.songs.map(\.name) == ["Waltz", "Autumn Leaves"])
        #expect(bandmate.songs[0].bpm == 96)
        #expect(bandmate.songs[0].pattern.beats == 3)
        #expect(bandmate.songs[1].practiceSeconds == 0)  // 個人の練習記録は共有しない
        #expect(bandmate.songs[1].bestBPM == nil)
    }

    @Test func pastingSomethingElseChangesNothing() {
        let engine = makeEngine()
        engine.saveCurrentAsSong(named: "Etude")
        #expect(engine.importSetlist("hello") == .notASetlist)
        #expect(engine.songs.map(\.name) == ["Etude"])
    }

    @Test func aSetlistPastedFromChatStillImports() throws {
        // チャットから文章ごとコピーし、引用符が “ ” に置き換わっていても読める
        let text = #"Here's our setlist: {“pulstick”: 1, “songs”: [{“name”: “Blues”, “bpm”: 132.4, “pattern”: {“beats”: 4, “accents”: [0, 9, -1]}, “subdivision”: 1}]} see you"#
        let engine = makeEngine()
        #expect(engine.importSetlist(text) == .imported(1))
        let song = try #require(engine.songs.first)
        #expect(song.bpm == 132)  // 呼び出し時と同じく整数に丸める
        #expect(song.pattern.accents == [0])  // 範囲外の拍は捨てる
        engine.applySong(song)
        #expect(engine.currentSong?.id == song.id)  // 取り込んだ曲がちゃんと「いまの曲」になる
    }

    @Test func songNamesWithCurlyQuotesSurviveARoundTrip() throws {
        let mine = makeEngine()
        mine.saveCurrentAsSong(named: "“Blue” Bossa")
        let text = try #require(mine.exportSetlist())
        let other = makeEngine()
        #expect(other.importSetlist(text) == .imported(1))
        #expect(other.songs.first?.name == "“Blue” Bossa")
    }

    @Test func bracesInTheSurroundingMessageDoNotBreakTheImport() {
        let text = #"Setlist {rev 2} for Sunday: {"pulstick": 1, "songs": [{"name": "A", "bpm": 100, "pattern": {"beats": 4, "accents": [0]}, "subdivision": 1}]} see you :-}"#
        #expect(makeEngine().importSetlist(text) == .imported(1))
    }

    @Test func aSetlistFromANewerVersionAsksForAnUpdate() {
        let engine = makeEngine()
        #expect(engine.importSetlist(#"{"pulstick": 99, "songs": []}"#) == .needsNewerVersion)
    }

    @Test func onlySongsThatChangedAreCounted() {
        let engine = makeEngine()
        let text = #"{"pulstick": 1, "songs": [{"name": " ", "bpm": 100, "pattern": {"beats": 4, "accents": [0]}, "subdivision": 1}, {"name": "A", "bpm": 100, "pattern": {"beats": 4, "accents": [0]}, "subdivision": 1}]}"#
        #expect(engine.importSetlist(text) == .imported(1))
    }

    @Test func importingWhilePlayingFollowsTheRedefinedSong() {
        let clock = TestClock()
        let engine = makeEngine(clock: clock)
        engine.saveCurrentAsSong(named: "A")  // 120, 4/4
        engine.applySong(engine.songs[0])
        engine.start()
        clock.advance(60)
        // 再生中に、A を 3 拍子として定義し直したセットリストを貼り付けた
        let text = #"{"pulstick": 1, "songs": [{"name": "A", "bpm": 96, "pattern": {"beats": 3, "accents": [0]}, "subdivision": 1}]}"#
        _ = engine.importSetlist(text)
        clock.advance(60)
        engine.stop()
        #expect(engine.songs[0].practiceSeconds == 60)  // 定義が変わった後の時間は A に入らない
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

/// 練習時間のテストで、待たずに時間を進めるための時計
final class TestClock {
    var date = Date(timeIntervalSinceReferenceDate: 1_000_000)
    func advance(_ seconds: TimeInterval) { date += seconds }
}

func makeEngine(clock: TestClock) -> PulstickEngine {
    let engine = makeEngine()
    engine.now = { clock.date }
    return engine
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

@Suite("BeatSequencer: 拍数の変更")
struct BeatSequencerShrinkTests {
    @Test func shrinkingTheBarWhilePlayingGoesBackToTheDownbeat() {
        var seq = BeatSequencer(beatsPerMeasure: 4, accents: [0])
        _ = seq.advance(); _ = seq.advance(); _ = seq.advance()  // 4 拍目
        seq.beatsPerMeasure = 3
        #expect(seq.advance() == Tick(beat: 0, click: .accent, startsMeasure: true))
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

    @Test func countsDownTheBarsToTheNextTempoStep() {
        // 次にいつ速くなるか分かっていれば、上がる直前に身構えられる
        let engine = makeEngine()
        engine.bpm = 100
        engine.speedTrainer = SpeedTrainer(measuresPerStep: 4, bpmIncrement: 5, targetBPM: 200)
        engine.speedTrainerEnabled = true
        engine.start()
        #expect(engine.beatClock.barsUntilTempoStep == 4)
        engine.handleMeasureCompleted()
        #expect(engine.beatClock.barsUntilTempoStep == 3)
        engine.stop()
    }

    @Test func theCountdownDisappearsAtTheTargetAndWhenStopped() {
        let engine = makeEngine()
        engine.bpm = 100
        engine.speedTrainer = SpeedTrainer(measuresPerStep: 1, bpmIncrement: 5, targetBPM: 105)
        engine.speedTrainerEnabled = true
        engine.start()
        engine.handleMeasureCompleted()  // 105 で目標に届き、繰り返さないのでもう上がらない
        #expect(engine.bpm == 105)
        #expect(engine.beatClock.barsUntilTempoStep == nil)
        engine.speedTrainer.loops = true  // 繰り返すなら、開始テンポに戻るまでを数える
        #expect(engine.beatClock.barsUntilTempoStep == 1)
        engine.stop()
        #expect(engine.beatClock.barsUntilTempoStep == nil)
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

    @Test func practiceTimerSetWhilePlayingCountsFromThatMoment() async throws {
        let clock = TestClock()
        let engine = makeEngine(clock: clock)
        engine.start()
        clock.advance(720)  // 12 分練習してから
        engine.stopAfter = 600  // 「10 分」を選ぶ
        try await spin(0.1)
        #expect(engine.isPlaying)
        engine.stop()
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
        engine.setBeats(3)  // テンポ違いは同じ曲の練習とみなすので、拍子を変えて別の曲にする
        engine.start()
        try await spin(0.1)
        engine.stop()
        #expect(engine.songs.first?.practiceSeconds == 0)
    }

    @Test func countInSoundsEveryBeatOfItsBarEvenRests() async throws {
        let output = SilentClickOutput()
        let engine = PulstickEngine(defaults: InMemorySettingsStore(), output: output)
        engine.setBeats(2)
        engine.cycleBeat(0); engine.cycleBeat(1); engine.cycleBeat(1)  // 両方の拍を休みに
        engine.bpm = 240  // 1 小節 0.5 秒
        engine.countInBars = 1
        engine.start()
        try await spin(0.9)
        engine.stop()
        #expect(output.played == [.accent, .normal])  // カウントインの 2 拍だけ鳴り、その後は休み
    }

    @Test func theSpeedTrainerWaitsForTheCountIn() async throws {
        let engine = makeEngine()
        engine.setBeats(1)
        engine.bpm = 240  // 1 小節 0.25 秒
        engine.countInBars = 2
        engine.speedTrainer = SpeedTrainer(measuresPerStep: 1, bpmIncrement: 1, targetBPM: 300)
        engine.speedTrainerEnabled = true
        engine.start()
        try await spin(0.3)  // まだカウントイン中（終わるのは 0.5 秒）
        #expect(engine.bpm == 240)
        try await spin(0.6)  // カウントインが終わって練習の小節が進む
        #expect(engine.bpm > 240)
        engine.stop()
    }

    @Test func practiceTimeStartsAfterTheCountIn() async throws {
        let engine = makeEngine()
        engine.setBeats(1)
        engine.bpm = 240  // 1 小節 0.25 秒
        engine.countInBars = 2
        engine.start()
        let pressedPlayAt = try #require(engine.playStartedAt)
        try await spin(0.7)
        // 練習の開始はカウントインの後（練習タイマー・練習ログ・曲の練習時間もここから）
        let practiceStartedAt = try #require(engine.playStartedAt)
        #expect(practiceStartedAt.timeIntervalSince(pressedPlayAt) >= 0.4)
        #expect(engine.practiceTimerStartedAt == practiceStartedAt)
        engine.stop()
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

// MARK: - SongPracticeTracker

@Suite("SongPracticeTracker")
struct SongPracticeTrackerTests {
    private let a = UUID()
    private let b = UUID()
    private let t0 = Date(timeIntervalSinceReferenceDate: 0)

    @Test func countsTimeForTheActiveSongAndSwitches() {
        var tracker = SongPracticeTracker()
        tracker.start(a, at: t0, bpm: 100)
        tracker.switchTo(b, at: t0.addingTimeInterval(60), bpm: 100)
        #expect(tracker.unsavedSeconds(for: a, at: t0.addingTimeInterval(90)) == 60)
        #expect(tracker.unsavedSeconds(for: b, at: t0.addingTimeInterval(90)) == 30)
    }

    @Test func adoptingGivesTheUnnamedStretchToTheNewSong() {
        var tracker = SongPracticeTracker()
        tracker.start(nil, at: t0, bpm: 100)
        tracker.adopt(a, bpm: 100)
        tracker.stop(at: t0.addingTimeInterval(120))
        #expect(tracker.takePending() == [a: 120])
        #expect(tracker.takePending().isEmpty)
        #expect(tracker.activeSongID == nil)
    }

    @Test func eachSongKeepsItsOwnPeakTempo() {
        var tracker = SongPracticeTracker()
        tracker.start(a, at: t0, bpm: 100)
        tracker.notePlaying(bpm: 130)
        tracker.switchTo(b, at: t0.addingTimeInterval(60), bpm: 90)
        #expect(tracker.takePeaks() == [a: 130, b: 90])
    }

    @Test func timeWithNoSongIsNotCredited() {
        var tracker = SongPracticeTracker()
        tracker.start(nil, at: t0, bpm: 100)
        tracker.switchTo(a, at: t0.addingTimeInterval(50), bpm: 100)
        tracker.stop(at: t0.addingTimeInterval(80))
        #expect(tracker.takePending() == [a: 30])
    }
}

// MARK: - 保存形式の往復
// BeatPreset と Song は古いデータを読むために init(from:) を手書きしている。
// 項目を足したときにデコードへ書き忘れると、保存はされるのに読み戻されず、起動のたびに消える

@Suite("Codable round trip")
struct CodableRoundTripTests {
    @Test func beatPresetKeepsEveryField() throws {
        let preset = BeatPreset(beats: 7, accents: [0, 2, 4], rests: [6])
        let decoded = try JSONDecoder().decode(BeatPreset.self, from: JSONEncoder().encode(preset))
        #expect(decoded == preset)
    }

    @Test func songKeepsEveryField() throws {
        var song = Song(
            name: "Etude", bpm: 132, pattern: BeatPreset(beats: 3, accents: [0], rests: [2]), subdivision: .triplet
        )
        song.practiceSeconds = 4_321
        song.bestBPM = 152
        let decoded = try JSONDecoder().decode(Song.self, from: JSONEncoder().encode(song))
        #expect(decoded == song)
    }
}

// MARK: - StoredSettings

@Suite("StoredSettings")
struct StoredSettingsTests {
    @Test func readsAndValidatesSavedValues() {
        let store = InMemorySettingsStore()
        store.set(999.0, forKey: "pulstick.bpm")          // 範囲外 → 丸める
        store.set(5, forKey: "pulstick.beats")
        store.set([-1, 0, 3, 9], forKey: "pulstick.accents")  // 範囲外の拍は捨てる
        store.set([4], forKey: "pulstick.rests")
        store.set(1.5, forKey: "pulstick.accentVolume")
        store.set(3, forKey: "pulstick.subdivision")
        store.set("wood", forKey: "pulstick.clickSound")
        store.set(true, forKey: "pulstick.gapTrainerEnabled")
        let stored = StoredSettings(reading: store)
        #expect(stored.bpm == 300)
        #expect(stored.beatsPerMeasure == 5)
        #expect(stored.accentBeats == [0, 3])
        #expect(stored.restBeats == [4])
        #expect(stored.accentVolume == 1)
        #expect(stored.subdivision == .triplet)
        #expect(stored.clickSound == .wood)
        #expect(stored.gapTrainerEnabled)
    }

    @Test func countInSetterStaysInRange() {
        let engine = makeEngine()
        engine.countInBars = -1
        #expect(engine.countInBars == 0)
        engine.countInBars = 9
        #expect(engine.countInBars == PulstickEngine.countInRange.upperBound)
    }

    @Test func countInIsRememberedAndKeptInRange() {
        let store = InMemorySettingsStore()
        store.set(9, forKey: "pulstick.countInBars")
        #expect(StoredSettings(reading: store).countInBars == PulstickEngine.countInRange.upperBound)
    }

    @Test func aSelectionWithoutItsSongIsDropped() {
        let store = InMemorySettingsStore()
        store.set(UUID().uuidString, forKey: "pulstick.selectedSong")
        #expect(StoredSettings(reading: store).selectedSongID == nil)
    }

    @Test func nonFiniteTempoFallsBackToTheDefault() {
        let store = InMemorySettingsStore()
        store.set(Double.nan, forKey: "pulstick.bpm")
        #expect(StoredSettings(reading: store).bpm == 120)
    }
}

/// 書き込みを数える設定ストア
final class CountingSettingsStore: SettingsStore {
    private let backing = InMemorySettingsStore()
    private(set) var writes = 0
    func object(forKey key: String) -> Any? { backing.object(forKey: key) }
    func set(_ value: Any?, forKey key: String) {
        writes += 1
        backing.set(value, forKey: key)
    }
}

@Suite("Launch")
struct LaunchTests {
    @Test func launchingDoesNotWriteSettingsBack() {
        // 前回の設定を一通り保存しておく
        let store = CountingSettingsStore()
        let first = PulstickEngine(defaults: store, output: SilentClickOutput())
        first.bpm = 132
        first.setBeats(3)
        first.subdivision = .eighth
        first.accentVolume = 0.5
        first.saveCurrentAsSong(named: "Waltz")
        first.speedTrainerEnabled = true
        let before = store.writes
        _ = PulstickEngine(defaults: store, output: SilentClickOutput())
        #expect(store.writes == before)  // 復元で保存し直さない
    }
}

// MARK: - TickPlan

@Suite("TickPlan")
struct TickPlanTests {
    private func beat(_ index: Int, starts: Bool = false, rest: Bool = false, click: ClickKind = .normal) -> Tick {
        Tick(beat: index, click: click, startsMeasure: starts, isRest: rest)
    }

    @Test func countInSoundsEveryBeatEvenRestsWithTheDownbeatAccented() {
        // 小節の区切りが分かるよう頭だけ強拍。弱拍の音なので強拍の音量を 0 にしていても聞こえる
        let other = TickPlan.plan(for: beat(1, rest: true), measureIndex: -1, countsMeasure: true, gap: nil, muted: false)
        #expect(other == TickPlan(sound: .normal, isCountingIn: true))
        let downbeat = TickPlan.plan(for: beat(0, starts: true, rest: true), measureIndex: -1, countsMeasure: true, gap: nil, muted: false)
        #expect(downbeat == TickPlan(sound: .accent, isCountingIn: true))
    }

    @Test func countInUsesAnAudibleSoundWhenOneVolumeIsZero() {
        // 弱拍の音量が 0 なら全部強拍、強拍の音量が 0 なら全部弱拍で鳴らす
        let accentOnly = TickPlan.CountInSounds(accentVolume: 1, normalVolume: 0)
        #expect(TickPlan.plan(for: beat(1), measureIndex: -1, countsMeasure: true, gap: nil, muted: false, countIn: accentOnly).sound == .accent)
        let normalOnly = TickPlan.CountInSounds(accentVolume: 0, normalVolume: 1)
        #expect(TickPlan.plan(for: beat(0, starts: true), measureIndex: -1, countsMeasure: true, gap: nil, muted: false, countIn: normalOnly).sound == .normal)
    }

    @Test func theCountInFollowsVolumesRestoredAtLaunch() {
        // 弱拍を 0 にしたまま終了しても、次の起動直後の再生から聞こえる音でカウントインする
        let defaults = InMemorySettingsStore()
        let first = PulstickEngine(defaults: defaults, output: SilentClickOutput())
        first.normalVolume = 0
        let second = PulstickEngine(defaults: defaults, output: SilentClickOutput())
        #expect(second.timerQueue.sync { second.activeCountIn } == TickPlan.CountInSounds(accentVolume: second.accentVolume, normalVolume: 0))
    }

    @Test func theTempoSetDuringTheCountInBecomesTheSessionStart() {
        // カウントイン中にテンポを直したら、↶ で戻る先はその値
        let engine = makeEngine()
        engine.countInBars = 1
        engine.bpm = 120
        engine.start()
        engine.bpm = 140
        engine.practiceDidBegin()
        #expect(engine.sessionStartBPM == 140)
        engine.stop()
    }

    @Test func countInSkipsSubdivisionsAndRespectsMute() {
        #expect(TickPlan.plan(for: beat(0, click: .subdivision), measureIndex: -1, countsMeasure: true, gap: nil, muted: false).sound == nil)
        #expect(TickPlan.plan(for: beat(0, starts: true), measureIndex: -1, countsMeasure: true, gap: nil, muted: true).sound == nil)
    }

    @Test func enteringTheFirstPracticeBarIsNotACompletedBar() {
        let plan = TickPlan.plan(for: beat(0, starts: true, click: .accent), measureIndex: 0, countsMeasure: true, gap: nil, muted: false)
        #expect(plan == TickPlan(sound: .accent))
    }

    @Test func enteringTheSecondPracticeBarCompletesOne() {
        let plan = TickPlan.plan(for: beat(0, starts: true, click: .accent), measureIndex: 1, countsMeasure: true, gap: nil, muted: false)
        #expect(plan == TickPlan(sound: .accent, completesPracticeMeasure: true))
    }

    @Test func restsAndSilentBarsDoNotSound() {
        #expect(TickPlan.plan(for: beat(2, rest: true), measureIndex: 0, countsMeasure: true, gap: nil, muted: false).sound == nil)
        let gap = GapTrainer(playBars: 1, muteBars: 1)
        let silent = TickPlan.plan(for: beat(0, starts: true), measureIndex: 1, countsMeasure: true, gap: gap, muted: false)
        #expect(silent.sound == nil)
        #expect(silent.isSilentBar)
    }
}
