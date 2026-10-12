import PulstickCore
import SwiftUI

/// ポップオーバーの中身。各セクションは別ファイルのビューに分けてあり、
/// 拍ごとに変わる BeatClock を購読するのは BeatIndicator と BPMDisplay だけ
struct PulstickView: View {
    @ObservedObject var engine: PulstickEngine
    /// スナップショット時は nil
    let hotKeys: GlobalHotKeys?
    @State private var isEditingBPM = false
    @State private var isShowingSongs = false

    var body: some View {
        VStack(spacing: 14) {
            BeatIndicator(engine: engine, clock: engine.beatClock)
            BPMDisplay(engine: engine, clock: engine.beatClock, isEditing: $isEditingBPM)
                .frame(maxWidth: .infinity)
                .overlay(alignment: .topTrailing) {
                    SongListButton(engine: engine, isShowingList: $isShowingSongs)
                }
            BPMSlider(engine: engine)
            PresetPicker(engine: engine)
            ChipPicker(Subdivision.allCases, selection: engine.subdivision, label: \.label) { sub in
                Text(sub.symbol)
                    .font(.system(size: 12, weight: .medium))
                    .tracking(-2)
                    .padding(.vertical, 5)
            } onSelect: { engine.subdivision = $0 }
            VStack(spacing: 6) {
                SpeedTrainerSection(engine: engine)
                GapTrainerSection(engine: engine)
            }
            TransportRow(engine: engine, hotKeys: hotKeys)
            Divider()
            VStack(spacing: 8) {
                VolumeRow(engine: engine)
                ChipPicker(ClickSound.allCases, selection: engine.clickSound, label: \.name) { sound in
                    sound.name
                        .font(.system(size: 11, weight: .medium))
                        .padding(.vertical, 3)
                } onSelect: { sound in
                    engine.clickSound = sound
                    engine.previewClick()
                }
            }
            PracticeSummary(engine: engine)
            FooterRow(engine: engine, hotKeys: hotKeys)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(width: 320)
        .background(keyboardShortcuts)
    }

    // MARK: - Keyboard Shortcuts
    // 楽器を持ったまま操作できるよう、ポップオーバーを開いていればキーだけで主要操作ができる。
    // BPM 入力中や、曲名を入力できる子ポップオーバーを開いている間は、
    // スペースや文字キーをテキスト入力に譲るため無効化する

    private var keyboardShortcuts: some View {
        let bindings = PopoverShortcut.all(presetCount: engine.presets.count).flatMap(\.bindings)
        return ZStack {
            ForEach(bindings.indices, id: \.self) { index in
                let binding = bindings[index]
                Button("") { binding.action(engine) }
                    .keyboardShortcut(binding.key, modifiers: binding.modifiers)
            }
        }
        .opacity(0)
        .allowsHitTesting(false)
        .disabled(isEditingBPM || isShowingSongs)
    }
}
