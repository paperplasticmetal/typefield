import AppKit

/// SVG numbers use fixed POSIX decimal rounding. Keep the configured formatter
/// local to one export so individual coordinates do not rebuild its ICU state.
struct FontLabSVGNumberFormatter {
    private let formatter: NumberFormatter
    private let fractionDigits: Int

    init(fractionDigits: Int) {
        self.fractionDigits = fractionDigits
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = fractionDigits
        formatter.maximumFractionDigits = fractionDigits
        formatter.roundingMode = .halfEven
        self.formatter = formatter
    }

    func string(_ value: Double) -> String {
        formatter.string(from: NSNumber(value: value)) ??
            String(format: "%.*f", locale: Locale(identifier: "en_US_POSIX"), fractionDigits, value)
    }
}

/// Cubic outlines stay editable in project files. Coordinates use the existing
/// glyph design box; handles may extend beyond it while anchors stay inside.
struct FontLabVectorNode: Codable, Equatable, Identifiable {
    var id = UUID()
    var point: FontLabPoint
    var incoming: FontLabPoint? = nil
    var outgoing: FontLabPoint? = nil
    var smooth = false
    var isValid: Bool {
        point.isValid && [incoming, outgoing].compactMap { $0 }.allSatisfy {
            $0.x.isFinite && $0.y.isFinite && (-2...3).contains($0.x) && (-2...3).contains($0.y)
        }
    }
}

struct FontLabVectorPath: Codable, Equatable, Identifiable {
    var id = UUID()
    var nodes: [FontLabVectorNode]
    var closed = false
    var isValid: Bool {
        nodes.count >= (closed ? 3 : 1) && nodes.count <= 30_000 &&
        Set(nodes.map(\.id)).count == nodes.count && nodes.allSatisfy(\.isValid)
    }
    var segmentCount: Int { closed ? nodes.count : max(0, nodes.count - 1) }
    func controls(_ index: Int) -> [FontLabPoint] {
        let a = nodes[index], b = nodes[(index + 1) % nodes.count]
        return [a.point, a.outgoing ?? a.point, b.incoming ?? b.point, b.point]
    }
    func isCurve(_ index: Int) -> Bool { nodes[index].outgoing != nil || nodes[(index + 1) % nodes.count].incoming != nil }

    func bezier(in rect: CGRect) -> NSBezierPath {
        let result = NSBezierPath()
        func mapped(_ p: FontLabPoint) -> NSPoint { NSPoint(x: rect.minX + p.x * rect.width, y: rect.minY + p.y * rect.height) }
        guard let first = nodes.first else { return result }
        result.move(to: mapped(first.point))
        for i in 0..<segmentCount {
            let p = controls(i)
            if isCurve(i) { result.curve(to: mapped(p[3]), controlPoint1: mapped(p[1]), controlPoint2: mapped(p[2])) }
            else { result.line(to: mapped(p[3])) }
        }
        if closed { result.close() }
        return result
    }

    /// Adaptive export approximation, independent of canvas zoom. The editable
    /// document and SVG retain the exact cubic handles.
    func flattened(tolerance: Double = 0.00015) -> [FontLabPoint] {
        guard let first = nodes.first else { return [] }
        var result = [first.point]
        func flatten(_ p: [FontLabPoint], _ depth: Int) {
            let chord = hypot(p[3].x-p[0].x, p[3].y-p[0].y)
            let polygon = hypot(p[1].x-p[0].x,p[1].y-p[0].y) + hypot(p[2].x-p[1].x,p[2].y-p[1].y) + hypot(p[3].x-p[2].x,p[3].y-p[2].y)
            if depth >= 12 || polygon - chord < tolerance { result.append(p[3]); return }
            let halves = FontLabVectorMath.split(p, at: 0.5)
            flatten(halves.0, depth + 1); flatten(halves.1, depth + 1)
        }
        for i in 0..<segmentCount {
            if isCurve(i) { flatten(controls(i), 0) } else { result.append(controls(i)[3]) }
        }
        if closed, result.count > 1 { result.removeLast() }
        return result
    }

