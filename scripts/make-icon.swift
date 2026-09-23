import AppKit
import Foundation

// swiftc -module-cache-path .build/module-cache Sources/TypefieldIcon.swift scripts/make-icon.swift -o /tmp/typefield-make-icon
// /tmp/typefield-make-icon
@main enum MakeTypefieldIcon { static func main() throws {
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
    let icon = TypefieldIcon.image(palette: .neutral, dark: false, size: size)
    guard let bitmap = icon.representations.first as? NSBitmapImageRep,
          let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("PNG unavailable") }
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

} }
