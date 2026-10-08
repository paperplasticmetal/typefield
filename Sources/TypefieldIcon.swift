import AppKit
import CoreText
import SwiftUI

/// Accent colors retain their stored IDs so existing appearance and Dock choices survive palette revisions.
enum TypefieldPalette: String, CaseIterable, Identifiable {
    case neutral, amber, ocean, forest, plum, rose
    var id: String { rawValue }
    var title: String {
        switch self {
        case .neutral: return "Porcelain"
        case .amber: return "Turmeric"
        case .ocean: return "Indigo"
        case .forest: return "Neem"
        case .plum: return "Jamun"
        case .rose: return "Rose"
        }
    }
    var lightAccent: String {
        switch self {
        case .neutral: return "505968"
        case .amber: return "704C00"
        case .ocean: return "25528B"
        case .forest: return "215D43"
        case .plum: return "68467D"
        case .rose: return "8C3C4D"
        }
    }
    var darkAccent: String {
        switch self {
        case .neutral: return "BAC6D8"
        case .amber: return "E6BA58"
        case .ocean: return "8EB8EF"
        case .forest: return "91CFA5"
        case .plum: return "CBA8DF"
        case .rose: return "EBA2B0"
        }
    }
    static func resolve(_ value: String?) -> Self { Self(rawValue: value ?? "") ?? .neutral }
    func accent(dark: Bool) -> NSColor { Self.color(dark ? darkAccent : lightAccent) }
    /// The light-mode chips can show the pigment at full strength; controls use
    /// darker shades so selected text remains readable on neutral surfaces.
    func swatch(dark: Bool) -> NSColor {
        if dark { return accent(dark: true) }
        let pigment: String
        switch self {
        case .neutral: pigment = lightAccent
        case .amber: pigment = "D9A625"
        case .ocean: pigment = "4A5CA5"
        case .forest: pigment = "438A61"
        case .plum: pigment = "925A9C"
        case .rose: pigment = "C85872"
        }
        return Self.color(pigment)
    }
    static func color(_ hex: String) -> NSColor {
        let value = UInt32(hex, radix: 16) ?? 0
        return NSColor(srgbRed: CGFloat((value >> 16) & 255) / 255, green: CGFloat((value >> 8) & 255) / 255, blue: CGFloat(value & 255) / 255, alpha: 1)
    }
}

enum TypefieldIcon {
    private struct Mark {
        let both: CGPath
    }

    private static let cache: NSCache<NSString, NSImage> = {
        let value = NSCache<NSString, NSImage>()
        value.totalCostLimit = 16 * 1024 * 1024
        value.countLimit = 96
        return value
    }()
    private static var appliedDockKey: String?

    private static func c(_ hex: String, _ alpha: CGFloat = 1) -> NSColor {
        TypefieldPalette.color(hex).withAlphaComponent(alpha)
    }
    private static func fill(_ context: CGContext, _ path: CGPath, _ color: NSColor) {
        context.addPath(path)
        context.setFillColor(color.cgColor)
        context.fillPath()
    }
    private static func stroke(_ context: CGContext, _ path: CGPath, _ color: NSColor, _ width: CGFloat) {
        context.addPath(path)
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(width)
        context.setLineJoin(.round)
        context.setLineCap(.round)
        context.strokePath()
    }
    /// One monogram for the whole color family, including the original Porcelain
    /// icon. The small optical master preserves the serif strokes at Dock sizes.
    private static func mark(size: Int) -> Mark? {
        let font = CTFontCreateWithName("BodoniSvtyTwoITCTT-Bold" as CFString, 700, nil)
        var chars: [UniChar] = [84, 102]
        var glyphs: [CGGlyph] = [0, 0]
        guard CTFontGetGlyphsForCharacters(font, &chars, &glyphs, 2),
              let tSource = CTFontCreatePathForGlyph(font, glyphs[0], nil),
              let fSource = CTFontCreatePathForGlyph(font, glyphs[1], nil) else { return nil }
        let tb = tSource.boundingBoxOfPath
        let fb = fSource.boundingBoxOfPath
        let extendedF = CGMutablePath()
        extendedF.addPath(fSource)
        let y = fb.minY + 289
        let x = fb.minX + 140
        let end = fb.minX + (size <= 32 ? 257 : 247)
        extendedF.move(to: CGPoint(x: x, y: y))
        extendedF.addLine(to: CGPoint(x: x, y: y + 11))
        extendedF.addLine(to: CGPoint(x: end - 6, y: y + 11))
        extendedF.addQuadCurve(to: CGPoint(x: end, y: y + 5), control: CGPoint(x: end, y: y + 11))
        extendedF.addQuadCurve(to: CGPoint(x: end - 6, y: y), control: CGPoint(x: end, y: y))
        extendedF.closeSubpath()
        let rawT = CGMutablePath()
        rawT.addPath(tSource, transform: CGAffineTransform(a: 1, b: 0, c: 0, d: 1,
            tx: -tb.minX, ty: 0))
        let rawF = CGMutablePath()
        rawF.addPath(extendedF, transform: CGAffineTransform(
            translationX: tb.width + (size <= 32 ? 60 : 24) - fb.minX, y: 0))
        let raw = CGMutablePath()
        raw.addPath(rawT)
        raw.addPath(rawF)
        let bounds = raw.boundingBoxOfPath
        let scale = min((size <= 32 ? 760 : 700) / bounds.width, 600 / bounds.height)
        let transform = CGAffineTransform(a: scale, b: 0, c: 0, d: scale,
            tx: 512 - bounds.midX * scale, ty: 510 - bounds.midY * scale)
        let t = CGMutablePath(); t.addPath(rawT, transform: transform)
        let f = CGMutablePath(); f.addPath(rawF, transform: transform)
        let both = CGMutablePath(); both.addPath(t); both.addPath(f)
        return Mark(both: both)
    }

