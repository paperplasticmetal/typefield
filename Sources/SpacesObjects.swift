import AppKit
import SwiftUI

/// Clipboard objects use rendered coordinates, so pasting between differently
/// scaled canvases retains the visible size rather than copying template roles.
struct SpacesObjectClip: Codable {
    var version = 1
    var layers: [ImportedLayer]
    var groups: [[Int]] = []
    var isValid: Bool {
        version == 1 && !layers.isEmpty && layers.count <= 1000 && Set(layers.map(\.id)).count == layers.count &&
        layers.allSatisfy { $0.isValidArtwork || ImportedLayout(width: 1, height: 1, layers: [$0]).isValid } &&
        layers.reduce(0) { $0 + ($1.artworkData?.count ?? 0) } <= 64 * 1024 * 1024 &&
        groups.count <= 1000 && groups.allSatisfy { $0.count <= 1000 && $0.allSatisfy { layers.indices.contains($0) } }
    }
}
enum SpacesObjects {
    static let pasteboardType = NSPasteboard.PasteboardType("app.typefield.spaces.objects.v1")
    static func clip(_ direction: TypeDirection, ids: Set<String>) -> SpacesObjectClip? {
        let plan = CanvasPlanCache.plan(for: direction)
        let elements = plan.elements.filter { ids.contains($0.objectID) }
        let layers = elements.map { e -> ImportedLayer in
            let color = (e.text.flatMap { $0.length > 0 ? $0.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor : nil } ?? e.color ?? plan.ink).usingColorSpace(.deviceRGB) ?? .black
            var style = e.style; style?.text = e.style?.text ?? e.text?.string ?? ""
            var layer = ImportedLayer(name: plan.sections.first { $0.id == e.sectionID }?.title ?? "Object", x: e.rect.minX, y: e.rect.minY, width: e.rect.width, height: e.rect.height, color: color.rgbHex, opacity: e.image != nil ? e.imageOpacity : color.alphaComponent, radius: e.radius, style: style)
            layer.strokeColor = e.strokeColor?.rgbHex; layer.strokeOpacity = e.strokeColor.map { Double($0.alphaComponent) }; layer.strokeWidth = e.strokeColor == nil ? nil : e.strokeWidth
            if e.image != nil {
                layer.artworkData = ((direction.objectLayers ?? []) + (direction.artworkLayers ?? []) + (direction.importedLayout?.layers ?? [])).first { $0.id == e.sectionID }?.artworkData
                if layer.artworkData == nil, let tiff = e.image?.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) { layer.artworkData = rep.representation(using: .png, properties: [:]) }
                layer.style = nil; layer.artworkInFront = true
            }
            layer.flipX = e.flipX; layer.flipY = e.flipY
            return layer
        }
        let groups = (direction.objectGroups ?? []).compactMap { group -> [Int]? in
            let indices = elements.indices.filter { group.members.contains(elements[$0].objectID) }
            return indices.count > 1 ? indices : nil
        }
        let clip = SpacesObjectClip(layers: layers, groups: groups)
        return clip.isValid ? clip : nil
    }
    static func read(_ pasteboard: NSPasteboard) -> SpacesObjectClip? {
        if let data = pasteboard.data(forType: pasteboardType) {
            guard data.count <= 90 * 1024 * 1024, let clip = try? JSONDecoder().decode(SpacesObjectClip.self, from: data), clip.isValid else { return nil }; return clip
        }
        guard let text = pasteboard.string(forType: .string), !text.isEmpty, TypeDirection.acceptsCanvasText(text) else { return nil }
        return SpacesObjectClip(layers: [ImportedLayer(name: "Text", x: 24, y: 24, width: 320, height: 80, color: "222222", style: TypeStyle(fontName: "Helvetica", size: 24, text: text))])
    }
    static func paste(_ clip: SpacesObjectClip, into source: TypeDirection, offset: Double = 20) -> (TypeDirection, Set<String>)? {
        guard clip.isValid else { return nil }
        var result = source
        let scale = source.canvasScale ?? 1
        var layers = clip.layers
        let bounds = layers.reduce(CGRect.null) { $0.union($1.rect) }
        let artboard = CanvasPlanCache.plan(for: source).artboardSize
        guard bounds.width <= artboard.width + 0.01, bounds.height <= artboard.height + 0.01 else { return nil }
        let dx = max(-bounds.minX, min(offset, artboard.width - bounds.maxX))
        let dy = max(-bounds.minY, min(offset, artboard.height - bounds.maxY))
        for i in layers.indices {
            layers[i].id = UUID().uuidString
            layers[i].x = (layers[i].x + dx) / scale; layers[i].y = (layers[i].y + dy) / scale
            layers[i].width /= scale; layers[i].height /= scale; layers[i].radius /= scale
            if let width = layers[i].strokeWidth { layers[i].strokeWidth = width / scale }
            layers[i].style = layers[i].style?.scaledForCanvas(1 / scale)
        }
        result.objectLayers = (result.objectLayers ?? []) + layers
        let idsByLayer = Dictionary(uniqueKeysWithValues: CanvasPlan(direction: result).elements.filter { e in layers.contains { $0.id == e.sectionID } }.map { ($0.sectionID, $0.objectID) })
        for group in clip.groups {
            let members = Set(group.compactMap { idsByLayer[layers[$0].id] })
            if members.count > 1 { result.objectGroups = (result.objectGroups ?? []) + [CanvasObjectGroup(members: members)] }
        }
        guard result.isValid else { return nil }
        return (result, Set(idsByLayer.values))
    }
    static func removing(_ ids: Set<String>, from source: TypeDirection) -> TypeDirection {
        var result = source
        let looseSections = Set((source.objectLayers ?? []).map(\.id))
        let looseIDs = Set(CanvasPlanCache.plan(for: source).elements.filter { looseSections.contains($0.sectionID) }.map(\.objectID))
        result.hiddenObjectIDs = (result.hiddenObjectIDs ?? []).union(ids.subtracting(looseIDs))
        for id in ids { result.objectTransforms?.removeValue(forKey: id) }
        let sections = Set(CanvasPlanCache.plan(for: source).elements.filter { ids.contains($0.objectID) }.map(\.sectionID))
        result.objectLayers?.removeAll { sections.contains($0.id) }
        result.objectGroups = result.objectGroups?.compactMap { group in
            var next = group; next.members.subtract(ids); return next.members.count > 1 ? next : nil
        }
        return result
    }
    static func reflected(_ source: TypeDirection, ids: Set<String>, horizontal: Bool) -> TypeDirection {
        let plan = CanvasPlanCache.plan(for: source)
        guard let box = CanvasSelection.bounds(ids, in: plan) else { return source }
        var result = source, transforms = source.objectTransforms ?? [:]
        let scale = source.canvasScale ?? 1
        for e in plan.elements where ids.contains(e.objectID) {
            var t = transforms[e.objectID] ?? CanvasObjectTransform()
            if horizontal { t.x += (box.minX + box.maxX - e.rect.minX - e.rect.maxX) / scale; t.flipX = !(t.flipX ?? false) }
            else { t.y += (box.minY + box.maxY - e.rect.minY - e.rect.maxY) / scale; t.flipY = !(t.flipY ?? false) }
            transforms[e.objectID] = t
        }
        result.objectTransforms = transforms
        return result.isValid ? result : source
    }
    static func resized(_ source: TypeDirection, ids: Set<String>, to target: CGRect) -> TypeDirection {
        let plan = CanvasPlanCache.plan(for: source)
        guard let box = CanvasSelection.bounds(ids, in: plan), box.width > 0, box.height > 0,
              plan.elements.filter({ ids.contains($0.objectID) }).allSatisfy({ $0.text == nil }),
              target.minX >= 0, target.minY >= 0, target.maxX <= plan.artboardSize.width + 0.01, target.maxY <= plan.artboardSize.height + 0.01 else { return source }
        let sx = target.width / box.width, sy = target.height / box.height, scale = source.canvasScale ?? 1
        var result = source, transforms = source.objectTransforms ?? [:]
        for e in plan.elements where ids.contains(e.objectID) {
            var t = transforms[e.objectID] ?? CanvasObjectTransform()
            t.x = t.x * sx + (target.minX - box.minX * sx) / scale
            t.y = t.y * sy + (target.minY - box.minY * sy) / scale
            t.stretchX = (t.stretchX ?? 1) * sx; t.stretchY = (t.stretchY ?? 1) * sy
            guard t.isValid else { return source }; transforms[e.objectID] = t
        }
        result.objectTransforms = transforms
        return result.isValid ? result : source
    }
}