    mutating func insertNode(segment: Int, t: Double) {
        guard segment >= 0, segment < segmentCount else { return }
        let next = (segment + 1) % nodes.count
        let p = controls(segment)
        var node: FontLabVectorNode
        if isCurve(segment) {
            let (a,b) = FontLabVectorMath.split(p, at: min(0.999, max(0.001, t)))
            nodes[segment].outgoing = a[1]; nodes[next].incoming = b[2]
            node = FontLabVectorNode(point: a[3], incoming: a[2], outgoing: b[1], smooth: true)
        } else { node = FontLabVectorNode(point: FontLabVectorMath.mix(p[0], p[3], t)) }
        nodes.insert(node, at: segment + 1)
    }
    mutating func reverse() {
        nodes.reverse()
        for i in nodes.indices { let handle = nodes[i].incoming; nodes[i].incoming = nodes[i].outgoing; nodes[i].outgoing = handle }
    }
    mutating func setSmooth(_ index: Int, _ value: Bool) {
        guard nodes.indices.contains(index) else { return }
        nodes[index].smooth = value
        guard value, nodes.count > 1 else { return }
        let p = nodes[index].point
        // Open endpoints have only one adjacent segment. Wrapping around to
        // the far endpoint can point a new handle away from its own curve (and
        // gives a two-node open path a zero-length tangent).
        let before = !closed && index == 0 ? p : nodes[(index + nodes.count - 1) % nodes.count].point
        let after = !closed && index == nodes.count - 1 ? p : nodes[(index + 1) % nodes.count].point
        let dx = after.x-before.x, dy = after.y-before.y, length = max(0.00001,hypot(dx,dy))
        let a = nodes[index].incoming.map { hypot($0.x-p.x,$0.y-p.y) } ?? hypot(before.x-p.x,before.y-p.y)/3
        let b = nodes[index].outgoing.map { hypot($0.x-p.x,$0.y-p.y) } ?? hypot(after.x-p.x,after.y-p.y)/3
        if closed || index > 0 { nodes[index].incoming = FontLabPoint(x:p.x-dx/length*a,y:p.y-dy/length*a) }
        if closed || index < nodes.count-1 { nodes[index].outgoing = FontLabPoint(x:p.x+dx/length*b,y:p.y+dy/length*b) }
    }
    func svg(xScale: Double, formatter: FontLabSVGNumberFormatter? = nil) -> String {
        let formatter = formatter ?? FontLabSVGNumberFormatter(fractionDigits: 4)
        func p(_ p: FontLabPoint) -> String { formatter.string(p.x*xScale*1000) + "," + formatter.string((1-p.y)*1000) }
        guard let first = nodes.first else { return "" }
        var d = "M" + p(first.point)
        for i in 0..<segmentCount {
            let c = controls(i)
            d += isCurve(i) ? " C\(p(c[1])) \(p(c[2])) \(p(c[3]))" : " L\(p(c[3]))"
        }
        return d + (closed ? " Z" : "")
    }
}

