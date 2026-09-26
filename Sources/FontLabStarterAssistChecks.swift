import AppKit

enum FontLabStarterAssistChecks {
    private static func rectangle(_ x: Double, _ y: Double, _ width: Double, _ height: Double) -> FontLabVectorPath {
        FontLabVectorMath.rectangle(CGRect(x: x, y: y, width: width, height: height), ellipse: false)
    }

    private static func fixture(_ drawn: [String]) -> FontLabProject {
        var project = FontLabProject(name: "Disposable starter specimen")
        let h = FontLabGlyph(character: "H", strokes: [FontLabStroke(vectorPaths: [
            rectangle(0.15, 0.18, 0.095, 0.60), rectangle(0.75, 0.18, 0.095, 0.60),
            rectangle(0.21, 0.44, 0.59, 0.09)
        ])], contourDesignWidth: 0.65)
        let n = FontLabGlyph(character: "n", strokes: [FontLabStroke(vectorPaths: [
            rectangle(0.17, 0.18, 0.11, 0.38), rectangle(0.73, 0.18, 0.11, 0.30),
            rectangle(0.24, 0.47, 0.55, 0.09)
        ])], contourDesignWidth: 0.57)
        func ring(_ character: String, _ bottom: Double, _ top: Double, _ width: Double) -> FontLabGlyph {
            let outer = FontLabVectorMath.rectangle(CGRect(x: 0.13, y: bottom, width: 0.74, height: top-bottom), ellipse: true)
            var inner = FontLabVectorMath.rectangle(CGRect(x: 0.27, y: bottom+0.10, width: 0.46, height: top-bottom-0.20), ellipse: true)
            inner.reverse()
            return FontLabGlyph(character: character, strokes: [FontLabStroke(vectorPaths: [outer, inner])], contourDesignWidth: width)
        }
        let fixtures: [String: FontLabGlyph] = [
            "H": h, "O": ring("O", 0.18, 0.78, 0.65),
            "n": n, "o": ring("o", 0.18, 0.56, 0.57),
            "p": FontLabGlyph(character: "p", strokes: [FontLabStroke(vectorPaths: [
                rectangle(0.16, 0.03, 0.11, 0.53),
                FontLabVectorMath.rectangle(CGRect(x: 0.22, y: 0.18, width: 0.66, height: 0.38), ellipse: true)
            ])], contourDesignWidth: 0.57)
        ]
        for character in drawn { project.glyphs[character] = fixtures[character] }
        return project
    }

