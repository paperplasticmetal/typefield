import AppKit
import CoreImage

/// Distances are stored in the object's unscaled canvas coordinates. Optional
/// containers on older documents mean no effects, with no migration required.
struct CanvasObjectEffects: Codable, Equatable {
    var blurRadius = 0.0
    var shadowEnabled = false
    var shadowColor = "000000"
    var shadowOpacity = 0.25
    var shadowRadius = 8.0
    var shadowX = 0.0
    var shadowY = 4.0

    var isValid: Bool {
        [blurRadius, shadowRadius].allSatisfy { $0.isFinite && (0...1000).contains($0) } &&
        [shadowX, shadowY].allSatisfy { $0.isFinite && abs($0) <= 10000 } &&
        shadowOpacity.isFinite && (0...1).contains(shadowOpacity) &&
        shadowColor.range(of: #"^[0-9A-Fa-f]{6}$"#, options: .regularExpression) != nil
    }
    var isActive: Bool { blurRadius > 0 || (shadowEnabled && shadowOpacity > 0) }
    func scaledForCanvas(_ factor: Double) -> Self {
        var value = self
        value.blurRadius *= factor; value.shadowRadius *= factor
        value.shadowX *= factor; value.shadowY *= factor
        return value
    }
    /// Apply one explicit inspector edit to a captured set of object IDs.
    /// Copy only the requested property back to its source coordinates: round
    /// tripping the entire rendered effect would alter unrelated stored values.
    /// Invalid edits are rejected as a unit, even if earlier objects accepted it.
    static func applying<T>(to source: TypeDirection, ids: Set<String>,
                            key: WritableKeyPath<Self, T>, displayedValue: T) -> TypeDirection {
        guard !ids.isEmpty, source.isValid else { return source }
        let selected = CanvasPlanCache.plan(for: source).elements.filter { ids.contains($0.objectID) }
        guard !selected.isEmpty else { return source }
        let layers = (source.importedLayout?.layers ?? []) + (source.artworkLayers ?? []) + (source.objectLayers ?? [])
        var bySection: [String: Self] = [:]
        for layer in layers { if let effects = layer.effects { bySection[layer.id] = effects } }
        var overrides = source.objectEffects ?? [:]
        var changed = false
        for element in selected {
            let scale = (source.canvasScale ?? 1) * (source.objectTransforms?[element.objectID]?.scale ?? 1)
            guard scale.isFinite && scale > 0 else { return source }
            let original = overrides[element.objectID] ?? bySection[element.sectionID] ?? Self()
            var requested = Self()
            requested[keyPath: key] = displayedValue
            let converted = requested.scaledForCanvas(1 / scale)
            var replacement = original
            replacement[keyPath: key] = converted[keyPath: key]
            guard replacement.isValid else { return source }
            if replacement != original {
                overrides[element.objectID] = replacement
                changed = true
            }
        }
        guard changed else { return source }
        var result = source
        result.objectEffects = overrides
        return result.isValid ? result : source
    }
    private enum CodingKeys: String, CodingKey {
        case blurRadius, shadowEnabled, shadowColor, shadowOpacity, shadowRadius, shadowX, shadowY
    }
    init(blurRadius: Double = 0, shadowEnabled: Bool = false, shadowColor: String = "000000",
         shadowOpacity: Double = 0.25, shadowRadius: Double = 8, shadowX: Double = 0, shadowY: Double = 4) {
        self.blurRadius = blurRadius; self.shadowEnabled = shadowEnabled; self.shadowColor = shadowColor
        self.shadowOpacity = shadowOpacity; self.shadowRadius = shadowRadius; self.shadowX = shadowX; self.shadowY = shadowY
    }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        blurRadius = try values.decodeIfPresent(Double.self, forKey: .blurRadius) ?? 0
        shadowEnabled = try values.decodeIfPresent(Bool.self, forKey: .shadowEnabled) ?? false
        shadowColor = try values.decodeIfPresent(String.self, forKey: .shadowColor) ?? "000000"
        shadowOpacity = try values.decodeIfPresent(Double.self, forKey: .shadowOpacity) ?? 0.25
        shadowRadius = try values.decodeIfPresent(Double.self, forKey: .shadowRadius) ?? 8
        shadowX = try values.decodeIfPresent(Double.self, forKey: .shadowX) ?? 0
        shadowY = try values.decodeIfPresent(Double.self, forKey: .shadowY) ?? 4
    }
}

extension CanvasPlan {
    /// Resolve after IDs, object transforms and canvas scale are finalized.
    /// A dictionary entry overrides a layer's own settings, including an
    /// explicit zero-effect entry created by Reset Effects.
    mutating func applyObjectEffects(from direction: TypeDirection) {
        let layers = (direction.importedLayout?.layers ?? []) + (direction.artworkLayers ?? []) + (direction.objectLayers ?? [])
        var bySection: [String: CanvasObjectEffects] = [:]
        for layer in layers { if let effects = layer.effects { bySection[layer.id] = effects } }
        for index in elements.indices {
            let element = elements[index]
            let source = direction.objectEffects?[element.objectID] ?? bySection[element.sectionID] ?? CanvasObjectEffects()
            guard source.isValid else { elements[index].effects = CanvasObjectEffects(); continue }
            let scale = (direction.canvasScale ?? 1) * (direction.objectTransforms?[element.objectID]?.scale ?? 1)
            elements[index].effects = source.scaledForCanvas(scale)
        }
    }
}

