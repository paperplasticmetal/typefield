import SwiftUI
import AppKit
import CoreText
import ImageIO

enum CanvasKind: String, Codable, CaseIterable { case website = "Website", product = "Product UI", editorial = "Editorial", poster = "Poster", specimen = "Type system", custom = "Custom layout", imported = "Figma layout" }
enum ImportedLayoutSource: String, Codable {
    case figma
    case illustrator
    case indesign

    var displayName: String {
        switch self {
        case .figma: return "Figma layout"
        case .illustrator: return "Illustrator layout"
        case .indesign: return "InDesign layout"
        }
    }
    var unitLabel: String { self == .figma ? "px" : "pt" }
}
enum TypeRole: String, Codable, CaseIterable, Identifiable {
    case display = "Display", heading = "Heading", subheading = "Subheading", body = "Body", label = "UI label", caption = "Caption", mono = "Monospace"
    var id: String { rawValue }
    var size: Double { switch self { case .display: return 64; case .heading: return 36; case .subheading: return 24; case .body: return 18; case .label: return 14; case .caption: return 12; case .mono: return 14 } }
    var sample: String { switch self { case .display: return "A new perspective."; case .heading: return "Designed for everyday life"; case .subheading: return "Details make the difference"; case .body: return "Good design begins with a clear idea. Explore a collection of considered objects, useful tools, and stories about the way we live."; case .label: return "Explore collection"; case .caption: return "Studio Journal, September 2026"; case .mono: return "0123456789  /  Aa Bb Cc  /  { type: true }" } }
}
struct TypeStyle: Codable, Equatable {
    var fontName: String
    var size: Double
    var leading: Double = 1.35
    var tracking: Double = 0
    var axes: [Int: Double] = [:]
    var features: [String: Int] = [:]
    var text: String
    var alignment: TextAlignmentOption?
    var kerning: Bool?
    var lineHeight: Double?
    var paragraphSpacing: Double?
    var wordSpacing: Double?
    var indent: Double?
    var casing: TextCaseOption?
    var underline: Bool?
    var strikethrough: Bool?
    var kerningOverride: Bool? {
        if let kerning { return kerning }
        if let legacy = features["kern"] { return legacy != 0 }
        return nil
    }
    var effectiveKerning: Bool { kerningOverride ?? true }
    var featuresWithoutKerning: [String: Int] { features.filter { $0.key != "kern" } }
    var canonicalFeatures: [String: Int] {
        var values = featuresWithoutKerning
        if let kerningOverride { values["kern"] = kerningOverride ? 1 : 0 }
        return values
    }
    mutating func setKerning(_ enabled: Bool) {
        kerning = enabled
        features.removeValue(forKey: "kern")
    }
    var font: CTFont { OpenType.font(name: fontName, size: size, axes: axes, features: canonicalFeatures) }
    func attributed(_ source: String? = nil, color: NSColor) -> NSAttributedString {
        let raw = source ?? text
        let value = casing == .upper ? raw.uppercased() : casing == .lower ? raw.lowercased() : raw
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = (alignment ?? .left).native
        paragraph.minimumLineHeight = lineHeight ?? size * leading
        paragraph.maximumLineHeight = paragraph.minimumLineHeight
        paragraph.paragraphSpacing = paragraphSpacing ?? 0
        paragraph.firstLineHeadIndent = indent ?? 0
        paragraph.lineBreakMode = .byWordWrapping
        var attributes: [NSAttributedString.Key: Any] = [.font: font as NSFont, .foregroundColor: color, .paragraphStyle: paragraph]
        if tracking != 0 || !effectiveKerning { attributes[.kern] = tracking }
        if underline == true { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        if strikethrough == true { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        let result = NSMutableAttributedString(string: value, attributes: attributes)
        if let spacing = wordSpacing, spacing != 0 {
            let string = value as NSString
            for i in 0..<string.length where string.character(at: i) == 32 { result.addAttribute(.kern, value: tracking + spacing, range: NSRange(location: i, length: 1)) }
        }
        return result
    }
    func scaledForCanvas(_ factor: Double) -> TypeStyle {
        guard factor != 1 else { return self }
        var scaled = self
        scaled.size *= factor
        scaled.tracking *= factor
        scaled.lineHeight = lineHeight.map { $0 * factor }
        scaled.paragraphSpacing = paragraphSpacing.map { $0 * factor }
        scaled.wordSpacing = wordSpacing.map { $0 * factor }
        scaled.indent = indent.map { $0 * factor }
        return scaled
    }
}

enum SpacesProofing {
    static func contrastRatio(ink: String, paper: String) -> Double? {
        func luminance(_ hex: String) -> Double? {
            guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
            let channels = [16, 8, 0].map { shift -> Double in
                let component = Double((value >> shift) & 0xff) / 255
                return component <= 0.04045 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]
        }
        guard let foreground = luminance(ink), let background = luminance(paper) else { return nil }
        return (max(foreground, background) + 0.05) / (min(foreground, background) + 0.05)
    }

    static func longestLine(_ text: String) -> Int {
        text.components(separatedBy: "\n").map(\.count).max() ?? 0
    }
}
enum TextAlignmentOption: String, Codable, CaseIterable { case left = "Left", center = "Center", right = "Right", justified = "Justified"
    var native: NSTextAlignment { switch self { case .left: return .left; case .center: return .center; case .right: return .right; case .justified: return .justified } }
}
enum TextCaseOption: String, Codable, CaseIterable { case original = "Original", upper = "UPPERCASE", lower = "lowercase" }
struct LayoutBlock: Codable, Identifiable, Equatable { var id = UUID().uuidString; var role: TypeRole }
struct CanvasBoardPosition: Codable, Equatable {
    var x: Double
    var y: Double
    var isValid: Bool { x.isFinite && y.isFinite && (0...100_000).contains(x) && (0...100_000).contains(y) }
}
struct TypeDirection: Codable, Identifiable, Equatable {
    static let maximumTextBytes = 200_000
    var id = UUID()
    var name = "Direction A"
    var canvas: CanvasKind = .website
    var width: Double = 960
    /// Optional to preserve layouts saved before canvases could be arranged freely.
    var boardPosition: CanvasBoardPosition?
    /// Uniformly scales the finished canvas, including its typography and artwork.
    /// The format width above remains the editable, unscaled template width.
    var canvasScale: Double?
    /// Optional explicit imported artboard width. Nil preserves legacy bounds
    /// that expand to include layers extending beyond the source declaration.
    var canvasWidth: Double?
    /// Optional artboard height override used by independent vertical resizing.
    /// Missing values retain the height generated by the canvas content.
    var canvasHeight: Double?
    var ink = "222222"
    var paper = "FFFFFF"
    var accent = "C59937"
    var styles: [String: TypeStyle] = [:]
    var notes = ""
    var blocks: [TypeRole]?
    var addedBlocks: [LayoutBlock]?
    var sectionOrder: [String]?
    var hiddenSections: Set<String>?
    var importedLayout: ImportedLayout?
    /// Artwork is independent of the template and its typography, including
    /// on canvases that did not originate from an imported layout.
    var artworkLayers: [ImportedLayer]?
    /// Optional so projects created before source tracking still decode. A
    /// missing value denotes the original Figma import flow.
    var importedSource: ImportedLayoutSource?
    var importWarnings: [String]?
    var textOverrides: [String: String]?
    var textPositions: [String: CanvasTextPosition]?
    var canvasDisplayName: String { canvas == .imported ? (importedSource ?? .figma).displayName : canvas.rawValue }
    var canvasUnitLabel: String { canvas == .imported ? (importedSource ?? .figma).unitLabel : "px" }
    var artworkLayersAreValid: Bool {
        let layers = artworkLayers ?? []
        return layers.count <= 128 && Set(layers.map(\.id)).count == layers.count &&
            layers.allSatisfy(\.isValidArtwork) &&
            layers.reduce(0) { $0 + ($1.artworkData?.count ?? 0) } <= 64 * 1024 * 1024
    }
    var maximumCanvasScale: Double {
        let widest = max(width, canvasWidth ?? width, importedLayout?.layers.map { $0.x + $0.width }.max() ?? width,
                         artworkLayers?.map { $0.x + $0.width }.max() ?? width) + 12
        let tallest = max(canvasHeight ?? 0, importedLayout?.height ?? 1, importedLayout?.layers.map { $0.y + $0.height }.max() ?? 1,
                          artworkLayers?.map { $0.y + $0.height }.max() ?? 1) + 12
        let fontSize = (canvas == .imported ? importedLayout?.layers.compactMap { $0.style?.size }.max() : styles.values.map(\.size).max()) ?? 1
        let strokeWidth = importedLayout?.layers.map(\.visibleStrokeWidth).max() ?? 0
        let exportSafe = min(4, 10_000 / max(1, widest), 10_000 / max(1, tallest),
                             1_000 / max(1, fontSize), 1_000 / max(1, strokeWidth))
        // A legacy imported artboard may already exceed an exporter's bounds.
        // Keep its existing 1× size reachable and allow gradual reduction.
        return canvas == .imported ? max(1, exportSafe) : exportSafe
    }
    var minimumCanvasScale: Double { min(0.2, max(0.02, maximumCanvasScale / 4)) }
    var minimumCanvasHeight: Double { 1 }
    var maximumCanvasHeight: Double { 10_000 }
    static func seededFontIndex(for role: TypeRole, count: Int) -> Int {
        guard count > 1 else { return 0 }
        switch role {
        case .display: return 0
        case .heading: return count == 2 ? 0 : min(1, count - 1)
        case .subheading: return count == 2 ? 0 : min(count >= 5 ? 2 : 1, count - 1)
        case .body: return min(count >= 5 ? 3 : 2, count - 1)
        case .label, .caption: return min(count >= 6 ? 4 : (count >= 3 ? 2 : 1), count - 1)
        case .mono: return count - 1
        }
    }
    init(name: String = "Canvas 1", fonts: [String] = [], roleFonts: [String: String] = [:]) {
        self.name = name
        for role in TypeRole.allCases {
            let fallback = role == .mono ? "Menlo-Regular" : role == .display || role == .heading ? "Georgia" : "Helvetica"
            let index = Self.seededFontIndex(for: role, count: fonts.count)
            styles[role.rawValue] = TypeStyle(fontName: roleFonts[role.rawValue] ?? (fonts.isEmpty ? fallback : fonts[index]), size: role.size, text: role.sample)
        }
    }
    func style(_ role: TypeRole) -> TypeStyle { styles[role.rawValue] ?? TypeStyle(fontName: "Helvetica", size: role.size, text: role.sample) }
    mutating func setCanvasText(_ text: String, textID: String) {
        var overrides = textOverrides ?? [:]
        overrides[textID] = text
        textOverrides = overrides
    }
    static func acceptsCanvasText(_ text: String) -> Bool { text.utf8.count <= maximumTextBytes }
    @discardableResult mutating func setImportedText(_ text: String, layerID: String) -> Bool {
        guard let index = importedLayout?.layers.firstIndex(where: { $0.id == layerID }), var style = importedLayout?.layers[index].style else { return false }
        style.text = text
        importedLayout?.layers[index].style = style
        return true
    }
    func copy(name: String? = nil) -> TypeDirection { var value = self; value.id = UUID(); value.name = name ?? self.name + " copy"; value.boardPosition = nil; return value }
    mutating func reorder(_ source: String, target: String, before: Bool, visible: [String]) {
        guard source != target, visible.contains(source), visible.contains(target) else { return }
        var order = visible.filter { $0 != source }
        guard let index = order.firstIndex(of: target) else { return }
        order.insert(source, at: index + (before ? 0 : 1)); sectionOrder = order
    }
    @discardableResult mutating func insert(_ role: TypeRole, target: String?, before: Bool, visible: [String]) -> String {
        let block = LayoutBlock(role: role)
        addedBlocks = (addedBlocks ?? []) + [block]
        let sectionID = canvas.rawValue + ":" + block.id
        var order = visible
        if let target, let index = order.firstIndex(of: target) { order.insert(sectionID, at: index + (before ? 0 : 1)) }
        else { order.append(sectionID) }
        sectionOrder = order
        return sectionID
    }
}
struct ImportedLayer: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var name: String
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var color: String
    var opacity: Double = 1
    var radius: Double = 0
    var style: TypeStyle?
    /// Optional fields keep Spaces saved before stroke editing readable.
    var strokeColor: String?
    var strokeOpacity: Double?
    var strokeWidth: Double?
    /// A bounded, normalized PNG embedded in the project, so artwork remains
    /// available after its source file is moved or access is revoked.
    var artworkData: Data?
    /// Missing in existing projects; newly imported artwork sits behind the
    /// template until the user explicitly brings it in front.
    var artworkInFront: Bool?
    var isValidArtwork: Bool {
        guard let artworkData, artworkData.count > 8,
              artworkData.count <= SpacesArtworkImport.maximumEmbeddedBytes else { return false }
        return artworkData.starts(with: SpacesArtworkImport.pngSignature) &&
            !name.isEmpty && name.count <= 1_024 &&
            [x, y, width, height, opacity].allSatisfy(\.isFinite) &&
            abs(x) <= 100_000 && abs(y) <= 100_000 &&
            (0.01...100_000).contains(width) && (0.01...100_000).contains(height) &&
            (0...1).contains(opacity) && style == nil &&
            strokeColor == nil && strokeOpacity == nil && strokeWidth == nil
    }
    var visibleStrokeWidth: Double { strokeColor == nil ? 0 : (strokeWidth ?? 0) }
    var rect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}
struct ImportedLayout: Codable, Equatable {
    var width: Double
    var height: Double
    var layers: [ImportedLayer]
    /// Use the first text layer only for the initial inspector state. A
    /// selected shape must not redirect edits to an unrelated text layer.
    func textLayerIndex(selectedID: String?) -> Int? {
        if let selectedID { return layers.firstIndex { $0.id == selectedID && $0.style != nil } }
        return layers.firstIndex { $0.style != nil }
    }
    var isValid: Bool {
        width.isFinite && height.isFinite && (1...10000).contains(width) && (1...100000).contains(height) && layers.count <= 5000 && Set(layers.map(\.id)).count == layers.count && layers.allSatisfy { layer in
            [layer.x, layer.y, layer.width, layer.height, layer.opacity, layer.radius].allSatisfy(\.isFinite) && abs(layer.x) <= 100000 && abs(layer.y) <= 100000 && (0.01...100000).contains(layer.width) && (0.01...100000).contains(layer.height) && (0...1).contains(layer.opacity) && (0...10000).contains(layer.radius) &&
            (layer.strokeColor.map { $0.range(of: #"^[0-9A-Fa-f]{6}$"#, options: .regularExpression) != nil } ?? true) &&
            (layer.strokeWidth.map { $0.isFinite && (0...1000).contains($0) && ($0 == 0 || layer.strokeColor != nil) } ?? true) &&
            (layer.strokeOpacity.map { $0.isFinite && (0...1).contains($0) } ?? true) &&
            layer.artworkData == nil &&
            (layer.style == nil || (layer.strokeColor == nil && layer.strokeWidth == nil && layer.strokeOpacity == nil)) &&
            (layer.style.map { $0.size.isFinite && (1...1000).contains($0.size) && TypeDirection.acceptsCanvasText($0.text) && $0.tracking.isFinite && abs($0.tracking) <= 100 && ($0.lineHeight.map { $0.isFinite && (1...2000).contains($0) } ?? true) && $0.axes.values.allSatisfy(\.isFinite) && [$0.paragraphSpacing, $0.indent, $0.wordSpacing].allSatisfy { $0.map { $0.isFinite && abs($0) <= 1000 } ?? true } } ?? true)
        }
    }
}

enum SpacesArtworkImportError: LocalizedError {
    case unsupported
    case tooLarge
    case unreadable
    case cannotRender

    var errorDescription: String? {
        switch self {
        case .unsupported: return "Choose an SVG, PNG, JPEG, TIFF, HEIC, BMP, or GIF image."
        case .tooLarge: return "This artwork is too large for an embedded Spaces image. Choose a smaller export."
        case .unreadable: return "The artwork file could not be read. Try exporting it as PNG."
        case .cannotRender: return "The artwork could not be rendered. Try exporting it as PNG."
        }
    }
}

/// Imports an image into the project itself rather than retaining a path to a
/// protected folder. SVG is validated by the existing plain-SVG reader and
/// rasterized once; the Spaces image is not an editable vector object.
enum SpacesArtworkImport {
    static let supportedExtensions: Set<String> = ["svg", "png", "jpg", "jpeg", "tif", "tiff", "heic", "heif", "bmp", "gif"]
    static let maximumSourceBytes = 64 * 1024 * 1024
    static let maximumEmbeddedBytes = 16 * 1024 * 1024
    static let pngSignature: [UInt8] = [137, 80, 78, 71, 13, 10, 26, 10]

    static func load(_ url: URL) throws -> ImportedLayer {
        guard url.isFileURL, supportedExtensions.contains(url.pathExtension.lowercased()) else {
            throw SpacesArtworkImportError.unsupported
        }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data: Data
        do {
            data = try TypefieldInputFile.read(url, maximumBytes: maximumSourceBytes)
        } catch let error as CocoaError where error.code == .fileReadTooLarge {
            throw SpacesArtworkImportError.tooLarge
        } catch {
            // Preserve the input reader's specific regular-file/permission
            // explanation instead of silently following a dropped symlink.
            throw error
        }
        guard !data.isEmpty else { throw SpacesArtworkImportError.unreadable }
        guard data.count <= maximumSourceBytes else { throw SpacesArtworkImportError.tooLarge }

        let source: CGImage
        if url.pathExtension.lowercased() == "svg" {
            source = try FontLabArtworkReader.svgImage(data)
        } else {
            guard let decoder = CGImageSourceCreateWithData(data as CFData, nil),
                  let image = CGImageSourceCreateThumbnailAtIndex(decoder, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 2400,
                    kCGImageSourceShouldCacheImmediately: true
                  ] as CFDictionary), image.width > 0, image.height > 0 else {
                throw SpacesArtworkImportError.cannotRender
            }
            source = image
        }
        let (png, width, height) = try normalizedPNG(source)
        var layer = ImportedLayer(name: url.deletingPathExtension().lastPathComponent,
                                  x: 0, y: 0, width: Double(width), height: Double(height), color: "FFFFFF")
        layer.artworkData = png
        return layer
    }

    private static func normalizedPNG(_ source: CGImage) throws -> (Data, Int, Int) {
        for limit in [2400, 1800, 1200] {
            let image: CGImage
            if max(source.width, source.height) > limit {
                let scale = Double(limit) / Double(max(source.width, source.height))
                let width = max(1, Int((Double(source.width) * scale).rounded()))
                let height = max(1, Int((Double(source.height) * scale).rounded()))
                guard let context = CGContext(data: nil, width: width, height: height,
                                              bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                    throw SpacesArtworkImportError.cannotRender
                }
                context.interpolationQuality = .high
                context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
                guard let scaled = context.makeImage() else { throw SpacesArtworkImportError.cannotRender }
                image = scaled
            } else {
                image = source
            }
            guard let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
                throw SpacesArtworkImportError.cannotRender
            }
            if png.count <= maximumEmbeddedBytes { return (png, image.width, image.height) }
        }
        throw SpacesArtworkImportError.tooLarge
    }
}

struct TypeBoard: Codable, Identifiable, Equatable {
    var id = UUID()
    var name = "Untitled typeboard"
    var directions = [TypeDirection()]
    var selectedDirection: UUID?
    var candidates: [String] = []
    var checkpoints: [DirectionCheckpoint]?
    func canvasName(_ canvas: TypeDirection) -> String {
        if canvas.name.range(of: #"^Direction [A-Z]( copy)*$"#, options: .regularExpression) != nil { return "Canvas \((directions.firstIndex { $0.id == canvas.id } ?? 0) + 1)" }
        return canvas.name
    }
    var nextCanvasName: String { var number = directions.count + 1; while directions.contains(where: { canvasName($0) == "Canvas \(number)" }) { number += 1 }; return "Canvas \(number)" }
    var isValid: Bool { !directions.isEmpty && directions.allSatisfy(\.isValid) && (checkpoints ?? []).allSatisfy { $0.direction.isValid } }
}
struct DirectionCheckpoint: Codable, Identifiable, Equatable {
    var id = UUID()
    var date = Date()
    var direction: TypeDirection
}
enum StudioCheckpointSave {
    static let maximumCount = 50
    struct Outcome {
        var board: TypeBoard
        var saved: Bool
    }

