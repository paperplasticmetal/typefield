import AppKit
import CoreText
import SwiftUI

/// Accent colors retain their stored IDs; the Dock renderer gives each ID its own design.
enum TypefieldPalette: String, CaseIterable, Identifiable {
    case neutral, amber, ocean, forest, plum, rose
    var id: String { rawValue }
    var title: String { switch self { case .neutral: return "Porcelain"; case .amber: return "Amber"; case .ocean: return "Ocean"; case .forest: return "Forest"; case .plum: return "Plum"; case .rose: return "Rose" } }
    var lightAccent: String { switch self { case .neutral: return "505968"; case .amber: return "885317"; case .ocean: return "235F9A"; case .forest: return "28664E"; case .plum: return "76538F"; case .rose: return "984C60" } }
    var darkAccent: String { switch self { case .neutral: return "BAC6D8"; case .amber: return "E3A857"; case .ocean: return "85BAED"; case .forest: return "87CBA9"; case .plum: return "C7A9E3"; case .rose: return "EDABBB" } }
    static func resolve(_ value: String?) -> Self { Self(rawValue: value ?? "") ?? .neutral }
    func accent(dark: Bool) -> NSColor { Self.color(dark ? darkAccent : lightAccent) }
    static func color(_ hex: String) -> NSColor {
        let value = UInt32(hex, radix: 16) ?? 0
        return NSColor(srgbRed: CGFloat((value >> 16) & 255) / 255, green: CGFloat((value >> 8) & 255) / 255, blue: CGFloat(value & 255) / 255, alpha: 1)
    }
}

enum TypefieldIcon {
    private struct Mark {
        let t: CGPath
        let f: CGPath
        let both: CGPath
        let bounds: CGRect
    }

