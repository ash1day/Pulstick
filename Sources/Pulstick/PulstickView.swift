import PulstickCore
import ServiceManagement
import SwiftUI

struct PulstickView: View {
    @ObservedObject var engine: PulstickEngine
    @State private var pulseScale: CGFloat = 1.0
    @State private var pulseOpacity: Double = 0.0

    var body: some View {
        VStack(spacing: 14) {
            beatIndicator
            bpmDisplay
            bpmSlider
            volumeControls
            timeSignaturePicker
            subdivisionPicker
            controlsRow
            Divider()
            footerRow
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(width: 320)
        .onChange(of: engine.currentBeat) {
            triggerPulse()
        }
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

            Button {
                engine.addBeat()
            } label: {
                Image(systemName: "plus.circle")
                    .font(.system(size: 15))
                    .foregroundColor(engine.beatsPerMeasure < 16 ? .secondary : .secondary.opacity(0.25))
            }
            .buttonStyle(.plain)
            .disabled(engine.beatsPerMeasure >= 16)
            .pointingHandCursor()
        }
        .frame(height: 52)
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
        .scaleEffect(isCurrent ? 1.25 : 1.0)
        .animation(.easeOut(duration: 0.1), value: engine.currentBeat)
    }

    // MARK: - BPM Display
    // ビートごとにリング状のパルスアニメーションが拡大→フェードアウトする

    private var bpmDisplay: some View {
        ZStack {
            Circle()
                .stroke(Color.accentColor.opacity(pulseOpacity), lineWidth: 2)
                .frame(width: 80, height: 80)
                .scaleEffect(pulseScale)

            VStack(spacing: 0) {
                Text("\(Int(engine.bpm))")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("BPM")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
            }
        }
        .frame(height: 84)
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
            .pointingHandCursor()

            CustomSlider(value: $engine.bpm, range: 40...240)
                .frame(height: 20)
                .pointingHandCursor()

            Button {
                engine.incrementBPM()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.bordered)
            .pointingHandCursor()
        }
    }

    // MARK: - Volume Controls

    private var volumeControls: some View {
        VStack(spacing: 6) {
            volumeRow(label: "強", value: $engine.accentVolume, color: .orange)
            volumeRow(label: "弱", value: $engine.normalVolume, color: .gray)
        }
    }

    private func volumeRow(label: String, value: Binding<Double>, color: Color) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(color)
                .frame(width: 16, alignment: .center)
            CustomSlider(value: value, range: 0...1, step: 0.01, tint: color)
                .frame(height: 16)
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
        .contentShape(Rectangle())
        .onTapGesture {
            engine.applyPreset(at: index)
        }
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(selected ? Color.accentColor.opacity(0.15) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(selected ? Color.accentColor.opacity(0.4) : Color.secondary.opacity(0.2), lineWidth: 1)
        )
        .contextMenu {
            Button("現在のパターンで上書き") {
                engine.saveCurrentAsPreset(at: index)
            }
            Button("デフォルトに戻す") {
                engine.resetPreset(at: index)
            }
        }
        .pointingHandCursor()
    }

    // MARK: - Subdivision
    // 1拍の刻み。音符記号は読めない人もいるので help で補足する

    private var subdivisionPicker: some View {
        HStack(spacing: 4) {
            ForEach(Subdivision.allCases, id: \.self) { sub in
                let selected = engine.subdivision == sub
                Text(sub.symbol)
                    .font(.system(size: 12, weight: .medium))
                    .tracking(-2)
                    .foregroundColor(selected ? .primary : .secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(selected ? Color.accentColor.opacity(0.15) : Color.clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(selected ? Color.accentColor.opacity(0.4) : Color.secondary.opacity(0.2), lineWidth: 1)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { engine.subdivision = sub }
                    .help(sub.label)
                    .pointingHandCursor()
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
            .pointingHandCursor()

            Button {
                engine.toggle()
            } label: {
                Label(
                    engine.isPlaying ? "Stop" : "Play",
                    systemImage: engine.isPlaying ? "stop.fill" : "play.fill"
                )
                .font(.system(size: 13, weight: .semibold))
                .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .tint(engine.isPlaying ? .red : .accentColor)
            .keyboardShortcut(.space, modifiers: [])
            .pointingHandCursor()
        }
    }

    // MARK: - Footer

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    private var footerRow: some View {
        HStack {
            Toggle("Launch at Login", isOn: $launchAtLogin)
                .toggleStyle(.checkbox)
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

// MARK: - Pointing Hand Cursor
// onHover + NSCursor で pointer カーソルを実現

struct PointingHandCursor: ViewModifier {
    func body(content: Content) -> some View {
        content.onHover { hovering in
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

extension View {
    func pointingHandCursor() -> some View {
        modifier(PointingHandCursor())
    }
}

// MARK: - Custom Slider
// macOS の SwiftUI 標準 Slider はポップオーバー内でトラックが二重描画される
// 問題があるため、GeometryReader + DragGesture で独自実装。

struct CustomSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    /// 値の刻み。BPM は整数、音量は 0.01 刻みにしたいので呼び出し側で指定する
    var step: Double = 1
    var tint: Color = .accentColor

    private let trackHeight: CGFloat = 4
    private let thumbSize: CGFloat = 18

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width - thumbSize
            let fraction = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
            let offset = width * CGFloat(fraction)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(height: trackHeight)
                    .padding(.horizontal, thumbSize / 2)

                Capsule()
                    .fill(tint)
                    .frame(width: offset + thumbSize / 2, height: trackHeight)
                    .padding(.leading, thumbSize / 2)

                Circle()
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                    .frame(width: thumbSize, height: thumbSize)
                    .offset(x: offset)
            }
            .frame(height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let fraction = Double((drag.location.x - thumbSize / 2) / width)
                        let clamped = min(max(fraction, 0), 1)
                        let raw = clamped * (range.upperBound - range.lowerBound) + range.lowerBound
                        let stepped = (raw / step).rounded() * step
                        value = min(max(stepped, range.lowerBound), range.upperBound)
                    }
            )
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
        case .quarter: "4分音符（刻みなし）"
        case .eighth: "8分音符"
        case .triplet: "3連符"
        case .sixteenth: "16分音符"
        }
    }
}
