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
            timeSignaturePicker
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

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(0..<engine.beatsPerMeasure, id: \.self) { beat in
                        let isAccent = engine.accentBeats.contains(beat)
                        let isCurrent = engine.isPlaying && engine.currentBeat == beat
                        VStack(spacing: 2) {
                            ZStack {
                                Circle()
                                    .fill(isAccent
                                          ? (isCurrent ? Color.orange : Color.orange.opacity(0.55))
                                          : Color.clear)
                                Circle()
                                    .stroke(
                                        isAccent
                                            ? Color.clear
                                            : (isCurrent ? Color.accentColor : Color.secondary.opacity(0.35)),
                                        lineWidth: 1.5
                                    )
                            }
                            .frame(width: 20, height: 20)
                            .scaleEffect(isCurrent ? 1.25 : 1.0)
                            .animation(.easeOut(duration: 0.1), value: engine.currentBeat)

                            Text(isAccent ? "強" : "弱")
                                .font(.system(size: 8, weight: .medium, design: .rounded))
                                .foregroundColor(isAccent ? .orange.opacity(0.8) : .secondary.opacity(0.5))
                        }
                        .frame(width: 24)
                        .contentShape(Rectangle())
                        .pointingHandCursor()
                        .onTapGesture {
                            engine.toggleAccent(beat)
                        }
                    }
                }
                .padding(.horizontal, 2)
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
        .frame(height: 46)
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
        Button {
            engine.applyPreset(at: index)
        } label: {
            HStack(spacing: 2) {
                ForEach(0..<preset.beats, id: \.self) { i in
                    let isAccent = preset.accents.contains(i)
                    Circle()
                        .fill(
                            isAccent
                                ? (selected ? Color.orange : Color.orange.opacity(0.5))
                                : (selected ? Color.secondary.opacity(0.45) : Color.secondary.opacity(0.22))
                        )
                        .frame(width: isAccent ? 7 : 5, height: isAccent ? 7 : 5)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
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
                    .fill(Color.accentColor)
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
                        let stepped = (clamped * (range.upperBound - range.lowerBound) + range.lowerBound).rounded()
                        value = min(max(stepped, range.lowerBound), range.upperBound)
                    }
            )
        }
    }
}
