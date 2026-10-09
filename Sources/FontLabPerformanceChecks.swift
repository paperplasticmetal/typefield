import AppKit
import CryptoKit

enum FontLabPerformanceChecks {
    private enum Failure: Error { case failed(String) }
    private static func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw Failure.failed(message) }
    }

    static func run() throws {
        var seed: UInt64 = 0x64f2a39
        for digits in [3, 4] {
            let formatter = FontLabSVGNumberFormatter(fractionDigits: digits)
            let scale = pow(10.0, Double(digits))
            var values: [Double] = [-0.0, 0, Double.leastNonzeroMagnitude, -Double.leastNonzeroMagnitude,
                          -9_000, 9_000, 9_999.99995, -9_999.99995, 0.00005, -0.00005,
                          0.02 * 1_000, 3 * 1_000, -2 * 3 * 1_000, 0.4 * 1_000]
            for i in -20...20 {
                let tie = (Double(i) + 0.5) / scale
                values += [tie.nextDown, tie, tie.nextUp]
            }
            for _ in 0..<2_000 {
                seed = seed &* 6_364_136_223_846_793_005 &+ 1
                values.append((Double(seed >> 11) / 9_007_199_254_740_992 - 0.5) * 18_000)
            }
            for value in values {
                let previous = String(format: "%.*f", locale: Locale(identifier: "en_US_POSIX"), digits, value)
                try check(formatter.string(value) == previous, "SVG formatting changed precision, sign or rounding at \(value)")
            }
        }

        // These output digests freeze complete pre-optimization SVG documents,
        // including handwriting nibs, counters, cubic handles and open paths.
        let fixtures = svgFixtures()
        try check(fixtures.count == svgDigests.count, "Missing frozen SVG output fixtures")
        for (glyph, expected) in zip(fixtures, svgDigests) {
            let data = FontLabSVGExporter.data(projectName: "Ink & <forms> \"test\"", glyph: glyph, metrics: FontLabMetrics())
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            try check(digest == expected, "SVG document bytes changed for the \(glyph.character) fixture")
            for path in FontLabVectorMath.paths(in: glyph) {
                try check(path.svg(xScale: glyph.resolvedDesignWidth) == path.svg(xScale: glyph.resolvedDesignWidth, formatter: FontLabSVGNumberFormatter(fractionDigits: 4)),
                          "Standalone SVG path formatting differed from collection export")
            }
        }

        let outer = FontLabVectorMath.rectangle(CGRect(x: 0.1, y: 0.2, width: 0.6, height: 0.5), ellipse: true)
        var counter = FontLabVectorMath.rectangle(CGRect(x: 0.25, y: 0.3, width: 0.3, height: 0.3), ellipse: true)
        counter.reverse()
        let other = FontLabVectorMath.rectangle(CGRect(x: 0.45, y: 0.4, width: 0.3, height: 0.3), ellipse: false)
        let pen = FontLabStroke(points: [.init(x: 0.1, y: 0.1), .init(x: 0.2, y: 0.2)])
        let first = FontLabStroke(vectorPaths: [outer, counter]), second = FontLabStroke(vectorPaths: [other])
        let glyph = FontLabGlyph(character: "A", strokes: [first, pen, second], contourDesignWidth: 0.62)
        var moved = outer; moved.nodes[0].point.x += 0.01
        let changed = FontLabVectorMath.replacingPaths(in: glyph, with: [moved, counter, other])
        try check(changed.strokes.map(\.id) == glyph.strokes.map(\.id) && changed.strokes[0].vectorPaths == [moved, counter] &&
                  changed.strokes[1] == pen && changed.strokes[2] == second, "A drag merged independent strokes or lost a counter")

        var split = other; split.id = UUID(); split.nodes.removeLast(); split.closed = false
        let splitResult = FontLabVectorMath.replacingPaths(in: glyph, with: [outer, counter, other, split])
        try check(splitResult.strokes[2].vectorPaths == [other, split] && splitResult.strokes[0] == first,
                  "A split path lost the stroke owning its surviving nodes")
        let newPath = FontLabVectorMath.rectangle(CGRect(x: 0.2, y: 0.2, width: 0.1, height: 0.1), ellipse: false)
        let added = FontLabVectorMath.replacingPaths(in: glyph, with: [outer, counter, other, newPath])
        try check(added.strokes[2].vectorPaths == [other, newPath] && added.strokes[1] == pen,
                  "A newly drawn path did not join the last outline stroke")
        let regrouped = FontLabVectorMath.replacingPaths(in: glyph, with: [outer, counter, other], pathGroups: [[outer.id, counter.id, other.id]])
        try check(regrouped.strokes.count == 2 && regrouped.strokes[0].vectorPaths == [outer, counter, other] && regrouped.strokes[1] == pen,
                  "Explicit compound groups changed stroke ownership")

        for value in [Double.nan, .infinity, -.infinity] {
            var invalid = glyph
            invalid.strokes[0].vectorPaths![0].nodes[0].point.x = value
            var project = FontLabProject(name: "Invalid", characters: ["A"]); project.glyphs["A"] = invalid
            try check(!invalid.isValid && !project.isValid && FontLabSVGCollectionExporter.artifacts(for: project).isEmpty,
                      "An invalid coordinate entered an SVG collection")
            do { _ = try FontLabTrueTypeExporter.artifact(for: project); throw Failure.failed("An invalid coordinate entered TrueType export") }
            catch FontLabTrueTypeExporter.ExportError.invalidProject { }
        }
        try dragChecks(glyph)
        print("PASS: Letterform SVG formatting, complete export bytes, path ownership and drag history")
    }

    private static func dragChecks(_ glyph: FontLabGlyph) throws {
        let original = FontLabVectorMath.paths(in: glyph)
        let first = original[0].nodes[0], other = original[1].nodes[1]
        for initialSelection: Set<UUID> in [[first.id], [first.id, other.id]] {
            let editor = FontLabVectorEditor(glyph: glyph, metrics: FontLabMetrics())
            editor.snap = false; editor.selection = initialSelection
            let canvas = FontLabVectorNSView(editor: editor)
            canvas.frame = CGRect(x: 0, y: 0, width: 700, height: 700)
            let rect = canvas.designRect
            let start = CGPoint(x: rect.minX + first.point.x * rect.width, y: rect.minY + first.point.y * rect.height)
            func event(_ type: NSEvent.EventType, dx: Double = 0, dy: Double = 0) -> NSEvent {
                NSEvent.mouseEvent(with: type, location: CGPoint(x: start.x + dx * rect.width, y: start.y + dy * rect.height),
                                   modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            }
            var commits = 0, history = FontLabGlyphEditHistory()
            editor.onCommit = { _ in commits += 1; history.record(glyph) }
            canvas.mouseDown(with: event(.leftMouseDown))
            for (dx, dy) in [(0.01, -0.012), (0.02, 0.01)] {
                canvas.mouseDragged(with: event(.leftMouseDragged, dx: dx, dy: dy))
                let actual = editor.paths
                try check(editor.selection == initialSelection && editor.message == FontLabVectorEditor.defaultMessage && commits == 0,
                          "A live drag changed selection/status or committed before mouse-up")
                for p in original.indices { for n in original[p].nodes.indices {
                    let before = original[p].nodes[n], after = actual[p].nodes[n]
                    if initialSelection.contains(before.id) {
                        try check(after.id == before.id && after.smooth == before.smooth &&
                                  abs(after.point.x - before.point.x - dx) < 1e-12 && abs(after.point.y - before.point.y - dy) < 1e-12,
                                  "A selected anchor moved by the wrong amount")
                        for (old, new) in [(before.incoming, after.incoming), (before.outgoing, after.outgoing)] {
                            if let old, let new {
                                try check(abs(new.x - old.x - dx) < 1e-12 && abs(new.y - old.y - dy) < 1e-12,
                                          "A drag failed to translate a selected handle")
                            } else { try check(old == nil && new == nil, "A drag added or removed a handle") }
                        }
                    } else { try check(before == after, "A drag changed an unselected node") }
                } }
            }
            let edited = editor.glyph
            try check(edited.strokes.map(\.id) == glyph.strokes.map(\.id) && edited.strokes[1] == glyph.strokes[1],
                      "A drag changed stroke grouping or unrelated handwriting")
            canvas.mouseUp(with: event(.leftMouseUp)); canvas.mouseUp(with: event(.leftMouseUp))
            try check(commits == 1 && history.undo(edited) == glyph && history.redo(glyph) == edited,
                      "A drag committed twice or failed exact Undo/Redo")

            // Take a fresh selection snapshot for each event, not the gesture.
            editor.receive(glyph); editor.selection = [first.id]
            canvas.mouseDown(with: event(.leftMouseDown))
            editor.selection = [other.id]
            canvas.mouseDragged(with: event(.leftMouseDragged, dx: 0.015, dy: 0.012))
            try check(editor.paths[0].nodes[0] == first && abs(editor.paths[1].nodes[1].point.x - other.point.x - 0.015) < 1e-12,
                      "A drag reused an earlier event's selection")
            canvas.cancelOperation(nil)
            try check(editor.glyph == glyph && commits == 1, "Cancelling a drag changed committed geometry or history")
        }
    }

    static func svgFixtures() -> [FontLabGlyph] {
        let samples: [FontLabPoint] = [.init(x: 0.123456789, y: 0.25), .init(x: 0.5, y: 0.654321), .init(x: 0.8, y: 0.8)]
        var pressure = samples; pressure[0].pressure = 0.2; pressure[1].pressure = 0.9; pressure[2].pressure = 0.4
        var result = FontLabNibStyle.allCases.map { nib in
            FontLabGlyph(character: nib == .round ? "R" : nib == .marker ? "M" : "E",
                         strokes: [FontLabStroke(points: samples, width: 0.021234, nibStyle: nib),
                                   FontLabStroke(points: pressure, width: 0.036789, nibStyle: nib),
                                   FontLabStroke(points: [.init(x: 0.5, y: 0.5, pressure: 0.8)], width: 0.05234, nibStyle: nib)],
                         contourDesignWidth: 0.87321)
        }
        let outer = FontLabVectorMath.rectangle(CGRect(x: 0.1, y: 0.2, width: 0.7, height: 0.6), ellipse: true)
        var inner = FontLabVectorMath.rectangle(CGRect(x: 0.25, y: 0.3, width: 0.3, height: 0.3), ellipse: true); inner.reverse()
        let open = FontLabVectorPath(nodes: [.init(point: .init(x: 0.1, y: 0.15), outgoing: .init(x: -0.03, y: -0.02)),
                                           .init(point: .init(x: 0.8, y: 0.82), incoming: .init(x: 1.2, y: 1.3))])
        result.append(FontLabGlyph(character: "V", strokes: [FontLabStroke(vectorPaths: [outer, inner, open])], contourDesignWidth: 0.7321))
        result.append(FontLabGlyph(character: "C", strokes: [FontLabStroke(contours: [samples, Array(samples.reversed())])], contourDesignWidth: 1.321))
        return result
    }

    private static let svgDigests = [
        "d53ed1eb817b848a8377a5d25b3626f3be38a38cb32e0991010df1030174812a",
        "a95230fb5fef2a7ab2b80c989eac448eb46d8c07d8cb64c292842d85351f84f9",
        "e0548a213ed36312b7be738ee22f720c14d5bd7eba7808320da8194aed19bc72",
        "c84aee3ce3d446c3f3aaa2d3f572087c3efd2a3488ccead0823f5d1f80b186e4",
        "d236d865a256db7c9994b97cd0a7b5bee096b7c874de69ecddbe10b82a2af02d"
    ]
}
