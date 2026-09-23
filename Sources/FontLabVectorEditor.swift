import SwiftUI
import AppKit

enum FontLabVectorTool: String, CaseIterable, Identifiable {
    case select = "Select", pen = "Bézier", rectangle = "Rectangle", ellipse = "Ellipse", hand = "Hand"
    var id: String { rawValue }
    var icon: String { switch self { case .select:return "cursorarrow";case .pen:return "point.topleft.down.to.point.bottomright.curvepath";case .rectangle:return "rectangle";case .ellipse:return "circle";case .hand:return "hand.draw" } }
}

final class FontLabVectorEditor: ObservableObject {
    @Published var glyph: FontLabGlyph
    @Published var componentStrokes: [FontLabStroke] = []
    @Published var metrics: FontLabMetrics
    @Published var tool = FontLabVectorTool.select
    @Published var selection = Set<UUID>()
    @Published var zoom = 1.0
    @Published var pan = CGPoint.zero
    @Published var grid = true
    @Published var snap = true
    @Published var fill = true
    @Published var objectSelection = true
    @Published var inkColor = Color(nsColor: .labelColor)
    @Published var message = "V Select · P Bézier · R Rectangle · O Ellipse · Space-drag to pan"
    var onCommit: (FontLabGlyph) -> Void = { _ in }
    var onUndo: () -> Void = {}
    var onRedo: () -> Void = {}
    var activePath: UUID?
    init(glyph: FontLabGlyph, metrics: FontLabMetrics) { self.glyph=glyph;self.metrics=metrics }
    var paths: [FontLabVectorPath] { FontLabVectorMath.paths(in:glyph) }
    var selectedNodes: [FontLabVectorNode] { paths.flatMap(\.nodes).filter { selection.contains($0.id) } }
    var selectedBounds: CGRect { FontLabVectorMath.bounds(selectedNodes.map(\.point)) }
    var openCount: Int { paths.filter { !$0.closed }.count }
    func receive(_ value: FontLabGlyph) {
        guard value != glyph else { return }
        glyph=value;selection.formIntersection(Set(paths.flatMap(\.nodes).map(\.id)))
        if !paths.contains(where:{$0.id == activePath}) { activePath=nil }
    }
    @discardableResult func apply(_ value: [FontLabVectorPath], commit: Bool = true) -> Bool {
        guard value.count <= 256, value.reduce(0,{$0+$1.nodes.count}) <= 30_000, value.allSatisfy(\.isValid) else {
            message="Keep anchors inside the design box and use fewer than 30,000 nodes.";return false
        }
        guard value != paths else { return false }
        let next=FontLabVectorMath.replacingPaths(in:glyph,with:value)
        guard next.isValid else { message="That edit is outside the glyph limits.";return false }
        guard next != glyph else { return false }
        glyph=next
        selection.formIntersection(Set(value.flatMap(\.nodes).map(\.id)))
        if commit { onCommit(next) }
        return true
    }
    func finishGesture(from before: FontLabGlyph) { if glyph != before { onCommit(glyph) } }
    func selectAll() { selection=Set(paths.flatMap(\.nodes).map(\.id)) }
    func fit() { zoom=1;pan = .zero }
    func selectObject(_ index: Int, adding: Bool) {
        let value = paths
        guard value.indices.contains(index) else { return }
        var outer = index
        for i in value.indices where value[i].closed && i != index {
            if value[i].cgPath.boundingBoxOfPath.contains(value[outer].cgPath.boundingBoxOfPath),
               let first = value[outer].nodes.first,
               value[i].cgPath.contains(CGPoint(x: first.point.x * 1000, y: first.point.y * 1000)) { outer = i }
        }
        let chosen = value.indices.filter { i in
            i == outer || (value[i].closed && value[outer].closed && value[i].nodes.allSatisfy {
                value[outer].cgPath.contains(CGPoint(x: $0.point.x * 1000, y: $0.point.y * 1000))
            })
        }
        let ids = Set(chosen.flatMap { value[$0].nodes.map(\.id) })
        selection = adding ? selection.union(ids) : ids
    }
    static func resized(_ paths: [FontLabVectorPath], selection: Set<UUID>, anchor: FontLabPoint, sx: Double, sy: Double) -> [FontLabVectorPath] {
        var result = paths
        func point(_ p: FontLabPoint) -> FontLabPoint {
            var p = p; p.x = anchor.x + (p.x-anchor.x)*sx; p.y = anchor.y + (p.y-anchor.y)*sy; return p
        }
        for p in result.indices { for n in result[p].nodes.indices where selection.contains(result[p].nodes[n].id) {
            result[p].nodes[n].point = point(result[p].nodes[n].point)
            result[p].nodes[n].incoming = result[p].nodes[n].incoming.map(point)
            result[p].nodes[n].outgoing = result[p].nodes[n].outgoing.map(point)
        } }
        return result
    }
    func setPenWidth(_ units: Double) {
        guard units.isFinite, (2...200).contains(units) else { return }
        var next = glyph
        for i in next.strokes.indices where !next.strokes[i].points.isEmpty { next.strokes[i].width = units / 1000 }
        if next != glyph { glyph = next; onCommit(next) }
    }
    func modifySelected(_ change: (inout FontLabVectorNode, Int, FontLabVectorPath) -> Void) {
        var value=paths
        for p in value.indices { let original=value[p]; for n in value[p].nodes.indices where selection.contains(value[p].nodes[n].id) { change(&value[p].nodes[n],n,original) } }
        _=apply(value)
    }
    func move(dx:Double,dy:Double) {
        modifySelected { node,_,_ in
            node.point.x += dx;node.point.y += dy
            if node.incoming != nil { node.incoming!.x += dx;node.incoming!.y += dy }
            if node.outgoing != nil { node.outgoing!.x += dx;node.outgoing!.y += dy }
        }
    }
    func setCoordinate(_ value: Double, x: Bool) {
        guard value.isFinite, !selection.isEmpty else { return }
        let b=selectedBounds
        move(dx:x ? value/(glyph.resolvedDesignWidth*1000)-b.minX : 0, dy:x ? 0 : value/1000+metrics.baseline-b.minY)
    }
    func smooth(_ enabled: Bool) {
        var value=paths
        for p in value.indices { for n in value[p].nodes.indices where selection.contains(value[p].nodes[n].id) { value[p].setSmooth(n,enabled) } }
        _=apply(value)
    }
    func lines() {
        var value=paths
        for p in value.indices { for n in 0..<value[p].segmentCount {
            let next=(n+1)%value[p].nodes.count
            if selection.contains(value[p].nodes[n].id) && selection.contains(value[p].nodes[next].id) {
                value[p].nodes[n].outgoing=nil;value[p].nodes[next].incoming=nil
                value[p].nodes[n].smooth=false;value[p].nodes[next].smooth=false
            }
        } }
        _=apply(value)
    }
    func curves() {
        var value=paths
        for p in value.indices { for n in 0..<value[p].segmentCount {
            let next=(n+1)%value[p].nodes.count
            if selection.contains(value[p].nodes[n].id) && selection.contains(value[p].nodes[next].id) && !value[p].isCurve(n) {
                let a=value[p].nodes[n].point,b=value[p].nodes[next].point
                value[p].nodes[n].outgoing=FontLabVectorMath.mix(a,b,1/3);value[p].nodes[next].incoming=FontLabVectorMath.mix(a,b,2/3)
            }
        } }
        _=apply(value)
    }
    func pathCommand(_ command: String) {
        var value=paths
        for p in value.indices where value[p].nodes.contains(where:{selection.contains($0.id)}) {
            if command == "reverse" { value[p].reverse() }
            if command == "counter",value[p].closed,let first=value[p].nodes.first {
                func area(_ path:FontLabVectorPath)->Double {
                    let points=path.flattened();guard points.count>=3 else {return 0}
                    return points.indices.reduce(0) { sum,i in let a=points[i],b=points[(i+1)%points.count];return sum+a.x*b.y-b.x*a.y }
                }
                let parents=value.indices.filter { $0 != p && value[$0].closed && value[$0].cgPath.contains(CGPoint(x:first.point.x*1000,y:first.point.y*1000)) }
                if let parent=parents.min(by:{abs(area(value[$0]))<abs(area(value[$1]))}) {
                    if area(value[parent])*area(value[p])>0 {value[p].reverse()}
                } else {message="A counter needs a closed contour inside another contour."}
            }
            if command == "close", value[p].nodes.count >= 3 { value[p].closed=true }
            if command == "open" { value[p].closed=false }
        }
        if apply(value) { activePath=nil }
    }
    func deleteSelection() {
        var value=paths
        for p in value.indices {
            let removed=Set(value[p].nodes.filter { selection.contains($0.id) }.map(\.id))
            guard !removed.isEmpty else { continue }
            // Join surviving anchors with straight segments across removed nodes;
            // do not leave unrelated old handles curling into the deleted area.
            let original=value[p].nodes
            value[p].nodes=original.enumerated().compactMap { i,node in
                guard !removed.contains(node.id) else { return nil }
                var node=node
                if removed.contains(original[(i+original.count-1)%original.count].id) { node.incoming=nil;node.smooth=false }
                if removed.contains(original[(i+1)%original.count].id) { node.outgoing=nil;node.smooth=false }
                return node
            }
            if value[p].nodes.count < 3 { value[p].closed=false }
        }
        value.removeAll {$0.nodes.isEmpty}
        _=apply(value);selection=[];activePath=nil
    }
    func duplicate() {
        let chosen=paths.filter { $0.nodes.contains { selection.contains($0.id) } }
        var copies=chosen.map { path -> FontLabVectorPath in
            var p=path;p.id=UUID();for i in p.nodes.indices {p.nodes[i].id=UUID()};return p
        }
        for p in copies.indices { for n in copies[p].nodes.indices {
            copies[p].nodes[n].point.x += 0.025
            if copies[p].nodes[n].incoming != nil { copies[p].nodes[n].incoming!.x += 0.025 }
            if copies[p].nodes[n].outgoing != nil { copies[p].nodes[n].outgoing!.x += 0.025 }
        } }
        if apply(paths+copies) { selection=Set(copies.flatMap(\.nodes).map(\.id)) }
    }
    func transform(scaleX:Double=1,scaleY:Double=1,angle:Double=0) {
        let b=selectedBounds,w=glyph.resolvedDesignWidth
        let c=cos(angle),s=sin(angle)
        func convert(_ p:FontLabPoint)->FontLabPoint {
            let x=(p.x-b.midX)*w*scaleX,y=(p.y-b.midY)*scaleY
            return FontLabPoint(x:b.midX+(x*c-y*s)/w,y:b.midY+x*s+y*c)
        }
        modifySelected {node,_,_ in node.point=convert(node.point);node.incoming=node.incoming.map(convert);node.outgoing=node.outgoing.map(convert)}
    }
    func align(horizontal:Bool) {
        let b=selectedBounds
        modifySelected {node,_,_ in
            let dx=horizontal ? 0 : b.midX-node.point.x,dy=horizontal ? b.midY-node.point.y : 0
            node.point.x += dx;node.point.y += dy
            if node.incoming != nil {node.incoming!.x += dx;node.incoming!.y += dy}
            if node.outgoing != nil {node.outgoing!.x += dx;node.outgoing!.y += dy}
        }
    }
    func addExtrema() {
        var value=paths
        for p in value.indices where selection.isEmpty || value[p].nodes.contains(where:{selection.contains($0.id)}) {
            for i in (0..<value[p].segmentCount).reversed() where value[p].isCurve(i) {
                let points=value[p].controls(i)
                func roots(_ v:[Double])->[Double] {
                    let a = -v[0]+3*v[1]-3*v[2]+v[3],b=2*(v[0]-2*v[1]+v[2]),c=v[1]-v[0]
                    if abs(a)<1e-10 {return abs(b)<1e-10 ? [] : [-c/b]}
                    let d=b*b-4*a*c;return d<0 ? [] : [(-b+sqrt(d))/(2*a),(-b-sqrt(d))/(2*a)]
                }
                let ts=(roots(points.map(\.x))+roots(points.map(\.y))).filter {$0>0.001 && $0<0.999}.sorted()
                var last=0.0,offset=0
                for t in ts where t-last>0.001 { value[p].insertNode(segment:i+offset,t:(t-last)/(1-last));last=t;offset+=1 }
            }
        }
        _=apply(value)
    }
    func boolean(_ operation: String) {
        let chosen=paths.filter { selection.isEmpty || $0.nodes.contains { selection.contains($0.id) } }
        guard !chosen.isEmpty, chosen.allSatisfy(\.closed) else {message="Close the selected contours before combining shapes.";return}
        let result: CGPath
        if operation == "overlap" {
            let combined=CGMutablePath();chosen.forEach {combined.addPath($0.cgPath)}
            result=combined.normalized(using:.winding)
        } else {
            guard chosen.count>=2 else {message="Select at least two closed contours.";return}
            var combined=chosen[0].cgPath
            for path in chosen.dropFirst() {
                combined = operation == "subtract" ? combined.subtracting(path.cgPath,using:.winding) : combined.intersection(path.cgPath,using:.winding)
            }
            result=combined
        }
        let replacement=FontLabVectorPath.from(result),ids=Set(chosen.map(\.id))
        if apply(paths.filter {!ids.contains($0.id)}+replacement) {selection=Set(replacement.flatMap(\.nodes).map(\.id));message="Contours combined. Undo restores the original shapes."}
    }
    func copyPaths() {
        let selected=paths.filter { $0.nodes.contains { selection.contains($0.id) } }
        guard !selected.isEmpty, let data=try? JSONEncoder().encode(selected) else {return}
        NSPasteboard.general.clearContents();NSPasteboard.general.setData(data,forType:.init("local.fontshelf.vector-paths"))
        message="Copied \(selected.count) contours. Paste into any glyph."
    }
    func pastePaths() {
        guard let data=NSPasteboard.general.data(forType:.init("local.fontshelf.vector-paths")),data.count<8_000_000,
              var added=try? JSONDecoder().decode([FontLabVectorPath].self,from:data),added.allSatisfy(\.isValid) else {message="Copy vector contours from a Letterform Editor glyph first.";return}
        for p in added.indices {added[p].id=UUID();for n in added[p].nodes.indices {added[p].nodes[n].id=UUID()}}
        if apply(paths+added) {selection=Set(added.flatMap(\.nodes).map(\.id))}
    }
}

