import SwiftUI

struct PulstickView: View {
    @ObservedObject var engine: PulstickEngine

    var body: some View {
        VStack(spacing: 16) {
            Text("\u{266A} \(Int(engine.bpm)) BPM")
                .font(.system(size: 24, weight: .bold, design: .rounded))

            HStack(spacing: 12) {
                Button {
                    engine.decrementBPM()
                } label: {
                    Image(systemName: "minus")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.bordered)

                Slider(value: $engine.bpm, in: 40...240, step: 1) { editing in
                    if !editing {
                        engine.bpmChanged()
                    }
                }
                .frame(width: 140)
                .onChange(of: engine.bpm) { _ in
                    engine.bpmChanged()
                }

                Button {
                    engine.incrementBPM()
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.bordered)
            }

            Button {
                engine.toggle()
            } label: {
                Label(
                    engine.isPlaying ? "Stop" : "Play",
                    systemImage: engine.isPlaying ? "stop.fill" : "play.fill"
                )
                .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .tint(engine.isPlaying ? .red : .accentColor)

            Divider()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
            .font(.caption)
        }
        .padding(20)
        .frame(width: 260)
    }
}
