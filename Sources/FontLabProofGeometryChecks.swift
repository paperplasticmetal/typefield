import AppKit
import Combine

enum FontLabProofGeometryChecks {
    static func run() throws {
        func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
            if !condition() { throw FontLabStore.SelfTestError.failed(message) }
        }
        func previousProof(_ project: FontLabProject, liveGlyph: FontLabGlyph? = nil) -> [String: FontLabGlyph] {
            var preview = project
            if let liveGlyph, preview.characters.contains(liveGlyph.character) {
                preview.glyphs[liveGlyph.character] = liveGlyph
            }
            let visible = Set(preview.previewText.map(String.init))
            return preview.outputProject.glyphs.filter { visible.contains($0.key) }
        }

        var project = FontLabProject(name: "Selective word proof", characters: ["A", "B", "C", "L", "S", "é", " "])
        let ellipse = FontLabVectorMath.rectangle(CGRect(x: 0.18, y: 0.22, width: 0.45, height: 0.5), ellipse: true)
        project.glyphs["A"] = FontLabGlyph(character: "A", strokes: [FontLabStroke(vectorPaths: [ellipse])], contourDesignWidth: 0.62)
        project.glyphs["B"]?.components = [FontLabComponentUse(source: "A", x: 0.025, y: 0.015, scale: 0.85)]
        project.glyphs["C"]?.components = [FontLabComponentUse(source: "B", x: 0.04, y: 0.03, scale: 0.8)]
        project.glyphs["L"]?.strokes = [FontLabStroke(contours: [[.init(x: 0.2, y: 0.2), .init(x: 0.5, y: 0.7), .init(x: 0.8, y: 0.2)]])]
        project.glyphs["S"]?.strokes = [FontLabStroke(points: [.init(x: 0.2, y: 0.3, pressure: 0.5), .init(x: 0.7, y: 0.6, pressure: 0.8)], width: 0.035, nibStyle: .marker)]
        project.previewText = "CCL S éC? "
        let saved = project
        let original = FontLabProofGeometry.glyphs(in: project)
        try check(project.isValid && original == previousProof(project) && Set(original.keys) == ["C", "L", "S", "é", " "],
                  "Selective proof geometry must match the visible subset of the complete output project")
        try check(original["L"] == project.glyphs["L"] && original["S"] == project.glyphs["S"] &&
                  original["é"] == project.glyphs["é"] && original["?"] == nil && original["A"] == nil && original["B"] == nil,
                  "Word proof must preserve legacy contours, pressure strokes and empty glyphs without materializing absent or unshown characters")
        var repeated = project; repeated.previewText = "CCCCCCCC"
        try check(FontLabProofGeometry.glyphs(in: repeated) == ["C": original["C"]!],
                  "Repeated proof letters must share one resolved glyph entry")
        repeated.previewText = ""
        try check(FontLabProofGeometry.glyphs(in: repeated).isEmpty, "An empty word proof must not resolve project geometry")
        repeated.previewText = "??"
        try check(FontLabProofGeometry.glyphs(in: repeated).isEmpty, "Missing proof letters must retain placeholder behavior")

        var live = project.glyphs["A"]!
        live.strokes[0].vectorPaths![0].nodes[0].point.x += 0.03
        live.strokes[0].vectorPaths![0].nodes[0].outgoing!.x += 0.02
        let changed = FontLabProofGeometry.glyphs(in: project, liveGlyph: live)
        try check(changed == previousProof(project, liveGlyph: live) && changed["C"] != original["C"] &&
                  changed["C"]?.components == nil && changed["A"] == nil && project == saved,
                  "A live source absent from proof text must update transitive visible components without modifying saved glyphs")
        try check(FontLabProofGeometry.glyphs(in: project, liveGlyph: project.glyphs["A"]) == original,
                  "Restoring the source snapshot must restore the exact word proof")
        var missingSource = project; missingSource.glyphs["A"] = nil
        try check(FontLabProofGeometry.glyphs(in: missingSource, liveGlyph: live) == changed,
                  "An allowed live source must resolve components even before that source exists in the saved glyph dictionary")
        var foreign = live; foreign.character = "?"
        try check(FontLabProofGeometry.glyphs(in: project, liveGlyph: foreign) == original,
                  "A live glyph outside the project's character set must not enter the proof")
        var orphan = project
        var orphanGlyph = project.glyphs["A"]!; orphanGlyph.character = "Z"
        orphan.glyphs["Z"] = orphanGlyph; orphan.previewText = "Z"
        var foreignOrphan = live; foreignOrphan.character = "Z"
        try check(FontLabProofGeometry.glyphs(in: orphan, liveGlyph: foreignOrphan) == ["Z": orphanGlyph],
                  "The live override guard must preserve the existing fallback for orphan dictionary glyphs")

