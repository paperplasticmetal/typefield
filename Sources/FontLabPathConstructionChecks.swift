import AppKit

enum FontLabPathConstructionChecks {
    static func run() throws {
        func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
            if !condition() { throw FontLabStore.SelfTestError.failed(message) }
        }
        func same(_ a: FontLabPoint, _ b: FontLabPoint) -> Bool {
            hypot(a.x - b.x, a.y - b.y) < 1e-10
        }
        func sameSegment(_ a: [FontLabPoint], _ b: [FontLabPoint]) -> Bool {
            zip(a, b).allSatisfy { same($0.0, $0.1) }
        }
        func compound(_ paths: [FontLabVectorPath], designWidth: Double = 1) -> CGPath {
            let result = CGMutablePath()
            paths.forEach { result.addPath($0.cgPath, transform: CGAffineTransform(scaleX: designWidth, y: 1)) }
            return result
        }
        func line(_ start: FontLabPoint, _ end: FontLabPoint) -> FontLabVectorPath {
            .init(nodes: [.init(point: start), .init(point: end)])
        }

        let source = FontLabVectorPath(nodes: [
            .init(point: .init(x: 0.12, y: 0.2), incoming: .init(x: 0.05, y: 0.1), outgoing: .init(x: 0.2, y: 0.5)),
            .init(point: .init(x: 0.3, y: 0.6), incoming: .init(x: 0.15, y: 0.7), outgoing: .init(x: 0.4, y: 0.7)),
            .init(point: .init(x: 0.45, y: 0.4), incoming: .init(x: 0.42, y: 0.3), outgoing: .init(x: 0.5, y: 0.45))
        ])
        let target = FontLabVectorPath(nodes: [
            .init(point: .init(x: 0.55, y: 0.3), incoming: .init(x: 0.5, y: 0.1), outgoing: .init(x: 0.6, y: 0.2)),
            .init(point: .init(x: 0.7, y: 0.5), incoming: .init(x: 0.6, y: 0.45), outgoing: .init(x: 0.8, y: 0.6)),
            .init(point: .init(x: 0.85, y: 0.7), incoming: .init(x: 0.9, y: 0.65), outgoing: .init(x: 0.95, y: 0.8))
        ])
        let unrelated = FontLabVectorMath.rectangle(CGRect(x: 0.1, y: 0.75, width: 0.1, height: 0.1), ellipse: true)
        for useFirst in [false, true] {
            let endpoint = useFirst ? source.nodes.first!.id : source.nodes.last!.id
            guard let continued = FontLabPathConstruction.continuing(source, from: endpoint) else {
                throw FontLabStore.SelfTestError.failed("An open endpoint could not be continued")
            }
            try check(continued.id == source.id && continued.nodes.last?.id == endpoint &&
                      Set(continued.nodes.map(\.id)) == Set(source.nodes.map(\.id)),
                      "Continuing an endpoint lost source identities or selected the wrong end")
            for segment in 0..<source.segmentCount { for sample in 0...20 {
                let t = Double(sample) / 20
                let before = FontLabVectorMath.evaluate(source.controls(segment), t)
                let after = FontLabVectorMath.evaluate(continued.controls(useFirst ? source.segmentCount - 1 - segment : segment), useFirst ? 1 - t : t)
                try check(same(before, after), "Continuing the first endpoint distorted its original cubic curves")
            } }
            if !useFirst { try check(continued == source, "Continuing the last endpoint must preserve the original path exactly") }
        }

