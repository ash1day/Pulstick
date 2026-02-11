import SwiftUI

struct PulstickView: View {
    @ObservedObject var engine: PulstickEngine
    @State private var pulseScale: CGFloat = 1.0
    @State private var pulseOpacity: Double = 0.0

    var body: some View {
        VStack(spacing: 14) {
            // Beat indicator dots
            beatIndicator

            // BPM display with pulse
            bpmDisplay

            // BPM slider with +/- buttons
            bpmSlider

            // Time signature picker
            timeSignaturePicker

            // Controls row: Tap + Play/Stop
            controlsRow

            Divider()

            // Quit + shortcut hint
            footerRow
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(width: 280)
        .onChange(of: engine.currentBeat) { _ in
            triggerPulse()
        }
    }

    // MARK: - Beat Indicator

    private var beatIndicator: some View {
        HStack(spacing: 6) {
            ForEach(0..<engine.timeSignature.beatsPerMeasure, id: \.self) { beat in
                Circle()
                    .fill(beatDotColor(for: beat))
                    .frame(width: beat == 0 ? 10 : 8, height: beat == 0 ? 10 : 8)
                    .scaleEffect(engine.isPlaying && engine.currentBeat == beat ? 1.3 : 1.0)
                    .animation(.easeOut(duration: 0.1), value: engine.currentBeat)
            }
        }
        .frame(height: 16)
    }

    private func beatDotColor(for beat: Int) -> Color {
        if !engine.isPlaying {
            return Color.secondary.opacity(0.3)
        }
        if engine.currentBeat == beat {
            return beat == 0 ? Color.orange : Color.accentColor
        }
        return Color.secondary.opacity(0.3)
    }

    // MARK: - BPM Display

    private var bpmDisplay: some View {
        ZStack {
            // Pulse ring
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

            Slider(value: $engine.bpm, in: 40...240, step: 1) { editing in
                if !editing {
                    engine.bpmChanged()
                }
            }
            .onChange(of: engine.bpm) { _ in
                engine.bpmChanged()
            }

            Button {
                engine.incrementBPM()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Time Signature

    private var timeSignaturePicker: some View {
        HStack(spacing: 4) {
            ForEach(TimeSignature.allCases) { sig in
                Button {
                    engine.setTimeSignature(sig)
                } label: {
                    Text(sig.rawValue)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                }
                .buttonStyle(.plain)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(engine.timeSignature == sig
                              ? Color.accentColor.opacity(0.15)
                              : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(engine.timeSignature == sig
                                ? Color.accentColor.opacity(0.4)
                                : Color.secondary.opacity(0.2),
                                lineWidth: 1)
                )
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
