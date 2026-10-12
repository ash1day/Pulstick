import PulstickCore
import SwiftUI

/// 練習モードのカード。見出し行にスイッチを持ち、オンのときだけ設定行を表示する
struct PracticeCard<Accessory: View, Settings: View>: View {
    let title: LocalizedStringKey
    let systemImage: String
    let help: LocalizedStringKey
    @Binding var isOn: Bool
    @ViewBuilder var accessory: () -> Accessory
    @ViewBuilder var settings: () -> Settings

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(title, systemImage: systemImage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(isOn ? .primary : .secondary)
                Spacer()
                accessory()
                MiniSwitch(isOn: $isOn)
                    .accessibilityLabel(title)
            }
            .help(help)

            if isOn {
                HStack(spacing: 4) {
                    settings()
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
                .fill(Color.secondary.opacity(isOn ? 0.08 : 0.04))
        )
        .animation(.easeOut(duration: 0.15), value: isOn)
    }
}

/// 「N 小節ごとに +X BPM、目標まで」。
/// 難しいフレーズをゆっくりから少しずつ速くしていく練習を想定している
struct SpeedTrainerSection: View {
    @ObservedObject var engine: PulstickEngine

    var body: some View {
        PracticeCard(
            title: "Speed Trainer",
            systemImage: "chart.line.uptrend.xyaxis",
            help: "Gradually raise the tempo while playing",
            isOn: $engine.speedTrainerEnabled
        ) {
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
        } settings: {
            MiniStepper(value: $engine.speedTrainer.bpmIncrement, range: 1...20, prefix: "+")
            // 語順が言語で異なるため、ステッパーの間に入る語は意味ベースのキーで訳す
            Text(String(localized: "trainer.every", defaultValue: "BPM every"))
            MiniStepper(value: $engine.speedTrainer.measuresPerStep, range: 1...32)
            Text(engine.speedTrainer.measuresPerStep == 1
                 ? String(localized: "trainer.upTo.one", defaultValue: "bar, up to")
                 : String(localized: "trainer.upTo.other", defaultValue: "bars, up to"))
            MiniStepper(value: $engine.speedTrainer.targetBPM, range: 41...240, step: 5)
        }
    }
}

/// 「N 小節鳴らして M 小節は無音」。無音の間も拍の表示は進むので、
/// 戻ってきたクリックと自分のテンポがずれていないか確かめられる
struct GapTrainerSection: View {
    @ObservedObject var engine: PulstickEngine

    var body: some View {
        PracticeCard(
            title: "Silent Bars",
            systemImage: "speaker.slash",
            help: "Mute some bars to check that you hold the tempo on your own",
            isOn: $engine.gapTrainerEnabled
        ) {
            EmptyView()
        } settings: {
            let prefix = String(localized: "gap.prefix", defaultValue: "Play")
            if !prefix.isEmpty {
                Text(prefix)
            }
            MiniStepper(value: $engine.gapTrainer.playBars, range: 1...16)
            Text(engine.gapTrainer.playBars == 1
                 ? String(localized: "gap.then.one", defaultValue: "bar, then")
                 : String(localized: "gap.then.other", defaultValue: "bars, then"))
            MiniStepper(value: $engine.gapTrainer.muteBars, range: 1...16)
            Text(String(localized: "gap.suffix", defaultValue: "silent"))
        }
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
