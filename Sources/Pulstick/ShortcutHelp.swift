import SwiftUI

/// フッターから開くショートカット一覧。ツールチップだけでは
/// グローバルショートカット（⌃⌥M など）の存在に気付きにくいため
struct ShortcutHelp: View {
    let hotKeys: GlobalHotKeys?
    let presetCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if hotKeys?.isToggleAvailable == true || hotKeys?.isTapAvailable == true || hotKeys?.isSongStepAvailable == true {
                section("From any app") {
                    if hotKeys?.isToggleAvailable == true { row("⌃⌥M", "Play / Stop") }
                    if hotKeys?.isTapAvailable == true { row("⌃⌥T", "Tap tempo") }
                    if hotKeys?.isSongStepAvailable == true { row("⌃⌥, ⌃⌥.", "Previous / next song") }
                }
            }
            section("In this window") {
                ForEach(PopoverShortcut.all(presetCount: presetCount), id: \.display) { shortcut in
                    row(shortcut.display, shortcut.label)
                }
            }
            // 練習タイマーや記録のリセットなどは右クリックの中にあり、見た目からは分からないので、ここで案内する
            section("Right-click") {
                rightClickTip("Play", "Practice timer, count-in")
                rightClickTip("Today’s minutes", "Reset the practice history")
                rightClickTip("A preset", "Save the current pattern")
                rightClickTip("A song", "Practise slower, ramp up")
            }
        }
        .padding(12)
        .frame(width: 220)
    }

    private func section<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
            content()
        }
    }

    private func rightClickTip(_ target: LocalizedStringKey, _ action: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(target)
                .font(.system(size: 11, weight: .semibold))
            Text(action)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
    }

    private func row(_ keys: String, _ action: LocalizedStringKey) -> some View {
        HStack {
            Text(verbatim: keys)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.15)))
            Spacer()
            Text(action)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
    }
}
