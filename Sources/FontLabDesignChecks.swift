import AppKit
import CoreText

enum FontLabDesignChecks {
    static func fixture() -> FontLabProject {
        var project = FontLabProject(name: "Font design QA", characters: ["A","B","C","V","W","O"])
        let rectangle = FontLabVectorMath.rectangle(CGRect(x:0.12,y:0.18,width:0.65,height:0.6),ellipse:false)
        project.glyphs["A"] = FontLabGlyph(character:"A",strokes:[FontLabStroke(vectorPaths:[rectangle])],contourDesignWidth:0.62)
        for c in ["V","W"] { var glyph=project.glyphs["A"]!;glyph.character=c;project.glyphs[c]=glyph }
        project.glyphs["B"]?.components=[FontLabComponentUse(source:"A")]
        project.glyphs["C"]?.components=[FontLabComponentUse(source:"B",x:0.025,scale:0.9)]
        func ring(_ count:Int,_ radius:Double,_ reverse:Bool)->[FontLabPoint] {
            var points=(0..<count).map { i -> FontLabPoint in
                let angle=Double(i)*2 * .pi/Double(count),r=radius+0.00012*sin(Double(i)*1.7)
                return .init(x:0.5+cos(angle)*r,y:0.48+sin(angle)*r)
            }
            if reverse {points.reverse()};return points
        }
        project.glyphs["O"]=FontLabGlyph(character:"O",strokes:[FontLabStroke(contours:[ring(320,0.28,false),ring(160,0.12,true)])],contourDesignWidth:0.62)
        return project
    }
    static func run() throws {
        func check(_ value:@autoclosure()->Bool,_ message:String)throws {if !value() {throw FontLabStore.SelfTestError.failed(message)}}
        try check(FontLabShortcutAction.resolve(key:"[",modifiers:.command) == .previousGlyph && FontLabShortcutAction.resolve(key:"]",modifiers:.command) == .nextGlyph,"Letterform glyph navigation shortcuts changed")
        try check(FontLabShortcutAction.resolve(key:"1",modifiers:[.command,.shift]) == .vectorEditor && FontLabShortcutAction.resolve(key:"2",modifiers:[.command,.shift]) == .sketchEditor,"Letterform editor mode shortcuts changed")
        try check(FontLabShortcutAction.resolve(key:"!",keyCode:18,modifiers:[.command,.shift]) == .vectorEditor && FontLabShortcutAction.resolve(key:"@",keyCode:19,modifiers:[.command,.shift]) == .sketchEditor,"Shifted physical number keys must switch Letterform editor modes")
        try check(FontLabShortcutAction.resolve(key:"[",modifiers:[.command,.option]) == nil && FontLabShortcutAction.resolve(key:"z",modifiers:.command) == nil,"Letterform shortcuts must leave unrelated commands alone")
        var p=fixture()
        try check(p.isValid,"Linked component fixture invalid")
        let before=p.resolvedGlyph("B")!
        p.glyphs["A"]!.strokes[0].vectorPaths![0].nodes[0].point.x += 0.01
        try check(p.resolvedGlyph("B") != before && p.glyphs["B"]!.strokes.isEmpty,"Component source edits did not propagate without baking")
        try check(p.resolvedGlyph("C")!.components == nil,"Nested component did not resolve")
        var cycle=p;cycle.glyphs["A"]?.components=[FontLabComponentUse(source:"C")]
        try check(!cycle.isValid,"Cyclic component reference accepted")
        var outside=p;outside.glyphs["B"]!.components![0].x=2
        try check(!outside.isValid,"Out-of-bounds component accepted")
        let componentFont=try FontLabTrueTypeExporter.artifact(for:p)
        let bakedFont=try FontLabTrueTypeExporter.artifact(for:p.outputProject)
        try check(componentFont.data == bakedFont.data,"Component export differs from resolved outline export")
        try check(FontLabSVGCollectionExporter.artifacts(for:p) == FontLabSVGCollectionExporter.artifacts(for:p.outputProject),"SVG collection did not resolve linked components")
        var detached=p.glyphs["B"]!
        detached.components=nil
        detached.strokes=FontLabDesign.detachedStrokes(before.strokes)+FontLabDesign.detachedStrokes(before.strokes)
        let detachedPaths=FontLabVectorMath.paths(in:detached)
        try check(Set(detachedPaths.map(\.id)).count == detachedPaths.count && Set(detachedPaths.flatMap(\.nodes).map(\.id)).count == detachedPaths.flatMap(\.nodes).count,"Decomposed copies share editable node identities")
        let left=FontLabKerningGroup(name:"Straight",members:["A","B"],side:.left)
        let right=FontLabKerningGroup(name:"Diagonal",members:["V","W"],side:.right)
        p.kerningGroups=[left,right]
        p.kerningPairs=[.init(left:"@"+left.id.uuidString,right:"@"+right.id.uuidString,value:-80),.init(left:"A",right:"@"+right.id.uuidString,value:-100),.init(left:"A",right:"V",value:-120),.init(left:"B",right:"V",value:0)]
        try check(p.isValid && p.kerning("A","V") == -120 && p.kerning("A","W") == -100 && p.kerning("B","W") == -80 && p.kerning("B","V") == 0,"Kerning group/exception precedence failed")
        let expanded=try p.resolvedKerning(characters:Set(p.characters))
        try check(expanded.count==3,"Zero kerning exception failed to override group")
        let kerned=try FontLabTrueTypeExporter.artifact(for:p)
        try check(kerned.postScriptName != componentFont.postScriptName,"Kerning changes reused font identity")
        let dataProvider=CGDataProvider(data:kerned.data as CFData)!,font=CTFontCreateWithGraphicsFont(CGFont(dataProvider)!,1000,nil,nil)
        try check(CTFontCopyTable(font,CTFontTableTag(0x6b65726e),[]) != nil,"Kerning table missing from exported font")
        func advance(_ string:String,_ font:CTFont)->Double {CTLineGetTypographicBounds(CTLineCreateWithAttributedString(NSAttributedString(string:string,attributes:[.font:font])),nil,nil,nil)}
        let unkerned=CTFontCreateWithGraphicsFont(CGFont(CGDataProvider(data:componentFont.data as CFData)!)!,1000,nil,nil)
        try check(abs((advance("AV",font)-advance("AV",unkerned))+120)<0.1,"Core Text did not apply exported pair kerning")
        var alias=p
        alias.glyphs["\u{00a0}"]=FontLabGlyph(character:"\u{00a0}")
        alias.kerningPairs?.append(.init(left:"A",right:"\u{00a0}",value:-70))
        let aliasFont=try FontLabTrueTypeExporter.artifact(for:alias)
        try check(aliasFont.data == kerned.data,"Nonexported cmap alias changed kerning without a revision")
        var overlap=p;overlap.kerningGroups?.append(.init(name:"Duplicate",members:["A"],side:.left));try check(!overlap.isValid,"Ambiguous same-side group membership accepted")
        let base=p.glyphs
        p.addMaster(name:"Bold",weight:700);let bold=p.activeMasterID!,regular=p.masters![0].id
        p.glyphs["A"]!.strokes[0].vectorPaths![0].nodes[1].point.x -= 0.04
        p.kerningPairs![0].value = -60
        let edited=p.glyphs
        p.switchMaster(regular);try check(p.glyphs==base && p.kerningPairs![0].value == -80,"Switching masters lost the original design")
        p.switchMaster(bold);try check(p.glyphs==edited && p.kerningPairs![0].value == -60,"Switching masters lost edits or kerning")
        let roundTrip=try JSONDecoder().decode(FontLabProject.self,from:JSONEncoder().encode(p))
        try check(roundTrip==p && roundTrip.isValid,"Components/masters/kerning did not persist")
        try check(roundTrip.masters?.first(where: { $0.id == roundTrip.activeMasterID })?.weight == 700,"The active master weight did not persist")
        let weightedArtifact=try FontLabTrueTypeExporter.artifact(for:roundTrip)
        let weightedFont=CTFontCreateWithGraphicsFont(CGFont(CGDataProvider(data:weightedArtifact.data as CFData)!)!,1000,nil,nil)
        let os2=CTFontCopyTable(weightedFont,CTFontTableTag(0x4f532f32),[]) as Data?
        try check(os2.map { UInt16($0[4]) << 8 | UInt16($0[5]) } == 700,"Active master weight was not written to OS/2.usWeightClass")
        var lighter=roundTrip
        var lighterMasters=lighter.masters ?? []
        if let index=lighterMasters.firstIndex(where: { $0.id == lighter.activeMasterID }) { lighterMasters[index].weight=400 }
        lighter.masters=lighterMasters
        let lighterArtifact=try FontLabTrueTypeExporter.artifact(for:lighter)
        try check(lighterArtifact.postScriptName != weightedArtifact.postScriptName,"Changing master weight reused the exported font identity")
        let source=fixture().glyphs["O"]!,smooth=try FontLabTraceSmoothing.fit(source,units:1)
        let paths=FontLabVectorMath.paths(in:smooth),compound=CGMutablePath();paths.forEach {compound.addPath($0.cgPath)}
        try check(paths.count==2 && paths.reduce(0,{$0+$1.nodes.count})<240 && paths.contains { $0.nodes.contains { $0.incoming != nil } },"Trace smoothing failed to reduce points into curves")
        try check(!compound.contains(CGPoint(x:500,y:480)) && compound.contains(CGPoint(x:250,y:480)),"Smoothing lost a counter or outer shape")
        try check(source.strokes[0].contours != nil && smooth.isValid,"Smoothing changed original data or returned invalid paths")
        var smoothedProject=fixture();smoothedProject.glyphs["O"]=smooth
        _=try FontLabTrueTypeExporter.artifact(for:smoothedProject)
        let corners=[FontLabPoint(x:0.1,y:0.1),.init(x:0.8,y:0.1),.init(x:0.8,y:0.8),.init(x:0.1,y:0.8)]
        let square=corners.indices.flatMap { i in (0..<20).map { FontLabVectorMath.mix(corners[i],corners[(i+1)%4],Double($0)/20) } }
        let polygon=FontLabGlyph(character:"L",strokes:[FontLabStroke(contours:[square])])
        let fittedSquare=try FontLabTraceSmoothing.fit(polygon,units:1)
        let squareNodes=FontLabVectorMath.paths(in:fittedSquare).flatMap(\.nodes)
        try check(squareNodes.count == 4 && squareNodes.allSatisfy { $0.incoming == nil && $0.outgoing == nil },"Smoothing rounded sharp corners")
        var mixed=source
        let curve=FontLabVectorMath.rectangle(CGRect(x:0.02,y:0.02,width:0.06,height:0.06),ellipse:true)
        mixed.strokes.append(FontLabStroke(vectorPaths:[curve]))
        let fittedMixed=try FontLabTraceSmoothing.fit(mixed,units:1)
        try check(FontLabVectorMath.paths(in:fittedMixed).contains(curve),"Smoothing changed an existing Bézier contour")
        print("PASS: linked/nested components, cycle/bounds rejection, master isolation, kerning groups/exceptions and Core Text export, smoothing counters and design persistence.")
    }
}