        for sourceFirst in [false, true] { for targetFirst in [false, true] {
            let sourceID = (sourceFirst ? source.nodes.first! : source.nodes.last!).id
            let targetID = (targetFirst ? target.nodes.first! : target.nodes.last!).id
            let expectedSource = FontLabPathConstruction.continuing(source, from: sourceID)!
            var expectedTarget = FontLabPathConstruction.continuing(target, from: targetID)!
            expectedTarget.reverse()
            for preserveBridge in [false, true] {
                guard let joined = FontLabPathConstruction.joining([target, source, unrelated], from: sourceID, to: targetID,
                                                                   preservingBridgeHandles: preserveBridge) else {
                    throw FontLabStore.SelfTestError.failed("One of the four endpoint orientations failed to join")
                }
                let result = joined[0]
                try check(joined.count == 2 && joined[1] == unrelated && result.id == source.id && result.nodes.count == 6 && !result.closed,
                          "Joining must preserve the chosen source path identity, every anchor and unrelated contours")
                try check(result.nodes[2].id == sourceID && result.nodes[3].id == targetID,
                          "Endpoint joining connected the wrong ends")
                for segment in 0..<2 {
                    try check(sameSegment(result.controls(segment), expectedSource.controls(segment)) &&
                              sameSegment(result.controls(segment + 3), expectedTarget.controls(segment)),
                              "Joining endpoints changed an existing adjoining cubic segment")
                }
                try check(result.isCurve(2) == preserveBridge,
                          "Line joins must be straight and Pen joins must retain active bridge handles")
                if preserveBridge {
                    try check(result.nodes[2].outgoing == expectedSource.nodes.last!.outgoing &&
                              result.nodes[3].incoming == expectedTarget.nodes.first!.incoming,
                              "Pen endpoint reversal lost the bridge control handles")
                }
            }

            var touchingTarget = target
            let targetIndex = targetFirst ? 0 : touchingTarget.nodes.count - 1
            touchingTarget.nodes[targetIndex].point = expectedSource.nodes.last!.point
            touchingTarget.nodes[targetIndex].point.pressure = 0.23
            var expectedTouching = FontLabPathConstruction.continuing(touchingTarget, from: targetID)!
            expectedTouching.reverse()
            for preserveBridge in [false, true] {
                let joined = FontLabPathConstruction.joining([source, touchingTarget], from: sourceID, to: targetID,
                                                             preservingBridgeHandles: preserveBridge)!
                let result = joined[0]
                try check(result.nodes.count == 5 && result.segmentCount == 4 && result.nodes[2].id == sourceID &&
                          !result.nodes.contains(where: { $0.id == targetID }),
                          "Coincident joins must retain the source endpoint and remove the redundant target anchor")
                for segment in 0..<2 {
                    try check(sameSegment(result.controls(segment), expectedSource.controls(segment)) &&
                              sameSegment(result.controls(segment + 2), expectedTouching.controls(segment)),
                              "Coincident joins must preserve both adjoining curves without a zero-length bridge")
                }
                try check(result.nodes[2].point == expectedSource.nodes.last!.point,
                          "Coincident geometry must not replace the original source anchor metadata")
            }
        } }

        for firstEndpoint in [false, true] { for preserveBridge in [false, true] {
            let from = (firstEndpoint ? source.nodes.first! : source.nodes.last!).id
            let to = (firstEndpoint ? source.nodes.last! : source.nodes.first!).id
            let expected = FontLabPathConstruction.continuing(source, from: from)!
            let closed = FontLabPathConstruction.joining([source], from: from, to: to,
                                                         preservingBridgeHandles: preserveBridge)![0]
            try check(closed.closed && closed.isValid && closed.id == source.id && closed.nodes.count == 3 &&
                      closed.isCurve(2) == preserveBridge,
                      "Closing opposite ends must retain the contour and honor Line/Pen bridge behavior")
            for segment in 0..<2 {
                try check(sameSegment(closed.controls(segment), expected.controls(segment)),
                          "Closing a contour changed its existing segments")
            }
        } }

        let loneAnchor = FontLabVectorPath(nodes: [
            .init(point: .init(x: 0.8, y: 0.3), incoming: .init(x: 0.6, y: 0.2), outgoing: .init(x: 0.9, y: 0.4))
        ])
        let joinedLone = FontLabPathConstruction.joining([source, loneAnchor], from: source.nodes[2].id,
                                                        to: loneAnchor.nodes[0].id, preservingBridgeHandles: true)![0]
        try check(joinedLone.nodes.last?.incoming == loneAnchor.nodes[0].incoming &&
                  joinedLone.nodes.last?.outgoing == loneAnchor.nodes[0].outgoing,
                  "Joining a lone Pen anchor must preserve its incoming bridge control and future outgoing control")

