import AppKit
import CoreText

enum FontLabVectorChecks {
    static func fixture() -> FontLabGlyph {
        let outer=FontLabVectorMath.rectangle(CGRect(x:0.1,y:0.18,width:0.8,height:0.6),ellipse:true)
        var inner=FontLabVectorMath.rectangle(CGRect(x:0.28,y:0.30,width:0.44,height:0.36),ellipse:true);inner.reverse()
        return FontLabGlyph(character:"O",strokes:[FontLabStroke(vectorPaths:[outer,inner])],contourDesignWidth:0.62)
    }
    static func run() throws {
        try FontLabInteractionChecks.run()
        try FontLabDirectCurveChecks.run()
        func check(_ condition:@autoclosure()->Bool,_ message:String)throws {if !condition() {throw FontLabStore.SelfTestError.failed(message)}}
        let glyph=fixture(),metrics=FontLabMetrics()
        let densePoints = (0..<10_000).map { index -> FontLabPoint in
            let angle = Double(index) * 2 * Double.pi / 10_000
            return .init(x: 0.5 + 0.4 * cos(angle), y: 0.5 + 0.4 * sin(angle))
        }
        let denseGlyph = FontLabGlyph(character: "D", strokes: [FontLabStroke(contours: [densePoints])])
        let cachedEditor = FontLabVectorEditor(glyph: denseGlyph, metrics: metrics)
        let firstPaths = cachedEditor.paths
        let startUncached = Date.timeIntervalSinceReferenceDate
        var uncachedCount = 0
        for _ in 0..<100 { uncachedCount += FontLabVectorMath.paths(in: denseGlyph)[0].nodes.count }
        let uncachedTime = Date.timeIntervalSinceReferenceDate - startUncached
        let startCached = Date.timeIntervalSinceReferenceDate
        var cachedCount = 0
        for _ in 0..<100 { cachedCount += cachedEditor.paths[0].nodes.count }
        let cachedTime = Date.timeIntervalSinceReferenceDate - startCached
        try check(cachedCount == uncachedCount && firstPaths == cachedEditor.paths,
                  "Cached legacy contours changed node identities or geometry")
        cachedEditor.glyph.strokes[0].contours![0][0].x = 0.8
        try check(cachedEditor.paths[0].nodes[0].point.x == 0.8,
                  "Nested glyph edits must invalidate converted contours")
        cachedEditor.receive(glyph)
        try check(cachedEditor.paths == FontLabVectorMath.paths(in: glyph),
                  "Receiving another glyph must invalidate converted contours")
        cachedEditor.receive(denseGlyph)
        try check(cachedEditor.paths == firstPaths && cachedEditor.glyph == denseGlyph,
                  "Restoring a glyph must restore its paths without modifying saved artwork")
        print(String(format: "PERF: 100 dense-outline reads (10,000 anchors): uncached %.3f ms; cached %.3f ms", uncachedTime * 1000, cachedTime * 1000))

        // Compare optimized hit testing with the original exhaustive sampler,
        // including curved controls outside their anchors at several zoom levels.
        let hitEditor = FontLabVectorEditor(glyph: glyph, metrics: metrics)
        let hitCanvas = FontLabVectorNSView(editor: hitEditor)
        hitCanvas.frame = CGRect(x: 0, y: 0, width: 600, height: 600)
        func exhaustiveHit(_ point: CGPoint) -> (Int, Int, Double)? {
            var best: (Int, Int, Double)?, distance = 7.0
            let rect = hitCanvas.designRect
            func screen(_ p: FontLabPoint) -> CGPoint { CGPoint(x: rect.minX + p.x * rect.width, y: rect.minY + p.y * rect.height) }
            for (a, path) in hitEditor.paths.enumerated() {
                for b in 0..<path.segmentCount {
                    let controls = path.controls(b), curve = path.isCurve(b), samples = curve ? 50 : 1
                    for sample in 0..<samples {
                        let t0 = Double(sample) / Double(samples), t1 = Double(sample + 1) / Double(samples)
                        let q = screen(curve ? FontLabVectorMath.evaluate(controls, t0) : controls[0])
                        let r = screen(curve ? FontLabVectorMath.evaluate(controls, t1) : controls[3])
                        let dx = r.x-q.x, dy = r.y-q.y
                        let t = min(1, max(0, ((point.x-q.x)*dx + (point.y-q.y)*dy) / max(1e-12, dx*dx+dy*dy)))
                        let d = hypot(q.x+dx*t-point.x, q.y+dy*t-point.y)
                        if d < distance { distance = d; best = (a, b, t0+(t1-t0)*t) }
                    }
                }
            }
            return best
        }
        for zoom in [0.5, 1.0, 3.0] {
            hitEditor.zoom = zoom
            for x in stride(from: 0.0, through: 600.0, by: 19) {
                for y in stride(from: 0.0, through: 600.0, by: 23) {
                    let point = CGPoint(x: x, y: y)
                    let expected = exhaustiveHit(point), actual = hitCanvas.hitSegment(point)
                    try check(expected?.0 == actual?.0 && expected?.1 == actual?.1 && abs((expected?.2 ?? 0) - (actual?.2 ?? 0)) < 1e-10,
                              "Control-hull hit rejection changed the selected curve or insertion position")
                }
            }
        }
        var history = FontLabGlyphEditHistory()
        var editedO = glyph; editedO.leftSideBearing += 0.01
        var a = glyph; a.character = "A"
        var editedA = a; editedA.rightSideBearing += 0.02
        history.record(glyph); history.record(a)
        try check(history.undo(editedO) == glyph && history.undo(editedA) == a,
                  "Changing the active letter lost its independent undo history")
        try check(history.redo(glyph) == editedO && history.undo(a) == nil,
                  "Undo without history must not remove saved artwork; redo must restore the matching glyph")

        var denseHistory = FontLabGlyphEditHistory()
        for step in 0..<30 {
            var snapshot = denseGlyph; snapshot.leftSideBearing = Double(step) / 1000
            denseHistory.record(snapshot)
        }
        try check(denseHistory.undoEntries["D"]?.count == 20,
                  "Dense history must retain at most its 200,000-anchor budget")
        var denseCurrent = denseGlyph; denseCurrent.leftSideBearing = 0.031
        let densePrevious = denseHistory.undo(denseCurrent)!
        try check(denseHistory.redo(densePrevious) == denseCurrent,
                  "Dense history pruning must preserve the newest undo/redo pair")
        _ = denseHistory.undo(denseCurrent)
        denseHistory.record(densePrevious)
        try check(denseHistory.redo(densePrevious) == nil,
                  "A new edit after undo must invalidate the abandoned redo branch")
        let rejectedEditor = FontLabVectorEditor(glyph: glyph, metrics: metrics)
        rejectedEditor.selectAll()
        let rejectionSelection = rejectedEditor.selection
        var rejectedCommits = 0; rejectedEditor.onCommit = { _ in rejectedCommits += 1 }
        rejectedEditor.move(dx: 10, dy: 0)
        try check(rejectedEditor.glyph == glyph && rejectedEditor.selection == rejectionSelection && rejectedCommits == 0,
                  "Rejected geometry must preserve the complete glyph, selection and undo boundary")

        var navigationProject = FontLabProject(name: "Navigation fixture", characters: ["A", "B", "C"])
        var drawnB = glyph; drawnB.character = "B"
        navigationProject.glyphs["B"] = drawnB
        try check(FontLabCharacterFilter.all.characters(in: navigationProject) == ["A", "B", "C"] &&
                  FontLabCharacterFilter.drawn.characters(in: navigationProject) == ["B"] &&
                  FontLabCharacterFilter.empty.characters(in: navigationProject) == ["A", "C"],
                  "Drawn and Empty navigation must preserve project character order and source glyphs")
        try check(FontLabCharacterNavigation.match(" B ", in: navigationProject.characters) == "B" &&
                  FontLabCharacterNavigation.match("b", in: navigationProject.characters) == "B" &&
                  FontLabCharacterNavigation.match("BC", in: navigationProject.characters) == nil &&
                  FontLabCharacterNavigation.match("Q", in: navigationProject.characters) == nil,
                  "Jump to character must select only one available project character")
        var filteredProject = FontLabProject(name: "Filtered navigation", characters: ["A", "B", "C", "D", "E"])
        filteredProject.glyphs["B"] = drawnB
        var drawnD = glyph; drawnD.character = "D"
        filteredProject.glyphs["D"] = drawnD
        var orphanQ = glyph; orphanQ.character = "Q"
        filteredProject.glyphs["Q"] = orphanQ
        try check(filteredProject.completedCount == 2 &&
                  FontLabCharacterNavigation.sequence(selectedCharacter: "B", in: filteredProject, filter: .drawn) == ["B", "D"] &&
                  FontLabCharacterNavigation.sequence(selectedCharacter: "C", in: filteredProject, filter: .drawn) == ["B", "C", "D"] &&
                  FontLabCharacterNavigation.sequence(selectedCharacter: "C", in: filteredProject, filter: .empty) == ["A", "C", "E"],
                  "Filtered navigation must skip hidden glyphs, retain a hidden current glyph, and ignore orphan artwork in completion counts")
        try check(FontLabProofStripLayout.clamped(0) == FontLabProofStripLayout.minimumHeight &&
                  FontLabProofStripLayout.clamped(9_999) == FontLabProofStripLayout.maximumHeight,
                  "Resizable proof strip must stay within usable height limits")
        let bridge = FontLabEditMenuBridge.shared
        let fixtureID = UUID()
        final class CommandRecorder { var received: [String] = [] }
        let recorder = CommandRecorder()
        let observer = NotificationCenter.default.addObserver(forName: FontLabEditMenuBridge.commandNotification, object: nil, queue: nil) { event in
            if let command = event.object as? String { recorder.received.append(command) }
        }
        bridge.update(projectID: fixtureID, character: "B", canUndo: true, canRedo: false)
        bridge.requestUndo(); bridge.requestRedo()
        try check(bridge.canUndo && !bridge.canRedo && bridge.undoTitle == "Undo B edit" && recorder.received == ["undo"],
                  "Edit-menu bridge must route only available glyph history actions")
        bridge.clear(); bridge.requestUndo()
        NotificationCenter.default.removeObserver(observer)
        try check(bridge.projectID == nil && !bridge.canUndo && recorder.received == ["undo"],
                  "Edit-menu bridge must clear when the Letterform Editor closes")

        let surgery = FontLabVectorEditor(glyph: glyph, metrics: metrics)
        var surgeryCommits = 0; surgery.onCommit = { _ in surgeryCommits += 1 }
        let contour = surgery.paths[0]
        surgery.selection = [contour.nodes[1].id]
        surgery.splitAtNode()
        try check(!surgery.paths[0].closed && surgery.paths[0].nodes.count == 5 && surgeryCommits == 1,
                  "Splitting a closed curve must create two independent endpoints in one edit")
        for i in 0..<contour.segmentCount { for sample in 0...20 {
            let before = FontLabVectorMath.evaluate(contour.controls((i+1)%contour.segmentCount),Double(sample)/20)
            let after = FontLabVectorMath.evaluate(surgery.paths[0].controls(i),Double(sample)/20)
            try check(hypot(before.x-after.x,before.y-after.y)<1e-10,"Splitting changed the original curve")
        } }
        surgery.joinEndpoints()
        try check(surgery.paths[0].closed && surgery.glyph.isValid && surgeryCommits == 2,"Joining split endpoints failed")
        let open = FontLabVectorPath(nodes: [
            FontLabVectorNode(point: .init(x:0.1,y:0.2),outgoing:.init(x:0.2,y:0.6)),
            FontLabVectorNode(point: .init(x:0.4,y:0.4),incoming:.init(x:0.3,y:0.7),outgoing:.init(x:0.5,y:0.3)),
            FontLabVectorNode(point: .init(x:0.8,y:0.2),incoming:.init(x:0.7,y:0.5))])
        let openGlyph = FontLabGlyph(character:"S",strokes:[FontLabStroke(vectorPaths:[open])])
        let splitOpen = FontLabVectorEditor(glyph:openGlyph,metrics:metrics)
        splitOpen.selection = [open.nodes[1].id]; splitOpen.splitAtNode()
        try check(splitOpen.paths.count == 2 && splitOpen.paths.allSatisfy { !$0.closed && $0.nodes.count == 2 },"Open-curve split lost a segment")
        splitOpen.joinEndpoints()
        try check(splitOpen.paths.count == 1 && splitOpen.paths[0].segmentCount == 2 && splitOpen.glyph.isValid,"Joining two open contours lost geometry")
        let midpoint = FontLabVectorEditor(glyph:openGlyph,metrics:metrics)
        midpoint.selectAll(); midpoint.insertMidpoints()
        try check(midpoint.paths[0].nodes.count == 5 && midpoint.selection.count == 2,"Midpoint insertion failed for adjacent cubic segments")
        for segment in 0..<2 { for sample in 0...40 {
            let t = Double(sample)/40
            let before = FontLabVectorMath.evaluate(open.controls(segment),t)
            let after = FontLabVectorMath.evaluate(midpoint.paths[0].controls(segment*2+(t>0.5 ? 1:0)),t>0.5 ? (t-0.5)*2:t*2)
            try check(hypot(before.x-after.x,before.y-after.y)<1e-10,"Inserted midpoint distorted a cubic")
        } }
        let distribution = FontLabVectorEditor(glyph:openGlyph,metrics:metrics)
        distribution.objectSelection = false; distribution.selectAll(); distribution.distribute(horizontal:true)
        try check(abs(distribution.paths[0].nodes[1].point.x-0.45)<1e-10 &&
                  abs(distribution.paths[0].nodes[1].outgoing!.x-0.55)<1e-10,
                  "Node distribution failed to translate curve handles with the anchor")
        let singleObject = FontLabVectorEditor(glyph:glyph,metrics:metrics)
        singleObject.objectSelection = true
        singleObject.selectAll(); singleObject.align(horizontal:true); singleObject.align(horizontal:false)
        singleObject.distribute(horizontal:true)
        try check(singleObject.glyph == glyph && !singleObject.canAlign && !singleObject.canDistribute,
                  "A single object with a counter must never collapse under alignment/distribution")
        let extra = FontLabVectorMath.rectangle(CGRect(x:0.01,y:0.04,width:0.05,height:0.06),ellipse:true)
        let arrangedGlyph = FontLabGlyph(character:"O",strokes:[FontLabStroke(vectorPaths:FontLabVectorMath.paths(in:glyph)+[extra])])
        for horizontal in [true,false] {
            let editor = FontLabVectorEditor(glyph:arrangedGlyph,metrics:metrics)
            editor.objectSelection = true
            editor.selection = [editor.paths[1].nodes[0].id,extra.nodes[0].id]
            let before = editor.paths; editor.align(horizontal:horizontal)
            let after = editor.paths
            try check(editor.canAlign && editor.glyph.isValid,"Compound object alignment failed")
            var shifts: [FontLabPoint] = []
            for (original,result) in zip(before,after) {
                let dx=result.nodes[0].point.x-original.nodes[0].point.x,dy=result.nodes[0].point.y-original.nodes[0].point.y
                shifts.append(.init(x:dx,y:dy))
                for (a,b) in zip(original.nodes,result.nodes) {
                    for (u,v) in zip([a.point,a.incoming!,a.outgoing!],[b.point,b.incoming!,b.outgoing!]) {
                        try check(abs(v.x-u.x-dx)<1e-10 && abs(v.y-u.y-dy)<1e-10,"Object alignment distorted curves")
                    }
                }
            }
            try check(abs(shifts[0].x-shifts[1].x)<1e-10 && abs(shifts[0].y-shifts[1].y)<1e-10,"Alignment detached a counter")
            let a=after[0].cgPath.boundingBoxOfPath,b=after[2].cgPath.boundingBoxOfPath
            try check(abs(horizontal ? a.midY-b.midY : a.midX-b.midX)<1e-8,"Object centers were not aligned")
        }
        for horizontal in [true,false] {
            let shapes = [CGRect(x:0.05,y:0.05,width:0.1,height:0.1),CGRect(x:0.2,y:0.2,width:0.1,height:0.1),CGRect(x:0.8,y:0.8,width:0.1,height:0.1)]
                .map { FontLabVectorMath.rectangle($0,ellipse:true) }
            let editor=FontLabVectorEditor(glyph:FontLabGlyph(character:"X",strokes:[FontLabStroke(vectorPaths:shapes)]),metrics:metrics)
            editor.objectSelection = true
            editor.selectAll();editor.distribute(horizontal:horizontal)
            try check(editor.canDistribute && editor.glyph.isValid,"Three objects could not be distributed")
            let result=editor.paths, centers=result.map { horizontal ? $0.cgPath.boundingBoxOfPath.midX : $0.cgPath.boundingBoxOfPath.midY }
            try check(abs((centers[1]-centers[0])-(centers[2]-centers[1]))<1e-8,"Object centers were not evenly distributed")
            try check(result[0]==shapes[0] && result[2]==shapes[2],"Distribution moved the outermost objects")
            let dx=result[1].nodes[0].point.x-shapes[1].nodes[0].point.x,dy=result[1].nodes[0].point.y-shapes[1].nodes[0].point.y
            for (a,b) in zip(shapes[1].nodes,result[1].nodes) {
                for (u,v) in zip([a.point,a.incoming!,a.outgoing!],[b.point,b.incoming!,b.outgoing!]) {
                    try check(abs(v.x-u.x-dx)<1e-10 && abs(v.y-u.y-dy)<1e-10,"Object distribution distorted curves")
                }
            }
        }
        let focusViewport=CGSize(width:600,height:520)
        let contourBounds=CGRect(x:0.1,y:0.18,width:0.8,height:0.6)
        guard let contourFocus=FontLabVectorEditor.focusTransform(selectionBounds:contourBounds,viewport:focusViewport,designWidth:glyph.resolvedDesignWidth) else {
            throw FontLabStore.SelfTestError.failed("Focus Selection rejected a valid contour.")
        }
        let focusEm=max(80,min((focusViewport.width-90)/glyph.resolvedDesignWidth,focusViewport.height-75))*contourFocus.zoom
        let focusLeft=(focusViewport.width-focusEm*glyph.resolvedDesignWidth)/2+contourFocus.pan.x+contourBounds.minX*focusEm*glyph.resolvedDesignWidth
        let focusRight=(focusViewport.width-focusEm*glyph.resolvedDesignWidth)/2+contourFocus.pan.x+contourBounds.maxX*focusEm*glyph.resolvedDesignWidth
        let focusBottom=(focusViewport.height-focusEm)/2+contourFocus.pan.y+contourBounds.minY*focusEm
        let focusTop=(focusViewport.height-focusEm)/2+contourFocus.pan.y+contourBounds.maxY*focusEm
        try check(focusLeft>=31 && focusRight<=focusViewport.width-31 && focusBottom>=31 && focusTop<=focusViewport.height-31,"Focus Selection did not frame contour bounds with padding.")
        let overshootPath = FontLabVectorPath(nodes: [
            FontLabVectorNode(point: FontLabPoint(x: 0.3, y: 0.35), outgoing: FontLabPoint(x: -1.5, y: -1.0)),
            FontLabVectorNode(point: FontLabPoint(x: 0.7, y: 0.65), incoming: FontLabPoint(x: 2.5, y: 2.0))
        ])
        let overshootGlyph = FontLabGlyph(character: "C", strokes: [FontLabStroke(vectorPaths: [overshootPath])], contourDesignWidth: 0.62)
        let overshootEditor = FontLabVectorEditor(glyph: overshootGlyph, metrics: metrics)
        overshootEditor.selection = [overshootPath.nodes[0].id]
        let overshootBounds = overshootEditor.selectedFocusBounds
        guard let overshootFocus = FontLabVectorEditor.focusTransform(selectionBounds: overshootBounds,
                                                                       viewport: focusViewport,
                                                                       designWidth: overshootGlyph.resolvedDesignWidth) else {
            throw FontLabStore.SelfTestError.failed("Focus Selection rejected a valid overshooting curve.")
        }
        let overshootEm = max(80, min((focusViewport.width - 90) / overshootGlyph.resolvedDesignWidth, focusViewport.height - 75)) * overshootFocus.zoom
        let overshootLeft = (focusViewport.width - overshootEm * overshootGlyph.resolvedDesignWidth) / 2 + overshootFocus.pan.x + overshootBounds.minX * overshootEm * overshootGlyph.resolvedDesignWidth
        let overshootRight = (focusViewport.width - overshootEm * overshootGlyph.resolvedDesignWidth) / 2 + overshootFocus.pan.x + overshootBounds.maxX * overshootEm * overshootGlyph.resolvedDesignWidth
        let overshootBottom = (focusViewport.height - overshootEm) / 2 + overshootFocus.pan.y + overshootBounds.minY * overshootEm
        let overshootTop = (focusViewport.height - overshootEm) / 2 + overshootFocus.pan.y + overshootBounds.maxY * overshootEm
        try check(overshootEditor.selectedBounds.minX == 0.3 && overshootBounds.minX == -1.5 && overshootBounds.maxX == 2.5
                  && overshootFocus.zoom < 0.5 && overshootLeft >= 31 && overshootRight <= focusViewport.width - 31
                  && overshootBottom >= 31 && overshootTop <= focusViewport.height - 31,
                  "Focus Selection must include selected Bézier control handles and keep their overshooting curves inside the viewport")
        let nodeFocus=FontLabVectorEditor.focusTransform(selectionBounds:CGRect(x:0.96,y:0.94,width:0,height:0),viewport:focusViewport,designWidth:glyph.resolvedDesignWidth)
        let emptyFocus=FontLabVectorEditor.focusTransform(selectionBounds:.null,viewport:focusViewport,designWidth:glyph.resolvedDesignWidth)
        let emptyRejected: Bool
        if case .none = emptyFocus { emptyRejected=true } else { emptyRejected=false }
        try check((nodeFocus?.zoom ?? 0)>0 && emptyRejected,"Focus Selection did not handle a single node or empty selection.")
        let objectEditor=FontLabVectorEditor(glyph:glyph,metrics:metrics)
        objectEditor.selectObject(1,adding:false)
        try check(objectEditor.selection.count == 8,"Object selection failed to include outer contour and counter")
        let objectOriginal=objectEditor.paths,objectAnchor=FontLabPoint(x:0.1,y:0.18)
        let objectResized=FontLabVectorEditor.resized(objectOriginal,selection:objectEditor.selection,anchor:objectAnchor,sx:0.5,sy:0.5)
        for (before,after) in zip(objectOriginal.flatMap(\.nodes),objectResized.flatMap(\.nodes)) {
            try check(abs(after.point.x-(objectAnchor.x+(before.point.x-objectAnchor.x)*0.5))<1e-10,"Object resize moved an anchor incorrectly")
            if let a=before.outgoing,let b=after.outgoing { try check(abs(b.y-(objectAnchor.y+(a.y-objectAnchor.y)*0.5))<1e-10,"Object resize did not scale Bézier handles") }
        }
        var objectCommits=0;objectEditor.onCommit={_ in objectCommits += 1}
        _=objectEditor.apply(objectResized,commit:false);objectEditor.finishGesture(from:glyph)
        try check(objectCommits==1 && objectEditor.glyph.isValid,"Corner resizing must commit one undoable edit")

        func pointer(_ type: NSEvent.EventType, _ point: CGPoint) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        func key(_ characters: String, code: UInt16, modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: 0, context: nil, characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)!
        }
        let transactionEditor = FontLabVectorEditor(glyph: glyph, metrics: metrics)
        transactionEditor.objectSelection = false; transactionEditor.snap = false
        let transactionCanvas = FontLabVectorNSView(editor: transactionEditor)
        transactionCanvas.frame = CGRect(x: 0, y: 0, width: 600, height: 600)
        let transactionNode = transactionEditor.paths[0].nodes[0]
        let transactionRect = transactionCanvas.designRect
        let nodeLocation = CGPoint(x: transactionRect.minX + transactionNode.point.x * transactionRect.width,
                                   y: transactionRect.minY + transactionNode.point.y * transactionRect.height)
        let movedLocation = CGPoint(x: nodeLocation.x + 8, y: nodeLocation.y + 5)
        var transactionCommits: [FontLabGlyph] = []
        transactionEditor.onCommit = { transactionCommits.append($0) }
        transactionEditor.selection = [transactionNode.id]
        transactionCanvas.mouseDown(with: pointer(.leftMouseDown, nodeLocation))
        transactionCanvas.mouseDragged(with: pointer(.leftMouseDragged, movedLocation))
        try check(transactionEditor.glyph != glyph && transactionCommits.isEmpty, "Dragging must remain an uncommitted edit until release")
        transactionCanvas.keyDown(with: key("q", code: 12))
        try check(transactionCommits.isEmpty && transactionEditor.glyph != glyph,
                  "Unrecognized keys must not commit or terminate an active drag")
        transactionCanvas.keyDown(with: key("\u{1b}", code: 53))
        transactionCanvas.mouseUp(with: pointer(.leftMouseUp, movedLocation))
        try check(transactionEditor.glyph == glyph && transactionEditor.selection == [transactionNode.id] && transactionCommits.isEmpty,
                  "Escape must restore geometry and selection without creating an undo entry on mouse-up")
        transactionCanvas.mouseDown(with: pointer(.leftMouseDown, nodeLocation))
        transactionCanvas.mouseDragged(with: pointer(.leftMouseDragged, movedLocation))
        transactionEditor.onUndo = {
            if !transactionCommits.isEmpty { transactionEditor.receive(glyph) }
        }
        transactionCanvas.keyDown(with: key("z", code: 6, modifiers: .command))
        transactionCanvas.mouseDragged(with: pointer(.leftMouseDragged, CGPoint(x: movedLocation.x + 5, y: movedLocation.y)))
        transactionCanvas.mouseUp(with: pointer(.leftMouseUp, movedLocation))
        try check(transactionCommits.count == 1 && transactionEditor.glyph == glyph,
                  "Undo during drag must finish one transaction and stop subsequent drag events from replaying it")
        transactionCommits = []
        transactionEditor.tool = .rectangle
        let shapeStart = CGPoint(x: transactionRect.minX + 20, y: transactionRect.minY + 20)
        let shapeEnd = CGPoint(x: shapeStart.x + 30, y: shapeStart.y + 40)
        transactionCanvas.mouseDown(with: pointer(.leftMouseDown, shapeStart))
        transactionCanvas.mouseDragged(with: pointer(.leftMouseDragged, shapeEnd))
        transactionCanvas.cancelOperation(nil)
        transactionCanvas.mouseUp(with: pointer(.leftMouseUp, shapeEnd))
        try check(transactionEditor.glyph == glyph && transactionCommits.isEmpty, "Cancelling a shape must discard its temporary contour")

