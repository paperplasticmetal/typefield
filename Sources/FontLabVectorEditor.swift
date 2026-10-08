import SwiftUI
import AppKit

/// Session-local history follows a glyph while the user edits other letters.
/// Limit retained geometry as well as steps so dense imports cannot retain
/// dozens of unbounded full-outline copies.
struct FontLabGlyphEditHistory {
    private(set) var undoEntries: [String: [FontLabGlyph]] = [:]
    private(set) var redoEntries: [String: [FontLabGlyph]] = [:]
    private var recent: [String] = []
    mutating func record(_ glyph: FontLabGlyph) {
        undoEntries[glyph.character, default: []].append(glyph)
        redoEntries[glyph.character] = []
        trim(glyph.character)
    }
    mutating func undo(_ current: FontLabGlyph) -> FontLabGlyph? {
        guard let previous = undoEntries[current.character]?.popLast() else { return nil }
        redoEntries[current.character, default: []].append(current)
        trim(current.character)
        return previous
    }
    mutating func redo(_ current: FontLabGlyph) -> FontLabGlyph? {
        guard let next = redoEntries[current.character]?.popLast() else { return nil }
        undoEntries[current.character, default: []].append(current)
        trim(current.character)
        return next
    }
    private mutating func trim(_ character: String) {
        recent.removeAll { $0 == character }; recent.append(character)
        undoEntries[character] = Array((undoEntries[character] ?? []).suffix(60))
        redoEntries[character] = Array((redoEntries[character] ?? []).suffix(60))
        func cost(_ values: [String: [FontLabGlyph]]) -> Int {
            values.values.flatMap { $0 }.reduce(0) { total, glyph in
                total + glyph.strokes.reduce(0) { $0 + $1.points.count + ($1.contours?.reduce(0) { $0 + $1.count } ?? 0) + ($1.vectorPaths?.reduce(0) { $0 + $1.nodes.count } ?? 0) }
            }
        }
        while recent.count > 20 || cost(undoEntries) + cost(redoEntries) > 200_000 {
            guard let oldest = recent.first else { break }
            if recent.count > 1 { undoEntries.removeValue(forKey: oldest); redoEntries.removeValue(forKey: oldest); recent.removeFirst() }
            else if (undoEntries[oldest]?.count ?? 0) > 1 { undoEntries[oldest]?.removeFirst() }
            else if (redoEntries[oldest]?.count ?? 0) > 1 { redoEntries[oldest]?.removeFirst() }
            else { break } // Retain one usable undo/redo even for a large glyph.
        }
    }
}

enum FontLabVectorTool: String, CaseIterable, Identifiable {
    case select = "Select", pen = "Pen", line = "Line", rectangle = "Rectangle", ellipse = "Ellipse", hand = "Hand"
    var id: String { rawValue }
    var icon: String { switch self { case .select:return "cursorarrow";case .pen:return "point.topleft.down.to.point.bottomright.curvepath";case .line:return "line.diagonal";case .rectangle:return "rectangle";case .ellipse:return "circle";case .hand:return "hand.draw" } }
    var shortcut: String { switch self { case .select:return "V";case .pen:return "P";case .line:return "L";case .rectangle:return "R";case .ellipse:return "O";case .hand:return "H" } }
}

/// Clipboard coordinates retain their physical em size and distance from the
/// baseline when moving artwork between glyphs or projects.
struct FontLabVectorClipboard: Codable {
    var version = 1
    let designWidth: Double
    let baseline: Double
    let paths: [FontLabVectorPath]
    var groups: [[UUID]]? = nil

    var isValid: Bool {
        version == 1 && designWidth.isFinite && (0.02...3).contains(designWidth) &&
        baseline.isFinite && (0...1).contains(baseline) && !paths.isEmpty &&
        paths.count <= 256 && Set(paths.map(\.id)).count == paths.count &&
        paths.reduce(0, { $0 + $1.nodes.count }) <= 30_000 && paths.allSatisfy(\.isValid) &&
        (groups.map { groups in
            let ids = groups.flatMap { $0 }
            return groups.allSatisfy { !$0.isEmpty } && ids.count == paths.count && Set(ids) == Set(paths.map(\.id))
        } ?? true)
    }

    func mapped(toWidth width: Double, baseline targetBaseline: Double) -> [FontLabVectorPath]? {
        guard isValid, width.isFinite, (0.02...3).contains(width), targetBaseline.isFinite else { return nil }
        func boundary(_ value: Double, _ limits: ClosedRange<Double>) -> Double {
            if value < limits.lowerBound, value >= limits.lowerBound - 1e-12 { return limits.lowerBound }
            if value > limits.upperBound, value <= limits.upperBound + 1e-12 { return limits.upperBound }
            return value
        }
        func point(_ value: FontLabPoint, anchor: Bool) -> FontLabPoint {
            var result = value
            result.x *= designWidth / width
            result.y += targetBaseline - baseline
            // A mathematically exact fit can land one floating-point step
            // outside the box after converting between physical em frames.
            let limits = anchor ? 0.0...1.0 : -2.0...3.0
            result.x = boundary(result.x, limits);result.y = boundary(result.y, limits)
            return result
        }
        var result = paths
        for p in result.indices { for n in result[p].nodes.indices {
            result[p].nodes[n].point = point(result[p].nodes[n].point,anchor:true)
            result[p].nodes[n].incoming = result[p].nodes[n].incoming.map { point($0,anchor:false) }
            result[p].nodes[n].outgoing = result[p].nodes[n].outgoing.map { point($0,anchor:false) }
        } }
        return result.allSatisfy(\.isValid) ? result : nil
    }
}

