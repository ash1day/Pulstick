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
        .frame(width: 280)
        .onChange(of: engine.currentBeat) {
            triggerPulse()
        }
    }

    // MARK: - Beat Indicator
    // ドットをタップしてアクセントのon/offを切り替え可能。
    // アクセント付きはオレンジ色・大きめ、再生中は現在拍がスケールアップ。

    private var beatIndicator: some View {
        HStack(spacing: 6) {
            ForEach(0..<engine.beatsPerMeasure, id: \.self) { beat in
                let isAccent = engine.accentBeats.contains(beat)
                Circle()
                    .fill(beatDotColor(for: beat))
                    .frame(width: isAccent ? 10 : 8, height: isAccent ? 10 : 8)
                    .scaleEffect(engine.isPlaying && engine.currentBeat == beat ? 1.3 : 1.0)
                    .animation(.easeOut(duration: 0.1), value: engine.currentBeat)
                    .pointingHandCursor()
                    .onTapGesture {
                        engine.toggleAccent(beat)
                    }
            }
        }
        .frame(height: 20)
    }

    private func beatDotColor(for beat: Int) -> Color {
        let isAccent = engine.accentBeats.contains(beat)
        if engine.isPlaying && engine.currentBeat == beat {
            return isAccent ? Color.orange : Color.accentColor
        }
        return isAccent ? Color.orange.opacity(0.5) : Color.secondary.opacity(0.3)
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

    private let presets: [(label: String, beats: Int)] = [
        ("4/4", 4), ("3/4", 3), ("6/8", 6), ("9/8", 9)
    ]

    private var timeSignaturePicker: some View {
        HStack(spacing: 4) {
            ForEach(presets, id: \.beats) { preset in
                beatButton(label: preset.label, beats: preset.beats, selected: engine.beatsPerMeasure == preset.beats) {
                    engine.setBeats(preset.beats)
                }
            }
        }
    }

    private func beatButton(label: String, beats: Int, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
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

    private var footerRow: some View {
        HStack {
            Text("Space: Play/Stop")
                .font(.system(size: 10))
                .foregroundColor(.secondary.opacity(0.6))
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