        let denseOuter = FontLabVectorPath(nodes: densePoints.map { FontLabVectorNode(point: $0) }, closed: true)
        let denseInnerPoints = (0..<600).map { index -> FontLabPoint in
            let angle = Double(index) * 2 * Double.pi / 600
            return .init(x: 0.5 + 0.2 * cos(angle), y: 0.5 + 0.2 * sin(angle))
        }
        let denseInner = FontLabVectorPath(nodes: denseInnerPoints.map { FontLabVectorNode(point: $0) }, closed: true)
        let denseObjectEditor = FontLabVectorEditor(glyph: FontLabGlyph(character: "O", strokes: [FontLabStroke(vectorPaths: [denseOuter, denseInner])]), metrics: metrics)
        let selectionStarted = Date()
        denseObjectEditor.selectObject(1, adding: false)
        try check(denseObjectEditor.selection.count == 10_600,
                  "Dense object selection must retain both enclosing outline and counter anchors")
        print(String(format: "PERF: select 10,600-anchor object and counter %.3f ms", Date().timeIntervalSince(selectionStarted) * 1000))

        let accessibilityEditor=FontLabVectorEditor(glyph:glyph,metrics:metrics)
        let accessibilityCanvas=FontLabVectorNSView(editor:accessibilityEditor)
        accessibilityCanvas.frame=CGRect(x:0,y:0,width:600,height:600)
        let contours=accessibilityCanvas.accessibilityChildren() as? [NSAccessibilityElement] ?? []
        try check(contours.count==2 && contours[0].accessibilityLabel()?.contains("Contour 1") == true,"Vector contours are missing from the accessibility hierarchy")
        let nodes=contours[0].accessibilityChildren() as? [NSAccessibilityElement] ?? []
        try check(nodes.count==4 && nodes[0].accessibilityLabel()?.contains("node 1") == true,"Vector nodes are missing from the accessibility hierarchy")
        try check(contours.allSatisfy { $0.isAccessibilityEnabled() } && nodes.allSatisfy { $0.isAccessibilityEnabled() },
                  "Editable contours and nodes must expose AXEnabled for VoiceOver press actions")
        try check(nodes[0].accessibilityPerformPress() && accessibilityEditor.selection==[glyph.strokes[0].vectorPaths![0].nodes[0].id] && !accessibilityEditor.objectSelection,"Accessible node selection did not enter node mode")
        let beforeNudge=accessibilityEditor.paths[0].nodes[0].point.x
        let moveRight=nodes[0].accessibilityCustomActions()?.first { $0.name == "Move node right one unit" }
        try check(moveRight?.handler?() == true && accessibilityEditor.paths[0].nodes[0].point.x>beforeNudge,"Accessible node movement did not edit the glyph")
        try check(contours[1].accessibilityPerformPress() && accessibilityEditor.objectSelection && accessibilityEditor.selection.count==8,"Accessible contour selection did not select the shape")

