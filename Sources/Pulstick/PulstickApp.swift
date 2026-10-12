import PulstickCore
import SwiftUI

@main
struct PulstickApp: App {
    @StateObject private var engine: PulstickEngine
    private let hotKeys: GlobalHotKeys

    init() {
        Snapshot.runIfRequested()
        let engine = PulstickEngine()
        _engine = StateObject(wrappedValue: engine)
        hotKeys = GlobalHotKeys(engine: engine)
    }

    var body: some Scene {
        MenuBarExtra {
            PulstickView(engine: engine)
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
        if engine.isPlaying {
            HStack(spacing: 3) {
                Image(systemName: "metronome.fill")
                Text("\(Int(engine.bpm))")
                    .monospacedDigit()
            }
        } else {
            Image(systemName: "metronome")
        }
    }
}