final class FontLabVectorEditor: ObservableObject {
    static let defaultMessage = ""
    @Published var glyph: FontLabGlyph {
        didSet { cachedPaths = nil }
    }
    // Legacy polygon outlines require node conversion. Reuse that conversion
    // across drawing, hit testing and selection until the glyph changes.
    private var cachedPaths: [FontLabVectorPath]?
    @Published var componentStrokes: [FontLabStroke] = []
    @Published var metrics: FontLabMetrics
    @Published var tool = FontLabVectorTool.select {
        didSet {
            if tool != .pen { activePath = nil }
            if tool == .select && oldValue != .select && objectSelection { selectCompleteObjects() }
        }
    }
    @Published var selection = Set<UUID>()
    @Published var zoom = 1.0
    @Published var pan = CGPoint.zero
    @Published var grid = true
    @Published var snap = true
    @Published var fill = true
    @Published var objectSelection = false {
        didSet { if objectSelection && !oldValue { selectCompleteObjects() } }
    }
    @Published var inkColor = Color(nsColor: .labelColor)
    @Published var message = FontLabVectorEditor.defaultMessage
    var onCommit: (FontLabGlyph) -> Void = { _ in }
    var onUndo: () -> Void = {}
    var onRedo: () -> Void = {}
    var onFocusSelectionRequested: () -> Void = {}
    @Published var activePath: UUID?
    init(glyph: FontLabGlyph, metrics: FontLabMetrics) { self.glyph=glyph;self.metrics=metrics }
    var paths: [FontLabVectorPath] {
        if let cachedPaths { return cachedPaths }
        let value = FontLabVectorMath.paths(in: glyph)
        cachedPaths = value
        return value
    }
    var selectedNodes: [FontLabVectorNode] { paths.flatMap(\.nodes).filter { selection.contains($0.id) } }
    var selectedBounds: CGRect { FontLabVectorMath.bounds(selectedNodes.map(\.point)) }
    var selectedFocusBounds: CGRect {
        var geometry: [FontLabPoint] = []
        for path in paths {
            let selectedIndices = Set(path.nodes.indices.filter { selection.contains(path.nodes[$0].id) })
            guard !selectedIndices.isEmpty else { continue }
            for index in selectedIndices {
                let node = path.nodes[index]
                geometry.append(node.point)
                if let incoming = node.incoming { geometry.append(incoming) }
                if let outgoing = node.outgoing { geometry.append(outgoing) }
            }
            for segment in 0..<path.segmentCount {
                let next = (segment + 1) % path.nodes.count
                if selectedIndices.contains(segment) || selectedIndices.contains(next) {
                    // The cubic is inside the convex hull of its anchors and
                    // controls, so these bounds frame both the selected curve
                    // and its handles without pulling in unrelated contours.
                    geometry.append(contentsOf: path.controls(segment))
                }
            }
        }
        return FontLabVectorMath.bounds(geometry)
    }
    var openCount: Int { paths.filter { !$0.closed }.count }
    func proofGlyphs(in project: FontLabProject) -> [String: FontLabGlyph] {
        var preview = project
        if preview.characters.contains(glyph.character) { preview.glyphs[glyph.character] = glyph }
        return preview.outputProject.glyphs
    }
    var interactionHint: String {
        switch tool {
        case .select:
            return objectSelection
                ? "Drag a shape to move it. Choose Nodes (A) to edit its outline. Space-drag pans."
                : "Drag an anchor to move it, a handle to adjust curvature, or an edge to bend it. Double-click an edge to add a node."
        case .pen: return "Click for straight segments; drag for curves. Click an open endpoint to continue or connect. Click the first point to close; Return finishes."
        case .line: return "Drag a line. Shift constrains it to 45° angles. Snap to an open endpoint to connect; Outline stroke gives the line a filled width."
        case .rectangle: return "Drag to draw a rectangle. Hold Shift for a square. A edits its points."
        case .ellipse: return "Drag to draw an ellipse. Hold Shift for a circle. A edits its points."
        case .hand: return "Drag to pan the canvas. Choose Nodes (A) to edit points or F to toggle the fill."
        }
    }
    func finishPath() {
        activePath = nil
        message = "Path finished. Click an open endpoint to continue, or empty space to start another path."
    }
    private var selectedOpenEndpoint: (path: Int, node: UUID)? {
        guard selection.count == 1, let id = selection.first else { return nil }
        guard let index = paths.firstIndex(where: { !$0.closed && ($0.nodes.first?.id == id || $0.nodes.last?.id == id) }) else { return nil }
        return (index, id)
    }
    var canContinueEndpoint: Bool { selectedOpenEndpoint != nil }
    func continueSelectedEndpoint() {
        guard let endpoint = selectedOpenEndpoint,
              let oriented = FontLabPathConstruction.continuing(paths[endpoint.path], from: endpoint.node) else { return }
        var value = paths
        value[endpoint.path] = oriented
        if oriented != paths[endpoint.path], !apply(value) { return }
        tool = .pen; objectSelection = false; activePath = oriented.id
        selection = [endpoint.node]
        message = "Continuing this endpoint. Click to add a straight segment or drag to add a curve."
    }
    var canCloseActivePath: Bool {
        guard let path = paths.first(where: { $0.id == activePath }), let first = path.nodes.first, let last = path.nodes.last else { return false }
        return FontLabPathConstruction.joining([path], from: last.id, to: first.id, preservingBridgeHandles: true) != nil
    }
    func closeActivePath() {
        guard let path = paths.first(where: { $0.id == activePath }), let first = path.nodes.first, let last = path.nodes.last,
              let result = FontLabPathConstruction.joining(paths, from: last.id, to: first.id, preservingBridgeHandles: true) else { return }
        if apply(result) { activePath = nil; message = "Path closed. Its outline now controls the filled shape." }
    }
    private var selectedOpenPaths: [FontLabVectorPath] {
        paths.filter { !$0.closed && $0.nodes.count > 1 && $0.nodes.contains { selection.contains($0.id) } }
    }
    var canCloseTouchedPaths: Bool {
        selectedOpenPaths.contains { path in
            FontLabPathConstruction.joining([path], from: path.nodes.last!.id, to: path.nodes[0].id,
                                            preservingBridgeHandles: true) != nil
        }
    }
    func closeTouchedPaths() {
        let ids = Set(selectedOpenPaths.map(\.id))
        var value = paths
        for path in paths where ids.contains(path.id) {
            if let joined = FontLabPathConstruction.joining(value, from: path.nodes.last!.id, to: path.nodes[0].id,
                                                           preservingBridgeHandles: true) { value = joined }
        }
        if apply(value) { activePath = nil; message = "Closed the selected paths. Their outlines now form filled shapes." }
    }
    var canOutlineSelectedPaths: Bool { !selectedOpenPaths.isEmpty }
    func strokeOutlinePreview(widthInUnits: Double) -> [[FontLabVectorPath]]? {
        guard widthInUnits.isFinite, (2...200).contains(widthInUnits), !selectedOpenPaths.isEmpty else { return nil }
        return FontLabPathConstruction.outlined(selectedOpenPaths, width: widthInUnits / 1000, designWidth: glyph.resolvedDesignWidth)
    }
    @discardableResult func outlineSelectedPaths(widthInUnits: Double) -> Bool {
        guard widthInUnits.isFinite, (2...200).contains(widthInUnits) else {
            message = "Enter a stroke width between 2 and 200 font units."; return false
        }
        let chosen = selectedOpenPaths
        guard !chosen.isEmpty else { message = "Select an open path with at least two points."; return false }
        guard let groups = FontLabPathConstruction.outlined(chosen, width: widthInUnits / 1000, designWidth: glyph.resolvedDesignWidth) else {
            message = "That stroke does not fit inside the design box. Use a narrower width or move the path away from its edge."; return false
        }
        let replacements = Dictionary(uniqueKeysWithValues: zip(chosen, groups).map { ($0.0.id, $0.1) })
        let value = paths.flatMap { replacements[$0.id] ?? [$0] }
        guard apply(value, pathGroups: groups.map { $0.map(\.id) }) else { return false }
        selection = Set(groups.flatMap { $0 }.flatMap(\.nodes).map(\.id))
        activePath = nil; tool = .select; objectSelection = false
        message = "Created filled, editable outlines. Undo restores the open paths."
        return true
    }
    func selectContours(closed: Bool) {
        tool = .select; objectSelection = false; activePath = nil
        selection = Set(paths.filter { $0.closed == closed }.flatMap(\.nodes).map(\.id))
        message = closed ? "Selected the filled outlines. Drag their anchors or handles to change the letter."
            : "Selected open paths. These do not fill; close them to make shapes, or delete them if unwanted."
    }
    func selectContour(_ id: UUID) {
        guard let path = paths.first(where: { $0.id == id }) else { return }
        tool = .select; objectSelection = false; activePath = nil
        selection = Set(path.nodes.map(\.id))
        message = path.closed ? "Closed contour selected. Its outline controls the filled letter."
            : "Open path selected. It does not fill until closed."
    }
    var selectedContourIDs: Set<UUID> {
        Set(paths.filter { !$0.nodes.isEmpty && $0.nodes.allSatisfy { selection.contains($0.id) } }.map(\.id))
    }
    var canCloseSelectedContours: Bool {
        let ids = selectedContourIDs
        return paths.contains { ids.contains($0.id) && !$0.closed && $0.nodes.count >= 3 }
    }
    func closeSelectedContours() {
        let ids = selectedContourIDs
        var value = paths
        for index in value.indices where ids.contains(value[index].id) && value[index].nodes.count >= 3 {
            value[index].closed = true
        }
        if apply(value) { activePath = nil }
    }
    func deleteSelectedContours() {
        let ids = selectedContourIDs
        guard !ids.isEmpty else { return }
        if apply(paths.filter { !ids.contains($0.id) }) { activePath = nil }
    }
    func receive(_ value: FontLabGlyph) {
        guard value != glyph else { return }
        let previousActive = paths.first(where: { $0.id == activePath })
        glyph=value;selection.formIntersection(Set(paths.flatMap(\.nodes).map(\.id)))
        guard let restored = paths.first(where: { $0.id == activePath && !$0.closed }) else {
            activePath = nil; return
        }
        // Undo can reverse a Continue-from-first orientation edit. Finish that
        // construction instead of silently appending at the opposite endpoint.
        if let previousActive, previousActive.nodes.count > 1,
           restored.nodes.first?.id == previousActive.nodes.last?.id,
           restored.nodes.last?.id == previousActive.nodes.first?.id {
            activePath = nil
            message = Self.defaultMessage
        }
    }
    @discardableResult func apply(_ value: [FontLabVectorPath], commit: Bool = true, pathGroups: [[UUID]] = []) -> Bool {
        guard value.count <= 256, value.reduce(0,{$0+$1.nodes.count}) <= 30_000, value.allSatisfy(\.isValid) else {
            message="Keep anchors inside the design box and use fewer than 30,000 nodes.";return false
        }
        guard value != paths || !pathGroups.isEmpty else { return false }
        let next=FontLabVectorMath.replacingPaths(in:glyph,with:value,pathGroups:pathGroups)
        guard next.isValid else { message="That edit is outside the glyph limits.";return false }
        guard next != glyph else { return false }
        if message != Self.defaultMessage { message=Self.defaultMessage }
        glyph=next
        selection.formIntersection(Set(value.flatMap(\.nodes).map(\.id)))
        if commit { onCommit(next) }
        return true
    }
    func finishGesture(from before: FontLabGlyph) { if glyph != before { onCommit(glyph) } }
    func selectAll() { selection=Set(paths.flatMap(\.nodes).map(\.id)) }
    private func selectCompleteObjects() {
        let partial = selection, value = paths
        guard !partial.isEmpty else { return }
        selection=[]
        for index in value.indices where value[index].nodes.contains(where: { partial.contains($0.id) }) {
            if !value[index].nodes.allSatisfy({ selection.contains($0.id) }) { selectObject(index,adding:true) }
        }
    }
    func fit() { zoom=1;pan = .zero }
    func requestFocusSelection() { onFocusSelectionRequested() }
    func selectObject(_ index: Int, adding: Bool) {
        let value = paths
        guard value.indices.contains(index) else { return }
        let outlines = value.map(\.cgPath)
        let outlineBounds = outlines.map(\.boundingBoxOfPath)
        var outer = index
        for i in value.indices where value[i].closed && i != index {
            if outlineBounds[i].contains(outlineBounds[outer]),
               let first = value[outer].nodes.first,
               outlines[i].contains(CGPoint(x: first.point.x * 1000, y: first.point.y * 1000)) { outer = i }
        }
        let chosen = value.indices.filter { i in
            i == outer || (value[i].closed && value[outer].closed && value[i].nodes.allSatisfy {
                outlines[outer].contains(CGPoint(x: $0.point.x * 1000, y: $0.point.y * 1000))
            })
        }
        let ids = Set(chosen.flatMap { value[$0].nodes.map(\.id) })
        selection = adding ? selection.union(ids) : ids
    }
    static func resized(_ paths: [FontLabVectorPath], selection: Set<UUID>, anchor: FontLabPoint, sx: Double, sy: Double) -> [FontLabVectorPath] {
        var result = paths
        func point(_ p: FontLabPoint) -> FontLabPoint {
            var p = p; p.x = anchor.x + (p.x-anchor.x)*sx; p.y = anchor.y + (p.y-anchor.y)*sy; return p
        }
        for p in result.indices { for n in result[p].nodes.indices where selection.contains(result[p].nodes[n].id) {
            result[p].nodes[n].point = point(result[p].nodes[n].point)
            result[p].nodes[n].incoming = result[p].nodes[n].incoming.map(point)
            result[p].nodes[n].outgoing = result[p].nodes[n].outgoing.map(point)
        } }
        return result
    }
    static func focusTransform(selectionBounds: CGRect, viewport: CGSize, designWidth: Double) -> (zoom: Double, pan: CGPoint)? {
        guard !selectionBounds.isNull, !selectionBounds.isInfinite,
              selectionBounds.minX.isFinite, selectionBounds.minY.isFinite,
              selectionBounds.width.isFinite, selectionBounds.height.isFinite,
              viewport.width.isFinite, viewport.height.isFinite, designWidth.isFinite, designWidth > 0 else { return nil }
        let viewWidth = Double(viewport.width), viewHeight = Double(viewport.height)
        let width = Double(designWidth)
        let baseEm = max(80, min((viewWidth - 90) / width, viewHeight - 75))
        let availableWidth = max(1, viewWidth - 64)
        let availableHeight = max(1, viewHeight - 64)
        let selectionWidth = max(Double(selectionBounds.width) * width, 0.02 * width)
        let selectionHeight = max(Double(selectionBounds.height), 0.02)
        let zoom = min(8, max(0.1, min(availableWidth / (baseEm * selectionWidth), availableHeight / (baseEm * selectionHeight))))
        let em = baseEm * zoom
        return (zoom, CGPoint(x: CGFloat(-(Double(selectionBounds.midX) - 0.5) * em * width),
                              y: CGFloat(-(Double(selectionBounds.midY) - 0.5) * em)))
    }
    func setPenWidth(_ units: Double) {
        guard units.isFinite, (2...200).contains(units) else { return }
        var next = glyph
        for i in next.strokes.indices where !next.strokes[i].points.isEmpty { next.strokes[i].width = units / 1000 }
        if next != glyph { glyph = next; onCommit(next) }
    }
    func modifySelected(_ change: (inout FontLabVectorNode, Int, FontLabVectorPath) -> Void) {
        var value=paths
        for p in value.indices { let original=value[p]; for n in value[p].nodes.indices where selection.contains(value[p].nodes[n].id) { change(&value[p].nodes[n],n,original) } }
        _=apply(value)
    }
    func move(dx:Double,dy:Double) {
        modifySelected { node,_,_ in
            node.point.x += dx;node.point.y += dy
            if node.incoming != nil { node.incoming!.x += dx;node.incoming!.y += dy }
            if node.outgoing != nil { node.outgoing!.x += dx;node.outgoing!.y += dy }
        }
    }
    func setCoordinate(_ value: Double, x: Bool) {
        guard value.isFinite else { message="Enter a finite coordinate in font units."; return }
        guard !selection.isEmpty else { return }
        if message != Self.defaultMessage { message=Self.defaultMessage }
        let b=selectedBounds
        let dx=x ? value/(glyph.resolvedDesignWidth*1000)-b.minX : 0,dy=x ? 0 : value/1000+metrics.baseline-b.minY
        guard abs(dx)>1e-12 || abs(dy)>1e-12 else { return }
        move(dx:dx,dy:dy)
    }
    func smooth(_ enabled: Bool) {
        var value=paths
        for p in value.indices { for n in value[p].nodes.indices where selection.contains(value[p].nodes[n].id) { value[p].setSmooth(n,enabled) } }
        _=apply(value)
    }
    func lines() {
        var value=paths
        for p in value.indices { for n in 0..<value[p].segmentCount {
            let next=(n+1)%value[p].nodes.count
            if selection.contains(value[p].nodes[n].id) && selection.contains(value[p].nodes[next].id) {
                value[p].nodes[n].outgoing=nil;value[p].nodes[next].incoming=nil
                value[p].nodes[n].smooth=false;value[p].nodes[next].smooth=false
            }
        } }
        _=apply(value)
    }

