import AppKit

final class FontLabVectorNSView: NSView {
    let editor: FontLabVectorEditor
    private var start = CGPoint.zero
    private var previousGlyph: FontLabGlyph?
    private var originalPaths: [FontLabVectorPath] = []
    private var initialSelection = Set<UUID>()
    private var marquee: CGRect?
    private var spaceDown = false
    private var panStart = CGPoint.zero
    private var resizeBox = CGRect.zero
    private enum Drag { case none, nodes, handle(Int,Int,Bool), pen(Int,Int), shape, marquee, pan, resize(Int) }
    private var drag = Drag.none
    init(editor:FontLabVectorEditor) {self.editor=editor;super.init(frame:.zero);setAccessibilityLabel("Vector glyph canvas");setAccessibilityRole(.group)}
    required init?(coder:NSCoder) {fatalError("init(coder:) has not been implemented")}
    override var acceptsFirstResponder:Bool {true}
    override func acceptsFirstMouse(for event:NSEvent?)->Bool {true}
    var designRect:CGRect {
        let width=editor.glyph.resolvedDesignWidth
        let em=max(80,min((bounds.width-90)/width,bounds.height-75))*editor.zoom
        return CGRect(x:(bounds.width-em*width)/2+editor.pan.x,y:(bounds.height-em)/2+editor.pan.y,width:em*width,height:em)
    }
    private func screen(_ p:FontLabPoint)->CGPoint {CGPoint(x:designRect.minX+p.x*designRect.width,y:designRect.minY+p.y*designRect.height)}
    private func design(_ p:CGPoint,clamp:Bool=true)->FontLabPoint {
        let x=(p.x-designRect.minX)/designRect.width,y=(p.y-designRect.minY)/designRect.height
        return FontLabPoint(x:clamp ? min(1,max(0,x)):x,y:clamp ? min(1,max(0,y)):y)
    }
    private func snapped(_ p:FontLabPoint,event:NSEvent)->FontLabPoint {
        guard editor.snap,!event.modifierFlags.contains(.control) else {return p}
        let xUnit=1/(editor.glyph.resolvedDesignWidth*1000),yUnit=0.001
        var result=FontLabPoint(x:(p.x/xUnit).rounded()*xUnit,y:(p.y/yUnit).rounded()*yUnit)
        var xs=[0.0,1.0],ys=[0.0,1.0,editor.metrics.baseline,editor.metrics.xHeight,editor.metrics.capHeight]
        for node in originalPaths.flatMap(\.nodes) where !editor.selection.contains(node.id) {xs.append(node.point.x);ys.append(node.point.y)}
        if let x=xs.min(by:{abs($0-p.x)<abs($1-p.x)}),abs(x-p.x)*designRect.width<5 {result.x=x}
        if let y=ys.min(by:{abs($0-p.y)<abs($1-p.y)}),abs(y-p.y)*designRect.height<5 {result.y=y}
        result.x=min(1,max(0,result.x));result.y=min(1,max(0,result.y));return result
    }
    override func draw(_ dirtyRect:NSRect) {
        NSColor.textBackgroundColor.setFill();bounds.fill()
        let r=designRect
        if editor.grid {
            NSColor.secondaryLabelColor.withAlphaComponent(0.09).setStroke()
            let grid=NSBezierPath();grid.lineWidth=0.5
            let step=editor.zoom>=3 ? 0.01:0.05
            for y in stride(from:0.0,through:1.00001,by:step) {let a=screen(.init(x:0,y:y));grid.move(to:a);grid.line(to:screen(.init(x:1,y:y)))}
            let xStep=step/editor.glyph.resolvedDesignWidth
            for x in stride(from:0.0,through:1.00001,by:xStep) {grid.move(to:screen(.init(x:x,y:0)));grid.line(to:screen(.init(x:x,y:1)))}
            grid.stroke()
        }
        NSColor.separatorColor.setStroke();NSBezierPath(rect:r).stroke()
        let guides=[("Baseline",editor.metrics.baseline),("x-height",editor.metrics.xHeight),("Cap height",editor.metrics.capHeight)]
        for (label,y) in guides {
            let position=screen(.init(x:0,y:y)).y
            NSColor.systemOrange.withAlphaComponent(0.48).setStroke()
            let line=NSBezierPath();line.move(to:CGPoint(x:0,y:position));line.line(to:CGPoint(x:bounds.width,y:position));line.lineWidth=0.7;line.stroke()
            (label as NSString).draw(at:CGPoint(x:8,y:position+3),withAttributes:[.font:NSFont.systemFont(ofSize:9),.foregroundColor:NSColor.secondaryLabelColor])
        }
        fontLabDrawStrokes(editor.componentStrokes,in:r,color:.systemTeal)
        let paths=editor.paths
        let pens=editor.glyph.strokes.filter {$0.contours == nil && $0.vectorPaths == nil}
        fontLabDrawStrokes(pens,in:r,color:NSColor(editor.inkColor))
        if editor.fill {FontLabVectorMath.draw(paths,in:r,color:NSColor(editor.inkColor))}
        for path in paths {
            NSColor.systemBlue.withAlphaComponent(0.75).setStroke();let outline=path.bezier(in:r);outline.lineWidth=1;outline.stroke()
            if editor.objectSelection && editor.tool == .select { continue }
            for (index,node) in path.nodes.enumerated() {
                let p=screen(node.point)
                if editor.selection.contains(node.id) {
                    for h in [node.incoming,node.outgoing].compactMap({$0}) {
                        let handle=screen(h);let line=NSBezierPath();line.move(to:p);line.line(to:handle);NSColor.systemOrange.setStroke();line.lineWidth=1;line.stroke()
                        NSColor.textBackgroundColor.setFill();let dot=NSBezierPath(ovalIn:CGRect(x:handle.x-3,y:handle.y-3,width:6,height:6));dot.fill();dot.stroke()
                    }
                }
                guard bounds.insetBy(dx:-10,dy:-10).contains(p) else {continue}
                let size:Double=editor.selection.contains(node.id) ? 8:6
                let box=CGRect(x:p.x-size/2,y:p.y-size/2,width:size,height:size)
                let shape=node.smooth ? NSBezierPath(ovalIn:box):NSBezierPath(rect:box)
                (editor.selection.contains(node.id) ? NSColor.systemOrange:NSColor.textBackgroundColor).setFill();shape.fill();NSColor.systemBlue.setStroke();shape.lineWidth=1;shape.stroke()
                if index==0 {let marker=NSBezierPath();marker.move(to:CGPoint(x:p.x+5,y:p.y));marker.line(to:CGPoint(x:p.x+9,y:p.y+3));marker.line(to:CGPoint(x:p.x+9,y:p.y-3));marker.close();NSColor.systemBlue.setFill();marker.fill()}
            }
        }
        if editor.objectSelection && editor.tool == .select, let box = selectionBox {
            NSColor.systemBlue.setStroke(); NSBezierPath(rect: box).stroke()
            for p in corners(box) {
                let handle = NSBezierPath(rect: CGRect(x:p.x-4,y:p.y-4,width:8,height:8))
                NSColor.textBackgroundColor.setFill(); handle.fill(); handle.stroke()
            }
        }
        if let marquee {NSColor.systemBlue.withAlphaComponent(0.12).setFill();marquee.fill();NSColor.systemBlue.setStroke();NSBezierPath(rect:marquee).stroke()}
        if paths.isEmpty && pens.isEmpty && editor.componentStrokes.isEmpty {
            ("Choose Bézier and click to place nodes. Drag for curves.\nClick the first node to close a contour." as NSString).draw(in:bounds.insetBy(dx:40,dy:60),withAttributes:[.font:NSFont.systemFont(ofSize:12),.foregroundColor:NSColor.secondaryLabelColor])
        }
    }
    private func corners(_ r: CGRect) -> [CGPoint] { [CGPoint(x:r.minX,y:r.minY),CGPoint(x:r.maxX,y:r.minY),CGPoint(x:r.maxX,y:r.maxY),CGPoint(x:r.minX,y:r.maxY)] }
    private var selectionBox: CGRect? {
        let chosen = editor.paths.filter { !$0.nodes.isEmpty && $0.nodes.allSatisfy { editor.selection.contains($0.id) } }
        guard !chosen.isEmpty else { return nil }
        let box = chosen.reduce(CGRect.null) { $0.union($1.bezier(in:designRect).bounds) }
        return box.width > 0.1 && box.height > 0.1 ? box : nil
    }
    private func hitNode(_ p:CGPoint)->(Int,Int,Bool?)? {
        let paths=editor.paths
        for a in paths.indices.reversed() {for b in paths[a].nodes.indices where editor.selection.contains(paths[a].nodes[b].id) {
            let node=paths[a].nodes[b]
            for (outgoing,h) in [(false,node.incoming),(true,node.outgoing)] {
                if let h,hypot(screen(h).x-p.x,screen(h).y-p.y)<7 {return (a,b,outgoing)}
            }
        }}
        for a in paths.indices.reversed() {for b in paths[a].nodes.indices.reversed() {
            let q=screen(paths[a].nodes[b].point);if hypot(q.x-p.x,q.y-p.y)<8 {return (a,b,nil)}
        }}
        return nil
    }
    private func hitSegment(_ p:CGPoint)->(Int,Int,Double)? {
        var best:(Int,Int,Double)?,distance=7.0
        let paths=editor.paths
        for a in paths.indices {for b in 0..<paths[a].segmentCount {
            let c=paths[a].controls(b),samples=paths[a].isCurve(b) ? 50:1
            for i in 0..<samples {
                let t0=Double(i)/Double(samples),t1=Double(i+1)/Double(samples)
                let q=screen(paths[a].isCurve(b) ? FontLabVectorMath.evaluate(c,t0):c[0])
                let r=screen(paths[a].isCurve(b) ? FontLabVectorMath.evaluate(c,t1):c[3])
                let dx=r.x-q.x,dy=r.y-q.y
                let t=min(1,max(0,((p.x-q.x)*dx+(p.y-q.y)*dy)/max(1e-12,dx*dx+dy*dy)))
                let d=hypot(q.x+dx*t-p.x,q.y+dy*t-p.y)
                if d<distance {distance=d;best=(a,b,t0+(t1-t0)*t)}
            }
        }}
        return best
    }
    override func mouseDown(with event:NSEvent) {
        window?.makeFirstResponder(self)
        start=convert(event.locationInWindow,from:nil);previousGlyph=editor.glyph;originalPaths=editor.paths;initialSelection=editor.selection
        if spaceDown || editor.tool == .hand {drag = .pan;panStart=editor.pan;return}
        let point=snapped(design(start),event:event)
        switch editor.tool {
        case .pen:
            var paths=editor.paths
            if let a=paths.firstIndex(where:{$0.id==editor.activePath && !$0.closed}) {
                if paths[a].nodes.count>=3,hypot(screen(paths[a].nodes[0].point).x-start.x,screen(paths[a].nodes[0].point).y-start.y)<9 {
                    paths[a].closed=true;_=editor.apply(paths);editor.activePath=nil;drag = .none;return
                }
                paths[a].nodes.append(.init(point:point));editor.selection=[paths[a].nodes.last!.id];_=editor.apply(paths,commit:false);drag = .pen(a,paths[a].nodes.count-1)
            } else if let (a,b,_) = hitNode(start),!paths[a].closed,b==paths[a].nodes.count-1 {
                editor.activePath=paths[a].id;editor.selection=[paths[a].nodes[b].id];drag = .none
            } else {
                let path=FontLabVectorPath(nodes:[.init(point:point)]);paths.append(path);editor.activePath=path.id;editor.selection=[path.nodes[0].id];_=editor.apply(paths,commit:false);drag = .pen(paths.count-1,0)
            }
        case .rectangle,.ellipse:drag = .shape
        case .select:
            if editor.objectSelection {
                if let box = selectionBox, let corner = corners(box).firstIndex(where: { hypot($0.x-start.x,$0.y-start.y)<9 }) {
                    drag = .resize(corner); resizeBox = box; return
                }
                let hit = hitSegment(start)?.0 ?? originalPaths.indices.reversed().first { originalPaths[$0].closed && originalPaths[$0].bezier(in:designRect).contains(start) }
                if let hit {
                    let alreadySelected = originalPaths[hit].nodes.allSatisfy { editor.selection.contains($0.id) }
                    if !alreadySelected || event.modifierFlags.contains(.shift) { editor.selectObject(hit, adding:event.modifierFlags.contains(.shift)) }
                    drag = .nodes; needsDisplay = true; return
                }
                if !event.modifierFlags.contains(.shift) { editor.selection = [] }
                drag = .marquee; marquee = CGRect(origin:start,size:.zero); needsDisplay = true; return
            }
            if let (a,b,handle)=hitNode(start) {
                if let handle {drag = .handle(a,b,handle);return}
                let id=originalPaths[a].nodes[b].id
                if event.clickCount==2 {editor.selection=[id];editor.smooth(!originalPaths[a].nodes[b].smooth);drag = .none;return}
                if event.modifierFlags.contains(.shift) {if editor.selection.contains(id) {editor.selection.remove(id)} else {editor.selection.insert(id)}}
                else if !editor.selection.contains(id) {editor.selection=[id]}
                drag = .nodes
            } else if let (a,b,t)=hitSegment(start) {
                if event.clickCount==2 {
                    var paths=editor.paths;paths[a].insertNode(segment:b,t:t);_=editor.apply(paths);editor.selection=[paths[a].nodes[b+1].id];drag = .none
                } else {
                    let ids=Set(originalPaths[a].nodes.map(\.id));editor.selection=event.modifierFlags.contains(.shift) ? editor.selection.union(ids):ids;drag = .nodes
                }
            } else {
                if !event.modifierFlags.contains(.shift) {editor.selection=[]}
                drag = .marquee;marquee=CGRect(origin:start,size:.zero)
            }
        case .hand:break
        }
        needsDisplay=true
    }
    override func mouseDragged(with event:NSEvent) {
        let end=convert(event.locationInWindow,from:nil)
        switch drag {
        case .none:break
        case let .resize(corner):
            let points = corners(resizeBox), opposite = points[(corner+2)%4], moving = points[corner]
            var sx = max(0.02,(end.x-opposite.x)/(moving.x-opposite.x))
            var sy = max(0.02,(end.y-opposite.y)/(moving.y-opposite.y))
            if event.modifierFlags.contains(.shift) { let uniform = abs(sx-1)>abs(sy-1) ? sx:sy; sx=uniform;sy=uniform }
            let anchor = design(opposite,clamp:false)
            _=editor.apply(FontLabVectorEditor.resized(originalPaths,selection:initialSelection,anchor:anchor,sx:sx,sy:sy),commit:false)
        case .pan:editor.pan=CGPoint(x:panStart.x+end.x-start.x,y:panStart.y+end.y-start.y)
        case .marquee:
            marquee=CGRect(x:min(start.x,end.x),y:min(start.y,end.y),width:abs(end.x-start.x),height:abs(end.y-start.y))
            let ids=Set(editor.paths.flatMap(\.nodes).filter {marquee!.contains(screen($0.point))}.map(\.id))
            editor.selection=event.modifierFlags.contains(.shift) ? initialSelection.union(ids):ids
        case .nodes:
            let a=design(start,clamp:false),b=design(end,clamp:false)
            var dx=b.x-a.x,dy=b.y-a.y
            if event.modifierFlags.contains(.shift) {if abs(dx*designRect.width)>abs(dy*designRect.height) {dy=0} else {dx=0}}
            if let reference=originalPaths.flatMap(\.nodes).first(where:{editor.selection.contains($0.id)}) {
                let p=snapped(.init(x:reference.point.x+dx,y:reference.point.y+dy),event:event);dx=p.x-reference.point.x;dy=p.y-reference.point.y
            }
            var paths=originalPaths
            for p in paths.indices {for n in paths[p].nodes.indices where editor.selection.contains(paths[p].nodes[n].id) {
                paths[p].nodes[n].point.x += dx;paths[p].nodes[n].point.y += dy
                if paths[p].nodes[n].incoming != nil {paths[p].nodes[n].incoming!.x += dx;paths[p].nodes[n].incoming!.y += dy}
                if paths[p].nodes[n].outgoing != nil {paths[p].nodes[n].outgoing!.x += dx;paths[p].nodes[n].outgoing!.y += dy}
            }}
            _=editor.apply(paths,commit:false)
        case let .handle(a,b,outgoing):
            var paths=editor.paths;let point=paths[a].nodes[b].point
            var handle=design(end,clamp:false)
            if event.modifierFlags.contains(.shift) {if abs(handle.x-point.x)*designRect.width>abs(handle.y-point.y)*designRect.height {handle.y=point.y} else {handle.x=point.x}}
            if outgoing {paths[a].nodes[b].outgoing=handle} else {paths[a].nodes[b].incoming=handle}
            if event.modifierFlags.contains(.option) {paths[a].nodes[b].smooth=false}
            else if paths[a].nodes[b].smooth {
                let other=outgoing ? paths[a].nodes[b].incoming:paths[a].nodes[b].outgoing
                if let other {
                    let w=editor.glyph.resolvedDesignWidth,dx=(handle.x-point.x)*w,dy=handle.y-point.y
                    let length=hypot((other.x-point.x)*w,other.y-point.y),denom=max(1e-9,hypot(dx,dy))
                    let h=FontLabPoint(x:point.x-dx/denom*length/w,y:point.y-dy/denom*length)
                    if outgoing {paths[a].nodes[b].incoming=h} else {paths[a].nodes[b].outgoing=h}
                }
            }
            _=editor.apply(paths,commit:false)
        case let .pen(a,b):
            var paths=editor.paths;guard paths.indices.contains(a),paths[a].nodes.indices.contains(b) else {return}
            let p=paths[a].nodes[b].point;var h=design(end,clamp:false)
            if event.modifierFlags.contains(.shift) {if abs(h.x-p.x)*designRect.width>abs(h.y-p.y)*designRect.height {h.y=p.y} else {h.x=p.x}}
            paths[a].nodes[b].outgoing=h;paths[a].nodes[b].incoming = .init(x:2*p.x-h.x,y:2*p.y-h.y);paths[a].nodes[b].smooth=true
            _=editor.apply(paths,commit:false)
        case .shape:
            let a=snapped(design(start),event:event);var b=snapped(design(end),event:event)
            if event.modifierFlags.contains(.shift) {
                let side=min(abs(b.x-a.x)*editor.glyph.resolvedDesignWidth,abs(b.y-a.y))
                b.x=a.x+(b.x<a.x ? -1:1)*side/editor.glyph.resolvedDesignWidth;b.y=a.y+(b.y<a.y ? -1:1)*side
            }
            let r=CGRect(x:min(a.x,b.x),y:min(a.y,b.y),width:abs(b.x-a.x),height:abs(b.y-a.y))
            guard r.width>0.001,r.height>0.001 else {return}
            let path=FontLabVectorMath.rectangle(r,ellipse:editor.tool == .ellipse)
            if editor.apply(originalPaths+[path],commit:false) {editor.selection=Set(path.nodes.map(\.id))}
        }
        needsDisplay=true
    }
    override func mouseUp(with event:NSEvent) {
        switch drag {case .nodes,.handle,.pen,.shape,.resize:if let previousGlyph {editor.finishGesture(from:previousGlyph)};default:break}
        previousGlyph=nil;marquee=nil;drag = .none;needsDisplay=true
    }
    override func keyDown(with event:NSEvent) {
        if handleCommandShortcut(event) { return }
        let modifiers=event.modifierFlags.intersection([.command,.shift,.option,.control])
        guard modifiers.isEmpty || modifiers == .shift else {super.keyDown(with:event);return}
        let key=event.charactersIgnoringModifiers?.lowercased() ?? ""
        let shift=modifiers.contains(.shift)
        if event.keyCode==53 {editor.activePath=nil;editor.tool = .select;editor.selection=[];return}
        if event.keyCode==51 || event.keyCode==117 {editor.deleteSelection();return}
        if event.keyCode==36 {editor.smooth(!editor.selectedNodes.allSatisfy(\.smooth));return}
        let unit=shift ? 0.01:0.001
        switch event.keyCode {
        case 123:editor.move(dx:-unit/editor.glyph.resolvedDesignWidth,dy:0);return
        case 124:editor.move(dx:unit/editor.glyph.resolvedDesignWidth,dy:0);return
        case 125:editor.move(dx:0,dy:-unit);return
        case 126:editor.move(dx:0,dy:unit);return
        default:break
        }
        switch key {
        case " ":spaceDown=true
        case "v":editor.tool = .select;editor.activePath=nil
        case "p":editor.tool = .pen
        case "r":editor.tool = .rectangle;editor.activePath=nil
        case "o":editor.tool = .ellipse;editor.activePath=nil
        case "h":editor.tool = .hand
        default:super.keyDown(with:event)
        }
    }
    override func keyUp(with event:NSEvent) {if event.keyCode==49 {spaceDown=false} else {super.keyUp(with:event)}}
    override func resignFirstResponder()->Bool {spaceDown=false;return super.resignFirstResponder()}
    override func performKeyEquivalent(with event:NSEvent)->Bool {
        if window?.firstResponder === self,handleCommandShortcut(event) {return true}
        return super.performKeyEquivalent(with:event)
    }
    private func handleCommandShortcut(_ event:NSEvent)->Bool {
        let modifiers=event.modifierFlags.intersection([.command,.shift,.option,.control])
        guard modifiers == .command || modifiers == [.command,.shift] else {return false}
        let shift=modifiers.contains(.shift)
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "z":if shift {editor.onRedo()} else {editor.onUndo()}
        case "a" where !shift:editor.selectAll()
        case "c" where !shift:editor.copyPaths()
        case "v" where !shift:editor.pastePaths()
        case "d" where !shift:editor.duplicate()
        case "0" where !shift:editor.fit()
        case "+","=":editor.zoom=min(8,editor.zoom*1.25)
        case "-" where !shift:editor.zoom=max(0.5,editor.zoom/1.25)
        default:return false
        }
        return true
    }
    override func scrollWheel(with event:NSEvent) {
        if event.modifierFlags.contains(.option) {zoom(by:exp(-event.scrollingDeltaY*0.015),at:convert(event.locationInWindow,from:nil))}
        else {editor.pan=CGPoint(x:editor.pan.x-event.scrollingDeltaX,y:editor.pan.y+event.scrollingDeltaY)}
    }
    override func magnify(with event:NSEvent) {zoom(by:1+event.magnification,at:convert(event.locationInWindow,from:nil))}
    private func zoom(by factor:Double,at point:CGPoint) {
        let before=design(point,clamp:false);editor.zoom=min(8,max(0.5,editor.zoom*factor));let after=screen(before)
        editor.pan=CGPoint(x:editor.pan.x+point.x-after.x,y:editor.pan.y+point.y-after.y)
    }
}
