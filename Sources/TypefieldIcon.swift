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
        gradient(ctx, top: c(dark ? "28372D" : "F3EAD4"), bottom: c(dark ? "18261F" : "E8D8B7"))
        let ink = c(dark ? "DDE9CA" : "213A2B")
        // The other icon directions share Bodoni. This one changes the actual
        // lettering to a flowing pen hand, with thick downstrokes and fine joins.
        let handName = size <= 32 ? "Baskerville-BoldItalic" : "SnellRoundhand-Black"
        let font = CTFontCreateWithName(handName as CFString, 700, nil)
        var chars: [UniChar] = [84, 102]
        var glyphs: [CGGlyph] = [0, 0]
        guard CTFontGetGlyphsForCharacters(font, &chars, &glyphs, 2),
              let t = CTFontCreatePathForGlyph(font, glyphs[0], nil),
              let f = CTFontCreatePathForGlyph(font, glyphs[1], nil) else {
            fill(ctx, m.both, ink)
            return
        }
        let tb = t.boundingBoxOfPath
        let fb = f.boundingBoxOfPath
        let raw = CGMutablePath()
        raw.addPath(t, transform: CGAffineTransform(translationX: -tb.minX, y: 0))
        raw.addPath(f, transform: CGAffineTransform(translationX: tb.width + (size <= 32 ? 18 : -7) - fb.minX, y: 0))
        let bounds = raw.boundingBoxOfPath
        let scale = min((size <= 32 ? 765 : 730) / bounds.width, 650 / bounds.height)
        let transform = CGAffineTransform(a: scale, b: 0, c: 0, d: scale,
            tx: 512 - bounds.midX * scale, ty: 508 - bounds.midY * scale)
        let hand = CGMutablePath(); hand.addPath(raw, transform: transform)
        fill(ctx, hand, ink)
        stroke(ctx, hand, ink, size <= 32 ? 28 : size <= 64 ? 12 : 6)
        if size >= 128 {
            // A tapered exit made with the same pen completes the lower f stroke.
            let exit = CGMutablePath()
            exit.move(to: CGPoint(x: 604, y: 354))
            exit.addCurve(to: CGPoint(x: 841, y: 409),
                control1: CGPoint(x: 680, y: 342), control2: CGPoint(x: 788, y: 365))
            exit.addQuadCurve(to: CGPoint(x: 755, y: 377), control: CGPoint(x: 819, y: 401))
            exit.addCurve(to: CGPoint(x: 604, y: 354),
                control1: CGPoint(x: 708, y: 361), control2: CGPoint(x: 647, y: 351))
            exit.closeSubpath()
            fill(ctx, exit, ink)
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
