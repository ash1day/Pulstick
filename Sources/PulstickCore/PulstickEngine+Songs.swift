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
        // 鳴らしている設定に名前を付けたのなら、ここからはその曲の練習として数える
        if isPlaying, activeSongID != song.id {
            switchSongPractice(to: song.id)
        }
    }

    public func applySong(_ song: Song) {
        bpm = song.bpm
        beatsPerMeasure = song.pattern.beats.clamped(to: Self.beatsRange)
        accentBeats = validBeatIndices(song.pattern.accents)
        restBeats = validBeatIndices(song.pattern.rests)
        subdivision = song.subdivision
        selectedSongID = song.id
        // 再生中に曲を切り替えたら、そこを新しい起点にする（↶ ボタンが前の曲のテンポに戻さないように）
        if isPlaying {
            restartSession()
            switchSongPractice(to: song.id)
        }
    }

    public func deleteSong(_ song: Song) {
        songs.removeAll { $0.id == song.id }
        if selectedSongID == song.id { selectedSongID = nil }
    }

    /// 設定が完全に一致するか
    public func matchesCurrentSettings(_ song: Song) -> Bool {
        song.bpm == bpm && matchesCurrentPattern(song)
    }

    /// いま使っている曲。選んだ曲の拍子と細分が変わっていなければ、テンポが練習で上下していてもその曲とみなす。
    /// 選んでいなければ、設定が一致する最初の曲
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
        // 1 つずつ動かすので入れ替えで足りる（保存と画面更新が 1 回で済む）
        songs.swapAt(index, destination)
    }

    /// セットリストの前後の曲を呼び出す（リハーサル中に曲を順に切り替える用途）。
    /// いまの曲が分からなければ先頭の曲から始める。端で押しても何もしない
    public func applyAdjacentSong(_ offset: Int) {
        guard !songs.isEmpty else { return }
        guard let current = currentSong.flatMap({ song in songs.firstIndex { $0.id == song.id } }) else {
            applySong(songs[0])
            return
        }
        let target = (current + offset).clamped(to: 0...(songs.count - 1))
        guard target != current else { return }
        applySong(songs[target])
    }

    // MARK: - 曲ごとの練習時間
    // 再生中は「数えている曲」と開始時刻だけを持ち、加算は停止時にまとめて確定する。
    // 練習ログと同じく、5 秒未満の再生は曲にも記録しないため

    /// 曲の練習時間。確定済みの分に、この再生でまだ確定していない分を足して返す
    public func practiceSeconds(for song: Song) -> Double {
        var total = song.practiceSeconds + (pendingSongSeconds[song.id] ?? 0)
        if song.id == activeSongID, let since = activeSongSince {
            total += Date().timeIntervalSince(since)
        }
        return total
    }

    /// 曲の練習時間を数え始める（nil なら数えない）
    func beginSongPractice(_ id: UUID?) {
        activeSongID = id
        activeSongSince = id == nil ? nil : Date()
    }

    /// ここまでの時間を、数えていた曲の未確定分に積み、別の曲を数え始める
    func switchSongPractice(to id: UUID?) {
        if let current = activeSongID, let since = activeSongSince {
            pendingSongSeconds[current, default: 0] += Date().timeIntervalSince(since)
        }
        beginSongPractice(id)
    }

    /// 停止時に呼ぶ。記録に値する長さの再生なら未確定分を曲に加え、そうでなければ捨てる
    func finishSongPractice(record: Bool) {
        switchSongPractice(to: nil)
        if record {
            for index in songs.indices {
                if let seconds = pendingSongSeconds[songs[index].id] {
                    songs[index].practiceSeconds += seconds
                }
            }
        }
        pendingSongSeconds = [:]
    }
}
