import AppKit
import Foundation

// swiftc -module-cache-path .build/module-cache Sources/TypefieldIcon.swift scripts/render-icon-gallery.swift -o /tmp/typefield-render-icon-gallery
// /tmp/typefield-render-icon-gallery /tmp/typefield-icon-gallery.png
@main enum RenderIconGallery {
    static func main() throws {
        let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "/tmp/typefield-icon-gallery.png")
        let width = 1200, height = 530
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
            let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else { throw CocoaError(.fileWriteUnknown) }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSColor(srgbRed: 0.95, green: 0.95, blue: 0.96, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)).fill()
        let names = ["Porcelain", "Ochre", "Indigo", "Sage", "Plum", "Coral"]
        let titleStyle: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 17, weight: .semibold), .foregroundColor: NSColor.black]
        let smallStyle: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.darkGray]
        for (index, design) in TypefieldPalette.allCases.enumerated() {
            let x = CGFloat(25 + index * 196)
            (names[index] as NSString).draw(at: NSPoint(x: x, y: 493), withAttributes: titleStyle)
            for (row, dark) in [false, true].enumerated() {
                let y = CGFloat(row == 0 ? 280 : 40)
                ((dark ? "Dark" : "Light") as NSString).draw(at: NSPoint(x: x, y: y + 196), withAttributes: smallStyle)
                TypefieldIcon.image(palette: design, dark: dark, size: 256)
                    .draw(in: NSRect(x: x, y: y + 54, width: 128, height: 128))
                TypefieldIcon.image(palette: design, dark: dark, size: 32)
                    .draw(in: NSRect(x: x + 138, y: y + 124, width: 32, height: 32))
                TypefieldIcon.image(palette: design, dark: dark, size: 16)
                    .draw(in: NSRect(x: x + 146, y: y + 76, width: 16, height: 16))
            }
        }
        graphics.flushGraphics()
        guard let data = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        try data.write(to: output, options: .atomic)
        print(output.path)
    }
}
