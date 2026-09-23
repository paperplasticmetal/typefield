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
