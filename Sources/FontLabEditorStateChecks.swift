import AppKit

enum FontLabEditorStateChecks {
    static func run() throws {
        func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
            if !condition() { throw FontLabStore.SelfTestError.failed(message) }
        }

        let source = FontLabVectorMath.rectangle(CGRect(x: 0.1, y: 0.3, width: 0.35, height: 0.35), ellipse: true)
        let clipboard = FontLabVectorClipboard(designWidth: 1.2, baseline: 0.22, paths: [source])
        let data = try JSONEncoder().encode(clipboard)
        var metrics = FontLabMetrics(); metrics.setBaseline(0.3)
        let destination = FontLabGlyph(character: "N", leftSideBearing: 0.03, rightSideBearing: 0.12, contourDesignWidth: 0.62)
        let editor = FontLabVectorEditor(glyph: destination, metrics: metrics)
        var commits = 0; editor.onCommit = { _ in commits += 1 }
        editor.pastePaths(data: data)
        try check(commits == 1 && editor.paths.count == 1 && editor.glyph.isValid,
                  "Pasting contours into another design width must make one valid edit")
        try check(editor.glyph.leftSideBearing == destination.leftSideBearing && editor.glyph.rightSideBearing == destination.rightSideBearing,
                  "Pasting artwork must preserve destination side bearings")
        for (before, after) in zip(source.nodes, editor.paths[0].nodes) {
            try check(before.id != after.id, "Pasted nodes must receive independent editing identities")
            for (a, b) in zip([before.point, before.incoming!, before.outgoing!], [after.point, after.incoming!, after.outgoing!]) {
                try check(abs(a.x * clipboard.designWidth - b.x * destination.resolvedDesignWidth) < 1e-10 &&
                          abs((a.y - clipboard.baseline) - (b.y - metrics.baseline)) < 1e-10,
                          "Clipboard transfer distorted physical outline size, handles or baseline position")
            }
        }
        let firstIDs = Set(editor.paths[0].nodes.map(\.id))
        editor.pastePaths(data: data)
        try check(commits == 2 && editor.paths.count == 2 && firstIDs.isDisjoint(with: editor.selection),
                  "Repeated paste must create an independent, selected copy")
        let saved = editor.glyph, selection = editor.selection
        editor.pastePaths(data: Data("invalid clipboard".utf8))
        var unknown = clipboard; unknown.version = 9
        editor.pastePaths(data: try JSONEncoder().encode(unknown))
        try check(commits == 2 && editor.glyph == saved && editor.selection == selection,
                  "Invalid or unsupported clipboard data must preserve artwork, selection and history")

        let narrow = FontLabVectorEditor(glyph: FontLabGlyph(character: "I", contourDesignWidth: 0.2), metrics: metrics)
        var narrowCommits = 0; narrow.onCommit = { _ in narrowCommits += 1 }
        narrow.pastePaths(data: data)
        try check(narrow.paths.isEmpty && narrowCommits == 0 && narrow.message.contains("do not fit"),
                  "Oversize pasted artwork must report rejection without squeezing or clipping the contours")
        let legacy = FontLabVectorEditor(glyph: destination, metrics: metrics)
        legacy.pastePaths(data: try JSONEncoder().encode([source]))
        try check(legacy.paths.count == 1 && legacy.paths[0].nodes.map(\.point) == source.nodes.map(\.point),
                  "Contours copied by older Typefield versions must retain their legacy coordinate behavior")
        let mappedBack = FontLabVectorClipboard(designWidth: destination.resolvedDesignWidth, baseline: metrics.baseline, paths: [editor.paths[0]])
            .mapped(toWidth: clipboard.designWidth, baseline: clipboard.baseline)
        try check(mappedBack?.first?.nodes.count == source.nodes.count,
                  "Clipboard conversion must round-trip every anchor")
        for (before, after) in zip(source.nodes, mappedBack![0].nodes) {
            try check(hypot(before.point.x - after.point.x, before.point.y - after.point.y) < 1e-10,
                      "Clipboard coordinate round trip moved the original artwork")
        }
        let edgePath=FontLabVectorPath(nodes:[.init(point:.init(x:0.1/0.134,y:0.034),incoming:.init(x:-2*0.1/0.134,y:0.034),outgoing:.init(x:3*0.1/0.134,y:0.034))])
        let edgeClipboard=FontLabVectorClipboard(designWidth:0.134,baseline:0.134,paths:[edgePath])
        let exactFit=edgeClipboard.mapped(toWidth:0.1,baseline:0.1)
        try check(exactFit?.first?.nodes.first?.point == FontLabPoint(x:1,y:0) && exactFit!.allSatisfy(\.isValid),
                  "An exact physical clipboard fit must tolerate floating-point boundary rounding")
        var oversized=edgePath;oversized.nodes[0].point.x += 1e-7
        try check(FontLabVectorClipboard(designWidth:0.134,baseline:0.134,paths:[oversized]).mapped(toWidth:0.1,baseline:0.1) == nil,
                  "Clipboard boundary rounding must not clip genuinely out-of-bounds artwork")

