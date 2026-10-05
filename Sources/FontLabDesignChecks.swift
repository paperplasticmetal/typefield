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
        let chainNames = Array("ABCDEFGH").map(String.init)
        var emptyChain = FontLabProject(name: "Empty component graph", characters: chainNames)
        for index in 0..<(chainNames.count - 1) {
            emptyChain.glyphs[chainNames[index]]?.components = (0..<16).map { _ in
                FontLabComponentUse(source: chainNames[index + 1])
            }
        }
        let emptyStarted = Date()
        try check(emptyChain.isValid && emptyChain.resolvedGlyph("A")?.strokes.isEmpty == true,
                  "Repeated empty component trees must resolve without expanding every reference")
        print(String(format: "PERF: 8-level, 16-way empty component validation %.3f ms", Date().timeIntervalSince(emptyStarted) * 1000))
        // Resolve H first to populate its cache, then reach it through an
        // over-depth branch. Reuse must preserve the original depth rejection.
        var tooDeep = emptyChain
        tooDeep.characters.append("I"); tooDeep.glyphs["I"] = FontLabGlyph(character: "I")
        tooDeep.glyphs["H"]?.components = [FontLabComponentUse(source: "I")]
        tooDeep.glyphs["A"]?.components?.insert(FontLabComponentUse(source: "H"), at: 0)
        try check(tooDeep.resolvedGlyph("A") == nil, "Cached empty components bypassed the nesting limit")
        var emptyCycle = emptyChain
        emptyCycle.glyphs["H"]?.components = [FontLabComponentUse(source: "A")]
        try check(emptyCycle.resolvedGlyph("A") == nil, "Empty component caching bypassed cycle rejection")
        var mixedGraph = p
        mixedGraph.characters += chainNames.filter { mixedGraph.glyphs[$0] == nil }
        for name in chainNames where mixedGraph.glyphs[name] == nil { mixedGraph.glyphs[name] = emptyChain.glyphs[name] }
        // H is empty and can be shared with differently transformed artwork.
        mixedGraph.glyphs["B"]?.components = [FontLabComponentUse(source: "H"), FontLabComponentUse(source: "A", x: 0.01, scale: 0.8), FontLabComponentUse(source: "H")]
        var withoutEmpty = mixedGraph
        withoutEmpty.glyphs["B"]?.components?.removeAll { $0.source == "H" }
        try check(mixedGraph.resolvedGlyph("C") == withoutEmpty.resolvedGlyph("C"),
                  "Empty component reuse changed nested nonempty geometry, transforms or metrics")
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
        try check(paths.count==2 && paths.reduce(0,{$0+$1.nodes.count})<40 && paths.contains { $0.nodes.contains { $0.incoming != nil } },"Trace smoothing failed to reduce points into curves")
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
        var denseCurve=curve
        for _ in 0..<4 {
            for segment in (0..<denseCurve.segmentCount).reversed() { denseCurve.insertNode(segment:segment,t:0.5) }
        }
        let denseGlyph=FontLabGlyph(character:"o",strokes:[FontLabStroke(vectorPaths:[denseCurve])])
        let compactCurve=try FontLabTraceSmoothing.fit(denseGlyph,units:1,refitDenseCurves:true)
        try check(FontLabVectorMath.paths(in:compactCurve).flatMap(\.nodes).count < 16,
                  "Dense generated curves were not reduced to practical editing anchors")
        let denseRing=(0..<30_000).map { i -> FontLabVectorNode in
            let angle=Double(i)*2 * .pi/30_000
            return .init(point:.init(x:0.5+0.38*cos(angle),y:0.5+0.30*sin(angle)))
        }
        let huge=FontLabGlyph(character:"A",strokes:[FontLabStroke(vectorPaths:[FontLabVectorPath(nodes:denseRing,closed:true)])],contourDesignWidth:0.62)
        let started=Date(),reduced=try FontLabTraceSmoothing.fit(huge,units:5,refitDenseCurves:true)
        let reducedPaths=FontLabVectorMath.paths(in:reduced)
        try check(reducedPaths.flatMap(\.nodes).count<40 && reducedPaths.count==1 && reduced.isValid,"30,000-anchor cleanup failed")
        let a=FontLabVectorMath.paths(in:huge)[0].cgPath,b=reducedPaths[0].cgPath
        var intersection=0,union=0
        for y in 0..<80 { for x in 0..<80 {
            let p=CGPoint(x:Double(x)*12.5+6.25,y:Double(y)*12.5+6.25),aa=a.contains(p),bb=b.contains(p)
            if aa && bb { intersection += 1 };if aa || bb { union += 1 }
        } }
        try check(Double(intersection)/Double(union)>0.98,"Dense cleanup distorted filled ink")
        print("STRESS CURVE: 30,000 → \(reducedPaths.flatMap(\.nodes).count) anchors, \(String(format:"%.3f",Date().timeIntervalSince(started)))s, IoU \(Double(intersection)/Double(union))")
        func stressRing(_ count:Int,_ radius:Double,_ reverse:Bool)->FontLabVectorPath {
            var nodes=(0..<count).map { i -> FontLabVectorNode in
                let t=Double(i)*2 * .pi/Double(count)
                return .init(point:.init(x:0.5+radius*cos(t),y:0.5+radius*sin(t)))
            }
            if reverse {nodes.reverse()};return FontLabVectorPath(nodes:nodes,closed:true)
        }
        let compoundDense=FontLabGlyph(character:"O",strokes:[FontLabStroke(vectorPaths:[stressRing(20_000,0.35,false),stressRing(10_000,0.18,true)])])
        let compoundFit=try FontLabTraceSmoothing.fit(compoundDense,units:5,refitDenseCurves:true),compoundInk=CGMutablePath()
        FontLabVectorMath.paths(in:compoundFit).forEach {compoundInk.addPath($0.cgPath)}
        try check(!compoundInk.contains(CGPoint(x:500,y:500)) && compoundInk.contains(CGPoint(x:240,y:500)),"Staged dense fitting lost its counter")
        let spikes=(0..<30_000).map { i -> FontLabVectorNode in
            let t=Double(i)*2 * .pi/30_000,r=i%2==0 ? 0.35:0.20
            return .init(point:.init(x:0.5+r*cos(t),y:0.5+r*sin(t)))
        }
        let noisy=FontLabGlyph(character:"O",strokes:[FontLabStroke(vectorPaths:[FontLabVectorPath(nodes:spikes,closed:true)])])
        do { _=try FontLabTraceSmoothing.fit(noisy,units:0.5);throw FontLabStore.SelfTestError.failed("Pathological outline bypassed bounded fitting") }
        catch is FontLabTraceSmoothing.Failure { /* Controlled refusal preserves the source. */ }
        print("CURVE FIT: \(source.strokes[0].contours!.reduce(0) { $0+$1.count }) → \(paths.reduce(0) { $0+$1.nodes.count }) anchors; dense curve \(denseCurve.nodes.count) → \(FontLabVectorMath.paths(in:compactCurve).flatMap(\.nodes).count)")
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 100, pixelsHigh: 100,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                      colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 100, height: 100).fill()
        let overlapping = [CGRect(x: 0.1, y: 0.2, width: 0.6, height: 0.6), CGRect(x: 0.4, y: 0.2, width: 0.5, height: 0.6)].map {
            FontLabStroke(vectorPaths: [FontLabVectorMath.rectangle($0, ellipse: false)])
        }
        fontLabDrawStrokes(overlapping, in: NSRect(x: 0, y: 0, width: 100, height: 100), color: NSColor.black.withAlphaComponent(0.6))
        NSGraphicsContext.restoreGraphicsState()
        let singleInk = bitmap.colorAt(x: 20, y: 50)!.redComponent
        let joinedInk = bitmap.colorAt(x: 50, y: 50)!.redComponent
        try check(abs(singleInk-joinedInk) < 0.01 && abs(singleInk-0.4) < 0.03,
                  "Overlapping preview strokes accumulated opacity or changed the chosen ink color")
        print("PASS: linked/nested components, cycle/bounds rejection, master isolation, kerning groups/exceptions and Core Text export, smoothing counters and design persistence.")
    }
}
