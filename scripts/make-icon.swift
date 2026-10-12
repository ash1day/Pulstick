// アプリアイコン（Resources/AppIcon.icns）を生成する。
// 使い方: swift scripts/make-icon.swift
// LP のブランドカラーの角丸四角形に、SF Symbols のメトロノームを白で重ねる。
import AppKit

let sizes = [16, 32, 64, 128, 256, 512, 1024]
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func render(size: Int) -> Data {
    let pixels = CGFloat(size)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // macOS のアイコン格子に合わせ、周囲に約 10% の余白を取った角丸四角形
    let inset = pixels * 0.1
    let tile = NSRect(x: inset, y: inset, width: pixels - inset * 2, height: pixels - inset * 2)
    let radius = tile.width * 0.225
    let path = NSBezierPath(roundedRect: tile, xRadius: radius, yRadius: radius)

    // 影
    NSGraphicsContext.current?.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
    shadow.shadowOffset = NSSize(width: 0, height: -pixels * 0.01)
    shadow.shadowBlurRadius = pixels * 0.02
    shadow.set()
    NSColor(red: 0.91, green: 0.36, blue: 0.23, alpha: 1).setFill()
    path.fill()
    NSGraphicsContext.current?.restoreGraphicsState()

    // 上が明るいグラデーションで立体感を出す
    NSGradient(colors: [
        NSColor(red: 0.98, green: 0.52, blue: 0.33, alpha: 1),
        NSColor(red: 0.85, green: 0.29, blue: 0.18, alpha: 1),
    ])!.draw(in: path, angle: -90)

    // メトロノームの記号を白で中央に
    let config = NSImage.SymbolConfiguration(pointSize: tile.width * 0.52, weight: .semibold)
        .applying(.init(paletteColors: [.white]))
    if let symbol = NSImage(systemSymbolName: "metronome.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(config)
    {
        let symbolSize = symbol.size
        let origin = NSPoint(x: tile.midX - symbolSize.width / 2, y: tile.midY - symbolSize.height / 2)
        symbol.draw(in: NSRect(origin: origin, size: symbolSize))
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for size in sizes where size <= 512 {
    try render(size: size).write(to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    try render(size: size * 2).write(to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
try render(size: 1024).write(to: root.appendingPathComponent("docs/icon.png"))

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", root.appendingPathComponent("Resources/AppIcon.icns").path]
try process.run()
process.waitUntilExit()
print(process.terminationStatus == 0 ? "Wrote Resources/AppIcon.icns and docs/icon.png" : "iconutil failed")
