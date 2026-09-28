import AppKit
import CoreText

/// Read-only, repeatable holdout check using fonts already installed on this Mac.
/// Only five letters enter each temporary project; the rest are retained solely
/// as ground truth for a raster silhouette comparison. No project is saved.
enum FontLabStarterQualityAudit {
    private static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz").map(String.init)
    private static let references = Array("HOnopagSNRit").map(String.init)

    @discardableResult static func run() -> Bool {
        func argument(_ flag: String) -> String? {
            guard let i = CommandLine.arguments.firstIndex(of: flag), i + 1 < CommandLine.arguments.count else { return nil }
            return CommandLine.arguments[i + 1]
        }
        let count = Int(argument("--starter-reference-count") ?? "5") ?? 5
        guard [5, 8, 12].contains(count) else { print("Use 5, 8 or 12 reference letters."); return false }
        let gridScale = Int(argument("--starter-grid-scale") ?? "1") ?? 0
        guard [1, 2, 4].contains(gridScale) else { print("Use a starter grid scale of 1, 2 or 4."); return false }
        let seeds = Array(references.prefix(count))
        let excluded = CommandLine.arguments.contains("--starter-common-targets") ? references : seeds
        let reportURL = argument("--starter-report").map { URL(fileURLWithPath: $0) }
        var report = "<html><meta charset='utf-8'><title>Typefield shape audit</title><style>body{font:16px system-ui;margin:32px;background:#faf8f2;color:#222}.grid{display:grid;grid-template-columns:repeat(6,1fr);gap:12px}.tile{background:white;border:1px solid #ddd;padding:8px}svg{width:100%;height:140px}.score{font-size:12px;color:#555}h2{margin-top:40px}</style><h1>Missing-letter shape audit</h1><p>References: \(seeds.joined(separator: " ")). Black = source truth; blue = suggestion. Both use identical coordinates including side bearings. These development faces are not an untouched evaluation set.</p>"
        var complete = true
        var audited = 0
        var aggregate: [Double] = []
        var faceMeans: [Double] = []
        let validation = CommandLine.arguments.contains("--starter-validation-set")
        let names = validation ? ["Georgia", "Verdana", "TrebuchetMS", "Baskerville", "Cochin", "AmericanTypewriter", "ComicSansMS", "BradleyHandITCTT-Bold", "Zapfino"] : ["Helvetica", "Times-Roman", "Courier", "Menlo-Regular", "Avenir-Book", "ChalkboardSE-Regular", "Noteworthy-Light", "MarkerFelt-Wide", "SnellRoundhand"]
        print("STARTER PROTOCOL: \(seeds.count) references, \(92*gridScale) × \(72*gridScale) fixed grid; silhouette overlap is not confidence")
        for name in names {
            guard let font = exactFont(named: name) else {
                print("STARTER UNAVAILABLE: \(name); audit incomplete")
                complete = false
                continue
            }
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
            let proposal = FontLabStarterAssist.propose(for: project, reuseCapStems: !CommandLine.arguments.contains("--starter-disable-stem-reuse"))
            var byMethod: [String: [Double]] = [:]
            var widthErrors: [Double] = []
            var allScores: [Double] = []
            var missing: [String] = []
            var anchors: [Double] = []
            report += "<h2>\(name)</h2><div class='grid'>"
            for character in alphabet where !excluded.contains(character) {
                guard let actual = truth[character] else { continue }
                guard let candidate = proposal.glyphs[character] else {
                    missing.append(character)
                    allScores.append(0)
                    continue
                }
                anchors.append(Double(FontLabVectorMath.paths(in: candidate).reduce(0) { $0 + $1.nodes.count }))
                let method = proposal.details[character]?.method ?? "Unknown"
                let score = overlap(candidate, actual, gridScale: gridScale)
                if reportURL != nil {
                    func drawing(_ glyph: FontLabGlyph, color: String) -> String {
                        let paths = FontLabVectorMath.paths(in: glyph).filter(\.closed).map { $0.svg(xScale: glyph.resolvedDesignWidth) }.joined(separator: " ")
                        return "<path fill='\(color)' fill-opacity='.55' transform='translate(\(glyph.leftSideBearing * 1000),0)' d='\(paths)'/>"
                    }
                    report += "<div class='tile'><b>\(character)</b><svg viewBox='0 0 1400 1000'>\(drawing(actual,color:"#111"))\(drawing(candidate,color:"#1681db"))</svg><div class='score'>\(percent(score)) · \(Int(anchors.last ?? 0)) anchors<br>\(method)</div></div>"
                }
                if CommandLine.arguments.contains("--starter-quality-details") {
                    print("STARTER GLYPH \(name) \(character): \(percent(score)) [\(method)]")
                }
                byMethod[method, default: []].append(score)
                allScores.append(score)
                widthErrors.append(abs(candidate.resolvedDesignWidth - actual.resolvedDesignWidth))
            }
            report += "</div>"
            guard !allScores.isEmpty else { continue }
            audited += 1
            aggregate += allScores
            faceMeans.append(mean(allScores))
            if !missing.isEmpty { complete = false }
            let breakdown = byMethod.keys.sorted().map { key in
                "\(key): \(byMethod[key]!.count) @ \(percent(mean(byMethod[key]!)))"
            }.joined(separator: "; ")
            print("STARTER ANCHORS \(name): mean \(String(format: "%.1f", mean(anchors))), max \(Int(anchors.max() ?? 0))")
            print("STARTER HOLDOUT \(name): \(allScores.count - missing.count)/\(allScores.count) glyphs, silhouette overlap \(percent(mean(allScores))), mean design-width error \(String(format: "%.3f", mean(widthErrors))) em [\(breakdown)]\(missing.isEmpty ? "" : "; missing \(missing.joined(separator: ""))")")
        }
        let aboveTarget = aggregate.filter { $0 >= 0.85 }.count
        let summary = "STARTER SUMMARY: \(audited)/\(names.count) faces, \(aggregate.count) targets, mean \(percent(mean(aggregate))), worst face \(percent(faceMeans.min() ?? 0)), \(aboveTarget)/\(aggregate.count) targets at least 85% overlap"
        print(summary)
        report += "<p>\(summary)</p><p>Grid: \(92*gridScale) × \(72*gridScale). Shape overlap is not calibrated confidence.</p>"
        if let reportURL {
            do { try (report + "</html>").write(to: reportURL, atomically: true, encoding: .utf8) }
            catch { print("Cannot write shape report: \(error.localizedDescription)"); return false }
        }
        return complete && audited == names.count
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

    private static func overlap(_ lhs: FontLabGlyph, _ rhs: FontLabGlyph, gridScale: Int) -> Double {
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
        let columns = 92 * gridScale, rows = 72 * gridScale
        for y in 0..<rows {
            for x in 0..<columns {
                let point = CGPoint(x: (Double(x) + 0.5) / Double(columns) * 1_400,
                                    y: (Double(y) + 0.5) / Double(rows) * 1_000)
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
