import Foundation
import AppKit
import ImageIO
import Vision
import zlib

struct FontLabArtworkSource {
    let image: CGImage
    let filename: String
    let format: FontLabImportFormat
    let notices: [String]
}

enum FontLabArtworkLayout: String, CaseIterable, Identifiable {
    case automatic = "Detect letters", grid = "Grid sheet", single = "Single letter"
    var id: String { rawValue }
}

struct FontLabArtworkOptions: Equatable {
    var layout = FontLabArtworkLayout.automatic
    var threshold = 0.55
    var lightInk = false
    var columns = 8
    var rows = 4
    var minimumArea = 5
}

struct FontLabArtworkRegion: Identifiable {
    var id = UUID()
    /// Source pixels, top-left origin. Letter geometry is measured from ink,
    /// never from an OCR box, so dots and counters remain part of the artwork.
    var rect: CGRect
    var character = ""
    var confidence: Float = 0
    var included = true
    var contours: [[FontLabPoint]] = [] // x/y normalized in the region, y-up
}

struct FontLabArtworkScan {
    let source: FontLabArtworkSource
    let mask: FontLabInkMask
    var regions: [FontLabArtworkRegion]
    var notices: [String]
}

enum FontLabArtworkError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(message) = self { return message }; return nil }
}

/// Reads only the selected file. Procreate archives are inspected in memory;
/// no archive paths are extracted, and no layer classes are unarchived.
enum FontLabArtworkReader {
    static let maximumFileBytes = 256 * 1024 * 1024
    static func load(_ url: URL) throws -> FontLabArtworkSource {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let request = try FontLabImportAPI.request(sourceURL: url, targetCharacter: "A")
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= maximumFileBytes else { throw FontLabArtworkError.message("Choose an artwork file smaller than 256 MB. Export a flattened PNG for larger Procreate documents.") }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        var notices: [String] = []
        let image: CGImage
        switch request.format {
        case .svg:
            image = try svgImage(data)
            notices.append("SVG artwork is rendered at high resolution and traced into editable outlines.")
        case .procreate:
            let archive = try FontLabArtworkZIP(data: data)
            guard archive.entries["Document.archive"] != nil || archive.entries["document.archive"] != nil else {
                throw FontLabArtworkError.message("This file does not contain a Procreate document. Export the artwork as PNG from Procreate.")
            }
            let candidates = ["composite.png", "QuickLook/Preview.png", "QuickLook/preview.png", "QuickLook/Thumbnail.png", "QuickLook/thumbnail.png"]
            guard let name = candidates.first(where: { archive.entries[$0] != nil }) else {
                throw FontLabArtworkError.message("This Procreate document has no readable flattened preview. In Procreate, use Actions → Share → PNG, then import that PNG for full-resolution tracing.")
            }
            image = try rasterImage(archive.read(name))
            notices.append("Procreate embedded \(name.lowercased().contains("thumbnail") ? "thumbnail" : "preview"): \(image.width) × \(image.height) px. This is flattened artwork, not the original layers. Export PNG from Procreate for full-resolution tracing.")
        default: image = try rasterImage(data)
        }
        if min(image.width, image.height) < 128 { notices.append("This image is small; a larger original will give smoother outlines.") }
        return FontLabArtworkSource(image: image, filename: url.lastPathComponent, format: request.format, notices: notices)
    }

