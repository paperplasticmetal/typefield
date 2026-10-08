import AppKit
import SwiftUI

/// End-to-end construction checks replay the same AppKit events as the canvas.
/// Every glyph, history entry, saved project and font is a disposable fixture.
enum FontLabPathDrawingChecks {
    private final class Harness {
        let editor: FontLabVectorEditor
        let canvas: FontLabVectorNSView
        var committed: FontLabGlyph
        var commits = 0
        var history = FontLabGlyphEditHistory()

        init(_ glyph: FontLabGlyph = FontLabGlyph(character: "A", contourDesignWidth: 0.62), snap: Bool = false) {
            committed = glyph
            editor = FontLabVectorEditor(glyph: glyph, metrics: FontLabMetrics())
            editor.snap = snap; editor.grid = false
            canvas = FontLabVectorNSView(editor: editor)
            canvas.frame = CGRect(x: 0, y: 0, width: 640, height: 640)
            editor.onCommit = { [weak self] value in
                guard let self, value != committed else { return }
                history.record(committed); committed = value; commits += 1
            }
            editor.onUndo = { [weak self] in
                guard let self, let value = history.undo(committed) else { return }
                committed = value; editor.receive(value)
            }
            editor.onRedo = { [weak self] in
                guard let self, let value = history.redo(committed) else { return }
                committed = value; editor.receive(value)
            }
        }

