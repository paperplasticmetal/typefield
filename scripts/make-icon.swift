import AppKit
import Foundation

// Run from the repository root: swift -module-cache-path .build/module-cache scripts/make-icon.swift
let assets = URL(fileURLWithPath: "Resources/Assets.xcassets/AppIcon.appiconset", isDirectory: true)
var pngBySize: [Int: Data] = [:]

let sizes: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024)
]
for (name, size) in sizes {
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
        let context = NSGraphicsContext(bitmapImageRep: bitmap) else { fatalError("Bitmap unavailable") }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    let scale = CGFloat(size) / 1024
    context.cgContext.scaleBy(x: scale, y: scale)

    // A strong T sits in a small field of baselines. All shapes stay legible at menu size.
    NSColor(calibratedRed: 0.07, green: 0.12, blue: 0.18, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 28, y: 28, width: 968, height: 968), xRadius: 212, yRadius: 212).fill()
    NSColor(calibratedRed: 0.96, green: 0.75, blue: 0.38, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 202, y: 686, width: 620, height: 104), xRadius: 25, yRadius: 25).fill()
    NSBezierPath(roundedRect: NSRect(x: 457, y: 237, width: 110, height: 498), xRadius: 28, yRadius: 28).fill()
    NSColor(calibratedRed: 0.50, green: 0.72, blue: 0.72, alpha: 1).setFill()
    for (x, width, y) in [(210.0, 162.0, 504.0), (210.0, 162.0, 367.0), (652.0, 162.0, 504.0), (652.0, 162.0, 367.0)] {
        NSBezierPath(roundedRect: NSRect(x: x, y: y, width: width, height: 38), xRadius: 19, yRadius: 19).fill()
    }
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("PNG unavailable") }
    try png.write(to: assets.appendingPathComponent(name), options: .atomic)
    pngBySize[size] = png
}

func bigEndian(_ value: Int) -> [UInt8] {
    let value = UInt32(value)
    return [UInt8((value >> 24) & 255), UInt8((value >> 16) & 255), UInt8((value >> 8) & 255), UInt8(value & 255)]
}
let elements: [(String, Int)] = [("icp4", 16), ("icp5", 32), ("icp6", 64), ("ic07", 128), ("ic08", 256), ("ic09", 512), ("ic10", 1024)]
var body = Data()
for (kind, size) in elements {
    let png = pngBySize[size]!
    body.append(contentsOf: kind.utf8)
    body.append(contentsOf: bigEndian(png.count + 8))
    body.append(png)
}
var icns = Data("icns".utf8)
icns.append(contentsOf: bigEndian(body.count + 8))
icns.append(body)
try icns.write(to: URL(fileURLWithPath: "Resources/AppIcon.icns"), options: .atomic)
print("Generated Typefield icon assets")
