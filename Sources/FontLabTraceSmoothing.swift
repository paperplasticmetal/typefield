import AppKit

/// Conservative fitting of imported polygons. A candidate must stay within the
/// chosen deviation, retain winding/containment and introduce no crossings.
enum FontLabTraceSmoothing {
    enum Failure: LocalizedError {
        case noPolygons, tooDense, unsafe
        var errorDescription: String? {
            switch self {
            case .noPolygons: return "Select a glyph with closed polygon outlines or dense curves (more than 32 anchors per contour). Simple Bézier curves and pen strokes are kept intact."
            case .tooDense: return "This outline is too dense for the smoothing preview (6,000 polygon points maximum)."
            case .unsafe: return "No safe curve fit was found at this tolerance. The original outline is unchanged."
            }
        }
    }
    static func fit(_ glyph: FontLabGlyph, units: Double, refitDenseCurves: Bool = false) throws -> FontLabGlyph {
        let paths = FontLabVectorMath.paths(in: glyph)
        let eligible = paths.filter { $0.closed && ($0.nodes.allSatisfy { $0.incoming == nil && $0.outgoing == nil } || (refitDenseCurves && $0.nodes.count > 32)) }
        guard !eligible.isEmpty else { throw Failure.noPolygons }
        guard eligible.reduce(0, { $0 + $1.nodes.count }) <= 6000 else { throw Failure.tooDense }
        let width = glyph.resolvedDesignWidth, tolerance = min(5, max(0.25, units)) / 1000
        func physical(_ p: FontLabPoint) -> FontLabPoint { .init(x: p.x * width, y: p.y) }
        func normalized(_ p: FontLabPoint) -> FontLabPoint { .init(x: p.x / width, y: p.y) }
        var candidates = paths
        var changed = false
        for index in candidates.indices where eligible.contains(where: { $0.id == candidates[index].id }) {
            let original = candidates[index].flattened(tolerance: 0.000001).map(physical)
            guard original.count <= 6000 else { continue }
            guard original.count > 4 else { continue }
            var accepted: FontLabVectorPath?
            // Retry more conservatively if the whole-contour distance check
            // rejects a locally fitted span (including the closing seam).
            for fraction in [0.8, 0.4, 0.2] {
                var candidate = fittedRing(original, tolerance: tolerance * fraction)
                candidate.id = paths[index].id
                for i in candidate.nodes.indices {
                    candidate.nodes[i].point = normalized(candidate.nodes[i].point)
                    candidate.nodes[i].incoming = candidate.nodes[i].incoming.map(normalized)
                    candidate.nodes[i].outgoing = candidate.nodes[i].outgoing.map(normalized)
                }
                let fitted = candidate.flattened(tolerance:0.000001).map(physical)
                guard candidate.isValid, candidate.nodes.count < paths[index].nodes.count, fitted.count <= 6000, area(original)*area(fitted)>0,
                      close(original,to:fitted,within:tolerance),close(fitted,to:original,within:tolerance) else { continue }
                accepted = candidate; break
            }
            if let accepted { candidates[index] = accepted; changed = changed || accepted.nodes.count < original.count || accepted.nodes.contains { $0.smooth } }
        }
        guard changed else { throw Failure.unsafe }
        let before = paths.filter(\.closed).map { $0.flattened(tolerance: 0.000001).map(physical) }
        let after = candidates.filter(\.closed).map { $0.flattened(tolerance: 0.000001).map(physical) }
        guard after.reduce(0, { $0 + $1.count }) <= 6000, !crossings(after) else { throw Failure.unsafe }
        for i in before.indices { for j in before.indices where i != j {
            guard let p = before[i].first, let q = after[i].first, contains(before[j],p) == contains(after[j],q) else { throw Failure.unsafe }
        } }
        // Near-touching boundaries can change a large filled region without
        // a proper segment crossing. Check filled ink as well as boundaries.
        guard silhouetteAgreement(paths, candidates) >= (units > 3 ? 0.96 : 0.975) else { throw Failure.unsafe }
        return FontLabVectorMath.replacingPaths(in: glyph, with: candidates)
    }
    /// Least-squares cubic spans, split at maximum residual. Corners are
    /// retained as line joins; smooth split points share a tangent. Work in em
    /// space so a narrow glyph gets the same error budget as a wide glyph.
    private static func fittedRing(_ input: [FontLabPoint], tolerance: Double) -> FontLabVectorPath {
        let points = FontLabRemixEngine.simplified(input, tolerance: tolerance * 0.35)
        let count = points.count
        func sub(_ a: FontLabPoint, _ b: FontLabPoint) -> FontLabPoint { .init(x:a.x-b.x,y:a.y-b.y) }
        func dot(_ a: FontLabPoint, _ b: FontLabPoint) -> Double { a.x*b.x+a.y*b.y }
        func unit(_ p: FontLabPoint) -> FontLabPoint {
            let d = max(1e-12,hypot(p.x,p.y)); return .init(x:p.x/d,y:p.y/d)
        }
        func offset(_ p: FontLabPoint, _ t: FontLabPoint, _ d: Double) -> FontLabPoint { .init(x:p.x+t.x*d,y:p.y+t.y*d) }
        // Pixel stair steps are not typographic corners. Estimate turns over
        // a physical neighborhood, rather than one tiny raster edge.
        func neighbor(_ i: Int, _ step: Int) -> FontLabPoint {
            var j = (i + step + count) % count
            for _ in 0..<count-1 {
                if hypot(points[j].x-points[i].x,points[j].y-points[i].y) >= max(0.004,tolerance*8) { break }
                j = (j + step + count) % count
            }
            return points[j]
        }
        let corners = Set(points.indices.filter { i in
            dot(unit(sub(points[i],neighbor(i,-1))), unit(sub(neighbor(i,1),points[i]))) < 0.5
        })
        var breaks = corners
        // Closed smooth rings need at least three anchors and noncoincident
        // span endpoints. Four distributed seams avoid a degenerate solve.
        if breaks.count < 3 { breaks.formUnion([0,count/4,count/2,count*3/4]) }
        let ordered = breaks.sorted()
        var segments: [[FontLabPoint]] = []
        func fit(_ samples: [FontLabPoint], _ left: FontLabPoint, _ right: FontLabPoint, _ depth: Int) {
            let a = samples.first!, b = samples.last!
            if samples.count == 2 { segments.append([a,a,b,b]); return }
            var u = [0.0]
            for i in 1..<samples.count { u.append(u.last! + hypot(samples[i].x-samples[i-1].x,samples[i].y-samples[i-1].y)) }
            let length = max(u.last!,1e-12); u = u.map { $0/length }
            var curve=[a,a,b,b]
            for iteration in 0..<4 {
                var c00=0.0,c01=0.0,c11=0.0,x0=0.0,x1=0.0
                for i in samples.indices {
                    let t=u[i],v=1-t,b0=v*v*v,b1=3*v*v*t,b2=3*v*t*t,b3=t*t*t
                    let l=offset(.init(x:0,y:0),left,b1),r=offset(.init(x:0,y:0),right,b2)
                    let residual=FontLabPoint(x:samples[i].x-a.x*(b0+b1)-b.x*(b2+b3),y:samples[i].y-a.y*(b0+b1)-b.y*(b2+b3))
                    c00 += dot(l,l); c01 += dot(l,r); c11 += dot(r,r); x0 += dot(l,residual); x1 += dot(r,residual)
                }
                let determinant=c00*c11-c01*c01
                var alpha=determinant > 1e-12 ? (x0*c11-x1*c01)/determinant : length/3
                var beta=determinant > 1e-12 ? (x1*c00-x0*c01)/determinant : length/3
                if alpha <= 0 || beta <= 0 || alpha > length || beta > length { alpha=length/3; beta=length/3 }
                curve=[a,offset(a,left,alpha),offset(b,right,beta),b]
                guard iteration < 3 else { break }
                // Chord length is only an initial parameterization. Reproject
                // samples onto the cubic so raster stair steps do not force a
                // new anchor merely because their travel speed is uneven.
                for i in 1..<(samples.count-1) {
                    let t=u[i],v=1-t
                    let q=FontLabPoint(x:curve[0].x*v*v*v+3*curve[1].x*v*v*t+3*curve[2].x*v*t*t+curve[3].x*t*t*t,
                                       y:curve[0].y*v*v*v+3*curve[1].y*v*v*t+3*curve[2].y*v*t*t+curve[3].y*t*t*t)
                    let derivative=FontLabPoint(x:3*(curve[1].x-curve[0].x)*v*v+6*(curve[2].x-curve[1].x)*v*t+3*(curve[3].x-curve[2].x)*t*t,
                                                y:3*(curve[1].y-curve[0].y)*v*v+6*(curve[2].y-curve[1].y)*v*t+3*(curve[3].y-curve[2].y)*t*t)
                    let second=FontLabPoint(x:6*((curve[2].x-2*curve[1].x+curve[0].x)*v+(curve[3].x-2*curve[2].x+curve[1].x)*t),
                                            y:6*((curve[2].y-2*curve[1].y+curve[0].y)*v+(curve[3].y-2*curve[2].y+curve[1].y)*t))
                    let residual=sub(q,samples[i]),denominator=dot(derivative,derivative)+dot(residual,second)
                    if abs(denominator)>1e-14 { u[i]=min(u[i+1],max(u[i-1],t-dot(residual,derivative)/denominator)) }
                }
            }
            var error=0.0,split=samples.count/2
            for i in 1..<(samples.count-1) {
                let t=u[i],v=1-t
                let q=FontLabPoint(x:curve[0].x*v*v*v+3*curve[1].x*v*v*t+3*curve[2].x*v*t*t+curve[3].x*t*t*t,
                                   y:curve[0].y*v*v*v+3*curve[1].y*v*v*t+3*curve[2].y*v*t*t+curve[3].y*t*t*t)
                let distance=hypot(q.x-samples[i].x,q.y-samples[i].y)
                if distance > error { error=distance;split=i }
            }
            if error <= tolerance || depth >= 18 { segments.append(curve);return }
            var before=split-1,after=split+1
            while before > 0 && hypot(samples[split].x-samples[before].x,samples[split].y-samples[before].y) < max(0.004,tolerance*8) { before -= 1 }
            while after < samples.count-1 && hypot(samples[split].x-samples[after].x,samples[split].y-samples[after].y) < max(0.004,tolerance*8) { after += 1 }
            let tangent=unit(sub(samples[after],samples[before]))
            fit(Array(samples[...split]),left,.init(x:-tangent.x,y:-tangent.y),depth+1)
            fit(Array(samples[split...]),tangent,right,depth+1)
        }
        for k in ordered.indices {
            let start=ordered[k],end=ordered[(k+1)%ordered.count]
            let indices = end > start ? Array(start...end) : Array(start..<count)+Array(0...end)
            let samples=indices.map { points[$0] }
            let left=unit(sub(neighbor(start,1),corners.contains(start) ? points[start] : neighbor(start,-1)))
            let right=unit(sub(neighbor(end,-1),corners.contains(end) ? points[end] : neighbor(end,1)))
            fit(samples,left,right,0)
        }
        let nodes = segments.indices.map { i -> FontLabVectorNode in
            let previous=segments[(i+segments.count-1)%segments.count],current=segments[i]
            let incoming=previous[2] == current[0] ? nil : previous[2]
            let outgoing=current[1] == current[0] ? nil : current[1]
            var smooth=false
            if let incoming,let outgoing {
                smooth=dot(unit(sub(current[0],incoming)),unit(sub(outgoing,current[0]))) > 0.999
            }
            return FontLabVectorNode(point:current[0],incoming:incoming,outgoing:outgoing,smooth:smooth)
        }
        return FontLabVectorPath(nodes:nodes,closed:true)
    }

    private static func silhouetteAgreement(_ before: [FontLabVectorPath], _ after: [FontLabVectorPath]) -> Double {
        let a=CGMutablePath(),b=CGMutablePath()
        before.filter(\.closed).forEach {a.addPath($0.cgPath)}
        after.filter(\.closed).forEach {b.addPath($0.cgPath)}
        var agreement=1.0
        // Test both the original frame and the union frame. A tiny bounds
        // change must not move the sampling grid away from a damaged region.
        for box in [a.boundingBoxOfPath, a.boundingBoxOfPath.union(b.boundingBoxOfPath)] {
            guard box.width > 0,box.height > 0 else {return 0}
            var intersection=0,union=0
            for y in 0..<160 {for x in 0..<160 {
                let p=CGPoint(x:box.minX+(Double(x)+0.5)/160*box.width,y:box.minY+(Double(y)+0.5)/160*box.height)
                let aa=a.contains(p,using:.winding),bb=b.contains(p,using:.winding)
                if aa && bb {intersection += 1};if aa || bb {union += 1}
            }}
            agreement=min(agreement,union == 0 ? 0 : Double(intersection)/Double(union))
        }
        return agreement
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
