import CoreText
import SwiftUI

/// Shape once in font coordinates, then compare faces at one visible x-height.
/// Font metrics alone differ slightly from the actual lowercase ink in Courier.
enum TourSpecimens {
    struct Face {
        let name: String
        let postScriptName: String
    }
    static let faces = [
        Face(name: "Baskerville", postScriptName: "Baskerville"),
        Face(name: "Helvetica Neue", postScriptName: "HelveticaNeue-Bold"),
        Face(name: "Courier", postScriptName: "Courier-Bold")
    ]

    struct Outline {
        let path: CGPath
        let resolvedFont: String
        var bounds: CGRect { path.boundingBoxOfPath }

        init(face: Face) {
            let font = CTFontCreateWithName(face.postScriptName as CFString, 1000, nil)
            resolvedFont = CTFontCopyPostScriptName(font) as String
            var character: UniChar = 120
            var glyph: CGGlyph = 0
            let hasX = CTFontGetGlyphsForCharacters(font, &character, &glyph, 1)
            let xBounds = hasX ? CTFontCreatePathForGlyph(font, glyph, nil)?.boundingBoxOfPath : nil
            let xHeight = max(xBounds?.height ?? CTFontGetXHeight(font), 1)
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: "Hello", attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font
            ]))
            let word = CGMutablePath()
            for run in CTLineGetGlyphRuns(line) as! [CTRun] {
                let count = CTRunGetGlyphCount(run)
                var glyphs = [CGGlyph](repeating: 0, count: count)
                var positions = [CGPoint](repeating: .zero, count: count)
                CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
                CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
                for index in 0..<count {
                    if let contour = CTFontCreatePathForGlyph(font, glyphs[index], nil) {
                        word.addPath(contour, transform: CGAffineTransform(translationX: positions[index].x, y: positions[index].y))
                    }
                }
            }
            var transform = CGAffineTransform(scaleX: 1 / xHeight, y: 1 / xHeight)
            path = word.copy(using: &transform) ?? word
        }
    }
    static let hello = faces.map(Outline.init)
    static let envelope = hello.reduce(CGRect.null) { $0.union($1.bounds) }

    struct Placement {
        let xHeight: CGFloat
        let baseline: CGFloat
        let centerX: CGFloat

        func path(for outline: Outline) -> CGPath {
            var transform = CGAffineTransform(a: xHeight, b: 0, c: 0, d: -xHeight,
                tx: centerX - outline.bounds.midX * xHeight, ty: baseline)
            return outline.path.copy(using: &transform) ?? outline.path
        }
    }

    static func placement(in rect: CGRect) -> Placement {
        let widest = hello.map { $0.bounds.width }.max() ?? 1
        // All faces share the fit factor; switching fonts never triggers a resize.
        let xHeight = max(0, min(52, (rect.width - 48) / widest, (rect.height - 48) / envelope.height))
        return Placement(xHeight: xHeight, baseline: rect.midY + envelope.midY * xHeight, centerX: rect.midX)
    }
}

struct TourHelloSpecimen: View {
    let face: Int
    var body: some View {
        GeometryReader { geometry in
            let placement = TourSpecimens.placement(in: CGRect(origin: .zero, size: geometry.size))
            Path(placement.path(for: TourSpecimens.hello[face])).fill()
        }
        .accessibilityHidden(true)
    }
}