        try check(glyph.isValid && glyph.hasArtwork,"Cubic glyph is not valid artwork.")
        let decoded=try JSONDecoder().decode(FontLabGlyph.self,from:JSONEncoder().encode(glyph))
        try check(decoded==glyph,"Cubic handles or node identities did not persist.")
        let old=Data("{\"character\":\"A\",\"strokes\":[],\"leftSideBearing\":0.08,\"rightSideBearing\":0.08}".utf8)
        let legacy=try JSONDecoder().decode(FontLabGlyph.self,from:old)
        try check(legacy.isValid,"Legacy glyph decoding broke.")
        var split=glyph.strokes[0].vectorPaths![0]
        let original=split.controls(0);split.insertNode(segment:0,t:0.37)
        for i in 0...100 {
            let t=Double(i)/100,p=FontLabVectorMath.evaluate(original,t)
            let q=t<=0.37 ? FontLabVectorMath.evaluate(split.controls(0),t/0.37):FontLabVectorMath.evaluate(split.controls(1),(t-0.37)/0.63)
            try check(hypot(p.x-q.x,p.y-q.y)<1e-10,"Adding a node changed the cubic shape.")
        }
        let reversed=split;split.reverse();split.reverse();try check(split==reversed,"Reversing twice changed cubic handles.")
        var project=FontLabProject(name:"Vector regression");project.glyphs["O"]=glyph
        let artifact=try FontLabTrueTypeExporter.artifact(for:project)
        let provider=CGDataProvider(data:artifact.data as CFData)!,font=CTFontCreateWithGraphicsFont(CGFont(provider)!,1000,nil,nil)
        var code:UniChar=79,gid=CGGlyph();CTFontGetGlyphsForCharacters(font,&code,&gid,1)
        let output=CTFontCreatePathForGlyph(font,gid,nil)!,bounds=output.boundingBoxOfPath
        try check(!output.contains(CGPoint(x:bounds.midX,y:bounds.midY)) && output.contains(CGPoint(x:bounds.minX+10,y:bounds.midY)),"Cubic TrueType export lost its counter or outer stroke.")
        try check(abs(bounds.width-496)<2 && abs(bounds.height-600)<2,"Cubic export distorted glyph proportions.")
        let svg=FontLabSVGExporter.string(projectName:project.name,glyph:glyph,metrics:metrics)
        try check(svg.contains(" C") && svg.contains("nonzero"),"SVG flattened editable cubic paths.")
        var renamed=glyph
        renamed.strokes[0].id=UUID()
        for p in renamed.strokes[0].vectorPaths!.indices {
            renamed.strokes[0].vectorPaths![p].id=UUID()
            for n in renamed.strokes[0].vectorPaths![p].nodes.indices {renamed.strokes[0].vectorPaths![p].nodes[n].id=UUID()}
        }
        project.glyphs["O"]=renamed
        let same=try FontLabTrueTypeExporter.artifact(for:project)
        try check(artifact.data==same.data,"UI-only vector identities changed font export identity.")
        renamed.strokes[0].vectorPaths![0].nodes[0].outgoing!.y += 0.02;project.glyphs["O"]=renamed
        let changed=try FontLabTrueTypeExporter.artifact(for:project)
        try check(artifact.postScriptName != changed.postScriptName,"Changing a curve handle reused the old font identity.")
        renamed.strokes[0].vectorPaths![0].closed=false;project.glyphs["O"]=renamed
        do {_=try FontLabTrueTypeExporter.artifact(for:project);throw FontLabStore.SelfTestError.failed("Font export silently filled an open path.")}
        catch FontLabTrueTypeExporter.ExportError.openContours { }
        let editor=FontLabVectorEditor(glyph:glyph,metrics:metrics)
        editor.selectAll();var commits=0;editor.onCommit={_ in commits+=1}
        editor.move(dx:0.01,dy:0.01)
        try check(commits==1 && abs(editor.paths[0].nodes[0].point.x-0.91)<1e-10,"Selected node movement or transaction count failed.")
        let moved=editor.glyph;editor.transform(scaleX:-1);editor.transform(scaleX:-1)
        for (a,b) in zip(FontLabVectorMath.paths(in:moved).flatMap(\.nodes),editor.paths.flatMap(\.nodes)) {
            try check(hypot(a.point.x-b.point.x,a.point.y-b.point.y)<1e-10,"Mirroring distorted the outline.")
        }
        editor.move(dx:10,dy:0);try check(editor.glyph.isValid && commits==3,"Out-of-bounds transforms were committed.")
        editor.pathCommand("open");try check(editor.openCount==2,"Opening selected contours failed.")
        editor.pathCommand("close");try check(editor.openCount==0,"Closing selected contours failed.")
        editor.selection=Set(editor.paths[1].nodes.map(\.id));editor.deleteSelection()
        try check(editor.paths.count==1,"Deleting a selected contour left debris.")
        let before=editor.glyph;editor.selection=[editor.paths[0].nodes[0].id];editor.smooth(false)
        try check(!editor.paths[0].nodes[0].smooth && editor.paths[0].nodes[0].outgoing != nil,"Corner conversion lost handles.")
        editor.receive(before);try check(editor.glyph==before,"Undo snapshot restoration failed.")
        var invalid=glyph;invalid.strokes[0].vectorPaths![0].nodes[0].incoming!.x = .infinity
        try check(!invalid.isValid,"Non-finite curve controls were accepted.")
        let polygon=FontLabGlyph(character:"A",strokes:[FontLabStroke(contours:[[.init(x:0.1,y:0.2),.init(x:0.5,y:0.8),.init(x:0.9,y:0.2)]])])
        try check(FontLabVectorMath.paths(in:polygon)==FontLabVectorMath.paths(in:polygon),"Imported node identities are unstable across redraws.")
        let converted=FontLabVectorMath.replacingPaths(in:polygon,with:FontLabVectorMath.paths(in:polygon))
        try check(converted.isValid && converted.strokes[0].contours==nil && converted.strokes[0].vectorPaths![0].nodes.map(\.point)==polygon.strokes[0].contours![0],"Imported contour editing changed the original polygon.")
        let shapes=FontLabVectorEditor(glyph:FontLabGlyph(character:"B"),metrics:metrics)
        let left=FontLabVectorMath.rectangle(CGRect(x:0.1,y:0.2,width:0.5,height:0.5),ellipse:false)
        let right=FontLabVectorMath.rectangle(CGRect(x:0.4,y:0.3,width:0.4,height:0.5),ellipse:false)
        _=shapes.apply([left,right]);shapes.selectAll();shapes.boolean("overlap")
        try check(shapes.paths.count==1 && shapes.paths[0].cgPath.contains(CGPoint(x:500,y:500)),"Removing overlaps failed.")
        _=shapes.apply([left,right]);shapes.selectAll();shapes.boolean("subtract")
        let sub=CGMutablePath();shapes.paths.forEach {sub.addPath($0.cgPath)}
        try check(sub.contains(CGPoint(x:200,y:400)) && !sub.contains(CGPoint(x:500,y:500)),"Contour subtraction failed.")
        _=shapes.apply([left,right]);shapes.selectAll();shapes.boolean("intersect")
        let intersection=CGMutablePath();shapes.paths.forEach {intersection.addPath($0.cgPath)}
        try check(intersection.contains(CGPoint(x:500,y:500)) && !intersection.contains(CGPoint(x:200,y:400)),"Contour intersection failed.")
        let ring=FontLabVectorEditor(glyph:glyph,metrics:metrics);ring.selectAll();ring.boolean("overlap")
        let combined=CGMutablePath();ring.paths.forEach {combined.addPath($0.cgPath)}
        try check(!combined.contains(CGPoint(x:500,y:480)) && combined.contains(CGPoint(x:120,y:480)),"Overlap cleanup filled a counter.")
        var wrong=FontLabVectorChecks.fixture();wrong.strokes[0].vectorPaths![1].reverse()
        let counter=FontLabVectorEditor(glyph:wrong,metrics:metrics);counter.selection=Set(counter.paths[1].nodes.map(\.id));counter.pathCommand("counter")
        let correct=CGMutablePath();counter.paths.forEach {correct.addPath($0.cgPath)}
        try check(!correct.contains(CGPoint(x:500,y:480)),"Make counter failed to match the parent winding.")
        let lens=CGMutablePath()
        lens.move(to:CGPoint(x:200,y:500))
        lens.addCurve(to:CGPoint(x:800,y:500),control1:CGPoint(x:300,y:900),control2:CGPoint(x:700,y:900))
        lens.addCurve(to:CGPoint(x:200,y:500),control1:CGPoint(x:700,y:100),control2:CGPoint(x:300,y:100))
        lens.closeSubpath()
        let compact=FontLabVectorPath.from(lens)
        try check(compact.count==1 && compact[0].isValid,"A closed two-anchor cubic was discarded.")
        for x in stride(from:100.0,through:900.0,by:23) {for y in stride(from:100.0,through:900.0,by:23) {
            let p=CGPoint(x:x,y:y);try check(lens.contains(p)==compact[0].cgPath.contains(p),"Compact curve conversion changed its shape.")
        }}
        let extreme=FontLabVectorEditor(glyph:glyph,metrics:metrics);extreme.selection=Set(extreme.paths[0].nodes.map(\.id));extreme.transform(angle:0.3)
        let curveBefore=extreme.paths[0].cgPath;extreme.addExtrema();let curveAfter=extreme.paths[0].cgPath
        try check(extreme.paths[0].nodes.count>4,"Extrema insertion did not find rotated curve extremes.")
        for x in stride(from:100.0,through:900.0,by:23) {for y in stride(from:180.0,through:780.0,by:23) {
            let p=CGPoint(x:x,y:y);try check(curveBefore.contains(p)==curveAfter.contains(p),"Extrema insertion changed filled geometry.")
        }}
        print("PASS: cubic split/reversal, vector persistence/legacy decoding, node transactions, transforms, contour editing, exact SVG curves and TrueType counter/identity fidelity.")
    }
}