    static func rasterImage(_ data: Data) throws -> CGImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 3200,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary), image.width > 1, image.height > 1 else {
            throw FontLabArtworkError.message("The artwork image could not be decoded. Try exporting a PNG or TIFF.")
        }
        return image
    }

    private final class SVGValidator: NSObject, XMLParserDelegate {
        var valid = true
        var count = 0
        var depth = 0
        private let allowed: Set<String> = ["svg", "g", "path", "rect", "circle", "ellipse", "line", "polyline", "polygon", "defs", "use", "clipPath", "title", "desc"]
        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
            count += 1; depth += 1
            if !allowed.contains(name) || count > 30_000 || depth > 128 { valid = false; parser.abortParsing(); return }
            for (key, value) in attributes {
                let lower = value.lowercased()
                if key.lowercased().hasPrefix("on") || (key.hasSuffix("href") && !value.hasPrefix("#")) ||
                    lower.contains("http:") && !key.hasPrefix("xmlns") || lower.contains("https:") && !key.hasPrefix("xmlns") ||
                    lower.contains("file:") || lower.contains("data:") || lower.contains("@import") ||
                    lower.contains("url(") && !(key == "clip-path" && lower.range(of: #"^url\(#[a-z0-9_-]+\)$"#, options: .regularExpression) != nil) {
                    valid = false; parser.abortParsing(); return
                }
            }
        }
        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) { depth -= 1 }
    }

    static func svgImage(_ data: Data) throws -> CGImage {
        guard data.count <= 10 * 1024 * 1024,
              let text = String(data: data, encoding: .utf8),
              !text.uppercased().contains("<!DOCTYPE"), !text.uppercased().contains("<!ENTITY") else {
            throw FontLabArtworkError.message("Use a plain, outlined SVG under 10 MB without external resources or document entities.")
        }
        let validator = SVGValidator(), parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false; parser.delegate = validator
        guard parser.parse(), validator.valid, let image = NSImage(data: data),
              image.size.width.isFinite, image.size.height.isFinite, image.size.width > 0, image.size.height > 0 else {
            throw FontLabArtworkError.message("This SVG uses unsupported content. Convert text to outlines, expand effects, and export a plain SVG with paths, shapes and strokes, or use PNG.")
        }
        let scale = 2400 / max(image.size.width, image.size.height)
        let width = max(2, Int(image.size.width * scale)), height = max(2, Int(image.size.height * scale))
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
            throw FontLabArtworkError.message("This SVG canvas could not be rendered.")
        }
        NSGraphicsContext.saveGraphicsState(); defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.clear.setFill(); NSRect(x: 0, y: 0, width: width, height: height).fill(using: .copy)
        image.draw(in: NSRect(x: 0, y: 0, width: width, height: height), from: .zero, operation: .sourceOver, fraction: 1)
        guard let result = bitmap.cgImage else { throw FontLabArtworkError.message("This SVG canvas could not be rendered.") }
        return result
    }
}

/// Minimal bounded ZIP reader for known Procreate preview members. ZIP64,
/// encrypted and unsupported compression entries fail explicitly.
struct FontLabArtworkZIP {
    struct Entry { let method: Int; let compressed: Int; let size: Int; let crc: UInt32; let offset: Int }
    let data: Data
    let entries: [String: Entry]
    init(data: Data) throws {
        self.data = data
        func fail() -> FontLabArtworkError { .message("The Procreate archive is damaged or uses an unsupported archive format. Export a PNG from Procreate.") }
        guard data.count >= 22 else { throw fail() }
        var end: Int?
        for i in stride(from: data.count - 22, through: max(0, data.count - 65_557), by: -1) {
            if data.u32(i) == 0x06054b50, i + 22 + data.u16(i + 20) == data.count { end = i; break }
        }
        guard let end, data.u16(end + 4) == 0, data.u16(end + 6) == 0,
              data.u16(end + 8) == data.u16(end + 10) else { throw fail() }
        let count = data.u16(end + 10), directory = Int(data.u32(end + 16)), directorySize = Int(data.u32(end + 12))
        guard count < 65_535, directory >= 0, directory + directorySize <= end else { throw fail() }
        var entries: [String: Entry] = [:], cursor = directory
        for _ in 0..<count {
            guard cursor + 46 <= end, data.u32(cursor) == 0x02014b50 else { throw fail() }
            let length = data.u16(cursor + 28), extra = data.u16(cursor + 30), comment = data.u16(cursor + 32)
            guard cursor + 46 + length + extra + comment <= end,
                  let name = String(data: data.subdata(in: (cursor + 46)..<(cursor + 46 + length)), encoding: .utf8),
                  entries[name] == nil, data.u16(cursor + 8) & 1 == 0 else { throw fail() }
            entries[name] = Entry(method: data.u16(cursor + 10), compressed: Int(data.u32(cursor + 20)),
                size: Int(data.u32(cursor + 24)), crc: data.u32(cursor + 16), offset: Int(data.u32(cursor + 42)))
            cursor += 46 + length + extra + comment
        }
        self.entries = entries
    }
    func read(_ name: String) throws -> Data {
        guard let entry = entries[name], entry.size > 0, entry.size <= 64 * 1024 * 1024,
              entry.compressed > 0, entry.offset + 30 <= data.count, data.u32(entry.offset) == 0x04034b50,
              [0, 8].contains(entry.method) else { throw FontLabArtworkError.message("The embedded Procreate preview is too large or unsupported. Export a PNG from Procreate.") }
        let start = entry.offset + 30 + data.u16(entry.offset + 26) + data.u16(entry.offset + 28)
        guard start + entry.compressed <= data.count else { throw FontLabArtworkError.message("The embedded preview is truncated.") }
        let compressed = data.subdata(in: start..<(start + entry.compressed))
        var output: Data
        if entry.method == 0 { output = compressed }
        else {
            output = Data(count: entry.size)
            var stream = z_stream()
            guard inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
                throw FontLabArtworkError.message("The embedded preview could not be decompressed.")
            }
            defer { inflateEnd(&stream) }
            let status = output.withUnsafeMutableBytes { target in
                compressed.withUnsafeBytes { source in
                    stream.next_in = UnsafeMutablePointer(mutating: source.bindMemory(to: UInt8.self).baseAddress!)
                    stream.avail_in = uInt(compressed.count)
                    stream.next_out = target.bindMemory(to: UInt8.self).baseAddress!
                    stream.avail_out = uInt(entry.size)
                    return inflate(&stream, Z_FINISH)
                }
            }
            guard status == Z_STREAM_END, stream.total_out == entry.size, stream.total_in == compressed.count else {
                throw FontLabArtworkError.message("The embedded preview is damaged.")
            }
        }
        let checksum = output.withUnsafeBytes { crc32(0, $0.bindMemory(to: UInt8.self).baseAddress, uInt(output.count)) }
        guard output.count == entry.size, UInt32(checksum) == entry.crc else { throw FontLabArtworkError.message("The embedded preview failed its integrity check.") }
        return output
    }
}