    static func save(direction: TypeDirection, board: TypeBoard, persist: (TypeBoard) -> TypeBoard) -> Outcome {
        var proposed = board
        var checkpoints = proposed.checkpoints ?? []
        let checkpoint = DirectionCheckpoint(direction: direction)
        checkpoints.append(checkpoint)
        proposed.checkpoints = Array(checkpoints.suffix(maximumCount))
        let persisted = persist(proposed)
        return Outcome(board: persisted, saved: persisted.checkpoints?.contains(where: { $0.id == checkpoint.id }) == true)
    }
}
struct DesignSpace: Codable, Identifiable {
    var id = UUID()
    var name = "Untitled space"
    var boards: [TypeBoard] = []
    var displayName: String { name == "Pairing Studio" ? "My projects" : name }
}

/// Describes what crossed a Spaces import/export boundary. Keep this based on
/// the saved layout and the current font catalog, not on a preview fallback.
struct StudioTransferReport {
    enum Format {
        case spaceJSON, developerHandoff, previewPDF, figma, typographySummary,
             typeSystemPDF, adobeBuilder

        var title: String {
            switch self {
            case .spaceJSON: return "Space JSON"
            case .developerHandoff: return "Developer handoff"
            case .previewPDF: return "Preview PDF"
            case .figma: return "Editable Figma layout"
            case .typographySummary: return "Typography summary"
            case .typeSystemPDF: return "Type system PDF"
            case .adobeBuilder: return "Adobe builder"
            }
        }
        var omitsArtwork: Bool {
            switch self {
            case .developerHandoff, .figma, .adobeBuilder, .typographySummary: return true
            default: return false
            }
        }
        var limitation: String {
            switch self {
            case .spaceJSON: return "Saved layout data and embedded artwork are included. Font files are not bundled."
            case .developerHandoff: return "Exports CSS, tokens, and a specimen. Font files and canvas artwork are not bundled."
            case .previewPDF: return "Exports each selected canvas as a separate visual PDF page. Text and images are not editable as Spaces objects in the PDF."
            case .figma: return "Exports editable text and shapes. Images are omitted, font files are not bundled, and Figma may reflow text."
            case .typographySummary: return "Exports typography settings for the selected canvases. Canvas layout and artwork are not included."
            case .typeSystemPDF: return "Builds one specimen page per selected canvas. Imported Figma and Adobe canvases are not supported."
            case .adobeBuilder: return "Creates an editable document inside Adobe. Images are omitted; fonts must be installed there. Text may reflow, and variable axes and OpenType features remain metadata."
            }
        }
    }

