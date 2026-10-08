import AppKit

enum CanvasInteractionTool: String, CaseIterable {
    case auto = "Auto", select = "Select", marquee = "Marquee", text = "Text", frame = "Canvas"
    var symbol: String {
        switch self { case .auto: return "cursorarrow.rays"; case .select: return "cursorarrow"; case .marquee: return "rectangle.dashed"; case .text: return "text.cursor"; case .frame: return "rectangle" }
    }
}
struct CanvasObjectTransform: Codable, Equatable {
    var scale = 1.0
    var x = 0.0
    var y = 0.0
    var stretchX: Double?
    var stretchY: Double?
    var flipX: Bool?
    var flipY: Bool?
    var isValid: Bool { [stretchX ?? 1, stretchY ?? 1].allSatisfy { $0.isFinite && (0.02...50).contains($0) } && scale.isFinite && (0.02...50).contains(scale) && x.isFinite && y.isFinite && abs(x) <= 100_000 && abs(y) <= 100_000 }
}
struct CanvasObjectGroup: Codable, Equatable, Identifiable {
    var id = UUID()
    var members: Set<String>
}
enum CanvasSelection {
    static func expanded(_ ids: Set<String>, groups: [CanvasObjectGroup]) -> Set<String> {
        groups.reduce(ids) { result, group in result.isDisjoint(with: group.members) ? result : result.union(group.members) }
    }
    static func bounds(_ ids: Set<String>, in plan: CanvasPlan) -> CGRect? {
        let rect = plan.elements.filter { ids.contains($0.objectID) }.reduce(CGRect.null) { $0.union($1.rect) }
        return rect.isNull ? nil : rect
    }
    static func marquee(_ rect: CGRect, in plan: CanvasPlan) -> Set<String> {
        Set(plan.elements.filter { !$0.objectID.isEmpty && rect.intersects($0.rect) }.map(\.objectID))
    }
    static func change(direction: TypeDirection, ids: Set<String>, anchor: CGPoint, scale: Double, delta: CGSize) -> TypeDirection {
        var result = direction
        let plan = CanvasPlanCache.plan(for: direction)
        let valid = Set(plan.elements.map(\.objectID)).intersection(ids)
        let canvasScale = direction.canvasScale ?? 1
        var transforms = direction.objectTransforms ?? [:]
        for id in valid {
            let old = transforms[id] ?? CanvasObjectTransform()
            let next = CanvasObjectTransform(scale: old.scale * scale,
                x: old.x * scale + (anchor.x * (1 - scale) + delta.width) / canvasScale,
                y: old.y * scale + (anchor.y * (1 - scale) + delta.height) / canvasScale, stretchX: old.stretchX, stretchY: old.stretchY, flipX: old.flipX, flipY: old.flipY)
            guard next.isValid else { return direction }
            transforms[id] = next
        }
        result.objectTransforms = transforms
        let candidate = CanvasPlan(direction: result)
        guard candidate.elements.allSatisfy({ element in
            !valid.contains(element.objectID) || (element.rect.minX >= -0.01 && element.rect.minY >= -0.01 && element.rect.maxX <= 10_000 && element.rect.maxY <= 10_000 && (element.style?.size ?? 1) <= 1_000)
        }) else { return direction }
        return result
    }
    static func aligned(direction: TypeDirection, ids: Set<String>, alignment: StudioCanvasAlignment) -> TypeDirection {
        let plan = CanvasPlanCache.plan(for: direction)
        guard let bounds = bounds(ids, in: plan) else { return direction }
        let target = alignment.origin(for: bounds, in: plan.artboardSize)
        let delta = CGSize(width: target.x - bounds.minX, height: target.y - bounds.minY)
        if abs(delta.width) < 0.0001 && abs(delta.height) < 0.0001 { return direction }
        return change(direction: direction, ids: ids, anchor: .zero, scale: 1, delta: delta)
    }
    static func transformed(_ source: CanvasElement, by transform: CanvasObjectTransform) -> CanvasElement {
        var element = source
        let factor = transform.scale
        let sx = factor * (transform.stretchX ?? 1), sy = factor * (transform.stretchY ?? 1)
        element.flipX = source.flipX != (transform.flipX ?? false); element.flipY = source.flipY != (transform.flipY ?? false)
        element.rect = CGRect(x: source.rect.minX * sx + transform.x, y: source.rect.minY * sy + transform.y, width: source.rect.width * sx, height: source.rect.height * sy)
        element.radius *= factor; element.strokeWidth *= factor
        if let style = source.style { element.style = style.scaledForCanvas(factor) }
        if let text = source.text, factor != 1 {
            let result = NSMutableAttributedString(attributedString: text)
            text.enumerateAttributes(in: NSRange(location: 0, length: text.length)) { attrs, range, _ in
                if let font = attrs[.font] as? NSFont { result.addAttribute(.font, value: NSFont(descriptor: font.fontDescriptor, size: font.pointSize * factor) ?? font, range: range) }
                if let kern = attrs[.kern] as? NSNumber { result.addAttribute(.kern, value: kern.doubleValue * factor, range: range) }
                if let paragraph = attrs[.paragraphStyle] as? NSParagraphStyle, let copy = paragraph.mutableCopy() as? NSMutableParagraphStyle {
                    copy.minimumLineHeight *= factor; copy.maximumLineHeight *= factor; copy.paragraphSpacing *= factor; copy.firstLineHeadIndent *= factor
                    result.addAttribute(.paragraphStyle, value: copy, range: range)
                }
            }
            element.text = result
        }
        return element
    }
}
extension CanvasPlan {
    mutating func applyObjectTransforms(_ transforms: [String: CanvasObjectTransform], canvasScale: Double = 1) {
        var counts: [String: Int] = [:]
        for i in elements.indices {
            let element = elements[i]
            let kind = element.text != nil ? "text" : element.image != nil ? "image" : "shape"
            let key = element.sectionID + "|" + kind
            let ordinal = counts[key, default: 0]; counts[key] = ordinal + 1
            let id = element.textID ?? key + "|\(ordinal)"
            elements[i].objectID = id
            if let transform = transforms[id], transform.isValid {
                // Match this object's pre-transform rendered frame without rounding
                // or relaying out any unselected object at a different scale.
                if elements[i].text != nil {
                    let rendered = CanvasSelection.transformed(elements[i], by: CanvasObjectTransform(scale: canvasScale))
                    elements[i].rect.size.width = max(elements[i].rect.width, CanvasBoardLayout.minimumTextFrameWidth(for: rendered) / canvasScale)
                }
                elements[i] = CanvasSelection.transformed(elements[i], by: transform)
            }
        }
        if !transforms.isEmpty {
            for i in sections.indices {
                let bounds = elements.filter { $0.sectionID == sections[i].id }.reduce(CGRect.null) { $0.union($1.rect) }
                if !bounds.isNull { sections[i].rect = bounds }
            }
        }
    }
}

