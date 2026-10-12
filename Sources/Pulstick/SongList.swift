import PulstickCore
import SwiftUI

/// 曲ごとのテンポと拍子を保存・呼び出すリスト。
/// バンドのセットリストや、教室で曲ごとに指定されたテンポを素早く切り替える用途
struct SongListButton: View {
    @ObservedObject var engine: PulstickEngine
    @Binding var isShowingList: Bool

    var body: some View {
        Button {
            isShowingList.toggle()
        } label: {
            Image(systemName: "music.note.list")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Songs: save and recall tempos")
        .accessibilityLabel(Text("Songs"))
        .pointingHandCursor()
        .popover(isPresented: $isShowingList, arrowEdge: .bottom) {
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
                Text("Save the current tempo and beat pattern under a song name to recall it with one click.")
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
        let isCurrent = engine.matchesCurrentSettings(song)
        return HStack(spacing: 8) {
            Text(verbatim: song.name)
                .font(.system(size: 12, weight: isCurrent ? .semibold : .regular))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
            Text("♩=\(Int(song.bpm)) · \(song.beats) beats")
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
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(isCurrent ? Color.accentColor.opacity(0.15) : Color.clear)
        )
        .accessibleTap(Text(verbatim: song.name), value: Text("\(Int(song.bpm)) BPM"), selected: isCurrent) {
            engine.applySong(song)
            dismiss()
        }
        .pointingHandCursor()
    }

    private func save() {
        engine.saveCurrentAsSong(named: newName)
        newName = ""
    }
}