/// Only affected objects are rasterized; unaffected PDF content remains vector.
/// Moving an object reuses its image because cache comparison excludes origin.
/// Raster buffers are bounded independently of imported document dimensions.
enum CanvasObjectEffectsRenderer {
    static let maximumPixels = 4_000_000
    static let maximumDimension = 4096
    static let maximumCacheBytes = 32 * 1024 * 1024
    private static let ciContext = CIContext(options: [.cacheIntermediates: false])
    private struct Entry { var source: CanvasElement; var scale: Double; var image: CGImage; var used: UInt64 }
    private static var cache: [Entry] = []
    private static var clock: UInt64 = 0
    static var cachedBytes: Int { cache.reduce(0) { $0 + $1.image.bytesPerRow * $1.image.height } }
    static func removeAll() { cache.removeAll() }

    static func drawingBounds(for element: CanvasElement) -> CGRect {
        let effects = element.effects
        let stroke = max(0, element.strokeWidth) / 2
        let base = element.rect.insetBy(dx: -stroke - 2, dy: -stroke - 2)
        let blurred = base.insetBy(dx: -3 * effects.blurRadius, dy: -3 * effects.blurRadius)
        guard effects.shadowEnabled && effects.shadowOpacity > 0 else { return blurred }
        let shadow = blurred.offsetBy(dx: effects.shadowX, dy: effects.shadowY)
            .insetBy(dx: -3 * effects.shadowRadius, dy: -3 * effects.shadowRadius)
        return blurred.union(shadow)
    }
    static func rasterScale(for bounds: CGRect, requested: Double) -> Double {
        guard bounds.width.isFinite, bounds.height.isFinite, bounds.width > 0, bounds.height > 0 else { return 0 }
        return min(max(0.01, requested), Double(maximumDimension) / bounds.width,
                   Double(maximumDimension) / bounds.height,
                   sqrt(Double(maximumPixels) / (bounds.width * bounds.height)))
    }
    private static func sameVisual(_ a: CanvasElement, _ b: CanvasElement) -> Bool {
        a.rect.size == b.rect.size && a.effects == b.effects && a.flipX == b.flipX && a.flipY == b.flipY &&
        a.color == b.color && a.strokeColor == b.strokeColor && a.strokeWidth == b.strokeWidth && a.radius == b.radius &&
        a.image === b.image && a.imageOpacity == b.imageOpacity &&
        ((a.text == nil && b.text == nil) || (a.text?.isEqual(to: b.text ?? NSAttributedString(string: "")) ?? false))
    }
    /// The closure draws the complete base object (including reflections) in
    /// its normal, top-left-origin coordinates. Shadows use canvas X/Y axes.
    static func draw(element: CanvasElement, zoom: Double, drawing: () -> Void) {
        let effects = element.effects
        guard effects.isActive, let destination = NSGraphicsContext.current else { drawing(); return }
        let bounds = drawingBounds(for: element)
        let scale = rasterScale(for: bounds, requested: max(1, zoom) * 2)
        guard scale > 0, [bounds.minX, bounds.minY, bounds.width, bounds.height, effects.blurRadius,
                          effects.shadowRadius, effects.shadowX, effects.shadowY].allSatisfy(\.isFinite) else { drawing(); return }
        clock &+= 1
        let rendered: CGImage
        if let index = cache.firstIndex(where: { $0.scale == scale && sameVisual($0.source, element) }) {
            cache[index].used = clock; rendered = cache[index].image
        } else {
            let width = max(1, min(maximumDimension, Int(floor(bounds.width * scale))))
            let height = max(1, min(maximumDimension, Int(floor(bounds.height * scale))))
            guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { drawing(); return }
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: CGFloat(width) / bounds.width, y: -CGFloat(height) / bounds.height)
            context.translateBy(x: -bounds.minX, y: -bounds.minY)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
            drawing()
            NSGraphicsContext.restoreGraphicsState()
            guard let original = context.makeImage() else { drawing(); return }
            let actualScale = min(CGFloat(width) / bounds.width, CGFloat(height) / bounds.height)
            let source = CIImage(cgImage: original)
            let content = effects.blurRadius > 0 ? source.applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: effects.blurRadius * actualScale]) : source
            var result = content
            if effects.shadowEnabled && effects.shadowOpacity > 0 {
                let color = (NSColor(hex: effects.shadowColor).usingColorSpace(.deviceRGB) ?? .black)
                let shadow = content.applyingFilter("CIColorMatrix", parameters: [
                    "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                    "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                    "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                    "inputAVector": CIVector(x: 0, y: 0, z: 0, w: effects.shadowOpacity),
                    "inputBiasVector": CIVector(x: color.redComponent, y: color.greenComponent, z: color.blueComponent, w: 0)
                ]).applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: effects.shadowRadius * actualScale])
                    .transformed(by: CGAffineTransform(translationX: effects.shadowX * actualScale, y: -effects.shadowY * actualScale))
                result = content.composited(over: shadow)
            }
            guard let image = ciContext.createCGImage(result, from: CGRect(x: 0, y: 0, width: width, height: height)) else { drawing(); return }
            rendered = image
            // A cached element retains its source image/text as well. Bound
            // those too; unknown image representation cost is not cached.
            let sourceCost = element.image.map(CanvasPlanCache.imageBytes) ?? 0
            if sourceCost <= maximumCacheBytes / 4 && (element.text?.length ?? 0) <= 100_000 {
                cache.append(Entry(source: element, scale: scale, image: image, used: clock))
                while cache.count > 32 || cachedBytes + cache.reduce(0, { $0 + ($1.source.image.map(CanvasPlanCache.imageBytes) ?? 0) }) > maximumCacheBytes {
                    guard let oldest = cache.indices.min(by: { cache[$0].used < cache[$1].used }) else { break }
                    cache.remove(at: oldest)
                }
            }
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = destination
        let image = NSImage(cgImage: rendered, size: bounds.size)
        image.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        NSGraphicsContext.restoreGraphicsState()
    }
}
