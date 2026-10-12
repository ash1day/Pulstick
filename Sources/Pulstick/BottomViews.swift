import PulstickCore
import ServiceManagement
import SwiftUI

struct TransportRow: View {
    @ObservedObject var engine: PulstickEngine
    let hotKeys: GlobalHotKeys?

    var body: some View {
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
            .help(hotKeys?.isTapAvailable == true
                  ? "Tap along to set the tempo (T, or ⌃⌥T from any app)"
                  : "Tap along to set the tempo (T)")
            .pointingHandCursor()

            Button {
                engine.toggle()
            } label: {
                playButtonLabel
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .tint(engine.isPlaying ? .red : .accentColor)
            .help(playButtonHelp)
            .pointingHandCursor()
            // 「15 分だけ集中して練習」のための自動停止。画面を増やさないよう右クリックメニューに置く
            .contextMenu {
                Picker("Stop After", selection: $engine.stopAfter) {
                    Text("Don't Stop").tag(TimeInterval?.none)
                    ForEach([5, 10, 15, 20, 30, 60], id: \.self) { minutes in
                        Text("\(minutes) min").tag(TimeInterval?.some(TimeInterval(minutes * 60)))
                    }
                }
                .pickerStyle(.inline)
                // 楽器を構える間や録音の入りのために、始める前に予備の小節を鳴らす
                Picker("Count-in", selection: $engine.countInBars) {
                    Text("No Count-in").tag(0)
                    Text("1 Bar").tag(1)
                    Text("2 Bars").tag(2)
                }
                .pickerStyle(.inline)
            }
        }
    }

    private var playButtonHelp: Text {
        let base: Text = switch (engine.isPlaying, hotKeys?.isToggleAvailable == true) {
        case (true, true): Text("Stop (Space, or ⌃⌥M from any app)")
        case (true, false): Text("Stop (Space)")
        case (false, true): Text("Play (Space, or ⌃⌥M from any app)")
        case (false, false): Text("Play (Space)")
        }
        return base + Text(verbatim: " · ") + Text("Right-click for a practice timer and count-in")
    }

    /// 再生中は経過時間（練習タイマー設定時は残り時間）を表示し、どれだけ練習したか分かるようにする
    @ViewBuilder
    private var playButtonLabel: some View {
        if engine.isPlaying, let startedAt = engine.playStartedAt {
            TimelineView(.periodic(from: startedAt, by: 1)) { context in
                let elapsed = context.date.timeIntervalSince(startedAt)
                // 練習タイマーは再生中に選び直すとそこから数えるので、残り時間はタイマーの起点から求める
                let timerElapsed = engine.practiceTimerStartedAt.map { context.date.timeIntervalSince($0) } ?? elapsed
                Label {
                    Text(ElapsedTime.format(engine.stopAfter.map { $0 - timerElapsed } ?? elapsed))
                        .monospacedDigit()
                } icon: {
                    Image(systemName: engine.stopAfter == nil ? "stop.fill" : "timer")
                }
            }
        } else if let limit = engine.stopAfter {
            Label {
                Text("Play") + Text(verbatim: " \(ElapsedTime.format(limit))").monospacedDigit()
            } icon: {
                Image(systemName: "timer")
            }
        } else {
            Label("Play", systemImage: "play.fill")
        }
    }
}

struct VolumeRow: View {
    @ObservedObject var engine: PulstickEngine

    var body: some View {
        HStack(spacing: 10) {
            // 録音に合わせるときや音を出せない場所では、音だけ止めて拍の表示で練習できる
            Image(systemName: engine.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.system(size: 11))
                .foregroundColor(engine.isMuted ? .orange : .secondary)
                .frame(width: 16)
                .help(engine.isMuted ? "Unmute (M)" : "Mute the click (M) · the beat display keeps going")
                .accessibleToggle($engine.isMuted, label: Text("Mute"))
            Group {
                volumeSlider(value: $engine.accentVolume, accent: true)
                volumeSlider(value: $engine.normalVolume, accent: false)
            }
            .saturation(engine.isMuted ? 0 : 1)
            .opacity(engine.isMuted ? 0.6 : 1)
        }
    }

    /// 拍インジケータと同じ ●（強）／○（弱）の記号で、どちらの音量かを示す
    private func volumeSlider(value: Binding<Double>, accent: Bool) -> some View {
        let name = accent ? Text("Accent volume") : Text("Beat volume")
        return HStack(spacing: 4) {
            Circle()
                .fill(accent ? Color.orange.opacity(0.8) : Color.clear)
                .overlay(Circle().stroke(accent ? Color.clear : Color.secondary.opacity(0.5), lineWidth: 1.2))
                .frame(width: 7, height: 7)
            CustomSlider(value: value, range: 0...1, step: 0.01, tint: accent ? .orange : .gray, accessibilityStep: 0.05)
                .frame(height: 16)
                .accessibilityLabel(name)
                .accessibilityValue(Text("\(Int(value.wrappedValue * 100))%"))
        }
        .help(name)
    }
}

