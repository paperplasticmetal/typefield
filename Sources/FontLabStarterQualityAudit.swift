import AppKit
import CoreText

/// Read-only, repeatable holdout check using fonts already installed on this Mac.
/// Only five letters enter each temporary project; the rest are retained solely
/// as ground truth for a raster silhouette comparison. No project is saved.
enum FontLabStarterQualityAudit {
    private static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz").map(String.init)
    private static let seeds = ["H", "O", "n", "o", "p"]

    @discardableResult static func run() -> Bool {
        var complete = true
        var audited = 0
        for name in ["Helvetica", "Times-Roman", "Courier", "Menlo-Regular", "Avenir-Book", "ChalkboardSE-Regular", "Noteworthy-Light", "MarkerFelt-Wide", "SnellRoundhand"] {
            guard let font = exactFont(named: name) else { continue }
            let cap = Double(CTFontGetCapHeight(font))
            guard cap > 0 else { continue }
            let xHeight = Double(CTFontGetXHeight(font))
            var project = FontLabProject(name: "Disposable holdout \(name)")
            project.metrics = FontLabMetrics(baseline: 0.22,
                                             xHeight: min(0.77, max(0.30, 0.22 + 0.60 * xHeight / cap)),
                                             capHeight: 0.82)
            let scale = 0.60 / cap
            let truth = Dictionary(uniqueKeysWithValues: alphabet.compactMap { character -> (String, FontLabGlyph)? in
                guard let glyph = outline(character, font: font, scale: scale, baseline: project.metrics.baseline) else { return nil }
                return (character, glyph)
            })
            guard seeds.allSatisfy({ truth[$0] != nil }) else { continue }
            for character in seeds { project.glyphs[character] = truth[character] }
            guard project.isValid else { continue }
            let proposal = FontLabStarterAssist.propose(for: project)
            var byMethod: [String: [Double]] = [:]
            var widthErrors: [Double] = []
            var allScores: [Double] = []
            var missing: [String] = []
            var anchors: [Double] = []
            for character in alphabet where !seeds.contains(character) {
                guard let actual = truth[character] else { continue }
                guard let candidate = proposal.glyphs[character] else {
                    missing.append(character)
                    allScores.append(0)
                    continue
                }
                anchors.append(Double(FontLabVectorMath.paths(in: candidate).reduce(0) { $0 + $1.nodes.count }))
                let method = proposal.details[character]?.method ?? "Unknown"
                let score = overlap(candidate, actual)
                if CommandLine.arguments.contains("--starter-quality-details") {
                    print("STARTER GLYPH \(name) \(character): \(percent(score)) [\(method)]")
                }
                byMethod[method, default: []].append(score)
                allScores.append(score)
                widthErrors.append(abs(candidate.resolvedDesignWidth - actual.resolvedDesignWidth))
            }
            guard !allScores.isEmpty else { continue }
            audited += 1
            if !missing.isEmpty { complete = false }
            let breakdown = byMethod.keys.sorted().map { key in
                "\(key): \(byMethod[key]!.count) @ \(percent(mean(byMethod[key]!)))"
            }.joined(separator: "; ")
            print("STARTER ANCHORS \(name): mean \(String(format: "%.1f", mean(anchors))), max \(Int(anchors.max() ?? 0))")
            print("STARTER HOLDOUT \(name): \(allScores.count - missing.count)/\(allScores.count) glyphs, silhouette overlap \(percent(mean(allScores))), mean design-width error \(String(format: "%.3f", mean(widthErrors))) em [\(breakdown)]\(missing.isEmpty ? "" : "; missing \(missing.joined(separator: ""))")")
        }
        return complete && audited > 0
    }

    private static func exactFont(named name: String) -> CTFont? {
        let font = CTFontCreateWithName(name as CFString, 1_000, nil)
        return (CTFontCopyPostScriptName(font) as String) == name ? font : nil
    }

    private static func outline(_ character: String, font: CTFont, scale: Double, baseline: Double) -> FontLabGlyph? {
        guard let code = character.utf16.first else { return nil }
        var unit = code, glyph = CGGlyph()
        guard CTFontGetGlyphsForCharacters(font, &unit, &glyph, 1), glyph != 0,
              let raw = CTFontCreatePathForGlyph(font, glyph, nil) else { return nil }
        let bounds = raw.boundingBoxOfPath
        guard bounds.width > 1 else { return nil }
        var advance = CGSize.zero
        _ = CTFontGetAdvancesForGlyphs(font, .horizontal, &glyph, &advance, 1)
        let transform = CGAffineTransform(a: 1_000 / bounds.width, b: 0, c: 0, d: scale * 1_000,
                                          tx: -bounds.minX * 1_000 / bounds.width, ty: baseline * 1_000)
        var affine = transform
        guard let normalized = raw.copy(using: &affine) else { return nil }
        var paths = FontLabVectorPath.from(normalized)
        for path in paths.indices {
            for node in paths[path].nodes.indices {
                let point = paths[path].nodes[node].point
                paths[path].nodes[node].point.x = min(1, max(0, point.x))
                paths[path].nodes[node].point.y = min(1, max(0, point.y))
            }
        }
        guard !paths.isEmpty, paths.allSatisfy({ $0.closed && $0.isValid }) else { return nil }
        let result = FontLabGlyph(character: character, strokes: [FontLabStroke(vectorPaths: paths)],
                                  leftSideBearing: min(0.4, max(0, Double(bounds.minX) * scale)),
                                  rightSideBearing: min(0.4, max(0, (Double(advance.width) - Double(bounds.maxX)) * scale)),
                                  contourDesignWidth: Double(bounds.width) * scale)
        return result.isValid ? result : nil
    }

    private static func overlap(_ lhs: FontLabGlyph, _ rhs: FontLabGlyph) -> Double {
        func ink(_ glyph: FontLabGlyph) -> CGPath {
            let path = CGMutablePath()
            let transform = CGAffineTransform(a: glyph.resolvedDesignWidth, b: 0, c: 0, d: 1,
                                              tx: glyph.leftSideBearing * 1_000, ty: 0)
            for outline in FontLabVectorMath.paths(in: glyph) where outline.closed {
                path.addPath(outline.cgPath, transform: transform)
            }
            return path
        }
        let a = ink(lhs), b = ink(rhs)
        var intersection = 0, union = 0
        for y in 0..<72 {
            for x in 0..<92 {
                let point = CGPoint(x: (Double(x) + 0.5) / 92 * 1_400,
                                    y: (Double(y) + 0.5) / 72 * 1_000)
                let inA = a.contains(point, using: .winding, transform: .identity)
                let inB = b.contains(point, using: .winding, transform: .identity)
                if inA && inB { intersection += 1 }
                if inA || inB { union += 1 }
            }
        }
        return union == 0 ? 0 : Double(intersection) / Double(union)
    }

    private static func mean(_ values: [Double]) -> Double {
        values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }
    private static func percent(_ value: Double) -> String { String(format: "%.1f%%", value * 100) }
}
