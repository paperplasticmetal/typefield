import AppKit

/// Direct point edits across sketch samples and saved outline representations.
/// Reshape never converts artwork or discards tablet metadata.
enum FontLabSketchReshape {
    enum Target: Equatable {
        case pen(stroke: Int, point: Int)
        case contour(stroke: Int, contour: Int, point: Int)
        case vector(stroke: Int, path: Int, node: Int)
    }

    static func visitPoints(in glyph: FontLabGlyph, _ visit: (Target, FontLabPoint) -> Void) {
        // Later strokes paint on top, and win an exact hit-test tie.
        for s in glyph.strokes.indices.reversed() {
            let stroke = glyph.strokes[s]
            if let paths = stroke.vectorPaths {
                for p in paths.indices.reversed() { for n in paths[p].nodes.indices.reversed() {
                    visit(.vector(stroke: s, path: p, node: n), paths[p].nodes[n].point)
                } }
            } else if let contours = stroke.contours {
                for c in contours.indices.reversed() { for p in contours[c].indices.reversed() {
                    visit(.contour(stroke: s, contour: c, point: p), contours[c][p])
                } }
            } else {
                for p in stroke.points.indices.reversed() { visit(.pen(stroke: s, point: p), stroke.points[p]) }
            }
        }
    }

    static func nearest(to point: FontLabPoint, in glyph: FontLabGlyph, displaySize: CGSize, radius: Double = 12) -> Target? {
        guard displaySize.width > 0, displaySize.height > 0 else { return nil }
        var target: Target?, distance = radius
        visitPoints(in: glyph) { candidate, anchor in
            let value = hypot((anchor.x - point.x) * displaySize.width, (anchor.y - point.y) * displaySize.height)
            if value < distance { distance = value; target = candidate }
        }
        return target
    }

    static func moving(_ target: Target, to point: FontLabPoint, in glyph: FontLabGlyph) -> FontLabGlyph? {
        guard point.x.isFinite, point.y.isFinite, (0...1).contains(point.x), (0...1).contains(point.y) else { return nil }
        var result = glyph
        func moved(_ original: FontLabPoint) -> FontLabPoint {
            var value = original; value.x = point.x; value.y = point.y; return value
        }
        let changedStroke: Int
        switch target {
        case let .pen(stroke, index):
            guard result.strokes.indices.contains(stroke), result.strokes[stroke].contours == nil,
                  result.strokes[stroke].vectorPaths == nil, result.strokes[stroke].points.indices.contains(index) else { return nil }
            result.strokes[stroke].points[index] = moved(result.strokes[stroke].points[index]); changedStroke = stroke
        case let .contour(stroke, contour, index):
            guard result.strokes.indices.contains(stroke), result.strokes[stroke].vectorPaths == nil,
                  let contours = result.strokes[stroke].contours, contours.indices.contains(contour),
                  contours[contour].indices.contains(index) else { return nil }
            result.strokes[stroke].contours?[contour][index] = moved(contours[contour][index]); changedStroke = stroke
        case let .vector(stroke, path, index):
            guard result.strokes.indices.contains(stroke), let paths = result.strokes[stroke].vectorPaths,
                  paths.indices.contains(path), paths[path].nodes.indices.contains(index) else { return nil }
            var node = paths[path].nodes[index]
            let dx = point.x - node.point.x, dy = point.y - node.point.y
            func translated(_ original: FontLabPoint) -> FontLabPoint {
                var value = original; value.x += dx; value.y += dy; return value
            }
            node.point = moved(node.point)
            node.incoming = node.incoming.map(translated); node.outgoing = node.outgoing.map(translated)
            guard node.isValid else { return nil }
            result.strokes[stroke].vectorPaths?[path].nodes[index] = node; changedStroke = stroke
        }
        return result.strokes[changedStroke].isValid ? result : nil
    }

