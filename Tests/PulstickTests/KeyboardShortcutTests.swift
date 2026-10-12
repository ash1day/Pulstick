import AppKit
import PulstickCore
import SwiftUI
import Testing
@testable import Pulstick

/// ポップオーバーを実際のウインドウに載せ、キーを送ってショートカットが効くかを確かめる。
/// 出力は SilentClickOutput なので音は鳴らない
@MainActor
@Suite("Keyboard shortcuts", .serialized)
struct KeyboardShortcutTests {
    private func window(for engine: PulstickEngine, editingBPM: Bool = false) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 640), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = NSHostingView(rootView: PulstickView(engine: engine, hotKeys: nil, isEditingBPM: editingBPM))
        window.layoutIfNeeded()
        return window
    }

    private func press(_ characters: String, keyCode: UInt16, modifiers: NSEvent.ModifierFlags = [], in window: NSWindow) -> Bool {
        let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: characters,
            charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode
        )!
        return window.performKeyEquivalent(with: event)
    }

    @Test func arrowUpRaisesTheTempo() async throws {
        let engine = makeEngine()
        engine.bpm = 100
        let window = window(for: engine)
        try await Task.sleep(for: .milliseconds(100))
        let handled = press(String(UnicodeScalar(NSUpArrowFunctionKey)!), keyCode: 126, in: window)
        #expect(handled)
        #expect(engine.bpm == 101)
    }

    @Test func arrowStepIsFiveWithShiftAndOneWithout() {
        // ⇧ の判定。ウインドウ経由では修飾キーの実際の押下状態を再現できないので関数で確かめる
        #expect(PopoverShortcut.tempoStep(.shift) == 5)
        #expect(PopoverShortcut.tempoStep([]) == 1)
    }

    @Test func arrowDownLowersTheTempoByOne() async throws {
        let engine = makeEngine()
        engine.bpm = 100
        let window = window(for: engine)
        try await Task.sleep(for: .milliseconds(100))
        _ = press(String(UnicodeScalar(NSDownArrowFunctionKey)!), keyCode: 125, modifiers: [.numericPad, .function], in: window)
        #expect(engine.bpm == 99)
    }

    @Test func letterAndNumberKeysReachTheirActions() async throws {
        let engine = makeEngine()
        let window = window(for: engine)
        try await Task.sleep(for: .milliseconds(100))
        _ = press("m", keyCode: 46, in: window)
        #expect(engine.isMuted)
        _ = press("3", keyCode: 20, in: window)
        #expect(engine.beatsPerMeasure == BeatPreset.defaults[2].beats)
    }

    @Test func bracketsStepThroughSongs() async throws {
        let engine = makeEngine()
        for (name, bpm) in [("A", 100.0), ("B", 120)] {
            engine.bpm = bpm
            engine.saveCurrentAsSong(named: name)
        }
        let window = window(for: engine)
        try await Task.sleep(for: .milliseconds(100))
        _ = press("[", keyCode: 33, in: window)
        #expect(engine.bpm == 100)
        _ = press("]", keyCode: 30, in: window)
        #expect(engine.bpm == 120)
    }

    @Test func spaceStartsAndStopsPlayback() async throws {
        let engine = makeEngine()
        let window = window(for: engine)
        try await Task.sleep(for: .milliseconds(100))
        _ = press(" ", keyCode: 49, in: window)
        #expect(engine.isPlaying)
        _ = press(" ", keyCode: 49, in: window)
        #expect(!engine.isPlaying)
    }

    @Test func shortcutsAreOffWhileTypingATempo() async throws {
        // BPM の入力中は、数字や Space を入力欄に譲る
        let engine = makeEngine()
        let window = window(for: engine, editingBPM: true)
        try await Task.sleep(for: .milliseconds(100))
        _ = press("3", keyCode: 20, in: window)
        _ = press(" ", keyCode: 49, in: window)
        #expect(engine.beatsPerMeasure == 4)
        #expect(!engine.isPlaying)
    }
}