extension TypeBoardEditor {
    var selectedLooseIndex: Int? { guard selectedObjects.count <= 1 else { return nil }; return direction.objectLayers?.firstIndex { $0.id == selectedSection } }
    func objectCommand(_ command: String) {
        guard !library.studio.readBlocked else { return }
        let ids = selectedObjects
        if command == "selectAll" { selectObjects(Set(CanvasPlanCache.plan(for: direction).elements.map(\.objectID))); return }
        if command == "insertText" || command == "insertShape" {
            let text = command == "insertText"
            let layer = ImportedLayer(name: text ? "Text box" : "Rectangle", x: 24, y: 24, width: text ? 280 : 160, height: text ? 80 : 120, color: text ? direction.ink : direction.accent, style: text ? TypeStyle(fontName: style.fontName, size: 24, text: "Your text") : nil)
            if let (next, ids) = SpacesObjects.paste(SpacesObjectClip(layers: [layer]), into: direction, offset: 0) { board.directions[directionIndex] = next; if save(text ? "Add Text Box" : "Add Shape") { selectObjects(ids); editorSession.selectionRevealToken += 1 } }; return
        }
        if command == "group" { groupObjects(); return }; if command == "ungroup" { ungroupObjects(); return }
        if command == "copy" || command == "cut" {
            guard let clip = SpacesObjects.clip(direction, ids: ids), let data = try? JSONEncoder().encode(clip) else { return }
            NSPasteboard.general.clearContents(); NSPasteboard.general.setData(data, forType: SpacesObjects.pasteboardType)
            NSPasteboard.general.setString(clip.layers.compactMap { $0.style?.text }.joined(separator: "\n"), forType: .string)
            if command == "copy" { return }
        }
        if command == "delete" || command == "cut" {
            guard !ids.isEmpty else { return }
            board.directions[directionIndex] = SpacesObjects.removing(ids, from: direction)
            if save(command == "cut" ? "Cut Objects" : "Delete Objects") { selectObjects([]) }; return
        }
        if command == "paste" || command == "pasteInPlace" || command == "duplicate" {
            let clip = command == "duplicate" ? SpacesObjects.clip(direction, ids: ids) : SpacesObjects.read(.general)
            guard let clip, let (next, selection) = SpacesObjects.paste(clip, into: direction, offset: command == "pasteInPlace" ? 0 : 20) else { status = "The clipboard objects cannot fit within this document’s limits."; return }
            board.directions[directionIndex] = next
            if save(command == "duplicate" ? "Duplicate Objects" : "Paste Objects") { selectObjects(selection); editorSession.selectionRevealToken += 1 }; return
        }
        if command == "flipHorizontal" || command == "flipVertical" {
            board.directions[directionIndex] = SpacesObjects.reflected(direction, ids: ids, horizontal: command == "flipHorizontal")
            _ = save("Flip Objects"); return
        }
        if ["mirrorVertical", "mirrorHorizontal", "mirrorBoth"].contains(command), let clip = SpacesObjects.clip(direction, ids: ids) {
            let size = CanvasPlanCache.plan(for: direction).artboardSize
            var candidate = direction, selection = Set<String>()
            let axes = command == "mirrorBoth" ? [(true,false),(false,true),(true,true)] : [(command == "mirrorVertical",command == "mirrorHorizontal")]
            for (x,y) in axes {
                var copy = clip
                for i in copy.layers.indices {
                    if x { copy.layers[i].x = size.width - copy.layers[i].x - copy.layers[i].width; copy.layers[i].flipX = !(copy.layers[i].flipX ?? false) }
                    if y { copy.layers[i].y = size.height - copy.layers[i].y - copy.layers[i].height; copy.layers[i].flipY = !(copy.layers[i].flipY ?? false) }
                }
                guard let (next, ids) = SpacesObjects.paste(copy, into: candidate, offset: 0) else { status = "Mirrored copies exceed document limits."; return }
                candidate = next; selection.formUnion(ids)
            }
            board.directions[directionIndex] = candidate
            if save("Mirror Copies") { selectObjects(selection); editorSession.selectionRevealToken += 1 }
        }
    }
    func resizeObjects(_ ids: Set<String>, to rect: CGRect) {
        let next = SpacesObjects.resized(direction, ids: ids, to: rect)
        guard next != direction else { return }; board.directions[directionIndex] = next; save("Resize Objects")
    }
    var objectActions: some View {
        Group {
            Button("Copy") { objectCommand("copy") }.disabled(selectedObjects.isEmpty)
            Button("Cut") { objectCommand("cut") }.disabled(selectedObjects.isEmpty)
            Button("Paste") { objectCommand("paste") }
            Button("Paste in place") { objectCommand("pasteInPlace") }
            Button("Duplicate") { objectCommand("duplicate") }.disabled(selectedObjects.isEmpty)
            Button("Delete") { objectCommand("delete") }.disabled(selectedObjects.isEmpty)
            Divider()
            Menu("Symmetry") {
                Button("Flip horizontally") { objectCommand("flipHorizontal") }
                Button("Flip vertically") { objectCommand("flipVertical") }
                Divider()
                Button("Mirror copy across vertical canvas axis") { objectCommand("mirrorVertical") }
                Button("Mirror copy across horizontal canvas axis") { objectCommand("mirrorHorizontal") }
                Button("Mirror copies into four quadrants") { objectCommand("mirrorBoth") }
            }.disabled(selectedObjects.isEmpty)
        }
    }
}

