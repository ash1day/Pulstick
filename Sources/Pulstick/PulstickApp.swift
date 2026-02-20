import PulstickCore
import SwiftUI

@main
struct PulstickApp: App {
    @StateObject private var engine = PulstickEngine()

    var body: some Scene {
        MenuBarExtra {
            PulstickView(engine: engine)
        } label: {
            Image(systemName: "metronome")
        }
        .menuBarExtraStyle(.window)
    }
}