    private func hasSelectedSegment(where predicate: (FontLabVectorPath, Int) -> Bool) -> Bool {
        paths.contains { path in
            (0..<path.segmentCount).contains { index in
                selection.contains(path.nodes[index].id) && selection.contains(path.nodes[(index + 1) % path.nodes.count].id) && predicate(path, index)
            }
        }
    }
    var canStraightenSegments: Bool { hasSelectedSegment { $0.isCurve($1) } }
    var canCurveSegments: Bool { hasSelectedSegment { !$0.isCurve($1) } }
    var canInsertMidpoints: Bool { hasSelectedSegment { _, _ in true } }
    var canCloseContours: Bool { paths.contains { !$0.closed && $0.nodes.count >= 3 && $0.nodes.contains { selection.contains($0.id) } } }
    var canOpenContours: Bool { paths.contains { $0.closed && $0.nodes.contains { selection.contains($0.id) } } }
    func curves() {
        var value=paths
        for p in value.indices { for n in 0..<value[p].segmentCount {
            let next=(n+1)%value[p].nodes.count
            if selection.contains(value[p].nodes[n].id) && selection.contains(value[p].nodes[next].id) && !value[p].isCurve(n) {
                let a=value[p].nodes[n].point,b=value[p].nodes[next].point
                value[p].nodes[n].outgoing=FontLabVectorMath.mix(a,b,1/3);value[p].nodes[next].incoming=FontLabVectorMath.mix(a,b,2/3)
            }
        } }
        _=apply(value)
    }

