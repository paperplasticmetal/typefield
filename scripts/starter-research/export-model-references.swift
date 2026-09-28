import AppKit
import CoreText

/// Compiled only by build-reference-exporter.py, never into the installed app.
/// This file exports eight supplied references, not the held-out alphabet.
enum ResearchReferenceExport {
    static func run() throws {
        func argument(_ flag: String) -> String? {
            guard let index = CommandLine.arguments.firstIndex(of: flag), index+1 < CommandLine.arguments.count else { return nil }
            return CommandLine.arguments[index+1]
        }
        func failure(_ message: String) -> NSError { NSError(domain: "TypefieldReferenceResearch", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        guard let destination = argument("--export-model-references"),
              let units = Double(argument("--units") ?? "3"), (1...8).contains(units) else {
            throw failure("Use --export-model-references /tmp/references.json [--units 1...8].")
        }
        let references = Array("Habe gmru".filter { !$0.isWhitespace }).map(String.init)
        let names = ["Helvetica", "Times-Roman", "Courier", "Menlo-Regular", "Avenir-Book", "ChalkboardSE-Regular", "Noteworthy-Light", "MarkerFelt-Wide", "SnellRoundhand"]
        var records: [[String: Any]] = []
        for name in names {
            let font = CTFontCreateWithName(name as CFString, 1000, nil)
            guard CTFontCopyPostScriptName(font) as String == name else { throw failure("Required face unavailable: \(name)") }
            var glyphs: [String: Any] = [:]
            var before = 0, after = 0, maxContour = 0
            for character in references {
                var code = character.utf16.first!, glyphID = CGGlyph()
                guard CTFontGetGlyphsForCharacters(font, &code, &glyphID, 1), glyphID != 0,
                      let raw = CTFontCreatePathForGlyph(font, glyphID, nil) else { throw failure("Missing reference \(name) \(character)") }
                let bounds = raw.boundingBoxOfPath
                let aspect = bounds.width/bounds.height
                guard bounds.height > 0, bounds.width > 0, (0.02...2.5).contains(aspect) else { throw failure("Unsupported reference bounds: \(name) \(character)") }
                // Leave a small margin and preserve physical aspect during fitting.
                // Unlike the application audit's fixed guides, this reversible frame
                // never clips ascenders or descenders before model encoding.
                var normalize = CGAffineTransform(a: 900/bounds.width, b: 0, c: 0, d: 900/bounds.height,
                                                   tx: 50-bounds.minX*900/bounds.width, ty: 50-bounds.minY*900/bounds.height)
                guard let normalized = raw.copy(using: &normalize) else { throw failure("Cannot normalize reference") }
                let paths = FontLabVectorPath.from(normalized)
                let original = FontLabGlyph(character: character, strokes: [FontLabStroke(vectorPaths: paths)], contourDesignWidth: aspect)
                guard original.isValid else { throw failure("Invalid normalized reference: \(name) \(character)") }
                // Unsafe fits retain their complete source outline. Never truncate
                // contours to fit the checkpoint's command budget.
                let fitted = (try? FontLabTraceSmoothing.fit(original, units: units, refitDenseCurves: true)) ?? original
                let fittedPaths = FontLabVectorMath.paths(in: fitted)
                let beforeCount = paths.reduce(0) { $0+$1.nodes.count }
                let afterCount = fittedPaths.reduce(0) { $0+$1.nodes.count }
                before += beforeCount; after += afterCount
                maxContour = max(maxContour, fittedPaths.map { $0.nodes.count+1 }.max() ?? 0)
                let combined = CGMutablePath()
                fittedPaths.forEach { combined.addPath($0.cgPath) }
                var inverse = normalize.inverted().concatenating(CGAffineTransform(scaleX: 0.001, y: 0.001))
                guard let restored = combined.copy(using: &inverse) else { throw failure("Cannot restore reference coordinates") }
                var advance = CGSize.zero
                _ = CTFontGetAdvancesForGlyphs(font, .horizontal, &glyphID, &advance, 1)
                glyphs[character] = ["path": svg(restored), "bounds": [bounds.minX/1000, bounds.minY/1000, bounds.width/1000, bounds.height/1000],
                                     "advance": advance.width/1000, "nodesBefore": beforeCount, "nodesAfter": afterCount]
            }
            records.append(["name": name, "capHeight": CTFontGetCapHeight(font)/1000, "xHeight": CTFontGetXHeight(font)/1000,
                            "references": references, "fitUnits": units, "glyphs": glyphs])
            print("REFERENCE FIT \(name): \(before) → \(after) anchors, longest contour \(maxContour) commands including move/closure")
        }
        try JSONSerialization.data(withJSONObject: records, options: [.sortedKeys]).write(to: URL(fileURLWithPath: destination), options: .atomic)
    }

    private static func svg(_ path: CGPath) -> String {
        var result = "", current = CGPoint.zero, start = CGPoint.zero
        func coordinates(_ p: CGPoint) -> String { "\(p.x) \(p.y)" }
        path.applyWithBlock { pointer in
            let element = pointer.pointee
            switch element.type {
            case .moveToPoint:
                current = element.points[0]; start = current; result += "M\(coordinates(current)) "
            case .addLineToPoint:
                current = element.points[0]; result += "L\(coordinates(current)) "
            case .addCurveToPoint:
                result += "C\(coordinates(element.points[0])) \(coordinates(element.points[1])) \(coordinates(element.points[2])) "
                current = element.points[2]
            case .addQuadCurveToPoint:
                let q = element.points[0], end = element.points[1]
                let a = CGPoint(x: current.x+(q.x-current.x)*2/3, y: current.y+(q.y-current.y)*2/3)
                let b = CGPoint(x: end.x+(q.x-end.x)*2/3, y: end.y+(q.y-end.y)*2/3)
                result += "C\(coordinates(a)) \(coordinates(b)) \(coordinates(end)) "; current = end
            case .closeSubpath:
                if current != start { result += "L\(coordinates(start)) " }; current = start
            @unknown default: break
            }
        }
        return result
    }
}