/// 今日の練習時間と連続日数。再生中のセッションも含めて 30 秒ごとに更新する
struct PracticeSummary: View {
    @ObservedObject var engine: PulstickEngine
    @State private var isConfirmingReset = false

    var body: some View {
        if engine.isPlaying || !engine.practiceLog.secondsByDay.isEmpty {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                let now = context.date
                // 記録と同じ規則（5 秒未満は数えない・日付をまたいだら今日の分だけ）で再生中の時間を足す
                let running = engine.unsavedPracticeToday()
                let today = engine.practiceLog.seconds(on: now) + running
                let streak = engine.practiceLog.streak(endingAt: now, practisingNow: running > 0)
                let week = recentWeek(endingAt: now, running: running)
                HStack(spacing: 10) {
                    Label("Today \(Int(today / 60)) min", systemImage: "clock")
                    if streak > 1 {
                        Label("\(streak)-day streak", systemImage: "flame")
                    }
                    Spacer()
                    WeekBars(seconds: week, endingAt: now)
                }
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .help("Practice time is counted while the metronome plays")
                // 新学期に付け直すときや Mac を共有しているとき用。消すと戻せないので必ず確認する
                .contextMenu {
                    Button("Reset Practice History…") { isConfirmingReset = true }
                }
                .confirmationDialog("Reset practice history?", isPresented: $isConfirmingReset) {
                    Button("Reset", role: .destructive) { engine.resetPracticeHistory() }
                } message: {
                    Text("This clears today's minutes, your streak, the 7-day chart and each song's practice time and best tempo. Your songs stay.")
                }
            }
        }
    }

    /// 直近 7 日の練習秒数。今日の分には再生中のセッションも含める
    private func recentWeek(endingAt now: Date, running: TimeInterval) -> [Double] {
        var week = engine.practiceLog.recentDays(7, endingAt: now)
        week[week.count - 1] += running
        return week
    }
}

struct FooterRow: View {
    @ObservedObject var engine: PulstickEngine
    let hotKeys: GlobalHotKeys?
    @State private var isShowingShortcuts = false
    /// SMAppService への問い合わせはプロセス間通信なので、表示時に一度だけ行う
    @State private var launchAtLogin = false

    var body: some View {
        HStack {
            CheckBox(title: "Launch at Login", isOn: $launchAtLogin)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .onChange(of: launchAtLogin) {
                    guard launchAtLogin != (SMAppService.mainApp.status == .enabled) else { return }
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
            PopoverIconButton(
                systemName: "keyboard", help: "Keyboard shortcuts", isPresented: $isShowingShortcuts
            ) {
                ShortcutHelp(hotKeys: hotKeys, presetCount: engine.presets.count)
            }
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
            .font(.system(size: 11))
            .keyboardShortcut("q")
            .pointingHandCursor()
        }
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

/// 直近 7 日の練習時間の小さな棒グラフ。量を表す単一系列なので単色の濃淡だけで描き、
/// 今日の棒だけを濃くする。練習しなかった日は基線上の小さな点で「0」を示す
struct WeekBars: View {
    /// 古い日から順に 7 日分（秒）
    let seconds: [Double]
    let endingAt: Date

    private let barWidth: CGFloat = 5
    private let height: CGFloat = 14

    var body: some View {
        let peak = max(seconds.max() ?? 0, 60)
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(seconds.indices, id: \.self) { index in
                let isToday = index == seconds.count - 1
                let value = seconds[index]
                Group {
                    if value > 0 {
                        UnevenRoundedRectangle(topLeadingRadius: 2, topTrailingRadius: 2)
                            .fill(Color.accentColor.opacity(isToday ? 1 : 0.45))
                            .frame(width: barWidth, height: max(2, height * CGFloat(value / peak)))
                    } else {
                        Capsule()
                            .fill(Color.secondary.opacity(0.35))
                            .frame(width: barWidth, height: 1.5)
                    }
                }
                .frame(height: height, alignment: .bottom)
                // 棒ごとのツールチップが優先されるので、7 日間の合計もここに添える
                .help(Text("\(dayName(index)) \(Int(value / 60)) min") + Text(verbatim: " · ") + weekTotal)
            }
        }
        .help(weekTotal)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Last 7 days"))
        .accessibilityValue(Text(seconds.indices.map { "\(dayName($0)) \(Int(seconds[$0] / 60))" }.joined(separator: ", ")))
    }

    private var weekTotal: Text {
        Text("Last 7 days: \(PracticeTime.format(seconds.reduce(0, +)))")
    }

    private func dayName(_ index: Int) -> String {
        let date = Calendar.current.date(byAdding: .day, value: index - (seconds.count - 1), to: endingAt)!
        return date.formatted(.dateTime.weekday(.abbreviated))
    }
}
