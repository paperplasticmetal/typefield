import AppKit

/// Conservative fitting of imported polygons. A candidate must stay within the
/// chosen deviation, retain winding/containment and introduce no crossings.
enum FontLabTraceSmoothing {
    enum Failure: LocalizedError {
        case noPolygons, tooDense, unsafe
        var errorDescription: String? {
            switch self {
            case .noPolygons: return "Select a glyph with closed polygon outlines. Existing Bézier curves and pen strokes are kept intact."
            case .tooDense: return "This outline is too dense for the smoothing preview (6,000 polygon points maximum)."
            case .unsafe: return "No safe curve fit was found at this tolerance. The original outline is unchanged."
            }
        }
    }
    static func fit(_ glyph: FontLabGlyph, units: Double) throws -> FontLabGlyph {
        let paths = FontLabVectorMath.paths(in: glyph)
        let eligible = paths.filter { $0.closed && $0.nodes.allSatisfy { $0.incoming == nil && $0.outgoing == nil } }
        guard !eligible.isEmpty else { throw Failure.noPolygons }
        guard eligible.reduce(0, { $0 + $1.nodes.count }) <= 6000 else { throw Failure.tooDense }
        let width = glyph.resolvedDesignWidth, tolerance = min(3, max(0.25, units)) / 1000
        func physical(_ p: FontLabPoint) -> FontLabPoint { .init(x: p.x * width, y: p.y) }
        func normalized(_ p: FontLabPoint) -> FontLabPoint { .init(x: p.x / width, y: p.y) }
        var candidates = paths
        var changed = false
        for index in candidates.indices where eligible.contains(where: { $0.id == candidates[index].id }) {
            let original = candidates[index].nodes.map { physical($0.point) }
            guard original.count > 4 else { continue }
            let reduced = FontLabRemixEngine.simplified(original, tolerance: tolerance * 0.35)
            var accepted: FontLabVectorPath?
            for tension in [1.0, 0.6, 0.3, 0.0] {
                var nodes = reduced.map { FontLabVectorNode(point: normalized($0)) }
                for i in nodes.indices {
                    let before = reduced[(i + reduced.count - 1) % reduced.count], p = reduced[i], after = reduced[(i + 1) % reduced.count]
                    let a = hypot(p.x-before.x,p.y-before.y), b = hypot(after.x-p.x,after.y-p.y)
                    guard a > 1e-8, b > 1e-8 else { continue }
                    let turn = ((p.x-before.x)*(after.x-p.x)+(p.y-before.y)*(after.y-p.y))/(a*b)
                    guard turn > 0.65, tension > 0 else { continue }
                    let tx = (p.x-before.x)/a + (after.x-p.x)/b, ty = (p.y-before.y)/a + (after.y-p.y)/b
                    let length = max(1e-10,hypot(tx,ty)), handle = min(a,b)/3*tension
                    nodes[i].incoming = normalized(.init(x:p.x-tx/length*handle,y:p.y-ty/length*handle))
                    nodes[i].outgoing = normalized(.init(x:p.x+tx/length*handle,y:p.y+ty/length*handle))
                    nodes[i].smooth = true
                }
                let candidate = FontLabVectorPath(id: paths[index].id, nodes:nodes, closed:true)
                let fitted = candidate.flattened(tolerance:0.00001).map(physical)
                guard candidate.isValid, fitted.count <= 6000, area(original)*area(fitted)>0,
                      close(original,to:fitted,within:tolerance),close(fitted,to:original,within:tolerance) else { continue }
                accepted = candidate; break
            }
            if let accepted { candidates[index] = accepted; changed = changed || accepted.nodes.count < original.count || accepted.nodes.contains { $0.smooth } }
        }
        guard changed else { throw Failure.unsafe }
        let before = paths.filter(\.closed).map { $0.flattened().map(physical) }
        let after = candidates.filter(\.closed).map { $0.flattened().map(physical) }
        guard after.reduce(0, { $0 + $1.count }) <= 6000, !crossings(after) else { throw Failure.unsafe }
        for i in before.indices { for j in before.indices where i != j {
            guard let p = before[i].first, let q = after[i].first, contains(before[j],p) == contains(after[j],q) else { throw Failure.unsafe }
        } }
        return FontLabVectorMath.replacingPaths(in: glyph, with: candidates)
    }
    private static func area(_ p: [FontLabPoint]) -> Double { p.indices.reduce(0) { sum,i in let a=p[i],b=p[(i+1)%p.count];return sum+a.x*b.y-b.x*a.y } }
    private static func contains(_ points: [FontLabPoint], _ p: FontLabPoint) -> Bool {
        let path = CGMutablePath(); guard let first=points.first else { return false }
        path.move(to:CGPoint(x:first.x*1000,y:first.y*1000));for point in points.dropFirst() {path.addLine(to:CGPoint(x:point.x*1000,y:point.y*1000))};path.closeSubpath()
        return path.contains(CGPoint(x:p.x*1000,y:p.y*1000))
    }
    private static func close(_ samples:[FontLabPoint],to polygon:[FontLabPoint],within limit:Double)->Bool {
        samples.allSatisfy { p in
            polygon.indices.contains { i in
                let a=polygon[i],b=polygon[(i+1)%polygon.count],dx=b.x-a.x,dy=b.y-a.y
                let t=min(1,max(0,((p.x-a.x)*dx+(p.y-a.y)*dy)/max(1e-20,dx*dx+dy*dy)))
                return hypot(p.x-a.x-dx*t,p.y-a.y-dy*t)<=limit
            }
        }
    }
    private static func crossings(_ contours:[[FontLabPoint]])->Bool {
        struct Edge { let a:FontLabPoint;let b:FontLabPoint;let contour:Int;let index:Int;let count:Int }
        let edges=contours.enumerated().flatMap { c,p in p.indices.map { Edge(a:p[$0],b:p[($0+1)%p.count],contour:c,index:$0,count:p.count) } }
        func side(_ a:FontLabPoint,_ b:FontLabPoint,_ p:FontLabPoint)->Double {(b.x-a.x)*(p.y-a.y)-(b.y-a.y)*(p.x-a.x)}
        for i in edges.indices { for j in edges.indices where j>i {
            let a=edges[i],b=edges[j]
            if a.contour==b.contour && (abs(a.index-b.index)<=1 || abs(a.index-b.index)==a.count-1) {continue}
            if max(a.a.x,a.b.x)<min(b.a.x,b.b.x) || max(b.a.x,b.b.x)<min(a.a.x,a.b.x) || max(a.a.y,a.b.y)<min(b.a.y,b.b.y) || max(b.a.y,b.b.y)<min(a.a.y,a.b.y) {continue}
            if side(a.a,a.b,b.a)*side(a.a,a.b,b.b)<(-1e-16) && side(b.a,b.b,a.a)*side(b.a,b.b,a.b)<(-1e-16) {return true}
        } }
        return false
    }
}
