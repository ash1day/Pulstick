import PulstickCore
import SwiftUI

/// ポップオーバー内のキーボードショートカット。
/// 隠しボタンへの登録とショートカット一覧の表示を、この一つの表から作って食い違いを防ぐ
struct PopoverShortcut {
    struct Binding {
        let key: KeyEquivalent
        /// 押されたときの修飾キーを受け取る（⇧ の有無で動きを変える矢印キー用）
        let action: (PulstickEngine, EventModifiers) -> Void

        init(key: KeyEquivalent, action: @escaping (PulstickEngine, EventModifiers) -> Void) {
            self.key = key
            self.action = action
        }

        init(key: KeyEquivalent, action: @escaping (PulstickEngine) -> Void) {
            self.key = key
            self.action = { engine, _ in action(engine) }
        }
    }

    /// ⇧ を押していれば 5、何も押していなければ 1。⌘・⌥・⌃ が付いていたら反応しない（nil）。
    /// SwiftUI のショートカットは修飾なしで登録した矢印キーを修飾付きにも一致させてしまうため、
    /// ⇧↑ を別に登録せず、押されたときの修飾キーで刻みを決める
    static func tempoStep(_ modifiers: EventModifiers) -> Double? {
        guard modifiers.isDisjoint(with: [.command, .option, .control]) else { return nil }
        return modifiers.contains(.shift) ? 5 : 1
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
            PopoverShortcut(display: "↑ ↓", label: "Tempo ±1 (⇧: ±5)", bindings: [
                Binding(key: .upArrow) { engine, modifiers in
                    if let step = tempoStep(modifiers) { engine.incrementBPM(by: step) }
                },
                Binding(key: .downArrow) { engine, modifiers in
                    if let step = tempoStep(modifiers) { engine.decrementBPM(by: step) }
                },
            ]),
            PopoverShortcut(display: "T", label: "Tap tempo", bindings: [
                Binding(key: "t") { $0.tapTempo() },
            ]),
            PopoverShortcut(display: "M", label: "Mute / unmute", bindings: [
                Binding(key: "m") { $0.isMuted.toggle() },
            ]),
            PopoverShortcut(display: "S", label: "Speed trainer on / off", bindings: [
                Binding(key: "s") { $0.speedTrainerEnabled.toggle() },
            ]),
            PopoverShortcut(display: "R", label: "Back to the start tempo", bindings: [
                Binding(key: "r") { $0.returnToSessionStartBPM() },
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