enum FontLabVectorMath {
    static func mix(_ a: FontLabPoint,_ b: FontLabPoint,_ t: Double) -> FontLabPoint { FontLabPoint(x:a.x+(b.x-a.x)*t,y:a.y+(b.y-a.y)*t) }
    static func split(_ p: [FontLabPoint], at t: Double) -> ([FontLabPoint],[FontLabPoint]) {
        let a=mix(p[0],p[1],t), b=mix(p[1],p[2],t), c=mix(p[2],p[3],t)
        let d=mix(a,b,t),e=mix(b,c,t),f=mix(d,e,t)
        return ([p[0],a,d,f],[f,e,c,p[3]])
    }
    static func evaluate(_ p: [FontLabPoint],_ t: Double) -> FontLabPoint { split(p, at:t).0[3] }
    static func rectangle(_ r: CGRect, ellipse: Bool) -> FontLabVectorPath {
        if !ellipse {
            return FontLabVectorPath(nodes: [FontLabPoint(x:r.minX,y:r.minY),FontLabPoint(x:r.maxX,y:r.minY),FontLabPoint(x:r.maxX,y:r.maxY),FontLabPoint(x:r.minX,y:r.maxY)].map { FontLabVectorNode(point:$0) },closed:true)
        }
        let k=0.5522847498307936, x=r.midX,y=r.midY,a=r.width/2,b=r.height/2
        return FontLabVectorPath(nodes:[
            FontLabVectorNode(point:.init(x:x+a,y:y),incoming:.init(x:x+a,y:y-b*k),outgoing:.init(x:x+a,y:y+b*k),smooth:true),
            FontLabVectorNode(point:.init(x:x,y:y+b),incoming:.init(x:x+a*k,y:y+b),outgoing:.init(x:x-a*k,y:y+b),smooth:true),
            FontLabVectorNode(point:.init(x:x-a,y:y),incoming:.init(x:x-a,y:y+b*k),outgoing:.init(x:x-a,y:y-b*k),smooth:true),
            FontLabVectorNode(point:.init(x:x,y:y-b),incoming:.init(x:x-a*k,y:y-b),outgoing:.init(x:x+a*k,y:y-b),smooth:true)
        ],closed:true)
    }
    static func bounds(_ points: [FontLabPoint]) -> CGRect {
        guard let a=points.first else { return .zero }
        return points.dropFirst().reduce(CGRect(x:a.x,y:a.y,width:0,height:0)) { r,p in
            CGRect(x:min(r.minX,p.x),y:min(r.minY,p.y),width:max(r.maxX,p.x)-min(r.minX,p.x),height:max(r.maxY,p.y)-min(r.minY,p.y))
        }
    }
    static func paths(in glyph: FontLabGlyph) -> [FontLabVectorPath] {
        glyph.strokes.flatMap { stroke in
            stroke.vectorPaths ?? (stroke.contours ?? []).enumerated().map { index, points in
                // Stable IDs across redraws until the first vector edit converts
                // legacy polygon contours. Avoid rewriting saved projects on view.
                var bytes = stroke.id.uuid; withUnsafeMutableBytes(of:&bytes) { buffer in
                    buffer[14] ^= UInt8((index >> 8) & 255); buffer[15] ^= UInt8(index & 255)
                }
                let pathID=UUID(uuid:bytes)
                return FontLabVectorPath(id:pathID,nodes:points.enumerated().map { n,p in
                    var id=pathID.uuid; withUnsafeMutableBytes(of:&id) { buffer in buffer[10] ^= UInt8((n >> 8)&255); buffer[11] ^= UInt8(n&255) }
                    return FontLabVectorNode(id:UUID(uuid:id),point:p)
                },closed:true)
            }
        }
    }
    static func pathGroups(in glyph: FontLabGlyph) -> [[UUID]] {
        glyph.strokes.filter { $0.contours != nil || $0.vectorPaths != nil }.map { stroke in
            var source = glyph; source.strokes = [stroke]
            return paths(in: source).map(\.id)
        }
    }
    /// Stroke groups paint independently. Merging them during an ordinary node
    /// edit can turn an overlap between opposite windings into a new hole.
    /// Explicit path groups are reserved for operations that combine contours.
    static func replacingPaths(in glyph: FontLabGlyph, with paths: [FontLabVectorPath], pathGroups: [[UUID]] = []) -> FontLabGlyph {
        let outlineIndices = glyph.strokes.indices.filter { glyph.strokes[$0].contours != nil || glyph.strokes[$0].vectorPaths != nil }
        let sourcePaths = outlineIndices.map { index -> [FontLabVectorPath] in
            var source = glyph; source.strokes = [glyph.strokes[index]]
            return self.paths(in: source)
        }
        var owners: [UUID: Int] = [:]
        for (group, paths) in sourcePaths.enumerated() {
            for path in paths { owners[path.id] = group }
        }
        // A fresh path joins the last outline group, preserving the existing
        // drawing workflow for making a counter inside a shape. Splits retain
        // their original group through the surviving node identities.
        let existingCount = max(1, outlineIndices.count)
        var groups = Array(repeating: [FontLabVectorPath](), count: existingCount + pathGroups.count)
        var explicitOwners: [UUID: Int] = [:]
        for (group, ids) in pathGroups.enumerated() {
            let idSet = Set(ids)
            // Reuse a source stroke when the explicit group contains all of
            // its paths. Reapplying Make counter then remains a true no-op.
            let reusable = outlineIndices.indices.first { owner in owners.filter { $0.value == owner }.keys.allSatisfy { idSet.contains($0) } }
            for id in ids { explicitOwners[id] = reusable ?? existingCount + group }
        }
        // Ordinary drags retain every path identity. Only a new or split path
        // needs the more expensive per-node lookup to recover its stroke group.
        var nodeOwners: [UUID: Int] = [:]
        if paths.contains(where: { explicitOwners[$0.id] == nil && owners[$0.id] == nil }) {
            for (group, paths) in sourcePaths.enumerated() {
                for path in paths { for node in path.nodes { nodeOwners[node.id] = group } }
            }
        }
        for path in paths {
            let owner = explicitOwners[path.id] ?? owners[path.id] ?? path.nodes.lazy.compactMap { nodeOwners[$0.id] }.first ?? existingCount - 1
            groups[owner].append(path)
        }
        var result = glyph, strokes: [FontLabStroke] = []
        let outlineOwners = Dictionary(uniqueKeysWithValues: outlineIndices.enumerated().map { ($0.element, $0.offset) })
        for (index, source) in glyph.strokes.enumerated() {
            guard let group = outlineOwners[index] else { strokes.append(source); continue }
            guard !groups[group].isEmpty else { continue }
            var stroke = source; stroke.points = []; stroke.contours = nil; stroke.vectorPaths = groups[group]
            strokes.append(stroke)
        }
        if outlineIndices.isEmpty, !groups[0].isEmpty { strokes.append(FontLabStroke(vectorPaths: groups[0])) }
        for group in groups.dropFirst(existingCount) where !group.isEmpty { strokes.append(FontLabStroke(vectorPaths: group)) }
        result.strokes = strokes
        if !paths.isEmpty, result.contourDesignWidth == nil { result.contourDesignWidth = glyph.resolvedDesignWidth }
        return result
    }
    static func draw(_ paths: [FontLabVectorPath], in rect: CGRect, color: NSColor, showOpen: Bool = true) {
        color.setFill();color.setStroke()
        let compound=NSBezierPath(); compound.windingRule = .nonZero
        for path in paths where path.closed { compound.append(path.bezier(in:rect)) }
        compound.fill()
        if showOpen { for path in paths where !path.closed { let p=path.bezier(in:rect);p.lineWidth=1.5;p.stroke() } }
    }
}

