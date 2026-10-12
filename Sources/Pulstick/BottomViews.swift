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
            .keyboardShortcut(.space, modifiers: [])
            .help(playButtonHelp)
            .pointingHandCursor()
        }
    }

    private var playButtonHelp: LocalizedStringKey {
        switch (engine.isPlaying, hotKeys?.isToggleAvailable == true) {
        case (true, true): "Stop (Space, or ⌃⌥M from any app)"
        case (true, false): "Stop (Space)"
        case (false, true): "Play (Space, or ⌃⌥M from any app)"
        case (false, false): "Play (Space)"
        }
    }

    /// 再生中は経過時間を表示し、どれだけ練習したか分かるようにする
    @ViewBuilder
    private var playButtonLabel: some View {
        if engine.isPlaying, let startedAt = engine.playStartedAt {
            TimelineView(.periodic(from: startedAt, by: 1)) { context in
                Label {
                    Text(ElapsedTime.format(context.date.timeIntervalSince(startedAt)))
                        .monospacedDigit()
                } icon: {
                    Image(systemName: "stop.fill")
                }
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
            Image(systemName: "speaker.wave.2.fill")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .help("Click volume")
            volumeSlider(value: $engine.accentVolume, accent: true)
            volumeSlider(value: $engine.normalVolume, accent: false)
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

    var body: some View {
        if engine.isPlaying || !engine.practiceLog.secondsByDay.isEmpty {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                let now = context.date
                let running = engine.playStartedAt.map { now.timeIntervalSince($0) } ?? 0
                let today = engine.practiceLog.seconds(on: now) + running
                let streak = engine.practiceLog.streak(endingAt: now, practisingNow: running > 0)
                HStack(spacing: 10) {
                    Label("Today \(Int(today / 60)) min", systemImage: "clock")
                    if streak > 1 {
                        Label("\(streak)-day streak", systemImage: "flame")
                    }
                }
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help("Practice time is counted while the metronome plays")
            }
        }
    }
}

struct FooterRow: View {
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