private extension Data {
    func u16(_ offset: Int) -> Int { Int(self[offset]) | Int(self[offset + 1]) << 8 }
    func u32(_ offset: Int) -> UInt32 { UInt32(u16(offset)) | UInt32(u16(offset + 2)) << 16 }
}

struct FontLabInkMask {
    let width: Int
    let height: Int
    var ink: [UInt8] // row zero is the top of the source image

    init(image: CGImage, options: FontLabArtworkOptions) {
        let width = image.width, height = image.height
        self.width = width; self.height = height
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        rgba.withUnsafeMutableBytes { bytes in
            let context = CGContext(data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        let cutoff = options.threshold * 255
        ink = stride(from: 0, to: rgba.count, by: 4).map { i in
            let alpha = Double(rgba[i + 3])
            // Premultiplied channels already contain alpha; composite onto a
            // background opposite to the selected ink without dark alpha halos.
            let light = 0.2126 * Double(rgba[i]) + 0.7152 * Double(rgba[i + 1]) + 0.0722 * Double(rgba[i + 2])
            return options.lightInk ? (light > cutoff && alpha > 8 ? 1 : 0) : (light + 255 - alpha < cutoff && alpha > 8 ? 1 : 0)
        }
    }
    init(width: Int, height: Int, ink: [UInt8]) { self.width = width; self.height = height; self.ink = ink }
    func clipped(_ rect: CGRect) -> CGRect { rect.integral.intersection(CGRect(x: 0, y: 0, width: width, height: height)) }
    func bounds(in region: CGRect) -> CGRect? {
        let r = clipped(region)
        guard !r.isNull, r.width > 0, r.height > 0 else { return nil }
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in Int(r.minY)..<Int(r.maxY) { for x in Int(r.minX)..<Int(r.maxX) where ink[y * width + x] != 0 {
            minX = min(minX, x); minY = min(minY, y); maxX = max(maxX, x); maxY = max(maxY, y)
        } }
        return maxX < minX ? nil : CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }
    func image() -> CGImage {
        let bytes = Data(ink.map { $0 == 0 ? UInt8(255) : UInt8(0) })
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0), provider: CGDataProvider(data: bytes as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }

    mutating func components(minimumArea: Int) throws -> [CGRect] {
        var seen = [UInt8](repeating: 0, count: ink.count), boxes: [CGRect] = []
        for start in ink.indices where ink[start] != 0 && seen[start] == 0 {
            var queue = [start], next = 0, minX = start % width, maxX = minX, minY = start / width, maxY = minY
            seen[start] = 1
            while next < queue.count {
                let p = queue[next]; next += 1
                let x = p % width, y = p / width
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
                for dy in -1...1 { for dx in -1...1 where dx != 0 || dy != 0 {
                    let nx = x + dx, ny = y + dy
                    guard nx >= 0, nx < width, ny >= 0, ny < height else { continue }
                    let n = ny * width + nx
                    if ink[n] != 0 && seen[n] == 0 { seen[n] = 1; queue.append(n) }
                } }
            }
            if queue.count < minimumArea { for p in queue { ink[p] = 0 }; continue }
            boxes.append(CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1))
            guard boxes.count <= 2_000 else { throw FontLabArtworkError.message("Too many marks were detected. Increase speck removal, adjust the threshold, or use a clean export without paper texture.") }
        }
        return boxes
    }
}

/// Component segmentation and tracing are independent of text recognition.
/// OCR suggests labels only; the user can supply order, edit labels, or draw boxes.
enum FontLabArtworkEngine {
    static func scan(_ source: FontLabArtworkSource, options: FontLabArtworkOptions, recognize: Bool = true) throws -> FontLabArtworkScan {
        guard (0.05...0.95).contains(options.threshold), (1...32).contains(options.rows), (1...32).contains(options.columns), (1...200).contains(options.minimumArea) else { throw FontLabArtworkError.message("The scan settings are invalid.") }
        var mask = FontLabInkMask(image: source.image, options: options)
        let components = try mask.components(minimumArea: options.minimumArea)
        guard !components.isEmpty else { throw FontLabArtworkError.message("No ink was found. Try the other ink color or adjust the threshold.") }
        var boxes: [CGRect]
        switch options.layout {
        case .single: boxes = [components.reduce(CGRect.null) { $0.union($1) }]
        case .grid:
            boxes = []
            for row in 0..<options.rows { for column in 0..<options.columns {
                let cell = CGRect(x: Double(column) * Double(mask.width) / Double(options.columns), y: Double(row) * Double(mask.height) / Double(options.rows),
                    width: Double(mask.width) / Double(options.columns), height: Double(mask.height) / Double(options.rows))
                if let bounds = mask.bounds(in: cell) { boxes.append(bounds) }
            } }
        case .automatic: boxes = readingOrder(groupDetachedMarks(components))
        }
        guard boxes.count <= 256 else { throw FontLabArtworkError.message("More than 256 letters were detected. Import a smaller sheet, use a grid, or remove background marks.") }
        var regions = boxes.compactMap { region(rect: $0, mask: mask) }
        var notices = source.notices
        if recognize {
            do { try suggestCharacters(in: &regions, mask: mask) }
            catch { notices.append("Automatic character recognition was unavailable. Enter the letter order or label the regions manually.") }
        }
        if regions.contains(where: { min($0.rect.width, $0.rect.height) < 12 }) { notices.append("Some letters have very little image detail. Inspect their outlines before importing.") }
        if regions.contains(where: { $0.rect.width > Double(mask.width) * 0.98 && $0.rect.height > Double(mask.height) * 0.98 }) {
            notices.append("Ink touches the image edges. If this is the background, switch ink color; if letters touch each other, use Grid sheet or draw separate regions.")
        }
        return FontLabArtworkScan(source: source, mask: mask, regions: regions, notices: notices)
    }