struct FontLabVectorEditorView: View {
    let glyph: FontLabGlyph
    let metrics: FontLabMetrics
    let componentStrokes: [FontLabStroke]
    let onChange: (FontLabGlyph)->Void
    let onUndo: ()->Void
    let onRedo: ()->Void
    let onPreviewInkChange: (String)->Void
    @StateObject private var editor: FontLabVectorEditor
    @State private var x = ""
    @State private var y = ""
    @State private var scale = "100"
    @State private var angle = "0"
    init(glyph:FontLabGlyph,metrics:FontLabMetrics,componentStrokes:[FontLabStroke]=[],previewInkHex:String?=nil,onChange:@escaping(FontLabGlyph)->Void,onUndo:@escaping()->Void,onRedo:@escaping()->Void,onPreviewInkChange:@escaping(String)->Void={_ in}) {
        self.glyph=glyph;self.metrics=metrics;self.componentStrokes=componentStrokes;self.onChange=onChange;self.onUndo=onUndo;self.onRedo=onRedo;self.onPreviewInkChange=onPreviewInkChange
        let value=FontLabVectorEditor(glyph:glyph,metrics:metrics)
        if let previewInkHex { value.inkColor=Color(nsColor:NSColor(hex:previewInkHex)) }
        _editor=StateObject(wrappedValue:value)
    }
    var body: some View {
        VStack(alignment:.leading,spacing:8) {
            HStack(spacing:6) {
                ForEach(FontLabVectorTool.allCases) { tool in
                    Button {editor.tool=tool;editor.activePath=nil} label: { Image(systemName:tool.icon).frame(width:28,height:24) }
                        .buttonStyle(.bordered).tint(editor.tool == tool ? .accentColor : .secondary).help(tool.rawValue).accessibilityLabel(tool.rawValue)
                }
                Picker("Selection", selection: $editor.objectSelection) { Text("Objects").tag(true); Text("Nodes").tag(false) }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 140)
                Spacer(minLength:0)
                Menu("Paths") {
                    Button("Smooth nodes") {editor.smooth(true)}.disabled(editor.selection.isEmpty)
                    Button("Corner nodes") {editor.smooth(false)}.disabled(editor.selection.isEmpty)
                    Button("Make selected segments straight") {editor.lines()}.disabled(editor.selection.count<2)
                    Button("Add curve handles") {editor.curves()}.disabled(editor.selection.count<2)
                    Divider()
                    Button("Close contours") {editor.pathCommand("close")}.disabled(editor.selection.isEmpty)
                    Button("Open contours") {editor.pathCommand("open")}.disabled(editor.selection.isEmpty)
                    Button("Make counter") {editor.pathCommand("counter")}.disabled(editor.selection.isEmpty)
                    Button("Reverse contours") {editor.pathCommand("reverse")}.disabled(editor.selection.isEmpty)
                    Button("Remove overlaps") {editor.boolean("overlap")}.disabled(editor.paths.isEmpty)
                    Button("Subtract later contours") {editor.boolean("subtract")}.disabled(editor.selection.isEmpty)
                    Button("Intersect contours") {editor.boolean("intersect")}.disabled(editor.selection.isEmpty)
                    Button("Add extrema") {editor.addExtrema()}.disabled(editor.paths.isEmpty)
                    Divider()
                    Button("Duplicate contours") {editor.duplicate()}.disabled(editor.selection.isEmpty)
                    Button("Copy contours") {editor.copyPaths()}.disabled(editor.selection.isEmpty)
                    Button("Paste contours") {editor.pastePaths()}
                    Button("Delete nodes",role:.destructive) {editor.deleteSelection()}.disabled(editor.selection.isEmpty)
                }.fixedSize()
            }
            FontLabVectorCanvas(editor:editor,onChange:onChange,onUndo:onUndo,onRedo:onRedo)
                .frame(minWidth:340,maxWidth:.infinity,minHeight:340,maxHeight:.infinity)
                .background(Color(nsColor:.textBackgroundColor),in:RoundedRectangle(cornerRadius:12))
                .clipShape(RoundedRectangle(cornerRadius:12))
                .overlay(RoundedRectangle(cornerRadius:12).strokeBorder(Color.primary.opacity(0.15)))
            HStack(spacing:10) {
                Toggle("Grid",isOn:$editor.grid);Toggle("Snap",isOn:$editor.snap);Toggle("Fill",isOn:$editor.fill)
                Spacer(minLength:0)
                Button("−") {editor.zoom=max(0.5,editor.zoom/1.25)}.help("Zoom out")
                Text("\(Int(editor.zoom*100))%").monospacedDigit().frame(width:42)
                Button("+") {editor.zoom=min(8,editor.zoom*1.25)}.help("Zoom in")
                Button("Fit") {editor.fit()}
            }.toggleStyle(.checkbox).font(.caption)
            HStack(spacing:6) {
                Text("\(editor.selection.count) nodes").foregroundStyle(.secondary).frame(width:65,alignment:.leading)
                Text("X");TextField("X",text:$x).frame(width:55).onSubmit {if let v=Double(x) {editor.setCoordinate(v,x:true)}}
                Text("Y");TextField("Y",text:$y).frame(width:55).onSubmit {if let v=Double(y) {editor.setCoordinate(v,x:false)}}
                Spacer(minLength:0)
                Menu("Transform") {
                    Button("Align horizontally") {editor.align(horizontal:true)}
                    Button("Align vertically") {editor.align(horizontal:false)}
                    Button("Flip horizontally") {editor.transform(scaleX:-1)}
                    Button("Flip vertically") {editor.transform(scaleY:-1)}
                }.disabled(editor.selection.isEmpty).fixedSize()
            }.textFieldStyle(.roundedBorder).font(.caption)
            HStack(spacing:6) {
                Button("Select all") { editor.selectAll() }.help("Select all outlines (⌘A)")
                Text("Scale %");TextField("100",text:$scale).frame(width:50)
                Button("Scale") {if let v=Double(scale),v>0,v<=1000 {editor.transform(scaleX:v/100,scaleY:v/100)}}.disabled(editor.selection.isEmpty)
                Text("Rotate °");TextField("0",text:$angle).frame(width:45)
                Button("Rotate") {if let v=Double(angle),v.isFinite {editor.transform(angle:v * .pi/180)}}.disabled(editor.selection.isEmpty)
                Spacer(minLength:0)
            }.textFieldStyle(.roundedBorder).font(.caption)
            HStack {
                ColorPicker("Preview ink", selection: $editor.inkColor, supportsOpacity: false).fixedSize()
                    .help("Canvas preview color only. Font exports remain monochrome; choose text color in Spaces or the app using the font.")
                if let stroke = editor.glyph.strokes.first(where: { !$0.points.isEmpty }) {
                    Text("Pen width")
                    TextField("Units", value: Binding(get: { stroke.width * 1000 }, set: { editor.setPenWidth($0) }), format: .number)
                        .textFieldStyle(.roundedBorder).frame(width: 55)
                    Text("units").foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }.font(.caption)
            Text(editor.objectSelection && editor.tool == .select ? "Click a shape to move it. Drag a box corner to resize; hold Shift to keep proportions. Nodes edits individual points." : editor.openCount>0 ? "\(editor.openCount) open contour(s). Close them before exporting a font." : editor.message)
                .font(.caption2).foregroundStyle(editor.openCount>0 ? .orange : .secondary).fixedSize(horizontal:false,vertical:true)
        }
        .onChange(of:glyph) { editor.receive($0);updateCoordinates() }
        .onAppear { editor.componentStrokes=componentStrokes }
        .onChange(of:componentStrokes) {editor.componentStrokes=$0}
        .onChange(of:metrics) {editor.metrics=$0}
        .onChange(of:editor.selection) {_ in updateCoordinates()}
        .onChange(of:editor.glyph) {_ in updateCoordinates()}
        .onChange(of:editor.inkColor) { color in onPreviewInkChange(NSColor(color).rgbHex) }
    }
    private func updateCoordinates() {
        guard !editor.selection.isEmpty else {x="";y="";return}
        x=String(format:"%.1f",editor.selectedBounds.minX*editor.glyph.resolvedDesignWidth*1000)
        y=String(format:"%.1f",(editor.selectedBounds.minY-editor.metrics.baseline)*1000)
    }
}

private struct FontLabVectorCanvas: NSViewRepresentable {
    @ObservedObject var editor:FontLabVectorEditor
    let onChange:(FontLabGlyph)->Void
    let onUndo:()->Void
    let onRedo:()->Void
    func makeNSView(context:Context)->FontLabVectorNSView {FontLabVectorNSView(editor:editor)}
    func updateNSView(_ view:FontLabVectorNSView,context:Context) {
        editor.onCommit=onChange;editor.onUndo=onUndo;editor.onRedo=onRedo;view.needsDisplay=true
    }
}
