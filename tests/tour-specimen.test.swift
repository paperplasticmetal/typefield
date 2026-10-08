import CoreText
import Foundation

@main
struct TourSpecimenChecks {
    static func main() throws {
        func require(_ value: Bool, _ message: String) throws {
            if !value { throw NSError(domain: "TourSpecimenChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        for size in [CGSize(width: 402, height: 270), CGSize(width: 280, height: 210)] {
            let rect = CGRect(origin: CGPoint(x: 13, y: 21), size: size)
            let placement = TourSpecimens.placement(in: rect)
            if size.width == 402 { try require(abs(placement.xHeight - 52) < 0.001, "Full-size specimen has a 52-point visible x-height") }
            for (face, outline) in zip(TourSpecimens.faces, TourSpecimens.hello) {
                try require(outline.resolvedFont == face.postScriptName, "Exact font resolves without fallback: \(face.postScriptName)")
                let font = CTFontCreateWithName(face.postScriptName as CFString, 1000, nil)
                let line = CTLineCreateWithAttributedString(NSAttributedString(string: "Hello", attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]))
                let rawBounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
                var character: UniChar = 120
                var glyph: CGGlyph = 0
                try require(CTFontGetGlyphsForCharacters(font, &character, &glyph, 1), "Font contains x")
                let rawXHeight = CTFontCreatePathForGlyph(font, glyph, nil)!.boundingBoxOfPath.height
                let placed = placement.path(for: outline).boundingBoxOfPath
                let scale = placed.width / rawBounds.width
                try require(abs(rawXHeight * scale - placement.xHeight) < 0.001, "Visible lowercase ink stays at the shared x-height")
                try require(abs(placed.midX - rect.midX) < 0.001, "Ink remains horizontally centered")
                try require(abs(placed.minY - (placement.baseline - rawBounds.maxY * scale)) < 0.001, "Every face uses the same baseline")
                try require(abs(placed.height / placed.width - rawBounds.height / rawBounds.width) < 0.001, "Letter proportions are unchanged")
                try require(placed.minX >= rect.minX + 23.99 && placed.maxX <= rect.maxX - 23.99, "No clipping at the specimen sides")
                try require(placed.minY >= rect.minY + 23.99 && placed.maxY <= rect.maxY - 23.99, "No vertical clipping")
                print(String(format: "%@ width=%.3f x-height=%.3f center=%.3f baseline=%.3f", face.name, placed.width, rawXHeight * scale, placed.midX, placement.baseline))
            }
        }
        print("PASS: Hello retains native proportions, common visible x-height and baseline, ink centering and shared responsive fit across all three fonts.")
    }
}
