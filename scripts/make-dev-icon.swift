// Makes the development build's icon: the normal icon with an orange hammer
// badge, so development and release copies are easy to tell apart.
//
//   swift scripts/make-dev-icon.swift
//
// Reads GChat/Assets.xcassets/AppIcon.appiconset/icon-1024.png and writes
// GChat/Assets.xcassets/AppIconDev.appiconset. Run again after changing the
// normal icon.

import AppKit

let assets = URL(fileURLWithPath: "GChat/Assets.xcassets")
let source = assets.appendingPathComponent("AppIcon.appiconset/icon-1024.png")
let target = assets.appendingPathComponent("AppIconDev.appiconset")

guard let base = NSImage(contentsOf: source) else {
    fatalError("Run from the repository root; could not read \(source.path)")
}

func render(size: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let scale = CGFloat(size) / 1024
    base.draw(in: NSRect(x: 0, y: 0, width: size, height: size))

    // Badge in the lower right corner, kept inside the 824-point tile
    // (100 to 924). Anything outside it makes macOS put the whole icon on a
    // grey plate.
    let badge = NSRect(x: 545 * scale, y: 125 * scale, width: 330 * scale, height: 330 * scale)
    NSColor(red: 0.98, green: 0.55, blue: 0.10, alpha: 1).setFill()
    let circle = NSBezierPath(ovalIn: badge)
    circle.fill()
    NSColor.white.setStroke()
    circle.lineWidth = 22 * scale
    circle.stroke()

    let configuration = NSImage.SymbolConfiguration(pointSize: 180 * scale, weight: .bold)
        .applying(.init(paletteColors: [.white]))
    if let hammer = NSImage(systemSymbolName: "hammer.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(configuration) {
        let fit = hammer.size
        let origin = NSPoint(x: badge.midX - fit.width / 2, y: badge.midY - fit.height / 2)
        hammer.draw(in: NSRect(origin: origin, size: fit))
    }

    NSGraphicsContext.current = nil
    return rep.representation(using: .png, properties: [:])!
}

try? FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
for size in [16, 32, 64, 128, 256, 512, 1024] {
    try! render(size: size).write(to: target.appendingPathComponent("icon-\(size).png"))
}
try! FileManager.default.copyItem(
    at: assets.appendingPathComponent("AppIcon.appiconset/Contents.json"),
    to: target.appendingPathComponent("Contents.json.tmp"))
try? FileManager.default.removeItem(at: target.appendingPathComponent("Contents.json"))
try! FileManager.default.moveItem(
    at: target.appendingPathComponent("Contents.json.tmp"),
    to: target.appendingPathComponent("Contents.json"))
print("Wrote \(target.path)")
