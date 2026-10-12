import AppKit
import PulstickCore
import SwiftUI

/// `Pulstick --snapshot out.png [--dark] [--beats N] [--trainer] [--gap] [--log]` でポップオーバーの中身を PNG に書き出して終了する。
/// 開発中の見た目確認と LP 用スクリーンショットのための仕組み。
enum Snapshot {
    static func runIfRequested() {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "--snapshot"), index + 1 < args.count else { return }
        let path = args[index + 1]
        let dark = args.contains("--dark")

        MainActor.assumeIsolated {
            let store = InMemorySettingsStore()
            if args.contains("--log") {
                // 見本用の練習記録: 今日を含め 4 日連続で 25 分ずつ
                var log = PracticeLog()
                for daysAgo in 0..<4 {
                    let end = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
                    log.record(from: end.addingTimeInterval(-25 * 60), to: end)
                }
                store.set(try? JSONEncoder().encode(log), forKey: "pulstick.practiceLog")
            }
            let engine = PulstickEngine(defaults: store, output: SilentClickOutput())
            if let i = args.firstIndex(of: "--beats"), i + 1 < args.count, let beats = Int(args[i + 1]) {
                engine.setBeats(beats)
            }
            engine.speedTrainerEnabled = args.contains("--trainer")
            engine.gapTrainerEnabled = args.contains("--gap")
            let view = PulstickView(engine: engine, hotKeys: nil)
                .background(Color(nsColor: .windowBackgroundColor))
                .environment(\.colorScheme, dark ? .dark : .light)
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
