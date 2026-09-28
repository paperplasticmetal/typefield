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
            "P": FontLabGlyph(character: "P", strokes: [FontLabStroke(vectorPaths: [
                rectangle(0.17, 0.18, 0.11, 0.60),
                FontLabVectorMath.rectangle(CGRect(x: 0.22, y: 0.45, width: 0.66, height: 0.33), ellipse: true)
            ])], contourDesignWidth: 0.65),
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
        func horizontalRuns(_ glyph: FontLabGlyph, y: Double) -> [Double] {
            let path = CGMutablePath()
            for contour in FontLabVectorMath.paths(in: glyph) where contour.closed { path.addPath(contour.cgPath) }
            var runs: [Double] = [], start: Int?
            for i in 0...500 {
                let inside = path.contains(CGPoint(x: Double(i) * 2, y: y * 1_000), using: .winding)
                if inside && start == nil { start = i }
                if !inside, let first = start {
                    runs.append(Double(i - first) / 500 * glyph.resolvedDesignWidth)
                    start = nil
                }
            }
            return runs
        }
        for example in [0,1] {
            var practice=try FontLabExamples.make(example)
            // Include narrower and shorter guide variants of the real examples.
            for factor in [1.0,0.8] {
                for character in practice.glyphs.keys where practice.glyphs[character]!.hasArtwork {
                    practice.glyphs[character]!.contourDesignWidth = practice.glyphs[character]!.resolvedDesignWidth * factor
                }
                let source=practice
                guard let a=FontLabStarterAssist.propose(for:practice).glyphs["A"] else {
                    throw FontLabStore.SelfTestError.failed("Handwriting/bubble A suggestion missing")
                }
                let ink=CGMutablePath();FontLabVectorMath.paths(in:a).forEach { ink.addPath($0.cgPath) }
                let bounds=ink.boundingBoxOfPath
                let box=CGRect(x:bounds.minX/1000,y:bounds.minY/1000,width:bounds.width/1000,height:bounds.height/1000)
                // A must have two separated stems through a meaningful upper
                // counter region, not a single pinhole or a filled triangle.
                let rows=(50...78).filter { horizontalRuns(a,y:box.minY+box.height*Double($0)/100).count==2 }
                try check(rows.count>=8,"Heavy/narrow A lost its usable counter")
                try check(ink.contains(CGPoint(x:box.midX*1000,y:(box.minY+box.height*0.4)*1000)),"A counter repair removed the crossbar")
                try check(practice==source,"Counter correction mutated supplied artwork")
                var export=practice;export.glyphs["A"]=a
                _=try FontLabTrueTypeExporter.artifact(for:export)
            }
        }
        let stemProject = fixture(["H", "O"])
        let stemBefore = stemProject
        let stemProposal = FontLabStarterAssist.propose(for: stemProject)
        for character in ["D", "E", "F", "L"] {
            guard let glyph = stemProposal.glyphs[character] else {
                throw FontLabStore.SelfTestError.failed("Missing source-stem suggestion")
            }
            try check(stemProposal.details[character]?.method == "Reused cap stem", "Cap stem was not reused")
            try check(FontLabVectorMath.paths(in: glyph).reduce(0, { $0+$1.nodes.count }) < 60, "Source-stem reuse created excessive editing anchors")
            let expectedWidth = (character == "D" ? 0.85*0.74 : (character == "L" ? 0.80 : 0.88)*0.695)*0.65
            try check(abs(glyph.resolvedDesignWidth-expectedWidth) < 0.004, "Source-stem arms discarded the source ink insets")
            try check(abs(glyph.leftSideBearing-(stemProject.glyphs["H"]!.leftSideBearing+0.15*0.65)) < 0.004, "Source-stem reboxing moved the supplied ink origin")
            var exported = stemProject; exported.glyphs[character] = glyph
            _ = try FontLabTrueTypeExporter.artifact(for: exported)
        }
        for character in ["K", "M", "N"] {
            guard let glyph = stemProposal.glyphs[character] else {
                throw FontLabStore.SelfTestError.failed("Missing stem-and-diagonal suggestion")
            }
            try check(stemProposal.details[character]?.sourceCharacters == ["H"] &&
                      stemProposal.details[character]?.confidence == .adapted,
                      "Stem-and-diagonal suggestion lost its actual source provenance")
            let paths = FontLabVectorMath.paths(in: glyph)
            try check(paths.allSatisfy(\.closed) && paths.reduce(0, { $0+$1.nodes.count }) < 60,
                      "Stem-and-diagonal suggestions must remain compact closed outlines")
            let expectedWidth = 0.695*0.65*(character == "M" ? 1.3 : 1)
            // K's diagonal caps can finish slightly inside the H width.
            let widthMatches = character == "K"
                ? glyph.resolvedDesignWidth <= expectedWidth+0.004 && glyph.resolvedDesignWidth >= expectedWidth*0.9
                : abs(glyph.resolvedDesignWidth-expectedWidth) < 0.004
            try check(widthMatches &&
                      abs(glyph.leftSideBearing-(stemProject.glyphs["H"]!.leftSideBearing+0.15*0.65)) < 0.004,
                      "Reused stems changed their physical position or width")
            var exported = stemProject; exported.glyphs[character] = glyph
            _ = try FontLabTrueTypeExporter.artifact(for: exported)
        }
        var broadBowl = stemProject
        broadBowl.glyphs["O"]!.contourDesignWidth = 1.2
        let broadBowlProposal = FontLabStarterAssist.propose(for: broadBowl)
        try check(abs((broadBowlProposal.glyphs["K"]?.resolvedDesignWidth ?? 0)-stemProposal.glyphs["K"]!.resolvedDesignWidth) < 0.001,
                  "A broad O incorrectly widened the H-based K")
        try check(stemProject == stemBefore, "Stem extraction changed source artwork")
        var monospaced = fixture(["H", "O", "n", "o", "p"])
        for character in monospaced.glyphs.keys where monospaced.glyphs[character]!.hasArtwork {
            monospaced.glyphs[character]!.contourDesignWidth = 0.60
            monospaced.glyphs[character]!.leftSideBearing = 0.05
            monospaced.glyphs[character]!.rightSideBearing = 0.05
        }
        let stemMonoProposal = FontLabStarterAssist.propose(for: monospaced)
        try check(stemMonoProposal.details["I"]?.method != "Reused cap stem", "Monospaced I lost its identifying bars")
        try check(stemMonoProposal.details["M"]?.method == "Constructed outline", "Monospaced M lost its fitted internal diagonal height")
        for character in ["K", "N"] {
            guard let glyph = stemMonoProposal.glyphs[character] else {
                throw FontLabStore.SelfTestError.failed("Missing monospaced diagonal suggestion")
            }
            try check(abs(glyph.resolvedDesignWidth+glyph.leftSideBearing+glyph.rightSideBearing-0.70) < 0.001,
                      "A reused stem changed the monospaced advance")
        }
        var deeplyInset = stemProject
        deeplyInset.glyphs["H"]!.leftSideBearing = 0.39
        let insetProposal = FontLabStarterAssist.propose(for: deeplyInset)
        try check(insetProposal.glyphs["E"]?.isValid == true && insetProposal.details["E"]?.method == "Constructed outline", "Reboxing clamped a copied stem beyond the side-bearing limit")
        for character in monospaced.glyphs.keys where monospaced.glyphs[character]!.hasArtwork {
            monospaced.glyphs[character]!.contourDesignWidth = 1.6
            monospaced.glyphs[character]!.leftSideBearing = 0.4
            monospaced.glyphs[character]!.rightSideBearing = 0.4
        }
        let wideMonoProposal = FontLabStarterAssist.propose(for: monospaced)
        guard let wideE = wideMonoProposal.glyphs["E"] else {
            throw FontLabStore.SelfTestError.failed("Wide monospaced E disappeared during reboxing")
        }
        try check(wideMonoProposal.details["E"]?.method == "Constructed outline" && abs(wideE.resolvedDesignWidth+wideE.leftSideBearing+wideE.rightSideBearing-2.4) < 0.001, "Reboxing changed a wide monospaced advance")
        let noStem = FontLabStarterAssist.propose(for: stemProject, reuseCapStems: false)
        try check(noStem.details["E"]?.method == "Constructed outline", "Stem ablation did not restore the original construction")
        try check(["K", "M", "N"].allSatisfy { noStem.details[$0]?.method == "Constructed outline" },
                  "Stem ablation did not restore the diagonal constructions")
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

        var hairline = fixture(["H"])
        hairline.glyphs["H"] = FontLabGlyph(character: "H", strokes: [FontLabStroke(vectorPaths: [
            rectangle(0.15, 0.18, 0.020, 0.60), rectangle(0.83, 0.18, 0.020, 0.60),
            rectangle(0.16, 0.48, 0.68, 0.020)
        ])], contourDesignWidth: 0.65)
        let hairlineProposal = FontLabStarterAssist.propose(for: hairline)
        try check(hairlineProposal.glyphs.count == 51, "Hairline source art lost starter-letter coverage")
        let hairlineS = hairlineProposal.glyphs["S"]!
        let sRuns = [0.28, 0.5, 0.72].flatMap { fraction in
            horizontalRuns(hairlineS, y: hairline.metrics.baseline + (hairline.metrics.capHeight - hairline.metrics.baseline) * fraction)
        }
        try check(!sRuns.isEmpty && (sRuns.min() ?? 1) < 0.045,
                  "A thin drawn H fell back to a heavy constructed S")

        var thinBowl = fixture(["H", "O"])
        let outer = FontLabVectorMath.rectangle(CGRect(x: 0.13, y: 0.18, width: 0.74, height: 0.60), ellipse: true)
        var inner = FontLabVectorMath.rectangle(CGRect(x: 0.225, y: 0.25, width: 0.55, height: 0.46), ellipse: true)
        inner.reverse()
        thinBowl.glyphs["O"] = FontLabGlyph(character: "O", strokes: [FontLabStroke(vectorPaths: [outer, inner])], contourDesignWidth: 0.65)
        let bowlProposal = FontLabStarterAssist.propose(for: thinBowl)
        let scaledBowl = bowlProposal.glyphs["o"]!, suggestedA = bowlProposal.glyphs["a"]!
        let midline = thinBowl.metrics.baseline + (thinBowl.metrics.xHeight - thinBowl.metrics.baseline) * 0.5
        let bowlSide = horizontalRuns(scaledBowl, y: midline).last ?? 0
        let stemPoints = suggestedA.strokes.last?.vectorPaths?.flatMap { $0.nodes.map(\.point) } ?? []
        let stemWidth = ((stemPoints.map(\.x).max() ?? 1) - (stemPoints.map(\.x).min() ?? 0)) * suggestedA.resolvedDesignWidth
        try check(bowlProposal.details["a"]?.confidence == .adapted && bowlSide > 0.01 &&
                  stemWidth <= bowlSide * 0.93,
                  "The added a stem is heavier than the copied o bowl's local side stroke")

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
        try check(proposal.details["P"]?.confidence == .template && proposal.details["S"]?.confidence == .template && proposal.details["x"]?.confidence == .template,
                  "Unrelated letterforms were incorrectly labeled as drawn adaptations")
        for character in ["C", "c", "Q", "a", "b", "d", "h", "m", "q", "u"] {
            try check(proposal.details[character]?.confidence == .adapted,
                      "Expected actual source contours in suggested \(character)")
        }
        try check(proposal.details["C"]?.sourceCharacters == ["O"] && proposal.details["q"]?.sourceCharacters == ["p"] &&
                  proposal.details["m"]?.sourceCharacters == ["n"], "Source contour provenance was incorrect")
        func anchors(_ glyph: FontLabGlyph) -> [FontLabPoint] {
            FontLabVectorMath.paths(in: glyph).flatMap(\.nodes).map(\.point)
        }
        let sourceO = mixed.glyphs["O"]!, derivedQ = proposal.glyphs["Q"]!
        let oPoints = sourceO.strokes[0].vectorPaths!.flatMap { $0.nodes.map(\.point) }
        let qPoints = derivedQ.strokes[0].vectorPaths!.flatMap { $0.nodes.map(\.point) }
        try check(derivedQ.strokes.count == sourceO.strokes.count + 1 &&
                  oPoints.count == qPoints.count && zip(oPoints,qPoints).allSatisfy {
                      abs($0.x * sourceO.resolvedDesignWidth - $1.x * derivedQ.resolvedDesignWidth) < 1e-10 && abs($0.y-$1.y) < 1e-10
                  }, "Q did not retain the drawn O geometry when expanding its box for the tail")
        try check(proposal.details["e"]?.sourceCharacters == ["o"] && proposal.details["e"]?.confidence == .adapted,
                  "e did not reuse the source o bowl")
        try check(proposal.details["G"]?.sourceCharacters == ["O"], "G discarded the available drawn bowl")
        var fullBox = mixed
        var fullPaths = FontLabVectorMath.paths(in: sourceO)
        for p in fullPaths.indices { for n in fullPaths[p].nodes.indices {
            func expand(_ point: FontLabPoint) -> FontLabPoint { .init(x:(point.x-0.13)/0.74,y:point.y) }
            fullPaths[p].nodes[n].point = expand(fullPaths[p].nodes[n].point)
            fullPaths[p].nodes[n].incoming = fullPaths[p].nodes[n].incoming.map(expand)
            fullPaths[p].nodes[n].outgoing = fullPaths[p].nodes[n].outgoing.map(expand)
        } }
        fullBox.glyphs["O"]!.strokes = [FontLabStroke(vectorPaths:fullPaths)]
        let fullProposal = FontLabStarterAssist.propose(for:fullBox)
        try check(fullProposal.details["Q"]?.confidence == .adapted && fullProposal.glyphs["Q"]?.isValid == true,
                  "A feature near the source box edge discarded Q's drawn bowl instead of expanding the box")
        let sourceo = mixed.glyphs["o"]!, derivedA = proposal.glyphs["a"]!
        try check(derivedA.strokes[0].vectorPaths?.map { $0.nodes.map(\.point) } == sourceo.strokes[0].vectorPaths?.map { $0.nodes.map(\.point) },
                  "a did not retain the drawn o curves exactly")
        let sourceP = mixed.glyphs["p"]!, derivedq = proposal.glyphs["q"]!
        let sourceX = anchors(sourceP).map(\.x), reflectedX = anchors(derivedq).map(\.x)
        try check(sourceX.count == reflectedX.count && abs((reflectedX.min() ?? 0) - (1 - (sourceX.max() ?? 1))) < 0.0001 &&
                  abs((reflectedX.max() ?? 1) - (1 - (sourceX.min() ?? 0))) < 0.0001,
                  "q did not mirror the drawn p geometry")
        let sourceN = mixed.glyphs["n"]!, derivedM = proposal.glyphs["m"]!
        try check(FontLabVectorMath.paths(in: derivedM).count == FontLabVectorMath.paths(in: sourceN).count * 2 &&
                  derivedM.resolvedDesignWidth > sourceN.resolvedDesignWidth,
                  "m did not repeat the drawn n curves at their physical width")
        let cPath = CGMutablePath()
        FontLabVectorMath.paths(in: proposal.glyphs["C"]!).forEach { cPath.addPath($0.cgPath) }
        try check(cPath.contains(CGPoint(x: 150, y: 480), using: .winding) &&
                  !cPath.contains(CGPoint(x: 850, y: 480), using: .winding),
                  "C did not open the drawn O bowl on the right")
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
        try check((lowerProposal.glyphs["i"]?.resolvedDesignWidth ?? 1) < lower.glyphs["n"]!.resolvedDesignWidth * 0.75,
                  "Similar-width lowercase bowls alone must not imply a monospaced design")
        var mono = mixed
        for character in ["H","O","n","o","p"] {
            mono.glyphs[character]?.contourDesignWidth = 0.60
        }
        let monoProposal=FontLabStarterAssist.propose(for:mono)
        try check(abs(monoProposal.glyphs["m"]!.resolvedDesignWidth-0.60)<0.0001 &&
                  abs(monoProposal.glyphs["i"]!.resolvedDesignWidth-0.60)<0.0001,
                  "Equal advances across both cases did not constrain narrow and repeated letters")
        var leaning = fixture(["n"])
        var leaningN=leaning.glyphs["n"]!
        var leaningPaths=FontLabVectorMath.paths(in:leaningN)
        for path in leaningPaths.indices { for node in leaningPaths[path].nodes.indices {
            leaningPaths[path].nodes[node].point.x += 0.15 * (leaningPaths[path].nodes[node].point.y-leaning.metrics.baseline)/leaningN.resolvedDesignWidth
        } }
        leaningN.strokes=[FontLabStroke(vectorPaths:leaningPaths)];leaning.glyphs["n"]=leaningN
        let leaningProposal=FontLabStarterAssist.propose(for:leaning)
        let leaningU=CGMutablePath()
        FontLabVectorMath.paths(in:leaningProposal.glyphs["u"]!).forEach {leaningU.addPath($0.cgPath)}
        func leftEdge(_ y: Double) -> Int { (0...1000).first {leaningU.contains(CGPoint(x:Double($0),y:y*1000))} ?? 1000 }
        try check(leaningProposal.details["u"]?.confidence == .adapted && leftEdge(0.49)>leftEdge(0.25)+30,
                  "Reflecting a handwritten n into u reversed its measured lean")
        let pSource = fixture(["P"])
        let rSuggestion = FontLabStarterAssist.propose(for: pSource)
        try check(rSuggestion.details["R"]?.confidence == .adapted && rSuggestion.glyphs["R"]?.strokes.count == 2,
                  "R did not retain the drawn P with an editable leg")
        var wide = fixture(["H"])
        wide.glyphs["H"]?.contourDesignWidth = 1.10
        wide.glyphs["H"]?.leftSideBearing = 0.025
        wide.glyphs["H"]?.rightSideBearing = 0.13
        let wideSuggestion = FontLabStarterAssist.propose(for: wide)
        try check(abs((wideSuggestion.glyphs["A"]?.resolvedDesignWidth ?? 0) - 1.10) < 0.0001 &&
                  wideSuggestion.glyphs["A"]?.leftSideBearing == 0.025 && wideSuggestion.glyphs["A"]?.rightSideBearing == 0.13,
                  "Template letters did not inherit source width and side bearings")
        try check(FontLabVectorMath.paths(in: wideSuggestion.glyphs["F"]!).flatMap(\.nodes).allSatisfy { $0.incoming == nil && $0.outgoing == nil },
                  "Angular source terminals were rounded in fallback templates")
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
