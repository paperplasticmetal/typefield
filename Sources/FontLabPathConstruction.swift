import AppKit

/// Geometry shared by endpoint drawing and the conversion of drawn centerlines
/// into editable, filled glyph contours. These operations never move artwork to
/// make it fit: a rejected operation leaves the caller's original paths intact.
enum FontLabPathConstruction {
    /// Orient an open contour so drawing can continue from the chosen endpoint.
    /// Reversal swaps control handles and retains all path and node identities.
    static func continuing(_ path: FontLabVectorPath, from nodeID: UUID) -> FontLabVectorPath? {
        guard path.isValid, !path.closed,
              path.nodes.first?.id == nodeID || path.nodes.last?.id == nodeID else { return nil }
        var result = path
        if result.nodes.last?.id != nodeID { result.reverse() }
        return result
    }

    /// Join two open ends, keeping the path and endpoint identity of `firstNode`.
    /// Line and explicit Join commands create a straight connecting segment;
    /// Pen can retain the unused endpoint handles to create a curved connection.
    static func joining(_ paths: [FontLabVectorPath], from firstNode: UUID, to secondNode: UUID,
                        preservingBridgeHandles: Bool = false) -> [FontLabVectorPath]? {
        guard firstNode != secondNode, valid(paths),
              let firstIndex = paths.firstIndex(where: { $0.nodes.contains { $0.id == firstNode } }),
              let secondIndex = paths.firstIndex(where: { $0.nodes.contains { $0.id == secondNode } }),
              var source = continuing(paths[firstIndex], from: firstNode),
              let destination = continuing(paths[secondIndex], from: secondNode) else { return nil }

        if firstIndex == secondIndex {
            // Both targets must be the two distinct ends of this same contour.
            guard source.nodes.first?.id == secondNode, source.nodes.count >= 3 else { return nil }
            if samePosition(source.nodes[0].point, source.nodes.last!.point) {
                // Retain the clicked source endpoint while joining the incoming
                // final segment to the outgoing initial segment without a stub.
                guard source.nodes.count >= 4 else { return nil }
                let last = source.nodes.removeLast()
                var merged = last
                merged.outgoing = source.nodes[0].outgoing
                merged.smooth = last.smooth && source.nodes[0].smooth && hasSmoothTangents(merged)
                source.nodes[0] = merged
            } else if !preservingBridgeHandles {
                source.nodes[source.nodes.count - 1].outgoing = nil
                source.nodes[source.nodes.count - 1].smooth = false
                source.nodes[0].incoming = nil
                source.nodes[0].smooth = false
            }
            source.closed = true
        } else {
            var target = destination
            // A lone Pen anchor is already both ends; its incoming handle is
            // still the control to use when approaching it from another path.
            if target.nodes.count > 1 { target.reverse() }
            if samePosition(source.nodes.last!.point, target.nodes[0].point) {
                let last = source.nodes.count - 1
                source.nodes[last].outgoing = target.nodes[0].outgoing
                source.nodes[last].smooth = source.nodes[last].smooth && target.nodes[0].smooth && hasSmoothTangents(source.nodes[last])
                target.nodes.removeFirst()
            } else if !preservingBridgeHandles {
                source.nodes[source.nodes.count - 1].outgoing = nil
                source.nodes[source.nodes.count - 1].smooth = false
                target.nodes[0].incoming = nil
                target.nodes[0].smooth = false
            }
            source.nodes.append(contentsOf: target.nodes)
        }

        guard source.isValid else { return nil }
        var result = paths
        result[firstIndex] = source
        if firstIndex != secondIndex { result.remove(at: secondIndex) }
        return result
    }

    /// Stroke each open centerline separately in physical em coordinates. Each
    /// returned group is one compound fill, so a loop's counter stays attached
    /// while overlapping independent centerlines remain independent paint groups.
    static func outlined(_ paths: [FontLabVectorPath], width: Double,
                         designWidth: Double) -> [[FontLabVectorPath]]? {
        guard valid(paths), width.isFinite, width > 0,
              designWidth.isFinite, (0.02...3).contains(designWidth),
              (width * 1000).isFinite,
              paths.allSatisfy({ !$0.closed && hasLength($0) }) else { return nil }
        var groups: [[FontLabVectorPath]] = []
        var pathCount = 0, nodeCount = 0
        for path in paths {
            let physical = CGMutablePath()
            physical.addPath(path.cgPath, transform: CGAffineTransform(scaleX: designWidth, y: 1))
            let stroked = physical.copy(strokingWithWidth: width * 1000,
                                        lineCap: .round, lineJoin: .round, miterLimit: 4)
            let bounds = stroked.boundingBoxOfPath
            // This tolerance covers only arithmetic at an exact design edge,
            // less than one billionth of an em. No geometry is translated or
            // scaled to accommodate overflow; normal out-of-bounds ink rejects.
            let epsilon = 1e-8
            guard !bounds.isNull, !bounds.isEmpty,
                  bounds.minX.isFinite, bounds.minY.isFinite,
                  bounds.maxX.isFinite, bounds.maxY.isFinite,
                  bounds.minX >= -epsilon, bounds.minY >= -epsilon,
                  bounds.maxX <= designWidth * 1000 + epsilon,
                  bounds.maxY <= 1000 + epsilon else { return nil }
            let normalized = CGMutablePath()
            normalized.addPath(stroked.normalized(using: .winding),
                               transform: CGAffineTransform(scaleX: 1 / designWidth, y: 1))
            var group = FontLabVectorPath.from(normalized)
            guard !group.isEmpty, group.allSatisfy({ $0.closed && $0.isValid }) else { return nil }
            for p in group.indices {
                for n in group[p].nodes.indices {
                    group[p].nodes[n].smooth = hasSmoothTangents(group[p].nodes[n])
                }
            }
            pathCount += group.count
            nodeCount += group.reduce(0) { $0 + $1.nodes.count }
            guard pathCount <= 256, nodeCount <= 30_000 else { return nil }
            groups.append(group)
        }
        return groups
    }

    private static func valid(_ paths: [FontLabVectorPath]) -> Bool {
        guard !paths.isEmpty, paths.count <= 256, paths.allSatisfy(\.isValid),
              Set(paths.map(\.id)).count == paths.count else { return false }
        let ids = paths.flatMap { $0.nodes.map(\.id) }
        return ids.count <= 30_000 && Set(ids).count == ids.count
    }

    private static func samePosition(_ a: FontLabPoint, _ b: FontLabPoint) -> Bool {
        a.x == b.x && a.y == b.y
    }

    private static func hasLength(_ path: FontLabVectorPath) -> Bool {
        (0..<path.segmentCount).contains { segment in
            let controls = path.controls(segment)
            return controls.dropFirst().contains { !samePosition($0, controls[0]) }
        }
    }

    private static func hasSmoothTangents(_ node: FontLabVectorNode) -> Bool {
        guard let incoming = node.incoming, let outgoing = node.outgoing else { return false }
        let ax = incoming.x - node.point.x, ay = incoming.y - node.point.y
        let bx = outgoing.x - node.point.x, by = outgoing.y - node.point.y
        let product = hypot(ax, ay) * hypot(bx, by)
        return product > 0 && ax * bx + ay * by < 0 && abs(ax * by - ay * bx) <= product * 1e-8
    }
}
