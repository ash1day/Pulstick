import Foundation

// テンポ・拍・アクセント・プリセット・曲の操作
extension PulstickEngine {
    /// 現在のテンポと拍子を曲として保存する。同じ名前（大文字小文字は区別しない）があれば上書き
    public func saveCurrentAsSong(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var song = Song(name: trimmed, bpm: bpm, pattern: currentPattern, subdivision: subdivision)
        if let index = songs.firstIndex(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            // 同じ曲の設定を更新するだけなので、識別子と練習時間は引き継ぐ
            song.id = songs[index].id
            song.practiceSeconds = songs[index].practiceSeconds
            songs[index] = song
        } else {
            // セットリストとして使えるよう、名前順ではなく追加した順に並べる
            songs.append(song)
        }
    }

    public func applySong(_ song: Song) {
        bpm = song.bpm
        beatsPerMeasure = song.pattern.beats.clamped(to: Self.beatsRange)
        accentBeats = validBeatIndices(song.pattern.accents)
        restBeats = validBeatIndices(song.pattern.rests)
        subdivision = song.subdivision
        // 再生中に曲を切り替えたら、そこを新しい起点にする（↶ ボタンが前の曲のテンポに戻さないように）
        if isPlaying {
            restartSession()
            // それまでの時間は前の曲に加算し、ここからは選んだ曲として数える
            creditSongPractice()
            beginSongPractice(song.id)
        }
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

    /// 曲リストで「いま使っている曲」を強調するための判定
    public func matchesCurrentSettings(_ song: Song) -> Bool {
        song.bpm == bpm && song.pattern.beats == beatsPerMeasure
            && song.pattern.accentSet == accentBeats && song.pattern.restSet == restBeats
            && song.subdivision == subdivision
    }

    /// 曲の練習時間を数え始める（nil なら数えない）
    func beginSongPractice(_ id: UUID?) {
        activeSongID = id
        activeSongSince = id == nil ? nil : Date()
    }

    /// 数えていた曲に、ここまでの時間を加算する
    func creditSongPractice() {
        guard let id = activeSongID, let since = activeSongSince,
              let index = songs.firstIndex(where: { $0.id == id })
        else { return }
        songs[index].practiceSeconds += Date().timeIntervalSince(since)
        activeSongSince = Date()
    }

    /// セットリストの中で曲を前後に動かす。端より先には動かさない
    public func moveSong(_ song: Song, by offset: Int) {
        guard let index = songs.firstIndex(where: { $0.id == song.id }) else { return }
        let destination = (index + offset).clamped(to: 0...(songs.count - 1))
        guard destination != index else { return }
        songs.insert(songs.remove(at: index), at: destination)
    }

    /// セットリストの前後の曲を呼び出す（リハーサル中に曲を順に切り替える用途）。
    /// いまの設定がどの曲とも一致しなければ、先頭の曲から始める
    public func applyAdjacentSong(_ offset: Int) {
        guard !songs.isEmpty else { return }
        let target: Int
        if let current = songs.firstIndex(where: matchesCurrentSettings) {
            target = (current + offset).clamped(to: 0...(songs.count - 1))
        } else {
            target = 0
        }
        applySong(songs[target])
    }

    public func deleteSong(_ song: Song) {
        songs.removeAll { $0.id == song.id }
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
