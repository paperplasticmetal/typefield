import AppKit

enum CanvasSelectionChecks {
    static func run() throws {
        func check(_ passed: @autoclosure () -> Bool, _ message: String) throws {
            if !passed() { throw NSError(domain: "Typefield.SelectionChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        let original = TypeDirection(name: "Selection fixture", fonts: ["Helvetica"])
        let plan = CanvasPlan(direction: original)
        let ids = Set(plan.elements.map(\.objectID))
        try check(ids.count == plan.elements.count && !ids.contains(""), "Every rendered object needs a unique selection ID")
        let objects = Array(plan.elements.filter { $0.text != nil }.prefix(2))
        let selection = Set(objects.map(\.objectID))
        let box = CanvasSelection.bounds(selection, in: plan)!
        var moved = CanvasSelection.change(direction: original, ids: selection, anchor: box.origin, scale: 1, delta: CGSize(width: 7.25, height: 9.5))
        let movedPlan = CanvasPlan(direction: moved)
        for (before, after) in zip(plan.elements, movedPlan.elements) {
            if selection.contains(before.objectID) { try check(abs(after.rect.minX-before.rect.minX-7.25) < 0.001 && abs(after.rect.minY-before.rect.minY-9.5) < 0.001, "Bulk moves must retain exact fractional deltas") }
            else { try check(before.rect == after.rect, "Bulk moves must not affect unselected geometry") }
        }
        moved.objectGroups = [CanvasObjectGroup(members: selection)]
        let restored = try JSONDecoder().decode(TypeDirection.self, from: JSONEncoder().encode(moved))
        try check(restored == moved && restored.isValid, "Groups and transforms must survive document round trips")
        try check(CanvasSelection.expanded([objects[0].objectID], groups: restored.objectGroups!) == selection, "Clicking a group member selects its group")
        let scaled = CanvasSelection.change(direction: moved, ids: selection, anchor: box.origin, scale: 0.75, delta: .zero)
        let scaledPlan = CanvasPlan(direction: scaled)
        let before = movedPlan.elements.first { $0.objectID == objects[0].objectID }!
        let after = scaledPlan.elements.first { $0.objectID == objects[0].objectID }!
        try check(abs(after.rect.width-before.rect.width*0.75)<0.001 && abs((after.style?.size ?? 0)-(before.style?.size ?? 0)*0.75)<0.001, "Scaling must scale geometry and typography together")
        try check(CanvasSelection.marquee(CGRect(origin: .zero, size: plan.artboardSize), in: plan) == ids, "Whole-canvas marquee must include every object")
        let pdf = try CanvasPreviewPDF.data(directions: [scaled])
        try check(!pdf.isEmpty, "Transformed content must export to PDF")
        let invalid = CanvasSelection.change(direction: moved, ids: selection, anchor: .zero, scale: 1000, delta: .zero)
        try check(invalid == moved, "Unsafe transformations must leave the document unchanged")
        var doubled = original; doubled.canvasScale = 2
        let doubledPlan = CanvasPlan(direction: doubled)
        let shifted = CanvasSelection.change(direction: doubled, ids: selection, anchor: .zero, scale: 1, delta: CGSize(width: 20, height: 10))
        let shiftedPlan = CanvasPlan(direction: shifted)
        let a = doubledPlan.elements.first { $0.objectID == objects[0].objectID }!, b = shiftedPlan.elements.first { $0.objectID == objects[0].objectID }!
        try check(abs(b.rect.minX-a.rect.minX-20)<0.001, "Content translation must account for canvas scale exactly once")
        let position = CanvasBoardLayout.moved(from: CanvasBoardPosition(x: 40, y: 50), by: CGSize(width: 13.25, height: 7.75), zoom: 0.5)
        try check(position.x == 66.5 && position.y == 65.5, "Frame motion must not snap to a grid")
        print("PASS: object selection, fractional bulk transforms, group persistence, scaled geometry/typography, PDF output and frame movement")
    }
}