    /// Flat paper and ink pairs keep the type itself in focus. Icon colors are
    /// independent of the control accent palette and retain its stored IDs.
    static func colors(palette: TypefieldPalette, dark: Bool) -> (paper: NSColor, ink: NSColor) {
        let pair: (String, String)
        switch palette {
        case .neutral: pair = dark ? ("171A20", "F3F4F6") : ("F6F7F9", "22262D")
        case .amber: pair = dark ? ("332B20", "E8C97D") : ("E8D2A1", "433720")
        case .ocean: pair = dark ? ("222B3D", "B4C5E8") : ("DDE3EF", "2F3E60")
        case .forest: pair = dark ? ("24362D", "BDD4B8") : ("DFE6D9", "354B3B")
        case .plum: pair = dark ? ("372B37", "D8B9D7") : ("E8DEE7", "593F59")
        case .rose: pair = dark ? ("20201E", "FF6046") : ("FF6046", "20201E")
        }
        return (c(pair.0), c(pair.1))
    }

    private static func draw(_ ctx: CGContext, _ m: Mark, _ palette: TypefieldPalette, _ dark: Bool, _ size: Int) {
        let colors = colors(palette: palette, dark: dark)
        ctx.setFillColor(colors.paper.cgColor)
        ctx.fill(CGRect(x: 64, y: 64, width: 896, height: 896))
        fill(ctx, m.both, colors.ink)
        if size <= 32 { stroke(ctx, m.both, colors.ink, 22) }
    }

    /// The stored palette IDs remain stable for existing preferences and backups.
    static func image(palette: TypefieldPalette, dark: Bool, size: Int = 512) -> NSImage {
        let key = "\(palette.rawValue)-\(dark)-\(size)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let image = NSImage(size: NSSize(width: size, height: size))
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
            let graphics = NSGraphicsContext(bitmapImageRep: bitmap),
            let monogram = mark(size: size) else { return image }
        let context = graphics.cgContext
        context.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
        context.setAllowsAntialiasing(true)
        let tile = CGPath(roundedRect: CGRect(x: 64, y: 64, width: 896, height: 896),
            cornerWidth: 196, cornerHeight: 196, transform: nil)
        context.addPath(tile); context.clip()
        draw(context, monogram, palette, dark, size)
        graphics.flushGraphics()
        image.addRepresentation(bitmap)
        cache.setObject(image, forKey: key, cost: size * size * 4)
        return image
    }

    static func isDark(mode: String, appearance: NSAppearance = NSApp.effectiveAppearance) -> Bool {
        mode == "Dark" || (mode == "Automatic" && appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
    }
    static func isDark(mode: String, scheme: ColorScheme) -> Bool {
        mode == "Dark" || (mode == "Automatic" && scheme == .dark)
    }
    static func apply() {
        let defaults = UserDefaults.standard
        let palette = TypefieldPalette.resolve(defaults.string(forKey: "typefield.iconPalette"))
        let dark = isDark(mode: defaults.string(forKey: "typefield.iconAppearance") ?? "Automatic")
        let key = "dock-\(palette.rawValue)-\(dark)"
        // Several windows observe appearance changes; only the effective icon
        // choice needs to rebuild or update the Dock.
        guard appliedDockKey != key else { return }
        let icon: NSImage
        if let cached = cache.object(forKey: key as NSString) {
            icon = cached
        } else {
            icon = NSImage(size: NSSize(width: 512, height: 512))
            let sizes = [16, 32, 64, 128, 256, 512, 1024]
            for size in sizes {
                if let data = image(palette: palette, dark: dark, size: size).tiffRepresentation,
                   let rep = NSBitmapImageRep(data: data) { rep.size = icon.size; icon.addRepresentation(rep) }
            }
            cache.setObject(icon, forKey: key as NSString, cost: sizes.reduce(0) { $0 + $1 * $1 * 4 })
        }
        NSApp.applicationIconImage = icon
        appliedDockKey = key
    }
}

/// SwiftUI must observe these preferences directly; changing the Dock image alone
/// does not invalidate an `Image(nsImage:)` already shown in another window.
struct TypefieldIconPreview: View {
    let size: CGFloat
    @AppStorage("typefield.iconPalette") private var iconPalette = "neutral"
    @AppStorage("typefield.iconAppearance") private var iconAppearance = "Automatic"
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Image(nsImage: TypefieldIcon.image(
            palette: .resolve(iconPalette),
            dark: TypefieldIcon.isDark(mode: iconAppearance, scheme: scheme),
            size: 128
        ))
        .resizable()
        .interpolation(.high)
        .frame(width: size, height: size)
    }
}
