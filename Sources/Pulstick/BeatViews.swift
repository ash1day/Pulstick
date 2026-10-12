import PulstickCore
import SwiftUI

// 拍ごとに再描画されるのはこのファイルのビューだけにする

/// 強（アクセント）: 塗りつぶし円・アクセントカラー、弱: 輪郭のみ・グレー。
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
            .accessibilityLabel(Text("Remove a beat"))

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
            .accessibilityLabel(Text("Add a beat"))
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
        // カウントイン中は音と同じく、休符もアクセントも無視して頭の拍だけを強拍として見せる
        let isAccent = clock.isCountingIn ? beat == 0 : engine.accentBeats.contains(beat)
        let isRest = clock.isCountingIn ? false : engine.restBeats.contains(beat)
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
                          ? (isCurrent ? Color.accentColor : Color.accentColor.opacity(0.7))
                          : (isCurrent ? Color.accentColor.opacity(0.25) : Color.clear))
                Circle()
                    .stroke(
                        isAccent ? Color.clear : (isCurrent ? Color.accentColor : outline),
                        lineWidth: 1.5
                    )
            }
        }
        .frame(width: diameter, height: diameter)
        // 拡大しない設定では、強拍の濃さと現在の拍の濃さが近く見分けにくいので、外側の輪で現在の拍を示す
        .overlay(
            Circle()
                .stroke(isCurrent && reduceMotion ? Color.accentColor : .clear, lineWidth: 1.5)
                .padding(-3)
        )
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
    /// 拍ごとに変わるパルスと無音小節の表示だけが購読する（この本体は拍ごとに再描画しない）
    let clock: BeatClock
    @Binding var isEditing: Bool
    @State private var draft = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        ZStack {
            PulseRing(clock: clock, isPlaying: engine.isPlaying)

            VStack(spacing: 0) {
                if isEditing {
                    TextField("", text: $draft)
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .multilineTextAlignment(.center)
                        .textFieldStyle(.plain)
                        .frame(width: 110, height: 46)
                        .focused($fieldFocused)
                        .onSubmit(commit)
                        .onExitCommand { isEditing = false }
                        .onChange(of: fieldFocused) {
                            if !fieldFocused { commit() }
                        }
                } else {
                    Text("\(Int(engine.bpm))")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .frame(height: 46)
                        .contentShape(Rectangle())
                        .accessibleTap(Text("Tempo"), value: engine.bpmAccessibilityValue, action: beginEditing)
                        .help("Click to type a tempo")
                        .pointerStyle(.horizontalText)
                }
                // 小見出しは親で一度だけ作って値として渡す（拍ごとの再描画で曲の検索などをやり直さない）
                SubtitleLabel(clock: clock, normal: subtitle)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
            }
        }
        .frame(height: 68)
        .onAppear {
            // 入力中の状態で表示されたとき（テストなど）も、入力欄にフォーカスを当てる
            if isEditing {
                // 表示が作り直されても、打ちかけの文字は消さない
                if draft.isEmpty { draft = "\(Int(engine.bpm))" }
                fieldFocused = true
            }
        }
    }

    /// 通常時の小見出し。いまの曲があれば曲名（リハーサル中に [ ] で切り替えても分かるように）。
    /// スピードトレーナーで練習中は、次にテンポが変わるまでの小節数を続けて出す
    private var subtitle: some View {
        HStack(spacing: 0) {
            if let song = engine.currentSong {
                Text("\(song.name) · \(TempoMarking.name(for: engine.bpm))")
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                Text("\(TempoMarking.name(for: engine.bpm)) · BPM")
            }
            if engine.speedTrainerEnabled {
                TempoStepCountdown(
                    clock: engine.beatClock,
                    increment: engine.nextTempoIncrease,
                    returnsToStart: engine.bpm >= Double(engine.speedTrainer.targetBPM)
                )
            }
        }
        // 長い曲名は予告を残して省略する
        .frame(maxWidth: 260)
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
}

/// ビートごとにリング状のパルスが拡大→フェードアウトする
private struct PulseRing: View {
    @ObservedObject var clock: BeatClock
    let isPlaying: Bool
    @State private var scale: CGFloat = 1.0
    @State private var opacity: Double = 0.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle()
            .stroke(Color.accentColor.opacity(opacity), lineWidth: 2)
            .frame(width: 84, height: 84)
            .scaleEffect(scale)
            .onChange(of: clock.current) {
                guard isPlaying, !reduceMotion else { return }
                scale = 1.0
                opacity = 0.6
                withAnimation(.easeOut(duration: 0.3)) {
                    scale = 1.25
                    opacity = 0.0
                }
            }
    }
}

/// カウントイン中・無音小節の間だけその旨を出し、それ以外は親から渡された小見出しを出す
private struct SubtitleLabel<Normal: View>: View {
    @ObservedObject var clock: BeatClock
    let normal: Normal

    var body: some View {
        if clock.isCountingIn {
            Label("Count-in", systemImage: "hourglass")
        } else if clock.isInSilentBar {
            Label("Silent bar · keep counting", systemImage: "speaker.slash.fill")
        } else {
            normal
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
                .accessibilityLabel(Text("Slower"))

            CustomSlider(value: $engine.bpm, range: PulstickEngine.bpmRange)
                .frame(height: 20)
                .accessibilityLabel(Text("Tempo"))
                .accessibilityValue(engine.bpmAccessibilityValue)

            stepButton("plus") { engine.incrementBPM() }
                .help("Faster (↑, ⇧↑ for +5)")
                .accessibilityLabel(Text("Faster"))
        }
    }

    private func stepButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        // 灰色の箱にすると BPM の数字より重く見えるので、記号だけの軽いボタンにする
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)
                .frame(width: 26, height: 26)
                .contentShape(Circle())
        }
        .buttonStyle(GlyphButtonStyle())
        .pointingHandCursor()
    }
}

extension PulstickEngine {
    var bpmAccessibilityValue: Text {
        Text("\(Int(bpm)) BPM")
    }
}

/// 再生中、次にテンポが変わるまでの小節数を「あと 3 小節で +5」のように予告する。
/// 上がる瞬間に不意を突かれず、その小節を弾き切る心構えができるように。
/// 小節ごとに変わる値なので BeatClock だけを監視し、ポップオーバー全体を描き直さない
private struct TempoStepCountdown: View {
    @ObservedObject var clock: BeatClock
    let increment: Int
    /// 目標に達していて、次は開始テンポに戻る（繰り返しモード）
    let returnsToStart: Bool

    var body: some View {
        if let bars = clock.barsUntilTempoStep, !clock.isCountingIn {
            // 次の小節で変わるときは色を付けて目に留まるようにする
            (Text(verbatim: " · ") + label(bars).foregroundColor(bars == 1 ? .accentColor : .secondary))
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
        }
    }

    private func label(_ bars: Int) -> Text {
        switch (returnsToStart, bars == 1) {
        case (false, true): Text("+\(increment) next bar")
        case (false, false): Text("+\(increment) in \(bars) bars")
        case (true, true): Text("Back to the start next bar")
        case (true, false): Text("Back to the start in \(bars) bars")
        }
    }
}
