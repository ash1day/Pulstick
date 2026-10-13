import AppKit
import PulstickCore
import SwiftUI
import Testing
@testable import Pulstick

/// 実機で触って確かめられない UI の、最低限の安全網。
/// 主要な状態で各ビューを描画し、body の評価でクラッシュしないこと・中身が空でないことを確かめる
@MainActor
@Suite("View smoke tests")
struct ViewSmokeTests {
    private func render(_ view: some View) -> NSImage? {
        let renderer = ImageRenderer(content: view.frame(width: 320))
        return renderer.nsImage
    }

    private func engine(configure: (PulstickEngine) -> Void = { _ in }) -> PulstickEngine {
        let engine = makeEngine()
        configure(engine)
        return engine
    }

    @Test func popoverRendersInItsDefaultState() throws {
        let image = try #require(render(PulstickView(engine: engine(), hotKeys: nil)))
        #expect(image.size.height > 300)
    }

    @Test func popoverRendersWithEverythingSwitchedOn() throws {
        let busy = engine { e in
            e.setBeats(16)
            e.speedTrainerEnabled = true
            e.gapTrainerEnabled = true
            e.isMuted = true
            e.subdivision = .sixteenth
            e.clickSound = .wood
            var log = PracticeLog()
            log.record(from: Date().addingTimeInterval(-600), to: Date())
            e.seedPracticeLog(log)
        }
        let plain = try #require(render(PulstickView(engine: engine(), hotKeys: nil)))
        let image = try #require(render(PulstickView(engine: busy, hotKeys: nil)))
        // トレーナーの設定行と練習ログの分だけ高くなる
        #expect(image.size.height > plain.size.height)
    }

    /// 「コントラストを上げる」とダークモードでは輪郭や塗りの分岐が変わるので、その組み合わせでも描けること
    @Test func popoverRendersInDarkModeWithIncreasedContrast() throws {
        let trainer = engine { $0.speedTrainerEnabled = true }
        let view = PulstickView(engine: trainer, hotKeys: nil)
            .environment(\.colorScheme, .dark)
            .environment(\._colorSchemeContrast, .increased)
        let image = try #require(render(view))
        #expect(image.size.height > 300)
    }

    @Test func songListRendersEmptyAndFilled() throws {
        let empty = try #require(render(SongList(engine: engine()) {}))
        let filled = engine { e in
            for name in ["A", "B", "C", "D", "E", "F", "G"] {  // 7 曲でスクロール表示に切り替わる
                e.saveCurrentAsSong(named: name)
            }
        }
        #expect(empty.size.height > 0)
        #expect(render(SongList(engine: filled) {}) != nil)
    }

    @Test func settingsPanelRendersMuted() {
        #expect(render(SettingsPanel(engine: engine { $0.isMuted = true })) != nil)
    }

    @Test func welcomeRenders() {
        #expect(render(WelcomeView {}) != nil)
    }

    @Test func shortcutHelpRenders() {
        #expect(render(ShortcutHelp(hotKeys: nil, presetCount: 4)) != nil)
    }

    @Test func stepperSentenceIgnoresBadPlaceholders() {
        let view = HStack {
            StepperSentence(template: "%1$@ ok %5$@ %0$@", slots: [AnyView(Text("x"))])
        }
        #expect(render(view) != nil)
    }

    @Test func weeklyTotalUsesHoursOnlyWhenNeeded() {
        let long = PracticeTime.format(2 * 3600 + 15 * 60)
        #expect(long.contains("2") && long.contains("15"))
        #expect(!PracticeTime.format(45 * 60).contains("0"))  // "0 hr 45 min" のようにしない
    }

    @Test func practiceTimeIsShortEnoughForTooltips() {
        // グラフのツールチップや曲の練習時間に添えるので、短い書き方にする
        #expect(PracticeTime.format(2 * 3600 + 45 * 60, locale: Locale(identifier: "en_US")) == "2h 45m")
        #expect(PracticeTime.format(2 * 3600 + 45 * 60, locale: Locale(identifier: "ja_JP")) == "2時間45分")
    }
}
