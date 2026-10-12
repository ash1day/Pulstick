import PulstickCore
import SwiftUI

/// 3 本の segmented track で区画の高さをそろえ、縦のリズムを整える
private let segmentHeight: CGFloat = 26

/// 各プリセットを小さな○で表現。強拍は大きめ・不透明、弱拍は小さめ・薄め。
/// 右クリックで「現在のパターンで上書き」または「デフォルトに戻す」が可能。
struct PresetPicker: View {
    @ObservedObject var engine: PulstickEngine

    var body: some View {
        HStack(spacing: 2) {
            ForEach(engine.presets.indices, id: \.self) { index in
                presetButton(index)
            }
        }
        .segmentedTrack(Text("Presets"))
    }

    private func presetButton(_ index: Int) -> some View {
        let preset = engine.presets[index]
        let selected = engine.matchesCurrentPattern(preset)
        // 拍数が多いプリセットはボタン幅に収まるよう○を小さくする
        let dense = preset.beats > 6
        let accentSize: CGFloat = dense ? 5 : 7
        let normalSize: CGFloat = dense ? 3.5 : 5
        return HStack(spacing: dense ? 1.5 : 2) {
            ForEach(0..<preset.beats, id: \.self) { i in
                let isAccent = preset.accents.contains(i)
                let isRest = preset.rests.contains(i)
                Circle()
                    .fill(
                        isRest ? Color.clear
                            : isAccent
                            ? (selected ? Color.accentColor : Color.secondary.opacity(0.55))
                            : (selected ? Color.secondary.opacity(0.45) : Color.secondary.opacity(0.22))
                    )
                    // 休符は輪郭だけの小さな○
                    .overlay(Circle().stroke(isRest ? Color.secondary.opacity(selected ? 0.5 : 0.3) : .clear, lineWidth: 0.8))
                    .frame(width: isAccent ? accentSize : normalSize, height: isAccent ? accentSize : normalSize)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: segmentHeight)
        .segment(selected: selected)
        .accessibleTap(Text("Preset \(index + 1)"), value: Text("\(preset.beats) beats"), selected: selected) {
            engine.applyPreset(at: index)
        }
        .help("Preset \(index + 1) (key \(index + 1)) · right-click to save or reset")
        .contextMenu {
            Button("Save Current Pattern Here") {
                engine.saveCurrentAsPreset(at: index)
            }
            Button("Reset to Default") {
                engine.resetPreset(at: index)
            }
        }
    }
}

/// 選択中の1つがハイライトされる横並びのチップ。細分化や音色の選択に使う
struct ChipPicker<Item: Hashable, Content: View>: View {
    /// VoiceOver で読み上げるグループ名
    let title: Text
    let items: [Item]
    let selection: Item
    /// ツールチップと VoiceOver で読み上げる名前
    let label: KeyPath<Item, Text>
    @ViewBuilder let content: (Item) -> Content
    let onSelect: (Item) -> Void

    init(
        _ title: Text, items: [Item], selection: Item, label: KeyPath<Item, Text>,
        @ViewBuilder content: @escaping (Item) -> Content, onSelect: @escaping (Item) -> Void
    ) {
        self.title = title
        self.items = items
        self.selection = selection
        self.label = label
        self.content = content
        self.onSelect = onSelect
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items, id: \.self) { item in
                let selected = item == selection
                content(item)
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity)
                    .frame(height: segmentHeight)
                    .segment(selected: selected)
                    .accessibleTap(item[keyPath: label], selected: selected) { onSelect(item) }
                    .help(item[keyPath: label])
            }
        }
        .segmentedTrack(title)
    }
}

/// 細分の記号。3 連符は 8 分音符 3 つと見分けられるよう、譜面と同じく小さな「3」を添える
struct SubdivisionGlyph: View {
    let subdivision: Subdivision

    var body: some View {
        Text(subdivision.symbol)
            .tracking(-2)
            .overlay(alignment: .top) {
                if subdivision == .triplet {
                    Text(verbatim: "3")
                        .font(.system(size: 8, weight: .semibold, design: .rounded))
                        .offset(y: -7)
                }
            }
    }
}

extension Subdivision {
    var symbol: String {
        switch self {
        case .quarter: "♩"
        case .eighth: "♪♪"
        case .triplet: "♪♪♪"
        case .sixteenth: "♪♪♪♪"
        }
    }

    var label: Text {
        switch self {
        case .quarter: Text("Quarter notes (no subdivision)")
        case .eighth: Text("Eighth notes")
        case .triplet: Text("Triplets")
        case .sixteenth: Text("Sixteenth notes")
        }
    }
}

extension ClickSound {
    var name: Text {
        switch self {
        case .beep: Text("Beep")
        case .wood: Text("Wood")
        case .tick: Text("Tick")
        }
    }
}
