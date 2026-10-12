import AppKit
import PulstickCore
import SwiftUI

/// `Pulstick --snapshot out.png [--dark] [--beats N] [--trainer] [--gap] [--log] [--songs] [--muted] [--shortcuts] [--timer] [--contrast] [--welcome] [--rests]` でポップオーバーの中身を PNG に書き出して終了する。
/// 開発中の見た目確認と LP 用スクリーンショットのための仕組み。
enum Snapshot {
    static func runIfRequested() {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "--snapshot"), index + 1 < args.count else { return }
        let path = args[index + 1]
        let dark = args.contains("--dark")

        MainActor.assumeIsolated {
            let engine = PulstickEngine(defaults: InMemorySettingsStore(), output: SilentClickOutput())
            if args.contains("--log") {
                // 見本用の練習記録: 今日を含め 4 日連続、その前に 1 日休み、さらに前にも練習
                var log = PracticeLog()
                for (daysAgo, minutes) in [(0, 25.0), (1, 40), (2, 15), (3, 30), (5, 20), (6, 35)] {
                    let end = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
                    log.record(from: end.addingTimeInterval(-minutes * 60), to: end)
                }
                engine.seedPracticeLog(log)
            }
            if let i = args.firstIndex(of: "--beats"), i + 1 < args.count, let beats = Int(args[i + 1]) {
                engine.setBeats(beats)
            }
            engine.speedTrainerEnabled = args.contains("--trainer")
            engine.gapTrainerEnabled = args.contains("--gap")
            engine.isMuted = args.contains("--muted")
            if args.contains("--rests") {
                // 見本: 2 拍目と 4 拍目だけ鳴らすジャズの練習
                engine.setBeats(4)
                engine.cycleBeat(0)
                engine.cycleBeat(2); engine.cycleBeat(2)
            }
            if args.contains("--timer") { engine.stopAfter = 15 * 60 }
            let showSongs = args.contains("--songs")
            if showSongs {
                for (name, bpm, beats) in [("Autumn Leaves", 132.0, 4), ("Blue Bossa", 150, 4), ("Waltz for Debby", 96, 3)] {
                    engine.bpm = bpm
                    engine.setBeats(beats)
                    engine.saveCurrentAsSong(named: name)
                }
            }
            let view = Group {
                if showSongs {
                    SongList(engine: engine) {}
                } else if args.contains("--welcome") {
                    WelcomeView {}
                } else if args.contains("--shortcuts") {
                    ShortcutHelp(hotKeys: nil, presetCount: engine.presets.count)
                } else {
                    PulstickView(engine: engine, hotKeys: nil)
                }
            }
                .background(Color(nsColor: .windowBackgroundColor))
                .environment(\.colorScheme, dark ? .dark : .light)
                .environment(\._colorSchemeContrast, args.contains("--contrast") ? .increased : .standard)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            guard let image = renderer.nsImage,
                  let tiff = image.tiffRepresentation,
                  let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
            else {
                FileHandle.standardError.write("snapshot failed\n".data(using: .utf8)!)
                exit(1)
            }
            try? png.write(to: URL(fileURLWithPath: path))
            exit(0)
        }
    }
}