    private var selectedEndpointIDs: [UUID] {
        guard selection.count == 2 else { return [] }
        let chosen = paths.flatMap { path in path.nodes.enumerated().compactMap { index, node -> UUID? in
            guard selection.contains(node.id), !path.closed, index == 0 || index == path.nodes.count - 1 else { return nil }
            return node.id
        } }
        return chosen.count == 2 ? chosen : []
    }
    var canJoinEndpoints: Bool {
        let ends = selectedEndpointIDs
        return ends.count == 2 && FontLabPathConstruction.joining(paths, from: ends[0], to: ends[1]) != nil
    }
    func joinEndpoints() {
        let ends = selectedEndpointIDs
        guard ends.count == 2, let value = FontLabPathConstruction.joining(paths, from: ends[0], to: ends[1]) else {
            message = "Select two open endpoints to connect. A closed shape needs at least three points."; return
        }
        if apply(value) { activePath = nil; message = "Endpoints joined. Existing curves are preserved; Undo restores the separate paths." }
    }

    var canSplitNode: Bool {
        guard selection.count == 1 else { return false }
        return paths.contains { path in path.nodes.enumerated().contains { index, node in
            selection.contains(node.id) && (path.closed || (index > 0 && index < path.nodes.count - 1))
        } }
    }

    func splitAtNode() {
        guard canSplitNode else { message = "Select one closed-contour node or an interior node of an open contour."; return }
        var value = paths
        guard let p = value.firstIndex(where: { $0.nodes.contains { selection.contains($0.id) } }),
              let n = value[p].nodes.firstIndex(where: { selection.contains($0.id) }) else { return }
        var duplicate = value[p].nodes[n]
        duplicate.id = UUID()
        let originalID = value[p].nodes[n].id
        if value[p].closed {
            value[p].nodes = Array(value[p].nodes[n...]) + Array(value[p].nodes[..<n]) + [duplicate]
            value[p].closed = false
            value[p].nodes[0].incoming = nil
            value[p].nodes[0].smooth = false
            value[p].nodes[value[p].nodes.count - 1].outgoing = nil
            value[p].nodes[value[p].nodes.count - 1].smooth = false
        } else {
            duplicate.incoming = nil; duplicate.smooth = false
            let second = FontLabVectorPath(nodes: [duplicate] + Array(value[p].nodes[(n + 1)...]), closed: false)
            value[p].nodes = Array(value[p].nodes[...n])
            value[p].nodes[n].outgoing = nil; value[p].nodes[n].smooth = false
            value.insert(second, at: p + 1)
        }
        if apply(value) { selection = [originalID, duplicate.id]; activePath = nil; message = "Split at the selected node without changing the curves. Move an endpoint to open the cut." }
    }

    func insertMidpoints() {
        var value = paths, inserted = Set<UUID>()
        for p in value.indices {
            for n in (0..<value[p].segmentCount).reversed() {
                let next = (n + 1) % value[p].nodes.count
                guard selection.contains(value[p].nodes[n].id), selection.contains(value[p].nodes[next].id) else { continue }
                value[p].insertNode(segment: n, t: 0.5)
                inserted.insert(value[p].nodes[n + 1].id)
            }
        }
        guard !inserted.isEmpty else { message = "Select both ends of a segment to insert a midpoint."; return }
        if apply(value) { objectSelection = false; selection = inserted; message = "Inserted \(inserted.count) \(inserted.count == 1 ? "midpoint" : "midpoints"); the original curve shape is unchanged." }
    }

