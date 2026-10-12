import PulstickCore
import SwiftUI

// 拍ごとに再描画されるのはこのファイルのビューだけにする

/// 強（アクセント）: 塗りつぶし円・オレンジ、弱: 輪郭のみ・グレー。
/// タップで強弱を切り替え。−/＋ボタンで拍を削除・追加。
struct BeatIndicator: View {
    @ObservedObject var engine: PulstickEngine
    @ObservedObject var clock: BeatClock
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        HStack(spacing: 4) {
            stepButton("minus.circle", enabled: engine.beatsPerMeasure > PulstickEngine.beatsRange.lowerBound) {
                engine.removeBeat()
            }
            .help("Remove a beat")

            // 16拍でもスクロールせず全拍が見えるよう、幅に合わせて○を縮める
            GeometryReader { geo in
                let slot = min(26, geo.size.width / CGFloat(engine.beatsPerMeasure))
                let diameter = max(8, min(20, slot - 6))
                HStack(spacing: 0) {
                    ForEach(0..<engine.beatsPerMeasure, id: \.self) { beat in
                        beatDot(beat: beat, diameter: diameter)
                            .frame(width: slot, height: geo.size.height)
                            .contentShape(Rectangle())
                            .pointingHandCursor()
                            .accessibleTap(Text("Beat \(beat + 1)"), value: beatStateName(beat)) {
                                engine.cycleBeat(beat)
                            }
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .help("Click a beat to switch it: normal → accent → rest")

            stepButton("plus.circle", enabled: engine.beatsPerMeasure < PulstickEngine.beatsRange.upperBound) {
                engine.addBeat()
            }
            .help("Add a beat")
        }
        .frame(height: 44)
    }

    private func stepButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15))
                .foregroundColor(enabled ? .secondary : .secondary.opacity(0.25))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .pointingHandCursor()
    }

    private func beatStateName(_ beat: Int) -> Text {
        if engine.restBeats.contains(beat) { return Text("Rest") }
        return engine.accentBeats.contains(beat) ? Text("Accented") : Text("Not accented")
    }

    private func beatDot(beat: Int, diameter: CGFloat) -> some View {
        let isAccent = engine.accentBeats.contains(beat)
        let isRest = engine.restBeats.contains(beat)
        let isCurrent = engine.isPlaying && clock.current == beat
        let outline = Color.secondary.opacity(contrast == .increased ? 0.8 : 0.35)
        return ZStack {
            if isRest {
                // 休符: 鳴らない拍は点線の輪郭だけで示す
                Circle()
                    .stroke(isCurrent ? Color.accentColor : outline, style: StrokeStyle(lineWidth: 1.2, dash: [2, 2.5]))
                    .padding(diameter * 0.15)
            } else {
                Circle()
                    .fill(isAccent
                          ? (isCurrent ? Color.orange : Color.orange.opacity(0.55))
                          : (isCurrent ? Color.accentColor.opacity(0.25) : Color.clear))
                Circle()
                    .stroke(
                        isAccent ? Color.clear : (isCurrent ? Color.accentColor : outline),
                        lineWidth: 1.5
                    )
            }
        }
        .frame(width: diameter, height: diameter)
        // 無音小節中は拍の表示だけ進め、音が鳴っていないことを薄さで示す
        .opacity(clock.isInSilentBar ? 0.35 : 1)
        // 「視差効果を減らす」設定では拡大アニメーションをやめ、色の変化だけで拍を示す
        .scaleEffect(isCurrent && !reduceMotion ? 1.25 : 1.0)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: clock.current)
    }
}

/// ビートごとにリング状のパルスアニメーションが拡大→フェードアウトする。
/// 数字をクリックすると直接入力できる（スライダーで 40→180 を探すのは手間なため）
struct BPMDisplay: View {
    @ObservedObject var engine: PulstickEngine
    @ObservedObject var clock: BeatClock
    @Binding var isEditing: Bool
    @State private var draft = ""
    @FocusState private var fieldFocused: Bool
    @State private var pulseScale: CGFloat = 1.0
    @State private var pulseOpacity: Double = 0.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.accentColor.opacity(pulseOpacity), lineWidth: 2)
                .frame(width: 80, height: 80)
                .scaleEffect(pulseScale)

            VStack(spacing: 0) {
                if isEditing {
                    TextField("", text: $draft)
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .multilineTextAlignment(.center)
                        .textFieldStyle(.plain)
                        .frame(width: 90, height: 38)
                        .focused($fieldFocused)
                        .onSubmit(commit)
                        .onExitCommand { isEditing = false }
                        .onChange(of: fieldFocused) {
                            if !fieldFocused { commit() }
                        }
                } else {
                    Text("\(Int(engine.bpm))")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .frame(height: 38)
                        .contentShape(Rectangle())
                        .accessibleTap(Text("Tempo"), value: engine.bpmAccessibilityValue, action: beginEditing)
                        .help("Click to type a tempo")
                        .pointerStyle(.horizontalText)
                }
                Group {
                    if clock.isInSilentBar {
                        Label("Silent bar · keep counting", systemImage: "speaker.slash.fill")
                    } else if let song = engine.currentSong {
                        // リハーサル中に [ ] で切り替えても、いまどの曲かが分かるように
                        Text("\(song.name) · \(TempoMarking.name(for: engine.bpm))")
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: 220)
                    } else {
                        Text("\(TempoMarking.name(for: engine.bpm)) · BPM")
                    }
                }
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(.secondary)
            }
        }
        .frame(height: 84)
        .onChange(of: clock.current) {
            triggerPulse()
        }
        .onAppear {
            // 入力中の状態で表示されたとき（テストなど）も、入力欄にフォーカスを当てる
            if isEditing {
                // 表示が作り直されても、打ちかけの文字は消さない
                if draft.isEmpty { draft = "\(Int(engine.bpm))" }
                fieldFocused = true
            }
        }
    }

    private func beginEditing() {
        draft = "\(Int(engine.bpm))"
        isEditing = true
        fieldFocused = true
    }

    private func commit() {
        guard isEditing else { return }
        if let value = Double(draft.trimmingCharacters(in: .whitespaces)) {
            engine.bpm = value.rounded()
        }
        isEditing = false
    }

    private func triggerPulse() {
        guard engine.isPlaying, !reduceMotion else { return }
        pulseScale = 1.0
        pulseOpacity = 0.6
        withAnimation(.easeOut(duration: 0.3)) {
            pulseScale = 1.4
            pulseOpacity = 0.0
        }
    }
}

/// macOS 標準の Slider はトラックが二重描画されるバグがあるため、CustomSlider で独自描画している
struct BPMSlider: View {
    @ObservedObject var engine: PulstickEngine

    var body: some View {
        HStack(spacing: 8) {
            stepButton("minus") { engine.decrementBPM() }
                .help("Slower (↓, ⇧↓ for −5)")

            CustomSlider(value: $engine.bpm, range: PulstickEngine.bpmRange)
                .frame(height: 20)
                .accessibilityLabel(Text("Tempo"))
                .accessibilityValue(engine.bpmAccessibilityValue)

            stepButton("plus") { engine.incrementBPM() }
                .help("Faster (↑, ⇧↑ for +5)")
        }
    }

    private func stepButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 26, height: 26)
        }
        .buttonStyle(.bordered)
        .pointingHandCursor()
    }
}

extension PulstickEngine {
    var bpmAccessibilityValue: Text {
        Text("\(Int(bpm)) BPM")
    }
}
