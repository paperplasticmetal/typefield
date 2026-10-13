import AppKit

/// Object grouping retains the pre-cache native containment rule, including
/// counters and ambiguous overlaps. These fixtures never enter a saved project.
enum FontLabObjectSelectionChecks {
    private static func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw FontLabStore.SelfTestError.failed(message) }
    }

    // Frozen pre-optimization selection oracle. Keep this independent of the
    // production cache so changes to its key or reuse rules cannot mask errors.
    private static func legacySelection(_ paths: [FontLabVectorPath], hit: Int) -> Set<UUID> {
        guard paths.indices.contains(hit) else { return [] }
        let outlines = paths.map(\.cgPath), bounds = outlines.map(\.boundingBoxOfPath)
        var outer = hit
        for index in paths.indices where paths[index].closed && index != hit {
            if bounds[index].contains(bounds[outer]), let first = paths[outer].nodes.first,
               outlines[index].contains(CGPoint(x: first.point.x * 1000, y: first.point.y * 1000)) { outer = index }
        }
        let chosen = paths.indices.filter { index in
            index == outer || (paths[index].closed && paths[outer].closed && paths[index].nodes.allSatisfy {
                outlines[outer].contains(CGPoint(x: $0.point.x * 1000, y: $0.point.y * 1000))
            })
        }
        return Set(chosen.flatMap { paths[$0].nodes.map(\.id) })
    }

    private static func glyph(_ paths: [FontLabVectorPath]) -> FontLabGlyph {
        FontLabGlyph(character: "O", strokes: [FontLabStroke(vectorPaths: paths)], contourDesignWidth: 0.62)
    }

    private static func circle(_ count: Int, radius: Double) -> FontLabVectorPath {
        .init(nodes: (0..<count).map { index in
            let angle = Double(index) * 2 * Double.pi / Double(count)
            return .init(point: .init(x: 0.5 + radius * cos(angle), y: 0.5 + radius * sin(angle)))
        }, closed: true)
    }

    static func run() throws {
        let outer = FontLabVectorMath.rectangle(CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8), ellipse: false)
        var counter = FontLabVectorMath.rectangle(CGRect(x: 0.32, y: 0.34, width: 0.26, height: 0.22), ellipse: true)
        counter.reverse()
        let island = FontLabVectorMath.rectangle(CGRect(x: 0.92, y: 0.2, width: 0.06, height: 0.1), ellipse: false)
        let nested = [outer, counter, island]
        let concave = FontLabVectorPath(nodes: [(0.1, 0.1), (0.9, 0.1), (0.9, 0.9), (0.6, 0.9),
            (0.6, 0.3), (0.4, 0.3), (0.4, 0.9), (0.1, 0.9)].map { .init(point: .init(x: $0.0, y: $0.1)) }, closed: true)
        let overlap = FontLabVectorMath.rectangle(CGRect(x: 0.45, y: 0.15, width: 0.5, height: 0.55), ellipse: true)
        let open = FontLabVectorPath(nodes: [.init(point: .init(x: 0.2, y: 0.2), outgoing: .init(x: 0.8, y: 0.8)),
                                                .init(point: .init(x: 0.7, y: 0.2))])
        let singleton = FontLabVectorPath(nodes: [.init(point: .init(x: 0.97, y: 0.95))])
        let curved = FontLabVectorMath.rectangle(CGRect(x: 0.06, y: 0.06, width: 0.88, height: 0.88), ellipse: true)
        for paths in [nested, [concave, counter, overlap, open, singleton], [curved, counter, open], Array(nested.reversed())] {
            let original = glyph(paths), editor = FontLabVectorEditor(glyph: original, metrics: FontLabMetrics())
            var commits = 0
            editor.onCommit = { _ in commits += 1 }
            for _ in 0..<3 { for index in paths.indices {
                let expected = legacySelection(paths, hit: index)
                editor.selectObject(index, adding: false)
                try check(editor.selection == expected, "Cached object selection changed counters, overlaps, open paths or contour order")
                let retained = Set(paths.last!.nodes.map(\.id))
                editor.selection = retained
                editor.selectObject(index, adding: true)
                try check(editor.selection == retained.union(expected), "Additive object selection lost an existing contour")
            } }
            try check(editor.objectSelectionGeometryBuildCount == 1 && editor.objectSelectionMembershipBuildCount <= paths.count,
                      "Repeated object selection must reuse bounded native geometry and contour membership")
            try check(editor.glyph == original && commits == 0, "Selection caching must not mutate geometry or create history")
            let before = editor.selection
            editor.selectObject(-1, adding: false); editor.selectObject(paths.count, adding: false)
            try check(editor.selection == before, "Out-of-range object selection must remain a no-op")
        }

        let original = glyph(nested)
        let editor = FontLabVectorEditor(glyph: original, metrics: FontLabMetrics())
        var history = FontLabGlyphEditHistory(), commits = 0
        editor.onCommit = { _ in commits += 1; history.record(original) }
        editor.selectObject(0, adding: false)
        let initialSelection = editor.selection
        let firstGeometry = editor.objectSelectionGeometryBuildCount
        editor.zoom = 2; editor.pan = CGPoint(x: 12, y: 18); editor.grid = false; editor.fill = false
        editor.selectObject(1, adding: false)
        try check(editor.objectSelectionGeometryBuildCount == firstGeometry && editor.selection == initialSelection,
                  "Viewport and selection changes must retain normalized object membership")
        var moved = nested
        for index in moved[1].nodes.indices {
            moved[1].nodes[index].point.x += 0.36
            moved[1].nodes[index].incoming?.x += 0.36
            moved[1].nodes[index].outgoing?.x += 0.36
        }
        try check(editor.apply(moved), "Object invalidation fixture must produce a valid edit")
        editor.selectObject(0, adding: false)
        try check(editor.selection == legacySelection(moved, hit: 0) && editor.selection != initialSelection &&
                  editor.objectSelectionGeometryBuildCount == firstGeometry + 1,
                  "Same-ID anchor edits must invalidate cached containment")
        let edited = editor.glyph
        guard let undone = history.undo(edited) else { throw FontLabStore.SelfTestError.failed("Missing object fixture Undo") }
        editor.receive(undone); editor.selectObject(0, adding: false)
        try check(editor.glyph == original && editor.selection == initialSelection && editor.objectSelectionGeometryBuildCount == firstGeometry + 2,
                  "Undo must invalidate grouping and restore the original object")
        guard let redone = history.redo(original) else { throw FontLabStore.SelfTestError.failed("Missing object fixture Redo") }
        editor.receive(redone); editor.selectObject(0, adding: false)
        try check(editor.glyph == edited && editor.selection == legacySelection(moved, hit: 0) && commits == 1,
                  "Cached selection must preserve exact Redo and the single edit commit")
        var handled = moved
        handled[0].nodes[0].outgoing = .init(x: 0.95, y: 0.8)
        let beforeHandle = editor.objectSelectionGeometryBuildCount
        try check(editor.apply(handled, commit: false), "Handle invalidation fixture must change geometry")
        editor.selectObject(1, adding: false)
        try check(editor.selection == legacySelection(handled, hit: 1) && editor.objectSelectionGeometryBuildCount == beforeHandle + 1,
                  "Same-ID handle edits must invalidate object bounds and containment")
        let reordered = Array(handled.reversed())
        editor.glyph = glyph(reordered); editor.selectObject(0, adding: false)
        try check(editor.selection == legacySelection(reordered, hit: 0), "Reordering contours must not reuse index-based membership")
        var opened = reordered; opened[0].closed = false
        editor.glyph = glyph(opened); editor.selectObject(0, adding: false)
        try check(editor.selection == legacySelection(opened, hit: 0), "Changing closed/open state must invalidate object membership")
        try legacyContourChecks(nested)

        // Malformed in-memory input may be inspected before validation. Keep
        // it uncached rather than exceeding the valid document's contour limit.
        let oversized = (0..<257).map { _ in FontLabVectorPath(nodes: [.init(point: .init(x: 0.1, y: 0.1))]) }
        let uncached = FontLabVectorEditor(glyph: glyph(oversized), metrics: FontLabMetrics())
        uncached.selectObject(0, adding: false); uncached.selectObject(0, adding: false)
        try check(uncached.objectSelectionGeometryBuildCount == 2, "Invalid oversized input must not retain an unbounded grouping cache")
        try marqueeChecks(nested)
        let dense = FontLabVectorEditor(glyph: glyph([circle(5_000, radius: 0.4), circle(5_000, radius: 0.2)]), metrics: FontLabMetrics())
        let coldStart = ProcessInfo.processInfo.systemUptime
        dense.selectObject(0, adding: false)
        let cold = (ProcessInfo.processInfo.systemUptime - coldStart) * 1000
        let warmStart = ProcessInfo.processInfo.systemUptime
        for index in 0..<10 { dense.selectObject(index % 2, adding: false) }
        let warm = (ProcessInfo.processInfo.systemUptime - warmStart) * 100
        try check(dense.selection.count == 10_000 && dense.objectSelectionGeometryBuildCount == 1 && dense.objectSelectionMembershipBuildCount == 1,
                  "Outer and counter hits must share one exact dense membership classification")
        print(String(format: "PERF: 10,000-anchor nested object selection cold %.3f ms, warmed %.3f ms", cold, warm))
        print("PASS: bounded object membership cache, native containment parity, same-ID edits, contour order, Undo/Redo and native marquee")
    }

    private static func legacyContourChecks(_ paths: [FontLabVectorPath]) throws {
        let original = FontLabGlyph(character: "O", strokes: [FontLabStroke(contours: paths.map { $0.nodes.map(\.point) })])
        let editor = FontLabVectorEditor(glyph: original, metrics: FontLabMetrics())
        let originalIDs = editor.paths.map { $0.nodes.map(\.id) }
        editor.selectObject(0, adding: false); editor.selectObject(1, adding: false)
        try check(editor.objectSelectionGeometryBuildCount == 1 && editor.glyph == original &&
                  editor.selection == legacySelection(editor.paths, hit: 1),
                  "Selecting legacy polygons must reuse converted geometry without rewriting the document")
        var received = original
        for index in received.strokes[0].contours![1].indices { received.strokes[0].contours![1][index].x += 0.36 }
        editor.receive(received); editor.selectObject(0, adding: false)
        try check(editor.paths.map { $0.nodes.map(\.id) } == originalIDs && editor.objectSelectionGeometryBuildCount == 2 &&
                  editor.selection == legacySelection(editor.paths, hit: 0),
                  "Received same-ID legacy contour edits must invalidate converted object membership")
        var converted = editor.paths; converted[0].nodes[0].point.y += 0.01
        try check(editor.apply(converted, commit: false), "First legacy vector edit must convert its contours")
        editor.selectObject(0, adding: false)
        try check(editor.glyph.strokes[0].contours == nil && editor.glyph.strokes[0].vectorPaths == converted &&
                  editor.objectSelectionGeometryBuildCount == 3 && editor.selection == legacySelection(converted, hit: 0),
                  "Legacy-to-vector conversion must invalidate grouping without changing selected object semantics")
    }

    private static func marqueeChecks(_ paths: [FontLabVectorPath]) throws {
        for shift in [false, true] {
            let original = glyph(paths)
            let editor = FontLabVectorEditor(glyph: original, metrics: FontLabMetrics())
            editor.objectSelection = true; editor.snap = false
            let retained = shift ? Set(paths[2].nodes.map(\.id)) : []
            editor.selection = retained
            let canvas = FontLabVectorNSView(editor: editor)
            canvas.frame = CGRect(x: 0, y: 0, width: 700, height: 700)
            let rect = canvas.designRect
            func screen(_ point: FontLabPoint) -> CGPoint { CGPoint(x: rect.minX + point.x * rect.width, y: rect.minY + point.y * rect.height) }
            func event(_ type: NSEvent.EventType, _ point: CGPoint) -> NSEvent {
                NSEvent.mouseEvent(with: type, location: point, modifierFlags: shift ? [.shift] : [], timestamp: 0,
                    windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            }
            var commits = 0
            editor.onCommit = { _ in commits += 1 }
            let start = screen(.init(x: 0.02, y: 0.02))
            canvas.mouseDown(with: event(.leftMouseDown, start))
            for end in [FontLabPoint(x: 0.6, y: 0.6), .init(x: 0.8, y: 0.8), .init(x: 0.89, y: 0.89)] {
                let last = screen(end), box = CGRect(x: start.x, y: start.y, width: last.x - start.x, height: last.y - start.y)
                var expected = retained
                for index in paths.indices where paths[index].nodes.contains(where: { box.contains(screen($0.point)) }) {
                    if !paths[index].nodes.allSatisfy({ expected.contains($0.id) }) { expected.formUnion(legacySelection(paths, hit: index)) }
                }
                canvas.mouseDragged(with: event(.leftMouseDragged, last))
                try check(editor.selection == expected, "Native Objects marquee must preserve compound and Shift-additive selection")
            }
            try check(editor.objectSelectionGeometryBuildCount == 1 && editor.objectSelectionMembershipBuildCount == 1,
                      "Repeated native marquee frames must not repeat native containment")
            canvas.cancelOperation(nil)
            try check(editor.selection == retained && editor.glyph == original && commits == 0,
                      "Cancelling an Objects marquee must restore selection without changing history")
        }
    }
}