/// Eight handles resize non-text objects independently. Text selections retain
/// proportional scaling so font metrics and text editing remain meaningful.
enum SpacesResizeHandle: CaseIterable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left
    var unit: CGPoint {
        switch self {
        case .topLeft: return CGPoint(x: 0,y: 0); case .top: return CGPoint(x: 0.5,y: 0)
        case .topRight: return CGPoint(x: 1,y: 0); case .right: return CGPoint(x: 1,y: 0.5)
        case .bottomRight: return CGPoint(x: 1,y: 1); case .bottom: return CGPoint(x: 0.5,y: 1)
        case .bottomLeft: return CGPoint(x: 0,y: 1); case .left: return CGPoint(x: 0,y: 0.5)
        }
    }
    func point(in box: CGRect) -> CGPoint { CGPoint(x: box.minX + box.width * unit.x, y: box.minY + box.height * unit.y) }
    func resized(_ box: CGRect, delta: CGSize, within canvas: CGSize) -> CGRect {
        var x = box.minX, y = box.minY, right = box.maxX, bottom = box.maxY
        if unit.x == 0 { x = min(right - 1, max(0, x + delta.width)) }
        if unit.x == 1 { right = max(x + 1, min(canvas.width, right + delta.width)) }
        if unit.y == 0 { y = min(bottom - 1, max(0, y + delta.height)) }
        if unit.y == 1 { bottom = max(y + 1, min(canvas.height, bottom + delta.height)) }
        return CGRect(x: x, y: y, width: right-x, height: bottom-y)
    }
}
extension CanvasNativeView {
    @objc func copy(_ sender: Any?) { onObjectCommand?("copy") }
    @objc func cut(_ sender: Any?) { onObjectCommand?("cut") }
    @objc func paste(_ sender: Any?) { onObjectCommand?("paste") }
    func resizeHandles() -> [(SpacesResizeHandle, CGPoint)] {
        guard tool == .auto || tool == .select, let box = CanvasSelection.bounds(objectSelection, in: plan) else { return [] }
        let allShapes = plan.elements.filter { objectSelection.contains($0.objectID) }.allSatisfy { $0.text == nil }
        return (allShapes ? SpacesResizeHandle.allCases : [.bottomRight]).map { ($0,$0.point(in: box)) }
    }
}