    /// Nested contours (including counters) move as one object. Node tools
    /// retain their separate semantics when the user switches to Nodes.
    private var selectedObjects: [[FontLabVectorPath]] {
        let chosen = paths
        let geometry = chosen.map { $0.cgPath }
        let boxes = geometry.map(\.boundingBoxOfPath)
        var groups: [Int: [FontLabVectorPath]] = [:]
        for i in chosen.indices {
            let parents = chosen.indices.filter { j in
                guard j != i, chosen[j].closed, chosen[i].closed,
                      boxes[j].width * boxes[j].height > boxes[i].width * boxes[i].height,
                      boxes[j].contains(boxes[i]), let first = chosen[i].nodes.first else { return false }
                return geometry[j].contains(CGPoint(x:first.point.x*1000,y:first.point.y*1000))
            }
            let root = parents.max { boxes[$0].width * boxes[$0].height < boxes[$1].width * boxes[$1].height } ?? i
            groups[root, default: []].append(chosen[i])
        }
        return groups.keys.sorted().map { groups[$0]! }.filter { $0.contains { path in path.nodes.contains { selection.contains($0.id) } } }
    }
    var canAlign: Bool { objectSelection ? selectedObjects.count >= 2 : selection.count >= 2 }
    var canDistribute: Bool { objectSelection ? selectedObjects.count >= 3 : selection.count >= 3 }
    private func arrangeObjects(horizontal: Bool, distribute: Bool) {
        let objects = selectedObjects.map { group -> (paths: [FontLabVectorPath], box: CGRect) in
            (group, group.reduce(CGRect.null) { $0.union($1.cgPath.boundingBoxOfPath) })
        }.sorted { a,b in horizontal ? a.box.midX < b.box.midX : a.box.midY < b.box.midY }
        guard objects.count >= (distribute ? 3 : 2) else {
            message = "Select at least \(distribute ? "three" : "two") objects. Counters move with their outer contour."
            return
        }
        let box = objects.reduce(CGRect.null) { $0.union($1.box) }
        let start = horizontal ? objects.first!.box.midX : objects.first!.box.midY
        let end = horizontal ? objects.last!.box.midX : objects.last!.box.midY
        var shifts: [UUID: (Double, Double)] = [:]
        for (index, object) in objects.enumerated() {
            let target = distribute ? start + (end-start)*Double(index)/Double(objects.count-1) : (horizontal ? box.midX : box.midY)
            let dx = horizontal ? (target-object.box.midX)/1000 : 0
            let dy = horizontal ? 0 : (target-object.box.midY)/1000
            for path in object.paths { for node in path.nodes { shifts[node.id] = (dx,dy) } }
        }
        var value = paths
        for p in value.indices { for n in value[p].nodes.indices {
            guard let (dx,dy) = shifts[value[p].nodes[n].id] else { continue }
            func shifted(_ point: FontLabPoint) -> FontLabPoint { .init(x:point.x+dx,y:point.y+dy) }
            value[p].nodes[n].point = shifted(value[p].nodes[n].point)
            value[p].nodes[n].incoming = value[p].nodes[n].incoming.map(shifted)
            value[p].nodes[n].outgoing = value[p].nodes[n].outgoing.map(shifted)
        } }
        if apply(value) { message = "Objects \(distribute ? "distributed" : "aligned"); curves and counters preserved." }
    }
    func distribute(horizontal: Bool) {
        if objectSelection { arrangeObjects(horizontal: horizontal, distribute: true); return }
        let nodes = selectedNodes.sorted { a, b in
            let av = horizontal ? a.point.x : a.point.y, bv = horizontal ? b.point.x : b.point.y
            return av == bv ? a.id.uuidString < b.id.uuidString : av < bv
        }
        guard nodes.count >= 3, let first = nodes.first, let last = nodes.last else { return }
        let start = horizontal ? first.point.x : first.point.y, end = horizontal ? last.point.x : last.point.y
        let positions = Dictionary(uniqueKeysWithValues: nodes.enumerated().map { ($0.element.id, start + (end - start) * Double($0.offset) / Double(nodes.count - 1)) })
        modifySelected { node, _, _ in
            guard let target = positions[node.id] else { return }
            let dx = horizontal ? target - node.point.x : 0, dy = horizontal ? 0 : target - node.point.y
            node.point.x += dx; node.point.y += dy
            if node.incoming != nil { node.incoming!.x += dx; node.incoming!.y += dy }
            if node.outgoing != nil { node.outgoing!.x += dx; node.outgoing!.y += dy }
        }
    }
    func pathCommand(_ command: String) {
        var value=paths
        var regrouping: [Set<UUID>] = []
        let sourceGroups = FontLabVectorMath.pathGroups(in:glyph).map { Set($0) }
        for p in value.indices where value[p].nodes.contains(where:{selection.contains($0.id)}) {
            if command == "reverse" { value[p].reverse() }
            if command == "counter",value[p].closed,let first=value[p].nodes.first {
                func area(_ path:FontLabVectorPath)->Double {
                    let points=path.flattened();guard points.count>=3 else {return 0}
                    return points.indices.reduce(0) { sum,i in let a=points[i],b=points[(i+1)%points.count];return sum+a.x*b.y-b.x*a.y }
                }
                let child=value[p].cgPath, samples=value[p].flattened()
                let parents=value.indices.filter { index in
                    guard index != p, value[index].closed else { return false }
                    let outline=value[index].cgPath
                    return outline.boundingBoxOfPath.contains(child.boundingBoxOfPath) &&
                        outline.contains(CGPoint(x:first.point.x*1000,y:first.point.y*1000)) &&
                        samples.allSatisfy { outline.contains(CGPoint(x:$0.x*1000,y:$0.y*1000)) }
                }
                if let parent=parents.min(by:{abs(area(value[$0]))<abs(area(value[$1]))}) {
                    if area(value[parent])*area(value[p])>0 {value[p].reverse()}
                    var joined = Set([value[parent].id,value[p].id])
                    for group in sourceGroups where !group.isDisjoint(with: joined) { joined.formUnion(group) }
                    for group in regrouping where !group.isDisjoint(with: joined) { joined.formUnion(group) }
                    regrouping.removeAll { !$0.isDisjoint(with: joined) };regrouping.append(joined)
                } else {message="A counter needs a closed contour inside another contour."}
            }
            if command == "close", value[p].nodes.count >= 3 { value[p].closed=true }
            if command == "open" { value[p].closed=false }
        }
        if apply(value,pathGroups:regrouping.map { Array($0) }) { activePath=nil }
    }
    func deleteSelection() {
        var value=paths
        for p in value.indices {
            let removed=Set(value[p].nodes.filter { selection.contains($0.id) }.map(\.id))
            guard !removed.isEmpty else { continue }
            // Join surviving anchors with straight segments across removed nodes;
            // do not leave unrelated old handles curling into the deleted area.
            let original=value[p].nodes
            value[p].nodes=original.enumerated().compactMap { i,node in
                guard !removed.contains(node.id) else { return nil }
                var node=node
                if removed.contains(original[(i+original.count-1)%original.count].id) { node.incoming=nil;node.smooth=false }
                if removed.contains(original[(i+1)%original.count].id) { node.outgoing=nil;node.smooth=false }
                return node
            }
            if value[p].nodes.count < 3 { value[p].closed=false }
        }
        value.removeAll {$0.nodes.isEmpty}
        _=apply(value);selection=[];activePath=nil
    }
    func duplicate() {
        let chosen=paths.filter { $0.nodes.contains { selection.contains($0.id) } }
        var copies=chosen.map { path -> FontLabVectorPath in
            var p=path;p.id=UUID();for i in p.nodes.indices {p.nodes[i].id=UUID()};return p
        }
        for p in copies.indices { for n in copies[p].nodes.indices {
            copies[p].nodes[n].point.x += 0.025
            if copies[p].nodes[n].incoming != nil { copies[p].nodes[n].incoming!.x += 0.025 }
            if copies[p].nodes[n].outgoing != nil { copies[p].nodes[n].outgoing!.x += 0.025 }
        } }
        let copyIDs = Dictionary(uniqueKeysWithValues: zip(chosen,copies).map { ($0.0.id,$0.1.id) })
        let groups = FontLabVectorMath.pathGroups(in:glyph).map { $0.compactMap { copyIDs[$0] } }.filter { !$0.isEmpty }
        if apply(paths+copies,pathGroups:groups) { selection=Set(copies.flatMap(\.nodes).map(\.id)); activePath=nil }
    }
    func transform(scaleX:Double=1,scaleY:Double=1,angle:Double=0) {
        guard scaleX.isFinite, scaleY.isFinite, angle.isFinite, scaleX != 0, scaleY != 0 else {
            message="Use a finite rotation and a nonzero scale."; return
        }
        guard !selection.isEmpty else { return }
        if message != Self.defaultMessage { message=Self.defaultMessage }
        guard scaleX != 1 || scaleY != 1 || angle != 0 else { return }
        let b=selectedBounds,w=glyph.resolvedDesignWidth
        let c=cos(angle),s=sin(angle)
        func convert(_ p:FontLabPoint)->FontLabPoint {
            let x=(p.x-b.midX)*w*scaleX,y=(p.y-b.midY)*scaleY
            return FontLabPoint(x:b.midX+(x*c-y*s)/w,y:b.midY+x*s+y*c)
        }
        modifySelected {node,_,_ in node.point=convert(node.point);node.incoming=node.incoming.map(convert);node.outgoing=node.outgoing.map(convert)}
    }
    func align(horizontal:Bool) {
        if objectSelection { arrangeObjects(horizontal: !horizontal, distribute: false); return }
        let b=selectedBounds
        modifySelected {node,_,_ in
            let dx=horizontal ? 0 : b.midX-node.point.x,dy=horizontal ? b.midY-node.point.y : 0
            node.point.x += dx;node.point.y += dy
            if node.incoming != nil {node.incoming!.x += dx;node.incoming!.y += dy}
            if node.outgoing != nil {node.outgoing!.x += dx;node.outgoing!.y += dy}
        }
    }
    func addExtrema() {
        var value=paths
        for p in value.indices where selection.isEmpty || value[p].nodes.contains(where:{selection.contains($0.id)}) {
            for i in (0..<value[p].segmentCount).reversed() where value[p].isCurve(i) {
                let points=value[p].controls(i)
                func roots(_ v:[Double])->[Double] {
                    let a = -v[0]+3*v[1]-3*v[2]+v[3],b=2*(v[0]-2*v[1]+v[2]),c=v[1]-v[0]
                    if abs(a)<1e-10 {return abs(b)<1e-10 ? [] : [-c/b]}
                    let d=b*b-4*a*c;return d<0 ? [] : [(-b+sqrt(d))/(2*a),(-b-sqrt(d))/(2*a)]
                }
                let ts=(roots(points.map(\.x))+roots(points.map(\.y))).filter {$0>0.001 && $0<0.999}.sorted()
                var last=0.0,offset=0
                for t in ts where t-last>0.001 { value[p].insertNode(segment:i+offset,t:(t-last)/(1-last));last=t;offset+=1 }
            }
        }
        _=apply(value)
    }
    func boolean(_ operation: String) {
        let chosen=paths.filter { selection.isEmpty || $0.nodes.contains { selection.contains($0.id) } }
        guard !chosen.isEmpty, chosen.allSatisfy(\.closed) else {message="Close the selected contours before combining shapes.";return}
        let result: CGPath
        if operation == "overlap" {
            let groups = FontLabVectorMath.pathGroups(in:glyph)
            var combined: CGPath?
            for group in groups {
                let compound=CGMutablePath()
                chosen.filter { group.contains($0.id) }.forEach {compound.addPath($0.cgPath)}
                guard !compound.isEmpty else { continue }
                let normalized=compound.normalized(using:.winding)
                combined = combined.map { $0.union(normalized,using:.winding) } ?? normalized
            }
            result=combined ?? CGMutablePath()
        } else {
            guard chosen.count>=2 else {message="Select at least two closed contours.";return}
            var combined=chosen[0].cgPath
            for path in chosen.dropFirst() {
                combined = operation == "subtract" ? combined.subtracting(path.cgPath,using:.winding) : combined.intersection(path.cgPath,using:.winding)
            }
            result=combined
        }
        let replacement=FontLabVectorPath.from(result),ids=Set(chosen.map(\.id))
        // Retain unselected counters alongside the replacement for their
        // original compound, rather than leaving a detached counter as ink.
        let siblings=FontLabVectorMath.pathGroups(in:glyph).filter { $0.contains { ids.contains($0) } }.flatMap { $0 }.filter { !ids.contains($0) }
        if apply(paths.filter {!ids.contains($0.id)}+replacement,pathGroups:[replacement.map(\.id)+siblings]) {selection=Set(replacement.flatMap(\.nodes).map(\.id));message="Contours combined. Undo restores the original shapes."}
    }
    func copyPaths() {
        let selected=paths.filter { $0.nodes.contains { selection.contains($0.id) } }
        let selectedIDs = Set(selected.map(\.id))
        let groups = FontLabVectorMath.pathGroups(in:glyph).map { $0.filter { selectedIDs.contains($0) } }.filter { !$0.isEmpty }
        let clipboard = FontLabVectorClipboard(designWidth: glyph.resolvedDesignWidth, baseline: metrics.baseline, paths: selected, groups:groups)
        guard clipboard.isValid, let data=try? JSONEncoder().encode(clipboard) else {return}
        NSPasteboard.general.clearContents();NSPasteboard.general.setData(data,forType:.init("local.fontshelf.vector-paths"))
        message="Copied \(selected.count) \(selected.count == 1 ? "contour" : "contours"). Paste into any glyph."
    }
    func pastePaths() {
        guard let data=NSPasteboard.general.data(forType:.init("local.fontshelf.vector-paths")) else {message="Copy vector contours from a Letterform Editor glyph first.";return}
        pastePaths(data: data)
    }
    func pastePaths(data: Data) {
        guard data.count < 8_000_000 else { message="The copied artwork exceeds the clipboard size limit.";return }
        var added: [FontLabVectorPath], groups: [[UUID]] = []
        if let clipboard = try? JSONDecoder().decode(FontLabVectorClipboard.self, from: data) {
            guard clipboard.isValid else { message="The copied contours are invalid or use an unsupported format.";return }
            guard let mapped = clipboard.mapped(toWidth: glyph.resolvedDesignWidth, baseline: metrics.baseline) else {
                message="Copied contours do not fit this glyph’s design box. Scale or reposition the source before copying; its proportions were preserved."
                return
            }
            added = mapped
            groups = clipboard.groups ?? []
        } else if let legacy = try? JSONDecoder().decode([FontLabVectorPath].self, from: data), !legacy.isEmpty, legacy.allSatisfy(\.isValid) {
            // Older versions did not record their source coordinate frame.
            added = legacy
        } else { message="Copy vector contours from a Letterform Editor glyph first.";return }
        for p in added.indices {
            let originalID = added[p].id;added[p].id=UUID()
            for g in groups.indices { groups[g] = groups[g].map { $0 == originalID ? added[p].id : $0 } }
            for n in added[p].nodes.indices {added[p].nodes[n].id=UUID()}
        }
        if apply(paths+added,pathGroups:groups) {selection=Set(added.flatMap(\.nodes).map(\.id)); activePath=nil; message="Pasted \(added.count) \(added.count == 1 ? "contour" : "contours"). Undo restores the previous outline."}
    }
}