        func screen(_ point: FontLabPoint) -> CGPoint {
            let rect = canvas.designRect
            return CGPoint(x: rect.minX + point.x * rect.width, y: rect.minY + point.y * rect.height)
        }
        func event(_ type: NSEvent.EventType, _ point: FontLabPoint,
                   modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: screen(point), modifierFlags: modifiers,
                              timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0,
                              clickCount: 1, pressure: 1)!
        }
        func click(_ point: FontLabPoint, modifiers: NSEvent.ModifierFlags = []) {
            canvas.mouseDown(with: event(.leftMouseDown, point, modifiers: modifiers))
            canvas.mouseUp(with: event(.leftMouseUp, point, modifiers: modifiers))
        }
        func drag(_ start: FontLabPoint, _ end: FontLabPoint,
                  modifiers: NSEvent.ModifierFlags = [], release: Bool = true) {
            canvas.mouseDown(with: event(.leftMouseDown, start, modifiers: modifiers))
            canvas.mouseDragged(with: event(.leftMouseDragged, end, modifiers: modifiers))
            if release { canvas.mouseUp(with: event(.leftMouseUp, end, modifiers: modifiers)) }
        }
        func key(_ characters: String, code: UInt16, modifiers: NSEvent.ModifierFlags = []) {
            canvas.keyDown(with: NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
                timestamp: 0, windowNumber: 0, context: nil, characters: characters,
                charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)!)
        }
    }

    private static func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw FontLabStore.SelfTestError.failed(message) }
    }
    private static func close(_ first: Double, _ second: Double) -> Bool { abs(first - second) < 1e-8 }
    private static func samePoints(_ first: [FontLabPoint], _ second: [FontLabPoint]) -> Bool {
        first.count == second.count && zip(first, second).allSatisfy { close($0.x, $1.x) && close($0.y, $1.y) }
    }
    private static func glyph(_ paths: [FontLabVectorPath]) -> FontLabGlyph {
        FontLabGlyph(character: "A", strokes: paths.map { FontLabStroke(vectorPaths: [$0]) }, contourDesignWidth: 0.62)
    }

    static func run() throws {
        let left = FontLabPoint(x: 0.2, y: 0.2), apex = FontLabPoint(x: 0.5, y: 0.8)
        let right = FontLabPoint(x: 0.8, y: 0.2)
        let line = Harness()
        line.editor.tool = .line
        let blank = line.editor.glyph
        line.click(left)
        try check(line.editor.glyph == blank && line.commits == 0,
                  "Clicking with Line must not leave a stray point or an undo entry")
        line.drag(left, apex, release: false)
        try check(line.editor.paths.count == 1 && line.editor.paths[0].nodes.count == 2 && line.commits == 0,
                  "Line drag must preview a two-node path without saving before mouse-up")
        line.key("\u{1b}", code: 53)
        line.canvas.mouseUp(with: line.event(.leftMouseUp, apex))
        try check(line.editor.glyph == blank && line.commits == 0,
                  "Escape must remove an unfinished Line preview without committing it")
        line.editor.tool = .line
        line.drag(left, apex)
        try check(line.editor.paths.count == 1 && line.commits == 1,
                  "A completed Line drag must create one path in one undo transaction")
        let beforeLineFinish = line.editor.glyph
        line.key("\r", code: 36)
        try check(line.editor.glyph == beforeLineFinish && line.commits == 1,
                  "Return in the Line tool must not smooth an endpoint or add an undo entry")
        line.drag(apex, right)
        try check(line.editor.paths.count == 1 && samePoints(line.editor.paths[0].nodes.map(\.point), [left, apex, right]) && line.commits == 2,
                  "Drawing a second Line from an endpoint must extend the same connected contour")
        line.drag(.init(x: 0.32, y: 0.44), .init(x: 0.68, y: 0.44))
        try check(line.editor.paths.count == 2 && line.commits == 3 && line.editor.openCount == 2 &&
                  line.editor.paths.flatMap(\.nodes).allSatisfy { $0.incoming == nil && $0.outgoing == nil },
                  "A Line-built A must retain connected legs and a separate straight crossbar")
        let lineA = line.editor.glyph
        line.key("z", code: 6, modifiers: .command)
        try check(line.editor.paths.count == 1 && line.committed == line.editor.glyph,
                  "Undo must remove only the last Line gesture")
        line.key("z", code: 6, modifiers: [.command, .shift])
        try check(line.editor.glyph == lineA, "Redo must restore the exact Line contour and node identities")

        let retract = Harness(); retract.editor.tool = .line
        let retractBlank = retract.editor.glyph
        retract.drag(left, apex, release: false)
        retract.canvas.mouseDragged(with: retract.event(.leftMouseDragged, left))
        retract.canvas.mouseUp(with: retract.event(.leftMouseUp, left))
        try check(retract.editor.glyph == retractBlank && retract.commits == 0,
                  "Retracting Line to its starting point must discard the preview without an edit")

        let diagonal = Harness(); diagonal.editor.tool = .line
        diagonal.drag(.init(x: 0.2, y: 0.2), .init(x: 0.6, y: 0.43), modifiers: .shift)
        try check(diagonal.editor.paths.count == 1, "Shift-Line must create a usable path")
        let diagonalPoints = diagonal.editor.paths[0].nodes.map(\.point)
        try check(close((diagonalPoints[1].x - diagonalPoints[0].x) * diagonal.editor.glyph.resolvedDesignWidth,
                        diagonalPoints[1].y - diagonalPoints[0].y),
                  "Shift-Line must constrain to 45 degrees in physical font coordinates")

        let pen = Harness(); pen.editor.tool = .pen
        pen.click(left); pen.click(apex); pen.click(right)
        try check(pen.editor.paths.count == 1 && samePoints(pen.editor.paths[0].nodes.map(\.point), [left, apex, right]),
                  "Three Bézier clicks must construct one connected corner path")
        let beforeFinish = pen.editor.glyph, finishCommits = pen.commits
        pen.key("\r", code: 36)
        try check(pen.editor.activePath == nil && pen.editor.glyph == beforeFinish && pen.commits == finishCommits && pen.editor.tool == .pen,
                  "Return must finish a Pen path without smoothing it, changing tools or adding history")
        // Start in empty space: (0.32, 0.44) is exactly on the left
        // diagonal, where idle Pen intentionally inserts an existing anchor.
        pen.click(.init(x: 0.38, y: 0.44)); pen.click(.init(x: 0.62, y: 0.44)); pen.key("\r", code: 36)
        try check(pen.editor.paths.count == 2 && pen.editor.paths.map { $0.nodes.count } == [3, 2],
                  "Finishing Pen must allow a separate crossbar in a blank A")

        try constructionJoins()
        try penLifecycle()
        try touchedPathClosing()
        try activePathState()
        try interruptedLineJoin()
        try hoverAndCancellation()
        try hostedViewportStability()
        try outlinePersistenceAndExport(line)
        print("PASS: Line/Pen path construction, endpoint joining, cancellation, stable hosted viewport, undo/redo, outlined-stroke persistence and SVG/TrueType export")
    }

    private static func constructionJoins() throws {
        // Filled paths and unrelated open artwork are deliberately separate
        // source strokes, so a join cannot erase or silently regroup them.
        let closed = FontLabVectorMath.rectangle(CGRect(x: 0.42, y: 0.76, width: 0.12, height: 0.12), ellipse: false)
        let untouched = FontLabVectorPath(nodes: [.init(point: .init(x: 0.1, y: 0.85)), .init(point: .init(x: 0.25, y: 0.9))])
        let source = FontLabVectorPath(nodes: [
            .init(point: .init(x: 0.1, y: 0.2), incoming: .init(x: 0.05, y: 0.1), outgoing: .init(x: 0.15, y: 0.35)),
            .init(point: .init(x: 0.3, y: 0.35), incoming: .init(x: 0.25, y: 0.3), outgoing: .init(x: 0.35, y: 0.5))])
        let destination = FontLabVectorPath(nodes: [
            .init(point: .init(x: 0.7, y: 0.5), incoming: .init(x: 0.65, y: 0.4), outgoing: .init(x: 0.8, y: 0.55)),
            .init(point: .init(x: 0.9, y: 0.7), incoming: .init(x: 0.85, y: 0.65), outgoing: .init(x: 0.95, y: 0.8))])
        for sourceFirst in [false, true] { for destinationLast in [false, true] {
            let drawing = Harness(glyph([source, destination, closed, untouched]))
            drawing.editor.tool = .line
            var orientedSource = source, orientedDestination = destination
            if sourceFirst { orientedSource.reverse() }
            if destinationLast { orientedDestination.reverse() }
            drawing.drag(orientedSource.nodes.last!.point, orientedDestination.nodes.first!.point)
            try check(drawing.editor.paths.count == 3 && drawing.commits == 1,
                      "Line joining either orientation must combine only the two endpoint paths in one edit")
            guard let joined = drawing.editor.paths.first(where: { $0.nodes.count == 4 }) else {
                throw FontLabStore.SelfTestError.failed("Line endpoint join lost its four original anchors")
            }
            try check(joined.nodes.map(\.point) == orientedSource.nodes.map(\.point) + orientedDestination.nodes.map(\.point) &&
                      joined.nodes[1].outgoing == nil && joined.nodes[2].incoming == nil && !joined.isCurve(1),
                      "Line must orient both source paths and add a straight bridge without losing original anchors")
            try check(joined.controls(0) == orientedSource.controls(0) && joined.controls(2) == orientedDestination.controls(0),
                      "Line endpoint joining must preserve the existing curved segments on both sides")
            try check(drawing.editor.paths.contains(closed) && drawing.editor.paths.contains(untouched),
                      "Endpoint joining must leave unrelated closed and open contours unchanged")

            let pen = Harness(glyph([source, destination, closed, untouched])); pen.editor.tool = .pen
            pen.click(orientedSource.nodes.last!.point)
            try check(pen.editor.activePath == source.id && pen.editor.paths[0].nodes == orientedSource.nodes &&
                      pen.commits == (sourceFirst ? 1 : 0),
                      "Pen must resume either endpoint and save a needed reversal exactly once")
            let beforeJoin = pen.commits
            pen.click(orientedDestination.nodes.first!.point)
            guard let penJoined = pen.editor.paths.first(where: { $0.id == source.id }) else {
                throw FontLabStore.SelfTestError.failed("Pen joining changed the active source path identity")
            }
            try check(pen.editor.paths.count == 3 && penJoined.nodes.count == 4 && pen.commits == beforeJoin + 1 &&
                      penJoined.nodes.map(\.point) == orientedSource.nodes.map(\.point) + orientedDestination.nodes.map(\.point),
                      "Pen endpoint joining must orient the target and keep all original anchors in one edit")
            try check(penJoined.controls(0) == orientedSource.controls(0) && penJoined.controls(2) == orientedDestination.controls(0) &&
                      penJoined.nodes[1].outgoing == orientedSource.nodes[1].outgoing &&
                      penJoined.nodes[2].incoming == orientedDestination.nodes[0].incoming && penJoined.isCurve(1),
                      "Pen joining must preserve a curved bridge and both existing neighboring segments")
            try check(pen.editor.paths.contains(closed) && pen.editor.paths.contains(untouched),
                      "Pen joining must not alter unrelated paths")
        } }

        let snapping = Harness(glyph([source, destination]), snap: true); snapping.editor.tool = .line
        let nearSource = FontLabPoint(x: source.nodes[1].point.x + 0.002, y: source.nodes[1].point.y + 0.002)
        let nearDestination = FontLabPoint(x: destination.nodes[0].point.x - 0.002, y: destination.nodes[0].point.y + 0.002)
        snapping.drag(nearSource, nearDestination)
        try check(snapping.editor.paths.count == 1 && snapping.editor.paths[0].nodes.map(\.point) == source.nodes.map(\.point) + destination.nodes.map(\.point),
                  "Line endpoint snapping must connect near hits exactly instead of leaving hairline gaps")

        var coincidentDestination = destination
        coincidentDestination.nodes[0].point = source.nodes[1].point
        let coincident = Harness(glyph([source, coincidentDestination]))
        coincident.editor.selection = [source.nodes[1].id, coincidentDestination.nodes[0].id]
        coincident.key("j", code: 38, modifiers: .command)
        try check(coincident.editor.paths.count == 1 && coincident.editor.paths[0].nodes.count == 3 && coincident.commits == 1,
                  "Joining coincident endpoints must merge the shared anchor instead of adding a zero-length segment")
        let merged = coincident.editor.paths[0]
        try check(merged.nodes[1].id == source.nodes[1].id && merged.nodes[1].incoming == source.nodes[1].incoming &&
                  merged.nodes[1].outgoing == coincidentDestination.nodes[0].outgoing,
                  "A coincident join must keep both neighboring curves and the source endpoint identity")

        let closedTarget = Harness(glyph([source, closed])); closedTarget.editor.tool = .line
        closedTarget.drag(source.nodes[1].point, closed.nodes[0].point)
        try check(closedTarget.editor.paths.count == 2 && closedTarget.editor.paths.contains(closed) &&
                  closedTarget.editor.paths.first(where: { $0.id == source.id })?.nodes.count == 3,
                  "Line may touch a closed outline but must never consume it as an open endpoint")

        let corners = [FontLabVectorPath(nodes: [.init(point: .init(x: 0.1, y: 0.2)), .init(point: .init(x: 0.3, y: 0.4))]),
                       FontLabVectorPath(nodes: [.init(point: .init(x: 0.6, y: 0.4)), .init(point: .init(x: 0.8, y: 0.2))])]
        let cornerPen = Harness(glyph(corners)); cornerPen.editor.tool = .pen; cornerPen.editor.activePath = corners[0].id
        cornerPen.click(corners[1].nodes[0].point)
        try check(cornerPen.editor.paths.count == 1 && cornerPen.editor.paths[0].nodes.count == 4 &&
                  !cornerPen.editor.paths[0].isCurve(1) && cornerPen.commits == 1,
                  "Joining corner endpoints with Pen must retain a straight bridge")

        let twoNode = Harness(glyph([corners[0]])); twoNode.editor.tool = .line
        let originalTwoNode = twoNode.editor.glyph
        twoNode.drag(corners[0].nodes[1].point, corners[0].nodes[0].point)
        try check(twoNode.editor.glyph == originalTwoNode && twoNode.commits == 0,
                  "Line must reject closing a two-anchor path without leaving the provisional duplicate endpoint")
    }

    private static func penLifecycle() throws {
        let points = [FontLabPoint(x: 0.2, y: 0.2), FontLabPoint(x: 0.5, y: 0.8), FontLabPoint(x: 0.8, y: 0.2)]
        let closing = Harness(); closing.editor.tool = .pen
        points.forEach { closing.click($0) }
        let closeCommits = closing.commits
        closing.click(points[0])
        try check(closing.editor.paths.count == 1 && closing.editor.paths[0].closed && closing.editor.paths[0].nodes.count == 3 &&
                  closing.editor.activePath == nil && closing.commits == closeCommits + 1,
                  "Clicking the first active Pen node must close once without adding a duplicate anchor")

        let cancelling = Harness(); cancelling.editor.tool = .pen
        cancelling.click(points[0]); cancelling.click(points[1])
        let saved = cancelling.editor.glyph, savedCommits = cancelling.commits
        cancelling.drag(points[2], .init(x: 0.9, y: 0.3), release: false)
        cancelling.key("\u{1b}", code: 53)
        cancelling.canvas.mouseUp(with: cancelling.event(.leftMouseUp, points[2]))
        try check(cancelling.editor.glyph == saved && cancelling.commits == savedCommits,
                  "Escape during Pen handle placement must restore all prior nodes and active construction")
        cancelling.key("\u{1b}", code: 53)
        try check(cancelling.editor.glyph == saved && cancelling.editor.activePath == nil && cancelling.commits == savedCommits,
                  "Idle Escape must finish a Pen path without deleting its saved nodes")

        let resumable = FontLabVectorPath(nodes: points.map { FontLabVectorNode(point: $0) })
        let resume = Harness(glyph([resumable])); resume.editor.tool = .pen
        let beforeResume = resume.editor.glyph
        resume.canvas.mouseDown(with: resume.event(.leftMouseDown, points[0]))
        resume.key("\u{1b}", code: 53)
        resume.canvas.mouseUp(with: resume.event(.leftMouseUp, points[0]))
        try check(resume.editor.glyph == beforeResume && resume.editor.activePath == nil && resume.commits == 0,
                  "Cancelling a first-endpoint resume must restore direction and active-path state")

        let finished = Harness(glyph([resumable])); finished.editor.tool = .pen; finished.editor.activePath = resumable.id
        let beforeEndpointFinish = finished.editor.glyph
        finished.click(points[2])
        try check(finished.editor.activePath == nil && finished.editor.glyph == beforeEndpointFinish && finished.commits == 0,
                  "Clicking the active corner endpoint must finish without appending a duplicate point")

        let openTarget = FontLabVectorPath(nodes: [.init(point: .init(x: 0.1, y: 0.6)), .init(point: .init(x: 0.3, y: 0.65))])
        let switchPath = Harness(glyph([resumable, openTarget])); switchPath.editor.tool = .pen; switchPath.editor.activePath = resumable.id
        switchPath.click(openTarget.nodes.last!.point, modifiers: .shift)
        try check(switchPath.editor.paths.count == 2 && switchPath.editor.paths[0] == resumable &&
                  switchPath.editor.paths[1] == openTarget && switchPath.editor.activePath == openTarget.id && switchPath.commits == 0,
                  "Shift-click on a different endpoint must resume it without bridging the separate paths")

        let closed = FontLabVectorMath.rectangle(CGRect(x: 0.1, y: 0.5, width: 0.2, height: 0.2), ellipse: false)
        let closedEdit = Harness(glyph([resumable, closed])); closedEdit.editor.tool = .pen; closedEdit.editor.activePath = resumable.id
        closedEdit.drag(closed.nodes[0].point, .init(x: 0.15, y: 0.55))
        try check(closedEdit.editor.paths.count == 2 && closedEdit.editor.paths[0] == resumable &&
                  closedEdit.editor.paths[1].closed && closedEdit.editor.paths[1].nodes[0].point != closed.nodes[0].point && closedEdit.commits == 1,
                  "An active Pen path must not consume a closed target when its anchor is edited")

        let continuing = Harness(glyph([resumable]))
        continuing.editor.selection = [resumable.nodes[0].id]
        try check(continuing.editor.canContinueEndpoint, "The first endpoint must offer Continue path")
        continuing.editor.continueSelectedEndpoint()
        try check(continuing.editor.tool == .pen && continuing.editor.activePath == resumable.id &&
                  continuing.editor.paths[0].nodes.map(\.id) == resumable.nodes.reversed().map(\.id) && continuing.commits == 1,
                  "Continue path must make the selected first endpoint the active last endpoint")
        continuing.click(.init(x: 0.1, y: 0.3))
        try check(continuing.editor.paths.count == 1 && continuing.editor.paths[0].nodes.count == 4 && continuing.commits == 2,
                  "A click after Continue path must append to that path without making a disconnected contour")

        let curve = FontLabVectorPath(nodes: [
            .init(point: .init(x: 0.15, y: 0.3), outgoing: .init(x: 0.35, y: 0.7)),
            .init(point: .init(x: 0.85, y: 0.3), incoming: .init(x: 0.65, y: 0.7))])
        let inserting = Harness(glyph([curve])); inserting.editor.tool = .pen
        inserting.click(FontLabVectorMath.evaluate(curve.controls(0), 0.5))
        try check(inserting.editor.paths.count == 1 && inserting.editor.paths[0].nodes.count == 3 && inserting.commits == 1,
                  "Pen on an existing segment must insert an anchor rather than create a stray path")
        let split = inserting.editor.paths[0]
        try check(samePoints([FontLabVectorMath.evaluate(split.controls(0), 0.5), FontLabVectorMath.evaluate(split.controls(1), 0.5)],
                             [FontLabVectorMath.evaluate(curve.controls(0), 0.25), FontLabVectorMath.evaluate(curve.controls(0), 0.75)]),
                  "Clicking Pen to insert a curve anchor must retain the original cubic geometry")
    }

    private static func hoverAndCancellation() throws {
        let pen = Harness(); pen.editor.tool = .pen
        pen.click(.init(x: 0.2, y: 0.2))
        let saved = pen.editor.glyph, savedCommits = pen.commits
        pen.canvas.mouseMoved(with: pen.event(.mouseMoved, .init(x: 0.6, y: 0.6)))
        try check(pen.canvas.rubberBandVisible && pen.canvas.hoverAction?.contains("add a point") == true &&
                  pen.editor.glyph == saved && pen.commits == savedCommits,
                  "Pen hover must preview the next segment without changing saved geometry or history")
        let exit = NSEvent.enterExitEvent(with: .mouseExited, location: CGPoint(x: 700, y: 700), modifierFlags: [],
            timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil)!
        pen.canvas.mouseExited(with: exit)
        try check(!pen.canvas.rubberBandVisible && pen.canvas.hoverAction == nil && pen.editor.glyph == saved,
                  "Leaving the canvas must hide construction hover without deleting the unfinished path")

        let line = Harness(); line.editor.tool = .line
        let blank = line.editor.glyph
        line.drag(.init(x: 0.2, y: 0.2), .init(x: 0.7, y: 0.7), release: false)
        let preview = line.editor.glyph
        line.canvas.mouseExited(with: exit)
        try check(line.editor.glyph == preview && line.commits == 0 && line.canvas.hoverAction == nil,
                  "Pointer exit during Line drawing must keep the reversible preview and avoid an early commit")
        line.key("\u{1b}", code: 53)
        line.canvas.mouseUp(with: line.event(.leftMouseUp, .init(x: 0.7, y: 0.7)))
        try check(line.editor.glyph == blank && line.commits == 0,
                  "Escape after pointer exit must still cancel the complete Line transaction")
    }

    private static func touchedPathClosing() throws {
        let untouchedClosed = FontLabVectorMath.rectangle(CGRect(x: 0.04, y: 0.04, width: 0.06, height: 0.08), ellipse: false)
        let untouchedOpen = FontLabVectorPath(nodes: [.init(point: .init(x: 0.08, y: 0.9)), .init(point: .init(x: 0.24, y: 0.9))])
        let points = [FontLabPoint(x: 0.2, y: 0.2), FontLabPoint(x: 0.5, y: 0.8), FontLabPoint(x: 0.8, y: 0.2)]
        let pen = Harness(glyph([untouchedClosed, untouchedOpen])); pen.editor.tool = .pen
        points.forEach { pen.click($0) }
        pen.key("\r", code: 36)
        let beforeClose = pen.commits
        try check(pen.editor.activePath == nil && pen.editor.selection.count == 1 && pen.editor.canCloseTouchedPaths,
                  "Finishing a three-point Pen path must leave Close path available for its selected endpoint")
        pen.editor.closeTouchedPaths()
        try check(pen.commits == beforeClose + 1 && pen.editor.paths.count == 3 && pen.editor.paths[2].closed &&
                  pen.editor.paths[2].nodes.count == 3 && pen.editor.paths[0] == untouchedClosed && pen.editor.paths[1] == untouchedOpen,
                  "Close path after Finish must close only the touched Pen contour in one undo transaction")
        pen.key("z", code: 6, modifiers: .command)
        try check(!pen.editor.paths[2].closed && pen.editor.paths[0] == untouchedClosed && pen.editor.paths[1] == untouchedOpen,
                  "Undo the Close path action must restore only its previous open contour")

        let line = Harness(); line.editor.tool = .line
        line.drag(points[0], points[1]); line.drag(points[1], points[2])
        let lineCommits = line.commits
        try check(line.editor.activePath == nil && line.editor.selection.count == 1 && line.editor.canCloseTouchedPaths,
                  "A connected three-point Line path must offer Close with only its newest endpoint selected")
        line.editor.closeTouchedPaths()
        try check(line.editor.paths.count == 1 && line.editor.paths[0].closed && line.editor.paths[0].nodes.count == 3 && line.commits == lineCommits + 1,
                  "Close path must connect a touched Line contour without adding an extra endpoint")
    }

    private static func activePathState() throws {
        let points = [FontLabPoint(x: 0.2, y: 0.2), FontLabPoint(x: 0.5, y: 0.8), FontLabPoint(x: 0.8, y: 0.2)]
        let closed = FontLabVectorPath(nodes: points.map { FontLabVectorNode(point: $0) }, closed: true)
        let undo = Harness(glyph([closed]))
        let original = undo.editor.glyph
        undo.editor.selection = [closed.nodes[0].id]
        undo.editor.splitAtNode()
        try check(undo.editor.paths.count == 1 && !undo.editor.paths[0].closed,
                  "The active-path undo fixture must split a closed contour")
        undo.editor.selection = [undo.editor.paths[0].nodes.last!.id]
        undo.editor.continueSelectedEndpoint()
        try check(undo.editor.activePath == closed.id && undo.commits == 1,
                  "Continuing the last split endpoint must not add an orientation-only undo entry")
        undo.key("z", code: 6, modifiers: .command)
        try check(undo.editor.glyph == original && undo.editor.activePath == nil,
                  "Undo that restores a closed path with the same ID must clear stale active construction")

        let hand = Harness(); hand.editor.tool = .pen
        hand.click(points[0]); hand.click(points[1])
        let beforeHand = hand.editor.glyph, handCommits = hand.commits
        hand.key("h", code: 4)
        try check(hand.editor.tool == .hand && hand.editor.activePath == nil && hand.editor.glyph == beforeHand && hand.commits == handCommits,
                  "Switching to Hand by keyboard must finish active Pen construction without changing artwork")
        hand.key("p", code: 35)
        hand.click(points[2])
        try check(hand.editor.paths.count == 2 && hand.editor.paths[0] == FontLabVectorMath.paths(in: beforeHand)[0],
                  "Returning from Hand to Pen must start a new path instead of silently extending the old one")

        let duplicate = Harness(); duplicate.editor.tool = .pen
        duplicate.click(points[0]); duplicate.click(points[1])
        let source = duplicate.editor.paths[0], duplicateCommits = duplicate.commits
        duplicate.key("d", code: 2, modifiers: .command)
        try check(duplicate.editor.paths.count == 2 && duplicate.editor.activePath == nil && duplicate.commits == duplicateCommits + 1 &&
                  duplicate.editor.paths[0] == source,
                  "Duplicating an active path must select its copy and clear construction on the original")
        duplicate.click(.init(x: 0.9, y: 0.8))
        try check(duplicate.editor.paths.count == 3 && duplicate.editor.paths[0] == source,
                  "Pen after Duplicate must not append to the deselected original path")
    }

    private static func interruptedLineJoin() throws {
        let source = FontLabVectorPath(nodes: [.init(point: .init(x: 0.1, y: 0.2)), .init(point: .init(x: 0.3, y: 0.4))])
        let destination = FontLabVectorPath(nodes: [.init(point: .init(x: 0.6, y: 0.5)), .init(point: .init(x: 0.8, y: 0.7))])
        let focus = Harness(glyph([source, destination])); focus.editor.tool = .line
        // Commit can synchronously trigger another responder transition. The
        // gesture must already be cleared before that callback re-enters it.
        let commit = focus.editor.onCommit, view = focus.canvas
        focus.editor.onCommit = { [weak view] value in commit(value); _ = view?.resignFirstResponder() }
        focus.drag(source.nodes[1].point, destination.nodes[0].point, release: false)
        try check(focus.commits == 0 && focus.editor.paths.count == 2,
                  "Line must keep a snapped connection provisional until the gesture commits")
        _ = focus.canvas.resignFirstResponder()
        try check(focus.editor.paths.count == 1 && focus.editor.paths[0].nodes.count == 4 && focus.commits == 1 &&
                  focus.editor.paths[0].nodes.map(\.point) == source.nodes.map(\.point) + destination.nodes.map(\.point),
                  "Losing focus during a snapped Line join must connect both paths in exactly one reentrant-safe commit")
        let joined = focus.editor.glyph
        focus.canvas.mouseUp(with: focus.event(.leftMouseUp, destination.nodes[0].point))
        try check(focus.editor.glyph == joined && focus.commits == 1,
                  "A stale mouse-up after interrupted Line joining must not replay or duplicate the edit")
    }

    private static func hostedViewportStability() throws {
        try check(Thread.isMainThread, "Hosted vector layout checks must run on the main thread")
        for (width, compact) in [(1100.0, false), (440.0, true)] {
            let size = CGSize(width: width, height: 760)
            let blank = FontLabGlyph(character: "A", contourDesignWidth: 0.62)
            let metrics = FontLabMetrics()
            let editor = FontLabVectorEditor(glyph: blank, metrics: metrics)
            editor.tool = .line; editor.snap = false; editor.grid = false
            var commits = 0
            let root = FontLabVectorEditorView(glyph: blank, metrics: metrics, retainedEditor: editor,
                compact: compact, onChange: { _ in commits += 1 }, onUndo: {}, onRedo: {})
                .frame(width: size.width, height: size.height)
            let hosting = NSHostingView(rootView: root)
            hosting.frame = CGRect(origin: .zero, size: size)
            // Attach to a real, unshown window so AppKit coordinate conversion
            // and SwiftUI updates match the editor without presenting test UI.
            let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = hosting
            defer {
                hostedCanvas(in: hosting)?.cancelOperation(nil)
                window.contentView = nil
                window.close()
            }
            flushHostedLayout(hosting)
            guard let canvas = hostedCanvas(in: hosting) else {
                throw FontLabStore.SelfTestError.failed("Hosted vector editor did not create its native canvas at width \(width)")
            }
            let beforeFrame = canvas.convert(canvas.bounds, to: hosting)
            let beforeDesign = canvas.designRect
            try check(beforeFrame.width >= 340 && beforeFrame.height >= 340 && beforeDesign.width > 0 && beforeDesign.height > 0,
                      "Hosted vector canvas must have a usable viewport before drawing at width \(width)")
            func event(_ type: NSEvent.EventType, x: CGFloat, y: CGFloat) -> NSEvent {
                let local = CGPoint(x: beforeDesign.minX + x * beforeDesign.width, y: beforeDesign.minY + y * beforeDesign.height)
                return NSEvent.mouseEvent(with: type, location: canvas.convert(local, to: nil), modifierFlags: [],
                    timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            }
            canvas.mouseDown(with: event(.leftMouseDown, x: 0.2, y: 0.2))
            canvas.mouseDragged(with: event(.leftMouseDragged, x: 0.7, y: 0.7))
            try check(editor.openCount == 1 && editor.paths[0].nodes.count == 2 && commits == 0,
                      "The first hosted Line must expose an open-path notice while its gesture is still provisional")
            flushHostedLayout(hosting)
            try check(hostedCanvas(in: hosting) === canvas && sameViewport(canvas.convert(canvas.bounds, to: hosting), beforeFrame) &&
                      sameViewport(canvas.designRect, beforeDesign),
                      "Showing the first open-path notice must not resize or move the canvas during a Line drag at width \(width)")
            try check(editor.tool == .line && commits == 0,
                      "Rendering the open-path notice must not finish or commit the active Line gesture")
            canvas.cancelOperation(nil)
            flushHostedLayout(hosting)
            try check(editor.glyph == blank && commits == 0 &&
                      sameViewport(canvas.convert(canvas.bounds, to: hosting), beforeFrame) && sameViewport(canvas.designRect, beforeDesign),
                      "Cancelling the first hosted Line must restore blank artwork without shifting its viewport at width \(width)")
        }
    }

    private static func hostedCanvas(in view: NSView) -> FontLabVectorNSView? {
        if let canvas = view as? FontLabVectorNSView { return canvas }
        for child in view.subviews {
            if let canvas = hostedCanvas(in: child) { return canvas }
        }
        return nil
    }

    private static func flushHostedLayout(_ hosting: NSView) {
        // Published editor changes are delivered through SwiftUI's run-loop
        // updates. Bound the drain; no visible window or user events are needed.
        for _ in 0..<10 {
            hosting.needsLayout = true
            hosting.layoutSubtreeIfNeeded()
            _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        hosting.layoutSubtreeIfNeeded()
    }

    private static func sameViewport(_ first: CGRect, _ second: CGRect) -> Bool {
        abs(first.minX - second.minX) <= 0.5 && abs(first.minY - second.minY) <= 0.5 &&
        abs(first.width - second.width) <= 0.5 && abs(first.height - second.height) <= 0.5
    }

    private static func outlinePersistenceAndExport(_ drawing: Harness) throws {
        var openProject = FontLabProject(name: "Path event export", characters: ["A"])
        openProject.glyphs["A"] = drawing.editor.glyph
        try check(FontLabTrueTypeExporter.exportScope(for: openProject).mappedOpenContourCharacters == ["A"],
                  "An open Line-built A must remain visibly blocked from TrueType export")
        let openSVG = FontLabSVGExporter.string(projectName: openProject.name, glyph: drawing.editor.glyph, metrics: openProject.metrics)
        try check(openSVG.contains("fill=\"none\"") && openSVG.contains("stroke=\"#111111\""),
                  "SVG must preserve a constructed open path before outline conversion")
        drawing.editor.selectAll()
        let unoutlined = drawing.editor.glyph, beforeOutlineCommits = drawing.commits
        try check(drawing.editor.canOutlineSelectedPaths && drawing.editor.outlineSelectedPaths(widthInUnits: 40),
                  "Selected Line paths must convert into a valid physical-width filled outline")
        let outlined = drawing.editor.glyph
        try check(drawing.editor.openCount == 0 && !drawing.editor.paths.isEmpty && drawing.editor.paths.allSatisfy(\.closed) &&
                  drawing.commits == beforeOutlineCommits + 1 && drawing.editor.tool == .select && !drawing.editor.objectSelection,
                  "Stroke outlining must close its contours and commit one undoable edit")
        drawing.key("z", code: 6, modifiers: .command)
        try check(drawing.editor.glyph == unoutlined, "Undo outline conversion must recover the exact original open paths")
        drawing.key("z", code: 6, modifiers: [.command, .shift])
        try check(drawing.editor.glyph == outlined, "Redo outline conversion must recover the exact filled geometry")

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("typefield-path-events-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("font-lab.json")
        let store = FontLabStore(url: url)
        guard let id = store.addProject(name: "Path event persistence") else {
            throw FontLabStore.SelfTestError.failed("Could not create disposable path persistence project")
        }
        store.setGlyph(outlined, in: id, save: true)
        try check(store.save(), "Constructed outlines must save through the normal store")
        let restored = FontLabStore(url: url)
        guard let project = restored.selectedProject, let retained = project.glyphs["A"] else {
            throw FontLabStore.SelfTestError.failed("Constructed path project was not restored")
        }
        try check(!restored.readBlocked && retained == outlined,
                  "Saving and reopening must preserve every constructed outline, handle and identity")
        let svg = FontLabSVGExporter.string(projectName: project.name, glyph: retained, metrics: project.metrics)
        try check(svg.contains("fill-rule=\"nonzero\"") && !svg.contains("fill=\"none\""),
                  "Outlined Line artwork must export as filled SVG geometry")
        let destination = directory.appendingPathComponent("constructed-A.ttf")
        let artifact = try FontLabTrueTypeExporter.write(project, to: destination)
        let written = try Data(contentsOf: destination)
        try check(artifact.mappedCharacters == [" ", "A"] && written == artifact.data &&
                  FontLabTrueTypeExporter.exportScope(for: project).mappedOpenContourCharacters.isEmpty,
                  "A saved outlined drawing must validate and write a mapped static TrueType font")
    }
}