    static func run() throws {
        func check(_ valid: @autoclosure () -> Bool, _ message: String) throws {
            if !valid() { throw FontLabStore.SelfTestError.failed(message) }
        }
        let one = fixture(["H"])
        let oneBefore = one.glyphs["H"]
        let partialFont = try FontLabTrueTypeExporter.artifact(for: one)
        try check(partialFont.mappedCharacters.contains("H") && !partialFont.mappedCharacters.contains("A"),
                  "A partial font should export its drawn H and omit undrawn A")
        let oneProposal = FontLabStarterAssist.propose(for: one)
        try check(oneProposal.glyphs.count == 51, "One drawn control must offer the other 51 Latin starter letters")
        try check(oneProposal.glyphs["H"] == nil && one.glyphs["H"] == oneBefore, "Starter generation changed a drawn glyph")
        try check(oneProposal.glyphs.values.allSatisfy { $0.isValid && $0.hasArtwork && $0.starterOrigin != nil }, "A starter outline failed validation or provenance")
        try check(oneProposal.details["h"]?.confidence == .template && oneProposal.details["A"]?.confidence == .template, "Sparse seeds must be marked as provisional templates")
        if let o = oneProposal.glyphs["o"] {
            let points = FontLabVectorMath.paths(in: o).flatMap(\.nodes).map(\.point)
            try check(points.map(\.y).max() ?? 1 <= one.metrics.xHeight + 0.002,
                      "Proposed lowercase o exceeded the project's x-height guide")
            try check(points.map(\.y).min() ?? 0 >= one.metrics.baseline - 0.002,
                      "Proposed lowercase o fell below the baseline guide")
        }
        let savedSuggestion = try JSONEncoder().encode(oneProposal.glyphs["A"]!)
        let restoredSuggestion = try JSONDecoder().decode(FontLabGlyph.self, from: savedSuggestion)
        try check(restoredSuggestion.starterOrigin == oneProposal.glyphs["A"]?.starterOrigin && restoredSuggestion.isValid,
                  "Accepted starter provenance did not survive a project round-trip")
        var oldPayload = try JSONSerialization.jsonObject(with: savedSuggestion) as! [String: Any]
        oldPayload.removeValue(forKey: "starterOrigin")
        let oldGlyph = try JSONDecoder().decode(FontLabGlyph.self, from: JSONSerialization.data(withJSONObject: oldPayload))
        try check(oldGlyph.starterOrigin == nil && oldGlyph.isValid, "A project saved before starter provenance no longer decodes")
        var oneAccepted = one
        for (character, glyph) in oneProposal.glyphs { oneAccepted.glyphs[character] = glyph }
        try check(oneAccepted.isValid && oneAccepted.glyphs["H"] == oneBefore, "Applying starters invalidated the project or overwrote the user's H")
        let oneFont = try FontLabTrueTypeExporter.artifact(for: oneAccepted)
        try check(oneFont.mappedCharacters.count >= 52, "Single-seed starter font did not map the full alphabet")

        var heavy = fixture(["H"])
        heavy.metrics = FontLabMetrics(baseline: 0.2121380208333334, xHeight: 0.6414279513888889, capHeight: 0.8)
        heavy.glyphs["H"] = FontLabGlyph(character: "H", strokes: [FontLabStroke(vectorPaths: [
            rectangle(0.12, heavy.metrics.baseline, 0.20, heavy.metrics.capHeight - heavy.metrics.baseline),
            rectangle(0.68, heavy.metrics.baseline, 0.20, heavy.metrics.capHeight - heavy.metrics.baseline),
            rectangle(0.25, 0.45, 0.50, 0.10)
        ])], contourDesignWidth: 0.65)
        let heavyProposal = FontLabStarterAssist.propose(for: heavy)
        let heavyMissing = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz").map(String.init).filter {
            heavy.glyphs[$0]?.hasArtwork != true && heavyProposal.glyphs[$0] == nil
        }
        try check(heavyProposal.glyphs.count == 51,
                  "A heavy-stroke project with taller x-height must still propose every missing Latin letter; missing: \(heavyMissing)")