    static func groupDetachedMarks(_ boxes: [CGRect]) -> [CGRect] {
        guard let tallest = boxes.map(\.height).max(), tallest > 0 else { return [] }
        var bodies = boxes.filter { $0.height >= tallest * 0.30 }
        let small = boxes.filter { $0.height < tallest * 0.30 }.sorted { $0.height > $1.height }
        for dot in small {
            let candidates = bodies.indices.filter { i in
                let body = bodies[i]
                let overlap = max(0, min(body.maxX, dot.maxX) - max(body.minX, dot.minX))
                let gap = max(0, max(body.minY, dot.minY) - min(body.maxY, dot.maxY))
                return overlap >= min(body.width, dot.width) * 0.35 && gap < tallest * 0.55
            }
            if let closest = candidates.min(by: { abs(bodies[$0].midY - dot.midY) < abs(bodies[$1].midY - dot.midY) }) {
                bodies[closest] = bodies[closest].union(dot)
            } else { bodies.append(dot) }
        }
        return bodies
    }

    static func readingOrder(_ boxes: [CGRect]) -> [CGRect] {
        var rows: [[CGRect]] = []
        for box in boxes.sorted(by: { $0.midY < $1.midY }) {
            if let index = rows.indices.min(by: { abs(rows[$0][0].midY - box.midY) < abs(rows[$1][0].midY - box.midY) }),
               abs(rows[index][0].midY - box.midY) < max(rows[index][0].height, box.height) * 0.65 {
                rows[index].append(box)
            } else { rows.append([box]) }
        }
        return rows.flatMap { $0.sorted { $0.minX < $1.minX } }
    }

