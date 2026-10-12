import PulstickCore
import ServiceManagement
import SwiftUI

struct PulstickView: View {
    @ObservedObject var engine: PulstickEngine
    /// スナップショット時は nil
    let hotKeys: GlobalHotKeys?
    @State private var pulseScale: CGFloat = 1.0
    @State private var pulseOpacity: Double = 0.0
    @State private var isEditingBPM = false
    @State private var bpmDraft = ""
    @FocusState private var bpmFieldFocused: Bool

    var body: some View {
        VStack(spacing: 14) {
            beatIndicator
            bpmDisplay
            bpmSlider
            timeSignaturePicker
            subdivisionPicker
            VStack(spacing: 6) {
                SpeedTrainerSection(engine: engine)
                GapTrainerSection(engine: engine)
            }
            controlsRow
            Divider()
            volumeControls
            footerRow
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(width: 320)
        .background(keyboardShortcuts)
        .onChange(of: engine.currentBeat) {
            triggerPulse()
        }
    }

    // MARK: - Keyboard Shortcuts
    // 楽器を持ったまま操作できるよう、ポップオーバーを開いていればキーだけで主要操作ができる。
    // BPM 入力中は数字キーや矢印キーをテキスト入力に譲るため無効化する

    private var keyboardShortcuts: some View {
        ZStack {
            shortcut(.upArrow) { engine.incrementBPM() }
            shortcut(.downArrow) { engine.decrementBPM() }
            shortcut(.upArrow, modifiers: .shift) { engine.bpm += 5 }
            shortcut(.downArrow, modifiers: .shift) { engine.bpm -= 5 }
            shortcut("t") { engine.tapTempo() }
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

    // MARK: - Beat Indicator
    // 強（アクセント）: 塗りつぶし円・オレンジ、弱: 輪郭のみ・グレー。
    // タップで強弱を切り替え。−/＋ボタンで拍を削除・追加。

    private var beatIndicator: some View {
        HStack(spacing: 4) {
            Button {
                engine.removeBeat()
            } label: {
                Image(systemName: "minus.circle")
                    .font(.system(size: 15))
                    .foregroundColor(engine.beatsPerMeasure > 1 ? .secondary : .secondary.opacity(0.25))
            }
            .buttonStyle(.plain)
            .disabled(engine.beatsPerMeasure <= 1)
            .help("Remove a beat")
            .pointingHandCursor()

            // 16拍でもスクロールせず全拍が見えるよう、幅に合わせて○を縮める
            GeometryReader { geo in
                let count = CGFloat(engine.beatsPerMeasure)
                let slot = min(26, geo.size.width / count)
                let diameter = max(8, min(20, slot - 6))
                HStack(spacing: 0) {
                    ForEach(0..<engine.beatsPerMeasure, id: \.self) { beat in
                        beatDot(beat: beat, diameter: diameter)
                            .frame(width: slot, height: geo.size.height)
                            .contentShape(Rectangle())
                            .pointingHandCursor()
                            .onTapGesture {
                                engine.toggleAccent(beat)
                            }
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .help("Click a beat to toggle its accent")

            Button {
                engine.addBeat()
            } label: {
                Image(systemName: "plus.circle")
                    .font(.system(size: 15))
                    .foregroundColor(engine.beatsPerMeasure < 16 ? .secondary : .secondary.opacity(0.25))
            }
            .buttonStyle(.plain)
            .disabled(engine.beatsPerMeasure >= 16)
            .help("Add a beat")
            .pointingHandCursor()
        }
        .frame(height: 44)
    }

    private func beatDot(beat: Int, diameter: CGFloat) -> some View {
        let isAccent = engine.accentBeats.contains(beat)
        let isCurrent = engine.isPlaying && engine.currentBeat == beat
        return ZStack {
            Circle()
                .fill(isAccent
                      ? (isCurrent ? Color.orange : Color.orange.opacity(0.55))
                      : (isCurrent ? Color.accentColor.opacity(0.25) : Color.clear))
            Circle()
                .stroke(
                    isAccent
                        ? Color.clear
                        : (isCurrent ? Color.accentColor : Color.secondary.opacity(0.35)),
                    lineWidth: 1.5
                )
        }
        .frame(width: diameter, height: diameter)
        // 無音小節中は拍の表示だけ進め、音が鳴っていないことを薄さで示す
        .opacity(engine.isInSilentBar ? 0.35 : 1)
        .scaleEffect(isCurrent ? 1.25 : 1.0)
        .animation(.easeOut(duration: 0.1), value: engine.currentBeat)
    }

    // MARK: - BPM Display
    // ビートごとにリング状のパルスアニメーションが拡大→フェードアウトする。
    // 数字をクリックすると直接入力できる（スライダーで 40→180 を探すのは手間なため）

    private var bpmDisplay: some View {
        ZStack {
            Circle()
                .stroke(Color.accentColor.opacity(pulseOpacity), lineWidth: 2)
                .frame(width: 80, height: 80)
                .scaleEffect(pulseScale)

            VStack(spacing: 0) {
                if isEditingBPM {
                    TextField("", text: $bpmDraft)
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .multilineTextAlignment(.center)
                        .textFieldStyle(.plain)
                        .frame(width: 90, height: 38)
                        .focused($bpmFieldFocused)
                        .onSubmit(commitBPMDraft)
                        .onExitCommand { isEditingBPM = false }
                        .onChange(of: bpmFieldFocused) {
                            if !bpmFieldFocused { commitBPMDraft() }
                        }
                } else {
                    Text("\(Int(engine.bpm))")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .frame(height: 38)
                        .contentShape(Rectangle())
                        .onTapGesture(perform: beginEditingBPM)
                        .help("Click to type a tempo")
                        .pointerStyle(.horizontalText)
                }
                Group {
                    if engine.isInSilentBar {
                        Label("Silent bar · keep counting", systemImage: "speaker.slash.fill")
                    } else {
                        Text("\(TempoMarking.name(for: engine.bpm)) · BPM")
                    }
                }
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(.secondary)
            }
        }
        .frame(height: 84)
    }

    private func beginEditingBPM() {
        bpmDraft = "\(Int(engine.bpm))"
        isEditingBPM = true
        bpmFieldFocused = true
    }

    private func commitBPMDraft() {
        guard isEditingBPM else { return }
        if let value = Double(bpmDraft.trimmingCharacters(in: .whitespaces)) {
            engine.bpm = value.rounded()
        }
        isEditingBPM = false
    }

    // MARK: - BPM Slider
    // macOS 標準の Slider はトラックが二重描画されるバグがあるため、
    // CustomSlider で独自描画している

    private var bpmSlider: some View {
        HStack(spacing: 8) {
            Button {
                engine.decrementBPM()
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.bordered)
            .help("Slower (↓, ⇧↓ for −5)")
            .pointingHandCursor()

            CustomSlider(value: $engine.bpm, range: 40...240)
                .frame(height: 20)

            Button {
                engine.incrementBPM()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.bordered)
            .help("Faster (↑, ⇧↑ for +5)")
            .pointingHandCursor()
        }
    }

    // MARK: - Time Signature
    // 各プリセットを小さな○で表現。強拍は大きめ・不透明、弱拍は小さめ・薄め。
    // 右クリックで「現在のパターンで上書き」または「デフォルトに戻す」が可能。

    private var timeSignaturePicker: some View {
        HStack(spacing: 4) {
            ForEach(engine.presets.indices, id: \.self) { index in
                presetButton(preset: engine.presets[index], index: index, selected: isPresetSelected(at: index))
            }
        }
    }

    private func isPresetSelected(at index: Int) -> Bool {
        let preset = engine.presets[index]
        return engine.beatsPerMeasure == preset.beats && engine.accentBeats == preset.accentSet
    }

    private func presetButton(preset: BeatPreset, index: Int, selected: Bool) -> some View {
        // 拍数が多いプリセットはボタン幅に収まるよう○を小さくする
        let dense = preset.beats > 6
        let accentSize: CGFloat = dense ? 5 : 7
        let normalSize: CGFloat = dense ? 3.5 : 5
        return HStack(spacing: dense ? 1.5 : 2) {
            ForEach(0..<preset.beats, id: \.self) { i in
                let isAccent = preset.accents.contains(i)
                Circle()
                    .fill(
                        isAccent
                            ? (selected ? Color.orange : Color.orange.opacity(0.5))
                            : (selected ? Color.secondary.opacity(0.45) : Color.secondary.opacity(0.22))
                    )
                    .frame(width: isAccent ? accentSize : normalSize, height: isAccent ? accentSize : normalSize)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .chip(selected: selected)
        .onTapGesture {
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

    // MARK: - Subdivision
    // 1拍の刻み。音符記号に馴染みのない人もいるので help で補足する

    private var subdivisionPicker: some View {
        HStack(spacing: 4) {
            ForEach(Subdivision.allCases, id: \.self) { sub in
                Text(sub.symbol)
                    .font(.system(size: 12, weight: .medium))
                    .tracking(-2)
                    .foregroundColor(engine.subdivision == sub ? .primary : .secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .chip(selected: engine.subdivision == sub)
                    .onTapGesture { engine.subdivision = sub }
                    .help(sub.label)
            }
        }
    }

    // MARK: - Controls

    private var controlsRow: some View {
        HStack(spacing: 8) {
            Button {
                engine.tapTempo()
            } label: {
                Text("Tap")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.bordered)
            .help("Tap along to set the tempo (T"
                + (hotKeys?.isTapAvailable == true ? ", or ⌃⌥T from any app)" : ")"))
            .pointingHandCursor()

            Button {
                engine.toggle()
            } label: {
                playButtonLabel
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .tint(engine.isPlaying ? .red : .accentColor)
            .keyboardShortcut(.space, modifiers: [])
            .help((engine.isPlaying ? "Stop (Space" : "Play (Space")
                + (hotKeys?.isToggleAvailable == true ? ", or ⌃⌥M from any app)" : ")"))
            .pointingHandCursor()
        }
    }

    /// 再生中は経過時間を表示し、どれだけ練習したか分かるようにする
    @ViewBuilder
    private var playButtonLabel: some View {
        if engine.isPlaying, let startedAt = engine.playStartedAt {
            TimelineView(.periodic(from: startedAt, by: 1)) { context in
                Label {
                    Text(ElapsedTime.format(context.date.timeIntervalSince(startedAt)))
                        .monospacedDigit()
                } icon: {
                    Image(systemName: "stop.fill")
                }
            }
        } else {
            Label("Play", systemImage: "play.fill")
        }
    }

    // MARK: - Volume Controls

    private var volumeControls: some View {
        HStack(spacing: 10) {
            Image(systemName: "speaker.wave.2.fill")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .help("Click volume")
            volumeSlider(value: $engine.accentVolume, accent: true)
            volumeSlider(value: $engine.normalVolume, accent: false)
        }
    }

    /// 拍インジケータと同じ ●（強）／○（弱）の記号で、どちらの音量かを示す
    private func volumeSlider(value: Binding<Double>, accent: Bool) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(accent ? Color.orange.opacity(0.8) : Color.clear)
                .overlay(Circle().stroke(accent ? Color.clear : Color.secondary.opacity(0.5), lineWidth: 1.2))
                .frame(width: 7, height: 7)
            CustomSlider(value: value, range: 0...1, step: 0.01, tint: accent ? .orange : .gray)
                .frame(height: 16)
        }
        .help(accent ? "Accent volume" : "Beat volume")
    }

    // MARK: - Footer

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    private var footerRow: some View {
        HStack {
            CheckBox(title: "Launch at Login", isOn: $launchAtLogin)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .onChange(of: launchAtLogin) {
                    do {
                        if launchAtLogin {
                            try SMAppService.mainApp.register()
                        } else {
                            try SMAppService.mainApp.unregister()
                        }
                    } catch {
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                }
            Spacer()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
            .font(.system(size: 11))
            .keyboardShortcut("q")
            .pointingHandCursor()
        }
    }

    // MARK: - Pulse Animation

    private func triggerPulse() {
        guard engine.isPlaying else { return }
        pulseScale = 1.0
        pulseOpacity = 0.6
        withAnimation(.easeOut(duration: 0.3)) {
            pulseScale = 1.4
            pulseOpacity = 0.0
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

    var label: String {
        switch self {
        case .quarter: "Quarter notes (no subdivision)"
        case .eighth: "Eighth notes"
        case .triplet: "Triplets"
        case .sixteenth: "Sixteenth notes"
        }
    }
}
