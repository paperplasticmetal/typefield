import AppKit

/// Replay actual canvas events against disposable glyphs. These checks cover
/// transaction boundaries as well as geometry; no saved project is opened.
enum FontLabInteractionChecks {
    static func run() throws {
        func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
            if !condition() { throw FontLabStore.SelfTestError.failed(message) }
        }
        func pointer(_ type: NSEvent.EventType, _ point: CGPoint, modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: point, modifierFlags: modifiers, timestamp: 0,
                              windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        func key(_ characters: String, code: UInt16, type: NSEvent.EventType = .keyDown, repeatKey: Bool = false) -> NSEvent {
            NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                            context: nil, characters: characters, charactersIgnoringModifiers: characters,
                            isARepeat: repeatKey, keyCode: code)!
        }
        func canvas(_ glyph: FontLabGlyph, objects: Bool = false, snap: Bool = false) -> FontLabVectorNSView {
            let editor = FontLabVectorEditor(glyph: glyph, metrics: FontLabMetrics())
            editor.objectSelection = objects; editor.snap = snap
            let canvas = FontLabVectorNSView(editor: editor)
            canvas.frame = CGRect(x: 0, y: 0, width: 600, height: 600)
            return canvas
        }
        func screen(_ p: FontLabPoint, _ canvas: FontLabVectorNSView) -> CGPoint {
            let r = canvas.designRect
            return CGPoint(x: r.minX + p.x * r.width, y: r.minY + p.y * r.height)
        }
        func drag(_ canvas: FontLabVectorNSView, from a: FontLabPoint, to b: FontLabPoint,
                  modifiers: NSEvent.ModifierFlags = [], release: Bool = true) {
            canvas.mouseDown(with: pointer(.leftMouseDown, screen(a, canvas)))
            canvas.mouseDragged(with: pointer(.leftMouseDragged, screen(b, canvas), modifiers: modifiers))
            if release { canvas.mouseUp(with: pointer(.leftMouseUp, screen(b, canvas), modifiers: modifiers)) }
        }
        func glyph(_ paths: [FontLabVectorPath], character: String = "A") -> FontLabGlyph {
            FontLabGlyph(character: character, strokes: paths.isEmpty ? [] : [FontLabStroke(vectorPaths: paths)], contourDesignWidth: 1)
        }
        func close(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-9 }

        let compound = FontLabVectorChecks.fixture()
        let objects = canvas(compound, objects: true)
        drag(objects, from: .init(x: 0.02, y: 0.44), to: .init(x: 0.12, y: 0.54))
        try check(objects.editor.selection.count == 8 && objects.editor.glyph == compound,
                  "Object marquee must select the whole outline and counter without changing geometry")
        let beforeMove = objects.editor.paths
        drag(objects, from: .init(x: 0.1, y: 0.48), to: .init(x: 0.14, y: 0.50))
        for (before, after) in zip(beforeMove.flatMap(\.nodes), objects.editor.paths.flatMap(\.nodes)) {
            try check(close(after.point.x - before.point.x, 0.04) && close(after.point.y - before.point.y, 0.02),
                      "Dragging a marquee-selected object must move every contour and preserve its counter")
        }
        let nodes = canvas(compound)
        drag(nodes, from: .init(x: 0.02, y: 0.44), to: .init(x: 0.12, y: 0.54))
        try check(nodes.editor.selection.count == 1, "Node marquee must retain individual-node selection")
        let switched = canvas(compound)
        switched.editor.selection = [switched.editor.paths[1].nodes[0].id]
        switched.editor.objectSelection = true
        try check(switched.editor.selection.count == 8,
                  "Switching from Nodes to Objects must expand a partial selection through its outline and counter")
        let switchBefore = switched.editor.paths.flatMap(\.nodes)
        switched.keyDown(with: key("", code: 124))
        for (before, after) in zip(switchBefore, switched.editor.paths.flatMap(\.nodes)) {
            try check(close(after.point.x - before.point.x, 0.001 / compound.resolvedDesignWidth) && close(after.point.y, before.point.y),
                      "Nudging after switching to Objects must move the complete compound instead of hidden individual nodes")
        }
        switched.editor.objectSelection = false
        try check(switched.editor.selection.count == 8, "Returning to Nodes must retain the current selection")
        switched.editor.objectSelection = true
        switched.editor.tool = .pen
        switched.editor.selection = [switched.editor.paths[1].nodes[0].id]
        switched.editor.tool = .select
        try check(switched.editor.selection.count == 8,
                  "Returning from Bézier to Select must not leave hidden partial-node selection in Objects mode")
        switched.editor.insertMidpoints()
        try check(!switched.editor.objectSelection && switched.editor.selection.count == 8 &&
                  switched.editor.paths.flatMap(\.nodes).count == 16,
                  "Inserting midpoints must expose its newly selected nodes in Nodes mode")
        let toggled = canvas(compound, objects: true)
        toggled.editor.selectAll()
        toggled.mouseDown(with: pointer(.leftMouseDown, screen(.init(x: 0.1, y: 0.48), toggled), modifiers: .shift))
        toggled.mouseUp(with: pointer(.leftMouseUp, .zero))
        try check(toggled.editor.selection.isEmpty, "Shift-clicking a selected compound object must deselect its outline and counter together")
        let dot = FontLabVectorPath(nodes: [.init(point: .init(x: 0.5, y: 0.5))])
        let isolated = canvas(glyph([dot]), objects: true)
        drag(isolated, from: .init(x: 0.5, y: 0.5), to: .init(x: 0.6, y: 0.6))
        try check(close(isolated.editor.paths[0].nodes[0].point.x, 0.6) && isolated.editor.selection.count == 1,
                  "An unfinished one-node contour must remain selectable and movable in object mode")

