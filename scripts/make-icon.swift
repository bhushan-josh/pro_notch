// Renders Support/AppIcon.icns. Run: swift scripts/make-icon.swift
import AppKit

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("ProNotch.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func render(size: CGFloat) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = size / 1024
    let tile = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let tilePath = NSBezierPath(roundedRect: tile, xRadius: 185 * s, yRadius: 185 * s)
    NSGradient(colors: [
        NSColor(calibratedRed: 0.36, green: 0.30, blue: 0.95, alpha: 1),
        NSColor(calibratedRed: 0.93, green: 0.33, blue: 0.62, alpha: 1),
    ])!.draw(in: tilePath, angle: -60)

    let island = NSRect(x: 230 * s, y: 560 * s, width: 564 * s, height: 190 * s)
    NSColor.black.setFill()
    NSBezierPath(roundedRect: island, xRadius: 95 * s, yRadius: 95 * s).fill()

    let art = NSRect(x: 280 * s, y: 605 * s, width: 100 * s, height: 100 * s)
    NSGradient(colors: [.systemOrange, .systemPink])!.draw(in: NSBezierPath(roundedRect: art, xRadius: 24 * s, yRadius: 24 * s), angle: 45)

    NSColor.white.setFill()
    let heights: [CGFloat] = [40, 80, 56, 96, 48]
    for (index, height) in heights.enumerated() {
        let x = (590 + CGFloat(index) * 30) * s
        let bar = NSRect(x: x, y: (655 - height / 2) * s, width: 16 * s, height: height * s)
        NSBezierPath(roundedRect: bar, xRadius: 8 * s, yRadius: 8 * s).fill()
    }

    NSColor.white.withAlphaComponent(0.9).setFill()
    let progress = NSRect(x: 230 * s, y: 330 * s, width: 564 * s, height: 26 * s)
    NSColor.white.withAlphaComponent(0.3).setFill()
    NSBezierPath(roundedRect: progress, xRadius: 13 * s, yRadius: 13 * s).fill()
    NSColor.white.setFill()
    NSBezierPath(roundedRect: NSRect(x: progress.minX, y: progress.minY, width: progress.width * 0.62, height: progress.height), xRadius: 13 * s, yRadius: 13 * s).fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try render(size: CGFloat(base * scale)).write(to: iconset.appendingPathComponent(name))
    }
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", root.appendingPathComponent("Support/AppIcon.icns").path]
try process.run()
process.waitUntilExit()
print(process.terminationStatus == 0 ? "Wrote Support/AppIcon.icns" : "iconutil failed")
