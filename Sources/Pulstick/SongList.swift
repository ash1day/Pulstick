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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Songs")
                .font(.system(size: 13, weight: .semibold))

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

    private var rows: some View {
        VStack(spacing: 2) {
            ForEach(engine.songs) { song in
                row(song)
            }
        }
    }

    private func row(_ song: Song) -> some View {
        let isCurrent = engine.currentSong?.id == song.id
        let practised = engine.practiceSeconds(for: song)
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: song.name)
                    .font(.system(size: 12, weight: isCurrent ? .semibold : .regular))
                    .lineLimit(1)
                    .truncationMode(.tail)
                // 曲ごとの練習量。1 分未満は出さない
                if practised >= 60 {
                    Text("Practised \(PracticeTime.format(practised))")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            Text("♩=\(Int(song.bpm)) · \(song.pattern.beats) beats")
                .font(.system(size: 11, design: .rounded))
                .monospacedDigit()
                .foregroundColor(.secondary)
                .lineLimit(1)
                .fixedSize()
            Button {
                engine.deleteSong(song)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.secondary)
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Delete")
            .accessibilityLabel(Text("Delete \(song.name)"))
            .pointingHandCursor()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .chip(selected: isCurrent, outlined: false)
        .accessibleTap(Text(verbatim: song.name), value: Text("\(Int(song.bpm)) BPM"), selected: isCurrent) {
            engine.applySong(song)
            dismiss()
        }
        // セットリストの順番を入れ替える
        .contextMenu {
            Button("Move Up") { engine.moveSong(song, by: -1) }
                .disabled(song.id == engine.songs.first?.id)
            Button("Move Down") { engine.moveSong(song, by: 1) }
                .disabled(song.id == engine.songs.last?.id)
        }
    }

    private func save() {
        engine.saveCurrentAsSong(named: newName)
        newName = ""
    }
}
