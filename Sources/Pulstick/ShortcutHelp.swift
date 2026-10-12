import SwiftUI

/// フッターから開くショートカット一覧。ツールチップだけでは
/// グローバルショートカット（⌃⌥M など）の存在に気付きにくいため
struct ShortcutHelp: View {
    let hotKeys: GlobalHotKeys?
    let presetCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if hotKeys?.isToggleAvailable == true || hotKeys?.isTapAvailable == true {
                section("From any app") {
                    if hotKeys?.isToggleAvailable == true { row("⌃⌥M", "Play / Stop") }
                    if hotKeys?.isTapAvailable == true { row("⌃⌥T", "Tap tempo") }
                }
            }
            section("In this window") {
                ForEach(PopoverShortcut.all(presetCount: presetCount), id: \.display) { shortcut in
                    row(shortcut.display, shortcut.label)
                }
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
