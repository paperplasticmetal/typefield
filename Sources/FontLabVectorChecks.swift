import AppKit
import CoreText

enum FontLabVectorChecks {
    static func fixture() -> FontLabGlyph {
        let outer=FontLabVectorMath.rectangle(CGRect(x:0.1,y:0.18,width:0.8,height:0.6),ellipse:true)
        var inner=FontLabVectorMath.rectangle(CGRect(x:0.28,y:0.30,width:0.44,height:0.36),ellipse:true);inner.reverse()
        return FontLabGlyph(character:"O",strokes:[FontLabStroke(vectorPaths:[outer,inner])],contourDesignWidth:0.62)
    }
    static func run() throws {
        func check(_ condition:@autoclosure()->Bool,_ message:String)throws {if !condition() {throw FontLabStore.SelfTestError.failed(message)}}
        let glyph=fixture(),metrics=FontLabMetrics()
        var history = FontLabGlyphEditHistory()
        var editedO = glyph; editedO.leftSideBearing += 0.01
        var a = glyph; a.character = "A"
        var editedA = a; editedA.rightSideBearing += 0.02
        history.record(glyph); history.record(a)
        try check(history.undo(editedO) == glyph && history.undo(editedA) == a,
                  "Changing the active letter lost its independent undo history")
        try check(history.redo(glyph) == editedO && history.undo(a) == nil,
                  "Undo without history must not remove saved artwork; redo must restore the matching glyph")

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
        singleObject.selectAll(); singleObject.align(horizontal:true); singleObject.align(horizontal:false)
        singleObject.distribute(horizontal:true)
        try check(singleObject.glyph == glyph && !singleObject.canAlign && !singleObject.canDistribute,
                  "A single object with a counter must never collapse under alignment/distribution")
        let extra = FontLabVectorMath.rectangle(CGRect(x:0.01,y:0.04,width:0.05,height:0.06),ellipse:true)
        let arrangedGlyph = FontLabGlyph(character:"O",strokes:[FontLabStroke(vectorPaths:FontLabVectorMath.paths(in:glyph)+[extra])])
        for horizontal in [true,false] {
            let editor = FontLabVectorEditor(glyph:arrangedGlyph,metrics:metrics)
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

        let accessibilityEditor=FontLabVectorEditor(glyph:glyph,metrics:metrics)
        let accessibilityCanvas=FontLabVectorNSView(editor:accessibilityEditor)
        accessibilityCanvas.frame=CGRect(x:0,y:0,width:600,height:600)
        let contours=accessibilityCanvas.accessibilityChildren() as? [NSAccessibilityElement] ?? []
        try check(contours.count==2 && contours[0].accessibilityLabel()?.contains("Contour 1") == true,"Vector contours are missing from the accessibility hierarchy")
        let nodes=contours[0].accessibilityChildren() as? [NSAccessibilityElement] ?? []
        try check(nodes.count==4 && nodes[0].accessibilityLabel()?.contains("node 1") == true,"Vector nodes are missing from the accessibility hierarchy")
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
