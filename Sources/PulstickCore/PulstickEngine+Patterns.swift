import Foundation

// テンポ・拍・アクセント・プリセット・曲の操作
extension PulstickEngine {
    /// 現在のテンポと拍子を曲として保存する。同じ名前（大文字小文字は区別しない）があれば上書き
    public func saveCurrentAsSong(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var song = Song(name: trimmed, bpm: bpm, pattern: currentPattern, subdivision: subdivision)
        if let index = songs.firstIndex(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            song.id = songs[index].id
            songs[index] = song
        } else {
            let index = songs.firstIndex { trimmed.localizedStandardCompare($0.name) == .orderedAscending } ?? songs.endIndex
            songs.insert(song, at: index)
        }
    }

    public func applySong(_ song: Song) {
        bpm = song.bpm
        beatsPerMeasure = song.pattern.beats.clamped(to: Self.beatsRange)
        accentBeats = validAccents(song.pattern.accents)
        subdivision = song.subdivision
        // 再生中に曲を切り替えたら、そこを新しい起点にする（↶ ボタンが前の曲のテンポに戻さないように）
        if isPlaying {
            restartSession()
        }
    }

    var currentPattern: BeatPreset {
        BeatPreset(beats: beatsPerMeasure, accents: Array(accentBeats).sorted())
    }

    /// いまのテンポをスピードトレーナーの起点にし、小節の数え直しを始める
    func restartSession() {
        sessionStartBPM = bpm
        speedTrainerProgress.restart()
    }

    /// 保存データや曲から読んだアクセント位置のうち、いまの拍数の範囲にあるものだけを残す
    func validAccents(_ accents: [Int]) -> Set<Int> {
        Set(accents.filter { (0..<beatsPerMeasure).contains($0) })
    }

    /// 曲リストで「いま使っている曲」を強調するための判定
    public func matchesCurrentSettings(_ song: Song) -> Bool {
        song.bpm == bpm && song.pattern.beats == beatsPerMeasure
            && song.pattern.accentSet == accentBeats && song.subdivision == subdivision
    }

    public func deleteSong(_ song: Song) {
        songs.removeAll { $0.id == song.id }
    }

    public func applyPreset(at index: Int) {
        guard index < presets.count else { return }
        let preset = presets[index]
        beatsPerMeasure = preset.beats
        accentBeats = preset.accentSet
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
        beatsPerMeasure -= 1
        if beatClock.current >= beatsPerMeasure {
            beatClock.current = 0
        }
    }

    public func toggleAccent(_ beat: Int) {
        if accentBeats.contains(beat) {
            accentBeats.remove(beat)
        } else {
            accentBeats.insert(beat)
        }
    }
}