        var missingComponent = project
        missingComponent.glyphs["C"]?.components = [FontLabComponentUse(source: "?")]
        var cyclic = project
        cyclic.glyphs["B"]?.components = [FontLabComponentUse(source: "C")]
        var outside = project
        outside.glyphs["C"]?.components?[0].x = 2
        for failed in [missingComponent, cyclic, outside] {
            let result = FontLabProofGeometry.glyphs(in: failed)
            try check(result == previousProof(failed) && result["C"] == failed.glyphs["C"],
                      "Unresolved, cyclic or out-of-bounds components must preserve outputProject's original-glyph fallback")
        }
        var invalidLegacy = project
        invalidLegacy.glyphs["L"]!.strokes[0].contours![0][0].x = 1.1
        try check(FontLabProofGeometry.glyphs(in: invalidLegacy) == previousProof(invalidLegacy) &&
                  FontLabProofGeometry.glyphs(in: invalidLegacy)["L"] == invalidLegacy.glyphs["L"],
                  "Temporarily invalid legacy artwork must retain the previous proof fallback without being dropped")

        var masters = project
        masters.addMaster(name: "Bold", weight: 700)
        let regularID = masters.masters![0].id, boldID = masters.activeMasterID!
        masters.glyphs["A"] = live
        let boldProof = FontLabProofGeometry.glyphs(in: masters)
        try check(boldProof == changed && boldProof == previousProof(masters),
                  "Word proof must resolve the active master snapshot rather than stale stored master outlines")
        masters.switchMaster(regularID)
        try check(FontLabProofGeometry.glyphs(in: masters) == original,
                  "Switching masters must restore the regular proof geometry")
        masters.switchMaster(boldID)
        try check(FontLabProofGeometry.glyphs(in: masters) == boldProof,
                  "Returning to a captured master must restore its exact proof geometry")

        // This is the publisher consumed by the live proof. UI-only changes
        // must not resolve geometry; @Published sends a new glyph before the
        // editor property changes, so resolve the emitted value itself.
        let editor = FontLabVectorEditor(glyph: project.glyphs["A"]!, metrics: project.metrics)
        var resolutions = 0, observed: [String: FontLabGlyph] = [:]
        let subscription = editor.$glyph.removeDuplicates().sink { value in
            resolutions += 1
            observed = FontLabProofGeometry.glyphs(in: project, liveGlyph: value)
        }
        defer { subscription.cancel() }
        editor.tool = .pen; editor.selection = [ellipse.nodes[0].id]; editor.activePath = ellipse.id
        editor.zoom = 2; editor.pan = CGPoint(x: 20, y: 30)
        editor.fill = false; editor.grid = false; editor.snap = false
        editor.objectSelection = true; editor.message = "Hover and tool feedback"
        try check(resolutions == 1 && observed == original,
                  "Tool, selection, construction, zoom, pan and display changes must not trigger geometry-only proof resolution")
        editor.glyph = live
        try check(resolutions == 2 && observed == changed,
                  "The geometry-only proof must resolve the emitted live glyph, not the editor's previous value")
        editor.glyph.strokes[0].vectorPaths![0].nodes[0].outgoing!.y += 0.015
        let handleProof = FontLabProofGeometry.glyphs(in: project, liveGlyph: editor.glyph)
        try check(resolutions == 3 && observed == handleProof && observed != changed,
                  "A nested handle edit must immediately update the linked live proof")
        editor.receive(project.glyphs["A"]!)
        try check(resolutions == 4 && observed == original && project == saved,
                  "Undo or cancellation must restore proof geometry without saving provisional artwork")
        editor.receive(editor.glyph)
        let unchanged = editor.glyph
        editor.glyph = unchanged
        try check(resolutions == 4, "Identical received or published glyphs must not repeat proof resolution")

        try boundedTiming()
        print("PASS: selective word-proof geometry, live transitive components, legacy and failure fallbacks, master snapshots and geometry-only updates")
    }

    private static func boundedTiming() throws {
        let characters = (0..<256).map { String(UnicodeScalar(0xE000 + $0)!) }
        let nodes = (0..<400).map { index -> FontLabVectorNode in
            let angle = Double(index) * 2 * Double.pi / 400
            return .init(point: .init(x: 0.5 + 0.3 * cos(angle), y: 0.5 + 0.3 * sin(angle)))
        }
        let stroke = FontLabStroke(vectorPaths: [FontLabVectorPath(nodes: nodes, closed: true)])
        var project = FontLabProject(name: "Bounded proof timing", characters: characters)
        for character in characters { project.glyphs[character]?.strokes = [stroke] }
        project.previewText = characters[0] + characters[1] + characters[0] + characters[2]
        let visible = Set(project.previewText.map(String.init))
        var baseline: [String: FontLabGlyph] = [:], candidate: [String: FontLabGlyph] = [:]
        let baselineStarted = Date.timeIntervalSinceReferenceDate
        for _ in 0..<12 { baseline = project.outputProject.glyphs }
        let baselineTime = Date.timeIntervalSinceReferenceDate - baselineStarted
        let candidateStarted = Date.timeIntervalSinceReferenceDate
        for _ in 0..<12 { candidate = FontLabProofGeometry.glyphs(in: project) }
        let candidateTime = Date.timeIntervalSinceReferenceDate - candidateStarted
        guard baseline.count == 256, candidate.count == 3,
              candidate == baseline.filter({ visible.contains($0.key) }) else {
            throw FontLabStore.SelfTestError.failed("Selective proof timing must retain exact visible geometry while excluding unshown glyphs")
        }
        print(String(format: "PERF: 12 word-proof resolutions (256 glyphs × 400 nodes, 3 distinct proof letters): complete %.3f ms; selective %.3f ms", baselineTime * 1000, candidateTime * 1000))
    }
}