        let mixed = fixture(["H", "O", "n", "o", "p"])
        try check(mixed.isValid, "Mixed-case control fixture is not a valid project")
        let mixedBefore = mixed.glyphs
        let proposal = FontLabStarterAssist.propose(for: mixed)
        let missing = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz").map(String.init).filter {
            mixed.glyphs[$0]?.hasArtwork != true && proposal.glyphs[$0] == nil
        }
        try check(proposal.glyphs.count == 47, "Mixed-case control letters must offer every missing Latin letter; missing: \(missing.map { "\($0): \(proposal.skipped[$0] ?? "unknown")" }.joined(separator: ", "))")
        try check(proposal.glyphs.keys.allSatisfy { mixed.glyphs[$0]?.hasArtwork != true }, "A proposal targeted existing artwork")
        try check(mixed.glyphs == mixedBefore, "Preparing proposals mutated the source project")
        try check(proposal.details["P"]?.confidence == .template && proposal.details["C"]?.confidence == .template && proposal.details["S"]?.confidence == .template, "Unrelated letterforms were incorrectly labeled as drawn adaptations")
        try check(proposal.details["c"]?.confidence == .template && proposal.details["x"]?.confidence == .template, "Template provenance was lost")
        try check(proposal.skipped["H"] != nil && proposal.skipped["o"] != nil, "Existing artwork should have a clear skipped reason")
        var accepted = mixed
        for (character, glyph) in proposal.glyphs { accepted.glyphs[character] = glyph }
        try check(accepted.isValid && accepted.glyphs["O"] == mixedBefore["O"], "Mixed-case acceptance changed the original drawing")
        let mixedFont = try FontLabTrueTypeExporter.artifact(for: accepted)
        try check(mixedFont.mappedCharacters.count >= 52, "Mixed-case starter font did not export both alphabets")

        let upper = fixture(["H", "O"])
        let upperProposal = FontLabStarterAssist.propose(for: upper)
        try check(upperProposal.glyphs["o"] != nil && upperProposal.details["o"]?.confidence == .adapted, "Uppercase O should offer a directly adapted lowercase o")
        let lower = fixture(["n", "o", "p"])
        let lowerProposal = FontLabStarterAssist.propose(for: lower)
        try check(lowerProposal.glyphs["O"] != nil && lowerProposal.details["O"]?.confidence == .adapted, "Lowercase o should offer a directly adapted uppercase O")
        var nonLatin = FontLabProject(name: "Out of scope", characters: ["H", "Ж", "&"])
        nonLatin.glyphs["H"] = oneBefore
        let nonLatinProposal = FontLabStarterAssist.propose(for: nonLatin)
        try check(nonLatinProposal.glyphs.isEmpty && nonLatinProposal.skipped["Ж"] == nil && nonLatinProposal.skipped["&"] == nil,
                  "Starter generation must stay within basic Latin letters")
        var digits = FontLabProject(name: "Digits only", characters: ["1", "!"])
        var digit = oneBefore!; digit.character = "1"; digits.glyphs["1"] = digit
        try check(FontLabStarterAssist.hasLatinArtwork(in: one) && !FontLabStarterAssist.hasLatinArtwork(in: digits),
                  "Starter action readiness did not reflect Latin artwork")

        try writeSpecimen(project: mixed, proposal: proposal)
        print("PASS: starter Latin proposals, editable outlines, provenance, preservation of drawn glyphs, both case directions, one-seed and mixed-seed TrueType export. /tmp/typefield-starter-specimen.svg")
    }

    private static func writeSpecimen(project: FontLabProject, proposal: FontLabStarterProposal) throws {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz").map(String.init)
        var content = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 1000 1015\" width=\"1000\" height=\"1015\">\n"
        content += "<rect width=\"1000\" height=\"1015\" fill=\"#f7f5f1\"/>\n"
        for (index, character) in alphabet.enumerated() {
            guard let glyph = project.glyphs[character]?.hasArtwork == true ? project.glyphs[character] : proposal.glyphs[character] else { continue }
            let col = index % 8, row = index / 8, x = col * 125, y = row * 145
            let source = project.glyphs[character]?.hasArtwork == true
            content += "<rect x=\"\(x+3)\" y=\"\(y+3)\" width=\"119\" height=\"139\" rx=\"7\" fill=\"white\" stroke=\"#dad8d3\"/>\n"
            content += "<g transform=\"translate(\(x+18) \(y+7)) scale(0.12)\" fill=\"#252523\" fill-rule=\"nonzero\">"
            for path in FontLabVectorMath.paths(in: glyph) where path.closed {
                content += "<path d=\"\(path.svg(xScale: glyph.resolvedDesignWidth))\"/>"
            }
            content += "</g>\n"
            content += "<text x=\"\(x+12)\" y=\"\(y+130)\" fill=\"#555\" font-family=\"-apple-system,Arial\" font-size=\"13\">\(character) \(source ? "drawn" : "starter")</text>\n"
        }
        content += "</svg>\n"
        try Data(content.utf8).write(to: URL(fileURLWithPath: "/tmp/typefield-starter-specimen.svg"), options: .atomic)
    }
}
