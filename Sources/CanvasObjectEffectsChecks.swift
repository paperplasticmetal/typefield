import AppKit

enum CanvasObjectEffectsChecks {
    static func run() throws {
        func check(_ value: @autoclosure () -> Bool, _ message: String) throws {
            if !value() { throw NSError(domain: "Typefield.EffectsChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        let old = try JSONDecoder().decode(CanvasObjectEffects.self, from: Data("{}".utf8))
        try check(old == CanvasObjectEffects() && !old.isActive, "Old documents need neutral effect defaults")
        let effects = CanvasObjectEffects(blurRadius: 4, shadowEnabled: true, shadowColor: "D03020", shadowOpacity: 0.7, shadowRadius: 3, shadowX: 12, shadowY: 8)
        let decoded = try JSONDecoder().decode(CanvasObjectEffects.self, from: JSONEncoder().encode(effects))
        try check(decoded == effects, "Effects must survive JSON round trips")
        for invalid in [CanvasObjectEffects(blurRadius: -.infinity), CanvasObjectEffects(blurRadius: .nan), CanvasObjectEffects(shadowColor: "BAD"), CanvasObjectEffects(shadowOpacity: 2), CanvasObjectEffects(shadowY: 10_001)] {
            try check(!invalid.isValid, "Unsafe effects must fail validation")
        }
        var direction = TypeDirection(name: "Effects fixture")
        direction.canvas = .imported; direction.width = 320; direction.canvasWidth = 320; direction.canvasHeight = 240
        direction.importedLayout = ImportedLayout(width: 320, height: 240, layers: [
            ImportedLayer(id: "shape", name: "Shape", x: 30, y: 25, width: 80, height: 50, color: "000000"),
            ImportedLayer(id: "text", name: "Text", x: 140, y: 30, width: 130, height: 60, color: "000000", style: TypeStyle(fontName: "Helvetica", size: 30, text: "Hello"))
        ])
        let neutral = CanvasPlan(direction: direction)
        let ids = Set(neutral.elements.map(\.objectID))
        direction.objectEffects = Dictionary(uniqueKeysWithValues: ids.map { ($0, effects) })
        direction.objectGroups = [CanvasObjectGroup(members: ids)]
        try check(direction.isValid, "Effects must produce a valid document")
        let restored = try JSONDecoder().decode(TypeDirection.self, from: JSONEncoder().encode(direction))
        try check(restored == direction, "Document must retain effects alongside groups")
        let affected = CanvasPlan(direction: direction)
        try check(affected.elements.allSatisfy { $0.effects == effects }, "All text/shape effects must reach preview plan")
        guard let clip = SpacesObjects.clip(direction, ids: ids) else { throw NSError(domain: "Typefield.EffectsChecks", code: 2) }
        try check(clip.layers.allSatisfy { $0.effects == effects }, "Copy must retain text and shape effects")
        var destination = TypeDirection(name: "Destination"); destination.width = 960; destination.canvasScale = 2
        guard let (pasted, selected) = SpacesObjects.paste(clip, into: destination) else { throw NSError(domain: "Typefield.EffectsChecks", code: 3) }
        try check(CanvasPlan(direction: pasted).elements.filter { selected.contains($0.objectID) }.allSatisfy { $0.effects == effects }, "Cross-scale paste must preserve visible blur and shadow distances")
        let reflected = SpacesObjects.reflected(direction, ids: ids, horizontal: true)
        try check(CanvasPlan(direction: reflected).elements.count == affected.elements.count && reflected.objectEffects == direction.objectEffects, "Flip retains effects and never creates copies")
        var doubled = direction; doubled.canvasScale = 2
        try check(CanvasPlan(direction: doubled).elements.allSatisfy { $0.effects == effects.scaledForCanvas(2) }, "Whole-canvas scaling must scale effects exactly once")
        var transformed = direction; transformed.objectTransforms = Dictionary(uniqueKeysWithValues: ids.map { ($0, CanvasObjectTransform(scale: 1.5)) })
        try check(CanvasPlan(direction: transformed).elements.allSatisfy { $0.effects == effects.scaledForCanvas(1.5) }, "Object scaling must scale effects exactly once")
        var reset = direction; reset.objectEffects = nil; reset.importedLayout?.layers[0].effects = effects
        let shapeID = affected.elements[0].objectID
        reset.objectEffects = [shapeID: CanvasObjectEffects()]
        try check(!CanvasPlan(direction: reset).elements[0].effects.isActive, "Explicit reset must override imported layer effects")
        let removed = SpacesObjects.removing(ids, from: direction)
        try check(removed.objectEffects?.isEmpty == true, "Removed objects must not retain orphaned effect overrides")
        let huge = CGRect(x: 0, y: 0, width: 100_000, height: 100_000)
        let scale = CanvasObjectEffectsRenderer.rasterScale(for: huge, requested: 8)
        try check(huge.width * huge.height * scale * scale <= Double(CanvasObjectEffectsRenderer.maximumPixels) + 1, "Effect raster work must be bounded")
        try verifyBulkEdits()
        try verifyRendering(direction: direction, plain: neutral)
        let report = StudioTransferReport(format: .figma, scope: "Fixture", directions: [direction], availableFonts: ["Helvetica"])
        try check(report.omittedEffectsCount == 2 && report.effectsOmissionNote?.contains("Blur and shadow are omitted") == true, "Visible editable-export review must disclose effects omission")
        let pdfReport = StudioTransferReport(format: .previewPDF, scope: "Fixture", directions: [direction], availableFonts: ["Helvetica"])
        try check(pdfReport.effectsOmissionNote == nil, "Preview PDF preserves effects without an omission warning")
        print("PASS: effect defaults/validation, document and clipboard round trips, text/shape and canvas scaling, flips, bounded raster cache, visible blur/shadow, and PDF effects")
    }
    private static func verifyBulkEdits() throws {
        func check(_ value: @autoclosure () -> Bool, _ message: String) throws {
            if !value() { throw NSError(domain: "Typefield.EffectsChecks", code: 9, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        let first = CanvasObjectEffects(blurRadius: 6, shadowEnabled: true, shadowColor: "A02391", shadowOpacity: 0.2,
                                        shadowRadius: 11.123456789012345, shadowX: 23.123456789012345, shadowY: -5.987654321098765)
        let second = CanvasObjectEffects(blurRadius: 2, shadowColor: "3020A0", shadowOpacity: 0.8,
                                         shadowRadius: 3.987654321098765, shadowX: -18.123456789012345, shadowY: 30.987654321098765)
        let third = CanvasObjectEffects(blurRadius: 0, shadowColor: "103022", shadowOpacity: 0.3, shadowRadius: 1, shadowX: 4, shadowY: 7)
        var source = TypeDirection(name: "Mixed effects edit fixture")
        source.canvas = .imported; source.width = 320; source.canvasWidth = 320; source.canvasHeight = 240
        source.importedLayout = ImportedLayout(width: 320, height: 240, layers: [
            ImportedLayer(id: "a", name: "First", x: 20, y: 20, width: 30, height: 30, color: "111111", effects: first),
            ImportedLayer(id: "b", name: "Second", x: 60, y: 20, width: 30, height: 30, color: "222222"),
            ImportedLayer(id: "c", name: "Unselected", x: 100, y: 20, width: 30, height: 30, color: "333333", effects: third)
        ])
        let elements = CanvasPlan(direction: source).elements
        let a = elements[0].objectID, b = elements[1].objectID
        let ids: Set<String> = [a, b]
        source.objectEffects = [b: second]
        var expected = source, expectedFirst = first, expectedSecond = second
        expectedFirst.shadowOpacity = 0.5; expectedSecond.shadowOpacity = 0.5
        expected.objectEffects = [a: expectedFirst, b: expectedSecond]
        let opacity = CanvasObjectEffects.applying(to: source, ids: ids, key: \.shadowOpacity, displayedValue: 0.5)
        try check(opacity == expected, "Bulk opacity must preserve distinct blur, shadows, source-layer values and all unselected data exactly")
        source.canvasScale = 2
        source.objectTransforms = [a: CanvasObjectTransform(scale: 0.75), b: CanvasObjectTransform(scale: 1.5)]
        expected = source; expectedFirst = first; expectedSecond = second
        expectedFirst.blurRadius = 8 / (2 * 0.75); expectedSecond.blurRadius = 8 / (2 * 1.5)
        expected.objectEffects = [a: expectedFirst, b: expectedSecond]
        let blur = CanvasObjectEffects.applying(to: source, ids: ids, key: \.blurRadius, displayedValue: 8.0)
        try check(blur == expected, "Bulk distances must use each object's scale while retaining unrelated stored scalars bit-for-bit")
        try check(CanvasPlan(direction: blur).elements.filter { ids.contains($0.objectID) }.allSatisfy { abs($0.effects.blurRadius - 8) < 0.000001 }, "Bulk edit must display the requested distance on differently scaled objects")
        var untouched = source; untouched.objectEffects = nil
        for selection: Set<String> in [[], ["missing-object"]] {
            let result = CanvasObjectEffects.applying(to: untouched, ids: selection, key: \.blurRadius, displayedValue: 8.0)
            try check(result == untouched && result.objectEffects == nil, "Empty and unknown IDs must leave the complete document and nil overrides unchanged")
        }
        let equal = CanvasObjectEffects.applying(to: untouched, ids: [a], key: \.shadowColor, displayedValue: first.shadowColor)
        try check(equal == untouched && equal.objectEffects == nil, "Unchanged property values must not create phantom overrides")
        let invalidColor = CanvasObjectEffects.applying(to: source, ids: ids, key: \.shadowColor, displayedValue: "not a color")
        let invalidNumber = CanvasObjectEffects.applying(to: source, ids: ids, key: \.blurRadius, displayedValue: Double.nan)
        try check(invalidColor == source && invalidNumber == source, "Invalid colors and nonfinite values must reject the complete bulk edit")
        var partiallyValid = source
        // The first object accepts 1500 / 3 = 500; the second would exceed the
        // stored-radius limit at 1500 / 1.5 = 1000. Increase it just past that.
        partiallyValid.objectTransforms = [a: CanvasObjectTransform(scale: 1.5), b: CanvasObjectTransform(scale: 0.75)]
        let rejected = CanvasObjectEffects.applying(to: partiallyValid, ids: ids, key: \.blurRadius, displayedValue: 1500.5)
        try check(rejected == partiallyValid, "A later invalid object must reject earlier valid changes atomically")
    }
    private static func verifyRendering(direction: TypeDirection, plain: CanvasPlan) throws {
        func raster(_ plan: CanvasPlan) throws -> (Data, Int, Int) {
            let view = CanvasNativeView(plan: plan)
            let pdf = view.dataWithPDF(inside: view.bounds)
            guard let provider = CGDataProvider(data: pdf as CFData), let document = CGPDFDocument(provider), let page = document.page(at: 1),
                  let context = CGContext(data: nil, width: 320, height: 240, bitsPerComponent: 8, bytesPerRow: 320 * 4,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                throw NSError(domain: "Typefield.EffectsChecks", code: 4, userInfo: [NSLocalizedDescriptionKey: "Effects PDF must be readable"])
            }
            context.drawPDFPage(page)
            guard let image = context.makeImage(), let bytes = image.dataProvider?.data else { throw NSError(domain: "Typefield.EffectsChecks", code: 5) }
            return (bytes as Data, image.width, image.height)
        }
        CanvasObjectEffectsRenderer.removeAll()
        let base = try raster(plain)
        let effected = try raster(CanvasPlan(direction: direction))
        func difference(in box: CGRect) -> Int {
            var count = 0
            for y in Int(box.minY)..<Int(box.maxY) {
                for x in Int(box.minX)..<Int(box.maxX) {
                    let i = (y * base.1 + x) * 4
                    if abs(Int(base.0[i]) - Int(effected.0[i])) + abs(Int(base.0[i+1]) - Int(effected.0[i+1])) + abs(Int(base.0[i+2]) - Int(effected.0[i+2])) > 18 { count += 1 }
                }
            }
            return count
        }
        guard difference(in: CGRect(x: 20, y: 18, width: 110, height: 75)) > 300,
              difference(in: CGRect(x: 135, y: 22, width: 145, height: 80)) > 100 else {
            throw NSError(domain: "Typefield.EffectsChecks", code: 6, userInfo: [NSLocalizedDescriptionKey: "Text and shapes must visibly retain blur/shadow in Preview PDF"])
        }
        guard CanvasObjectEffectsRenderer.cachedBytes > 0, CanvasObjectEffectsRenderer.cachedBytes <= CanvasObjectEffectsRenderer.maximumCacheBytes else {
            throw NSError(domain: "Typefield.EffectsChecks", code: 7, userInfo: [NSLocalizedDescriptionKey: "Effects cache must contain bounded rendered objects"])
        }
        let bytesBefore = CanvasObjectEffectsRenderer.cachedBytes
        var moved = direction
        moved.objectTransforms = Dictionary(uniqueKeysWithValues: plain.elements.map { ($0.objectID, CanvasObjectTransform(x: 2, y: 3)) })
        _ = try raster(CanvasPlan(direction: moved))
        guard CanvasObjectEffectsRenderer.cachedBytes == bytesBefore else {
            throw NSError(domain: "Typefield.EffectsChecks", code: 8, userInfo: [NSLocalizedDescriptionKey: "Moving must reuse effect raster entries"])
        }
        CanvasObjectEffectsRenderer.removeAll()
    }
}
