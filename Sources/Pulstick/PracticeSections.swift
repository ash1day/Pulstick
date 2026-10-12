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
            let bpmRange = PulstickEngine.bpmRange
            StepperSentence(
                template: engine.speedTrainer.measuresPerStep == 1
                    ? String(localized: "trainer.sentence.one", defaultValue: "%1$@ BPM every %2$@ bar, up to %3$@")
                    : String(localized: "trainer.sentence.other", defaultValue: "%1$@ BPM every %2$@ bars, up to %3$@"),
                slots: [
                    AnyView(MiniStepper(value: $engine.speedTrainer.bpmIncrement, range: 1...20, prefix: "+")),
                    AnyView(MiniStepper(value: $engine.speedTrainer.measuresPerStep, range: 1...32)),
                    AnyView(MiniStepper(
                        value: $engine.speedTrainer.targetBPM,
                        range: Int(bpmRange.lowerBound) + 1...Int(bpmRange.upperBound), step: 5
                    )),
                ]
            )
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
            StepperSentence(
                template: engine.gapTrainer.playBars == 1
                    ? String(localized: "gap.sentence.one", defaultValue: "Play %1$@ bar, then %2$@ silent")
                    : String(localized: "gap.sentence.other", defaultValue: "Play %1$@ bars, then %2$@ silent"),
                slots: [
                    AnyView(MiniStepper(value: $engine.gapTrainer.playBars, range: 1...16)),
                    AnyView(MiniStepper(value: $engine.gapTrainer.muteBars, range: 1...16)),
                ]
            )
        }
    }
}

/// 言語ごとに語順が違う文の途中にステッパーを差し込む。
/// 語順はローカライズされたテンプレート（"%2$@ 小節ごとに %1$@ BPM" など）で決まる
struct StepperSentence: View {
    let template: String
    let slots: [AnyView]

    var body: some View {
        let parts = SentenceTemplate.parse(template)
        ForEach(parts.indices, id: \.self) { index in
            switch parts[index] {
            case .text(let text): Text(verbatim: text)
            // 訳文の差し込み番号が誤っていても落ちないよう、範囲外は無視する
            case .slot(let slot): if slots.indices.contains(slot) { slots[slot] }
            }
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
            value = (value + delta).clamped(to: range)
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