/// Exercise the visible filled result as well as the editable overlay. A moved
/// control point alone is not evidence that the letter being shown changed.
private enum FontLabDirectCurveChecks {
    static func run() throws {
        func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
            if !condition() { throw FontLabStore.SelfTestError.failed(message) }
        }
        func close(_ a: Double, _ b: Double) -> Bool { abs(a-b)<1e-8 }
        func glyph(_ paths: [FontLabVectorPath]) -> FontLabGlyph {
            FontLabGlyph(character:"A",strokes:[FontLabStroke(vectorPaths:paths)],contourDesignWidth:0.62)
        }
        func canvas(_ glyph: FontLabGlyph) -> FontLabVectorNSView {
            let editor=FontLabVectorEditor(glyph:glyph,metrics:FontLabMetrics())
            editor.snap=false;editor.grid=false
            editor.inkColor = .init(nsColor:NSColor(deviceRed:1,green:0,blue:0,alpha:1))
            let canvas=FontLabVectorNSView(editor:editor);canvas.frame=CGRect(x:0,y:0,width:600,height:600)
            return canvas
        }
        func screen(_ p: FontLabPoint, _ canvas: FontLabVectorNSView) -> CGPoint {
            let r=canvas.designRect;return CGPoint(x:r.minX+p.x*r.width,y:r.minY+p.y*r.height)
        }
        func pointer(_ type: NSEvent.EventType, _ point: CGPoint, modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
            NSEvent.mouseEvent(with:type,location:point,modifierFlags:modifiers,timestamp:0,windowNumber:0,
                              context:nil,eventNumber:0,clickCount:1,pressure:1)!
        }
        func beginDrag(_ canvas: FontLabVectorNSView, _ a: FontLabPoint, _ b: FontLabPoint,
                       modifiers: NSEvent.ModifierFlags = []) {
            canvas.mouseDown(with:pointer(.leftMouseDown,screen(a,canvas)))
            canvas.mouseDragged(with:pointer(.leftMouseDragged,screen(b,canvas),modifiers:modifiers))
        }
        func release(_ canvas: FontLabVectorNSView) {canvas.mouseUp(with:pointer(.leftMouseUp,.zero))}
        func key(_ letter: String, code: UInt16) -> NSEvent {
            NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:0,context:nil,
                            characters:letter,charactersIgnoringModifiers:letter,isARepeat:false,keyCode:code)!
        }
        func render(_ canvas: FontLabVectorNSView, pureFill: Bool = false) -> NSBitmapImageRep {
            let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:600,pixelsHigh:600,bitsPerSample:8,
                                       samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,
                                       bytesPerRow:0,bitsPerPixel:0)!
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:bitmap)
            if pureFill {
                NSColor.white.setFill();canvas.bounds.fill()
                let strokes=canvas.editor.glyph.strokes.compactMap { stroke -> FontLabStroke? in
                    guard let paths=stroke.vectorPaths else { return stroke.contours != nil ? stroke:nil }
                    var value=stroke;value.vectorPaths=paths.filter(\.closed);return value
                }
                fontLabDrawStrokes(strokes,in:canvas.designRect,color:NSColor(deviceRed:1,green:0,blue:0,alpha:1))
            } else {canvas.draw(canvas.bounds)}
            NSGraphicsContext.restoreGraphicsState()
            return bitmap
        }
        func redMask(_ bitmap: NSBitmapImageRep) -> [Bool] {
            let bytes=bitmap.bitmapData!,stride=bitmap.bytesPerRow
            return (0..<600*600).map { i in
                let p=i/600*stride+i%600*4
                return bytes[p]>230 && bytes[p+1]<50 && bytes[p+2]<50
            }
        }
        func verifyFillChange(beforeView:[Bool],beforeFill:[Bool],afterView:[Bool],afterFill:[Bool],label:String) throws {
            var interiorChanges=0,visibleMatches=0
            for y in 3..<597 {for x in 3..<597 {
                let i=y*600+x
                guard beforeFill[i] != afterFill[i] else {continue}
                // Exclude anti-aliased boundaries; control overlays may still
                // cross a few samples, so require broad agreement, not exact pixels.
                let neighbors=[i-2,i+2,i-1200,i+1200]
                guard neighbors.allSatisfy({beforeFill[$0]==beforeFill[i] && afterFill[$0]==afterFill[i]}) else {continue}
                interiorChanges += 1
                if beforeView[i]==beforeFill[i] && afterView[i]==afterFill[i] {visibleMatches += 1}
            }}
            try check(interiorChanges>80 && Double(visibleMatches)/Double(interiorChanges)>0.85,
                      "\(label): visible solid fill did not follow the edited closed outline")
            print("BITMAP: \(label), \(interiorChanges) changed interior pixels, \(visibleMatches) visibly matched")
        }

        // A disposable dense polygon A exercises the actual simplify/import
        // representation transition; no private user glyph is compiled in.
        let outer:[FontLabPoint]=[.init(x:0.14,y:0.12),.init(x:0.42,y:0.88),.init(x:0.58,y:0.88),.init(x:0.86,y:0.12),
                                  .init(x:0.69,y:0.12),.init(x:0.62,y:0.33),.init(x:0.38,y:0.33),.init(x:0.31,y:0.12)]
        let counter:[FontLabPoint]=[.init(x:0.435,y:0.5),.init(x:0.565,y:0.5),.init(x:0.5,y:0.72)]
        func dense(_ ring:[FontLabPoint], samples:Int)->[FontLabPoint] {
            ring.indices.flatMap { index in (0..<samples).map {FontLabVectorMath.mix(ring[index],ring[(index+1)%ring.count],Double($0)/Double(samples))} }
        }
        let imported=FontLabGlyph(character:"A",strokes:[FontLabStroke(contours:[dense(outer,samples:80),dense(counter,samples:48)])],contourDesignWidth:0.62)
        let simplified=try FontLabTraceSmoothing.fit(imported,units:5)
        let simplifiedPaths=FontLabVectorMath.paths(in:simplified)
        try check(simplifiedPaths.flatMap(\.nodes).count<100 && simplifiedPaths.count==2,
                  "The dense A fixture must simplify to editable closed outlines with a counter")
        let anchorCanvas=canvas(simplified)
        try check(!anchorCanvas.editor.objectSelection && anchorCanvas.editor.tool == .select,
                  "A new letterform session must default to direct node editing")
        let originalAnchor=anchorCanvas.editor.paths[0].nodes[0]
        let beforeView=redMask(render(anchorCanvas)),beforeFill=redMask(render(anchorCanvas,pureFill:true))
        var anchorCommits=0;anchorCanvas.editor.onCommit={_ in anchorCommits += 1}
        beginDrag(anchorCanvas,originalAnchor.point,.init(x:originalAnchor.point.x+0.10,y:originalAnchor.point.y+0.09))
        try check(anchorCommits==0 && anchorCanvas.editor.paths[0].nodes[0].point != originalAnchor.point,
                  "Dragging a simplified A anchor must edit the live outline before mouse-up")
        try verifyFillChange(beforeView:beforeView,beforeFill:beforeFill,afterView:redMask(render(anchorCanvas)),
                             afterFill:redMask(render(anchorCanvas,pureFill:true)),label:"simplified A anchor drag")
        anchorCanvas.cancelOperation(nil);release(anchorCanvas)
        try check(anchorCanvas.editor.glyph==simplified && redMask(render(anchorCanvas,pureFill:true))==beforeFill && anchorCommits==0,
                  "Cancelling a simplified anchor edit must restore its filled bitmap without a commit")

        let handleCanvas=canvas(simplified)
        let r=handleCanvas.designRect
        let angularPath=handleCanvas.editor.paths[0]
        let straightSegments=(0..<angularPath.segmentCount).filter {!angularPath.isCurve($0)}
        func segmentLength(_ index:Int)->Double {
            let a=angularPath.nodes[index].point,b=angularPath.nodes[(index+1)%angularPath.nodes.count].point
            return hypot((b.x-a.x)*r.width,(b.y-a.y)*r.height)
        }
        guard let nodeIndex=straightSegments.max(by:{segmentLength($0)<segmentLength($1)}) else {
            throw FontLabStore.SelfTestError.failed("The angular A fixture must expose a straight leg for Add curve handles")
        }
        let nextIndex=(nodeIndex+1)%angularPath.nodes.count
        handleCanvas.editor.selection=[angularPath.nodes[nodeIndex].id,angularPath.nodes[nextIndex].id]
        try check(handleCanvas.editor.canCurveSegments,"Selecting an A leg must enable Add curve handles")
        handleCanvas.editor.curves()
        guard let handle=handleCanvas.editor.paths[0].nodes[nodeIndex].outgoing else {
            throw FontLabStore.SelfTestError.failed("Add curve handles did not create the selected A leg's outgoing control")
        }
        try check(handleCanvas.editor.paths.flatMap(\.nodes).allSatisfy {hypot(($0.point.x-handle.x)*r.width,($0.point.y-handle.y)*r.height)>12},
                  "The added A leg handle must be separated from every anchor for an unambiguous pointer test")
        handleCanvas.editor.selection=[angularPath.nodes[nodeIndex].id]
        var handleCommits=0;handleCanvas.editor.onCommit={_ in handleCommits += 1}
        let handleBeforeView=redMask(render(handleCanvas)),handleBeforeFill=redMask(render(handleCanvas,pureFill:true))
        let legStart=angularPath.nodes[nodeIndex].point,legEnd=angularPath.nodes[nextIndex].point,length=segmentLength(nodeIndex)
        let handleTarget=FontLabPoint(x:handle.x-(legEnd.y-legStart.y)*r.height/length*60/r.width,
                                      y:handle.y+(legEnd.x-legStart.x)*r.width/length*60/r.height)
        beginDrag(handleCanvas,handle,handleTarget)
        try check(handleCanvas.editor.paths[0].nodes[nodeIndex].point==angularPath.nodes[nodeIndex].point && handleCommits==0,
                  "Dragging an A curve handle must keep its anchor fixed and preview before committing")
        try verifyFillChange(beforeView:handleBeforeView,beforeFill:handleBeforeFill,afterView:redMask(render(handleCanvas)),
                             afterFill:redMask(render(handleCanvas,pureFill:true)),label:"simplified A handle drag")
        release(handleCanvas)
        try check(handleCommits==1,"Dragging an added A curve handle must commit exactly once")

        var shortHandle=FontLabVectorMath.rectangle(CGRect(x:0.2,y:0.2,width:0.6,height:0.6),ellipse:false)
        shortHandle.nodes[0].outgoing = .init(x:0.205,y:0.2)
        for grabHandle in [false,true] {
            let hit=canvas(glyph([shortHandle]));hit.editor.selection=[shortHandle.nodes[0].id]
            let a=grabHandle ? shortHandle.nodes[0].outgoing!:shortHandle.nodes[0].point
            beginDrag(hit,a,.init(x:a.x+0.08,y:a.y+0.06));release(hit)
            try check(grabHandle ? hit.editor.paths[0].nodes[0].point==shortHandle.nodes[0].point : hit.editor.paths[0].nodes[0].point != shortHandle.nodes[0].point,
                      "The nearer anchor or short handle must receive the drag; handles cannot steal an anchor-center click")
        }
        let pen=canvas(simplified);pen.editor.tool = .pen
        beginDrag(pen,originalAnchor.point,.init(x:originalAnchor.point.x+0.05,y:originalAnchor.point.y+0.04));release(pen)
        try check(pen.editor.paths.count==2 && pen.editor.paths.allSatisfy(\.closed) && pen.editor.paths[0].nodes[0].point != originalAnchor.point,
                  "Bézier on an existing closed anchor must edit it instead of creating an open overlay")
        let coincident=FontLabVectorPath(nodes:[.init(point:originalAnchor.point),.init(point:.init(x:0.35,y:0.4))])
        for penMode in [false,true] {
            let shared=canvas(glyph(simplifiedPaths+[coincident]));shared.editor.selectContours(closed:true)
            if penMode {shared.editor.tool = .pen}
            beginDrag(shared,originalAnchor.point,.init(x:originalAnchor.point.x+0.04,y:originalAnchor.point.y+0.04));release(shared)
            try check(shared.editor.paths.count==3 && shared.editor.paths[2]==coincident && shared.editor.paths[0].nodes[0].point != originalAnchor.point,
                      "A selected closed anchor must win a hit tie against an unselected coincident open overlay")
        }
        var open=FontLabVectorPath(nodes:[.init(point:.init(x:0.1,y:0.1)),.init(point:.init(x:0.15,y:0.2))])
        let activePen=canvas(glyph(simplifiedPaths+[open]));activePen.editor.tool = .pen;activePen.editor.activePath=open.id
        beginDrag(activePen,originalAnchor.point,.init(x:originalAnchor.point.x+0.04,y:originalAnchor.point.y+0.03));release(activePen)
        try check(activePen.editor.paths.count==3 && activePen.editor.paths[2]==open,
                  "Clicking a closed anchor must not extend a different active open contour")
        open.nodes=[.init(point:originalAnchor.point),.init(point:.init(x:0.2,y:0.4)),.init(point:.init(x:0.3,y:0.5))]
        let closing=canvas(glyph(simplifiedPaths+[open]));closing.editor.tool = .pen;closing.editor.activePath=open.id
        closing.mouseDown(with:pointer(.leftMouseDown,screen(originalAnchor.point,closing)));release(closing)
        try check(closing.editor.paths[2].closed && closing.editor.paths[0]==simplifiedPaths[0],
                  "Closing the active Bézier contour must take priority over a coincident existing closed anchor")

        let openPath=FontLabVectorPath(nodes:[
            .init(point:.init(x:0.2,y:0.2),incoming:.init(x:0.1,y:0.7),outgoing:.init(x:0.4,y:0.2)),
            .init(point:.init(x:0.8,y:0.6),incoming:.init(x:0.6,y:0.6),outgoing:.init(x:0.9,y:0.9))])
        let inactive=canvas(glyph([openPath]));inactive.editor.selectAll()
        let originalOpen=inactive.editor.glyph,openImage=render(inactive).representation(using:.png,properties:[:])!
        var changedInactive=openPath;changedInactive.nodes[0].incoming = .init(x:0.8,y:0.9);changedInactive.nodes[1].outgoing = .init(x:0.1,y:0.8)
        inactive.editor.receive(glyph([changedInactive]))
        try check(render(inactive).representation(using:.png,properties:[:])==openImage,
                  "Unused open-end handles must not be drawn as editable curve controls")
        inactive.editor.receive(originalOpen)
        beginDrag(inactive,.init(x:0.1,y:0.7),.init(x:0.15,y:0.75));release(inactive)
        try check(inactive.editor.glyph==originalOpen,"An unused incoming handle on an open endpoint must not capture pointer edits")

        let rectangle=FontLabVectorMath.rectangle(CGRect(x:0.2,y:0.2,width:0.6,height:0.6),ellipse:false)
        let segment=canvas(glyph([rectangle]));var segmentCommits=0;segment.editor.onCommit={_ in segmentCommits += 1}
        beginDrag(segment,.init(x:0.5,y:0.2),.init(x:0.5,y:0.32))
        let bent=segment.editor.paths[0]
        try check(bent.nodes.map(\.point)==rectangle.nodes.map(\.point) && close(FontLabVectorMath.evaluate(bent.controls(0),0.5).y,0.32),
                  "Dragging a straight edge must bend its cubic at the pointer while both endpoints stay fixed")
        release(segment)
        try check(segmentCommits==1,"A direct segment drag must commit exactly once")
        let bounded=canvas(glyph([rectangle]));let boundedOriginal=bounded.editor.glyph
        beginDrag(bounded,.init(x:0.5,y:0.2),.init(x:0.5,y:0.3))
        let lastValid=bounded.editor.glyph
        bounded.mouseDragged(with:pointer(.leftMouseDragged,screen(.init(x:10,y:10),bounded)))
        try check(bounded.editor.glyph==lastValid && bounded.editor.glyph.isValid,
                  "An out-of-range edge drag must retain the last valid preview")
        bounded.cancelOperation(nil);release(bounded)
        try check(bounded.editor.glyph==boundedOriginal,"Escape after a rejected edge position must restore the original contour")
        let noMove=canvas(glyph([rectangle]));let noMoveBefore=noMove.editor.glyph
        var noMoveCommits=0;noMove.editor.onCommit={_ in noMoveCommits += 1}
        let edge=screen(.init(x:0.5,y:0.2),noMove)
        noMove.mouseDown(with:pointer(.leftMouseDown,edge));noMove.mouseDragged(with:pointer(.leftMouseDragged,CGPoint(x:edge.x+1,y:edge.y+1)));release(noMove)
        try check(noMove.editor.glyph==noMoveBefore && noMoveCommits==0,
                  "Click jitter must not convert a straight edge into a curve or create an edit")
        let ellipse=FontLabVectorMath.rectangle(CGRect(x:0.2,y:0.2,width:0.6,height:0.6),ellipse:true)
        for option in [false,true] {
            let curve=canvas(glyph([ellipse])),target=FontLabVectorMath.evaluate(ellipse.controls(0),0.31)
            guard let hit=curve.hitSegment(screen(target,curve)) else {throw FontLabStore.SelfTestError.failed("Could not hit a cubic interior")}
            let expected=FontLabVectorMath.evaluate(ellipse.controls(0),hit.2)
            beginDrag(curve,target,.init(x:target.x+0.03,y:target.y+0.05),modifiers:option ? .option:[])
            let result=curve.editor.paths[0],point=FontLabVectorMath.evaluate(result.controls(0),hit.2)
            try check(result.nodes.map(\.point)==ellipse.nodes.map(\.point) && close(point.x-expected.x,0.03) && close(point.y-expected.y,0.05),
                      "Cubic segment deformation must follow the pointer without moving endpoints")
            if option {
                try check(!result.nodes[0].smooth && !result.nodes[1].smooth && result.nodes[0].incoming==ellipse.nodes[0].incoming && result.nodes[1].outgoing==ellipse.nodes[1].outgoing,
                          "Option edge drag must break endpoint smooth coupling without moving the opposite handles")
            } else {
                for index in [0,1] {
                    let n=result.nodes[index],a=n.incoming!,b=n.outgoing!,w=curve.editor.glyph.resolvedDesignWidth
                    try check(abs((a.x-n.point.x)*(b.y-n.point.y)-(a.y-n.point.y)*(b.x-n.point.x))<1e-8 && n.smooth,
                              "Normal edge drag must keep smooth endpoint handles collinear")
                    let old=index==0 ? ellipse.nodes[index].incoming!:ellipse.nodes[index].outgoing!,now=index==0 ? a:b
                    try check(close(hypot((old.x-n.point.x)*w,old.y-n.point.y),hypot((now.x-n.point.x)*w,now.y-n.point.y)),
                              "Smooth edge drag must preserve the opposite handle's physical length")
                }
            }
            curve.cancelOperation(nil);release(curve)
            try check(curve.editor.paths==[ellipse],"Cancelling an edge drag must restore every cubic handle")
        }

        let selected=canvas(glyph(simplifiedPaths+[openPath]))
        selected.editor.selectContours(closed:false)
        try check(selected.editor.selection==Set(openPath.nodes.map(\.id)) && !selected.editor.objectSelection,"Open-path selection must isolate the unfilled overlays")
        selected.editor.selectContours(closed:true)
        try check(selected.editor.selection==Set(simplifiedPaths.flatMap(\.nodes).map(\.id)),"Filled-outline selection must exclude open overlays")
        selected.editor.selectContour(openPath.id)
        try check(selected.editor.selection==Set(openPath.nodes.map(\.id)),"Contour manager selection must target exactly the requested path")
        selected.editor.selection=[simplifiedPaths[0].nodes[0].id]
        let partialGlyph=selected.editor.glyph
        try check(selected.editor.selectedContourIDs.isEmpty,"A partial node selection must not count as a selected contour")
        selected.editor.deleteSelectedContours()
        try check(selected.editor.glyph==partialGlyph,"Contour deletion must not remove a path for a partial node selection")
        selected.editor.selectContour(openPath.id)
        try check(!selected.editor.canCloseSelectedContours,"A two-node open path cannot become a valid closed contour")
        var toggleCommits=0;selected.editor.onCommit={_ in toggleCommits += 1};let toggleGlyph=selected.editor.glyph
        selected.editor.objectSelection=true;selected.editor.tool = .hand
        selected.keyDown(with:key("a",code:0));selected.keyDown(with:key("f",code:3))
        try check(!selected.editor.objectSelection && selected.editor.tool == .select && !selected.editor.fill &&
                  selected.editor.glyph==toggleGlyph && toggleCommits==0,"A/F shortcuts must select direct editing and toggle preview fill without editing the glyph")
        let penStroke=FontLabStroke(points:[.init(x:0.2,y:0.45),.init(x:0.8,y:0.45)],width:0.15)
        let penPreview=canvas(FontLabGlyph(character:"A",strokes:[penStroke],contourDesignWidth:0.62))
        let solidPen=redMask(render(penPreview)).filter {$0}.count
        penPreview.keyDown(with:key("f",code:3))
        try check(solidPen>1000 && redMask(render(penPreview)).allSatisfy {!$0} && penPreview.editor.glyph.strokes==[penStroke],
                  "Fill off must show a pen centerline instead of leaving solid stroke ink visible")
        let componentPreview=canvas(FontLabGlyph(character:"A",contourDesignWidth:0.62))
        componentPreview.editor.componentStrokes=[FontLabStroke(vectorPaths:[rectangle])]
        let componentPoint=screen(.init(x:0.5,y:0.45),componentPreview)
        let componentFill=render(componentPreview).colorAt(x:Int(componentPoint.x),y:Int(componentPoint.y))!.usingColorSpace(.deviceRGB)!
        componentPreview.keyDown(with:key("f",code:3))
        let componentOutline=render(componentPreview).colorAt(x:Int(componentPoint.x),y:Int(componentPoint.y))!.usingColorSpace(.deviceRGB)!
        try check(abs(componentFill.redComponent-componentOutline.redComponent)+abs(componentFill.greenComponent-componentOutline.greenComponent)>0.1,
                  "Fill off must remove linked-component interior ink while retaining its outline")

        var project=FontLabDesignChecks.fixture()
        project.glyphs["A"]=simplified
        let proof=canvas(simplified);let proofBefore=proof.editor.proofGlyphs(in:project)
        beginDrag(proof,originalAnchor.point,.init(x:originalAnchor.point.x+0.03,y:originalAnchor.point.y+0.02))
        let preview=proof.editor.proofGlyphs(in:project)
        try check(preview["A"]==proof.editor.glyph && preview["B"] != proofBefore["B"] && project.glyphs["A"]==simplified,
                  "Live word proof must show the uncommitted outline and linked components without mutating the saved project")
        proof.cancelOperation(nil);release(proof)
        try check(proof.editor.proofGlyphs(in:project)==proofBefore,"Cancelling a drag must restore the original linked live proof")
        let warningSession=FontLabEditorSession()
        let warningProject=FontLabProject(id:project.id,characters:["A","G"])
        var warningState=FontLabState(projects:[warningProject],selectedProject:project.id)
        warningState.projects[0].glyphs["A"]=glyph(simplifiedPaths+[openPath])
        let warning=warningSession.warnAboutOpenContours(["A","G"],projectID:project.id)
        let refreshed=warningSession.refreshedOpenContourWarning(in:warningState,currentError:warning)!
        try check(refreshed.contains("in A before") && !refreshed.contains("A, G"),"Preflight warning must update as open paths are repaired")
        warningState.selectedProject=nil
        try check(warningSession.refreshedOpenContourWarning(in:warningState,currentError:refreshed)==refreshed,
                  "A valid project without an explicit selected ID must keep its open-path warning")
        warningState.projects[0].glyphs["A"]=simplified
        try check(warningSession.refreshedOpenContourWarning(in:warningState,currentError:refreshed)=="","Repairing the last open path must clear its preflight warning")
        _=warningSession.warnAboutOpenContours(["A"],projectID:project.id)
        try check(warningSession.refreshedOpenContourWarning(in:warningState,currentError:"The project could not be saved.")==nil,
                  "Refreshing export preflight must never clear a persistence error")
        print("PASS: direct curve editing, visible simplified-A fill, nearest handles, Pen anchor editing, open-path controls, preview shortcuts and live component proof")
    }

}