    private static let cache: NSCache<NSString, NSImage> = {
        let value = NSCache<NSString, NSImage>()
        value.totalCostLimit = 16 * 1024 * 1024
        value.countLimit = 96
        return value
    }()

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
    private static func moved(_ path: CGPath, _ x: CGFloat, _ y: CGFloat) -> CGPath {
        var transform = CGAffineTransform(translationX: x, y: y)
        return path.copy(using: &transform) ?? path
    }
    private static func rotated(_ path: CGPath, _ angle: CGFloat) -> CGPath {
        let center = CGPoint(x: path.boundingBoxOfPath.midX, y: path.boundingBoxOfPath.midY)
        var transform = CGAffineTransform(translationX: center.x, y: center.y)
            .rotated(by: angle).translatedBy(x: -center.x, y: -center.y)
        return path.copy(using: &transform) ?? path
    }
    private static func line(_ context: CGContext, _ x1: CGFloat, _ y1: CGFloat,
                             _ x2: CGFloat, _ y2: CGFloat, _ color: NSColor, _ width: CGFloat) {
        context.beginPath()
        context.move(to: CGPoint(x: x1, y: y1))
        context.addLine(to: CGPoint(x: x2, y: y2))
        context.setStrokeColor(color.cgColor)
        context.setLineCap(.round)
        context.setLineWidth(width)
        context.strokePath()
    }
    private static func dot(_ context: CGContext, _ x: CGFloat, _ y: CGFloat,
                            _ radius: CGFloat, _ color: NSColor) {
        context.setFillColor(color.cgColor)
        context.fillEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
    }
    private static func gradient(_ context: CGContext, top: NSColor, bottom: NSColor) {
        guard let value = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [bottom.cgColor, top.cgColor] as CFArray, locations: [0, 1]) else { return }
        context.drawLinearGradient(value, start: CGPoint(x: 0, y: 64),
            end: CGPoint(x: 0, y: 960), options: [])
    }
    private static func random(_ state: inout UInt32) -> CGFloat {
        state = state &* 1_664_525 &+ 1_013_904_223
        return CGFloat(state & 0xffff) / 65535
    }
    private static func grain(_ context: CGContext, size: Int, seed: UInt32,
                              count: Int, color: NSColor, radius: ClosedRange<CGFloat>) {
        guard size >= 64 else { return }
        var state = seed
        for _ in 0..<count {
            let x = 90 + random(&state) * 844
            let y = 90 + random(&state) * 844
            let r = radius.lowerBound + random(&state) * (radius.upperBound - radius.lowerBound)
            dot(context, x, y, r, color)
        }
    }
    private static func label(_ text: String, _ context: CGContext,
                              _ x: CGFloat, _ y: CGFloat, _ color: NSColor) {
        let attr: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 26, weight: .medium),
            .foregroundColor: color
        ]
        let textLine = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attr))
        context.textPosition = CGPoint(x: x, y: y)
        CTLineDraw(textLine, context)
    }

    /// Extend Bodoni's tiny f bar and tighten its gap to the T. Small sizes get
    /// a little more separation because they have fewer physical pixels.
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
        rawT.addPath(tSource, transform: CGAffineTransform(translationX: -tb.minX, y: 0))
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
        return Mark(t: t, f: f, both: both, bounds: both.boundingBoxOfPath)
    }

    private static func porcelain(_ ctx: CGContext, _ m: Mark, _ dark: Bool, _ size: Int) {
        ctx.setFillColor(c(dark ? "171A20" : "F6F7F9").cgColor)
        ctx.fill(CGRect(x: 64, y: 64, width: 896, height: 896))
        let ink = c(dark ? "F3F4F6" : "22262D")
        fill(ctx, m.both, ink)
        if size <= 32 { stroke(ctx, m.both, ink, 22) }
    }

    private static func paperPlay(_ ctx: CGContext, _ m: Mark, _ dark: Bool, _ size: Int) {
        gradient(ctx, top: c(dark ? "43302D" : "FFE9CC"), bottom: c(dark ? "261D25" : "F5D9BF"))
        dot(ctx, 759, 730, 165, c(dark ? "EF9F56" : "FFB35F", 0.70))
        dot(ctx, 231, 290, 130, c(dark ? "498FA3" : "83C5C4", 0.74))
        let t = rotated(m.t, -0.045)
        let f = rotated(m.f, 0.065)
        fill(ctx, moved(t, 16, -23), c(dark ? "66332E" : "C75D51"))
        fill(ctx, moved(f, 16, -23), c(dark ? "1C4351" : "35617B"))
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 12, height: -16), blur: 18,
            color: c("49382D", dark ? 0.45 : 0.24).cgColor)
        fill(ctx, t, c(dark ? "FFB467" : "EE754E"))
        fill(ctx, f, c(dark ? "B4E9D8" : "245D73"))
        ctx.restoreGState()
        if size <= 32 {
            stroke(ctx, t, c(dark ? "FFB467" : "EE754E"), 21)
            stroke(ctx, f, c(dark ? "B4E9D8" : "245D73"), 21)
        }
        if size >= 64 {
            dot(ctx, 793, 324, 21, c(dark ? "F7D779" : "D44850"))
            dot(ctx, 224, 697, 12, c(dark ? "A4DCD0" : "287991"))
        }
    }

    private static func typeStudy(_ ctx: CGContext, _ m: Mark, _ dark: Bool, _ size: Int) {
        gradient(ctx, top: c(dark ? "18394B" : "EAF7F8"), bottom: c(dark ? "102531" : "DDECF0"))
        let guide = c(dark ? "70B8C3" : "4B9CA9", dark ? 0.55 : 0.48)
        let baseline = m.bounds.minY + 7
        let cap = m.bounds.maxY - 8
        let xHeight = baseline + (cap - baseline) * 0.52
        for (y, width) in [(baseline, CGFloat(5)), (xHeight, CGFloat(3)), (cap, CGFloat(3))] {
            line(ctx, 123, y, 901, y, guide, width)
            if size >= 64 { dot(ctx, 124, y, 8, guide); dot(ctx, 899, y, 8, guide) }
        }
        if size >= 128 {
            for x in stride(from: 176, through: 856, by: 68) { line(ctx, CGFloat(x), 145, CGFloat(x), 160, guide, 3) }
            label("CAP", ctx, 132, cap + 18, guide)
            label("x", ctx, 132, xHeight + 18, guide)
            label("BASE", ctx, 132, baseline - 43, guide)
        }
        let ink = c(dark ? "F1F9F6" : "183949")
        fill(ctx, m.both, ink)
        if size <= 32 { stroke(ctx, m.both, ink, 22) }
        if size >= 64 {
            dot(ctx, m.bounds.minX - 25, baseline, 13, c(dark ? "FFBE7F" : "E87951"))
            dot(ctx, m.bounds.maxX + 25, xHeight, 13, c(dark ? "FFBE7F" : "E87951"))
        }
    }

    private static func inkSketch(_ ctx: CGContext, _ m: Mark, _ dark: Bool, _ size: Int) {
        gradient(ctx, top: c(dark ? "2D3640" : "F9F2E5"),
            bottom: c(dark ? "18222A" : "E9DAC2"))
        let tb = m.t.boundingBoxOfPath
        let fb = m.f.boundingBoxOfPath
        let ink = c(dark ? "DEE9E7" : "1A3944")
        let deep = c(dark ? "9FB8B9" : "061922")

        if size >= 64 {
            // A broad pen enters the cap. Its pressure widens, then joins
            // the unmodified T instead of turning the letters into script.
            let entry = CGMutablePath()
            entry.move(to: CGPoint(x: tb.minX - 55, y: tb.maxY + 31))
            entry.addCurve(to: CGPoint(x: tb.minX + 168, y: tb.maxY - 12),
                control1: CGPoint(x: tb.minX + 28, y: tb.maxY + 42),
                control2: CGPoint(x: tb.minX + 100, y: tb.maxY + 6))
            entry.addCurve(to: CGPoint(x: tb.minX + 22, y: tb.maxY - 18),
                control1: CGPoint(x: tb.minX + 119, y: tb.maxY - 26),
                control2: CGPoint(x: tb.minX + 62, y: tb.maxY - 27))
            entry.addQuadCurve(to: CGPoint(x: tb.minX - 55, y: tb.maxY + 31),
                control: CGPoint(x: tb.minX - 23, y: tb.maxY + 6))
            entry.closeSubpath()
            fill(ctx, entry, ink)

            // The f serif releases a single broad-to-fine ink stroke.
            // A small uneven pool at the join resolves into a sharp nib tip.
            let tail = CGMutablePath()
            tail.move(to: CGPoint(x: fb.minX + 119, y: fb.minY + 15))
            tail.addCurve(to: CGPoint(x: fb.maxX + 8, y: fb.minY - 18),
                control1: CGPoint(x: fb.minX + 176, y: fb.minY + 15),
                control2: CGPoint(x: fb.maxX - 8, y: fb.minY - 13))
            tail.addCurve(to: CGPoint(x: fb.minX + 189, y: fb.minY - 36),
                control1: CGPoint(x: fb.maxX - 3, y: fb.minY - 27),
                control2: CGPoint(x: fb.minX + 237, y: fb.minY - 39))
            tail.addCurve(to: CGPoint(x: fb.minX + 119, y: fb.minY + 15),
                control1: CGPoint(x: fb.minX + 148, y: fb.minY - 35),
                control2: CGPoint(x: fb.minX + 108, y: fb.minY - 9))
            tail.closeSubpath()
            fill(ctx, tail, ink)
            ctx.setFillColor(ink.cgColor)
            ctx.fillEllipse(in: CGRect(x: fb.maxX - 12, y: fb.minY - 27, width: 23, height: 14))
        }
        fill(ctx, m.both, ink)
        if size <= 32 { stroke(ctx, m.both, ink, 22) }

        if size >= 64 {
            ctx.saveGState()
            ctx.addPath(m.both)
            ctx.clip()
            // Darker deposits at cap joins and serif ends make the wet ink
            // visible at settings-card size, without outlining the glyph.
            ctx.setFillColor(deep.withAlphaComponent(dark ? 0.34 : 0.50).cgColor)
            ctx.fillEllipse(in: CGRect(x: tb.minX + 120, y: tb.maxY - 74, width: 148, height: 95))
            ctx.fillEllipse(in: CGRect(x: fb.minX + 58, y: fb.maxY - 83, width: 148, height: 95))
            ctx.fillEllipse(in: CGRect(x: fb.minX + 95, y: fb.minY - 11, width: 136, height: 61))

            let dry = c(dark ? "243943" : "E0D8C1", dark ? 0.78 : 0.82)
            let tDrag = CGMutablePath()
            tDrag.move(to: CGPoint(x: tb.midX - 24, y: tb.maxY - 91))
            tDrag.addCurve(to: CGPoint(x: tb.midX - 35, y: tb.maxY - 281),
                control1: CGPoint(x: tb.midX - 16, y: tb.maxY - 139),
                control2: CGPoint(x: tb.midX - 37, y: tb.maxY - 226))
            tDrag.addQuadCurve(to: CGPoint(x: tb.midX - 55, y: tb.maxY - 185),
                control: CGPoint(x: tb.midX - 44, y: tb.maxY - 271))
            tDrag.addQuadCurve(to: CGPoint(x: tb.midX - 24, y: tb.maxY - 91),
                control: CGPoint(x: tb.midX - 36, y: tb.maxY - 131))
            tDrag.closeSubpath()
            fill(ctx, tDrag, dry)

            let fDrag = CGMutablePath()
            fDrag.move(to: CGPoint(x: fb.minX + 84, y: fb.maxY - 114))
            fDrag.addCurve(to: CGPoint(x: fb.minX + 75, y: fb.maxY - 286),
                control1: CGPoint(x: fb.minX + 91, y: fb.maxY - 166),
                control2: CGPoint(x: fb.minX + 67, y: fb.maxY - 247))
            fDrag.addQuadCurve(to: CGPoint(x: fb.minX + 53, y: fb.maxY - 201),
                control: CGPoint(x: fb.minX + 60, y: fb.maxY - 277))
            fDrag.addQuadCurve(to: CGPoint(x: fb.minX + 84, y: fb.maxY - 114),
                control: CGPoint(x: fb.minX + 76, y: fb.maxY - 153))
            fDrag.closeSubpath()
            fill(ctx, fDrag, dry)

            ctx.restoreGState()
        }
    }

    private static func chalkboard(_ ctx: CGContext, _ m: Mark, _ dark: Bool, _ size: Int) {
        gradient(ctx, top: c(dark ? "202332" : "3A3650"), bottom: c(dark ? "10131E" : "29283D"))
        if size >= 64 {
            for i in 0..<4 {
                let y = CGFloat(306 + i * 119)
                line(ctx, 125, y, 860, y + 40, c("D8D6E3", 0.07), 24)
            }
            grain(ctx, size: size, seed: 0xCA1C, count: 850,
                color: c("E4E2ED", 0.19), radius: 1.4...5.5)
            stroke(ctx, moved(m.both, 8, -7), c("FFFFFF", 0.22), 23)
        }
        let chalk = c(dark ? "F4F1E5" : "F7F3E9", 0.94)
        fill(ctx, m.both, chalk)
        stroke(ctx, m.both, c("FFFFFF", 0.46), size <= 32 ? 22 : 8)
        if size >= 64 {
            ctx.saveGState(); ctx.addPath(m.both); ctx.clip()
            for i in 0..<24 {
                let x = CGFloat(139 + i * 30)
                line(ctx, x, 212, x + 200, 822,
                    c(dark ? "242637" : "3C384F", 0.28), 12)
            }
            grain(ctx, size: size, seed: 0xC004, count: 1000,
                color: c(dark ? "242637" : "3C384F", 0.62), radius: 2.5...7.0)
            ctx.restoreGState()
            let dust = c("F4F0E7", 0.26)
            for i in 0..<5 {
                let y = CGFloat(206 + i * 5)
                line(ctx, 625, y, 833, y + CGFloat(i % 2) * 3, dust, CGFloat(2 + i % 3))
            }
        }
    }

    private static func pressedType(_ ctx: CGContext, _ m: Mark, _ dark: Bool, _ size: Int) {
        gradient(ctx, top: c(dark ? "704854" : "F5DDE0"), bottom: c(dark ? "3E2735" : "DDBFC4"))
        let border = CGPath(roundedRect: CGRect(x: 99, y: 99, width: 826, height: 826),
            cornerWidth: 157, cornerHeight: 157, transform: nil)
        stroke(ctx, border, c(dark ? "DBA3AA" : "FFF4E9", 0.36), 4)
        grain(ctx, size: size, seed: 0xEA175, count: 480,
            color: c(dark ? "E9B9B4" : "9D6B73", 0.12), radius: 0.8...2.4)
        for step in (1...17).reversed() {
            let offset = CGFloat(step) * 2.4
            fill(ctx, moved(m.both, offset, -offset),
                c(dark ? "2D1B2A" : "8E5868", 0.12 + CGFloat(18 - step) * 0.013))
        }
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 8, height: -10), blur: 13,
            color: c("381D2A", dark ? 0.54 : 0.25).cgColor)
        fill(ctx, m.both, c(dark ? "FFE5DB" : "FFF8E9"))
        ctx.restoreGState()
        ctx.saveGState(); ctx.addPath(m.both); ctx.clip()
        gradient(ctx, top: c(dark ? "FFF4E5" : "FFFDF2"), bottom: c(dark ? "D4A8A7" : "E5C8BE"))
        ctx.restoreGState()
        stroke(ctx, moved(m.both, -2, 3), c("FFFFFF", dark ? 0.22 : 0.39), size <= 32 ? 20 : 5)
        // The light relief needs a darker optical master at actual Dock sizes.
        if size <= 32 && !dark {
            let smallInk = c("704452")
            fill(ctx, m.both, smallInk)
            stroke(ctx, m.both, smallInk, 16)
        }
    }

    /// The stored palette IDs are also the icon design IDs for existing preferences and backups.
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
        switch palette {
        case .neutral: porcelain(context, monogram, dark, size)
        case .amber: paperPlay(context, monogram, dark, size)
        case .ocean: typeStudy(context, monogram, dark, size)
        case .forest: inkSketch(context, monogram, dark, size)
        case .plum: chalkboard(context, monogram, dark, size)
        case .rose: pressedType(context, monogram, dark, size)
        }
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
