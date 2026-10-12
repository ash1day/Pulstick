import AppKit
import SwiftUI

/// 初回起動時だけ出す案内。メニューバー常駐アプリは起動しても何も表示されないので、
/// 「どこにいるのか」と最初に覚えておくと便利なことだけを伝える
enum Welcome {
    private static let shownKey = "pulstick.welcomeShown"
    private static var window: NSWindow?
    private static var closeObserver: NSObjectProtocol?

    @MainActor
    static func showIfFirstLaunch(defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: shownKey) else { return }
        defaults.set(true, forKey: shownKey)
        // 案内を入れる前のバージョンから更新した人には出さない（すでに使い方を知っている）
        let hasUsedBefore = defaults.dictionaryRepresentation().keys.contains {
            $0.hasPrefix("pulstick.") && $0 != shownKey
        }
        guard !hasUsedBefore else { return }

        let window = NSWindow(
            contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false
        )
        window.title = "Pulstick"
        window.isReleasedWhenClosed = false
        // ウインドウ → ビュー → 閉じる処理 → ウインドウ の循環参照を作らないよう弱参照で閉じる
        window.contentView = NSHostingView(rootView: WelcomeView { [weak window] in window?.close() })
        window.center()
        self.window = window
        // 閉じたら保持をやめて解放する
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
                closeObserver = nil
                Welcome.window = nil
            }
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}

struct WelcomeView: View {
    let dismiss: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            HStack(alignment: .top) {
                Spacer()
                // メニューバーの方向（右上）を指して、アイコンの場所を示す
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.accentColor)
            }
            .frame(height: 10)

            // NSApp が無い状況（スナップショット）でも描けるよう、名前からアプリのアイコンを引く
            if let icon = NSImage(named: NSImage.applicationIconName) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 72, height: 72)
            }

            VStack(spacing: 6) {
                Text("Pulstick lives in your menu bar")
                    .font(.system(size: 17, weight: .semibold))
                Text("Click the metronome icon at the top right of the screen to open it.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 10) {
                tip("metronome", Text("Click the icon to set the tempo and press Space to play."))
                tip("command", Text("Press ⌃⌥M in any app to start or stop."))
                tip("power", Text("Turn on “Launch at Login” at the bottom to keep it handy."))
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.08)))

            Button(action: dismiss) {
                Text("Got It")
                    .frame(minWidth: 120)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
        .padding(24)
        .frame(width: 360)
    }

    private func tip(_ symbol: String, _ text: Text) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.accentColor)
                .frame(width: 18)
            text
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
