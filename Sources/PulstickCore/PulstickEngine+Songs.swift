import Foundation

// 曲（セットリスト）の保存・呼び出しと、曲ごとの練習時間
extension PulstickEngine {
    /// 現在のテンポと拍子を曲として保存し、その曲を選択中にする。
    /// 同じ名前（大文字小文字は区別しない）があれば上書きする
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
        selectedSongID = song.id
        guard isPlaying, songPractice.activeSongID != song.id else { return }
        if songPractice.activeSongID == nil {
            // どの曲でもない設定を弾いていた時間は、いま名前を付けたこの曲の練習として引き取る
            songPractice.adopt(song.id)
        } else {
            switchSongPractice(to: song.id)
        }
    }

    public func applySong(_ song: Song) {
        // 先に選択しておくと、パターンの反映時に曲の切り替えが 1 回で済む
        selectedSongID = song.id
        batchPatternChange {
            bpm = song.bpm
            beatsPerMeasure = song.pattern.beats.clamped(to: Self.beatsRange)
            accentBeats = validBeatIndices(song.pattern.accents)
            restBeats = validBeatIndices(song.pattern.rests)
            subdivision = song.subdivision
        }
        // 再生中に曲を切り替えたら、そこを新しい起点にする（↶ ボタンが前の曲のテンポに戻さないように）
        if isPlaying {
            restartSession()
            if songPractice.activeSongID != song.id {
                switchSongPractice(to: song.id)
            }
        }
    }

    public func deleteSong(_ song: Song) {
        songs.removeAll { $0.id == song.id }
        if selectedSongID == song.id { selectedSongID = nil }
        // 数えていた曲が消えたら、その時間を捨てずに、いま一致する曲へ数え直す
        if songPractice.activeSongID == song.id {
            songPractice.adoptReplacing(song.id, with: currentSong?.id)
        }
    }

    /// 設定が完全に一致するか
    public func matchesCurrentSettings(_ song: Song) -> Bool {
        song.bpm == bpm && matchesCurrentPattern(song)
    }

    /// いま使っている曲。
    /// 1. 選んだ曲の拍子と細分が変わっていなければ、その曲（テンポがトレーナーや矢印キーで上下して
    ///    別の曲の BPM と重なっても乗り換えない）
    /// 2. そうでなければ、設定が完全に一致する最初の曲
    public var currentSong: Song? {
        if let selected = songs.first(where: { $0.id == selectedSongID }), matchesCurrentPattern(selected) {
            return selected
        }
        return songs.first(where: matchesCurrentSettings)
    }

    private func matchesCurrentPattern(_ song: Song) -> Bool {
        song.pattern.beats == beatsPerMeasure && song.pattern.accentSet == accentBeats
            && song.pattern.restSet == restBeats && song.subdivision == subdivision
    }

    /// セットリストの中で曲を前後に動かす。端より先には動かさない
    public func moveSong(_ song: Song, by offset: Int) {
        guard let index = songs.firstIndex(where: { $0.id == song.id }) else { return }
        let destination = (index + offset).clamped(to: 0...(songs.count - 1))
        guard destination != index else { return }
        // 手元のコピーで動かしてから 1 回で代入し、保存と画面更新を 1 回で済ませる
        var reordered = songs
        reordered.insert(reordered.remove(at: index), at: destination)
        songs = reordered
    }

    /// セットリストの前後の曲を呼び出す（リハーサル中に曲を順に切り替える用途）。
    /// いまの曲が分からなければ先頭の曲から始める。端で押しても何もしない
    public func applyAdjacentSong(_ offset: Int) {
        guard !songs.isEmpty else { return }
        // 一致する曲がなくても、選んだ曲があればそこから動く（保存データが壊れていて一致しえない曲でも先へ進める）
        let anchor = currentSong?.id ?? selectedSongID ?? setlistAnchorID
        guard let current = songs.firstIndex(where: { $0.id == anchor }) else {
            applySong(songs[0])
            return
        }
        let target = (current + offset).clamped(to: 0...(songs.count - 1))
        guard target != current else { return }
        applySong(songs[target])
    }

    // MARK: - 曲ごとの練習時間
    // 数えている曲と未確定の時間は SongPracticeTracker が持つ。
    // 練習ログと同じく 5 秒未満の再生は曲にも記録しないため、短いうちは停止時まで保留する

    /// 曲の練習時間。確定済みの分に、この再生でまだ確定していない分を足して返す
    public func practiceSeconds(for song: Song) -> Double {
        song.practiceSeconds + songPractice.unsavedSeconds(for: song.id, at: now())
    }

    /// 再生中に拍子などを変えて「いまの曲」が変わったら、数える曲を切り替える
    func followCurrentSongIfPlaying() {
        guard isPlaying, currentSong?.id != songPractice.activeSongID else { return }
        switchSongPractice(to: currentSong?.id)
    }

    /// 数える曲を切り替える。再生がすでに記録に値する長さなら、それまでの分を即座に保存する
    func switchSongPractice(to id: UUID?) {
        songPractice.switchTo(id, at: now())
        if isLongEnoughToLog {
            commitSongPractice(songPractice.takePending())
        }
    }

    /// 再生中でまだ練習ログに記録していない時間のうち、今日の分。
    /// 記録と同じく 5 秒未満は数えず、日付をまたいだら今日の 0 時以降だけを数える
    public func unsavedPracticeToday(calendar: Calendar = .current) -> TimeInterval {
        guard isLongEnoughToLog, let startedAt = playStartedAt else { return 0 }
        let current = now()
        return current.timeIntervalSince(max(startedAt, calendar.startOfDay(for: current)))
    }

    var isLongEnoughToLog: Bool {
        playStartedAt.map { now().timeIntervalSince($0) >= minimumLoggedSession } ?? false
    }

    /// 停止時に呼ぶ。記録に値する長さの再生なら未確定分を曲に加え、そうでなければ捨てる
    func finishSongPractice(record: Bool) {
        songPractice.stop(at: now())
        let pending = songPractice.takePending()
        if record {
            commitSongPractice(pending)
        }
    }

    /// 時間を曲に加える。手元のコピーで足してから 1 回で代入し、保存を 1 回で済ませる
    private func commitSongPractice(_ seconds: [UUID: Double]) {
        guard !seconds.isEmpty else { return }
        var updated = songs
        for index in updated.indices {
            updated[index].practiceSeconds += seconds[updated[index].id] ?? 0
        }
        songs = updated
    }
}