        let ellipse = FontLabVectorMath.rectangle(CGRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6), ellipse: true)
        var splitLoop = ellipse
        splitLoop.closed = false
        var finalAnchor = splitLoop.nodes[0]; finalAnchor.id = UUID(); finalAnchor.outgoing = nil
        splitLoop.nodes[0].incoming = nil
        splitLoop.nodes.append(finalAnchor)
        for firstEndpoint in [false, true] {
            let from = (firstEndpoint ? splitLoop.nodes.first! : splitLoop.nodes.last!).id
            let to = (firstEndpoint ? splitLoop.nodes.last! : splitLoop.nodes.first!).id
            let expected = FontLabPathConstruction.continuing(splitLoop, from: from)!
            let closed = FontLabPathConstruction.joining([splitLoop], from: from, to: to)![0]
            try check(closed.closed && closed.nodes.count == 4 && closed.nodes[0].id == from &&
                      !closed.nodes.contains(where: { $0.id == to }),
                      "Rejoining split coincident ends must retain the chosen source endpoint without a redundant anchor")
            for segment in 0..<4 {
                try check(sameSegment(closed.controls(segment), expected.controls(segment)),
                          "Closing coincident endpoints distorted the original ellipse")
            }
        }

        let short = line(.init(x: 0.2, y: 0.3), .init(x: 0.8, y: 0.7))
        let retraced = FontLabVectorPath(nodes: [.init(point: .init(x: 0.2, y: 0.3)),
                                                .init(point: .init(x: 0.8, y: 0.7)),
                                                .init(point: .init(x: 0.2, y: 0.3))])
        try check(FontLabPathConstruction.joining([short], from: short.nodes[0].id, to: short.nodes[1].id) == nil &&
                  FontLabPathConstruction.joining([retraced], from: retraced.nodes[0].id, to: retraced.nodes[2].id) == nil,
                  "Closing a two-anchor line or its coincident retracing must not create a non-area contour")
        try check(FontLabPathConstruction.continuing(source, from: source.nodes[1].id) == nil &&
                  FontLabPathConstruction.continuing(ellipse, from: ellipse.nodes[0].id) == nil &&
                  FontLabPathConstruction.joining([source, target], from: source.nodes[1].id, to: target.nodes[0].id) == nil &&
                  FontLabPathConstruction.joining([source, ellipse], from: source.nodes[0].id, to: ellipse.nodes[0].id) == nil &&
                  FontLabPathConstruction.joining([source], from: source.nodes[0].id, to: source.nodes[0].id) == nil &&
                  FontLabPathConstruction.joining([source], from: source.nodes[0].id, to: UUID()) == nil,
                  "Interior, closed, repeated and absent endpoint targets must be rejected")
        var duplicate = target; duplicate.nodes[0].id = source.nodes[0].id
        var invalid = target; invalid.nodes[1].point.x = .nan
        try check(FontLabPathConstruction.joining([source, duplicate], from: source.nodes[2].id, to: target.nodes[2].id) == nil &&
                  FontLabPathConstruction.joining([source, invalid], from: source.nodes[2].id, to: target.nodes[2].id) == nil,
                  "Ambiguous identities and invalid geometry must reject the complete join")

        for designWidth in [0.2, 0.62, 1.4] { for width in [0.008, 0.04, 0.08] { for horizontal in [false, true] {
            let centerline = horizontal ? line(.init(x: 0.3, y: 0.5), .init(x: 0.7, y: 0.5)) :
                                          line(.init(x: 0.5, y: 0.3), .init(x: 0.5, y: 0.7))
            guard let groups = FontLabPathConstruction.outlined([centerline], width: width, designWidth: designWidth) else {
                throw FontLabStore.SelfTestError.failed("An in-bounds centerline could not become a filled outline")
            }
            let shape = compound(groups[0], designWidth: designWidth), bounds = shape.boundingBoxOfPath
            let radius = width * 500
            let start = CGPoint(x: centerline.nodes[0].point.x * designWidth * 1000, y: centerline.nodes[0].point.y * 1000)
            let end = CGPoint(x: centerline.nodes[1].point.x * designWidth * 1000, y: centerline.nodes[1].point.y * 1000)
            let expected = CGRect(x: start.x - radius, y: start.y - radius,
                                  width: end.x - start.x + radius * 2, height: end.y - start.y + radius * 2)
            try check(groups.count == 1 && groups[0].allSatisfy { $0.closed && $0.isValid } &&
                      groups[0].contains { $0.nodes.contains { $0.incoming != nil || $0.outgoing != nil } },
                      "Outlining must produce valid editable cubic contours rather than a centerline or flattened cap")
            try check(abs(bounds.minX - expected.minX) < 1e-4 && abs(bounds.minY - expected.minY) < 1e-4 &&
                      abs(bounds.maxX - expected.maxX) < 1e-4 && abs(bounds.maxY - expected.maxY) < 1e-4,
                      "Outlined stroke width or round-cap extent changed with glyph aspect ratio")
            let insideCap = CGPoint(x: start.x - (horizontal ? radius * 0.8 : 0), y: start.y - (horizontal ? 0 : radius * 0.8))
            let outsideCap = CGPoint(x: start.x - (horizontal ? radius * 1.2 : 0), y: start.y - (horizontal ? 0 : radius * 1.2))
            try check(shape.contains(insideCap, using: .winding) && !shape.contains(outsideCap, using: .winding),
                      "Round end caps must retain their physical radius in either direction")
        } } }

        let corner = FontLabVectorPath(nodes: [.init(point: .init(x: 0.3, y: 0.3)),
                                             .init(point: .init(x: 0.7, y: 0.3)),
                                             .init(point: .init(x: 0.7, y: 0.7))])
        let cornerGroup = FontLabPathConstruction.outlined([corner], width: 0.04, designWidth: 0.62)![0]
        let cornerShape = compound(cornerGroup, designWidth: 0.62)
        try check(cornerShape.contains(CGPoint(x: 434 + 14, y: 300 - 14), using: .winding) &&
                  !cornerShape.contains(CGPoint(x: 434 + 19, y: 300 - 19), using: .winding),
                  "Centerline corners must use round joins, without a square or miter protrusion")

        let loop = FontLabVectorPath(nodes: [FontLabPoint(x: 0.2, y: 0.2), .init(x: 0.8, y: 0.2),
                                             .init(x: 0.8, y: 0.8), .init(x: 0.2, y: 0.8), .init(x: 0.2, y: 0.2)]
            .map { FontLabVectorNode(point: $0) })
        let loopGroup = FontLabPathConstruction.outlined([loop], width: 0.04, designWidth: 0.62)![0]
        let loopShape = compound(loopGroup, designWidth: 0.62)
        try check(loopGroup.count == 2 && loopShape.contains(CGPoint(x: 124, y: 500), using: .winding) &&
                  !loopShape.contains(CGPoint(x: 310, y: 500), using: .winding),
                  "Outlining an open loop must retain its counter in the same compound fill group")
        let crossing = line(.init(x: 0.15, y: 0.5), .init(x: 0.85, y: 0.5))
        let separateGroups = FontLabPathConstruction.outlined([loop, crossing], width: 0.04, designWidth: 0.62)!
        try check(separateGroups.count == 2 &&
                  compound(separateGroups[1], designWidth: 0.62).contains(CGPoint(x: 310, y: 500), using: .winding) &&
                  !compound(separateGroups[0], designWidth: 0.62).contains(CGPoint(x: 310, y: 500), using: .winding),
                  "Independent centerlines must return independent groups while preserving their own holes")

        // Compare the editable outline against Core Graphics' original stroked
        // curve at physical coordinates, including a loop with coincident ends.
        let cubicLoop = FontLabVectorPath(nodes: [
            .init(point: .init(x: 0.5, y: 0.3), outgoing: .init(x: 0.85, y: 0.7)),
            .init(point: .init(x: 0.5, y: 0.3), incoming: .init(x: 0.15, y: 0.7))
        ])
        for centerline in [source, cubicLoop] {
            let outline = FontLabPathConstruction.outlined([centerline], width: 0.025, designWidth: 0.62)![0]
            let actual = compound(outline, designWidth: 0.62)
            let expected = compound([centerline], designWidth: 0.62)
                .copy(strokingWithWidth: 25, lineCap: .round, lineJoin: .round, miterLimit: 4)
            for x in 0..<100 { for y in 0..<100 {
                let point = CGPoint(x: (Double(x) + 0.37) * 6.2, y: (Double(y) + 0.61) * 10)
                try check(actual.contains(point, using: .winding) == expected.contains(point, using: .winding),
                          "Editable stroke contours changed the filled silhouette of the original cubic centerline")
            } }
        }

        let fitsEdge = line(.init(x: 0.02 / 0.62, y: 0.4), .init(x: 0.7, y: 0.4))
        let overflow = line(.init(x: 0.01 / 0.62, y: 0.4), .init(x: 0.7, y: 0.4))
        let zero = line(.init(x: 0.4, y: 0.4), .init(x: 0.4, y: 0.4))
        var curveOverflow = short; curveOverflow.nodes[0].outgoing = .init(x: -1, y: 0.2)
        try check(FontLabPathConstruction.outlined([fitsEdge], width: 0.04, designWidth: 0.62) != nil &&
                  FontLabPathConstruction.outlined([overflow], width: 0.04, designWidth: 0.62) == nil &&
                  FontLabPathConstruction.outlined([short, overflow], width: 0.04, designWidth: 0.62) == nil &&
                  FontLabPathConstruction.outlined([curveOverflow], width: 0.04, designWidth: 0.62) == nil,
                  "Outlining must accept exact fits and reject cap/curve overflow atomically without clipping or shifting")
        try check(FontLabPathConstruction.outlined([], width: 0.04, designWidth: 0.62) == nil &&
                  FontLabPathConstruction.outlined([zero], width: 0.04, designWidth: 0.62) == nil &&
                  FontLabPathConstruction.outlined([FontLabVectorPath(nodes: [source.nodes[0]])], width: 0.04, designWidth: 0.62) == nil &&
                  FontLabPathConstruction.outlined([ellipse], width: 0.04, designWidth: 0.62) == nil &&
                  FontLabPathConstruction.outlined([source], width: 0, designWidth: 0.62) == nil &&
                  FontLabPathConstruction.outlined([source], width: .nan, designWidth: 0.62) == nil &&
                  FontLabPathConstruction.outlined([source], width: 0.04, designWidth: .infinity) == nil,
                  "Only nondegenerate open centerlines and finite physical widths may become outlines")
        print("Letterform path construction checks passed: endpoint orientation, curve-preserving joins, closures, physical round strokes, counters and atomic overflow rejection")
    }
}
