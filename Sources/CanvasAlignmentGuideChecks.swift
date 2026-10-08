import Foundation
import CoreGraphics

enum CanvasAlignmentGuideChecks {
    static func run() throws {
        var count = 0
        func check(_ value: Bool, _ message: String) throws {
            count += 1
            if !value { throw NSError(domain: "Typefield.AlignmentGuides", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        func near(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 0.0001 }
        let canvas = CGSize(width: 1000, height: 800)
        let box = CGRect(x: 100, y: 100, width: 80, height: 40)
        let peer = CanvasAlignmentTarget(id: "peer", rect: CGRect(x: 300, y: 300, width: 80, height: 40))
        let both = CanvasAlignmentGuides.translated(box, delta: CGSize(width: 196, height: 197), canvas: canvas, objects: [peer], selected: ["selected"], zoom: 1)
        try check(both.rect.origin == CGPoint(x: 300, y: 300), "Nearby peer edges must attract on both axes")
        try check(both.rect.size == box.size, "Moving a group must preserve its size and all member spacing")
        try check(both.guides.count == 6 && both.guides.allSatisfy { !$0.canvas }, "Peer edge and center coincidences must have visible guides")
        let excluded = CanvasAlignmentGuides.translated(box, delta: CGSize(width: 196, height: 197), canvas: canvas, objects: [peer], selected: ["peer"], zoom: 1)
        try check(excluded.rect.origin == CGPoint(x: 296, y: 297) && excluded.guides.isEmpty, "Selected group members must never attract their own group")
        let centered = CanvasAlignmentGuides.translated(box, delta: CGSize(width: 357, height: 277), canvas: canvas, objects: [], selected: [], zoom: 1)
        try check(centered.rect.midX == 500 && centered.rect.midY == 400, "Canvas center axes must attract the selection")
        try check(centered.guides.count == 2 && centered.guides.allSatisfy(\.canvas), "Canvas center guides must span the canvas")
        let nearEdge = CanvasAlignmentGuides.translated(box, delta: CGSize(width: 817, height: 657), canvas: canvas, objects: [], selected: [], zoom: 1)
        try check(nearEdge.rect.maxX == canvas.width && nearEdge.rect.maxY == canvas.height, "Canvas trailing boundaries must attract without expanding the canvas")
        let clamped = CanvasAlignmentGuides.translated(box, delta: CGSize(width: -200, height: 900), canvas: canvas, objects: [], selected: [], zoom: 1)
        try check(clamped.rect.minX == 0 && clamped.rect.maxY == 800, "Dragging outside canvas bounds must remain clamped")
        let free = CanvasAlignmentGuides.translated(box, delta: CGSize(width: 196.25, height: 197.75), canvas: canvas, objects: [peer], selected: [], zoom: 1, bypass: true)
        try check(free.rect.origin == CGPoint(x: 296.25, y: 297.75) && free.guides.isEmpty, "Option must bypass attraction and preserve fractional positioning")
        let unsnapped = CanvasAlignmentGuides.translated(box, delta: CGSize(width: 33.25, height: 71.75), canvas: canvas, objects: [], selected: [], zoom: 1)
        try check(unsnapped.rect.origin == CGPoint(x: 133.25, y: 171.75), "Free movement must not snap to an arbitrary grid")
        let closer = CanvasAlignmentTarget(id: "closer", rect: peer.rect.offsetBy(dx: 4, dy: 200))
        let nearest = CanvasAlignmentGuides.translated(box, delta: CGSize(width: 203, height: 29), canvas: canvas, objects: [peer, closer], selected: [], zoom: 1)
        try check(nearest.rect.minX == 304, "The nearest guide must win, independent of object order")
        let reordered = CanvasAlignmentGuides.translated(box, delta: CGSize(width: 203, height: 29), canvas: canvas, objects: [closer, peer], selected: [], zoom: 1)
        try check(reordered.rect == nearest.rect, "Reordering unmatched objects must not change the winning guide")
        for zoom: CGFloat in [0.5, 1, 2, 4] {
            let inside = CanvasAlignmentGuides.translated(box, delta: CGSize(width: 200 + 5 / zoom, height: 27), canvas: canvas, objects: [peer], selected: [], zoom: zoom)
            try check(near(inside.rect.minX, 300), "Attraction must stay at six view points at zoom \(zoom)")
            let outside = CanvasAlignmentGuides.translated(box, delta: CGSize(width: 200 + 7 / zoom, height: 27), canvas: canvas, objects: [peer], selected: [], zoom: zoom)
            try check(near(outside.rect.minX, 300 + 7 / zoom), "Pointer must leave a guide outside the zoom-invariant tolerance")
            let right = CanvasAlignmentGuides.resized(CGRect(x: 100, y: 100, width: 200 - 4 / zoom, height: 80), handle: CGPoint(x: 1, y: 0.5), canvas: canvas, objects: [peer], selected: [], zoom: zoom)
            try check(right.rect.minX == 100 && right.rect.maxX == 300 && right.rect.minY == 100 && right.rect.height == 80, "Right handle must snap only its moving edge at zoom \(zoom)")
            try check(right.guides.contains { $0.axis == .vertical && $0.position == 300 }, "Snapped resize edge must render a guide")
        }
        let resizePeer = CanvasAlignmentTarget(id: "resize-peer", rect: CGRect(x: 100, y: 100, width: 50, height: 50))
        let topLeft = CanvasAlignmentGuides.resized(CGRect(x: 103, y: 104, width: 197, height: 196), handle: .zero, canvas: canvas, objects: [resizePeer], selected: [], zoom: 1)
        try check(topLeft.rect == CGRect(x: 100, y: 100, width: 200, height: 200), "Top-left resize must preserve the fixed bottom-right corner")
        let bypassResize = CanvasAlignmentGuides.resized(CGRect(x: 103, y: 104, width: 197, height: 196), handle: .zero, canvas: canvas, objects: [resizePeer], selected: [], zoom: 1, bypass: true)
        try check(bypassResize.rect.minX == 103 && bypassResize.rect.minY == 104 && bypassResize.guides.isEmpty, "Option must bypass resize attraction")
        let tinyPeer = CanvasAlignmentTarget(id: "tiny", rect: CGRect(x: 100, y: 400, width: 1, height: 1))
        let tiny = CanvasAlignmentGuides.resized(CGRect(x: 100, y: 100, width: 2, height: 20), handle: CGPoint(x: 1, y: 0.5), canvas: canvas, objects: [tinyPeer], selected: [], zoom: 1)
        try check(tiny.rect.width >= 1, "Resize attraction must not collapse or invert an object")
        let distant = CanvasAlignmentTarget(id: "distant", rect: peer.rect.offsetBy(dx: 0, dy: 350))
        let extended = CanvasAlignmentGuides.translated(box, delta: CGSize(width: 196, height: 27), canvas: canvas, objects: [peer, distant], selected: [], zoom: 1)
        let vertical = extended.guides.filter { $0.axis == .vertical }
        try check(vertical.count == 3 && vertical.allSatisfy { $0.start < 127 && $0.end > 690 }, "Coincident guide segments should merge across objects above and below")
        let invalid = CanvasAlignmentTarget(id: "invalid", rect: .null)
        let ignored = CanvasAlignmentGuides.translated(box, delta: CGSize(width: 33.25, height: 71.75), canvas: canvas, objects: [invalid], selected: [], zoom: 1)
        try check(ignored.rect == unsnapped.rect, "Invalid reference geometry must not affect interaction")
        let scaled = CanvasAlignmentGuides.scaled(box, factor: 2.47, canvas: canvas, objects: [peer], selected: [], zoom: 1)
        try check(scaled.rect == CGRect(x: 100, y: 100, width: 200, height: 100), "Text/group resize must snap its moving edge while retaining the aspect ratio and fixed corner")
        try check(scaled.guides.contains { $0.axis == .vertical && $0.position == 300 }, "Proportional resize must show its matched edge")
        let freeScale = CanvasAlignmentGuides.scaled(box, factor: 2.47, canvas: canvas, objects: [peer], selected: [], zoom: 1, bypass: true)
        try check(near(freeScale.rect.width, 197.6) && freeScale.guides.isEmpty, "Option must bypass proportional resize attraction")
        let outsidePeers = [
            CanvasAlignmentTarget(id: "negative", rect: CGRect(x: -3, y: -3, width: 1, height: 1)),
            CanvasAlignmentTarget(id: "beyond", rect: CGRect(x: 1002, y: 802, width: 1, height: 1))]
        let nearNegative = CanvasAlignmentGuides.translated(box, delta: CGSize(width: -98, height: -98), canvas: canvas, objects: outsidePeers, selected: [], zoom: 1)
        try check(nearNegative.rect.minX == 0 && nearNegative.rect.minY == 0, "Peer guides outside the canvas must not pull objects through its leading edges")
        let nearMaximum = CanvasAlignmentGuides.translated(box, delta: CGSize(width: 819, height: 659), canvas: canvas, objects: outsidePeers, selected: [], zoom: 1)
        try check(nearMaximum.rect.maxX == 1000 && nearMaximum.rect.maxY == 800, "Peer guides outside the canvas must not pull objects through its trailing edges")
        let resizeMaximum = CanvasAlignmentGuides.resized(CGRect(x: 100, y: 100, width: 899, height: 699), handle: CGPoint(x: 1, y: 1), canvas: canvas, objects: outsidePeers, selected: [], zoom: 1)
        try check(resizeMaximum.rect.maxX == 1000 && resizeMaximum.rect.maxY == 800, "Corner resize must reject out-of-canvas matches")
        let scaleMaximum = CanvasAlignmentGuides.scaled(box, factor: 11.24, canvas: canvas, objects: outsidePeers, selected: [], zoom: 1)
        try check(scaleMaximum.rect.maxX <= 1000 && scaleMaximum.rect.maxY <= 800 && near(scaleMaximum.rect.width / scaleMaximum.rect.height, 2), "Proportional snapping must preserve bounds and aspect ratio near the canvas maximum")
        print("PASS: \(count) smart-guide checks across moves, groups, canvas/peer alignment, resizing, zoom and Option bypass")
    }
}
