import AppKit

enum SpacesInteractionChecks {
    static func importedFixture() -> TypeDirection {
        var d = TypeDirection(name: "Interaction fixture", fonts: ["Helvetica"])
        d.canvas = .imported; d.width = 640; d.canvasWidth = 640; d.canvasHeight = 480
        d.importedLayout = ImportedLayout(width: 900, height: 700, layers: [
            ImportedLayer(id: "qa-shape", name: "Coral rectangle", x: 40, y: 40, width: 180, height: 100, color: "E87050"),
            ImportedLayer(id: "qa-text", name: "Headline", x: 280, y: 70, width: 240, height: 60, color: "222222", style: TypeStyle(fontName: "Helvetica", size: 24, text: "Alignment fixture")),
            ImportedLayer(id: "qa-shape-two", name: "Blue rectangle", x: 80, y: 240, width: 150, height: 90, color: "526AC2")])
        return d
    }
    static func run() throws {
        func check(_ value: Bool, _ message: String) throws {
            if !value { throw NSError(domain: "Typefield.SpacesInteractions", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        var fixtures = CanvasKind.allCases.filter { $0 != .imported }.map { kind -> TypeDirection in
            var d = TypeDirection(name: kind.rawValue, fonts: ["Helvetica"]); d.canvas = kind; if kind == .custom { d.addedBlocks = [LayoutBlock(role: .heading), LayoutBlock(role: .body)] }; return d
        }
        fixtures.append(importedFixture())
        var count = 0
        for fixture in fixtures {
            for scale in [0.75, 1.0, 2.0] {
                var source = fixture; source.canvasScale = scale
                let initial = CanvasPlan(direction: source)
                let selected = Set(initial.elements.filter { $0.text != nil }.prefix(2).map(\.objectID))
                for ids in [Set(selected.prefix(1)), selected] {
                    for alignment in StudioCanvasAlignment.allCases {
                        var current = source
                        let expected = alignment.origin(for: CanvasSelection.bounds(ids, in: initial)!, in: initial.artboardSize)
                        for _ in 0..<5 { current = CanvasSelection.aligned(direction: current, ids: ids, alignment: alignment) }
                        let result = CanvasPlan(direction: current)
                        let bounds = CanvasSelection.bounds(ids, in: result)!
                        try check(abs(bounds.minX-expected.x)<0.01 && abs(bounds.minY-expected.y)<0.01, "\(fixture.name): repeated \(alignment) missed the selected frame at scale \(scale): expected \(expected), got \(bounds.origin), canvas \(initial.artboardSize) -> \(result.artboardSize)")
                        try check(result.artboardSize == initial.artboardSize, "\(fixture.name): \(alignment) changed artboard size from \(initial.artboardSize) to \(result.artboardSize)")
                        for (a,b) in zip(initial.elements,result.elements) where !ids.contains(a.objectID) { try check(a.rect == b.rect, "\(fixture.name): \(alignment) moved unselected \(a.objectID) at scale \(scale): \(a.rect) -> \(b.rect)") }
                        try check(current.isValid, "Alignment produced an invalid document")
                        let decoded = try JSONDecoder().decode(TypeDirection.self, from: JSONEncoder().encode(current))
                        try check(CanvasPlan(direction: decoded).artboardSize == initial.artboardSize, "Alignment did not retain canvas size after reload")
                        count += 1
                    }
                }
            }
        }
        for scale in [0.75, 1.0, 2.0] {
            var fixture = importedFixture(); fixture.canvasScale = scale
            let ids = Set(CanvasPlan(direction: fixture).elements.filter { $0.text != nil }.map(\.objectID))
            let aligned = CanvasSelection.aligned(direction: fixture, ids: ids, alignment: .bottom)
            let plan = CanvasPlan(direction: aligned)
            let edge = CanvasBoardLayout.resized(canvas: aligned, artboardSize: plan.artboardSize, position: CanvasBoardPosition(x: 20, y: 20), edge: .bottom, by: CGSize(width: 0, height: 30 * scale), zoom: 1)
            try check(edge.warning == nil && abs((edge.height ?? 0) - 510) < 0.01, "Resizing aligned content must preserve scale and requested height")
            let corner = CanvasBoardLayout.resized(canvas: aligned, artboardSize: plan.artboardSize, position: CanvasBoardPosition(x: 20, y: 20), corner: .bottomRight, by: CGSize(width: 64, height: 48), zoom: 1)
            try check(corner.warning == nil && corner.scale > scale, "Corner resizing must accept text aligned to the canvas edge")
        }
        let imported = importedFixture(), plan = CanvasPlan(direction: imported)
        let session = StudioEditorSession(board: TypeBoard())
        for _ in 0..<20 {
            for object in plan.elements {
                session.selectObjects([object.objectID], in: imported)
                try check(session.selectedSection == object.sectionID && session.selectedObjects == [object.objectID], "Canvas selection failed to synchronize the inspector layer")
            }
            session.selectObjects(Set(plan.elements.map(\.objectID)), in: imported)
            try check(session.selectedSection == nil && session.selectedTextID == nil, "Multiselection retained a stale single-layer inspector")
            session.selectObjects([], in: imported)
            try check(session.selectedObjects.isEmpty && session.selectedSection == nil, "Deselect retained inspector state")
        }
        let rowPlan = CanvasPlan(arrangement: plan.sections, width: 240)
        try check(rowPlan.isArrangement && !plan.isArrangement, "Arrangement must use row interaction semantics")
        let transformed = CanvasSelection.change(direction: imported, ids: [plan.elements[1].objectID], anchor: .zero, scale: 0.8, delta: CGSize(width: 10, height: 20))
        let aligned = CanvasSelection.aligned(direction: transformed, ids: [plan.elements[1].objectID], alignment: .right)
        let final = CanvasPlan(direction: aligned)
        try check(abs(final.elements[1].rect.maxX-final.artboardSize.width)<0.01 && final.artboardSize == plan.artboardSize, "Alignment must compose with existing object transforms and explicit imported canvas bounds")
        print("PASS: \(count) repeated alignment scenarios, fixed canvas bounds, selection/inspector synchronization and arrangement semantics")
    }
}