struct FontLabVectorEditorView: View {
    let glyph: FontLabGlyph
    let metrics: FontLabMetrics
    let componentStrokes: [FontLabStroke]
    let compact: Bool
    let onChange: (FontLabGlyph)->Void
    let onUndo: ()->Void
    let onRedo: ()->Void
    let onPreviewInkChange: (String)->Void
    @StateObject private var editor: FontLabVectorEditor
    @State private var x = ""
    @State private var y = ""
    @State private var scale = "100"
    @State private var angle = "0"
    @State private var showSelectionInspector = false
    @State private var showCanvasAppearance = false
    @State private var showContours = false
    @State private var showStrokeOutline = false
    @State private var outlineWidth = "40"
    init(glyph:FontLabGlyph,metrics:FontLabMetrics,retainedEditor:FontLabVectorEditor?=nil,componentStrokes:[FontLabStroke]=[],previewInkHex:String?=nil,compact:Bool=false,onChange:@escaping(FontLabGlyph)->Void,onUndo:@escaping()->Void,onRedo:@escaping()->Void,onPreviewInkChange:@escaping(String)->Void={_ in}) {
        self.glyph=glyph;self.metrics=metrics;self.componentStrokes=componentStrokes;self.compact=compact;self.onChange=onChange;self.onUndo=onUndo;self.onRedo=onRedo;self.onPreviewInkChange=onPreviewInkChange
        let value=retainedEditor ?? FontLabVectorEditor(glyph:glyph,metrics:metrics)
        if let previewInkHex { value.inkColor=Color(nsColor:NSColor(hex:previewInkHex)) }
        _editor=StateObject(wrappedValue:value)
    }
    var body: some View {
        VStack(alignment:.leading,spacing:8) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    vectorToolButtons
                    Divider().frame(height: 20)
                    selectionPicker
                    Spacer(minLength: 0)
                    pathsMenu
                    selectionInspectorButton
                }
                VStack(alignment: .leading, spacing: 6) {
                    vectorToolButtons
                    HStack(spacing: 8) { selectionPicker; Spacer(minLength: 0); pathsMenu; selectionInspectorButton }
                }
            }.controlSize(.small)
            constructionControls
                .font(.caption).controlSize(.small)
            FontLabVectorCanvas(editor:editor,onChange:onChange,onUndo:onUndo,onRedo:onRedo)
                .frame(minWidth:340,maxWidth:.infinity,minHeight:340,maxHeight:.infinity)
                .background(Color(nsColor:.textBackgroundColor),in:RoundedRectangle(cornerRadius:12))
                .clipShape(RoundedRectangle(cornerRadius:12))
                .overlay(RoundedRectangle(cornerRadius:12).strokeBorder(Color.primary.opacity(0.15)))
                .overlay(alignment: .topTrailing) {
                    if editor.openCount > 0 {
                        Button { editor.selectContours(closed: false) } label: {
                            Label("\(editor.openCount) open \(editor.openCount == 1 ? "path" : "paths")", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                        }
                        .font(.caption).controlSize(.small).foregroundStyle(.orange)
                        .accessibilityLabel("Select \(editor.openCount) open \(editor.openCount == 1 ? "path" : "paths")")
                        .help("Open paths do not form solid letterforms. Select them, then Close path or Outline stroke.")
                        .padding(10)
                    }
                }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { canvasDisplayControls; Spacer(minLength: 0); vectorZoomControls }
                VStack(alignment: .leading, spacing: 8) {
                    canvasDisplayControls
                    HStack { Spacer(minLength: 0); vectorZoomControls }
                }
            }.font(.caption).controlSize(.small)
            .popover(isPresented: $showCanvasAppearance) { canvasAppearance.padding(16).frame(width: 310) }
            Text(editor.message.isEmpty ? editor.interactionHint : editor.message)
                .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                .help("Objects: edit whole shapes. Nodes: edit points and handles. Paths contains contour operations. Selection contains coordinates and transforms.")
        }
        .onChange(of:glyph) { editor.receive($0);updateCoordinates() }
        .onAppear { editor.receive(glyph); editor.metrics=metrics; editor.componentStrokes=componentStrokes; updateCoordinates() }
        .onChange(of:componentStrokes) {editor.componentStrokes=$0}
        .onChange(of:metrics) {editor.metrics=$0;updateCoordinates()}
        .onChange(of:editor.selection) {_ in updateCoordinates()}
        .onChange(of:editor.glyph) {_ in updateCoordinates()}
        .onChange(of:editor.inkColor) { color in onPreviewInkChange(NSColor(color).rgbHex) }
    }
    private var constructionControls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { continuationButton; joinButton; closeButton; outlineStrokeButton; Spacer(minLength: 0) }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) { continuationButton; joinButton; Spacer(minLength: 0) }
                HStack(spacing: 8) { closeButton; outlineStrokeButton; Spacer(minLength: 0) }
            }
        }
        .popover(isPresented: $showStrokeOutline) { strokeOutlineInspector.padding(16).frame(width: 320) }
    }
    @ViewBuilder private var continuationButton: some View {
        if editor.activePath != nil {
            Button("Finish path") { editor.finishPath() }.help("Finish this open path without changing its shape (Return)")
        } else {
            Button("Continue path") { editor.continueSelectedEndpoint() }
                .disabled(!editor.canContinueEndpoint).help("Select one open endpoint, then continue drawing from it with Pen")
        }
    }
    private var joinButton: some View {
        Button("Join") { editor.joinEndpoints() }.disabled(!editor.canJoinEndpoints)
            .accessibilityLabel("Join endpoints").help("Shift-select two open endpoints, then join them (⌘J)")
    }
    private var closeButton: some View {
        Button("Close path") {
            if editor.activePath != nil { editor.closeActivePath() } else { editor.closeTouchedPaths() }
        }
        .disabled(editor.activePath != nil ? !editor.canCloseActivePath : !editor.canCloseTouchedPaths)
        .help("Connect the first and last points of the active path or selected contours")
    }
    private var outlineStrokeButton: some View {
        Button("Outline stroke…") { showStrokeOutline = true }
            .disabled(!editor.canOutlineSelectedPaths)
            .help("Give selected open paths a width and turn them into filled, editable outlines")
    }
    private var strokeOutlineInspector: some View {
        let width = Double(outlineWidth.trimmingCharacters(in: .whitespacesAndNewlines))
        let preview = width.flatMap { editor.strokeOutlinePreview(widthInUnits: $0) }
        return VStack(alignment: .leading, spacing: 12) {
            HStack { Text("Outline stroke").font(.headline); Spacer(); Button("Cancel") { showStrokeOutline = false } }
            Text("Turn the selected open paths into filled outlines with round ends and joins. Every point remains editable; Undo restores the original paths.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Text("Width")
                TextField("40", text: $outlineWidth).textFieldStyle(.roundedBorder).frame(width: 64)
                    .accessibilityLabel("Outline stroke width in font units")
                Text("font units").foregroundStyle(.secondary)
            }.font(.caption)
            Canvas { context, size in
                let scale = min(size.width / (editor.glyph.resolvedDesignWidth * 1000), size.height / 1000)
                var transform = CGAffineTransform(a: scale * editor.glyph.resolvedDesignWidth, b: 0, c: 0, d: -scale,
                    tx: (size.width - scale * editor.glyph.resolvedDesignWidth * 1000) / 2, ty: (size.height + scale * 1000) / 2)
                for group in preview ?? [] {
                    let compound = CGMutablePath()
                    for path in group { if let mapped = path.cgPath.copy(using: &transform) { compound.addPath(mapped) } }
                    context.fill(Path(compound), with: .color(.primary), style: FillStyle(eoFill: false))
                }
            }.frame(height: 150).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
                .accessibilityLabel("Filled stroke preview")
            if preview == nil {
                Text("Use 2–200 units and keep the full stroke inside the design box. Move a path away from the edge if needed.")
                    .font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("Create outline") {
                    if let width, editor.outlineSelectedPaths(widthInUnits: width) { showStrokeOutline = false }
                }.disabled(preview == nil).buttonStyle(.borderedProminent)
            }
        }
    }
    private var canvasDisplayControls: some View {
        HStack(spacing: 10) {
            Toggle(isOn: $editor.fill) { Label("Fill", systemImage: "circle.lefthalf.filled") }
                .toggleStyle(.button).help("Show or hide the filled letter (F). This changes the preview only.")
                .accessibilityLabel("Show fill")
            Button("Contours (\(editor.paths.count))") { showContours = true }
                .popover(isPresented: $showContours) { contourInspector.padding(16).frame(width: 360) }
            Menu("Canvas") {
                Toggle("Show grid", isOn: $editor.grid)
                Toggle("Snap to grid", isOn: $editor.snap)
                Divider()
                Button("Preview appearance…") { showCanvasAppearance = true }
            }.menuStyle(.borderlessButton).fixedSize()
        }.fixedSize()
    }
    private var contourInspector: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("Contours").font(.headline); Spacer(); Button("Done") { showContours = false } }
            Text("Closed contours form the letter and its counters. Open paths are unfinished lines.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Select filled outlines") { editor.selectContours(closed: true) }
                    .disabled(editor.paths.allSatisfy { !$0.closed })
                Button("Select open paths") { editor.selectContours(closed: false) }.disabled(editor.openCount == 0)
            }.controlSize(.small)
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(Array(editor.paths.enumerated()), id: \.element.id) { index, path in
                        Button { editor.selectContour(path.id) } label: {
                            HStack {
                                Image(systemName: path.closed ? "seal" : "point.topleft.down.to.point.bottomright.curvepath")
                                    .foregroundStyle(path.closed ? Color.accentColor : .orange)
                                Text("Contour \(index + 1) · \(path.closed ? "Closed" : "Open")")
                                Spacer()
                                Text("\(path.nodes.count) nodes").foregroundStyle(.secondary)
                                if !path.nodes.isEmpty && path.nodes.allSatisfy({ editor.selection.contains($0.id) }) {
                                    Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                                }
                            }.padding(6).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
            }.frame(maxHeight: 200)
            HStack {
                Button("Close contours") { editor.closeSelectedContours() }.disabled(!editor.canCloseSelectedContours)
                Spacer()
                Button("Delete contours", role: .destructive) { editor.deleteSelectedContours() }.disabled(editor.selectedContourIDs.isEmpty)
            }.controlSize(.small)
            Text("Selection is highlighted on the canvas. Deleting can be undone with ⌘Z.").font(.caption).foregroundStyle(.secondary)
        }
    }
    private var selectionInspectorButton: some View {
        Button("Selection") { showSelectionInspector = true }
            .buttonStyle(.borderless).help("Coordinates, alignment, scale and rotation")
            .popover(isPresented: $showSelectionInspector) { selectionInspector.padding(16).frame(width: 400) }
    }
    private var selectionInspector: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("Selection").font(.headline); Spacer(); Button("Select all") { editor.selectAll() }; Button("Done") { showSelectionInspector = false } }
            HStack(spacing:6) {
                Text("\(editor.selection.count) \(editor.selection.count == 1 ? "node" : "nodes")").foregroundStyle(.secondary).frame(width:65,alignment:.leading)
                Text("X");TextField("X",text:$x).frame(width:55).disabled(editor.selection.isEmpty).accessibilityLabel("Selection X in font units").onSubmit {submitCoordinate(x, horizontal:true)}
                Text("Y");TextField("Y",text:$y).frame(width:55).disabled(editor.selection.isEmpty).accessibilityLabel("Selection Y above baseline in font units").onSubmit {submitCoordinate(y, horizontal:false)}
                Spacer(minLength:0)
                Menu("Transform") {
                    Button(editor.objectSelection ? "Align objects horizontally" : "Align nodes horizontally") {editor.align(horizontal:true)}.disabled(!editor.canAlign)
                    Button(editor.objectSelection ? "Align objects vertically" : "Align nodes vertically") {editor.align(horizontal:false)}.disabled(!editor.canAlign)
                    Button(editor.objectSelection ? "Distribute objects horizontally" : "Distribute nodes horizontally") {editor.distribute(horizontal:true)}.disabled(!editor.canDistribute)
                    Button(editor.objectSelection ? "Distribute objects vertically" : "Distribute nodes vertically") {editor.distribute(horizontal:false)}.disabled(!editor.canDistribute)
                    Button("Flip horizontally") {editor.transform(scaleX:-1)}
                    Button("Flip vertically") {editor.transform(scaleY:-1)}
                }.disabled(editor.selection.isEmpty).fixedSize()
            }.textFieldStyle(.roundedBorder).font(.caption)
            HStack(spacing:6) {
                Text("Scale %");TextField("100",text:$scale).frame(width:50).disabled(editor.selection.isEmpty).onSubmit {submitScale()}
                Button("Scale") {submitScale()}.disabled(editor.selection.isEmpty)
                Spacer(minLength: 0)
            }.textFieldStyle(.roundedBorder).font(.caption)
            HStack(spacing: 6) {
                Text("Rotate °");TextField("0",text:$angle).frame(width:45).disabled(editor.selection.isEmpty).onSubmit {submitRotation()}
                Button("Rotate") {submitRotation()}.disabled(editor.selection.isEmpty)
                Spacer(minLength:0)
            }.textFieldStyle(.roundedBorder).font(.caption)
            Text(editor.message).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
        }
    }
    private func submitCoordinate(_ text: String, horizontal: Bool) {
        guard let value = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)), value.isFinite else {
            editor.message="Enter a finite coordinate in font units.";updateCoordinates();return
        }
        editor.setCoordinate(value, x:horizontal)
        // Rejected out-of-bounds edits leave the outline unchanged; show its
        // actual position instead of retaining a value that was never applied.
        updateCoordinates()
    }
    private func submitScale() {
        guard let value = Double(scale.trimmingCharacters(in: .whitespacesAndNewlines)), value.isFinite, value > 0, value <= 1000 else {
            editor.message="Enter a scale greater than 0 and at most 1,000 percent.";return
        }
        editor.transform(scaleX:value/100,scaleY:value/100)
    }
    private func submitRotation() {
        guard let value = Double(angle.trimmingCharacters(in: .whitespacesAndNewlines)), value.isFinite else {
            editor.message="Enter a finite rotation in degrees.";return
        }
        editor.transform(angle:value.truncatingRemainder(dividingBy:360) * .pi/180)
    }
    private var canvasAppearance: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("Preview appearance").font(.headline); Spacer(); Button("Done") { showCanvasAppearance = false } }
            HStack {
                ColorPicker("Preview ink", selection: $editor.inkColor, supportsOpacity: false).fixedSize()
                    .help("Canvas preview color only. Font exports remain monochrome; choose text color in Spaces or the app using the font.")
                if let stroke = editor.glyph.strokes.first(where: { !$0.points.isEmpty }) {
                    Text("Pen width")
                    TextField("Units", value: Binding(get: { stroke.width * 1000 }, set: { editor.setPenWidth($0) }), format: .number)
                        .textFieldStyle(.roundedBorder).frame(width: 55)
                    Text("units").foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }.font(.caption)
        }
    }
    private var vectorToolButtons: some View {
        HStack(spacing:6) {
            ForEach(FontLabVectorTool.allCases) { tool in
                Button {editor.tool=tool;editor.activePath=nil;editor.message=""} label: {
                    HStack(spacing: 3) {
                        Image(systemName:tool.icon).frame(width:24,height:24)
                        if editor.tool == tool { Text(tool.rawValue).font(.caption).fixedSize() }
                    }
                }
                    .buttonStyle(.plain).padding(4).background(editor.tool == tool ? Color.accentColor.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 6)).foregroundStyle(editor.tool == tool ? Color.accentColor : Color.primary).help("\(tool.rawValue) (\(tool.shortcut))").accessibilityLabel(tool.rawValue)
            }
        }.padding(3).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
    }
    private var selectionPicker: some View {
        Picker("Selection", selection: Binding(get: { editor.objectSelection }, set: {
            editor.objectSelection = $0; editor.tool = .select; editor.activePath = nil; editor.message = ""
        })) { Text("Objects").tag(true); Text("Nodes").tag(false) }
            .pickerStyle(.segmented).labelsHidden().frame(width:140)
            .help("Nodes edits anchors, handles and curves (A). Objects moves whole shapes.")
    }
    private var pathsMenu: some View {
        Menu("Paths") {
                    Button("Select filled outlines") { editor.selectContours(closed: true) }.disabled(editor.paths.allSatisfy { !$0.closed })
                    Button("Select open paths") { editor.selectContours(closed: false) }.disabled(editor.openCount == 0)
                    Button("Manage contours…") { showContours = true }
                    Divider()
                    Button("Smooth nodes") {editor.smooth(true)}.disabled(editor.selection.isEmpty)
                    Button("Corner nodes") {editor.smooth(false)}.disabled(editor.selection.isEmpty)
                    Button("Make selected segments straight") {editor.lines()}.disabled(!editor.canStraightenSegments)
                    Button("Add curve handles") {editor.curves()}.disabled(!editor.canCurveSegments)
                    Button("Insert segment midpoints") {editor.insertMidpoints()}.disabled(!editor.canInsertMidpoints)
                    Button("Split at selected node") {editor.splitAtNode()}.disabled(!editor.canSplitNode)
                    Button("Join selected endpoints") {editor.joinEndpoints()}.disabled(!editor.canJoinEndpoints)
                    Button("Continue from selected endpoint") { editor.continueSelectedEndpoint() }.disabled(!editor.canContinueEndpoint)
                    Button("Outline selected strokes…") { showStrokeOutline = true }.disabled(!editor.canOutlineSelectedPaths)
                    Divider()
                    Button("Close contours") {editor.pathCommand("close")}.disabled(!editor.canCloseContours)
                    Button("Open contours") {editor.pathCommand("open")}.disabled(!editor.canOpenContours)
                    Button("Make counter") {editor.pathCommand("counter")}.disabled(editor.selection.isEmpty)
                    Button("Reverse contours") {editor.pathCommand("reverse")}.disabled(editor.selection.isEmpty)
                    Button("Remove overlaps") {editor.boolean("overlap")}.disabled(editor.paths.isEmpty)
                    Button("Subtract later contours") {editor.boolean("subtract")}.disabled(editor.selection.isEmpty)
                    Button("Intersect contours") {editor.boolean("intersect")}.disabled(editor.selection.isEmpty)
                    Button("Add extrema") {editor.addExtrema()}.disabled(editor.paths.isEmpty)
                    Divider()
                    Button("Duplicate contours") {editor.duplicate()}.disabled(editor.selection.isEmpty)
                    Button("Copy contours") {editor.copyPaths()}.disabled(editor.selection.isEmpty)
                    Button("Paste contours") {editor.pastePaths()}
                    Button("Delete nodes",role:.destructive) {editor.deleteSelection()}.disabled(editor.selection.isEmpty)
        }.menuStyle(.borderlessButton).fixedSize()
    }
    private var vectorZoomControls: some View {
        HStack(spacing:10) {
            Button("−") {editor.zoom=max(0.1,editor.zoom/1.25)}.help("Zoom out")
            Text("\(Int(editor.zoom*100))%").monospacedDigit().frame(width:42)
            Button("+") {editor.zoom=min(8,editor.zoom*1.25)}.help("Zoom in")
            Button("Fit") {editor.fit()}
            Button("Focus") {editor.requestFocusSelection()}
                .disabled(editor.selection.isEmpty)
                .help("Zoom and center the selected contour or nodes")
                .accessibilityLabel("Focus selection")
        }
    }
    private func updateCoordinates() {
        guard !editor.selection.isEmpty else {x="";y="";return}
        x=String(format:"%.1f",editor.selectedBounds.minX*editor.glyph.resolvedDesignWidth*1000)
        y=String(format:"%.1f",(editor.selectedBounds.minY-editor.metrics.baseline)*1000)
    }
}

private struct FontLabVectorCanvas: NSViewRepresentable {
    @ObservedObject var editor:FontLabVectorEditor
    let onChange:(FontLabGlyph)->Void
    let onUndo:()->Void
    let onRedo:()->Void
    func makeNSView(context:Context)->FontLabVectorNSView {FontLabVectorNSView(editor:editor)}
    func updateNSView(_ view:FontLabVectorNSView,context:Context) {
        editor.onCommit=onChange;editor.onUndo=onUndo;editor.onRedo=onRedo
        editor.onFocusSelectionRequested = { [weak view] in view?.focusSelection() }
        view.needsDisplay=true
    }
}