    static func region(rect: CGRect, mask: FontLabInkMask) -> FontLabArtworkRegion? {
        guard let bounds = mask.bounds(in: rect), bounds.width >= 1, bounds.height >= 1 else { return nil }
        let contours = trace(mask: mask, rect: bounds)
        guard !contours.isEmpty else { return nil }
        return FontLabArtworkRegion(rect: bounds, contours: contours)
    }

    /// Follow each exposed pixel edge with the ink on the right. At diagonal
    /// contacts, take the right turn to retain separate closed contours.
    /// Simplification works below one source pixel and preserves winding/holes.
    static func trace(mask: FontLabInkMask, rect: CGRect) -> [[FontLabPoint]] {
        let r = mask.clipped(rect), stride = mask.width + 1
        guard !r.isNull else { return [] }
        var edges: [Int: [Int]] = [:]
        func occupied(_ x: Int, _ y: Int) -> Bool {
            x >= Int(r.minX) && x < Int(r.maxX) && y >= Int(r.minY) && y < Int(r.maxY) && mask.ink[y * mask.width + x] != 0
        }
        func edge(_ x: Int, _ y: Int, _ nx: Int, _ ny: Int) { edges[y * stride + x, default: []].append(ny * stride + nx) }
        for y in Int(r.minY)..<Int(r.maxY) { for x in Int(r.minX)..<Int(r.maxX) where occupied(x, y) {
            if !occupied(x, y - 1) { edge(x, y, x + 1, y) }
            if !occupied(x + 1, y) { edge(x + 1, y, x + 1, y + 1) }
            if !occupied(x, y + 1) { edge(x + 1, y + 1, x, y + 1) }
            if !occupied(x - 1, y) { edge(x, y + 1, x, y) }
        } }
        var contours: [[FontLabPoint]] = []
        for start in edges.keys.sorted() {
            while edges[start]?.isEmpty == false {
                var current = start, previous = start - 1, points: [FontLabPoint] = []
                repeat {
                    let x = current % stride, y = current / stride
                    points.append(FontLabPoint(x: (Double(x) - r.minX) / r.width, y: 1 - (Double(y) - r.minY) / r.height))
                    guard let choices = edges[current], !choices.isEmpty else { break }
                    let dx = x - previous % stride, dy = y - previous / stride
                    let next = choices.max { a, b in
                        func score(_ p: Int) -> Int { let nx = p % stride - x, ny = p / stride - y; return (dx * ny - dy * nx) * 2 + dx * nx + dy * ny }
                        return score(a) < score(b)
                    }!
                    edges[current]!.removeAll { $0 == next }
                    previous = current; current = next
                } while current != start
                if current == start, points.count >= 3 {
                    let simplified = FontLabRemixEngine.simplified(points, tolerance: 0.55 / max(r.width, r.height))
                    if simplified.count >= 3 { contours.append(simplified) }
                }
            }
        }
        return contours
    }

    private static func suggestCharacters(in regions: inout [FontLabArtworkRegion], mask: FontLabInkMask) throws {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["en-US"]
        try VNImageRequestHandler(cgImage: mask.image(), options: [:]).perform([request])
        for observation in request.results ?? [] {
            guard let text = observation.topCandidates(1).first else { continue }
            for index in text.string.indices {
                let character = String(text.string[index])
                guard !character.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      let box = try text.boundingBox(for: index..<text.string.index(after: index))?.boundingBox else { continue }
                let pixels = CGRect(x: box.minX * Double(mask.width), y: (1 - box.maxY) * Double(mask.height),
                    width: box.width * Double(mask.width), height: box.height * Double(mask.height))
                let scores = regions.indices.map { i -> (Int, Double) in
                    let overlap = regions[i].rect.intersection(pixels)
                    return (i, overlap.isNull ? 0 : overlap.width * overlap.height / max(1, regions[i].rect.width * regions[i].rect.height))
                }
                if let best = scores.max(by: { $0.1 < $1.1 }), best.1 > 0.55, text.confidence > regions[best.0].confidence {
                    regions[best.0].character = character; regions[best.0].confidence = text.confidence
                }
            }
        }
    }