    let format: Format
    let scope: String
    let directions: [TypeDirection]
    let availableFonts: Set<String>

    var referencedFonts: Set<String> {
        directions.reduce(into: Set<String>()) { names, direction in
            names.formUnion(StudioFontCollection.fontNames(in: direction))
            if format == .developerHandoff && direction.canvas != .imported { names.formUnion(direction.styles.values.map(\.fontName)) }
        }
    }
    var missingFonts: [String] { referencedFonts.subtracting(availableFonts).sorted() }
    var artworkCount: Int {
        directions.reduce(0) { $0 + CanvasPlanCache.plan(for: $1).elements.filter { $0.image != nil }.count }
    }
    var omittedArtworkCount: Int { format.omitsArtwork ? artworkCount : 0 }
    var blockingReason: String? {
        if format == .typeSystemPDF && directions.contains(where: { $0.canvas == .imported }) {
            return "The selection includes an imported Figma or Adobe canvas. Choose only native canvases or use Preview PDF for the imported layout."
        }
        if format == .adobeBuilder && directions.count > 100 { return "Adobe builders support up to 100 selected canvases." }
        return nil
    }
    var detail: String {
        var lines = ["Scope: " + scope, "Referenced fonts: \(referencedFonts.count)"]
        if missingFonts.isEmpty { lines.append("Unavailable here: none") }
        else {
            lines.append("Unavailable here (fallback in preview): " + missingFonts.prefix(8).joined(separator: ", ")
                         + (missingFonts.count > 8 ? " and \(missingFonts.count - 8) more" : ""))
        }
        if format.omitsArtwork { lines.append("Image layers omitted: \(omittedArtworkCount)") }
        lines.append(format.limitation)
        if let blockingReason { lines.append("Cannot export: " + blockingReason) }
        return lines.joined(separator: "\n")
    }
}

struct StudioImportReport {
    let source: String
    let boards: [TypeBoard]
    let availableFonts: Set<String>
    var canvasCount: Int { boards.reduce(0) { $0 + $1.directions.count } }
    var textLayerCount: Int { boards.flatMap(\.directions).reduce(0) { $0 + CanvasPlanCache.plan(for: $1).elements.filter { $0.text != nil }.count } }
    var warnings: [String] { Array(Set(boards.flatMap(\.directions).flatMap { $0.importWarnings ?? [] })).sorted() }
    var missingFonts: [String] { StudioFontCollection.fontNames(in: boards).subtracting(availableFonts).sorted() }
    var detail: String {
        var lines = ["Source: " + source,
                     "Imported: \(boards.count) \(boards.count == 1 ? "typeboard" : "typeboards"), \(canvasCount) \(canvasCount == 1 ? "canvas" : "canvases"), \(textLayerCount) text \(textLayerCount == 1 ? "layer" : "layers")",
                     missingFonts.isEmpty ? "Unavailable fonts: none" : "Unavailable fonts: " + missingFonts.prefix(8).joined(separator: ", ") + (missingFonts.count > 8 ? " and \(missingFonts.count - 8) more" : ""),
                     "Import notes: \(warnings.count)"]
        lines += warnings.prefix(8)
        if warnings.count > 8 { lines.append("…and \(warnings.count - 8) more; see Import notes on each canvas.") }
        return lines.joined(separator: "\n")
    }
}
enum StudioRoleScope {
    static func affectedTextCount(role: TypeRole, direction: TypeDirection) -> Int {
        CanvasPlanCache.plan(for: direction).elements.filter { $0.role == role && $0.text != nil }.count
    }
}
struct StudioState: Codable {
    var version = 1
    var spaces: [DesignSpace] = []
    var selectedSpace: UUID?
    var selectedBoard: UUID?
}
/// Keep document persistence and Foundation's history movement in one transaction.
/// Failed writes put the same group back on its original stack for retry.
final class StudioUndoManager: UndoManager {
    weak var store: StudioStore?
    override func undo() {
        guard canUndo else { return }
        guard let store else { super.undo(); return }
        store.replayHistory({ super.undo() }, restoringHistory: { super.redo() })
    }
    override func redo() {
        guard canRedo else { return }
        guard let store else { super.redo(); return }
        store.replayHistory({ super.redo() }, restoringHistory: { super.undo() })
    }
}

final class StudioStore: ObservableObject {
    @Published var focusedSpace: UUID?
    @Published var focusedBoard: UUID?
    @Published var state = StudioState()
    @Published var error = ""
    @Published var savedAt: Date?
    let url: URL
    let undoManager = StudioUndoManager()
    private typealias HistoryAction = (name: String, apply: (StudioStore) -> Bool)
    private var replayingHistory = false
    private var restoringHistory = false
    private var historyFailed = false
    private var replayedActions: [HistoryAction] = []
    private var historyRegistrations = 0
    private var lastEdit: (board: UUID, action: String, date: Date)?
    private(set) var readBlocked = false
    init(url: URL, recoveryError: String? = nil) {
        self.url = url
        undoManager.store = self
        undoManager.levelsOfUndo = 100
        if let recoveryError {
            readBlocked = true
            error = recoveryError
            return
        }
        do {
            try TypefieldInputFile.requireRegularFileIfPresent(url)
            guard FileManager.default.fileExists(atPath: url.path) else { return }
            let loaded = try JSONDecoder().decode(StudioState.self, from: Data(contentsOf: url))
            guard loaded.version == 1, loaded.spaces.allSatisfy({ $0.boards.allSatisfy(\.isValid) }) else { throw NSError(domain: "FontShelf", code: 1, userInfo: [NSLocalizedDescriptionKey: "The workspace has invalid data or requires a newer Typefield version."]) }
            state = loaded
            focusedSpace = loaded.selectedSpace; focusedBoard = loaded.selectedBoard
        } catch { readBlocked = true; self.error = "Spaces could not be opened. The saved file has been preserved. " + error.localizedDescription }
    }
    func blockForBackupRecovery(_ message: String) {
        readBlocked = true
        error = message
    }
    @discardableResult func save() -> Bool {
        guard !readBlocked else { return false }
        do {
            guard state.spaces.allSatisfy({ $0.boards.allSatisfy(\.isValid) }) else {
                throw NSError(domain: "Typefield", code: 1, userInfo: [NSLocalizedDescriptionKey: "A typeboard contains invalid data."])
            }
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let focusedSpace, let space = state.spaces.first(where: { $0.id == focusedSpace }) {
                if let focusedBoard, !space.boards.contains(where: { $0.id == focusedBoard }) { self.focusedBoard = nil }
            } else {
                focusedSpace = nil
                focusedBoard = nil
            }
            state.selectedSpace = focusedSpace; state.selectedBoard = focusedBoard
            let data = try JSONEncoder().encode(state)
            try LibraryBackupTools.preserve(url)
            if FileManager.default.fileExists(atPath: url.path) {
                try Data(contentsOf: url).write(to: url.appendingPathExtension("backup"), options: .atomic)
            }
            try data.write(to: url, options: .atomic); savedAt = Date(); error = ""; return true
        } catch { self.error = "Spaces could not be saved: " + error.localizedDescription; return false }
    }
    fileprivate func replayHistory(_ replay: () -> Void, restoringHistory restore: () -> Void) {
        let previousState = state, previousSpace = focusedSpace, previousBoard = focusedBoard
        let previousSavedAt = savedAt, previousEdit = lastEdit
        replayingHistory = true; historyFailed = false; replayedActions = []
        defer { replayingHistory = false; restoringHistory = false; replayedActions = [] }
        replay()
        if !historyFailed && save() { lastEdit = nil; return }
        if historyFailed && error.isEmpty { error = "Spaces history could not be applied. The document and history were preserved." }
        state = previousState; focusedSpace = previousSpace; focusedBoard = previousBoard
        savedAt = previousSavedAt; lastEdit = previousEdit
        // Every replayed action registered an inverse, including a placeholder
        // for rejected actions. Move that group back while restoring only its
        // callbacks; never attempt a second disk write or document mutation.
        restoringHistory = true
        restore()
    }
    private func registerHistory(_ name: String, apply: @escaping (StudioStore) -> Bool) {
        historyRegistrations += 1
        undoManager.registerUndo(withTarget: self) { store in
            if store.restoringHistory {
                guard let original = store.replayedActions.popLast() else { return }
                store.registerHistory(original.name, apply: original.apply)
                return
            }
            store.replayedActions.append((name, apply))
            let registrations = store.historyRegistrations
            if !store.historyFailed && !apply(store) { store.historyFailed = true }
            if store.historyRegistrations == registrations {
                // Keep failed and no-op callbacks in the group so compensation
                // can restore the exact original ordering and retry operation.
                store.registerHistory(name) { _ in true }
            }
        }
        undoManager.setActionName(name)
    }
    /// A failed write must not leave a space or typeboard visible only in memory.
    @discardableResult private func persist(_ edit: () -> Void) -> Bool {
        guard !readBlocked else { return false }
        let previousState = state
        let previousSpace = focusedSpace
        let previousBoard = focusedBoard
        let previousSavedAt = savedAt
        edit()
        if replayingHistory { return true }
        guard save() else {
            state = previousState
            focusedSpace = previousSpace
            focusedBoard = previousBoard
            savedAt = previousSavedAt
            return false
        }
        return true
    }
    func addSpace(_ name: String) -> UUID? {
        let space = DesignSpace(name: name.isEmpty ? "Untitled space" : name)
        guard persist({ state.spaces.append(space); focusedSpace = space.id; focusedBoard = nil }) else { return nil }
        return space.id
    }
    func addBoard(space: UUID, fonts: [String] = [], roleFonts: [String: String] = [:]) -> UUID? {
        createBoard(in: space, defaultSpaceName: "My projects", fonts: fonts, roleFonts: roleFonts)?.board
    }
    /// When the Library starts the first typeboard, create its Space and board in one save.
    func createBoard(in space: UUID?, defaultSpaceName: String, fonts: [String] = [], roleFonts: [String: String] = [:]) -> (space: UUID, board: UUID)? {
        guard space == nil || state.spaces.contains(where: { $0.id == space }) else { return nil }
        let target = space ?? UUID()
        let existing = state.spaces.first(where: { $0.id == target })
        var number = (existing?.boards.count ?? 0) + 1
        while existing?.boards.contains(where: { $0.name == "Typeboard \(number)" }) == true { number += 1 }
        let board = TypeBoard(name: "Typeboard \(number)", directions: [TypeDirection(fonts: fonts, roleFonts: roleFonts)], candidates: fonts)
        guard persist({
            if space == nil { state.spaces.append(DesignSpace(id: target, name: defaultSpaceName)) }
            guard let index = state.spaces.firstIndex(where: { $0.id == target }) else { return }
            state.spaces[index].boards.append(board)
            focusedSpace = target
            focusedBoard = board.id
        }) else { return nil }
        return (target, board.id)
    }
    @discardableResult func update(space: UUID, board: TypeBoard, action: String = "Edit Typeboard") -> Bool {
        update(space: space, board: board, action: action, focus: false)
    }
    @discardableResult private func update(space: UUID, board: TypeBoard, action: String, focus: Bool) -> Bool {
        guard let i = state.spaces.firstIndex(where: { $0.id == space }), let j = state.spaces[i].boards.firstIndex(where: { $0.id == board.id }) else { return false }
        let previous = state.spaces[i].boards[j]
        guard previous != board else { return true }
        // Direction navigation isn't a document edit and shouldn't fill the undo stack.
        var content = previous; content.selectedDirection = board.selectedDirection
        let contentChanged = content != board
        let replaying = undoManager.isUndoing || undoManager.isRedoing
        let coalesced = contentChanged && !replaying && !undoManager.canRedo && undoManager.canUndo && action.hasPrefix("Change ") && action != "Change Font" && lastEdit?.board == board.id && lastEdit?.action == action && Date().timeIntervalSince(lastEdit!.date) < 0.8
        guard persist({
            state.spaces[i].boards[j] = board
            if focus { focusedSpace = space; focusedBoard = board.id }
        }) else { return false }
        if contentChanged {
            if !coalesced {
                if !replaying { undoManager.beginUndoGrouping() }
                registerHistory(action) { store in
                    store.update(space: space, board: previous, action: action, focus: true)
                }
                if !replaying { undoManager.endUndoGrouping() }
            }
            lastEdit = replaying ? nil : (board.id, action, Date())
        } else {
            lastEdit = nil
        }
        return true
    }
    func endUndoCoalescing() { lastEdit = nil }
    @discardableResult func removeBoard(space: UUID, id: UUID) -> Bool {
        guard let i = state.spaces.firstIndex(where: { $0.id == space }), let j = state.spaces[i].boards.firstIndex(where: { $0.id == id }) else { return false }
        let board = state.spaces[i].boards[j]
        guard persist({
            state.spaces[i].boards.remove(at: j)
            if focusedBoard == id { focusedBoard = state.spaces[i].boards.first?.id }
        }) else { return false }
        let replaying = undoManager.isUndoing || undoManager.isRedoing
        if !replaying { undoManager.beginUndoGrouping() }
        registerHistory("Delete Typeboard") { $0.restoreBoard(space: space, board: board, index: j) }
        if !replaying { undoManager.endUndoGrouping() }
        lastEdit = nil
        return true
    }
    private func restoreBoard(space: UUID, board: TypeBoard, index: Int) -> Bool {
        guard let i = state.spaces.firstIndex(where: { $0.id == space }), !state.spaces[i].boards.contains(where: { $0.id == board.id }) else { return false }
        guard persist({
            state.spaces[i].boards.insert(board, at: min(index, state.spaces[i].boards.count))
            focusedSpace = space; focusedBoard = board.id
        }) else { return false }
        registerHistory("Delete Typeboard") { $0.removeBoard(space: space, id: board.id) }
        lastEdit = nil
        return true
    }
    @discardableResult func removeSpace(_ id: UUID) -> Bool {
        guard let index = state.spaces.firstIndex(where: { $0.id == id }) else { return false }
        let removed = state.spaces[index]
        let selectedBoard = focusedSpace == id ? focusedBoard : nil
        guard persist({
            state.spaces.remove(at: index)
            if focusedSpace == id { focusedSpace = nil; focusedBoard = nil }
        }) else { return false }
        let replaying = undoManager.isUndoing || undoManager.isRedoing
        if !replaying { undoManager.beginUndoGrouping() }
        registerHistory("Delete Space") { $0.restoreSpace(removed, at: index, selectedBoard: selectedBoard) }
        if !replaying { undoManager.endUndoGrouping() }
        lastEdit = nil
        return true
    }
    private func restoreSpace(_ space: DesignSpace, at index: Int, selectedBoard: UUID?) -> Bool {
        guard !state.spaces.contains(where: { $0.id == space.id }) else { return false }
        guard persist({
            state.spaces.insert(space, at: min(index, state.spaces.count))
            focusedSpace = space.id
            focusedBoard = space.boards.contains(where: { $0.id == selectedBoard }) ? selectedBoard : space.boards.first?.id
        }) else { return false }
        registerHistory("Delete Space") { $0.removeSpace(space.id) }
        lastEdit = nil
        return true
    }
    @discardableResult func renameSpace(_ id: UUID, to name: String) -> Bool {
        guard let index = state.spaces.firstIndex(where: { $0.id == id }) else { return false }
        return persist { state.spaces[index].name = name }
    }
    @discardableResult func select(space: UUID, board: UUID? = nil) -> Bool {
        guard !readBlocked, let existing = state.spaces.first(where: { $0.id == space }), board.map({ id in existing.boards.contains { $0.id == id } }) ?? true else { return false }
        guard focusedSpace != space || focusedBoard != board else { return true }
        guard persist({ focusedSpace = space; focusedBoard = board }) else { return false }
        // Returning to a board starts a fresh editing interaction, even when
        // navigation was quicker than the numeric-field coalescing interval.
        endUndoCoalescing()
        return true
    }
    @discardableResult func importSpace(_ space: DesignSpace) -> Bool {
        guard space.boards.allSatisfy(\.isValid) else { error = "Space could not be imported: a typeboard contains invalid data."; return false }
        return persist { state.spaces.append(space); focusedSpace = space.id; focusedBoard = nil }
    }
    @discardableResult func importBoard(_ board: TypeBoard, into space: UUID?, defaultSpaceName: String) -> Bool {
        guard board.isValid else { error = "Typeboard could not be imported: invalid layout data."; return false }
        guard space == nil || state.spaces.contains(where: { $0.id == space }) else { return false }
        return persist {
            let target: UUID
            if let space { target = space }
            else {
                let created = DesignSpace(name: defaultSpaceName)
                state.spaces.append(created)
                target = created.id
            }
            guard let index = state.spaces.firstIndex(where: { $0.id == target }) else { return }
            state.spaces[index].boards.append(board)
            focusedSpace = target
            focusedBoard = board.id
        }
    }
}

struct TagQuery: Codable, Equatable {
    var included: Set<String> = []
    var excluded: Set<String> = []
    var matchAll = true
    var active: Bool { !included.isEmpty || !excluded.isEmpty }
    static func contains(_ parent: String, in tags: Set<String>) -> Bool { tags.contains { $0 == parent || $0.hasPrefix(parent + "/") } }
    func matches(_ tags: Set<String>) -> Bool {
        let include = included.isEmpty || (matchAll ? included.allSatisfy { Self.contains($0, in: tags) } : included.contains { Self.contains($0, in: tags) })
        return include && !excluded.contains { Self.contains($0, in: tags) }
    }
    static func hierarchy(_ tags: Set<String>) -> [String] {
        var result = tags
        for tag in tags { let parts = tag.split(separator: "/"); for count in 1..<max(1, parts.count) { result.insert(parts.prefix(count).joined(separator: "/")) } }
        return result.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}