extension CanvasNativeView {
    override func selectAll(_ sender: Any?) {
        guard directionID != nil, tool != .frame else { return }
        if plan.isArrangement { onObjectCommand?("selectAll"); return }
        objectSelection = Set(plan.elements.map(\.objectID).filter { !$0.isEmpty })
        onObjectSelection?(objectSelection); needsDisplay = true
    }
    func trackObjectSelection(_ event: NSEvent) {
        guard let window else { return }
        window.makeFirstResponder(self)
        let originalPlan = plan, originalSelection = objectSelection
        let start = convert(event.locationInWindow, from: nil)
        let origin = CGPoint(x: start.x / zoom, y: start.y / zoom)
        let additive = event.modifierFlags.contains(.shift)
        let handle = resizeHandles().first { hypot(origin.x - $0.1.x, origin.y - $0.1.y) < 8 / zoom }?.0
        let resize = handle != nil
        let independent = plan.elements.filter { objectSelection.contains($0.objectID) }.allSatisfy { $0.text == nil }
        let hit = plan.elements.last { $0.rect.contains(origin) && !$0.objectID.isEmpty }
        let marquee = !resize && (tool == .marquee || hit == nil)
        if !marquee && !resize, let hit {
            let ids = CanvasSelection.expanded([hit.objectID], groups: objectGroups)
            if additive { objectSelection = objectSelection.isSuperset(of: ids) ? objectSelection.subtracting(ids) : objectSelection.union(ids) }
            else if !objectSelection.contains(hit.objectID) { objectSelection = ids }
        }
        let selected = objectSelection
        let box = CanvasSelection.bounds(selected, in: originalPlan)
        var factor = 1.0, delta = CGSize.zero, moved = false
        var resizedBox: CGRect?
        defer { selectionMarquee = nil; plan = originalPlan; needsDisplay = true; window.invalidateCursorRects(for: self) }
        while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp, .keyDown], until: .distantFuture, inMode: .eventTracking, dequeue: true) {
            if next.type == .keyDown { if next.keyCode == 53 { objectSelection = originalSelection; return }; continue }
            let screen = convert(next.locationInWindow, from: nil)
            let point = CGPoint(x: screen.x / zoom, y: screen.y / zoom)
            moved = moved || hypot(screen.x - start.x, screen.y - start.y) > 3
            if marquee {
                let rect = CGRect(x: min(origin.x, point.x), y: min(origin.y, point.y), width: abs(point.x-origin.x), height: abs(point.y-origin.y))
                selectionMarquee = rect
                let hits = moved ? CanvasSelection.expanded(CanvasSelection.marquee(rect, in: originalPlan), groups: objectGroups) : []
                objectSelection = additive ? originalSelection.union(hits) : hits
            } else if moved, let box {
                if resize && independent, let handle {
                    resizedBox = handle.resized(box, delta: CGSize(width: point.x-origin.x, height: point.y-origin.y), within: originalPlan.artboardSize)
                } else if resize {
                    factor = min((originalPlan.artboardSize.width-box.minX)/max(1,box.width), (originalPlan.artboardSize.height-box.minY)/max(1,box.height), max(0.05, max((point.x-box.minX)/max(1,box.width), (point.y-box.minY)/max(1,box.height))))
                } else {
                    delta = CGSize(width: min(max(point.x-origin.x,-box.minX), max(0,originalPlan.artboardSize.width-box.maxX)), height: min(max(point.y-origin.y,-box.minY), max(0,originalPlan.artboardSize.height-box.maxY)))
                }
                var transform = CanvasObjectTransform(scale: factor, x: box.minX*(1-factor)+delta.width, y: box.minY*(1-factor)+delta.height)
                if let target = resizedBox {
                    let sx = target.width / box.width, sy = target.height / box.height
                    transform = CanvasObjectTransform(x: target.minX-box.minX*sx, y: target.minY-box.minY*sy, stretchX: sx, stretchY: sy)
                }
                plan = originalPlan
                for i in plan.elements.indices where selected.contains(plan.elements[i].objectID) { plan.elements[i] = CanvasSelection.transformed(originalPlan.elements[i], by: transform) }
                (resize ? NSCursor.resizeLeftRight : NSCursor.closedHand).set()
            }
            needsDisplay = true; displayIfNeeded()
            if next.type == .leftMouseUp {
                plan = originalPlan
                onObjectSelection?(objectSelection)
                if moved, !marquee, let box { if let resizedBox { onObjectResize?(selected, resizedBox) } else { onObjectTransform?(selected, box.origin, factor, delta) } }
                return
            }
        }
        objectSelection = originalSelection
    }
    func drawObjectSelection() {
        guard directionID != nil, tool == .auto || tool == .select || tool == .marquee else { return }
        ShelfPalette.nativeAccent.setStroke()
        for element in plan.elements where objectSelection.contains(element.objectID) {
            let outline = NSBezierPath(rect: element.rect); outline.lineWidth = 1 / zoom; outline.stroke()
        }
        if let box = CanvasSelection.bounds(objectSelection, in: plan) {
            let outline = NSBezierPath(rect: box); outline.lineWidth = 1.5 / zoom; outline.stroke()
            for (_, point) in resizeHandles() {
                let handle = CGRect(x: point.x-4/zoom, y: point.y-4/zoom, width: 8/zoom, height: 8/zoom)
                NSColor.controlBackgroundColor.setFill(); handle.fill(); ShelfPalette.nativeAccent.setStroke(); NSBezierPath(rect: handle).stroke()
            }
        }
        if let rect = selectionMarquee {
            ShelfPalette.nativeAccent.withAlphaComponent(0.1).setFill(); rect.fill()
            ShelfPalette.nativeAccent.setStroke(); let outline = NSBezierPath(rect: rect); outline.lineWidth = 1/zoom; outline.setLineDash([4/zoom,3/zoom], count: 2, phase: 0); outline.stroke()
        }
    }
}
