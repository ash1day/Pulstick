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
            // 同じ曲の設定を更新するだけなので、識別子と練習の記録は引き継ぐ
            song.id = songs[index].id
            song.practiceSeconds = songs[index].practiceSeconds
            song.bestBPM = songs[index].bestBPM
            songs[index] = song
        } else {
            // セットリストとして使えるよう、名前順ではなく追加した順に並べる
            songs.append(song)
        }
        selectedSongID = song.id
        selectedSongIsTentative = false
        guard isPlaying, songPractice.activeSongID != song.id else { return }
        // どの曲でもない設定を弾いていた時間は、いま名前を付けたこの曲の練習として引き取る。
        // 別の曲を数えていたなら、そこで区切ってこの曲に切り替える
        if !songPractice.adopt(song.id, bpm: bpm) {
            switchSongPractice(to: song.id)
        }
    }

    public func applySong(_ song: Song) {
        applySong(song, tempoPercent: 100)
    }

    /// 曲を呼び出す。tempoPercent を指定すると、本来のテンポの何 % で練習するかを選べる
    /// （難しい曲を 70〜80% から始める定番の練習法。拍子は同じなので、その曲の練習として数える）
    public func applySong(_ song: Song, tempoPercent: Int) {
        // 先に選択しておくと、パターンの反映時に曲の切り替えが 1 回で済む
        selectedSongID = song.id
        selectedSongIsTentative = false
        batchPatternChange {
            // テンポも一括変更の中で決める。先に本来のテンポを入れると、再生中はそれが最高テンポに記録されてしまう
            bpm = (song.bpm * Double(tempoPercent) / 100).rounded()
            applyPattern(song.pattern)
            subdivision = song.subdivision
        }
        // 再生中に曲を切り替えたら、そこを新しい起点にする（↶ ボタンが前の曲のテンポに戻さないように）
        if isPlaying {
            restartSession()
            // 通常はパターンの反映時（followCurrentSongIfPlaying）に切り替わっている。
            // 保存データが壊れていて反映時に値が丸められ、曲と一致しなくなった場合のための念押し
            if songPractice.activeSongID != song.id {
                switchSongPractice(to: song.id)
            }
        }
    }

    /// 本来のテンポの percent % から始め、スピードトレーナーで曲のテンポまで上げていく。
    /// 難しい曲を「遅く始めて、慣れたら本来のテンポへ」と練習する流れを 1 回の操作で用意する。
    /// スピードトレーナーの目標はこの曲のテンポに書き換わる。繰り返しモードなら 70% のテンポに戻ってまた上げる
    public func rampUp(_ song: Song, fromPercent percent: Int) {
        speedTrainer.targetBPM = Int(song.bpm.rounded())
        speedTrainerEnabled = true
        applySong(song, tempoPercent: percent)
    }

    /// セットリストを共有用のテキスト（JSON）にする。バンドのメンバーに送る用途なので、
    /// 個人の練習時間や最高テンポは含めない
    public func exportSetlist() -> String {
        let shared = SharedSetlist(songs: songs.map {
            SharedSetlist.Entry(name: $0.name, bpm: $0.bpm, pattern: $0.pattern, subdivision: $0.subdivision)
        })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? encoder.encode(shared)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    /// 共有されたセットリストを取り込む。同じ名前の曲は設定を上書きし（練習の記録は残す）、新しい曲は末尾に足す。
    /// Pulstick のセットリストとして読めなければ何も変えずに nil を返す
    @discardableResult
    public func importSetlist(_ text: String) -> Int? {
        guard let data = text.data(using: .utf8),
              let shared = try? JSONDecoder().decode(SharedSetlist.self, from: data),
              shared.pulstick == SharedSetlist.version
        else { return nil }
        var updated = songs
        for entry in shared.songs {
            let name = entry.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, entry.bpm.isFinite else { continue }
            var pattern = entry.pattern
            pattern.beats = pattern.beats.clamped(to: Self.beatsRange)
            let bpm = entry.bpm.clamped(to: Self.bpmRange)
            if let index = updated.firstIndex(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
                updated[index].name = name
                updated[index].bpm = bpm
                updated[index].pattern = pattern
                updated[index].subdivision = entry.subdivision
            } else {
                updated.append(Song(name: name, bpm: bpm, pattern: pattern, subdivision: entry.subdivision))
            }
        }
        songs = updated
        return shared.songs.count
    }

    public func deleteSong(_ song: Song) {
        songs.removeAll { $0.id == song.id }
        if selectedSongID == song.id { selectedSongID = nil }
        // 数えていた曲が消えたら、その時間を捨てずに、いま一致する曲へ数え直す
        if songPractice.activeSongID == song.id {
            songPractice.adoptReplacing(song.id, with: currentSong?.id, bpm: bpm)
        }
    }

    /// 設定が完全に一致するか
    public func matchesCurrentSettings(_ song: Song) -> Bool {
        song.bpm == bpm && matchesCurrentPattern(song)
    }

    /// いま使っている曲。
    /// 1. 選んだ曲の拍子と細分が変わっていなければ、その曲（テンポがトレーナーや矢印キーで上下して
    ///    別の曲の BPM と重なっても乗り換えない）。ただし起動時に戻した仮の選択は、設定が完全に一致するときだけ
    /// 2. そうでなければ、設定が完全に一致する最初の曲
    public var currentSong: Song? {
        if let selected = songs.first(where: { $0.id == selectedSongID }),
           selectedSongIsTentative ? matchesCurrentSettings(selected) : matchesCurrentPattern(selected)
        {
            return selected
        }
        return songs.first(where: matchesCurrentSettings)
    }

    private func matchesCurrentPattern(_ song: Song) -> Bool {
        matchesCurrentPattern(song.pattern) && song.subdivision == subdivision
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
        let anchor = currentSong?.id ?? selectedSongID
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

    /// 練習ログと曲ごとの練習時間・最高テンポを消す（新学期に付け直すときや、Mac を共有しているとき用）。
    /// 曲そのもの（テンポや拍子）は残す
    public func resetPracticeHistory() {
        // 再生中なら、それまでの分を捨ててここから数え直す（停止時に消した記録が書き戻されないように）。
        // 練習タイマーはそのまま続ける（「15 分で止める」という意図は記録の消去とは関係ないため）
        if isPlaying {
            playStartedAt = now()
            songPractice = SongPracticeTracker()
            songPractice.start(currentSong?.id, at: now(), bpm: bpm)
        }
        practiceLog = PracticeLog()
        var cleared = songs
        for index in cleared.indices {
            cleared[index].practiceSeconds = 0
            cleared[index].bestBPM = nil
        }
        songs = cleared
    }

    /// 曲の練習時間。確定済みの分に、この再生でまだ確定していない分を足して返す
    public func practiceSeconds(for song: Song) -> Double {
        song.practiceSeconds + songPractice.unsavedSeconds(for: song.id, at: now())
    }

    /// 再生中に拍子などを変えて「いまの曲」が変わったら、数える曲を切り替える
    func followCurrentSongIfPlaying() {
        guard isPlaying else { return }
        let current = currentSong?.id
        guard current != songPractice.activeSongID else { return }
        switchSongPractice(to: current)
    }

    /// 数える曲を切り替える。再生がすでに記録に値する長さなら、それまでの分を即座に保存する
    func switchSongPractice(to id: UUID?) {
        songPractice.switchTo(id, at: now(), bpm: bpm)
        if isLongEnoughToLog {
            commitSongPractice()
        }
    }

    /// 再生中でまだ練習ログに記録していない時間のうち、今日の分。
    /// 記録と同じく 5 秒未満は数えず、日付をまたいだら今日の 0 時以降だけを数える
    public func unsavedPracticeToday(calendar: Calendar = .current) -> TimeInterval {
        guard isLongEnoughToLog, let startedAt = playStartedAt else { return 0 }
        let current = now()
        return current.timeIntervalSince(max(startedAt, calendar.startOfDay(for: current)))
    }

    /// 直近 7 日（今日を含む）の練習時間。再生中でまだ記録していない今日の分も含める
    public func practiceSecondsThisWeek(calendar: Calendar = .current) -> TimeInterval {
        // 再生中の分は、日付をまたいでいても全部が直近 7 日に入る
        practiceLog.recentDays(7, endingAt: now(), calendar: calendar).reduce(0, +) + unsavedPractice()
    }

    /// 再生中でまだ練習ログに記録していない時間（記録と同じく、練習が始まって 5 秒以上たってから数える）
    public func unsavedPractice() -> TimeInterval {
        guard isLongEnoughToLog, let startedAt = playStartedAt else { return 0 }
        return now().timeIntervalSince(startedAt)
    }

    /// 練習が始まっていて（カウントイン中ではなく）、記録に値する長さを弾いているか
    var isLongEnoughToLog: Bool {
        guard practiceHasBegun, let startedAt = playStartedAt else { return false }
        return now().timeIntervalSince(startedAt) >= minimumLoggedSession
    }

    /// 停止時に呼ぶ。記録に値する長さの再生なら未確定分を曲に加え、そうでなければ捨てる
    func finishSongPractice(record: Bool) {
        songPractice.stop(at: now())
        if record {
            commitSongPractice()
        } else {
            _ = songPractice.takePending()
            _ = songPractice.takePeaks()
        }
    }

    /// 保留中の練習時間と最高テンポを曲に加える。手元のコピーで更新してから 1 回で代入し、保存を 1 回で済ませる
    private func commitSongPractice() {
        let seconds = songPractice.takePending()
        let peaks = songPractice.takePeaks()
        guard !seconds.isEmpty || !peaks.isEmpty else { return }
        var updated = songs
        for index in updated.indices {
            let id = updated[index].id
            updated[index].practiceSeconds += seconds[id] ?? 0
            if let peak = peaks[id] {
                updated[index].bestBPM = max(updated[index].bestBPM ?? 0, peak)
            }
        }
        songs = updated
    }
}
