import PulstickCore
import SwiftUI

/// 曲ごとのテンポと拍子を保存・呼び出すリスト。
/// バンドのセットリストや、教室で曲ごとに指定されたテンポを素早く切り替える用途
struct SongListButton: View {
    @ObservedObject var engine: PulstickEngine
    @Binding var isShowingList: Bool

    var body: some View {
        PopoverIconButton(
            systemName: "music.note.list", size: 14, help: "Songs: save and recall tempos",
            label: Text("Songs"), isPresented: $isShowingList
        ) {
            SongList(engine: engine) { isShowingList = false }
        }
    }
}

struct SongList: View {
    @ObservedObject var engine: PulstickEngine
    let dismiss: () -> Void
    @State private var newName = ""
    /// コピー・貼り付けの結果を短く知らせる
    @State private var shareStatus: Text?
    /// ポインタが乗っている曲。削除ボタンはその行にだけ出し、練習記録ごと消える誤クリックを防ぐ
    @State private var hoveredSongID: Song.ID?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Songs")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                // バンドのメンバーとセットリストを共有する（チャットなどにテキストとして貼れる）
                shareButton("doc.on.doc", help: "Copy the setlist to share it with your band", action: copySetlist)
                    .disabled(engine.songs.isEmpty)
                shareButton("doc.on.clipboard", help: "Add songs from a setlist on the clipboard", action: pasteSetlist)
            }
            if let shareStatus {
                shareStatus
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 6) {
                TextField("Song name", text: $newName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(save)
                Button("Save", action: save)
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                    .help("Save the current tempo, beats and subdivision under this name")
            }
            .font(.system(size: 12))

            if engine.songs.isEmpty {
                Text("Save the current tempo and beat pattern under a song name to recall it with one click. Songs stay in the order you add them, like a setlist.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if engine.songs.count <= 6 {
                rows
            } else {
                // 曲が多いときだけスクロールさせ、ポップオーバーが画面より高くならないようにする
                ScrollView { rows }
                    .frame(maxHeight: 220)
            }
        }
        .padding(12)
        .frame(width: 250)
    }

    /// 再生中は練習時間が伸びていくので 30 秒ごとに描き直す。いまの曲は行ごとに探さず 1 回だけ求める
    private var rows: some View {
        TimelineView(.periodic(from: .now, by: engine.isPlaying ? 30 : 3600)) { _ in
            let currentID = engine.currentSong?.id
            VStack(spacing: 2) {
                ForEach(engine.songs) { song in
                    row(song, isCurrent: song.id == currentID)
                }
            }
        }
    }

    private func row(_ song: Song, isCurrent: Bool) -> some View {
        // 拍数、これまでに鳴らした最高テンポ、曲ごとの練習量（1 分未満は出さない）。行末が切れても目標に近い最高テンポは残る順にする
        let details = details(beats: song.pattern.beats, practised: engine.practiceSeconds(for: song), best: song.bestBPM)
        let delete = { engine.deleteSong(song) }
        return VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 8) {
                Text(verbatim: song.name)
                    .font(.system(size: 12, weight: isCurrent ? .semibold : .regular))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
                Text(verbatim: "♩=\(Int(song.bpm))")
                    .font(.system(size: 11, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .fixedSize()
                Button(action: delete) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.secondary)
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                // 行の幅が変わらないよう、消さずに透明にする（VoiceOver では行の「削除」アクションで消せる）
                .opacity(hoveredSongID == song.id ? 1 : 0)
                .help("Delete")
                .accessibilityLabel(Text("Delete \(song.name)"))
                .pointingHandCursor()
            }
            // 曲名の列は右のテンポ表記に挟まれて狭いので、曲名を削らないよう行の幅いっぱいを使う 2 行目に出す
            details
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .selectedRow(isCurrent)
        .onHover { isHovering in
            if isHovering {
                hoveredSongID = song.id
            } else if hoveredSongID == song.id {
                // 隣の行に移ったときは、先に届いた隣の行の hover を消さない
                hoveredSongID = nil
            }
        }
        // 2 行目の拍数や最高テンポも VoiceOver に届くよう、値に含める
        .accessibleTap(
            Text(verbatim: song.name),
            value: Text("\(Int(song.bpm)) BPM") + Text(verbatim: ", ") + details,
            selected: isCurrent
        ) {
            engine.applySong(song)
            dismiss()
        }
        .accessibilityAction(named: Text("Delete"), delete)
        // セットリストの順番を入れ替える
        .contextMenu {
            // 難しい曲は本来のテンポより遅く始め、慣れたら上げていく
            ForEach([70, 80, 90], id: \.self) { percent in
                Button {
                    engine.applySong(song, tempoPercent: percent)
                    dismiss()
                } label: {
                    let percentText = "\(percent)%"
                    let tempo = Int((song.bpm * Double(percent) / 100).rounded())
                    Text("Practise at \(percentText)") + Text(verbatim: " (♩=\(tempo))")
                }
            }
            Button {
                engine.rampUp(song, fromPercent: 70)
                dismiss()
            } label: {
                Text("Ramp Up from 70% to ♩=\(Int(song.bpm))")
            }
            .help("Start at 70% of the tempo and let the speed trainer raise it to the song's tempo")
            Divider()
            // リハで「少し速くしよう」と決めたテンポを、曲名を打ち直さずにこの曲へ残す（練習の記録は引き継ぐ）
            Button("Update with Current Settings") { engine.saveCurrentAsSong(named: song.name) }
            Divider()
            Button("Move Up") { engine.moveSong(song, by: -1) }
                .disabled(song.id == engine.songs.first?.id)
            Button("Move Down") { engine.moveSong(song, by: 1) }
                .disabled(song.id == engine.songs.last?.id)
            Divider()
            Button("Delete", role: .destructive, action: delete)
        }
    }

    private func details(beats: Int, practised: Double, best: Double?) -> Text {
        let time = practised >= 60 ? Text("Practised \(PracticeTime.format(practised))") : nil
        let peak = best.map { Text("Best ♩=\(Int($0))") }
        return [peak, time].compactMap { $0 }.reduce(Text("\(beats) beats")) { $0 + Text(verbatim: " · ") + $1 }
    }

    private func shareButton(_ symbol: String, help: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .frame(width: 20, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(Text(help))
        .pointingHandCursor()
    }

    private func copySetlist() {
        // 書き出せなかったときは、クリップボードを空にせず失敗を伝える
        guard let text = engine.exportSetlist() else {
            shareStatus = Text("Couldn't copy the setlist")
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        shareStatus = Text("Songs copied: \(engine.songs.count)")
    }

    private func pasteSetlist() {
        switch engine.importSetlist(NSPasteboard.general.string(forType: .string) ?? "") {
        case .imported(let count): shareStatus = Text("Songs added or updated: \(count)")
        case .notASetlist: shareStatus = Text("No Pulstick setlist on the clipboard")
        case .needsNewerVersion: shareStatus = Text("This setlist needs a newer version of Pulstick")
        }
    }

    private func save() {
        engine.saveCurrentAsSong(named: newName)
        newName = ""
    }
}
