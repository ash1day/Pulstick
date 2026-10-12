import PulstickCore
import SwiftUI

/// ポップオーバーの中身。各セクションは別ファイルのビューに分けてあり、
/// 拍ごとに変わる BeatClock を購読するのは BeatIndicator と BPMDisplay だけ
struct PulstickView: View {
    @ObservedObject var engine: PulstickEngine
    /// スナップショット時は nil
    let hotKeys: GlobalHotKeys?
    @State private var isEditingBPM: Bool
    @State private var isShowingSongs = false

    /// - Parameter isEditingBPM: テストで「BPM を入力中」の状態から始めるときだけ true を渡す
    init(engine: PulstickEngine, hotKeys: GlobalHotKeys?, isEditingBPM: Bool = false) {
        self.engine = engine
        self.hotKeys = hotKeys
        _isEditingBPM = State(initialValue: isEditingBPM)
    }

    var body: some View {
        VStack(spacing: 14) {
            BeatIndicator(engine: engine, clock: engine.beatClock)
            // 数字・スライダー・曲の呼び出しを 1 つのテンポのまとまりとして見せる
            VStack(spacing: 8) {
                BPMDisplay(engine: engine, clock: engine.beatClock, isEditing: $isEditingBPM)
                    .frame(maxWidth: .infinity)
                    .overlay(alignment: .trailing) {
                        SongListButton(engine: engine, isShowingList: $isShowingSongs)
                    }
                BPMSlider(engine: engine)
            }
            PresetPicker(engine: engine)
            SegmentedPicker(Text("Subdivision"), items: Subdivision.allCases, selection: engine.subdivision, label: \.label) { sub in
                SubdivisionGlyph(subdivision: sub)
                    .font(.system(size: 12, weight: .medium))
            } onSelect: { engine.subdivision = $0 }
            VStack(spacing: 6) {
                SpeedTrainerSection(engine: engine)
                GapTrainerSection(engine: engine)
            }
            TransportRow(engine: engine, hotKeys: hotKeys)
            Divider()
            VStack(spacing: 8) {
                VolumeRow(engine: engine)
                SegmentedPicker(Text("Click sound"), items: ClickSound.allCases, selection: engine.clickSound, label: \.name) { sound in
                    sound.name
                        .font(.system(size: 11, weight: .medium))
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
        ShortcutButtons(engine: engine, presetCount: engine.presets.count)
            .disabled(isEditingBPM || isShowingSongs)
    }

    /// ショートカットを起こしたキー入力の修飾キー。キー入力の処理中でなければ（古いイベントやキーボードの
    /// 実際の状態を拾わないよう）修飾なしとみなす
    static func currentModifiers() -> EventModifiers {
        guard let event = NSApp?.currentEvent, event.type == .keyDown else { return [] }
        var modifiers: EventModifiers = []
        let flags = event.modifierFlags
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.command) { modifiers.insert(.command) }
        return modifiers
    }
}

/// ショートカットを受ける見えないボタン。エンジンを購読しないので、テンポのドラッグなどで
/// ポップオーバーが再描画されても、プリセットの数が変わらない限り作り直されない
private struct ShortcutButtons: View {
    let engine: PulstickEngine
    let presetCount: Int

    var body: some View {
        let bindings = PopoverShortcut.all(presetCount: presetCount).flatMap(\.bindings)
        ZStack {
            ForEach(bindings.indices, id: \.self) { index in
                let binding = bindings[index]
                Button("") { binding.action(engine, PulstickView.currentModifiers()) }
                    .keyboardShortcut(binding.key, modifiers: [])
            }
        }
        .opacity(0)
        .allowsHitTesting(false)
    }
}
