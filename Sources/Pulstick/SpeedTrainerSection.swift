import PulstickCore
import SwiftUI

/// 「N 小節ごとに +X BPM、目標まで」を設定するセクション。
/// 難しいフレーズをゆっくりから少しずつ速くしていく練習を想定している
struct SpeedTrainerSection: View {
    @ObservedObject var engine: PulstickEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Speed Trainer", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(engine.speedTrainerEnabled ? .primary : .secondary)
                Spacer()
                if engine.speedTrainerEnabled, let start = engine.sessionStartBPM, engine.bpm != start {
                    Button {
                        engine.returnToSessionStartBPM()
                    } label: {
                        Label("\(Int(start))", systemImage: "arrow.uturn.backward")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
                    .help("Go back to the tempo you started at")
                    .pointingHandCursor()
                }
                MiniSwitch(isOn: $engine.speedTrainerEnabled)
                    .accessibilityLabel("Speed Trainer")
                    .help("Gradually raise the tempo while playing")
            }

            if engine.speedTrainerEnabled {
                HStack(spacing: 4) {
                    MiniStepper(value: $engine.speedTrainer.bpmIncrement, range: 1...20, prefix: "+")
                    Text("BPM every")
                    MiniStepper(value: $engine.speedTrainer.measuresPerStep, range: 1...32)
                    Text(engine.speedTrainer.measuresPerStep == 1 ? "bar, up to" : "bars, up to")
                    MiniStepper(value: $engine.speedTrainer.targetBPM, range: 41...240, step: 5)
                }
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(engine.speedTrainerEnabled ? 0.08 : 0.04))
        )
        .animation(.easeOut(duration: 0.15), value: engine.speedTrainerEnabled)
    }
}

/// 左右の矢印で値を増減する小さなステッパー
struct MiniStepper: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step: Int = 1
    var prefix: String = ""

    var body: some View {
        HStack(spacing: 0) {
            stepButton("chevron.left", delta: -step)
            Text("\(prefix)\(value)")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(.primary)
                .frame(minWidth: 22)
            stepButton("chevron.right", delta: step)
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 2)
        .background(RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.12)))
    }

    private func stepButton(_ symbol: String, delta: Int) -> some View {
        Button {
            value = min(max(value + delta, range.lowerBound), range.upperBound)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 8, weight: .bold))
                .frame(width: 12, height: 14)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundColor(.secondary)
        .pointingHandCursor()
    }
}
