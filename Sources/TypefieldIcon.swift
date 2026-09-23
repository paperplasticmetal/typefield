import AppKit
import CoreText
import SwiftUI

/// Shared, opaque color pairs keep appearance and Dock artwork coherent.
enum TypefieldPalette: String, CaseIterable, Identifiable {
    case neutral, amber, ocean, forest, plum, rose
    var id: String { rawValue }
    var title: String { switch self { case .neutral: return "Porcelain"; case .amber: return "Amber"; case .ocean: return "Ocean"; case .forest: return "Forest"; case .plum: return "Plum"; case .rose: return "Rose" } }
    var lightAccent: String { switch self { case .neutral: return "505968"; case .amber: return "885317"; case .ocean: return "235F9A"; case .forest: return "28664E"; case .plum: return "76538F"; case .rose: return "984C60" } }
    var darkAccent: String { switch self { case .neutral: return "BAC6D8"; case .amber: return "E3A857"; case .ocean: return "85BAED"; case .forest: return "87CBA9"; case .plum: return "C7A9E3"; case .rose: return "EDABBB" } }
    var paper: String { switch self { case .neutral: return "F6F7F9"; case .amber: return "FAF4E9"; case .ocean: return "EEF5FB"; case .forest: return "EFF6F1"; case .plum: return "F5F0FA"; case .rose: return "FBF0F3" } }
    var night: String { switch self { case .neutral: return "171A20"; case .amber: return "211C16"; case .ocean: return "141E29"; case .forest: return "15221C"; case .plum: return "211B29"; case .rose: return "281B21" } }
    static func resolve(_ value: String?) -> Self { Self(rawValue: value ?? "") ?? .neutral }
    func accent(dark: Bool) -> NSColor { Self.color(dark ? darkAccent : lightAccent) }
    static func color(_ hex: String) -> NSColor {
        let value = UInt32(hex, radix: 16) ?? 0
        return NSColor(srgbRed: CGFloat((value >> 16) & 255) / 255, green: CGFloat((value >> 8) & 255) / 255, blue: CGFloat(value & 255) / 255, alpha: 1)
    }
}

enum TypefieldIcon {
    private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.totalCostLimit = 16 * 1024 * 1024
        cache.countLimit = 96
        return cache
    }()
    /// Conventional type outlines, with explicit separation instead of an H-like ligature.
    /// Paths stay vector-backed at every Dock size; no raster generation artifacts.
    static func image(palette: TypefieldPalette, dark: Bool, size: Int = 512) -> NSImage {
        let key = "\(palette.rawValue)-\(dark)-\(size)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let image = NSImage(size: NSSize(width: size, height: size))
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
            let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else { return image }
        let context = graphics.cgContext
        context.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
        context.setAllowsAntialiasing(true)
        let tile = CGPath(roundedRect: CGRect(x: 64, y: 64, width: 896, height: 896), cornerWidth: 196, cornerHeight: 196, transform: nil)
        context.addPath(tile)
        context.setFillColor(TypefieldPalette.color(dark ? palette.night : palette.paper).cgColor)
        context.fillPath()
        // This is native outline rendering, not a font binary bundled or redistributed.
        let font = CTFontCreateWithName("HelveticaNeue-Bold" as CFString, 700, nil)
        var chars: [UniChar] = [116, 102]
        var glyphs: [CGGlyph] = [0, 0]
        CTFontGetGlyphsForCharacters(font, &chars, &glyphs, 2)
        let outlines = glyphs.compactMap { CTFontCreatePathForGlyph(font, $0, nil) }
        let combined = CGMutablePath()
        var x: CGFloat = 0
        for path in outlines {
            let bounds = path.boundingBoxOfPath
            let transform = CGAffineTransform(translationX: x - bounds.minX, y: 0)
            combined.addPath(path, transform: transform)
            x += bounds.width + (size <= 32 ? 96 : 64)
        }
        let bounds = combined.boundingBoxOfPath
        let scale = min((size <= 32 ? 630 : 590) / bounds.width, 560 / bounds.height)
        context.translateBy(x: 512 - bounds.midX * scale, y: 510 - bounds.midY * scale)
        context.scaleBy(x: scale, y: scale)
        context.addPath(combined)
        let ink = palette == .neutral ? TypefieldPalette.color(dark ? "F3F4F6" : "22262D") : palette.accent(dark: dark)
        context.setFillColor(ink.cgColor)
        context.fillPath()
        graphics.flushGraphics()
        image.addRepresentation(bitmap)
        cache.setObject(image, forKey: key, cost: size * size * 4)
        return image
    }
    static func isDark(mode: String, appearance: NSAppearance = NSApp.effectiveAppearance) -> Bool {
        mode == "Dark" || (mode == "Automatic" && appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
    }
    static func apply() {
        let defaults = UserDefaults.standard
        let palette = TypefieldPalette.resolve(defaults.string(forKey: "typefield.iconPalette"))
        let dark = isDark(mode: defaults.string(forKey: "typefield.iconAppearance") ?? "Automatic")
        let icon = NSImage(size: NSSize(width: 512, height: 512))
        for size in [16, 32, 64, 128, 256, 512, 1024] {
            if let data = image(palette: palette, dark: dark, size: size).tiffRepresentation,
               let rep = NSBitmapImageRep(data: data) { rep.size = icon.size; icon.addRepresentation(rep) }
        }
        NSApp.applicationIconImage = icon
    }
}