        let pathEditor = FontLabVectorEditor(glyph: FontLabGlyph(character: "O", strokes: [FontLabStroke(vectorPaths: [source])]), metrics: metrics)
        pathEditor.selection = [source.nodes[0].id, source.nodes[2].id]
        try check(!pathEditor.canStraightenSegments && !pathEditor.canCurveSegments && !pathEditor.canInsertMidpoints,
                  "Segment operations must be unavailable for nonadjacent selected nodes")
        pathEditor.selection.insert(source.nodes[1].id)
        try check(pathEditor.canStraightenSegments && !pathEditor.canCurveSegments && pathEditor.canInsertMidpoints && pathEditor.canOpenContours && !pathEditor.canCloseContours,
                  "Path commands must reflect selected segment geometry and closed state")
        pathEditor.lines()
        try check(!pathEditor.canStraightenSegments && pathEditor.canCurveSegments,
                  "Straightening segments must update curve-command availability")
        pathEditor.pathCommand("open")
        try check(!pathEditor.canOpenContours && pathEditor.canCloseContours,
                  "Opening contours must update open/close availability")
        let shortPath = FontLabVectorPath(nodes: Array(source.nodes.prefix(2)))
        let shortEditor = FontLabVectorEditor(glyph: FontLabGlyph(character: "S", strokes: [FontLabStroke(vectorPaths: [shortPath])]), metrics: metrics)
        shortEditor.selectAll()
        try check(!shortEditor.canCloseContours, "Closing a two-node open path must be unavailable")

        pathEditor.selectAll()
        let valid = pathEditor.glyph, selected = pathEditor.selection
        var rejectedCommits = 0; pathEditor.onCommit = { _ in rejectedCommits += 1 }
        pathEditor.setCoordinate(.infinity, x: true)
        pathEditor.transform(scaleX: 0)
        pathEditor.transform(scaleY: .nan)
        pathEditor.transform(angle: .infinity)
        try check(pathEditor.glyph == valid && pathEditor.selection == selected && rejectedCommits == 0,
                  "Invalid numeric edits must not collapse artwork, alter selection or create history")
        pathEditor.setCoordinate(pathEditor.selectedBounds.minX * pathEditor.glyph.resolvedDesignWidth * 1000,x:true)
        try check(pathEditor.message == FontLabVectorEditor.defaultMessage && pathEditor.glyph == valid && rejectedCommits == 0,
                  "A valid unchanged coordinate must clear a stale rejection without creating history")
        pathEditor.transform(scaleX:0);pathEditor.transform(scaleX:1,scaleY:1)
        try check(pathEditor.message == FontLabVectorEditor.defaultMessage && pathEditor.glyph == valid && rejectedCommits == 0,
                  "A valid unchanged transform must clear a stale rejection without creating history")
        pathEditor.setCoordinate(.nan,x:true);pathEditor.move(dx:0.01,dy:0)
        try check(pathEditor.message == FontLabVectorEditor.defaultMessage && rejectedCommits == 1,
                  "An accepted geometry edit must clear its previous rejection hint")
        pathEditor.selectAll();pathEditor.insertMidpoints()
        try check(pathEditor.message.hasPrefix("Inserted "),"Operation-specific success feedback must remain visible after an accepted edit")