extension FontLabVectorPath {
    /// Boolean operations use font-sized coordinates for Core Graphics' numeric
    /// tolerances, then return editable cubic nodes rather than raster outlines.
    var cgPath: CGPath {
        let result=CGMutablePath()
        func p(_ value:FontLabPoint)->CGPoint {CGPoint(x:value.x*1000,y:value.y*1000)}
        guard let first=nodes.first else {return result}
        result.move(to:p(first.point))
        for i in 0..<segmentCount {let c=controls(i);if isCurve(i) {result.addCurve(to:p(c[3]),control1:p(c[1]),control2:p(c[2]))} else {result.addLine(to:p(c[3]))}}
        if closed {result.closeSubpath()};return result
    }
    static func from(_ path:CGPath)->[FontLabVectorPath] {
        var result:[FontLabVectorPath]=[],nodes:[FontLabVectorNode]=[]
        func point(_ p:CGPoint)->FontLabPoint {FontLabPoint(x:abs(p.x)<1e-7 ? 0:abs(p.x-1000)<1e-7 ? 1:p.x/1000,y:abs(p.y)<1e-7 ? 0:abs(p.y-1000)<1e-7 ? 1:p.y/1000)}
        path.applyWithBlock { pointer in
            let element=pointer.pointee
            switch element.type {
            case .moveToPoint:
                if !nodes.isEmpty {result.append(.init(nodes:nodes))};nodes=[.init(point:point(element.points[0]))]
            case .addLineToPoint:nodes.append(.init(point:point(element.points[0])))
            case .addCurveToPoint:
                guard !nodes.isEmpty else {return}
                nodes[nodes.count-1].outgoing=point(element.points[0]);nodes.append(.init(point:point(element.points[2]),incoming:point(element.points[1])))
            case .addQuadCurveToPoint:
                guard let previous=nodes.last else {return}
                let control=point(element.points[0]),end=point(element.points[1])
                nodes[nodes.count-1].outgoing=FontLabVectorMath.mix(previous.point,control,2/3)
                nodes.append(.init(point:end,incoming:FontLabVectorMath.mix(end,control,2/3)))
            case .closeSubpath:
                if nodes.count>1,let first=nodes.first,let last=nodes.last,hypot(first.point.x-last.point.x,first.point.y-last.point.y)<1e-8 {
                    nodes[0].incoming=last.incoming;nodes.removeLast()
                }
                var contour=FontLabVectorPath(nodes:nodes,closed:true)
                // Boolean results can enclose an area with only one or two
                // cubic segments. Split them exactly to meet our anchor minimum.
                while !contour.nodes.isEmpty && contour.nodes.count<3,
                      let segment=(0..<contour.segmentCount).first(where:{contour.isCurve($0)}) {
                    contour.insertNode(segment:segment,t:0.5)
                }
                if contour.nodes.count>=3 {result.append(contour)};nodes=[]
            @unknown default:break
            }
        }
        if !nodes.isEmpty {result.append(.init(nodes:nodes))}
        return result
    }
}