    static func selfTest() throws {
        func check(_ value: @autoclosure () -> Bool, _ message: String) throws {
            if !value() { throw FontLabStore.SelfTestError.failed(message) }
        }
        let sample = FontLabPoint(x: 0.2, y: 0.3, pressure: 0.7, tiltX: -0.2, tiltY: 0.4)
        let pen = FontLabStroke(points: [sample, .init(x: 0.8, y: 0.7)], width: 0.045, nibStyle: .marker)
        let contour = FontLabStroke(contours: [[.init(x: 0.4, y: 0.4), .init(x: 0.6, y: 0.4), .init(x: 0.5, y: 0.6)]])
        let curve = FontLabVectorMath.rectangle(CGRect(x: 0.1, y: 0.1, width: 0.7, height: 0.7), ellipse: true)
        let glyph = FontLabGlyph(character: "A", strokes: [pen, contour, FontLabStroke(vectorPaths: [curve])])
        let penTarget = nearest(to: sample, in: glyph, displaySize: CGSize(width: 552, height: 552))
        try check(penTarget == .pen(stroke: 0, point: 0), "Sketch Reshape did not expose a pen sample")
        let movedPen = moving(penTarget!, to: .init(x: 0.25, y: 0.375, pressure: 0), in: glyph)!
        var expected = sample; expected.x = 0.25; expected.y = 0.375
        try check(movedPen.strokes[0].points[0] == expected && movedPen.strokes[0].id == pen.id &&
                  movedPen.strokes[0].width == pen.width && movedPen.strokes[0].nibStyle == pen.nibStyle &&
                  Array(movedPen.strokes.dropFirst()) == Array(glyph.strokes.dropFirst()),
                  "Reshaping pen samples changed pressure, tilt, style, identity or unrelated artwork")
        let movedContour = moving(.contour(stroke: 1, contour: 0, point: 0), to: .init(x: 0.35, y: 0.35), in: glyph)!
        try check(movedContour.strokes[1].contours?[0][0] == FontLabPoint(x: 0.35, y: 0.35) && movedContour.strokes[1].id == contour.id,
                  "Reshaping a legacy contour lost its original representation or identity")
        let node = curve.nodes[0], destination = FontLabPoint(x: node.point.x + 0.05, y: node.point.y + 0.05)
        try check(nearest(to: node.point, in: glyph, displaySize: CGSize(width: 552, height: 552)) == .vector(stroke: 2, path: 0, node: 0),
                  "Sketch Reshape did not expose an imported vector anchor")
        let movedCurve = moving(.vector(stroke: 2, path: 0, node: 0), to: destination, in: glyph)!
        let changedNode = movedCurve.strokes[2].vectorPaths![0].nodes[0]
        try check(changedNode.id == node.id && changedNode.smooth == node.smooth && changedNode.point == destination &&
                  abs(changedNode.incoming!.x - node.incoming!.x - 0.05) < 1e-10 &&
                  abs(changedNode.incoming!.y - node.incoming!.y - 0.05) < 1e-10 &&
                  abs(changedNode.outgoing!.x - node.outgoing!.x - 0.05) < 1e-10 &&
                  abs(changedNode.outgoing!.y - node.outgoing!.y - 0.05) < 1e-10,
                  "Reshaping a vector anchor changed its relative handles or smooth state")
        var extreme = glyph
        extreme.strokes[2].vectorPaths?[0].nodes[0].outgoing = .init(x: 3, y: 0.5)
        try check(moving(.vector(stroke: 2, path: 0, node: 0), to: destination, in: extreme) == nil &&
                  moving(.pen(stroke: 0, point: 999), to: destination, in: glyph) == nil &&
                  moving(.pen(stroke: 0, point: 0), to: .init(x: -.infinity, y: 0.4), in: glyph) == nil,
                  "Invalid or stale Sketch Reshape targets were accepted")

        func pointer(_ type: NSEvent.EventType, x: Double, y: Double) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: CGPoint(x: 24 + x * 552, y: 24 + y * 552), modifierFlags: [],
                              timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 0)!
        }
        let view = FontLabDrawingNSView(frame: CGRect(x: 0, y: 0, width: 600, height: 600))
        view.replaceGlyph(glyph); view.tool = .reshape
        var commits: [FontLabGlyph] = []; view.onCommit = { commits.append($0) }
        view.mouseDown(with: pointer(.leftMouseDown, x: 0.2, y: 0.3))
        view.mouseDragged(with: pointer(.leftMouseDragged, x: 0.25, y: 0.375))
        try check(commits.isEmpty && view.glyph.strokes[0].points[0] == expected, "Sketch Reshape drag failed or committed before mouse-up")
        view.mouseUp(with: pointer(.leftMouseUp, x: 0.25, y: 0.375))
        try check(commits.count == 1 && commits[0] == movedPen, "Sketch Reshape must create exactly one complete undo transaction")
        view.onUndo = { view.replaceGlyph(glyph) }; view.onRedo = { view.replaceGlyph(movedPen) }
        func key(_ text: String, code: UInt16, modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: 0,
                            context: nil, characters: text, charactersIgnoringModifiers: text, isARepeat: false, keyCode: code)!
        }
        view.keyDown(with: key("z", code: 6, modifiers: .command))
        try check(view.glyph == glyph, "Sketch Reshape Undo did not restore the original sample metadata")
        view.keyDown(with: key("z", code: 6, modifiers: [.command, .shift]))
        try check(view.glyph == movedPen, "Sketch Reshape Redo did not restore the complete edit")
        view.mouseDown(with: pointer(.leftMouseDown, x: 0.25, y: 0.375))
        view.mouseDragged(with: pointer(.leftMouseDragged, x: 0.3, y: 0.4))
        view.keyDown(with: key("\u{1b}", code: 53))
        view.mouseUp(with: pointer(.leftMouseUp, x: 0.3, y: 0.4))
        try check(view.glyph == movedPen && commits.count == 1, "Escape failed to cancel an in-progress Sketch Reshape")
        print("PASS: Sketch Reshape pen/contour/vector targets, tablet metadata, relative handles, bounds, single-gesture history, Undo/Redo and Escape")
    }
}
