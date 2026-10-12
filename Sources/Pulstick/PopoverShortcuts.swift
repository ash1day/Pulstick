import PulstickCore
import SwiftUI

/// ポップオーバー内のキーボードショートカット。
/// 隠しボタンへの登録とショートカット一覧の表示を、この一つの表から作って食い違いを防ぐ
struct PopoverShortcut {
    struct Binding {
        let key: KeyEquivalent
        var modifiers: EventModifiers = []
        let action: (PulstickEngine) -> Void
    }

    /// 一覧に出すキーの表記（"↑ ↓" のように複数のキーをまとめてよい）
    let display: String
    let label: LocalizedStringKey
    let bindings: [Binding]

    static func all(presetCount: Int) -> [PopoverShortcut] {
        [
            PopoverShortcut(display: "Space", label: "Play / Stop", bindings: [
                Binding(key: .space) { $0.toggle() },
            ]),
            PopoverShortcut(display: "↑ ↓", label: "Tempo ±1", bindings: [
                Binding(key: .upArrow) { $0.incrementBPM() },
                Binding(key: .downArrow) { $0.decrementBPM() },
            ]),
            PopoverShortcut(display: "⇧↑ ⇧↓", label: "Tempo ±5", bindings: [
                Binding(key: .upArrow, modifiers: .shift) { $0.incrementBPM(by: 5) },
                Binding(key: .downArrow, modifiers: .shift) { $0.decrementBPM(by: 5) },
            ]),
            PopoverShortcut(display: "T", label: "Tap tempo", bindings: [
                Binding(key: "t") { $0.tapTempo() },
            ]),
            PopoverShortcut(display: "M", label: "Mute / unmute", bindings: [
                Binding(key: "m") { $0.isMuted.toggle() },
            ]),
            PopoverShortcut(display: "1–\(presetCount)", label: "Choose a preset", bindings: (0..<presetCount).map { index in
                Binding(key: KeyEquivalent(Character("\(index + 1)"))) { $0.applyPreset(at: index) }
            }),
            PopoverShortcut(display: "[ ]", label: "Previous / next song", bindings: [
                Binding(key: "[") { $0.applyAdjacentSong(-1) },
                Binding(key: "]") { $0.applyAdjacentSong(1) },
            ]),
        ]
    }
}
