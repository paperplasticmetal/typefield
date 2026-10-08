import AppKit

/// Repeated canvas work must be cheap without reusing an edited outline or a
/// previous selection. These fixtures contain no installed or user font data.
enum FontLabCanvasPerformanceChecks {
    static func run() throws {
        func check(_ condition:@autoclosure()->Bool,_ message:String) throws {
            if !condition() {throw FontLabStore.SelfTestError.failed(message)}
        }
        func glyph(_ count:Int)->FontLabGlyph {
            let nodes=(0..<count).map {index -> FontLabVectorNode in
                let angle=Double(index)*2 * Double.pi/Double(count)
                return .init(point:.init(x:0.5+0.36*cos(angle),y:0.5+0.36*sin(angle)))
            }
            return FontLabGlyph(character:"A",strokes:[FontLabStroke(vectorPaths:[.init(nodes:nodes,closed:true)])],contourDesignWidth:0.62)
        }
        func view(_ glyph:FontLabGlyph)->FontLabVectorNSView {
            let editor=FontLabVectorEditor(glyph:glyph,metrics:FontLabMetrics());editor.grid=false;editor.fill=false
            let canvas=FontLabVectorNSView(editor:editor);canvas.frame=CGRect(x:0,y:0,width:620,height:620)
            return canvas
        }
        func render(_ canvas:FontLabVectorNSView)->Data {
            let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:Int(canvas.bounds.width),pixelsHigh:Int(canvas.bounds.height),
                                       bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
            NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:bitmap)
            canvas.draw(canvas.bounds);NSGraphicsContext.restoreGraphicsState()
            return bitmap.representation(using:.png,properties:[:])!
        }
        func freshRender(_ source:FontLabVectorNSView)->Data {
            let fresh=view(source.editor.glyph)
            fresh.frame=source.frame;fresh.bounds=source.bounds
            fresh.editor.tool=source.editor.tool;fresh.editor.objectSelection=source.editor.objectSelection
            fresh.editor.selection=source.editor.selection;fresh.editor.zoom=source.editor.zoom;fresh.editor.pan=source.editor.pan
            return render(fresh)
        }
        let canvas=view(glyph(600)),original=render(canvas)
        try check(canvas.overlayCacheBuildCount==1 && render(canvas)==original && canvas.overlayCacheBuildCount==1,
                  "Dense canvas redraw must reuse its unchanged editing overlay")
        for tool in [FontLabVectorTool.pen,.line,.rectangle,.ellipse,.hand,.select] {
            canvas.editor.tool=tool
            try check(render(canvas)==original && canvas.overlayCacheBuildCount==1,
                      "Changing tools without changing displayed geometry must reuse the same overlay")
        }
        canvas.editor.objectSelection=true
        let objects=render(canvas)
        try check(objects==freshRender(canvas) && objects != original && canvas.overlayCacheBuildCount==2,
                  "Objects mode must cache its own outline-only overlay")
        canvas.editor.objectSelection=false
        try check(render(canvas)==original && canvas.overlayCacheBuildCount==2,
                  "Returning to Nodes must reuse the valid Nodes overlay instead of rebuilding every anchor")
        canvas.editor.selection=[canvas.editor.paths[0].nodes[0].id]
        let selected=render(canvas)
        try check(selected != original && selected==freshRender(canvas) && canvas.overlayCacheBuildCount==3,
                  "Changing node selection must invalidate cached marker styling")
        var paths=canvas.editor.paths
        paths[0].nodes[0].point.x -= 0.08
        paths[0].nodes[0].outgoing = .init(x:0.8,y:0.63)
        _=canvas.editor.apply(paths,commit:false)
        let edited=render(canvas)
        try check(edited != selected && edited==freshRender(canvas) && canvas.overlayCacheBuildCount==4,
                  "A same-identity anchor or handle edit must never display a stale cached outline")
        canvas.editor.zoom=1.3;canvas.editor.pan=CGPoint(x:18,y:-12)
        try check(render(canvas)==freshRender(canvas) && canvas.overlayCacheBuildCount==5,
                  "Zoom and pan must invalidate the screen-space overlay")
        canvas.frame.size=CGSize(width:660,height:640)
        try check(render(canvas)==freshRender(canvas) && canvas.overlayCacheBuildCount==6,
                  "Resizing the canvas must invalidate overlay pixel dimensions")
        var light=Data(),dark=Data(),freshDark=Data()
        NSAppearance(named:.aqua)!.performAsCurrentDrawingAppearance {light=render(canvas)}
        let lightBuilds=canvas.overlayCacheBuildCount
        NSAppearance(named:.darkAqua)!.performAsCurrentDrawingAppearance {dark=render(canvas);freshDark=freshRender(canvas)}
        try check(dark != light && dark==freshDark && canvas.overlayCacheBuildCount==lightBuilds+1,
                  "Appearance changes must invalidate cached outline and marker colors")

        let hit=view(glyph(1000));let center=CGPoint(x:hit.designRect.midX,y:hit.designRect.midY)
        _=hit.hitSegment(center);_=hit.hitSegment(center)
        try check(hit.hitGeometryBuildCount==1,"Repeated segment hit tests must reuse unchanged control hulls")
        hit.editor.zoom=2;hit.editor.pan=CGPoint(x:10,y:20);_=hit.hitSegment(center)
        try check(hit.hitGeometryBuildCount==1,"Viewport changes must reuse normalized segment geometry")
        var changed=hit.editor.paths;changed[0].nodes[0].outgoing = .init(x:0.5,y:0.2)
        _=hit.editor.apply(changed,commit:false);_=hit.hitSegment(center)
        try check(hit.hitGeometryBuildCount==2,"An edited handle must invalidate cached segment hit geometry")

        // Report bounded native timings, without a machine-dependent speed gate.
        let dense=view(glyph(10_000))
        let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:620,pixelsHigh:620,bitsPerSample:8,samplesPerPixel:4,
                                   hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
        NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:bitmap)
        dense.draw(dense.bounds)
        let started=ProcessInfo.processInfo.systemUptime
        for _ in 0..<10 {dense.draw(dense.bounds)}
        let redraw=(ProcessInfo.processInfo.systemUptime-started)*1000/10
        let point=CGPoint(x:dense.designRect.midX,y:dense.designRect.midY)
        _=dense.hitSegment(point)
        let hitStarted=ProcessInfo.processInfo.systemUptime
        for _ in 0..<100 {_=dense.hitSegment(point)}
        let hits=(ProcessInfo.processInfo.systemUptime-hitStarted)*1000/100
        NSGraphicsContext.restoreGraphicsState()
        try check(dense.overlayCacheBuildCount==1 && dense.hitGeometryBuildCount==1,
                  "Dense repeated redraws and hit tests rebuilt their cached geometry")
        print(String(format:"PERF: 10,000-anchor warmed canvas redraw %.3f ms; segment hit %.3f ms",redraw,hits))
        print("PASS: dense canvas overlay and segment caches invalidate geometry, selection, mode, zoom, pan and resize")
    }
}