enum SpacesObjectChecks {
    static func run() throws {
        func check(_ value: Bool, _ message: String) throws { if !value { throw NSError(domain: "SpacesObjects", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) } }
        let fixture = SpacesInteractionChecks.importedFixture(), original = CanvasPlan(direction: SpacesInteractionChecks.importedFixture())
        let ids = Set(original.elements.map(\.objectID))
        var grouped = fixture; grouped.objectGroups = [CanvasObjectGroup(members: ids)]
        let clip = SpacesObjects.clip(grouped, ids: ids)!
        let decoded = try JSONDecoder().decode(SpacesObjectClip.self, from: JSONEncoder().encode(clip))
        try check(decoded.isValid && decoded.groups.count == 1, "Clipboard must retain text, shapes and groups")
        var cases = 0
        for kind in CanvasKind.allCases {
            for scale in [0.75, 1.0, 2.0] {
                var destination = kind == .imported ? fixture : TypeDirection(name: "Paste destination", fonts: ["Helvetica"])
                destination.canvas = kind; destination.canvasScale = scale
                destination.canvasHeight = 1000
                let count = CanvasPlan(direction: destination).elements.count
                guard let (next, selection) = SpacesObjects.paste(decoded, into: destination, offset: 0) else { throw NSError(domain: "SpacesObjects", code: 2, userInfo: [NSLocalizedDescriptionKey: "Paste failed: \(kind) \(scale)"]) }
                let plan = CanvasPlan(direction: next), copied = plan.elements.filter { selection.contains($0.objectID) }
                try check(copied.count == 3 && plan.elements.count == count + 3 && selection.isDisjoint(with: ids), "Paste must create independent object IDs")
                for (a,b) in zip(original.elements,copied) {
                    try check(abs(a.rect.width-b.rect.width)<1 && abs(a.rect.height-b.rect.height)<1 && a.text?.string == b.text?.string, "Paste must preserve rendered text/geometry across scales")
                }
                try check(next.objectGroups?.last?.members == selection, "Pasted groups must refer to new IDs")
                let textObject = copied.first { $0.text != nil }!
                let changedFont = StudioFontDrop.applying("Courier", to: next, element: textObject)!
                try check(StudioFontCollection.fontNames(in: changedFont).contains("Courier"), "Pasted text fonts must appear in handoff and missing-font reports")
                try check(CanvasPlan(direction: changedFont).elements.first { $0.objectID == textObject.objectID }?.style?.fontName == "Courier", "Font drops must edit the independent text box")
                let saved = try JSONDecoder().decode(TypeDirection.self, from: JSONEncoder().encode(next))
                try check(saved == next && CanvasPlan(direction: saved).elements.count == plan.elements.count, "Pasted objects must survive reload")
                let removed = SpacesObjects.removing(selection, from: next)
                try check(CanvasPlan(direction: removed).elements.count == count, "Delete must remove only selected copies")
                try check((removed.hiddenObjectIDs ?? []).isDisjoint(with: selection), "Deleted loose objects must not accumulate hidden IDs")
                cases += 1
            }
        }
        let shape = original.elements[0], shapes: Set<String> = [shape.objectID]
        for handle in SpacesResizeHandle.allCases {
            let target = handle.resized(shape.rect, delta: CGSize(width: 12,height: 8), within: original.artboardSize)
            let result = SpacesObjects.resized(fixture, ids: shapes, to: target), plan = CanvasPlan(direction: result)
            try check(plan.elements[0].rect == target && plan.elements[1].rect == original.elements[1].rect, "Every shape handle must resize without moving unselected text")
            let aligned = CanvasSelection.aligned(direction: result, ids: shapes, alignment: .right)
            try check(abs(CanvasPlan(direction: aligned).elements[0].rect.maxX-original.artboardSize.width)<0.01, "Stretched objects must remain alignable")
        }
        let flipped = SpacesObjects.reflected(grouped, ids: ids, horizontal: true)
        let twice = SpacesObjects.reflected(flipped, ids: ids, horizontal: true)
        for (a,b) in zip(original.elements,CanvasPlan(direction: twice).elements) { try check(a.rect == b.rect && !b.flipX, "Two flips must restore geometry and orientation") }
        var board = TypeBoard(); board.directions = [flipped]
        let payload = FigmaLayoutExporter.payload(board: board)
        let imported = try FigmaLayoutImporter.board(data: JSONSerialization.data(withJSONObject: payload), fonts: [])
        try check(CanvasPlan(direction: imported.directions[0]).elements.allSatisfy(\.flipX), "Figma source round trip must retain reflections")
        let pb = NSPasteboard(name: NSPasteboard.Name("Typefield-Spaces-Checks-" + UUID().uuidString))
        defer { pb.releaseGlobally() }
        pb.setData(try JSONEncoder().encode(clip), forType: SpacesObjects.pasteboardType)
        try check(SpacesObjects.read(pb)?.layers.count == 3, "Typed object clipboard must decode")
        pb.clearContents(); pb.setString("Editable plain text", forType: .string)
        try check(SpacesObjects.read(pb)?.layers.first?.style?.text == "Editable plain text", "Plain text paste must produce an editable text box")
        pb.clearContents(); pb.setData(Data("{}".utf8), forType: SpacesObjects.pasteboardType)
        try check(SpacesObjects.read(pb) == nil, "Malformed object clipboard must be rejected")
        let responder = CanvasNativeView(plan: original)
        responder.plan = original; responder.directionID = fixture.id; responder.tool = .auto
        var commands: [String] = [], selected = Set<String>()
        responder.onObjectCommand = { commands.append($0) }; responder.onObjectSelection = { selected = $0 }
        responder.copy(nil); responder.cut(nil); responder.paste(nil); responder.selectAll(nil)
        try check(commands == ["copy", "cut", "paste"] && selected == ids, "Canvas responder must route clipboard and select all")
        responder.plan = CanvasPlan(arrangement: original.sections, width: 240)
        responder.selectAll(nil)
        try check(commands.last == "selectAll", "Arrangement must select actual canvas objects, not preview labels")
        let old = try JSONDecoder().decode(CanvasObjectTransform.self, from: Data("{\"scale\":1,\"x\":2,\"y\":3}".utf8))
        try check(old.isValid && old.stretchX == nil && old.flipX == nil, "Older object transforms must decode")
        print("PASS: \(cases) cross-format/scaled clipboard round trips, fresh grouped IDs, delete, eight shape handles, alignment, double reflection, Figma mirror round trip and malformed clipboard")
    }
}
