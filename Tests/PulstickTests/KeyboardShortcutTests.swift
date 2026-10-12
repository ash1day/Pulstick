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

    @Test func typingATempoAndPressingReturnSetsIt() async throws {
        let engine = makeEngine()
        engine.bpm = 100
        let window = window(for: engine, editingBPM: true)
        window.makeKey()
        try await Task.sleep(for: .milliseconds(200))
        let editor = try #require(window.firstResponder as? NSTextView, "入力欄にフォーカスが当たっていない")
        editor.selectAll(nil)
        editor.insertText("150", replacementRange: editor.selectedRange())
        editor.insertNewline(nil)  // Return
        try await Task.sleep(for: .milliseconds(100))
        #expect(engine.bpm == 150)
    }

    @Test func escapeCancelsTypingATempo() async throws {
        let engine = makeEngine()
        engine.bpm = 100
        let window = window(for: engine, editingBPM: true)
        window.makeKey()
        try await Task.sleep(for: .milliseconds(200))
        let editor = try #require(window.firstResponder as? NSTextView)
        editor.selectAll(nil)
        editor.insertText("250", replacementRange: editor.selectedRange())
        // 実機の Esc と同じく、コマンドとしてレスポンダチェーンに流す
        editor.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
        try await Task.sleep(for: .milliseconds(100))
        #expect(engine.bpm == 100)
        // 入力が終わってショートカットが戻っている（入力中のままなら 3 は入力欄に入る）
        _ = press("3", keyCode: 20, in: window)
        #expect(engine.beatsPerMeasure == BeatPreset.defaults[2].beats)
    }

    /// ビュー階層から最初の入力欄を探す
    private func firstTextField(in view: NSView) -> NSTextField? {
        if let field = view as? NSTextField, field.isEditable { return field }
        for subview in view.subviews {
            if let found = firstTextField(in: subview) { return found }
        }
        return nil
    }

    @Test func typingASongNameAndPressingReturnSavesIt() async throws {
        let engine = makeEngine()
        engine.bpm = 132
        let host = NSHostingView(rootView: SongList(engine: engine) {})
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: host.fittingSize), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        window.makeKey()
        window.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        let field = try #require(firstTextField(in: host))
        window.makeFirstResponder(field)
        let editor = try #require(window.firstResponder as? NSTextView)
        // ショートカットと同じ文字（T・1・M）やスペースを含む曲名でも、そのまま保存される
        editor.insertText("Autumn t1m", replacementRange: editor.selectedRange())
        editor.insertNewline(nil)
        try await Task.sleep(for: .milliseconds(100))
        #expect(engine.songs.map(\.name) == ["Autumn t1m"])
        #expect(engine.songs.first?.bpm == 132)
    }
}
