import AppKit
import SwiftUI

/// Uses disposable artwork and storage. The system clipboard is never changed.
enum SpacesImageInteractionChecks {
    private static func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw NSError(domain: "SpacesImageInteractions", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }
    private static func close(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX-b.minX) < 0.000001 && abs(a.minY-b.minY) < 0.000001 && abs(a.width-b.width) < 0.000001 && abs(a.height-b.height) < 0.000001
    }
    private static func fixture(_ data: Data, width: Double = 320, height: Double = 160, scale: Double = 1, stretch: Double = 1) -> (TypeDirection, String) {
        var source = SpacesInteractionChecks.importedFixture(); source.canvasScale = scale
        var layer = ImportedLayer(id: "image-limits", name: "Image limits", x: 100, y: 100, width: width, height: height, color: "FFFFFF")
        layer.artworkData = data; layer.artworkInFront = true
        source.artworkLayers = [layer]
        let id = CanvasPlan(direction: source).elements.first { $0.sectionID == layer.id }!.objectID
        if stretch != 1 {
            source.objectTransforms = [id: CanvasObjectTransform(x: 100 * (1-stretch), y: 100 * (1-stretch), stretchX: stretch, stretchY: stretch, flipX: true)]
        }
        return (source, id)
    }
    static func run() throws {
        try check(Thread.isMainThread, "Spaces image checks must run on the AppKit main thread")
        let image = NSImage(size: CGSize(width: 16, height: 8), flipped: false) { rect in NSColor.red.setFill(); rect.fill(); return true }
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let data = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "SpacesImageInteractions", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not encode image fixture"])
        }
        try handleTargets(data)
        try resizeLimits(data)
        try selectionLimits(data)
        try duplicateRouting(data)
        print("PASS: nearest image handles at four zooms, legal anchored previews at transform limits, batch limit intersections, unchanged bound gestures and hosted duplicate/rollback routing")
    }
    private static func handleTargets(_ data: Data) throws {
        for size in [CGSize(width: 8, height: 4), CGSize(width: 16, height: 8), CGSize(width: 32, height: 16), CGSize(width: 320, height: 160)] {
            let (source, id) = fixture(data, width: size.width, height: size.height)
            let plan = CanvasPlan(direction: source), box = CanvasSelection.bounds([id], in: plan)!
            let view = CanvasNativeView(plan: plan); view.directionID = source.id; view.tool = .auto; view.objectSelection = [id]
            for zoom in [0.25, 0.5, 1.0, 2.0] {
                view.zoom = zoom
                for handle in SpacesResizeHandle.allCases {
                    try check(view.resizeHandle(at: handle.point(in: box)) == handle, "Exact \(handle) center must choose its nearest handle at \(size), zoom \(zoom)")
                }
                try check(view.resizeHandle(at: CGPoint(x: box.minX - 8.01/zoom, y: box.minY)) == nil, "Handle hit radius must remain eight screen points")
            }
        }
    }
    private static func resizeLimits(_ data: Data) throws {
        // All eight anchors, with proportional corners and deliberate Shift stretching.
        for scale in [0.75, 1.0, 2.0] {
            for expanding in [false, true] {
                let (source, id) = fixture(data, width: expanding ? 2 : 320, height: expanding ? 2 : 160, scale: scale)
                let plan = CanvasPlan(direction: source), box = CanvasSelection.bounds([id], in: plan)!
                let limits = CanvasObjectResizeLimits(ids: [id], transforms: source.objectTransforms ?? [:])
                for handle in SpacesResizeHandle.allCases {
                    for proportional in (handle.isCorner ? [true, false] : [false]) {
                        let sign = expanding ? 1.0 : -1.0
                        let delta = CGSize(width: (handle.unit.x == 0 ? -1 : 1) * sign * 100_000,
                                           height: (handle.unit.y == 0 ? -1 : 1) * sign * 100_000)
                        let proposed = proportional ? handle.proportionalResize(box, delta: delta, within: plan.artboardSize, objects: [], selected: [id], zoom: 1, bypass: true) : CanvasAlignmentResult(rect: handle.resized(box, delta: delta, within: plan.artboardSize), guides: [])
                        let result = limits.constrained(proposed, from: box, handle: handle, proportional: proportional)
                        let changed = SpacesObjects.resized(source, ids: [id], to: result.rect)
                        let committed = CanvasPlan(direction: changed)
                        try check(changed != source && changed.isValid && close(CanvasSelection.bounds([id], in: committed)!, result.rect), "Extreme \(handle) preview must persist at scale \(scale), growing \(expanding), proportional \(proportional)")
                        let transform = changed.objectTransforms![id]!
                        let boundary = expanding ? 50.0 : 0.02
                        if handle.unit.x != 0.5 { try check(abs(transform.stretchX!-boundary) < 0.000001, "Horizontal resize must stop at the stored transform boundary") }
                        if handle.unit.y != 0.5 { try check(abs(transform.stretchY!-boundary) < 0.000001, "Vertical resize must stop at the stored transform boundary") }
                        try check(abs((handle.unit.x == 0 ? result.rect.maxX : result.rect.minX) - (handle.unit.x == 0 ? box.maxX : box.minX)) < 0.000001 && abs((handle.unit.y == 0 ? result.rect.maxY : result.rect.minY) - (handle.unit.y == 0 ? box.maxY : box.minY)) < 0.000001, "Clamping must retain the opposite anchor")
                        if proportional { try check(abs(result.rect.width/result.rect.height-box.width/box.height) < 0.000001, "Clamping must preserve image aspect ratio") }
                        try check(committed.artboardSize == plan.artboardSize && changed.artworkLayers == source.artworkLayers, "Resize must preserve the canvas and embedded image bytes")
                        for element in plan.elements where element.objectID != id {
                            try check(committed.elements.first { $0.objectID == element.objectID }?.rect == element.rect, "Extreme resize must preserve unselected objects")
                        }
                        let restored = try JSONDecoder().decode(TypeDirection.self, from: JSONEncoder().encode(changed))
                        try check(restored == changed, "Boundary transforms must survive JSON reload")
                    }
                }
            }
            for boundary in [0.02, 50.0] {
                let (source, id) = fixture(data, width: boundary == 50 ? 2 : 320, height: boundary == 50 ? 2 : 160, scale: scale, stretch: boundary)
                let box = CanvasSelection.bounds([id], in: CanvasPlan(direction: source))!
                let factor = boundary == 50 ? 2.0 : 0.5
                let proposed = CGRect(x: box.maxX-box.width*factor, y: box.maxY-box.height*factor, width: box.width*factor, height: box.height*factor)
                let limited = CanvasObjectResizeLimits(ids: [id], transforms: source.objectTransforms!).constrained(CanvasAlignmentResult(rect: proposed, guides: []), from: box, handle: .topLeft, proportional: true)
                try check(limited.rect == box && SpacesObjects.resized(source, ids: [id], to: limited.rect) == source, "Dragging farther beyond an accumulated limit must be an exact no-op without a false history entry")
            }
        }
        try check(CanvasObjectTransform.normalizedScaleBoundary(0.02.nextDown) == 0.02 && CanvasObjectTransform.normalizedScaleBoundary(50.0.nextUp) == 50 && CanvasObjectTransform.normalizedScaleBoundary(0.019) == 0.019 && CanvasObjectTransform.normalizedScaleBoundary(50.01) == 50.01, "Only floating-point boundary spill may normalize; materially invalid scales must stay invalid")
    }
    private static func selectionLimits(_ data: Data) throws {
        for growing in [false, true] {
            var (source, first) = fixture(data, width: 2, height: 2)
            var secondLayer = source.artworkLayers![0]; secondLayer.id = "second-image"; secondLayer.x = 220
            source.artworkLayers!.append(secondLayer)
            let second = CanvasPlan(direction: source).elements.first { $0.sectionID == secondLayer.id }!.objectID
            let a = growing ? 40.0 : 0.5, b = growing ? 10.0 : 2.0
            source.objectTransforms = [first: CanvasObjectTransform(x: 100*(1-a), y: 100*(1-a), stretchX: a, stretchY: a), second: CanvasObjectTransform(x: 220*(1-b), y: 100*(1-b), stretchX: b, stretchY: b)]
            let ids: Set<String> = [first, second]
            source.objectGroups = [CanvasObjectGroup(members: ids)]
            let original = CanvasPlan(direction: source), box = CanvasSelection.bounds(ids, in: original)!
            let requested = growing ? 3.0 : 0.001, expected = growing ? 1.25 : 0.04
            let proposed = CGRect(x: box.maxX-box.width*requested, y: box.maxY-box.height*requested, width: box.width*requested, height: box.height*requested)
            let guide = CanvasAlignmentGuide(axis: .vertical, position: proposed.minX, start: 0, end: 480, canvas: false)
            let limited = CanvasObjectResizeLimits(ids: ids, transforms: source.objectTransforms!).constrained(CanvasAlignmentResult(rect: proposed, guides: [guide]), from: box, handle: .topLeft, proportional: true)
            try check(abs(limited.rect.width/box.width-expected) < 0.000001 && limited.guides.isEmpty, "Batch limits must intersect every object's range and remove stale snap guides")
            let changed = SpacesObjects.resized(source, ids: ids, to: limited.rect), plan = CanvasPlan(direction: changed)
            try check(changed != source && changed.isValid && changed.objectGroups == source.objectGroups && close(CanvasSelection.bounds(ids, in: plan)!, limited.rect), "Group boundary preview must persist without changing membership")
            for element in original.elements where ids.contains(element.objectID) {
                let predicted = CanvasSelection.transformed(element, by: CanvasObjectTransform(scale: expected, x: limited.rect.minX-box.minX*expected, y: limited.rect.minY-box.minY*expected)).rect
                try check(close(plan.elements.first { $0.objectID == element.objectID }!.rect, predicted), "Every selected image must receive the same anchored resize")
            }
        }
        let ids: Set<String> = ["a", "b"]
        let transforms = ["a": CanvasObjectTransform(scale: 40, stretchX: 0.02), "b": CanvasObjectTransform(scale: 0.5, stretchY: 50)]
        let limits = CanvasObjectResizeLimits(ids: ids, transforms: transforms, scaling: true)
        try check(limits.horizontal == 0.04...1.25 && limits.vertical == 0.04...1.25, "Selections containing text must limit the accumulated uniform scale, independently of image stretching")
        let (source, id) = fixture(data, width: 20, height: 10, scale: 0.83, stretch: 3.14159)
        let box = CanvasSelection.bounds([id], in: CanvasPlan(direction: source))!
        let factor = 0.02 / 3.14159
        let target = CGRect(x: box.maxX-box.width*factor, y: box.maxY-box.height*factor, width: box.width*factor, height: box.height*factor)
        let next = SpacesObjects.resized(source, ids: [id], to: target)
        try check(next != source && next.isValid && close(CanvasSelection.bounds([id], in: CanvasPlan(direction: next))!, target), "Fractional canvas scale and cumulative transforms must preserve exact boundary geometry")
        try check(CanvasSelection.change(direction: source, ids: [id], anchor: box.origin, scale: 1, delta: .zero) == source, "Unchanged uniform scaling must not create transform metadata or a false edit")
    }
    private static func duplicateRouting(_ data: Data) throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Typefield-image-routing-" + UUID().uuidString)
        let suite = "Typefield.ImageRouting." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: folder) }
        let library = Library(storageURL: folder.appendingPathComponent("library.json"))
        let (source, id) = fixture(data, width: 40, height: 20)
        var board = TypeBoard(); board.directions = [source]; board.selectedDirection = source.id
        let session = library.editorSession(for: board)
        session.interactionTool = .frame; session.selectObjects([id], in: source)
        var accepted = board, saves = 0, reject = false
        let root = TypeBoardEditor(library: library, savedBoard: board, projectName: "Image routing fixture", projectBoards: [board], focusCanvas: .constant(false), sidebarCollapsed: .constant(true), onSave: { candidate, _ in
            if reject { return accepted }; accepted = candidate; saves += 1; return candidate
        }, onDelete: {}).defaultAppStorage(defaults)
        let host = NSHostingView(rootView: root); host.sizingOptions = []; host.frame = CGRect(x: 0, y: 0, width: 1400, height: 1000)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host
        defer { window.contentView = nil; window.close() }
        func flush() { for _ in 0..<6 { host.layoutSubtreeIfNeeded(); _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01)) } }
        func canvas(_ view: NSView) -> CanvasNativeView? {
            if let native = view as? CanvasNativeView, native.directionID == source.id, !native.plan.isArrangement { return native }
            for child in view.subviews { if let result = canvas(child) { return result } }
            return nil
        }
        flush()
        guard let native = canvas(host), let duplicate = native.onObjectCommand else { throw NSError(domain: "SpacesImageInteractions", code: 3, userInfo: [NSLocalizedDescriptionKey: "Hosted Spaces editor did not expose the object command route"]) }
        let token = session.selectionRevealToken
        duplicate("duplicate"); flush()
        try check(saves == 1 && session.interactionTool == .auto && session.selectedObjects.count == 1 && !session.selectedObjects.contains(id) && session.selectionRevealToken == token + 1, "Duplicate from Canvas mode must select and reveal its new object in Auto")
        try check(canvas(host)?.tool == .auto && canvas(host)?.resizeHandles().count == 8, "Successful duplicate must immediately expose native image handles")
        // Clipboard paste and paste-in-place use this same successful-command
        // branch; their private-pasteboard decoding is covered by SpacesObjectChecks.
        reject = true; session.interactionTool = .frame; flush()
        session.selectObjects([id], in: source); flush()
        let prior = session.board, priorToken = session.selectionRevealToken
        canvas(host)?.onObjectCommand?("duplicate"); flush()
        try check(session.board == prior && session.interactionTool == .frame && session.selectionRevealToken == priorToken && saves == 1, "Rejected duplicate must preserve the document and avoid a false mode switch or reveal")
    }
}