        let box = FontLabVectorMath.rectangle(CGRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6), ellipse: false)
        let boundary = canvas(glyph([box]))
        boundary.editor.selectAll()
        var boundaryCommits = 0
        boundary.editor.onCommit = { _ in boundaryCommits += 1 }
        drag(boundary, from: box.nodes[0].point, to: .init(x: 1.2, y: 0.2), release: false)
        try check(close(boundary.editor.paths[0].nodes.map(\.point.x).max()!, 1) && boundary.editor.glyph.isValid,
                  "Dragging a group past the right boundary must stop at the edge without rejecting the movement")
        boundary.mouseDragged(with: pointer(.leftMouseDragged, screen(.init(x: -0.8, y: 0.2), boundary)))
        try check(close(boundary.editor.paths[0].nodes.map(\.point.x).min()!, 0),
                  "A bounded drag must remain reversible and stop at the opposite edge")
        boundary.mouseUp(with: pointer(.leftMouseUp, .zero))
        try check(boundaryCommits == 1, "A boundary-clamped drag must remain a single undo transaction")

        let offsetBox = FontLabVectorMath.rectangle(CGRect(x: 0.2, y: 0.219, width: 0.4, height: 0.3), ellipse: false)
        let constrained = canvas(glyph([offsetBox]), snap: true)
        drag(constrained, from: offsetBox.nodes[0].point, to: .init(x: 0.31, y: 0.2192), modifiers: .shift)
        try check(close(constrained.editor.paths[0].nodes[0].point.y, 0.219),
                  "Guide snapping must never override a Shift-locked movement axis")

        let offGrid = FontLabVectorPath(nodes: [.init(point: .init(x: 0.2004, y: 0.4)), .init(point: .init(x: 0.6009, y: 0.4))])
        let snapped = canvas(glyph([offGrid]), snap: true)
        snapped.editor.selectAll()
        drag(snapped, from: offGrid.nodes[1].point, to: .init(x: 0.7053, y: 0.4))
        try check(close(snapped.editor.paths[0].nodes[1].point.x, 0.705),
                  "Multiselection snapping must follow the node under the pointer")

        let smooth = FontLabVectorPath(nodes: [
            .init(point: .init(x: 0.5, y: 0.5), incoming: .init(x: 0.3, y: 0.5), outgoing: .init(x: 0.7, y: 0.5), smooth: true),
            .init(point: .init(x: 0.8, y: 0.8))
        ])
        let handles = canvas(glyph([smooth]))
        handles.editor.selection = [smooth.nodes[0].id]
        drag(handles, from: .init(x: 0.7, y: 0.5), to: .init(x: 0.5, y: 0.5), release: false)
        handles.mouseDragged(with: pointer(.leftMouseDragged, screen(.init(x: 0.5, y: 0.7), handles)))
        handles.mouseUp(with: pointer(.leftMouseUp, .zero))
        let opposing = handles.editor.paths[0].nodes[0].incoming!
        try check(close(opposing.x, 0.5) && close(opposing.y, 0.3),
                  "Crossing an anchor with a smooth handle must preserve the opposing handle length")
        let oldIncoming = opposing
        drag(handles, from: .init(x: 0.5, y: 0.7), to: .init(x: 0.7, y: 0.7), modifiers: .option)
        try check(!handles.editor.paths[0].nodes[0].smooth && handles.editor.paths[0].nodes[0].incoming == oldIncoming,
                  "Option-drag must break smooth coupling without moving the other handle")

        let collapsed = FontLabVectorPath(nodes: [
            .init(point: .init(x: 0.3, y: 0.3), incoming: .init(x: 0.3, y: 0.3), outgoing: .init(x: 0.3, y: 0.3)),
            .init(point: .init(x: 0.8, y: 0.8))
        ])
        let collapsedCanvas = canvas(glyph([collapsed]))
        collapsedCanvas.editor.selection = [collapsed.nodes[0].id]
        drag(collapsedCanvas, from: .init(x: 0.3, y: 0.3), to: .init(x: 0.4, y: 0.4))
        try check(close(collapsedCanvas.editor.paths[0].nodes[0].point.x, 0.4),
                  "A collapsed handle must not make its anchor impossible to drag")

        for tool in [FontLabVectorTool.rectangle, .ellipse] {
            let shape = canvas(glyph([]))
            shape.editor.tool = tool
            var commits = 0; shape.editor.onCommit = { _ in commits += 1 }
            drag(shape, from: .init(x: 0.3, y: 0.3), to: .init(x: 0.6, y: 0.7), release: false)
            try check(shape.editor.paths.count == 1, "Shape drag must show a live preview")
            shape.mouseDragged(with: pointer(.leftMouseDragged, screen(.init(x: 0.3, y: 0.3), shape)))
            shape.mouseUp(with: pointer(.leftMouseUp, .zero))
            try check(shape.editor.paths.isEmpty && commits == 0,
                      "Retracting a shape drag to its origin must remove the stale preview and create no edit")
        }

        let interrupted = canvas(glyph([box]))
        var commits = 0; interrupted.editor.onCommit = { _ in commits += 1 }
        drag(interrupted, from: box.nodes[0].point, to: .init(x: 0.25, y: 0.25), release: false)
        let edited = interrupted.editor.glyph
        _ = interrupted.resignFirstResponder()
        interrupted.mouseDragged(with: pointer(.leftMouseDragged, screen(.init(x: 0.3, y: 0.3), interrupted)))
        interrupted.mouseUp(with: pointer(.leftMouseUp, .zero))
        try check(commits == 1 && interrupted.editor.glyph == edited,
                  "Losing canvas focus must save one edit and ignore stale drag events")
        let reentrant = canvas(glyph([box]))
        var reentrantCommits = 0
        reentrant.editor.onCommit = { _ in
            reentrantCommits += 1
            if reentrantCommits == 1 { _ = reentrant.resignFirstResponder() }
        }
        drag(reentrant, from: box.nodes[0].point, to: .init(x: 0.25, y: 0.25))
        try check(reentrantCommits == 1,
                  "A view rebuild or focus callback during commit must not commit the same drag twice")
        let panned = canvas(glyph([box]))
        var panCommits = 0; panned.editor.onCommit = { _ in panCommits += 1 }
        panned.keyDown(with: key(" ", code: 49))
        panned.mouseDown(with: pointer(.leftMouseDown, CGPoint(x: 300, y: 300)))
        panned.mouseDragged(with: pointer(.leftMouseDragged, CGPoint(x: 320, y: 310)))
        panned.keyDown(with: key(" ", code: 49, repeatKey: true))
        panned.mouseDragged(with: pointer(.leftMouseDragged, CGPoint(x: 345, y: 330)))
        try check(panned.editor.pan == CGPoint(x: 45, y: 30),
                  "Holding Space through key repeat must not interrupt the ongoing pan")
        panned.cancelOperation(nil); panned.mouseUp(with: pointer(.leftMouseUp, .zero))
        panned.keyUp(with: key(" ", code: 49, type: .keyUp))
        try check(panned.editor.pan == .zero && panCommits == 0,
                  "Cancelling a pan must restore the viewport without creating a glyph edit")

        let pen = canvas(glyph([]))
        pen.editor.tool = .pen
        var penCommits = 0; pen.editor.onCommit = { _ in penCommits += 1 }
        drag(pen, from: .init(x: 0.2, y: 0.2), to: .init(x: 0.25, y: 0.25))
        let firstPenNode = pen.editor.paths[0].nodes[0]
        try check(firstPenNode.smooth && close(firstPenNode.incoming!.x, 0.15) && close(firstPenNode.outgoing!.y, 0.25),
                  "Dragging a new Bézier node must create opposite editable curve handles")
        pen.mouseDown(with: pointer(.leftMouseDown, screen(.init(x: 0.8, y: 0.2), pen)))
        pen.mouseUp(with: pointer(.leftMouseUp, .zero))
        drag(pen, from: .init(x: 0.5, y: 0.8), to: .init(x: 0.6, y: 0.8))
        pen.mouseDown(with: pointer(.leftMouseDown, screen(firstPenNode.point, pen)))
        pen.mouseUp(with: pointer(.leftMouseUp, .zero))
        try check(pen.editor.paths.count == 1 && pen.editor.paths[0].closed && pen.editor.paths[0].nodes.count == 3 &&
                  pen.editor.activePath == nil && pen.editor.glyph.isValid && penCommits == 4,
                  "Clicking the first Bézier node must close its contour in exactly one additional edit")
        let closedPen = pen.editor.glyph
        drag(pen, from: .init(x: 0.85, y: 0.85), to: .init(x: 0.88, y: 0.89), release: false)
        pen.cancelOperation(nil); pen.mouseUp(with: pointer(.leftMouseUp, .zero))
        try check(pen.editor.glyph == closedPen && penCommits == 4,
                  "Escape during Bézier placement must discard just the unfinished node gesture")
        pen.mouseDown(with: pointer(.leftMouseDown, screen(.init(x: 0.1, y: 0.8), pen)))
        pen.mouseUp(with: pointer(.leftMouseUp, .zero))
        let unfinished = pen.editor.glyph
        pen.cancelOperation(nil)
        try check(pen.editor.glyph == unfinished && pen.editor.paths.count == 2 && pen.editor.activePath == nil &&
                  pen.editor.tool == .select && penCommits == 5,
                  "Escape between Bézier gestures must finish the path without deleting committed nodes")
        pen.editor.selection = Set(pen.editor.paths[0].nodes.map(\.id))
        let beforeReversal = pen.editor.paths
        pen.editor.pathCommand("reverse"); pen.editor.pathCommand("reverse")
        try check(pen.editor.paths == beforeReversal && penCommits == 7,
                  "Reversing a mouse-created curved contour twice must restore every anchor and handle")

        for shift in [false, true] {
            let resized = canvas(glyph([box]), objects: true)
            resized.editor.selectAll()
            var resizeCommits = 0; resized.editor.onCommit = { _ in resizeCommits += 1 }
            drag(resized, from: .init(x: 0.8, y: 0.8), to: .init(x: 0.7, y: 0.6), modifiers: shift ? .shift : [])
            let anchors = resized.editor.paths[0].nodes.map(\.point)
            try check(close(anchors.map(\.x).min()!, 0.2) && close(anchors.map(\.y).min()!, 0.2) &&
                      close(anchors.map(\.x).max()!, shift ? 0.6 : 0.7) && close(anchors.map(\.y).max()!, 0.6) && resizeCommits == 1,
                      "Corner resize must retain its opposite corner and obey Shift proportional scaling")
            let resizedGlyph = resized.editor.glyph
            drag(resized, from: .init(x: shift ? 0.6 : 0.7, y: 0.6), to: .init(x: 0.5, y: 0.5), release: false)
            resized.cancelOperation(nil); resized.mouseUp(with: pointer(.leftMouseUp, .zero))
            try check(resized.editor.glyph == resizedGlyph && resizeCommits == 1,
                      "Cancelling an object resize must restore geometry without adding an undo entry")
        }

        for sameCharacter in [false, true] {
            let replaced = canvas(glyph([box]))
            var replacementCommits = 0; replaced.editor.onCommit = { _ in replacementCommits += 1 }
            drag(replaced, from: box.nodes[0].point, to: .init(x: 0.25, y: 0.25), release: false)
            let replacement = glyph([smooth], character: sameCharacter ? "A" : "B")
            replaced.editor.receive(replacement)
            replaced.mouseDragged(with: pointer(.leftMouseDragged, screen(.init(x: 0.3, y: 0.3), replaced)))
            replaced.cancelOperation(nil)
            replaced.mouseUp(with: pointer(.leftMouseUp, .zero))
            try check(replaced.editor.glyph == replacement && replacementCommits == 0,
                      "A document replacement during a drag must not replay or restore the previous glyph")
        }

        var line = FontLabVectorPath(nodes: [.init(point: .init(x: 0.2, y: 0.3)), .init(point: .init(x: 0.8, y: 0.6))])
        line.setSmooth(0, true); line.setSmooth(1, true)
        try check(line.nodes[0].incoming == nil && line.nodes[1].outgoing == nil &&
                  close(line.nodes[0].outgoing!.x, 0.4) && close(line.nodes[0].outgoing!.y, 0.4) &&
                  close(line.nodes[1].incoming!.x, 0.6) && close(line.nodes[1].incoming!.y, 0.5),
                  "Smoothing an open line must create nonzero handles along its own segment")
        var openCorner = FontLabVectorPath(nodes: [.init(point: .init(x: 0.1, y: 0.1)), .init(point: .init(x: 0.6, y: 0.1)), .init(point: .init(x: 0.6, y: 0.8))])
        openCorner.setSmooth(0, true); openCorner.setSmooth(2, true)
        try check(close(openCorner.nodes[0].outgoing!.y, 0.1) && close(openCorner.nodes[2].incoming!.x, 0.6),
                  "Open endpoint smoothing must ignore the unrelated far endpoint")
        let paintedA = FontLabVectorMath.rectangle(CGRect(x: 0.1, y: 0.1, width: 0.6, height: 0.6), ellipse: false)
        var paintedB = FontLabVectorMath.rectangle(CGRect(x: 0.3, y: 0.3, width: 0.6, height: 0.6), ellipse: false)
        paintedB.reverse()
        let painted = canvas(FontLabGlyph(character: "B", strokes: [FontLabStroke(vectorPaths: [paintedA]), FontLabStroke(vectorPaths: [paintedB])], contourDesignWidth: 1), objects: true)
        painted.editor.grid = false
        painted.editor.inkColor = .init(nsColor: NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 1))
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 600, pixelsHigh: 600,
                                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else {
            throw FontLabStore.SelfTestError.failed("Could not render the independent-stroke paint fixture")
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        painted.draw(painted.bounds)
        graphics.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        let sample = screen(.init(x: 0.43, y: 0.43), painted)
        let paintedColor = bitmap.colorAt(x: Int(sample.x), y: Int(sample.y))!.usingColorSpace(.deviceRGB)!
        try check(paintedColor.redComponent > 0.95 && paintedColor.greenComponent < 0.05,
                  "Independent opposite-winding strokes must paint their overlap in the vector canvas instead of cancelling")
        try check(FontLabShortcutAction.resolve(key:"c",modifiers:.command) == .copyContours &&
                  FontLabShortcutAction.resolve(key:"v",modifiers:.command) == .pasteContours &&
                  FontLabShortcutAction.resolve(key:"a",modifiers:.command) == .selectAllContours &&
                  FontLabShortcutAction.resolve(key:"v",modifiers:[.command,.shift]) == nil &&
                  FontLabShortcutAction.resolve(key:"v",modifiers:[]) == nil,
                  "Workspace contour commands must match only their unmodified Command shortcuts")
        try check(FontLabShortcutAnchor.allowsWorkspaceShortcuts(matchingWindow:true,isKeyWindow:true,hasSheet:false,hasModalWindow:false,firstResponder:NSView()),
                  "Workspace contour shortcuts must remain available after selecting a glyph")
        for responder in [NSTextView(), NSTextField()] as [NSResponder] {
            try check(!FontLabShortcutAnchor.allowsWorkspaceShortcuts(matchingWindow:true,isKeyWindow:true,hasSheet:false,hasModalWindow:false,firstResponder:responder),
                      "Workspace shortcuts must preserve normal text-field copy, paste and select-all")
        }
        for context in [(false,true,false,false),(true,false,false,false),(true,true,true,false),(true,true,false,true)] {
            try check(!FontLabShortcutAnchor.allowsWorkspaceShortcuts(matchingWindow:context.0,isKeyWindow:context.1,hasSheet:context.2,hasModalWindow:context.3,firstResponder:NSView()),
                      "Workspace shortcuts must not cross windows or intercept sheet/modal input")
        }
        try check(painted.responds(to: #selector(FontLabVectorNSView.copy(_:))) &&
                  painted.responds(to: #selector(FontLabVectorNSView.paste(_:))) &&
                  painted.responds(to: #selector(FontLabVectorNSView.selectAll(_:))),
                  "The focused vector canvas must expose native Edit menu responders")
        painted.selectAll(nil)
        try check(painted.editor.selection.count == 8, "The native Select All menu action must select contour anchors")
        let retainedSession = FontLabEditorSession()
        let visibleEditor = retainedSession.vector(for:"current-glyph",glyph:compound,metrics:FontLabMetrics())
        let workspaceEditor = retainedSession.vector(for:"current-glyph",glyph:compound,metrics:FontLabMetrics())
        workspaceEditor.selectAll()
        try check(visibleEditor === workspaceEditor && visibleEditor.selection.count == 8,
                  "Workspace commands must share the visible glyph's retained editor and selection")
        print("PASS: Letterform canvas compound selection, snapping, boundary drag, handle continuity, shape retraction, interruption and endpoint smoothing checks")
    }
}