    static func project(from scan: FontLabArtworkScan, name: String, existing: FontLabProject? = nil, replace: Bool = false) throws -> FontLabProject {
        let selected = scan.regions.filter(\.included)
        let characters = selected.map { $0.character.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard !selected.isEmpty, characters.allSatisfy({ $0.count == 1 }), Set(characters).count == characters.count else {
            throw FontLabArtworkError.message("Assign one unique character to each included region. Uncheck unwanted marks or duplicate letters.")
        }
        var project = existing ?? FontLabProject(name: name.trimmingCharacters(in: .whitespacesAndNewlines))
        if existing == nil { project.metrics.baseline = 0.24; project.metrics.capHeight = 0.80; project.metrics.xHeight = 0.64 }
        let caps = selected.filter { $0.character.rangeOfCharacter(from: .uppercaseLetters) != nil }.map(\.rect.height)
        let shortLower = selected.filter { "acemnorsuvwxz".contains($0.character) }.map(\.rect.height)
        func median(_ values: [CGFloat]) -> CGFloat { let sorted = values.sorted(); return sorted[sorted.count / 2] }
        let capHeight = !caps.isEmpty ? median(caps) : (!shortLower.isEmpty ? median(shortLower) * 1.4 : selected.map(\.rect.height).max()!)
        var scale = (project.metrics.capHeight - project.metrics.baseline) / max(1, capHeight)
        // A whole sheet shares its scale; a single drawing fits the character's
        // intended vertical zone while retaining all disconnected components.
        if selected.count == 1 {
            let character = characters[0]
            let height = "acemnorsuvwxz".contains(character) ? project.metrics.xHeight - project.metrics.baseline :
                "gjpqy".contains(character) ? project.metrics.xHeight - project.metrics.baseline + project.metrics.baseline * 0.7 : project.metrics.capHeight - project.metrics.baseline
            scale = height / selected[0].rect.height
        }
        var baselines: [UUID: Double] = [:]
        for region in selected {
            let row = selected.filter { abs($0.rect.midY - region.rect.midY) < max($0.rect.height, region.rect.height) * 0.65 }
            let base = row.filter { !"gjpqy,;".contains($0.character) }.map(\.rect.maxY)
            baselines[region.id] = base.isEmpty ? region.rect.maxY - ("gjpqy".contains(region.character) ? region.rect.height * 0.25 : 0) : median(base)
        }
        // Bound the shared scale rather than clipping strokes at the canvas edge.
        for region in selected {
            let baseline = baselines[region.id]!
            scale = min(scale, (0.988 - project.metrics.baseline) / max(1, baseline - region.rect.minY),
                        (project.metrics.baseline - 0.012) / max(1, region.rect.maxY - baseline), 2.9 / max(1, region.rect.width))
        }
        var imported = 0
        for (region, character) in zip(selected, characters) {
            if !replace, project.glyphs[character]?.hasArtwork == true { continue }
            var glyph = FontLabGlyph(character: character)
            glyph.leftSideBearing = 0.045; glyph.rightSideBearing = 0.045
            glyph.contourDesignWidth = max(0.02, region.rect.width * scale)
            let baseline = baselines[region.id]!
            let contours = region.contours.map { $0.map { p in
                FontLabPoint(x: p.x, y: project.metrics.baseline + (baseline - region.rect.maxY + p.y * region.rect.height) * scale)
            } }
            glyph.strokes = [FontLabStroke(contours: contours)]
            glyph.importedFrom = scan.source.filename; glyph.importFormat = scan.source.format
            guard glyph.isValid else { throw FontLabArtworkError.message("A traced outline is too complex. Increase speck removal or import a simpler drawing.") }
            if !project.characters.contains(character) { project.characters.append(character) }
            project.glyphs[character] = glyph; imported += 1
        }
        guard imported > 0 else { throw FontLabArtworkError.message("All assigned letters already have artwork. Choose a new project or enable replacement.") }
        guard project.isValid else { throw FontLabArtworkError.message("Enter a project name from 1 to 200 characters and review the selected letters.") }
        return project
    }
}
