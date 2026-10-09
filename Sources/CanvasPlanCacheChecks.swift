import AppKit

enum CanvasPlanCacheChecks {
    static func run() throws {
        func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
            if !condition() { throw NSError(domain: "Typefield.CanvasPlanCacheChecks", code: 1,
                                             userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        func equivalent(_ a: CanvasPlan, _ b: CanvasPlan) -> Bool {
            guard a.size == b.size, a.artboardSize == b.artboardSize, a.paper == b.paper, a.ink == b.ink,
                  a.contentScale == b.contentScale, a.isArrangement == b.isArrangement,
                  a.accessibilityText == b.accessibilityText, a.elements.count == b.elements.count,
                  a.sections.count == b.sections.count else { return false }
            for (a, b) in zip(a.sections, b.sections) {
                if a.id != b.id || a.title != b.title || a.rect != b.rect { return false }
            }
            for (a, b) in zip(a.elements, b.elements) {
                if a.rect != b.rect || a.color != b.color || a.strokeColor != b.strokeColor ||
                    a.radius != b.radius || a.strokeWidth != b.strokeWidth || a.imageOpacity != b.imageOpacity ||
                    a.artworkInFront != b.artworkInFront || a.sectionID != b.sectionID || a.style != b.style ||
                    a.role != b.role || a.textID != b.textID || a.textKind != b.textKind || a.objectID != b.objectID ||
                    a.flipX != b.flipX || a.flipY != b.flipY || a.effects != b.effects { return false }
                if (a.text == nil) != (b.text == nil) || (a.text != nil && !a.text!.isEqual(to: b.text!)) { return false }
                if (a.image == nil) != (b.image == nil) || a.image?.tiffRepresentation != b.image?.tiffRepresentation { return false }
            }
            return true
        }
        func budgets() throws {
            let stats = CanvasPlanCache.statistics
            try check(stats.plans <= CanvasPlanCache.maximumPlans && stats.dimensions <= CanvasPlanCache.maximumDimensions &&
                        stats.elements <= CanvasPlanCache.maximumElements && stats.dimensionSourceElements <= CanvasPlanCache.maximumElements &&
                        stats.textLength <= CanvasPlanCache.maximumTextLength && stats.imageBytes <= CanvasPlanCache.maximumImageBytes,
                      "Canvas plan and dimension caches exceeded their retained-resource budgets")
        }
        defer { CanvasPlanCache.removeAll() }
        let kinds: [CanvasKind] = [.website, .product, .editorial, .poster, .specimen, .custom]
        var directions = (0..<32).map { index -> TypeDirection in
            var direction = TypeDirection(name: "Cache fixture \(index)", fonts: ["Helvetica", "Georgia"])
            direction.canvas = kinds[index % kinds.count]
            direction.width = index.isMultiple(of: 2) ? 480 : 960
            if index.isMultiple(of: 5) { direction.boardPosition = CanvasBoardPosition(x: Double(index) * 83.25, y: 120.5) }
            direction.styles[TypeRole.body.rawValue]?.text = "Café العربية हिन्दी 日本語 👩🏽‍💻. Text across a canvas."
            return direction
        }
        var imported = TypeDirection(name: "Imported cache fixture")
        imported.canvas = .imported
        imported.importedLayout = ImportedLayout(width: 600, height: 400, layers: [
            ImportedLayer(id: "shape", name: "Shape", x: 20.25, y: 25.5, width: 180, height: 90, color: "334455"),
            ImportedLayer(id: "text", name: "Text", x: 45.5, y: 140, width: 220.25, height: 100, color: "222222",
                          style: TypeStyle(fontName: "Helvetica", size: 22, text: "Emoji 👩🏽‍💻 العربية हिन्दी"))
        ])
        imported.objectTransforms = ["text|text|0": CanvasObjectTransform(x: 6.25, y: 3.5)]
        directions[31] = imported
        let fresh = directions.map { CanvasPlan(direction: $0) }
        for count in [17, 32] {
            CanvasPlanCache.removeAll()
            var builds = 0
            for (index, direction) in directions.prefix(count).enumerated() {
                let cached = CanvasPlanCache.plan(for: direction) { source in builds += 1; return CanvasPlan(direction: source) }
                try check(equivalent(cached, fresh[index]), "Caching must preserve every rendered canvas element and section")
            }
            for _ in 0..<3 {
                for (index, direction) in directions.prefix(count).enumerated() {
                    let cached = CanvasPlanCache.plan(for: direction) { source in builds += 1; return CanvasPlan(direction: source) }
                    let dimensions = CanvasPlanCache.dimensions(for: direction) { source in builds += 1; return CanvasPlan(direction: source) }
                    try check(equivalent(cached, fresh[index]) && dimensions == CanvasPlanCache.Dimensions(fresh[index]),
                              "Warm geometry and rendering must match the original full plan")
                }
            }
            try check(builds == count, "An unchanged 17/32-canvas workspace must not rebuild its cached plans")
            try budgets()
        }
        var nextX = 24.0
        let positions = CanvasBoardLayout.positions(for: directions)
        for (index, direction) in directions.enumerated() {
            let position = direction.boardPosition ?? CanvasBoardPosition(x: nextX, y: 52)
            try check(positions[direction.id] == position, "Geometry caching changed automatic or explicit canvas placement")
            nextX = max(nextX, position.x + fresh[index].size.width + 32)
        }
        var changed = imported
        changed.importedLayout?.layers[1].style?.text = "A much longer replacement 👩🏽‍💻 العربية हिन्दी 日本語 paragraph that wraps on more lines."
        changed.width = 520
        changed.canvasScale = 1.2
        changed.hiddenSections = ["shape"]
        let edited = CanvasPlan(direction: changed)
        try check(CanvasPlanCache.dimensions(for: changed) == CanvasPlanCache.Dimensions(edited) &&
                    equivalent(CanvasPlanCache.plan(for: changed), edited),
                  "Editing text, scale, width or hidden objects under the same canvas ID must invalidate cached output")
        try check(equivalent(CanvasPlanCache.plan(for: imported), fresh[31]), "Undo to the original canvas must restore its exact plan")

        var composed = TypeDirection()
        composed.canvas = .custom; composed.blocks = [.body]
        composed.styles[TypeRole.body.rawValue]?.text = "é"
        var decomposed = composed
        decomposed.styles[TypeRole.body.rawValue]?.text = "e\u{301}"
        var overrideComposed = composed
        overrideComposed.textOverrides = ["Custom layout:block-0|Body|0": "é"]
        var overrideDecomposed = overrideComposed
        overrideDecomposed.textOverrides?["Custom layout:block-0|Body|0"] = "e\u{301}"
        var layerComposed = imported
        layerComposed.importedLayout?.layers[1].name = "é"
        layerComposed.importedLayout?.layers[1].style?.text = "é"
        var layerDecomposed = layerComposed
        layerDecomposed.importedLayout?.layers[1].name = "e\u{301}"
        layerDecomposed.importedLayout?.layers[1].style?.text = "e\u{301}"
        for (before, after) in [(composed, decomposed), (overrideComposed, overrideDecomposed), (layerComposed, layerDecomposed)] {
            let expected = CanvasPlan(direction: after)
            for geometryFirst in [false, true] {
                CanvasPlanCache.removeAll()
                _ = CanvasPlanCache.plan(for: before)
                var rebuilt = 0
                if geometryFirst {
                    _ = CanvasPlanCache.dimensions(for: after) { source in rebuilt += 1; return CanvasPlan(direction: source) }
                }
                let actual = CanvasPlanCache.plan(for: after) { source in rebuilt += 1; return CanvasPlan(direction: source) }
                try check(rebuilt == 1 && equivalent(actual, expected) &&
                            zip(actual.elements, expected.elements).allSatisfy { ($0.text?.string ?? "").utf8.elementsEqual(($1.text?.string ?? "").utf8) } &&
                            zip(actual.sections, expected.sections).allSatisfy { $0.title.utf8.elementsEqual($1.title.utf8) },
                          "Both caches must invalidate canonically equivalent but byte-distinct text and accessibility titles")
            }
        }

        // Hidden dimensions beyond full-plan capacity must not churn a visible plan.
        CanvasPlanCache.removeAll()
        var visibleBuilds = 0
        _ = CanvasPlanCache.plan(for: imported) { _ in visibleBuilds += 1; return fresh[31] }
        var geometryBuilds = 0
        let many = (0..<80).map { _ in TypeDirection() }
        let small = CanvasPlan(arrangement: [], width: 320)
        for _ in 0..<2 {
            for direction in many {
                _ = CanvasPlanCache.dimensions(for: direction) { _ in geometryBuilds += 1; return small }
            }
        }
        _ = CanvasPlanCache.plan(for: imported) { _ in visibleBuilds += 1; return fresh[31] }
        try check(visibleBuilds == 1 && geometryBuilds == many.count && CanvasPlanCache.statistics.plans == CanvasPlanCache.maximumPlans,
                  "Reading many hidden-canvas dimensions must retain the visible plan and reuse scalar geometry")
        for _ in 0...CanvasPlanCache.maximumDimensions { _ = CanvasPlanCache.dimensions(for: TypeDirection()) { _ in small } }
        try budgets()
        try check(CanvasPlanCache.statistics.dimensions == CanvasPlanCache.maximumDimensions,
                  "Dimension-only snapshots must obey their entry limit")

        CanvasPlanCache.removeAll()
        for _ in 0...CanvasPlanCache.maximumPlans { _ = CanvasPlanCache.plan(for: TypeDirection()) { _ in small } }
        try check(CanvasPlanCache.statistics.plans == CanvasPlanCache.maximumPlans, "Full plans must obey the entry limit")
        try budgets()
        CanvasPlanCache.removeAll()
        var dense = small
        dense.elements = Array(repeating: CanvasElement(rect: CGRect(x: 0, y: 0, width: 1, height: 1)), count: 1_000)
        for _ in 0..<20 { _ = CanvasPlanCache.plan(for: TypeDirection()) { _ in dense } }
        try check(CanvasPlanCache.statistics.elements == CanvasPlanCache.maximumElements && CanvasPlanCache.statistics.plans == 16,
                  "Many individually cacheable dense plans must obey the aggregate element budget")
        try budgets()
        CanvasPlanCache.removeAll()
        dense.elements.append(CanvasElement(rect: .zero))
        _ = CanvasPlanCache.plan(for: TypeDirection()) { _ in dense }
        try check(CanvasPlanCache.statistics.plans == 0, "A plan over the existing 1,000-element ceiling must not be retained")
        CanvasPlanCache.removeAll()
        var hiddenShapes = TypeDirection()
        hiddenShapes.importedLayout = ImportedLayout(width: 320, height: 320, layers: (0..<5_000).map { index in
            ImportedLayer(id: "hidden\(index)", name: "Shape", x: 0, y: 0, width: 1, height: 1, color: "000000")
        })
        for _ in 0..<4 {
            hiddenShapes.id = UUID()
            _ = CanvasPlanCache.plan(for: hiddenShapes) { _ in small }
        }
        try check(CanvasPlanCache.statistics.plans == 3, "Layers retained only in source snapshots must count toward the element budget")
        try budgets()
        CanvasPlanCache.removeAll()

        var long = small
        long.elements = [CanvasElement(rect: .zero, text: NSAttributedString(string: String(repeating: "a", count: 600_000)))]
        for _ in 0..<4 { _ = CanvasPlanCache.plan(for: TypeDirection()) { _ in long } }
        try budgets()
        try check(CanvasPlanCache.statistics.plans == 3, "Large text plans must obey the existing aggregate text budget")
        CanvasPlanCache.removeAll()
        long.elements[0].text = NSAttributedString(string: String(repeating: "a", count: 1_000_001))
        _ = CanvasPlanCache.plan(for: TypeDirection()) { _ in long }
        try check(CanvasPlanCache.statistics.plans == 0, "The per-plan text limit must still reject oversized plans")
        CanvasPlanCache.removeAll()
        var unknownImage = small
        unknownImage.elements = [CanvasElement(rect: .zero, image: NSImage(size: CGSize(width: 100, height: 100)))]
        _ = CanvasPlanCache.plan(for: TypeDirection()) { _ in unknownImage }
        try check(CanvasPlanCache.statistics.plans == 0, "Unknown image representation cost must remain uncacheable")

        // Shared Data keeps this fixture small while exercising conservative
        // per-layer accounting for artwork hidden from the rendered plan.
        CanvasPlanCache.removeAll()
        let bytes = Data(repeating: 0, count: 16 * 1024 * 1024)
        var hidden = TypeDirection()
        hidden.artworkLayers = (0..<9).map { index in
            ImportedLayer(id: "hidden\(index)", name: "Hidden", x: 0, y: 0, width: 1, height: 1,
                          color: "000000", artworkData: bytes)
        }
        hidden.hiddenSections = Set(hidden.artworkLayers!.map(\.id))
        _ = CanvasPlanCache.plan(for: hidden) { _ in small }
        _ = CanvasPlanCache.dimensions(for: hidden) { _ in small }
        try check(CanvasPlanCache.statistics.plans == 0 && CanvasPlanCache.statistics.dimensions == 0,
                  "Hidden compressed artwork must be charged to both source-retaining caches")
        try budgets()

        CanvasPlanCache.removeAll()
        _ = CanvasPlanCache.plan(for: imported) { _ in CanvasPlanCache.removeAll(); return fresh[31] }
        try check(CanvasPlanCache.statistics.plans == 0 && CanvasPlanCache.statistics.dimensions == 0,
                  "A catalog clear during plan construction must prevent stale plan and dimension reinsertion")
        _ = CanvasPlanCache.dimensions(for: imported) { _ in CanvasPlanCache.removeAll(); return fresh[31] }
        try check(CanvasPlanCache.statistics.dimensions == 0,
                  "A catalog clear during dimension construction must prevent stale reinsertion")
        var afterClearBuilds = 0
        _ = CanvasPlanCache.plan(for: imported) { _ in afterClearBuilds += 1; return fresh[31] }
        try check(afterClearBuilds == 1, "After a catalog clear, the next request must build a fresh plan")
        print("PASS: canvas geometry and plans retain exact layout across 17/32-canvas workspaces, source edits and undo; hidden dimensions, capacity, text/image/element budgets and catalog-clear races are bounded.")
    }
}