        let first = FontLabVectorMath.rectangle(CGRect(x:0.1,y:0.2,width:0.5,height:0.5),ellipse:false)
        var second = FontLabVectorMath.rectangle(CGRect(x:0.3,y:0.3,width:0.5,height:0.5),ellipse:false);second.reverse()
        let grouped = FontLabGlyph(character:"B",strokes:[FontLabStroke(vectorPaths:[first]),FontLabStroke(vectorPaths:[second])],contourDesignWidth:0.62)
        func paint(_ glyph: FontLabGlyph, _ point: CGPoint) -> Bool {
            glyph.strokes.contains { stroke in
                var source = glyph;source.strokes=[stroke]
                let compound=CGMutablePath();FontLabVectorMath.paths(in:source).forEach {compound.addPath($0.cgPath)}
                return compound.contains(point,using:.winding)
            }
        }
        let replaced=FontLabVectorMath.replacingPaths(in:grouped,with:FontLabVectorMath.paths(in:grouped))
        try check(replaced == grouped,"Converting editable paths must preserve original strokes, IDs and paint groups")
        let groupedEditor=FontLabVectorEditor(glyph:grouped,metrics:metrics)
        groupedEditor.selectAll();groupedEditor.move(dx:0.02,dy:0)
        try check(groupedEditor.glyph.strokes.count == 2,"Moving separate outline strokes must not merge their winding groups")
        for x in 0..<96 { for y in 0..<100 {
            let point=CGPoint(x:Double(x)*10+5,y:Double(y)*10+5)
            try check(paint(grouped,point) == paint(groupedEditor.glyph,CGPoint(x:point.x+20,y:point.y)),
                      "Routine node movement changed the union of independently painted stroke groups")
        } }
        let compound=CGMutablePath();compound.addPath(first.cgPath);compound.addPath(second.cgPath)
        try check(paint(grouped,CGPoint(x:450,y:450)) && !compound.contains(CGPoint(x:450,y:450),using:.winding),
                  "Opposite-winding fixture must expose accidental compound cancellation")
        let unionEditor=FontLabVectorEditor(glyph:grouped,metrics:metrics)
        unionEditor.selectAll();unionEditor.boolean("overlap")
        try check(paint(unionEditor.glyph,CGPoint(x:450,y:450)),"Remove overlaps must union independent source groups without cutting a new hole")
        let duplicated=FontLabVectorEditor(glyph:grouped,metrics:metrics)
        duplicated.selectAll();duplicated.duplicate()
        try check(duplicated.glyph.strokes.count == 4 && paint(duplicated.glyph,CGPoint(x:450,y:450)),
                  "Duplicate must preserve the paint groups of copied contours")
        let groupedClipboard=FontLabVectorClipboard(designWidth:0.62,baseline:metrics.baseline,paths:[first,second],groups:[[first.id],[second.id]])
        let groupedPaste=FontLabVectorEditor(glyph:destination,metrics:metrics)
        groupedPaste.pastePaths(data:try JSONEncoder().encode(groupedClipboard))
        try check(groupedPaste.glyph.strokes.count == 2 && paint(groupedPaste.glyph,CGPoint(x:450,y:450)),
                  "Clipboard transfer must preserve independent source paint groups")
        let inner=FontLabVectorMath.rectangle(CGRect(x:0.25,y:0.35,width:0.2,height:0.2),ellipse:false)
        let counterEditor=FontLabVectorEditor(glyph:FontLabGlyph(character:"O",strokes:[FontLabStroke(vectorPaths:[first]),FontLabStroke(vectorPaths:[inner])]),metrics:metrics)
        counterEditor.selection=Set(inner.nodes.map(\.id));counterEditor.pathCommand("counter")
        try check(counterEditor.glyph.strokes.count == 1 && !paint(counterEditor.glyph,CGPoint(x:350,y:450)),
                  "Make counter must intentionally group the inner and outer source contours")
        var counterCommits=0;counterEditor.onCommit={_ in counterCommits += 1};counterEditor.pathCommand("counter")
        try check(counterCommits == 0,"Reapplying Make counter must not create an unchanged history entry")
        counterEditor.selection=Set(first.nodes.map(\.id));counterEditor.boolean("overlap")
        try check(!paint(counterEditor.glyph,CGPoint(x:350,y:450)),"Removing overlaps on an outer contour must preserve its unselected counter")
        let crossing=FontLabVectorMath.rectangle(CGRect(x:0.25,y:0.35,width:0.55,height:0.2),ellipse:false)
        let crossingGlyph=FontLabGlyph(character:"C",strokes:[FontLabStroke(vectorPaths:[first]),FontLabStroke(vectorPaths:[crossing])])
        let crossingEditor=FontLabVectorEditor(glyph:crossingGlyph,metrics:metrics)
        crossingEditor.selection=Set(crossing.nodes.map(\.id));crossingEditor.pathCommand("counter")
        try check(crossingEditor.glyph == crossingGlyph,"A crossing contour whose first node is inside another shape must not become a counter")
        let splitPath=FontLabVectorPath(nodes:[.init(point:.init(x:0.1,y:0.1)),.init(point:.init(x:0.3,y:0.4)),.init(point:.init(x:0.6,y:0.2))])
        let splitEditor=FontLabVectorEditor(glyph:FontLabGlyph(character:"S",strokes:[FontLabStroke(vectorPaths:[splitPath]),FontLabStroke(vectorPaths:[second])]),metrics:metrics)
        splitEditor.selection=[splitPath.nodes[1].id];splitEditor.splitAtNode()
        try check(splitEditor.glyph.strokes.count == 2 && splitEditor.glyph.strokes[0].vectorPaths?.count == 2,
                  "Splitting an open contour must retain both fragments in their original paint group")
        print("Letterform editor state checks passed: clipboard units/baselines, isolation, rejected paste, legacy input, path availability and invalid transforms")
    }
}
