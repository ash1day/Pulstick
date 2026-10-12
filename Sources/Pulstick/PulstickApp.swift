import PulstickCore
import SwiftUI

@main
struct PulstickApp: App {
    /// App はエンジンを購読しない（App の body が変更のたびに再評価されないように）。
    /// App 構造体の init は一度しか呼ばれないので StateObject でなくても寿命は保たれる
    private let engine: PulstickEngine
    private let hotKeys: GlobalHotKeys

    init() {
        Snapshot.runIfRequested()
        let engine = PulstickEngine(output: AudioClickOutput())
        self.engine = engine
        hotKeys = GlobalHotKeys(engine: engine)
        // 再生したまま終了しても、その練習時間を失わないよう停止して記録する
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { engine.stop() }
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didFinishLaunchingNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { Welcome.showIfFirstLaunch() }
        }
    }

    var body: some Scene {
        MenuBarExtra {
            PulstickView(engine: engine, hotKeys: hotKeys)
        } label: {
            MenuBarLabel(engine: engine)
        }
        .menuBarExtraStyle(.window)
    }
}

/// 再生中はアイコンを塗りつぶし BPM を並べ、ポップオーバーを開かなくても状態が分かるようにする
struct MenuBarLabel: View {
    @ObservedObject var engine: PulstickEngine

    var body: some View {
        Group {
            if engine.isPlaying {
                HStack(spacing: 3) {
                    Image(systemName: engine.isMuted ? "speaker.slash.fill" : "metronome.fill")
                    Text("\(Int(engine.bpm))")
                        .monospacedDigit()
                    // 音が出ていないときだけ拍番号を出す（毎拍の再描画はこの間だけにとどめる）
                    if engine.isMuted {
                        MenuBarBeat(clock: engine.beatClock)
                    }
                }
            } else {
                Image(systemName: "metronome")
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(engine.isPlaying ? Text("Pulstick, playing at \(Int(engine.bpm)) BPM") : Text("Pulstick, stopped"))
    }
}

/// ミュート中にメニューバーで現在の拍を示す
struct MenuBarBeat: View {
    @ObservedObject var clock: BeatClock

    var body: some View {
        Text(verbatim: "· \(clock.current + 1)")
            .monospacedDigit()
    }
}
