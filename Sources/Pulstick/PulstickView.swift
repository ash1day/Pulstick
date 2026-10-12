import PulstickCore
import SwiftUI

/// ポップオーバーの中身。各セクションは別ファイルのビューに分けてあり、
/// 拍ごとに変わる BeatClock を購読するのは BeatIndicator と BPMDisplay だけ
struct PulstickView: View {
    @ObservedObject var engine: PulstickEngine
    /// スナップショット時は nil
    let hotKeys: GlobalHotKeys?
    @State private var isEditingBPM = false

    var body: some View {
        VStack(spacing: 14) {
            BeatIndicator(engine: engine, clock: engine.beatClock)
            BPMDisplay(engine: engine, clock: engine.beatClock, isEditing: $isEditingBPM)
                .frame(maxWidth: .infinity)
                .overlay(alignment: .topTrailing) {
                    SongListButton(engine: engine)
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
            FooterRow(hotKeys: hotKeys)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(width: 320)
        .background(keyboardShortcuts)
    }

    // MARK: - Keyboard Shortcuts
    // 楽器を持ったまま操作できるよう、ポップオーバーを開いていればキーだけで主要操作ができる。
    // BPM 入力中は数字キーや矢印キーをテキスト入力に譲るため無効化する

    private var keyboardShortcuts: some View {
        ZStack {
            shortcut(.upArrow) { engine.incrementBPM() }
            shortcut(.downArrow) { engine.decrementBPM() }
            shortcut(.upArrow, modifiers: .shift) { engine.incrementBPM(by: 5) }
            shortcut(.downArrow, modifiers: .shift) { engine.decrementBPM(by: 5) }
            shortcut("t") { engine.tapTempo() }
            shortcut("m") { engine.isMuted.toggle() }
            ForEach(engine.presets.indices, id: \.self) { index in
                shortcut(KeyEquivalent(Character("\(index + 1)"))) { engine.applyPreset(at: index) }
            }
        }
        .opacity(0)
        .allowsHitTesting(false)
        .disabled(isEditingBPM)
    }

    private func shortcut(_ key: KeyEquivalent, modifiers: EventModifiers = [], action: @escaping () -> Void) -> some View {
        Button("", action: action)
            .keyboardShortcut(key, modifiers: modifiers)
    }
}
