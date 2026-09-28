import AppKit
import CoreText

/// Research-only evaluator for frozen predictions. Coordinates are physical em
/// units: x in 0...1.4, y in 0...1, baseline 0.22 and cap height 0.82.
/// Append to the audit's isolated source snapshot to reuse its private sampler.
extension FontLabStarterQualityAudit {
    private struct FrozenFace: Decodable {
        let name: String
        let glyphs: [FrozenGlyph]
    }
    private struct FrozenGlyph: Decodable {
        let character: String
        let contours: [[[Double]]]
    }
    private struct PredictionAuditError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
    static func auditFrozenPredictions() throws {
        func fail(_ message: String) -> PredictionAuditError { .init(message: message) }
        func argument(_ flag: String) -> String? {
            guard let index = CommandLine.arguments.firstIndex(of: flag), index+1 < CommandLine.arguments.count else { return nil }
            return CommandLine.arguments[index+1]
        }
        guard let path = argument("--audit-frozen-predictions") else { throw fail("Provide the frozen prediction JSON path.") }
        let scale = Int(argument("--prediction-grid-scale") ?? "1") ?? 0
        guard [1, 2, 4].contains(scale) else { throw fail("Use prediction grid scale 1, 2 or 4.") }
        let original = ["Helvetica", "Times-Roman", "Courier", "Menlo-Regular", "Avenir-Book", "ChalkboardSE-Regular", "Noteworthy-Light", "MarkerFelt-Wide", "SnellRoundhand"]
        let additional = ["Georgia", "Verdana", "TrebuchetMS", "Baskerville", "Cochin", "AmericanTypewriter", "ComicSansMS", "BradleyHandITCTT-Bold", "Zapfino"]
        let names = original+additional
        let targets = alphabet.filter { !"HOnop".contains($0) }
        let url = URL(fileURLWithPath: path)
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= 128*1024*1024 else { throw fail("Prediction JSON must be nonempty and at most 128 MB.") }
        let faces = try JSONDecoder().decode([FrozenFace].self, from: Data(contentsOf: url))
        guard faces.count == names.count, Set(faces.map(\.name)) == Set(names) else {
            throw fail("Include each of the 18 evaluation faces exactly once; no substitutions or omitted faces.")
        }
        for face in faces {
            let characters = face.glyphs.map(\.character)
            guard Set(characters).count == characters.count, Set(characters).isSubset(of: Set(targets)) else {
                throw fail("Duplicate, reference or unexpected character in \(face.name).")
            }
        }
        var groups: [[Double]] = [], anchorCounts: [Int] = [], retention: [Double] = []
        var rejected = 0, exported = 0
        for name in names {
            guard let font = exactFont(named: name), CTFontGetCapHeight(font) > 0 else { throw fail("Exact evaluation font unavailable: \(name).") }
            let face = faces.first { $0.name == name }!
            let records = Dictionary(uniqueKeysWithValues: face.glyphs.map { ($0.character, $0) })
            var scores: [Double] = []
            var project = FontLabProject(name: "Disposable frozen prediction audit")
            project.metrics = FontLabMetrics(baseline: 0.22,
                                             xHeight: min(0.77, max(0.30, 0.22+0.60*CTFontGetXHeight(font)/CTFontGetCapHeight(font))),
                                             capHeight: 0.82)
            var failed: [String] = []
            for character in targets {
                guard let truth = outline(character, font: font, scale: 0.60/CTFontGetCapHeight(font), baseline: 0.22) else {
                    throw fail("Unavailable ground-truth glyph \(name) \(character).")
                }
                guard let record = records[character], !record.contours.isEmpty,
                      record.contours.reduce(0, { $0+$1.count }) <= 30_000,
                      record.contours.allSatisfy({ ring in
                          ring.count >= 3 && ring.allSatisfy { point in
                              point.count == 2 && point[0].isFinite && point[1].isFinite &&
                              (0...1.4).contains(point[0]) && (0...1).contains(point[1])
                          }
                      }) else { scores.append(0); failed.append(character); continue }
                let xs = record.contours.flatMap { $0.map { $0[0] } }
                guard let left = xs.min(), let right = xs.max(), right > left, left <= 0.4 else {
                    scores.append(0); failed.append(character); continue
                }
                let contours = record.contours.map { ring in
                    ring.map { FontLabPoint(x: ($0[0]-left)/(right-left), y: $0[1]) }
                }
                let raw = FontLabGlyph(character: character, strokes: [FontLabStroke(contours: contours)],
                                       leftSideBearing: left, rightSideBearing: 0, contourDesignWidth: right-left)
                guard raw.isValid, raw.hasArtwork else { scores.append(0); failed.append(character); continue }
                // Preserve the complete prediction if a compact fit is unsafe.
                let fitted = (try? FontLabTraceSmoothing.fit(raw, units: 3)) ?? raw
                guard fitted.isValid, fitted.hasArtwork else { scores.append(0); failed.append(character); continue }
                scores.append(overlap(truth, fitted, gridScale: scale))
                retention.append(overlap(raw, fitted, gridScale: 4))
                anchorCounts.append(FontLabVectorMath.paths(in: fitted).reduce(0) { $0+$1.nodes.count })
                project.glyphs[character] = fitted
            }
            if !project.glyphs.values.filter({ $0.hasArtwork }).isEmpty {
                _ = try FontLabTrueTypeExporter.artifact(for: project)
                exported += 1
            }
            rejected += failed.count
            groups.append(scores)
            print("FROZEN FACE \(name): \(percent(mean(scores))); \(targets.count-failed.count)/\(targets.count) valid; rejected \(failed.joined())")
            fflush(stdout)
        }
        let all = groups.flatMap { $0 }
        print("FROZEN SUMMARY: original \(percent(mean(groups.prefix(9).flatMap { $0 }))); additional \(percent(mean(groups.dropFirst(9).flatMap { $0 }))); \(all.count) targets; \(rejected) rejected at zero; \(exported) exported faces")
        print("FROZEN COVERAGE: \(all.filter { $0 >= 0.85 }.count)/\(all.count) at least 85%; worst face \(percent(groups.map(mean).min() ?? 0)); grid \(92*scale) × \(72*scale)")
        print("FROZEN GEOMETRY: mean anchors \(mean(anchorCounts.map(Double.init))); max \(anchorCounts.max() ?? 0); mean fit retention \(percent(mean(retention))); minimum \(percent(retention.min() ?? 0))")
        print("Silhouette overlap is not calibrated confidence. This evaluator does not run model inference or save a project.")
    }
}
