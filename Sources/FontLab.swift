import SwiftUI
import AppKit
import CoreText
import UniformTypeIdentifiers

struct FontLabPoint: Codable, Equatable {
    var x: Double
    var y: Double
    /// Optional native tablet data. Keeping these fields optional preserves
    /// decoding for Letterform Editor projects created before pressure support existed.
    var pressure: Double? = nil
    var tiltX: Double? = nil
    var tiltY: Double? = nil

    var isValid: Bool {
        x.isFinite && y.isFinite && (0...1).contains(x) && (0...1).contains(y) &&
            (pressure.map { $0.isFinite && (0...1).contains($0) } ?? true) &&
            (tiltX.map { $0.isFinite && (-1...1).contains($0) } ?? true) &&
            (tiltY.map { $0.isFinite && (-1...1).contains($0) } ?? true)
    }
}

enum FontLabNibStyle: String, Codable, CaseIterable, Identifiable {
    case round
    case marker
    case outline

    var id: String { rawValue }
    var title: String {
        switch self {
        case .round: return "Round"
        case .marker: return "Marker"
        case .outline: return "Outline"
        }
    }
    var systemImage: String {
        switch self {
        case .round: return "pencil.tip"
        case .marker: return "highlighter"
        case .outline: return "circle.dotted"
        }
    }
}

struct FontLabStroke: Codable, Identifiable, Equatable {
    var id = UUID()
    var points: [FontLabPoint] = []
    var width = 0.026
    /// Optional so projects saved before nib styles existed continue to decode.
    /// A missing value is rendered as the original round pen.
    var nibStyle: FontLabNibStyle? = nil
    /// A compound, non-zero-filled outline. Optional for old pen-only projects.
    /// Keeping counters with their outer shape preserves holes during editing.
    var contours: [[FontLabPoint]]? = nil
    var vectorPaths: [FontLabVectorPath]? = nil

    var resolvedNibStyle: FontLabNibStyle { nibStyle ?? .round }

    var isValid: Bool {
        if let vectorPaths {
            return contours == nil && points.isEmpty && !vectorPaths.isEmpty && vectorPaths.count <= 256 &&
                vectorPaths.reduce(0) { $0 + $1.nodes.count } <= 30_000 && vectorPaths.allSatisfy(\.isValid) &&
                Set(vectorPaths.map(\.id)).count == vectorPaths.count && width.isFinite && (0.002...0.2).contains(width)
        }
        return (contours.map { !$0.isEmpty && $0.count <= 256 && $0.reduce(0) { $0 + $1.count } <= 30_000 && $0.allSatisfy { $0.count >= 3 && $0.allSatisfy(\.isValid) } } ?? !points.isEmpty) &&
            points.count <= 50_000 && width.isFinite && (0.002...0.2).contains(width) && points.allSatisfy(\.isValid)
    }
}

enum FontLabDrawingTool: String, CaseIterable, Identifiable {
    case pen
    case eraser
    case reshape

    var id: String { rawValue }
    var title: String { self == .pen ? "Pen" : self == .eraser ? "Eraser" : "Reshape" }
    var systemImage: String { self == .pen ? "pencil.tip" : self == .eraser ? "eraser" : "point.topleft.down.to.point.bottomright.curvepath" }
}

enum FontLabSmoothingLevel: String, CaseIterable, Identifiable {
    case off
    case gentle
    case strong

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    /// How much of the newest sample to retain. Lower values produce a calmer,
    /// more heavily smoothed line while remaining deterministic.
    var response: Double {
        switch self {
        case .off: return 1
        case .gentle: return 0.72
        case .strong: return 0.46
        }
    }
}

enum FontLabDrawingOperations {
    static func smoothed(_ sample: FontLabPoint, after previous: FontLabPoint, level: FontLabSmoothingLevel) -> FontLabPoint {
        let response = level.response
        guard response < 1 else { return sample }
        return FontLabPoint(
            x: previous.x + (sample.x - previous.x) * response,
            y: previous.y + (sample.y - previous.y) * response,
            pressure: blended(previous.pressure, sample.pressure, response: response),
            tiltX: blended(previous.tiltX, sample.tiltX, response: response),
            tiltY: blended(previous.tiltY, sample.tiltY, response: response)
        )
    }

    static func erasing(_ strokes: [FontLabStroke], near point: FontLabPoint, radius: Double) -> [FontLabStroke] {
        let safeRadius = max(0.002, min(radius, 0.25))
        return strokes.filter { stroke in
            let hitRadius = safeRadius + stroke.width * 0.5
            return !strokeIntersects(stroke, point: point, squaredRadius: hitRadius * hitRadius)
        }
    }

    static func pressureScale(for point: FontLabPoint) -> Double {
        guard let pressure = point.pressure else { return 1 }
        return 0.34 + min(max(pressure, 0), 1) * 1.18
    }

    private static func blended(_ earlier: Double?, _ later: Double?, response: Double) -> Double? {
        guard let later else { return earlier }
        guard let earlier else { return later }
        return earlier + (later - earlier) * response
    }

    private static func strokeIntersects(_ stroke: FontLabStroke, point: FontLabPoint, squaredRadius: Double) -> Bool {
        if let paths = stroke.vectorPaths {
            let compound = CGMutablePath()
            for path in paths where path.closed { compound.addPath(path.cgPath) }
            return compound.contains(CGPoint(x: point.x * 1000, y: point.y * 1000))
        }
        if let contours = stroke.contours {
            let path = CGMutablePath()
            for contour in contours {
                path.addLines(between: contour.map { CGPoint(x: $0.x, y: $0.y) })
                path.closeSubpath()
            }
            return path.contains(CGPoint(x: point.x, y: point.y))
        }
        guard let first = stroke.points.first else { return false }
        if squaredDistance(first, point) <= squaredRadius { return true }
        for (start, end) in zip(stroke.points, stroke.points.dropFirst()) {
            if squaredDistance(from: point, toSegmentFrom: start, to: end) <= squaredRadius { return true }
        }
        return false
    }

    private static func squaredDistance(_ lhs: FontLabPoint, _ rhs: FontLabPoint) -> Double {
        let dx = lhs.x - rhs.x
        let dy = lhs.y - rhs.y
        return dx * dx + dy * dy
    }

    private static func squaredDistance(from point: FontLabPoint, toSegmentFrom start: FontLabPoint, to end: FontLabPoint) -> Double {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return squaredDistance(point, start) }
        let projection = min(max(((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared, 0), 1)
        let closest = FontLabPoint(x: start.x + projection * dx, y: start.y + projection * dy)
        return squaredDistance(point, closest)
    }
}

enum FontLabImportFormat: String, Codable, CaseIterable {
    case svg
    case png
    case jpeg
    case tiff
    case heic
    case procreate

    var displayName: String { self == .procreate ? "Procreate" : rawValue.uppercased() }
    var filenameExtensions: Set<String> {
        switch self {
        case .jpeg: return ["jpg", "jpeg"]
        case .tiff: return ["tif", "tiff"]
        case .heic: return ["heic", "heif"]
        default: return [rawValue]
        }
    }
}

/// A validated request for local artwork tracing. Source files are read-only.
struct FontLabImportRequest: Equatable {
    let sourceURL: URL
    let format: FontLabImportFormat
    let targetCharacter: String
}

struct FontLabImportedGlyph: Equatable {
    var strokes: [FontLabStroke]
    var sourceFilename: String
    var format: FontLabImportFormat
}

protocol FontLabGlyphImporting {
    func trace(_ request: FontLabImportRequest) throws -> FontLabImportedGlyph
}

enum FontLabImportAPI {
    enum RequestError: LocalizedError {
        case unsupportedFormat
        case invalidCharacter

        var errorDescription: String? {
            switch self {
            case .unsupportedFormat: return "Choose PNG, JPEG, TIFF, HEIC, SVG, or Procreate artwork."
            case .invalidCharacter: return "Choose one character before importing artwork."
            }
        }
    }

    static func request(sourceURL: URL, targetCharacter: String) throws -> FontLabImportRequest {
        guard targetCharacter.count == 1 else { throw RequestError.invalidCharacter }
        let fileExtension = sourceURL.pathExtension.lowercased()
        guard let format = FontLabImportFormat.allCases.first(where: { $0.filenameExtensions.contains(fileExtension) }) else {
            throw RequestError.unsupportedFormat
        }
        return FontLabImportRequest(sourceURL: sourceURL, format: format, targetCharacter: targetCharacter)
    }
}

enum FontLabSVGExporter {
    static func data(projectName: String, glyph: FontLabGlyph, metrics: FontLabMetrics) -> Data {
        Data(string(projectName: projectName, glyph: glyph, metrics: metrics).utf8)
    }

    static func string(projectName: String, glyph: FontLabGlyph, metrics: FontLabMetrics) -> String {
        let formatter = FontLabSVGNumberFormatter(fractionDigits: 3)
        let vectorFormatter = FontLabSVGNumberFormatter(fractionDigits: 4)
        func number(_ value: Double) -> String { formatter.string(value) }
        let xScale = glyph.contourDesignWidth ?? 1
        let penScale = min(xScale, 1)
        let elements = glyph.strokes.compactMap { stroke -> String? in
            if let paths = stroke.vectorPaths {
                let closed = paths.filter(\.closed).map { $0.svg(xScale: xScale, formatter: vectorFormatter) }.joined(separator: " ")
                var elements: [String] = []
                if !closed.isEmpty { elements.append("  <path d=\"\(closed)\" fill=\"#111111\" fill-rule=\"nonzero\"/>") }
                for path in paths where !path.closed { elements.append("  <path d=\"\(path.svg(xScale: xScale, formatter: vectorFormatter))\" fill=\"none\" stroke=\"#111111\" stroke-width=\"1\"/>") }
                return elements.joined(separator: "\n")
            }
            if let contours = stroke.contours {
                let d = contours.map { contour in
                    contour.enumerated().map { index, point in
                        "\(index == 0 ? "M" : "L")\(number(point.x * xScale * 1_000)),\(number((1 - point.y) * 1_000))"
                    }.joined(separator: " ") + " Z"
                }.joined(separator: " ")
                return "  <path d=\"\(d)\" fill=\"#111111\" fill-rule=\"nonzero\"/>"
            }
            guard let first = stroke.points.first else { return nil }
            let firstWidth = stroke.width * FontLabDrawingOperations.pressureScale(for: first) * penScale * 1_000
            if stroke.points.count == 1 {
                switch stroke.resolvedNibStyle {
                case .round:
                    return "  <circle cx=\"\(number(first.x * xScale * 1_000))\" cy=\"\(number((1 - first.y) * 1_000))\" r=\"\(number(firstWidth / 2))\" fill=\"#111111\"/>"
                case .marker:
                    let width = firstWidth * 1.28
                    return "  <rect x=\"\(number(first.x * xScale * 1_000 - width / 2))\" y=\"\(number((1 - first.y) * 1_000 - firstWidth * 0.32))\" width=\"\(number(width))\" height=\"\(number(firstWidth * 0.64))\" rx=\"\(number(firstWidth * 0.08))\" fill=\"#111111\"/>"
                case .outline:
                    return "  <circle cx=\"\(number(first.x * xScale * 1_000))\" cy=\"\(number((1 - first.y) * 1_000))\" r=\"\(number(firstWidth / 2))\" fill=\"none\" stroke=\"#111111\" stroke-width=\"\(number(max(2, firstWidth * 0.14)))\"/>"
                }
            }
            if stroke.resolvedNibStyle == .outline { return outlineElements(for: stroke, xScale: xScale, formatter: formatter) }
            let marker = stroke.resolvedNibStyle == .marker
            let widthScale = marker ? 1.28 : 1
            let cap = marker ? "square" : "round"
            let join = marker ? "bevel" : "round"
            if stroke.points.contains(where: { $0.pressure != nil }) {
                return zip(stroke.points, stroke.points.dropFirst()).map { start, end in
                    let scale = (FontLabDrawingOperations.pressureScale(for: start) + FontLabDrawingOperations.pressureScale(for: end)) / 2
                    let width = number(stroke.width * scale * widthScale * penScale * 1_000)
                    return "  <line x1=\"\(number(start.x * xScale * 1_000))\" y1=\"\(number((1 - start.y) * 1_000))\" x2=\"\(number(end.x * xScale * 1_000))\" y2=\"\(number((1 - end.y) * 1_000))\" stroke=\"#111111\" stroke-width=\"\(width)\" stroke-linecap=\"\(cap)\"/>"
                }.joined(separator: "\n")
            }
            let points = stroke.points.map { "\(number($0.x * xScale * 1_000)),\(number((1 - $0.y) * 1_000))" }.joined(separator: " ")
            return "  <polyline points=\"\(points)\" fill=\"none\" stroke=\"#111111\" stroke-width=\"\(number(stroke.width * widthScale * penScale * 1_000))\" stroke-linecap=\"\(cap)\" stroke-linejoin=\"\(join)\"/>"
        }.joined(separator: "\n")
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 \(number(glyph.contourDesignWidth == nil ? 1000 : glyph.resolvedDesignWidth * 1000)) 1000" role="img" aria-label="\(escaped(projectName)) glyph \(escaped(glyph.character))">
          <metadata>Typefield Letterform Editor; character=\(escaped(glyph.character)); baseline=\(number(metrics.baseline)); x-height=\(number(metrics.xHeight)); cap-height=\(number(metrics.capHeight)); left-side-bearing=\(number(glyph.leftSideBearing)); right-side-bearing=\(number(glyph.rightSideBearing))</metadata>
        \(elements)
        </svg>
        """
    }

    /// Turns a centerline into two independent edge paths. Unlike painting a
    /// white line over a black one, the space between these paths remains
    /// transparent when the SVG is placed over color.
    private static func outlineElements(for stroke: FontLabStroke, xScale: Double, formatter: FontLabSVGNumberFormatter) -> String {
        func number(_ value: Double) -> String { formatter.string(value) }
        let mapped = stroke.points.map { (x: $0.x * xScale * 1_000, y: (1 - $0.y) * 1_000, pressure: FontLabDrawingOperations.pressureScale(for: $0)) }
        guard mapped.count > 1 else { return "" }
        var leading: [(Double, Double)] = []
        var trailing: [(Double, Double)] = []
        for index in mapped.indices {
            let before = mapped[index == mapped.startIndex ? index : mapped.index(before: index)]
            let after = mapped[index == mapped.index(before: mapped.endIndex) ? index : mapped.index(after: index)]
            let dx = after.x - before.x
            let dy = after.y - before.y
            let length = max(0.001, hypot(dx, dy))
            let offset = stroke.width * min(xScale, 1) * 500 * mapped[index].pressure
            let ox = -dy / length * offset
            let oy = dx / length * offset
            leading.append((mapped[index].x + ox, mapped[index].y + oy))
            trailing.append((mapped[index].x - ox, mapped[index].y - oy))
        }
        let lineWidth = number(max(2, stroke.width * min(xScale, 1) * 140))
        return [leading, trailing].map { edge in
            let points = edge.map { "\(number($0.0)),\(number($0.1))" }.joined(separator: " ")
            return "  <polyline points=\"\(points)\" fill=\"none\" stroke=\"#111111\" stroke-width=\"\(lineWidth)\" stroke-linecap=\"round\" stroke-linejoin=\"round\"/>"
        }.joined(separator: "\n")
    }

    private static func escaped(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}

struct FontLabGlyph: Codable, Equatable {
    var character: String
    var strokes: [FontLabStroke] = []
    var leftSideBearing = 0.08
    var rightSideBearing = 0.08
    var importedFrom: String?
    var importFormat: FontLabImportFormat?
    /// Identifies an accepted starter proposal. Optional for older projects and
    /// excluded from font revision data because it does not affect the outline.
    var starterOrigin: String? = nil
    var contourDesignWidth: Double? = nil
    var components: [FontLabComponentUse]? = nil
    var resolvedDesignWidth: Double { contourDesignWidth ?? 0.62 }

    var hasArtwork: Bool { components?.isEmpty == false || strokes.contains { !$0.points.isEmpty || $0.contours?.isEmpty == false || $0.vectorPaths?.isEmpty == false } }
    var isValid: Bool {
        (components.map { $0.count <= 16 && $0.allSatisfy(\.isValid) && Set($0.map(\.id)).count == $0.count } ?? true) &&
        character.count == 1 && strokes.count <= 10_000 && strokes.allSatisfy(\.isValid) &&
            (contourDesignWidth.map { $0.isFinite && (0.02...3).contains($0) } ?? true) &&
            leftSideBearing.isFinite && rightSideBearing.isFinite &&
            (0...0.4).contains(leftSideBearing) && (0...0.4).contains(rightSideBearing) &&
            (starterOrigin.map { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.count <= 160 } ?? true) &&
            ((importedFrom == nil && importFormat == nil) || (importedFrom?.isEmpty == false && importFormat != nil))
    }
}

struct FontLabMetrics: Codable, Equatable {
    var baseline = 0.18
    var xHeight = 0.56
    var capHeight = 0.78

    var isValid: Bool {
        baseline.isFinite && xHeight.isFinite && capHeight.isFinite &&
            (0.04...0.42).contains(baseline) && xHeight >= baseline + 0.05 &&
            capHeight >= xHeight + 0.05 && capHeight <= 0.96
    }

    mutating func setBaseline(_ value: Double) {
        baseline = min(max(value, 0.04), min(0.42, xHeight - 0.05))
    }

    mutating func setXHeight(_ value: Double) {
        xHeight = min(max(value, baseline + 0.05), capHeight - 0.05)
    }

    mutating func setCapHeight(_ value: Double) {
        capHeight = min(max(value, xHeight + 0.05), 0.96)
    }
}

struct FontLabProject: Codable, Identifiable, Equatable {
    static let starterCharacters: [String] = {
        Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789.,!?&@#-'\":;()").map(String.init)
    }()

    var id = UUID()
    var name = "Untitled font"
    var characters = FontLabProject.starterCharacters
    var glyphs: [String: FontLabGlyph] = [:]
    var metrics = FontLabMetrics()
    var previewText = "Hamburgefontsiv 0123"
    /// Optional metadata keeps projects created before local remix support fully
    /// decodable while preserving source/licensing context for new derivatives.
    var remixProvenance: FontLabRemixProvenance? = nil
    var masters: [FontLabMaster]? = nil
    var activeMasterID: UUID? = nil
    var kerningGroups: [FontLabKerningGroup]? = nil
    var kerningPairs: [FontLabKerningPair]? = nil
    /// Canvas-only preview ink. Exported outlines remain monochrome.
    var previewInkHex: String? = nil

    init(id: UUID = UUID(), name: String = "Untitled font", characters: [String] = FontLabProject.starterCharacters) {
        self.id = id
        self.name = name
        self.characters = characters
        glyphs = Dictionary(uniqueKeysWithValues: characters.map { ($0, FontLabGlyph(character: $0)) })
    }

    var completedCount: Int { characters.filter { resolvedGlyph($0)?.hasArtwork == true }.count }
    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name.count <= 200 &&
            !characters.isEmpty && characters.count <= 2_000 && Set(characters).count == characters.count &&
            characters.allSatisfy { $0.count == 1 } && metrics.isValid && previewText.count <= 2_000 &&
            glyphs.count <= 2_000 && glyphs.allSatisfy { key, glyph in key == glyph.character && glyph.isValid } &&
            (remixProvenance?.isValid ?? true) && designIsValid &&
            (previewInkHex.map { $0.count == 6 && UInt64($0, radix: 16) != nil } ?? true)
    }
}

struct FontLabState: Codable, Equatable {
    var version = 1
    var projects: [FontLabProject] = []
    var selectedProject: UUID?
    var deletedProjects: [FontLabProject]? = nil

    var isValid: Bool {
        version == 1 && Set(projects.map(\.id)).count == projects.count && projects.allSatisfy(\.isValid) &&
            (deletedProjects.map { $0.allSatisfy(\.isValid) && Set($0.map(\.id)).count == $0.count && Set($0.map(\.id)).isDisjoint(with: projects.map(\.id)) } ?? true) &&
            (selectedProject == nil || projects.contains { $0.id == selectedProject })
    }
}

final class FontLabStore: ObservableObject {
    private struct SnapshotSave {
        let snapshot: FontLabState
        let destination: URL
        let revision: Int
    }

    @Published private(set) var state = FontLabState()
    @Published var error = ""
    @Published var status = ""
    @Published private(set) var savedAt: Date?

    let url: URL
    private(set) var readBlocked = false
    private var pendingSave: DispatchWorkItem?
    private var terminationObserver: NSObjectProtocol?
    private let persistenceQueue = DispatchQueue(label: "Typefield.FontLab.persistence", qos: .utility)
    /// Protects the revision read performed by the background persistence
    /// queue. UI mutations stay on the main thread, but queued save blocks
    /// need a synchronized way to tell whether their captured snapshot has
    /// already been superseded before doing the expensive JSON encode/write.
    private let persistenceRevisionLock = NSLock()
    private var latestPersistenceRevision = 0
    private var queuedSaveRevision = 0
    private var finishedSaveRevision = 0
    /// Main-thread-owned single-flight state. While one snapshot is being
    /// written, subsequent requests replace this deferred value rather than
    /// retaining and serializing an unbounded queue of obsolete projects.
    private var backgroundSaveInFlight = false
    private var deferredSnapshotSave: SnapshotSave?
    private var persistenceErrorMessage: String?
    var canRetrySave: Bool { !readBlocked && persistenceErrorMessage != nil }

    init(url: URL, recoveryError: String? = nil) {
        self.url = url
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in self?.flushPendingSave() }
        if let recoveryError {
            readBlocked = true
            error = recoveryError
            return
        }
        do {
            try TypefieldInputFile.requireRegularFileIfPresent(url)
            guard FileManager.default.fileExists(atPath: url.path) else { return }
            let loaded = try JSONDecoder().decode(FontLabState.self, from: Data(contentsOf: url))
            guard loaded.isValid else {
                throw NSError(domain: "Typefield.FontLab", code: 1, userInfo: [NSLocalizedDescriptionKey: "The file contains invalid or unsupported Letterform Editor data."])
            }
            state = loaded
        } catch {
            readBlocked = true
            self.error = "Letterform Editor could not be opened. The original file has been preserved and saving is disabled. " + error.localizedDescription
        }
    }

    deinit {
        if let terminationObserver { NotificationCenter.default.removeObserver(terminationObserver) }
    }

    func blockForBackupRecovery(_ message: String) {
        pendingSave?.cancel()
        pendingSave = nil
        readBlocked = true
        error = message
    }

    /// Drain any queued artwork write before staging the multi-file import.
    @discardableResult func prepareForBackupImport() -> Bool { save() }

    /// Called only after the journal has committed the matching saved file.
    func acceptSavedBackupImport(_ imported: FontLabState) {
        state = imported
        savedAt = Date()
        error = ""
    }

    var selectedProject: FontLabProject? {
        if let id = state.selectedProject { return state.projects.first { $0.id == id } }
        return state.projects.first
    }

    @discardableResult func addProject(name: String) -> UUID? {
        guard !readBlocked else { return nil }
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let project = FontLabProject(name: cleaned.isEmpty ? nextProjectName : cleaned)
        let previous = state
        state.projects.append(project)
        state.selectedProject = project.id
        guard save() else { state = previous; return nil }
        return project.id
    }

    /// Inserts a complete project produced by a local generator without routing
    /// it through backup import (which intentionally renames imported projects).
    /// Persistence is scheduled so encoding a large generated starter cannot
    /// stall the sheet-to-workspace transition; termination still flushes it.
    @discardableResult func addGeneratedProject(_ generated: FontLabProject) -> UUID? {
        guard !readBlocked, generated.isValid else {
            if !readBlocked { error = "The generated Letterform Editor project is invalid and was not saved." }
            return nil
        }
        var project = generated
        if state.projects.contains(where: { $0.id == project.id }) { project.id = UUID() }
        state.projects.append(project)
        state.selectedProject = project.id
        scheduleSave(after: 0.05)
        return project.id
    }

    /// Compare the whole snapshot before applying or undoing an import. A stale
    /// sheet/undo cannot overwrite edits made after that snapshot was captured.
    @discardableResult func replaceArtworkProject(_ expected: FontLabProject, with updated: FontLabProject) -> Bool {
        guard !readBlocked, expected.id == updated.id, updated.isValid,
              let index = state.projects.firstIndex(where: { $0.id == expected.id }), state.projects[index] == expected else { return false }
        state.projects[index] = updated
        scheduleSave(after: 0.05)
        return true
    }

    /// Deleted experiments remain recoverable across relaunches.
    @discardableResult func deleteProject(_ id: UUID) -> Bool {
        guard !readBlocked, let index = state.projects.firstIndex(where: { $0.id == id }) else { return false }
        let previous = state
        let removed = state.projects.remove(at: index)
        state.deletedProjects = (state.deletedProjects ?? []) + [removed]
        if state.selectedProject == id {
            state.selectedProject = state.projects.isEmpty ? nil : state.projects[min(index, state.projects.count - 1)].id
        }
        guard save() else { state = previous; return false }
        status = "Deleted “\(removed.name)”. Restore it from Deleted projects."
        return true
    }

    @discardableResult func restoreProject(_ id: UUID) -> Bool {
        guard !readBlocked, let index = state.deletedProjects?.firstIndex(where: { $0.id == id }) else { return false }
        let previous = state
        let project = state.deletedProjects!.remove(at: index)
        state.projects.append(project)
        state.selectedProject = project.id
        guard save() else { state = previous; return false }
        status = "Restored “\(project.name)”."
        return true
    }

    func selectProject(_ id: UUID) {
        guard state.projects.contains(where: { $0.id == id }) else { return }
        state.selectedProject = id
        scheduleSave(after: 0.4)
    }

    func updateProject(_ id: UUID, save shouldSave: Bool = true, _ edit: (inout FontLabProject) -> Void) {
        guard !readBlocked, let index = state.projects.firstIndex(where: { $0.id == id }) else { return }
        let previous = state
        var project = state.projects[index]
        edit(&project)
        guard project.isValid else {
            error = "Letterform Editor contains invalid project data and was not saved."
            return
        }
        state.projects[index] = project
        if shouldSave, !save() { state = previous }
    }

    func renameProject(_ id: UUID, to name: String) {
        let limited = String(name.prefix(200))
        let safeName = limited.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled font" : limited
        updateProject(id) { $0.name = safeName }
    }

    func setGlyph(_ glyph: FontLabGlyph, in projectID: UUID, save shouldSave: Bool) {
        updateProject(projectID, save: shouldSave) { project in
            if !project.characters.contains(glyph.character) { project.characters.append(glyph.character) }
            project.glyphs[glyph.character] = glyph
        }
    }

    @discardableResult func importProjects(_ projects: [FontLabProject]) -> Bool {
        guard !readBlocked else { return false }
        guard let imported = stateByImportingProjects(projects) else {
            error = "The backup contains invalid Letterform Editor project data."
            return false
        }
        guard !projects.isEmpty else { return true }
        let previous = state
        state = imported
        guard save() else {
            state = previous
            return false
        }
        return true
    }

    /// Produces independent backup copies without changing the live store.
    func stateByImportingProjects(_ projects: [FontLabProject]) -> FontLabState? {
        guard !readBlocked, projects.allSatisfy(\.isValid) else { return nil }
        var imported = state
        let suffix = " (imported)"
        let copies = projects.map { project -> FontLabProject in
            var copy = project
            copy.id = UUID()
            copy.name = String(project.name.prefix(max(1, 200 - suffix.count))) + suffix
            return copy
        }
        imported.projects.append(contentsOf: copies)
        if imported.selectedProject == nil { imported.selectedProject = copies.first?.id }
        return imported.isValid ? imported : nil
    }

    @discardableResult func save() -> Bool {
        pendingSave?.cancel()
        pendingSave = nil
        guard !readBlocked else { return false }
        guard state.isValid else {
            error = "Letterform Editor contains invalid project data and was not saved."
            return false
        }
        // The synchronous snapshot below includes all current state, so a
        // deferred older background request is no longer needed.
        deferredSnapshotSave = nil
        let snapshot = state
        queuedSaveRevision += 1
        let revision = queuedSaveRevision
        registerLatestPersistenceRevision(revision)
        let result: Result<Date, Error> = Result {
            try persistenceQueue.sync { try Self.persist(snapshot, to: url) }
        }
        finishedSaveRevision = max(finishedSaveRevision, revision)
        switch result {
        case let .success(timestamp):
            savedAt = timestamp
            if error == persistenceErrorMessage { error = "" }
            persistenceErrorMessage = nil
            return true
        case let .failure(saveError):
            let message = "Letterform Editor could not be saved. " + saveError.localizedDescription
            persistenceErrorMessage = message
            error = message
            return false
        }
    }

    private static func persist(_ snapshot: FontLabState, to url: URL) throws -> Date {
        let folder = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        // Generated starters contain many small editable strokes. Compact,
        // sorted JSON keeps saves deterministic while avoiding the I/O and
        // allocation cost of pretty-printing several megabytes of points.
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(snapshot)
        try LibraryBackupTools.preserve(url)
        if FileManager.default.fileExists(atPath: url.path) {
            let existing = try Data(contentsOf: url)
            try existing.write(to: url.appendingPathExtension("backup"), options: .atomic)
        }
        try data.write(to: url, options: .atomic)
        return Date()
    }

    private func enqueueSnapshotSave() {
        pendingSave = nil
        guard !readBlocked else { return }
        guard state.isValid else {
            error = "Letterform Editor contains invalid project data and was not saved."
            return
        }
        let snapshot = state
        let destination = url
        queuedSaveRevision += 1
        let revision = queuedSaveRevision
        registerLatestPersistenceRevision(revision)
        let request = SnapshotSave(snapshot: snapshot, destination: destination, revision: revision)
        if backgroundSaveInFlight {
            deferredSnapshotSave = request
            return
        }
        backgroundSaveInFlight = true
        beginBackgroundSave(request)
    }

    private func beginBackgroundSave(_ request: SnapshotSave) {
        let revision = request.revision
        persistenceQueue.async {
            let result: Result<Date, Error>?
            if self.isLatestPersistenceRevision(revision) {
                result = Result { try Self.persist(request.snapshot, to: request.destination) }
            } else {
                result = nil
            }
            DispatchQueue.main.async { [weak self] in
                self?.finishBackgroundSave(revision: revision, result: result)
            }
        }
    }

    private func finishBackgroundSave(revision: Int, result: Result<Date, Error>?) {
        finishedSaveRevision = max(finishedSaveRevision, revision)
        if revision == queuedSaveRevision, let result {
            switch result {
            case let .success(timestamp):
                savedAt = timestamp
                if error == persistenceErrorMessage { error = "" }
                persistenceErrorMessage = nil
            case let .failure(saveError):
                let message = "Letterform Editor could not be saved. " + saveError.localizedDescription
                persistenceErrorMessage = message
                error = message
            }
        }

        if let deferredSnapshotSave {
            self.deferredSnapshotSave = nil
            beginBackgroundSave(deferredSnapshotSave)
        } else {
            backgroundSaveInFlight = false
        }
    }

    private func registerLatestPersistenceRevision(_ revision: Int) {
        persistenceRevisionLock.lock()
        latestPersistenceRevision = max(latestPersistenceRevision, revision)
        persistenceRevisionLock.unlock()
    }

    private func isLatestPersistenceRevision(_ revision: Int) -> Bool {
        persistenceRevisionLock.lock()
        let isLatest = revision == latestPersistenceRevision
        persistenceRevisionLock.unlock()
        return isLatest
    }

    /// Coalesces rapid UI edits so sliders and text entry do not rewrite and
    /// back up the entire project file for every intermediate value.
    func scheduleSave(after delay: TimeInterval = 0.35) {
        guard !readBlocked else { return }
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.enqueueSnapshotSave() }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    func flushPendingSave() {
        // A failed background write has finished, but its artwork is still only
        // in memory. Navigation/termination must retry it, even after the error
        // banner has been dismissed or another operation changed its text.
        guard pendingSave != nil || finishedSaveRevision < queuedSaveRevision || persistenceErrorMessage != nil else { return }
        _ = save()
    }

    private var nextProjectName: String {
        var number = state.projects.count + 1
        while state.projects.contains(where: { $0.name == "Font experiment \(number)" }) { number += 1 }
        return "Font experiment \(number)"
    }

    enum SelfTestError: LocalizedError {
        case failed(String)
        var errorDescription: String? {
            if case let .failed(message) = self { return message }
            return nil
        }
    }

    /// Deterministic model, round-trip, atomic-save, and corrupt-file-preservation checks.
    /// The fixture is isolated in the temporary directory and never reads user fonts.
    static func selfTest() throws {
        try FontLabPersistenceChecks.run()
        try FontLabSketchReshape.selfTest()
        try FontLabEditorStateChecks.run()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Typefield-FontLabSelfTest-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
        try? FileManager.default.removeItem(at: root)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("font-lab.json")
        let store = FontLabStore(url: file)
        guard let id = store.addProject(name: "Test face") else { throw SelfTestError.failed("Could not create the test project.") }
        let stroke = FontLabStroke(id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!, points: [FontLabPoint(x: 0.1, y: 0.2), FontLabPoint(x: 0.8, y: 0.9)], width: 0.03)
        var glyph = FontLabGlyph(character: "A")
        glyph.strokes = [stroke]
        store.setGlyph(glyph, in: id, save: true)
        guard store.error.isEmpty else { throw SelfTestError.failed(store.error) }
        store.renameProject(id, to: "  \n ")
        guard store.selectedProject?.name == "Untitled font", store.error.isEmpty else {
            throw SelfTestError.failed("Whitespace-only project names must remain valid and saveable.")
        }
        let loaded = FontLabStore(url: file)
        guard loaded.selectedProject?.glyphs["A"] == glyph else { throw SelfTestError.failed("The saved glyph did not round-trip.") }
        guard loaded.selectedProject?.previewInkHex == nil else { throw SelfTestError.failed("Older projects should use the default preview ink.") }
        store.updateProject(id) { $0.addMaster(name: "Bold", weight: 700) }
        guard store.error.isEmpty,
              FontLabStore(url: file).selectedProject?.masters?.first(where: { $0.id == store.selectedProject?.activeMasterID })?.weight == 700 else {
            throw SelfTestError.failed("A 700 master weight did not persist through the Letterform save path.")
        }
        store.updateProject(id) { $0.previewInkHex = "3278AB" }
        guard FontLabStore(url: file).selectedProject?.previewInkHex == "3278AB" else { throw SelfTestError.failed("Preview ink did not persist.") }
        store.updateProject(id) { $0.previewInkHex = "invalid" }
        guard !store.error.isEmpty else { throw SelfTestError.failed("Invalid preview ink was accepted.") }
        store.updateProject(id) { $0.previewInkHex = "3278AB" }
        guard loaded.selectedProject?.completedCount == 1 else { throw SelfTestError.failed("Glyph completion was not restored.") }
        guard loaded.selectedProject?.name == "Untitled font" else { throw SelfTestError.failed("The safe project name did not round-trip.") }
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("Backups").path) else {
            throw SelfTestError.failed("Letterform Editor did not create an automatic state backup.")
        }

        // Failed writes must not leave a phantom project or an unsaved edit in
        // the observable in-memory state.
        let blockedParent = root.appendingPathComponent("blocked-parent")
        try Data("file blocks directory creation".utf8).write(to: blockedParent)
        let blockedStore = FontLabStore(url: blockedParent.appendingPathComponent("nested/font-lab.json"))
        guard blockedStore.addProject(name: "Must not appear") == nil,
              blockedStore.state.projects.isEmpty, blockedStore.state.selectedProject == nil,
              !blockedStore.error.isEmpty else {
            throw SelfTestError.failed("A failed Letterform project creation reported success or left a phantom project.")
        }

        let failedUpdateFile = root.appendingPathComponent("failed-update/font-lab.json")
        let failedUpdateStore = FontLabStore(url: failedUpdateFile)
        guard let failedUpdateID = failedUpdateStore.addProject(name: "Saved before failure") else {
            throw SelfTestError.failed("Could not create the failed-update fixture.")
        }
        let stateBeforeFailedUpdate = failedUpdateStore.state
        try FileManager.default.removeItem(at: failedUpdateFile)
        try FileManager.default.createDirectory(at: failedUpdateFile, withIntermediateDirectories: false)
        failedUpdateStore.updateProject(failedUpdateID) { $0.previewText = "This edit cannot be saved" }
        guard failedUpdateStore.state == stateBeforeFailedUpdate, !failedUpdateStore.error.isEmpty else {
            throw SelfTestError.failed("A failed Letterform project update remained in memory or hid its save error.")
        }

        let importFile = root.appendingPathComponent("imported-font-lab.json")
        let importStore = FontLabStore(url: importFile)
        guard importStore.importProjects(loaded.state.projects),
              importStore.state.projects.count == 1,
              importStore.state.projects[0].id != id,
              importStore.state.projects[0].name == "Untitled font (imported)",
              importStore.state.projects[0].glyphs["A"] == glyph else {
            throw SelfTestError.failed("Letterform Editor backup projects did not import as independent copies.")
        }

        // A synchronous flush must invalidate every older queued snapshot and
        // leave the newest UI state on disk. This exercises the same path used
        // when the app terminates while background saves are still pending.
        let revisionFile = root.appendingPathComponent("revisioned-font-lab.json")
        let revisionStore = FontLabStore(url: revisionFile)
        guard let revisionProjectID = revisionStore.addProject(name: "Revision test") else {
            throw SelfTestError.failed("Could not create the persistence revision fixture.")
        }
        for revision in 1...12 {
            revisionStore.updateProject(revisionProjectID, save: false) { $0.previewText = "Queued revision \(revision)" }
            revisionStore.enqueueSnapshotSave()
        }
        revisionStore.updateProject(revisionProjectID, save: false) { $0.previewText = "Termination flush" }
        revisionStore.scheduleSave(after: 60)
        revisionStore.flushPendingSave()
        let revisionReloaded = FontLabStore(url: revisionFile)
        guard revisionReloaded.selectedProject?.previewText == "Termination flush" else {
            throw SelfTestError.failed("A stale background snapshot overwrote the latest Letterform Editor state.")
        }
        let generatedFixture = FontLabProject(name: "Generated fixture", characters: ["A"])
        guard let generatedID = revisionStore.addGeneratedProject(generatedFixture) else {
            throw SelfTestError.failed("Could not add a generated project without blocking persistence.")
        }
        revisionStore.flushPendingSave()
        let generatedReloaded = FontLabStore(url: revisionFile)
        guard generatedReloaded.state.selectedProject == generatedID,
              generatedReloaded.selectedProject?.name == "Generated fixture" else {
            throw SelfTestError.failed("The generated project was not persisted by the termination flush path.")
        }

        // Delete exactly the requested project, persist a recoverable copy,
        // and invalidate pending saves so deleted projects cannot reappear.
        revisionStore.scheduleSave(after: 60)
        guard revisionStore.deleteProject(revisionProjectID), revisionStore.state.selectedProject == generatedID,
              revisionStore.state.projects.count == 1 else { throw SelfTestError.failed("Deleting an unselected Letterform Editor project changed the selection.") }
        guard revisionStore.deleteProject(generatedID), revisionStore.state.projects.isEmpty,
              revisionStore.state.selectedProject == nil else { throw SelfTestError.failed("Deleting the last Letterform Editor project left an invalid selection.") }
        revisionStore.flushPendingSave()
        let trashReloaded = FontLabStore(url: revisionFile)
        guard trashReloaded.state.projects.isEmpty, trashReloaded.state.deletedProjects?.count == 2,
              trashReloaded.restoreProject(revisionProjectID),
              trashReloaded.selectedProject?.previewText == "Termination flush",
              !trashReloaded.restoreProject(revisionProjectID),
              !trashReloaded.deleteProject(UUID()), trashReloaded.state.isValid else {
            throw SelfTestError.failed("Letterform Editor deletion recovery lost data or accepted duplicate restoration.")
        }
        let restored = FontLabStore(url: revisionFile)
        guard restored.selectedProject?.id == revisionProjectID, restored.state.deletedProjects?.count == 1 else {
            throw SelfTestError.failed("Restored Letterform Editor projects did not persist.")
        }

        let artworkFile = root.appendingPathComponent("artwork-import.json")
        let artworkStore = FontLabStore(url: artworkFile)
        _ = artworkStore.addProject(name: "Artwork transaction")
        let beforeArtwork = artworkStore.selectedProject!
        var afterArtwork = beforeArtwork
        afterArtwork.glyphs["A"] = glyph
        guard artworkStore.replaceArtworkProject(beforeArtwork, with: afterArtwork),
              !artworkStore.replaceArtworkProject(beforeArtwork, with: beforeArtwork),
              artworkStore.replaceArtworkProject(afterArtwork, with: beforeArtwork) else {
            throw SelfTestError.failed("Artwork import/undo accepted a stale snapshot or lost its original project.")
        }
        artworkStore.flushPendingSave()
        guard FontLabStore(url: artworkFile).selectedProject == beforeArtwork else {
            throw SelfTestError.failed("Artwork import Undo did not preserve the original project on disk.")
        }

        let corruptFile = root.appendingPathComponent("corrupt.json")
        let corruptData = Data("{ definitely-not-json".utf8)
        try corruptData.write(to: corruptFile, options: .atomic)
        let corruptStore = FontLabStore(url: corruptFile)
        guard corruptStore.readBlocked, !corruptStore.save(), !corruptStore.deleteProject(id), !corruptStore.restoreProject(id) else { throw SelfTestError.failed("A corrupt project was not write-blocked.") }
        guard try Data(contentsOf: corruptFile) == corruptData else { throw SelfTestError.failed("A corrupt project was overwritten.") }

        guard (try FontLabImportAPI.request(sourceURL: URL(fileURLWithPath: "/tmp/glyph.svg"), targetCharacter: "A")).format == .svg else {
            throw SelfTestError.failed("SVG import request validation failed.")
        }
        let legacyPoint = try JSONDecoder().decode(FontLabPoint.self, from: Data("{\"x\":0.2,\"y\":0.3}".utf8))
        guard legacyPoint.isValid, legacyPoint.pressure == nil, legacyPoint.tiltX == nil, legacyPoint.tiltY == nil else {
            throw SelfTestError.failed("Pre-pressure Letterform Editor points are no longer backward compatible.")
        }
        let legacyStrokeJSON = "{\"id\":\"AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE\",\"points\":[{\"x\":0.2,\"y\":0.3}],\"width\":0.03}"
        let legacyStroke = try JSONDecoder().decode(FontLabStroke.self, from: Data(legacyStrokeJSON.utf8))
        guard legacyStroke.isValid, legacyStroke.nibStyle == nil, legacyStroke.resolvedNibStyle == .round else {
            throw SelfTestError.failed("Pre-nib-style Letterform Editor strokes are no longer backward compatible.")
        }
        let tabletPoint = FontLabPoint(x: 0.8, y: 0.9, pressure: 0.75, tiltX: -0.2, tiltY: 0.4)
        let smoothed = FontLabDrawingOperations.smoothed(tabletPoint, after: FontLabPoint(x: 0.2, y: 0.3, pressure: 0.25), level: .gentle)
        guard smoothed.isValid, abs(smoothed.x - 0.632) < 0.000_001, abs((smoothed.pressure ?? 0) - 0.61) < 0.000_001 else {
            throw SelfTestError.failed("Deterministic stroke smoothing failed.")
        }
        let retained = FontLabStroke(points: [FontLabPoint(x: 0.75, y: 0.75), FontLabPoint(x: 0.9, y: 0.9)], width: 0.02)
        let erased = FontLabDrawingOperations.erasing([stroke, retained], near: FontLabPoint(x: 0.45, y: 0.55), radius: 0.04)
        guard erased == [retained] else { throw SelfTestError.failed("Whole-stroke erasing failed.") }
        guard FontLabDrawingOperations.pressureScale(for: FontLabPoint(x: 0, y: 0, pressure: 1)) >
                FontLabDrawingOperations.pressureScale(for: FontLabPoint(x: 0, y: 0, pressure: 0.1)) else {
            throw SelfTestError.failed("Tablet pressure did not affect stroke width.")
        }
        let svg = FontLabSVGExporter.string(projectName: "Test & face", glyph: glyph, metrics: FontLabMetrics())
        guard svg == FontLabSVGExporter.string(projectName: "Test & face", glyph: glyph, metrics: FontLabMetrics()), svg.contains("<polyline"), svg.contains("Test &amp; face") else {
            throw SelfTestError.failed("Deterministic SVG export failed.")
        }
        var pressureGlyph = FontLabGlyph(character: "P")
        pressureGlyph.strokes = [FontLabStroke(points: [FontLabPoint(x: 0.1, y: 0.2, pressure: 0.2), tabletPoint], width: 0.03)]
        guard FontLabSVGExporter.string(projectName: "Pressure", glyph: pressureGlyph, metrics: FontLabMetrics()).contains("<line") else {
            throw SelfTestError.failed("Pressure-aware SVG export failed.")
        }
        var markerGlyph = FontLabGlyph(character: "M")
        markerGlyph.strokes = [FontLabStroke(points: stroke.points, width: stroke.width, nibStyle: .marker)]
        guard FontLabSVGExporter.string(projectName: "Marker", glyph: markerGlyph, metrics: FontLabMetrics()).contains("stroke-linecap=\"square\"") else {
            throw SelfTestError.failed("Marker SVG export lost its flat nib geometry.")
        }
        var outlineGlyph = FontLabGlyph(character: "O")
        outlineGlyph.strokes = [FontLabStroke(points: stroke.points, width: stroke.width, nibStyle: .outline)]
        let outlineSVG = FontLabSVGExporter.string(projectName: "Outline", glyph: outlineGlyph, metrics: FontLabMetrics())
        guard outlineSVG.components(separatedBy: "<polyline").count == 3 else {
            throw SelfTestError.failed("Outline SVG export must produce two transparent rails.")
        }
    }
}

enum FontLabCharacterPanelLayout {
    static let minimumWidth = 184.0
    static let defaultWidth = 270.0
    static let maximumWidth = 420.0
    static let dividerWidth = 16.0

    static func limits(workspaceWidth: Double) -> ClosedRange<Double> {
        // Reserve the drawing tools/canvas and editor insets at narrow widths.
        let upper = min(maximumWidth, max(152, workspaceWidth - 530))
        return min(minimumWidth, upper)...upper
    }

    static func clamped(_ width: Double) -> Double {
        min(max(width, minimumWidth), maximumWidth)
    }
}

enum FontLabProofStripLayout {
    static let minimumHeight = 144.0
    static let defaultHeight = 166.0
    static let maximumHeight = 340.0
    static let emptyHeight = 88.0
    static let collapsedHeight = 52.0

    static func clamped(_ height: Double) -> Double {
        min(max(height, minimumHeight), maximumHeight)
    }
}

enum FontLabCharacterFilter: String, CaseIterable, Identifiable {
    case all = "All", drawn = "Drawn", empty = "Empty"
    var id: String { rawValue }

    func characters(in project: FontLabProject) -> [String] {
        project.characters.filter { character in
            switch self {
            case .all: return true
            case .drawn: return project.resolvedGlyph(character)?.hasArtwork == true
            case .empty: return project.resolvedGlyph(character)?.hasArtwork != true
            }
        }
    }
}

enum FontLabCharacterNavigation {
    static func match(_ query: String, in characters: [String]) -> String? {
        let character = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard character.count == 1 else { return nil }
        return characters.first(where: { $0 == character }) ??
            characters.first(where: { $0.caseInsensitiveCompare(character) == .orderedSame })
    }

    static func sequence(selectedCharacter: String, in project: FontLabProject, filter: FontLabCharacterFilter) -> [String] {
        let visible = Set(filter.characters(in: project))
        return project.characters.filter { visible.contains($0) || $0 == selectedCharacter }
    }
}

/// The AppKit Edit menu reads this session-only snapshot. FontLabView owns the
/// actual history and receives commands only while its workspace is visible.
final class FontLabEditMenuBridge {
    static let shared = FontLabEditMenuBridge()
    static let commandNotification = Notification.Name("TypefieldFontLabHistoryCommand")

    private(set) var projectID: UUID?
    private(set) var character: String?
    private(set) var canUndo = false
    private(set) var canRedo = false
    var undoTitle: String { character.map { "Undo \($0) edit" } ?? "Undo" }
    var redoTitle: String { character.map { "Redo \($0) edit" } ?? "Redo" }

    func update(projectID: UUID?, character: String?, canUndo: Bool, canRedo: Bool) {
        self.projectID = projectID
        self.character = character
        self.canUndo = projectID != nil && canUndo
        self.canRedo = projectID != nil && canRedo
    }

    func clear() { update(projectID: nil, character: nil, canUndo: false, canRedo: false) }
    func requestUndo() {
        guard canUndo else { return }
        NotificationCenter.default.post(name: Self.commandNotification, object: "undo")
    }
    func requestRedo() {
        guard canRedo else { return }
        NotificationCenter.default.post(name: Self.commandNotification, object: "redo")
    }
}

/// Window-independent interaction state; docking must not erase undo or selection.
final class FontLabEditorSession: ObservableObject {
    @Published var focusEditor = false
    @Published var showCharacters = true
    @Published var selectedCharacter = "A"
    @Published var strokeWidth = 0.026
    @Published var drawingTool = FontLabDrawingTool.pen
    @Published var nibStyle = FontLabNibStyle.round
    @Published var smoothing = FontLabSmoothingLevel.gentle
    @Published var usesTabletPressure = true
    @Published var tabletInputDetected = false
    @Published var selectingCharacters = false
    @Published var selectedCharacters: Set<String> = []
    @Published var characterFilter = FontLabCharacterFilter.all
    @Published var characterJump = ""
    @Published var characterJumpMessage = ""
    @Published var artworkUndo: (before: FontLabProject, after: FontLabProject)?
    @Published var editHistory = FontLabGlyphEditHistory()
    @Published var vectorEditing = true
    @Published var designUndo: (before: FontLabProject, after: FontLabProject)?
    @Published var glyphEditRevision = UUID()
    @Published var showMetrics = false
    private var openContourExportWarning: (projectID: UUID, message: String)?
    private var vectorKey = ""
    private var vectorEditor: FontLabVectorEditor?
    func vector(for key: String, glyph: FontLabGlyph, metrics: FontLabMetrics) -> FontLabVectorEditor {
        if vectorKey == key, let vectorEditor { return vectorEditor }
        let value = FontLabVectorEditor(glyph: glyph, metrics: metrics)
        vectorKey = key; vectorEditor = value
        return value
    }

    @discardableResult func startSketching(glyph: FontLabGlyph) -> Bool {
        guard glyph.components?.isEmpty != false else { return false }
        vectorEditing = false
        drawingTool = .pen
        nibStyle = .round
        usesTabletPressure = true
        return true
    }

    func warnAboutOpenContours(_ characters: [String], projectID: UUID) -> String {
        let shown = characters.prefix(12).joined(separator: ", ")
        let remainder = characters.count > 12 ? " and \(characters.count - 12) more" : ""
        let message = "Close or remove the open paths in \(shown)\(remainder) before exporting TrueType. Use Contours → Select open paths in the vector editor to review them. SVG can preserve unfinished paths."
        openContourExportWarning = (projectID, message)
        return message
    }

    /// Refresh only our preflight warning; never erase a persistence or read error.
    func refreshedOpenContourWarning(in state: FontLabState, currentError: String) -> String? {
        guard let warning = openContourExportWarning else { return nil }
        guard currentError == warning.message else { openContourExportWarning = nil; return nil }
        let selectedProjectID = state.selectedProject ?? state.projects.first?.id
        guard selectedProjectID == warning.projectID,
              let project = state.projects.first(where: { $0.id == warning.projectID }) else {
            openContourExportWarning = nil; return ""
        }
        let characters = FontLabTrueTypeExporter.exportScope(for: project).mappedOpenContourCharacters
        guard !characters.isEmpty else { openContourExportWarning = nil; return "" }
        return warnAboutOpenContours(characters, projectID: project.id)
    }
}

struct FontLabView: View {
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @ObservedObject private var library: Library
    @ObservedObject private var session: FontLabEditorSession
    @ObservedObject private var store: FontLabStore
    @Binding private var sidebarCollapsed: Bool
    private let editorToolbar: AnyView
    private var selectedCharacter: String { get { session.selectedCharacter } nonmutating set { session.selectedCharacter = newValue } }
    private var strokeWidth: Double { get { session.strokeWidth } nonmutating set { session.strokeWidth = newValue } }
    private var drawingTool: FontLabDrawingTool { get { session.drawingTool } nonmutating set { session.drawingTool = newValue } }
    private var nibStyle: FontLabNibStyle { get { session.nibStyle } nonmutating set { session.nibStyle = newValue } }
    private var smoothing: FontLabSmoothingLevel { get { session.smoothing } nonmutating set { session.smoothing = newValue } }
    private var usesTabletPressure: Bool { get { session.usesTabletPressure } nonmutating set { session.usesTabletPressure = newValue } }
    private var tabletInputDetected: Bool { get { session.tabletInputDetected } nonmutating set { session.tabletInputDetected = newValue } }
    private var selectingCharacters: Bool { get { session.selectingCharacters } nonmutating set { session.selectingCharacters = newValue } }
    private var selectedCharacters: Set<String> { get { session.selectedCharacters } nonmutating set { session.selectedCharacters = newValue } }
    private var characterFilter: FontLabCharacterFilter { get { session.characterFilter } nonmutating set { session.characterFilter = newValue } }
    private var characterJump: String { get { session.characterJump } nonmutating set { session.characterJump = newValue } }
    private var characterJumpMessage: String { get { session.characterJumpMessage } nonmutating set { session.characterJumpMessage = newValue } }
    @AppStorage("fontLabCharacterBrowserWidth") private var characterBrowserWidth = FontLabCharacterPanelLayout.defaultWidth
    @AppStorage("fontLabProofStripHeight") private var proofStripHeight = FontLabProofStripLayout.defaultHeight
    @AppStorage("fontLabProofStripExpanded") private var proofStripExpanded = true
    @State private var resizingCharacterWidth: Double?
    @State private var resizingProofHeight: Double?
    @State private var showInputHelp = false
    @State private var showBrushSettings = false
    @State private var showMetricsGuide = false
    @State private var showExamples = false
    @State private var showArtworkImporter = false
    private var artworkUndo: (before: FontLabProject, after: FontLabProject)? { get { session.artworkUndo } nonmutating set { session.artworkUndo = newValue } }
    @State private var isExportingFont = false
    @State private var clearRequest: ClearRequest?
    @State private var deleteRequest: FontLabProject?
    private var editHistory: FontLabGlyphEditHistory { get { session.editHistory } nonmutating set { session.editHistory = newValue } }
    private var glyphUndo: [FontLabGlyph] { editHistory.undoEntries[selectedCharacter] ?? [] }
    private var glyphRedo: [FontLabGlyph] { editHistory.redoEntries[selectedCharacter] ?? [] }
    private var vectorEditing: Bool { get { session.vectorEditing } nonmutating set { session.vectorEditing = newValue } }
    @State private var showFontDesign = false
    @State private var showSmoothing = false
    private var designUndo: (before: FontLabProject, after: FontLabProject)? { get { session.designUndo } nonmutating set { session.designUndo = newValue } }
    private var glyphEditRevision: UUID { get { session.glyphEditRevision } nonmutating set { session.glyphEditRevision = newValue } }
    @State private var exportRequest: ExportRequest?

    private struct ExportRequest {
        enum Kind { case glyphSVG, selectedSVGs, allSVGs, trueType, variableTrueType }
        let projectID: UUID
        let kind: Kind
        let characters: [String]
        let message: String
    }

    private struct ClearRequest: Identifiable {
        let id = UUID()
        let projectID: UUID
        let glyph: FontLabGlyph
    }

    init(library: Library, sidebarCollapsed: Binding<Bool>, session: FontLabEditorSession, editorToolbar: AnyView = AnyView(EmptyView())) {
        self.library = library
        self.session = session
        self.editorToolbar = editorToolbar
        _sidebarCollapsed = sidebarCollapsed
        _store = ObservedObject(wrappedValue: library.fontLab)
    }

    private var project: FontLabProject? { store.selectedProject }
    private var menuHistorySignature: String {
        "\(project?.id.uuidString ?? "")|\(selectedCharacter)|\(glyphUndo.count)|\(glyphRedo.count)|\(store.readBlocked)"
    }

    var body: some View {
        HStack(spacing: 0) {
            if !sidebarCollapsed && !session.focusEditor {
                WorkspaceSidebarShell { projectSidebar }
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
            VStack(spacing: 0) {
                if let project {
                    projectWorkspace(project)
                } else {
                    WorkspaceHeader(sidebarCollapsed: sidebarCollapsed) {
                        Text("Letterform Editor")
                    } actions: {
                        drawingDevicesButton
                        artworkImportButton
                        editorToolbar
                    }
                    emptyState
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background {
            FontLabShortcutBridge(
                characters: project.map { FontLabCharacterNavigation.sequence(selectedCharacter: selectedCharacter, in: $0, filter: characterFilter) } ?? [],
                selectedCharacter: selectedCharacter,
                canSketch: project?.glyphs[selectedCharacter]?.components?.isEmpty != false,
                onSelectCharacter: { selectedCharacter = $0 },
                onSelectMode: { vectorEditing = $0 },
                onVectorCommand: { performVectorWorkspaceCommand($0) }
            )
            .frame(width: 1, height: 1)
            .allowsHitTesting(false)
        }
        .onAppear {
            characterBrowserWidth = FontLabCharacterPanelLayout.clamped(characterBrowserWidth)
            proofStripHeight = FontLabProofStripLayout.clamped(proofStripHeight)
            if let project = store.selectedProject, !project.characters.contains(selectedCharacter) {
                selectedCharacter = project.characters.first ?? "A"
            }
            syncMenuHistory()
        }
        .onChange(of: store.state.selectedProject) { _ in
            editHistory = FontLabGlyphEditHistory()
            if let project = store.selectedProject, !project.characters.contains(selectedCharacter) {
                selectedCharacter = project.characters.first ?? "A"
            }
            if let project = store.selectedProject {
                selectedCharacters.formIntersection(project.characters)
            } else {
                selectedCharacters.removeAll()
            }
            characterFilter = .all
            characterJumpMessage = ""
            syncMenuHistory()
        }
        .onChange(of: menuHistorySignature) { _ in syncMenuHistory() }
        .onReceive(store.$state) { snapshot in
            if let message = session.refreshedOpenContourWarning(in: snapshot, currentError: store.error), message != store.error {
                store.error = message
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: FontLabEditMenuBridge.commandNotification)) { event in
            guard let project, FontLabEditMenuBridge.shared.projectID == project.id,
                  FontLabEditMenuBridge.shared.character == selectedCharacter else { return }
            let glyph = project.glyphs[selectedCharacter] ?? FontLabGlyph(character: selectedCharacter)
            switch event.object as? String {
            case "undo": undoStroke(glyph, projectID: project.id)
            case "redo": redoGlyph(projectID: project.id)
            default: break
            }
        }
        .alert("Review export", isPresented: Binding(get: { exportRequest != nil }, set: { if !$0 { exportRequest = nil } }), presenting: exportRequest) { request in
            Button("Continue to save…") { performExport(request) }
            Button("Cancel", role: .cancel) { exportRequest = nil }
        } message: { request in
            Text(request.message)
        }
        .alert("Clear glyph artwork?", isPresented: Binding(get: { clearRequest != nil }, set: { if !$0 { clearRequest = nil } })) {
            Button("Clear", role: .destructive) {
                if let request = clearRequest { clearGlyph(request.glyph, projectID: request.projectID) }
                clearRequest = nil
            }
            Button("Cancel", role: .cancel) { clearRequest = nil }
        } message: {
            Text("This removes every stroke from \(clearRequest?.glyph.character ?? "this glyph"). The current project file is backed up before the change.")
        }
        .alert("Delete Letterform Editor project?", isPresented: Binding(get: { deleteRequest != nil }, set: { if !$0 { deleteRequest = nil } })) {
            Button("Delete project", role: .destructive) {
                if let request = deleteRequest { _ = store.deleteProject(request.id) }
                deleteRequest = nil
            }
            Button("Cancel", role: .cancel) { deleteRequest = nil }
        } message: {
            Text("“\(deleteRequest?.name ?? "This project")” will move to Deleted projects, where you can restore it. Source fonts and exported font files stay in place.")
        }
        .typefieldSheet(isPresented: $showInputHelp) {
            let glyph = store.selectedProject?.glyphs[selectedCharacter] ?? FontLabGlyph(character: selectedCharacter)
            FontLabDrawingDeviceGuide(canStartSketch: !store.readBlocked && glyph.components?.isEmpty != false,
                                      inputDetected: tabletInputDetected) {
                guard !store.readBlocked else { return }
                if store.selectedProject == nil {
                    guard store.addProject(name: "Untitled font") != nil else { return }
                }
                _ = session.startSketching(glyph: glyph)
            }
        }
        .typefieldSheet(isPresented: $showMetricsGuide) {
            let currentProject = store.selectedProject
            let currentGlyph = currentProject?.glyphs[selectedCharacter] ?? FontLabGlyph(character: selectedCharacter)
            FontLabMetricsGuideSheet(metrics: currentProject?.metrics ?? FontLabMetrics(), glyph: currentGlyph)
        }
        .typefieldSheet(isPresented: $showArtworkImporter) {
            FontLabArtworkImportSheet(currentProject: store.selectedProject, selectedCharacter: selectedCharacter) { result, original in
                if let original {
                    guard store.replaceArtworkProject(original, with: result) else { return false }
                    artworkUndo = (before: original, after: result)
                } else {
                    guard store.addGeneratedProject(result) != nil else { return false }
                    artworkUndo = nil
                }
                editHistory = FontLabGlyphEditHistory(); selectedCharacters.removeAll(); selectingCharacters = false
                selectedCharacter = result.characters.first(where: { result.glyphs[$0]?.hasArtwork == true }) ?? "A"
                let changed = result.characters.filter { result.glyphs[$0]?.hasArtwork == true && result.glyphs[$0] != original?.glyphs[$0] }.count
                store.error = ""
                store.status = "Imported \(changed) traced \(changed == 1 ? "glyph" : "glyphs") into \(result.name). Review the editable outlines in Vector; the source file was not changed."
                return true
            }
        }
        .typefieldSheet(isPresented: $showFontDesign) {
            if let original = store.selectedProject {
                FontLabDesignView(project: original, character: selectedCharacter) { updated, openCharacter in
                    guard store.replaceArtworkProject(original, with: updated) else { return false }
                    designUndo = (original, updated); editHistory = FontLabGlyphEditHistory(); vectorEditing = true
                    if let openCharacter { selectedCharacter = openCharacter }
                    glyphEditRevision = UUID()
                    store.error = ""
                    store.status = "Updated project setup for \(updated.name). Project history can restore the previous snapshot."
                    return true
                }
            }
        }
        .typefieldSheet(isPresented: $showSmoothing) {
            if let current = store.selectedProject, let glyph = current.glyphs[selectedCharacter] {
                FontLabSmoothingView(original: glyph, metrics: current.metrics) { edited in
                    guard recordGlyphEdit(edited, projectID: current.id) else { return false }
                    vectorEditing = true
                    let editor = session.vector(for: vectorSessionKey(current), glyph: edited, metrics: current.metrics)
                    editor.receive(edited)
                    editor.tool = .select; editor.objectSelection = false
                    editor.selection = []; editor.activePath = nil
                    editor.message = "Outline simplified. Drag an anchor to move it, or drag an edge to bend the letter."
                    return true
                }
            }
        }
        .typefieldSheet(isPresented: $showExamples) {
            FontLabExamplesView { project in
                if store.addGeneratedProject(project) != nil {
                    selectedCharacter = project.characters.first(where: { project.glyphs[$0]?.hasArtwork == true }) ?? "A"
                    vectorEditing = true
                }
            }
        }
        .onDisappear {
            FontLabEditMenuBridge.shared.clear()
            store.flushPendingSave()
        }
        .accessibilityIdentifier("font-lab-workspace")
    }

    private var projectSidebar: some View {
        VStack(alignment: .leading, spacing: 6) {
            WorkspaceSidebarHeader(library: library, collapsed: $sidebarCollapsed)
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Letterform projects").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text("Draw and test letterforms").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { _ = store.addProject(name: "") } label: { Image(systemName: "plus") }
                        .buttonStyle(.plain).help("New Letterform Editor project").disabled(store.readBlocked)
                }
                Button("Try handwriting & bubble examples…") { showExamples = true }
                    .font(.caption).disabled(store.readBlocked)
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(store.state.projects) { project in
                            Button { store.selectProject(project.id) } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: project.completedCount == 0 ? "scribble" : "pencil.and.outline")
                                        .foregroundStyle(project.id == store.selectedProject?.id ? ShelfPalette.ink : .secondary)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(project.name).lineLimit(1)
                                        Text("\(project.completedCount) of \(project.characters.count) drawn").font(.caption2).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal, 8).padding(.vertical, 9)
                                .background(project.id == store.selectedProject?.id ? Color.primary.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 9))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Delete project…", role: .destructive) { deleteRequest = project }.disabled(store.readBlocked)
                            }
                        }
                    }
                }
                if let deleted = store.state.deletedProjects, !deleted.isEmpty {
                    Menu {
                        ForEach(deleted.reversed()) { project in
                            Button("Restore “\(project.name)”") { _ = store.restoreProject(project.id) }
                        }
                    } label: { Label("Deleted projects (\(deleted.count))", systemImage: "trash") }
                        .disabled(store.readBlocked)
                }
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Experiments stay separate from your font files.").font(.caption).foregroundStyle(.secondary)
                    Text("\(library.families.count) library families remain untouched.").font(.caption2).foregroundStyle(.tertiary)
                }
                .padding(.bottom, 12)
            }
            .padding(.horizontal, 12)
        }
    }

    private var drawingDevicesButton: some View {
        Button { showInputHelp = true } label: {
            WorkspaceHeaderActionLabel("iPad & tablet", systemImage: "ipad")
        }
        .buttonStyle(.plain).help("Draw with Apple Pencil through Sidecar or a connected pen tablet")
        .accessibilityIdentifier("font-lab-drawing-devices")
    }

    private var artworkImportButton: some View {
        Button { showArtworkImporter = true } label: {
            WorkspaceHeaderActionLabel("Import", systemImage: "square.and.arrow.down")
        }
        .buttonStyle(.plain).disabled(store.readBlocked)
        .help("Import a letter, alphabet sheet, SVG or Procreate artwork")
        .accessibilityIdentifier("font-lab-import")
    }

    private func projectWorkspace(_ project: FontLabProject) -> some View {
        let selectedDrawnCharacters = project.characters.filter { selectedCharacters.contains($0) && project.resolvedGlyph($0)?.hasArtwork == true }
        let allDrawnCharacters = project.characters.filter { project.resolvedGlyph($0)?.hasArtwork == true }
        let trueTypeScope = FontLabTrueTypeExporter.exportScope(for: project)
        return VStack(spacing: 0) {
            WorkspaceHeader(sidebarCollapsed: sidebarCollapsed && !session.focusEditor) {
                HStack(spacing: 12) {
                    TextField("Project name", text: projectNameBinding(project.id))
                        .font(.system(size: WorkspaceHeaderLayout.titleSize, weight: .semibold)).textFieldStyle(.plain)
                        .frame(minWidth: 150, idealWidth: 230, maxWidth: 360, minHeight: WorkspaceHeaderLayout.titleHeight)
                        .onSubmit { store.flushPendingSave() }
                        .disabled(store.readBlocked)
                        .layoutPriority(1)
                    Text("\(project.completedCount)/\(project.characters.count) glyphs")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: true, vertical: false)
                }
            } actions: {
                    Menu {
                    Button("Components & masters…", systemImage: "square.stack.3d.up") { showFontDesign = true }
                        .help("Components, masters, kerning groups and glyph set")
                        .disabled(store.readBlocked || isExportingFont)
                    Divider()
                        if let undo = designUndo, undo.after == project {
                            Button("Undo project setup") {
                                if store.replaceArtworkProject(undo.after, with: undo.before) {
                                    designUndo = nil; editHistory = FontLabGlyphEditHistory(); glyphEditRevision = UUID()
                                    if !undo.before.characters.contains(selectedCharacter) { selectedCharacter = undo.before.characters.first ?? "A" }
                                    store.status = "Restored the project before setup. Per-glyph edit history was cleared."
                                }
                            }
                        }
                        if let undo = artworkUndo, undo.after == project {
                            Button("Undo project import") {
                                if store.replaceArtworkProject(undo.after, with: undo.before) {
                                    artworkUndo = nil; editHistory = FontLabGlyphEditHistory(); glyphEditRevision = UUID()
                                    if !undo.before.characters.contains(selectedCharacter) { selectedCharacter = undo.before.characters.first ?? "A" }
                                    store.status = "Restored the project before import. Per-glyph edit history was cleared."
                                }
                            }
                        }
                        if designUndo?.after == project || artworkUndo?.after == project { Divider() }
                        Button("Delete project…", role: .destructive) { deleteRequest = project }
                            .disabled(store.readBlocked || isExportingFont)
                    } label: { WorkspaceHeaderActionLabel("Project", systemImage: "folder", showsMenuIndicator: true) }
                        .workspaceHeaderMenu()
                        .help("Font setup and project history")
                    drawingDevicesButton
                    artworkImportButton
                    Menu {
                        Button("Export \(selectedCharacter) as SVG…") { prepareExport(.glyphSVG, characters: [selectedCharacter], project: project) }
                            .disabled(project.resolvedGlyph(selectedCharacter)?.hasArtwork != true)
                        Divider()
                        Button("Export selected as SVGs…") { prepareExport(.selectedSVGs, characters: selectedDrawnCharacters, project: project) }
                            .disabled(selectedDrawnCharacters.isEmpty)
                        Button("Export all drawn glyphs as SVGs…") { prepareExport(.allSVGs, characters: allDrawnCharacters, project: project) }
                            .disabled(allDrawnCharacters.isEmpty)
                        Divider()
                        Button("Export installable TrueType (.ttf)…") { prepareExport(.trueType, characters: trueTypeScope.mappedArtworkCharacters, project: project) }
                            .disabled(trueTypeScope.mappedArtworkCharacters.isEmpty || isExportingFont)
                            .help(trueTypeScope.mappedArtworkCharacters.isEmpty ? "Draw a supported, single-scalar character before exporting a TrueType font." : "Export the outlined characters that TrueType can map.")
                        Button("Export variable TrueType (.ttf)…") { prepareExport(.variableTrueType, characters: trueTypeScope.mappedArtworkCharacters, project: project) }
                            .disabled((project.masters?.count ?? 0) < 2 || isExportingFont)
                            .help("Interpolate two compatible masters on a weight axis. Incompatible glyphs are rejected with a reason.")
                    } label: { WorkspaceHeaderActionLabel("Export", systemImage: "square.and.arrow.up", showsMenuIndicator: true) }
                        .workspaceHeaderMenu().disabled(store.readBlocked)
                    editorToolbar
            }
            if !store.error.isEmpty {
                HStack(alignment: .top) {
                    Text(store.error).font(.caption).foregroundStyle(.orange).textSelection(.enabled)
                    if store.canRetrySave {
                        Button("Retry save") { _ = store.save() }.controlSize(.small)
                    }
                }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20).padding(.bottom, 10)
                    .padding(.leading, sidebarCollapsed ? WorkspaceSidebarLayout.revealWidth + 8 : 0)
            } else if !store.status.isEmpty {
                Text(store.status).font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20).padding(.bottom, 10)
                    .padding(.leading, sidebarCollapsed ? WorkspaceSidebarLayout.revealWidth + 8 : 0)
            }
            if !session.focusEditor {
            if isExportingFont {
                ProgressView("Building font…").controlSize(.small).padding(.horizontal, 20).padding(.bottom, 8)
            }
            if let provenance = project.remixProvenance {
                Text(provenance.summary + ". Review both source font licenses before distributing the result.")
                    .help((provenance.preservedCharacters ?? []).isEmpty ? provenance.summary : "Source structure preserved for: " + provenance.preservedCharacters!.joined(separator: " "))
                    .font(.caption2).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20).padding(.bottom, 9)
                    .padding(.leading, sidebarCollapsed ? WorkspaceSidebarLayout.revealWidth + 8 : 0)
            }
            if let master = project.masters?.first(where: { $0.id == project.activeMasterID }) {
                Text("Active master: " + master.name).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20).padding(.bottom, 8)
            }
            }
            Divider()
            GeometryReader { proxy in
                let hasProofText = !project.previewText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                let proofHeight = session.focusEditor ? 0 : proofStripExpanded ? (hasProofText ? FontLabProofStripLayout.clamped(resizingProofHeight ?? proofStripHeight) : FontLabProofStripLayout.emptyHeight) : FontLabProofStripLayout.collapsedHeight
                // Keep a bounded viewport at every width. An unbounded horizontal
                // proposal makes a panel drag grow its containing scroll view.
                let compactEditor = session.focusEditor || proxy.size.width < 1_200
                let browserLimits = FontLabCharacterPanelLayout.limits(workspaceWidth: proxy.size.width)
                let displayedBrowserWidth = min(max(resizingCharacterWidth ?? characterBrowserWidth, browserLimits.lowerBound), browserLimits.upperBound)
                let metricsWidth = proxy.size.width - ((!session.focusEditor || session.showCharacters) ? displayedBrowserWidth + 16 : 0) - 60
                VStack(spacing: 0) {
                    if !session.focusEditor {
                    preview(project).frame(height: proofHeight)
                    if proofStripExpanded && hasProofText {
                        FontLabPanelResizeHandle(axis: .vertical, value: proofHeight,
                            limits: FontLabProofStripLayout.minimumHeight...FontLabProofStripLayout.maximumHeight,
                            defaultValue: FontLabProofStripLayout.defaultHeight, label: "Proof strip height", identifier: "font-lab-proof-divider",
                            onPreview: { resizingProofHeight = $0 },
                            onCommit: { proofStripHeight = $0; resizingProofHeight = nil },
                            onCancel: { resizingProofHeight = nil })
                            .frame(height: 12)
                    }
                    Divider()
                    }
                    ScrollView(.vertical) {
                        HStack(spacing: 0) {
                            if !session.focusEditor || session.showCharacters {
                            characterBrowser(project)
                                .frame(width: displayedBrowserWidth)
                            FontLabPanelResizeHandle(axis: .horizontal, value: displayedBrowserWidth,
                                limits: browserLimits, defaultValue: FontLabCharacterPanelLayout.defaultWidth,
                                label: "Character list width", identifier: "font-lab-character-divider",
                                onPreview: { resizingCharacterWidth = $0 },
                                onCommit: { characterBrowserWidth = FontLabCharacterPanelLayout.clamped($0); resizingCharacterWidth = nil },
                                onCancel: { resizingCharacterWidth = nil })
                                .frame(width: FontLabCharacterPanelLayout.dividerWidth)
                            }
                            glyphEditor(project, compact: compactEditor, metricsColumns: metricsWidth >= 640 ? 3 : 1)
                        }
                        .frame(width: max(0, proxy.size.width - 16), alignment: .topLeading)
                        .frame(minHeight: max(compactEditor ? 440 : 520, proxy.size.height - proofHeight - (proofStripExpanded && hasProofText ? 13 : 1)), alignment: .topLeading)
                    }
                }
            }
        }
    }

    private func characterBrowser(_ project: FontLabProject) -> some View {
        let visibleCharacters = characterFilter.characters(in: project)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Characters").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Button(selectingCharacters ? "Done" : selectedCharacters.isEmpty ? "Select" : "Selected \(selectedCharacters.count)") {
                    selectingCharacters.toggle()
                }
                .buttonStyle(.plain).font(.caption).foregroundStyle(ShelfPalette.ink)
                .help(selectingCharacters ? "Finish selecting glyphs" : "Select several glyphs for SVG export")
            }
            HStack(spacing: 6) {
                Picker("Filter", selection: $session.characterFilter) {
                    ForEach(FontLabCharacterFilter.allCases) { filter in Text(localizedKey(filter.rawValue)).tag(filter) }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Show characters")
                .accessibilityIdentifier("font-lab-character-filter")
                Text("\(visibleCharacters.count)")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    .accessibilityLabel("\(visibleCharacters.count) characters shown")
            }
            if !visibleCharacters.contains(selectedCharacter) {
                Text("Editing \(selectedCharacter); hidden by \(characterFilter.rawValue.lowercased()) filter.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            TextField("Jump to character", text: $session.characterJump)
                .textFieldStyle(.roundedBorder)
                .onSubmit { jumpToCharacter(in: project) }
                .onChange(of: characterJump) { _ in characterJumpMessage = "" }
                .accessibilityIdentifier("font-lab-character-jump")
            if !characterJumpMessage.isEmpty {
                Text(characterJumpMessage).font(.caption2).foregroundStyle(.orange)
            }
            if selectingCharacters {
                HStack(spacing: 10) {
                    Button("Select drawn") {
                        selectedCharacters = Set(project.characters.filter { project.resolvedGlyph($0)?.hasArtwork == true })
                    }
                    .buttonStyle(.plain).font(.caption2)
                    Button("Clear") { selectedCharacters.removeAll() }
                        .buttonStyle(.plain).font(.caption2).disabled(selectedCharacters.isEmpty)
                    Spacer()
                    Text("\(selectedCharacters.count) selected")
                        .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .contain)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 34, maximum: 46), spacing: 6)], spacing: 6) {
                    ForEach(visibleCharacters, id: \.self) { character in
                        let complete = project.resolvedGlyph(character)?.hasArtwork == true
                        let selectedForExport = selectedCharacters.contains(character)
                        Button {
                            selectedCharacter = character
                            if selectingCharacters {
                                if selectedForExport { selectedCharacters.remove(character) }
                                else { selectedCharacters.insert(character) }
                            }
                        } label: {
                            ZStack {
                                Text(character).font(.system(size: 18, design: .serif)).frame(maxWidth: .infinity, minHeight: 34)
                                if selectingCharacters {
                                    Image(systemName: selectedForExport ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(selectedForExport ? ShelfPalette.ink : Color.secondary)
                                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                        .padding(3)
                                }
                                if complete {
                                    Circle().fill(Color.green).frame(width: 6, height: 6)
                                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                                        .padding(4)
                                }
                            }
                            .background(selectedForExport ? ShelfPalette.ink.opacity(colorSchemeContrast == .increased ? 0.28 : 0.18) : selectedCharacter == character ? ShelfPalette.ink.opacity(colorSchemeContrast == .increased ? 0.2 : 0.11) : Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 7))
                            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(selectedForExport || selectedCharacter == character ? ShelfPalette.ink : Color.primary.opacity(colorSchemeContrast == .increased ? 0.45 : 0.08), lineWidth: selectedForExport || selectedCharacter == character ? (colorSchemeContrast == .increased ? 2 : 1.5) : 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(character), \(complete ? "artwork present" : "empty")")
                        .accessibilityValue(selectingCharacters ? (selectedForExport ? "Selected for export" : "Not selected for export") : (selectedCharacter == character ? "Current glyph" : ""))
                        .accessibilityAddTraits(selectedCharacter == character ? .isSelected : [])
                        .help(complete ? "Artwork present" : "No artwork yet")
                        .id(character)
                    }
                    }
                    if visibleCharacters.isEmpty {
                        Text(characterFilter == .drawn ? "No drawn characters yet." : "No empty characters.")
                            .font(.caption).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 8)
                    }
                }
                .onChange(of: selectedCharacter) { character in
                    if characterFilter.characters(in: project).contains(character) { proxy.scrollTo(character, anchor: .center) }
                }
                .onChange(of: characterFilter) { filter in
                    if filter.characters(in: project).contains(selectedCharacter) { proxy.scrollTo(selectedCharacter, anchor: .center) }
                }
            }
        }
        .padding(16).frame(maxHeight: .infinity, alignment: .topLeading)
    }

    private func jumpToCharacter(in project: FontLabProject) {
        let query = characterJump.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count == 1 else { characterJumpMessage = "Enter one character."; return }
        guard let match = FontLabCharacterNavigation.match(query, in: project.characters) else {
            characterJumpMessage = "\(query) is not in this project."
            return
        }
        if !characterFilter.characters(in: project).contains(match) { characterFilter = .all }
        selectedCharacter = match
        characterJump = ""
        characterJumpMessage = ""
    }

    private func glyphEditor(_ project: FontLabProject, compact: Bool, metricsColumns: Int) -> some View {
        let glyph = project.glyphs[selectedCharacter] ?? FontLabGlyph(character: selectedCharacter)
        let paths = FontLabVectorMath.paths(in: glyph)
        let anchorCount = paths.reduce(0) { $0 + $1.nodes.count }
        let canSimplify = paths.contains { $0.closed && ($0.nodes.allSatisfy { $0.incoming == nil && $0.outgoing == nil } || $0.nodes.count > 32) }
        return HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    glyphNavigation(in: project)
                    Spacer(minLength: 0)
                    glyphModePicker(glyph)
                    Button { undoStroke(glyph, projectID: project.id) } label: { Image(systemName: "arrow.uturn.backward") }
                        .disabled(glyphUndo.isEmpty || store.readBlocked).help("Undo glyph edit (⌘Z)").accessibilityLabel("Undo edit")
                    Button { redoGlyph(projectID: project.id) } label: { Image(systemName: "arrow.uturn.forward") }
                        .disabled(glyphRedo.isEmpty || store.readBlocked).help("Redo glyph edit (⇧⌘Z)").accessibilityLabel("Redo edit")
                    glyphHeaderActions(project, glyph: glyph, anchorCount: anchorCount, canSimplify: canSimplify)
                }.buttonStyle(.borderless).controlSize(.small)
                if anchorCount > 100 && canSimplify {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("\(anchorCount) points — simplify this outline before editing individual nodes.", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                            .font(.callout).fixedSize(horizontal: false, vertical: true)
                        Button("Simplify outline…") { showSmoothing = true }.disabled(store.readBlocked)
                    }.padding(10).background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
                }
                if compact || session.focusEditor {
                    DisclosureGroup(isExpanded: $session.showMetrics) {
                        metricsPanel(project, glyph: glyph, expanded: true, columns: metricsColumns).padding(.top, 8)
                    } label: {
                        Label("Metrics & spacing", systemImage: "ruler")
                            .font(.subheadline.weight(.medium))
                    }
                    .accessibilityIdentifier("font-lab-compact-metrics")
                }
                if vectorEditing || glyph.components?.isEmpty == false {
                    FontLabVectorEditorView(glyph: glyph, metrics: project.metrics, retainedEditor: session.vector(for: vectorSessionKey(project), glyph: glyph, metrics: project.metrics), componentStrokes: Array((project.resolvedGlyph(glyph.character)?.strokes ?? []).dropFirst(glyph.strokes.count)), previewInkHex: project.previewInkHex, compact: compact,
                        onChange: { edited in recordGlyphEdit(edited, projectID: project.id) },
                        onUndo: { undoStroke(glyph, projectID: project.id) },
                        onRedo: { redoGlyph(projectID: project.id) },
                        onPreviewInkChange: { hex in
                            store.updateProject(project.id, save: false) { $0.previewInkHex = hex }
                            store.scheduleSave()
                        })
                        .id(vectorSessionKey(project))
                        .disabled(store.readBlocked)
                } else {
                HStack(spacing: 12) {
                        Picker("Tool", selection: $session.drawingTool) {
                            ForEach(FontLabDrawingTool.allCases) { tool in
                                Label(localizedKey(tool.title), systemImage: tool.systemImage).tag(tool)
                            }
                        }
                        .labelsHidden().pickerStyle(.segmented).frame(width: 240)
                    Spacer(minLength: 0)
                    Button("Brush settings") { showBrushSettings = true }
                        .buttonStyle(.borderless)
                        .typefieldPopover(isPresented: $showBrushSettings) { brushSettings.frame(width: 440).padding(12) }
                }.controlSize(.small)
                FontLabGlyphCanvas(
                    glyph: glyph,
                    metrics: project.metrics,
                    strokeWidth: strokeWidth,
                    tool: drawingTool,
                    nibStyle: nibStyle,
                    smoothing: smoothing,
                    usesTabletPressure: usesTabletPressure,
                    onTabletInput: { if !tabletInputDetected { tabletInputDetected = true } },
                    onUndo: { undoStroke(glyph, projectID: project.id) },
                    onRedo: { redoGlyph(projectID: project.id) },
                    onSelectTool: { drawingTool = $0 }
                ) { editedGlyph in
                    recordGlyphEdit(editedGlyph, projectID: project.id)
                }
                .id(project.id.uuidString + selectedCharacter + glyphEditRevision.uuidString)
                .frame(minWidth: 340, maxWidth: .infinity, minHeight: 340, maxHeight: .infinity)
                .layoutPriority(1)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.12)))
                }
            }
            if !compact && !session.focusEditor && session.showMetrics { metricsPanel(project, glyph: glyph) }
        }
        .padding(compact ? 6 : 20).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var brushSettings: some View {
                VStack(alignment: .leading, spacing: 9) {
                    HStack(spacing: 12) {
                        Text("Nib").font(.caption).foregroundStyle(.secondary)
                        Picker("Nib", selection: $session.nibStyle) {
                            ForEach(FontLabNibStyle.allCases) { style in
                                Label(localizedKey(style.title), systemImage: style.systemImage).tag(style)
                            }
                        }
                        .labelsHidden().pickerStyle(.menu).frame(width: 124)
                        .disabled(drawingTool != .pen)
                        Spacer(minLength: 0)
                    }
                    HStack(spacing: 12) {
                        Text(drawingTool == .reshape ? "Point editing" : drawingTool == .pen ? "Stroke" : "Eraser size").font(.caption).foregroundStyle(.secondary)
                        Slider(value: $session.strokeWidth, in: 0.008...0.07).frame(maxWidth: 210).disabled(drawingTool == .reshape)
                        Text(strokeWidth.formatted(.number.precision(.fractionLength(3))))
                            .font(.caption2.monospacedDigit()).foregroundStyle(.secondary).frame(width: 38, alignment: .trailing)
                        Spacer(minLength: 0)
                        Picker("Smoothing", selection: $session.smoothing) {
                            ForEach(FontLabSmoothingLevel.allCases) { level in Text(localizedKey(level.title)).tag(level) }
                        }
                        .pickerStyle(.menu).frame(width: 138).disabled(drawingTool != .pen)
                    }
                    HStack(spacing: 14) {
                        Toggle("Pressure", isOn: $session.usesTabletPressure)
                            .toggleStyle(.switch).controlSize(.small).disabled(drawingTool != .pen)
                        Spacer(minLength: 4)
                        Button { showInputHelp.toggle() } label: {
                            Label(tabletInputDetected ? "Pen input detected" : "iPad & tablet", systemImage: tabletInputDetected ? "checkmark.circle.fill" : "ipad")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(tabletInputDetected ? Color.green : Color.secondary)
                        .help("Set up Apple Pencil with Sidecar or a macOS drawing tablet")
                    }
                    Text(drawingTool == .reshape ? "Drag a blue point to reshape a stroke or outline. Use Vector editor for curve handles. ⌘Z undoes the last canvas edit." : drawingTool == .pen ? "Draw with a mouse, trackpad, Apple Pencil through Sidecar, or a macOS-compatible pen tablet. ⌘Z undoes the last canvas edit." : "Drag across a line or filled shape to erase it. ⌘Z restores the last canvas edit.")
                        .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    private func glyphNavigation(in project: FontLabProject) -> some View {
        HStack(spacing: 8) {
            Text("Edit \(selectedCharacter)").font(.title3.weight(.semibold))
            Button { selectAdjacentCharacter(in: project, offset: -1) } label: {
                Image(systemName: "chevron.left").frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .disabled(!hasAdjacentCharacter(in: project, offset: -1))
            .help(characterFilter == .all ? "Previous glyph (⌘[)" : "Previous \(characterFilter.rawValue.lowercased()) glyph (⌘[)")
            .accessibilityLabel("Previous glyph")
            Button { selectAdjacentCharacter(in: project, offset: 1) } label: {
                Image(systemName: "chevron.right").frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .disabled(!hasAdjacentCharacter(in: project, offset: 1))
            .help(characterFilter == .all ? "Next glyph (⌘])" : "Next \(characterFilter.rawValue.lowercased()) glyph (⌘])")
            .accessibilityLabel("Next glyph")
        }
    }

    private func glyphModePicker(_ glyph: FontLabGlyph) -> some View {
        Picker("Editor", selection: $session.vectorEditing) {
            Text("Vector").tag(true)
            Text("Sketch").tag(false).disabled(glyph.components?.isEmpty == false)
        }.pickerStyle(.segmented).labelsHidden().frame(width: 150)
    }

    private func glyphHeaderActions(_ project: FontLabProject, glyph: FontLabGlyph, anchorCount: Int, canSimplify: Bool) -> some View {
        Menu("Glyph") {
            if anchorCount <= 100 {
                Button("Simplify outline…") { showSmoothing = true }
                    .disabled(store.readBlocked || !canSimplify)
            }
            Button("Clear", role: .destructive) { clearRequest = ClearRequest(projectID: project.id, glyph: glyph) }
                .disabled(!glyph.hasArtwork || store.readBlocked)
            Divider()
            Text("History applies to \(selectedCharacter) artwork and spacing in this session.")
        }.menuStyle(.borderlessButton).fixedSize().help("Simplify or clear this glyph")
    }

    private func hasAdjacentCharacter(in project: FontLabProject, offset: Int) -> Bool {
        let sequence = FontLabCharacterNavigation.sequence(selectedCharacter: selectedCharacter, in: project, filter: characterFilter)
        guard let index = sequence.firstIndex(of: selectedCharacter) else { return false }
        return sequence.indices.contains(index + offset)
    }

    private func selectAdjacentCharacter(in project: FontLabProject, offset: Int) {
        let sequence = FontLabCharacterNavigation.sequence(selectedCharacter: selectedCharacter, in: project, filter: characterFilter)
        guard let index = sequence.firstIndex(of: selectedCharacter),
              sequence.indices.contains(index + offset) else { return }
        selectedCharacter = sequence[index + offset]
    }

    private func metricsPanel(_ project: FontLabProject, glyph: FontLabGlyph, expanded: Bool = false, columns: Int = 1) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Metrics").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Button { showMetricsGuide = true } label: { Label("Guide", systemImage: "questionmark.circle") }
                    .buttonStyle(.plain).font(.caption).help("Learn what each type metric controls")
            }
            if expanded {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 0), spacing: 20, alignment: .topLeading), count: columns), alignment: .leading, spacing: 16) {
                    metricIllustration(project, glyph: glyph)
                    verticalMetrics(project)
                    glyphBearings(project, glyph: glyph)
                }
            } else {
                metricIllustration(project, glyph: glyph)
                verticalMetrics(project)
                Divider()
                glyphBearings(project, glyph: glyph)
            }
        }
        .padding(16)
        .frame(width: expanded ? nil : 232)
        .frame(maxWidth: expanded ? .infinity : nil, alignment: .topLeading)
        .shelfGlass(radius: 14)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityIdentifier(expanded ? "font-lab-expanded-metrics" : "font-lab-side-metrics")
    }

    private func metricIllustration(_ project: FontLabProject, glyph: FontLabGlyph) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            FontLabMetricExample(metrics: project.metrics, glyph: glyph)
                .frame(height: 118)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color.primary.opacity(0.1)))
            Text("H reaches cap height; x reaches x-height. Both sit on the baseline.")
                .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func verticalMetrics(_ project: FontLabProject) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            metricSlider("Baseline", value: metricBinding(project.id, kind: .baseline), range: 0.04...0.42)
            metricSlider("x-height", value: metricBinding(project.id, kind: .xHeight), range: 0.12...0.88)
            metricSlider("Cap height", value: metricBinding(project.id, kind: .capHeight), range: 0.22...0.96)
        }
    }

    private func glyphBearings(_ project: FontLabProject, glyph: FontLabGlyph) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            metricSlider("Left bearing", value: bearingBinding(glyph, projectID: project.id, left: true), range: 0...0.4)
            metricSlider("Right bearing", value: bearingBinding(glyph, projectID: project.id, left: false), range: 0...0.4)
            Text("Measurements are proportions of the drawing area. Side bearings apply to this glyph.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func metricSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack { Text(title).font(.caption); Spacer(); Text(value.wrappedValue.formatted(.number.precision(.fractionLength(2)))).font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
            Slider(value: value, in: range, onEditingChanged: { editing in
                if !editing { store.flushPendingSave() }
            })
        }
    }

    private func preview(_ project: FontLabProject) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button { proofStripExpanded.toggle() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: proofStripExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .semibold)).frame(width: 10)
                        Text("Word proof").font(.caption.weight(.semibold))
                    }
                    .padding(.horizontal, 8).frame(height: 32).contentShape(Rectangle())
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .help(proofStripExpanded ? "Collapse word proof" : "Expand word proof")
                .accessibilityLabel(proofStripExpanded ? "Collapse word proof" : "Expand word proof")
                .accessibilityIdentifier("font-lab-word-proof-toggle")
                Spacer()
                if proofStripExpanded {
                    Text(project.previewText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Enter text to preview your letterforms together." : "Click a letter to edit it; outlines mark missing characters.")
                        .font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            if proofStripExpanded {
                TextField("Proof text", text: previewBinding(project.id)).textFieldStyle(.roundedBorder)
                    .onSubmit { store.flushPendingSave() }.disabled(store.readBlocked)
                if !project.previewText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    FontLabLiveVectorProof(project: project, editor: session.vector(for: vectorSessionKey(project), glyph: project.glyphs[selectedCharacter] ?? FontLabGlyph(character: selectedCharacter), metrics: project.metrics), vectorEditing: vectorEditing || project.glyphs[selectedCharacter]?.components?.isEmpty == false, selectedCharacter: selectedCharacter, onSelect: { character in
                        if project.characters.contains(character) { selectedCharacter = character }
                    })
                        .id(vectorSessionKey(project))
                        .frame(minHeight: 50, maxHeight: .infinity)
                        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(colorSchemeContrast == .increased ? 0.4 : 0.1)))
                }
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
        .accessibilityIdentifier("font-lab-proof-strip")
    }

    private func vectorSessionKey(_ project: FontLabProject) -> String {
        project.id.uuidString + (project.activeMasterID?.uuidString ?? "") + selectedCharacter + glyphEditRevision.uuidString
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "pencil.and.outline").font(.system(size: 42)).foregroundStyle(.secondary)
            Text(store.readBlocked ? "Letterform Editor data needs attention" : "Start a Letterform Editor project").font(.title2)
            Text(store.error.isEmpty ? "Draw from scratch or import your own letter artwork. Tune every glyph and export SVG artwork or an installable TrueType font." : store.error)
                .foregroundStyle(Color(nsColor: store.error.isEmpty ? .secondaryLabelColor : .systemOrange)).multilineTextAlignment(.center).frame(maxWidth: 520)
            if !store.readBlocked {
                HStack(spacing: 10) {
                    Button("Import artwork", systemImage: "doc.viewfinder") { showArtworkImporter = true }
                        .disabled(store.readBlocked)
                    Button("Blank project") { _ = store.addProject(name: "") }
                }
            }
        }
        .padding(40)
    }

    private enum MetricKind { case baseline, xHeight, capHeight }

    private func metricBinding(_ projectID: UUID, kind: MetricKind) -> Binding<Double> {
        Binding(get: {
            guard let metrics = store.state.projects.first(where: { $0.id == projectID })?.metrics else { return 0 }
            switch kind { case .baseline: return metrics.baseline; case .xHeight: return metrics.xHeight; case .capHeight: return metrics.capHeight }
        }, set: { value in
            store.updateProject(projectID, save: false) { project in
                switch kind {
                case .baseline: project.metrics.setBaseline(value)
                case .xHeight: project.metrics.setXHeight(value)
                case .capHeight: project.metrics.setCapHeight(value)
                }
            }
            store.scheduleSave()
        })
    }

    private func projectNameBinding(_ projectID: UUID) -> Binding<String> {
        Binding(get: { store.state.projects.first(where: { $0.id == projectID })?.name ?? "" }, set: { name in
            let limited = String(name.prefix(200))
            let safeName = limited.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled font" : limited
            store.updateProject(projectID, save: false) { $0.name = safeName }
            store.scheduleSave()
        })
    }

    private func previewBinding(_ projectID: UUID) -> Binding<String> {
        Binding(get: { store.state.projects.first(where: { $0.id == projectID })?.previewText ?? "" }, set: { text in
            store.updateProject(projectID, save: false) { $0.previewText = String(text.prefix(2_000)) }
            store.scheduleSave()
        })
    }

    private func bearingBinding(_ fallback: FontLabGlyph, projectID: UUID, left: Bool) -> Binding<Double> {
        Binding(get: {
            let glyph = store.state.projects.first(where: { $0.id == projectID })?.glyphs[fallback.character] ?? fallback
            return left ? glyph.leftSideBearing : glyph.rightSideBearing
        }, set: { value in
            var glyph = store.state.projects.first(where: { $0.id == projectID })?.glyphs[fallback.character] ?? fallback
            if left { glyph.leftSideBearing = value } else { glyph.rightSideBearing = value }
            recordGlyphEdit(glyph, projectID: projectID)
        })
    }

    private func performVectorWorkspaceCommand(_ command: FontLabShortcutAction) -> Bool {
        guard command.isVectorCommand, !store.readBlocked, let project = store.selectedProject else { return false }
        let glyph = project.glyphs[selectedCharacter] ?? FontLabGlyph(character: selectedCharacter)
        guard vectorEditing || glyph.components?.isEmpty == false else { return false }
        let editor = session.vector(for: vectorSessionKey(project),
                                    glyph: glyph, metrics: project.metrics)
        editor.receive(glyph)
        editor.metrics = project.metrics
        editor.onCommit = { edited in recordGlyphEdit(edited, projectID: project.id) }
        switch command {
        case .copyContours: editor.copyPaths()
        case .pasteContours: editor.pastePaths()
        case .selectAllContours: editor.selectAll()
        case .joinEndpoints: editor.joinEndpoints()
        default: return false
        }
        return true
    }

    @discardableResult private func recordGlyphEdit(_ edited: FontLabGlyph, projectID: UUID) -> Bool {
        guard !store.readBlocked, var candidate = store.selectedProject, candidate.id == projectID else { return false }
        let previous = candidate.glyphs[edited.character] ?? FontLabGlyph(character: edited.character)
        guard edited != previous else { return true }
        candidate.glyphs[edited.character] = edited
        guard candidate.isValid else { store.error = "This edit would move a linked component outside its glyph. Adjust or decompose the component first."; glyphEditRevision = UUID(); return false }
        store.setGlyph(edited, in: projectID, save: false)
        guard store.selectedProject?.glyphs[edited.character] == edited else { return false }
        editHistory.record(previous)
        store.scheduleSave(after: 0.4)
        return true
    }

    private func undoStroke(_ glyph: FontLabGlyph, projectID: UUID) {
        let current = store.selectedProject?.glyphs[glyph.character] ?? glyph
        var history = editHistory
        guard let edited = history.undo(current), edited != current,
              var candidate = store.selectedProject, candidate.id == projectID else { return }
        candidate.glyphs[edited.character] = edited
        guard candidate.isValid else { store.error = "Undo would invalidate a linked component. Adjust its placement first."; return }
        store.setGlyph(edited, in: projectID, save: true)
        if store.selectedProject?.glyphs[edited.character] == edited { editHistory = history }
    }

    private func redoGlyph(projectID: UUID) {
        var history = editHistory
        guard let current = store.selectedProject?.glyphs[selectedCharacter], let next = history.redo(current),
              var candidate = store.selectedProject, candidate.id == projectID else { return }
        candidate.glyphs[next.character] = next
        guard candidate.isValid else { store.error = "Redo would invalidate a linked component. Adjust its placement first."; return }
        store.setGlyph(next, in: projectID, save: true)
        if store.selectedProject?.glyphs[next.character] == next { editHistory = history }
    }

    private func clearGlyph(_ glyph: FontLabGlyph, projectID: UUID) {
        guard let project = store.selectedProject, project.id == projectID,
              let current = project.glyphs[glyph.character], current == glyph else { return }
        var edited = current
        edited.strokes = []
        edited.components = nil
        edited.importedFrom = nil
        edited.importFormat = nil
        edited.starterOrigin = nil
        store.setGlyph(edited, in: projectID, save: true)
        if store.selectedProject?.glyphs[edited.character] == edited, edited != current { editHistory.record(current) }
    }

    private func syncMenuHistory() {
        FontLabEditMenuBridge.shared.update(
            projectID: project?.id,
            character: project == nil ? nil : selectedCharacter,
            canUndo: !glyphUndo.isEmpty && !store.readBlocked,
            canRedo: !glyphRedo.isEmpty && !store.readBlocked
        )
    }

    private func prepareExport(_ kind: ExportRequest.Kind, characters: [String], project: FontLabProject) {
        let undrawn = max(0, project.characters.count - project.completedCount)
        let message: String
        switch kind {
        case .glyphSVG:
            message = "Export \(characters.first ?? selectedCharacter) as one SVG outline. Other glyphs and kerning pairs stay in this project; the SVG is not a full font."
        case .selectedSVGs:
            let skipped = max(0, selectedCharacters.count - characters.count)
            message = "Export \(characters.count) selected drawn \(characters.count == 1 ? "glyph" : "glyphs") as separate SVG outlines. \(skipped) selected empty \(skipped == 1 ? "character is" : "characters are") skipped. Kerning pairs are not part of SVG glyph files."
        case .allSVGs:
            message = "Export all \(characters.count) drawn glyphs as separate SVG outlines. \(undrawn) undrawn \(undrawn == 1 ? "character is" : "characters are") omitted. Kerning pairs are not part of SVG glyph files."
        case .trueType:
            let scope = FontLabTrueTypeExporter.exportScope(for: project)
            guard scope.mappedOpenContourCharacters.isEmpty else {
                store.error = session.warnAboutOpenContours(scope.mappedOpenContourCharacters, projectID: project.id)
                return
            }
            message = "Export a static TrueType font from the active master: \(scope.mappedArtworkCharacters.count) outlined \(scope.mappedArtworkCharacters.count == 1 ? "character" : "characters") mapped, plus a blank space. \(scope.skippedCharacters.count) empty or unsupported project \(scope.skippedCharacters.count == 1 ? "character is" : "characters are") omitted. Kerning uses the legacy kern table, which some apps ignore."
        case .variableTrueType:
            message = "Export one variable TrueType font with a weight axis between two compatible masters. Every mapped character must have corresponding contours and matching winding. Vertical metrics and kerning must match; incompatible masters are rejected before saving."
        }
        exportRequest = ExportRequest(projectID: project.id, kind: kind, characters: characters, message: message)
    }

    private func performExport(_ request: ExportRequest) {
        exportRequest = nil
        guard let project = store.selectedProject, project.id == request.projectID else {
            store.error = "The selected project changed. Open Export again to review the current scope."
            return
        }
        switch request.kind {
        case .glyphSVG:
            guard let character = request.characters.first else { return }
            exportGlyphSVG(project, character: character)
        case .selectedSVGs, .allSVGs:
            exportGlyphSVGs(project, characters: request.characters)
        case .trueType:
            exportInstallableFont(project)
        case .variableTrueType:
            exportInstallableFont(project, variable: true)
        }
    }

    private func exportGlyphSVG(_ project: FontLabProject, character: String) {
        guard let glyph = project.resolvedGlyph(character), glyph.hasArtwork else {
            store.status = "Draw \(character) before exporting it."
            return
        }
        let panel = NSSavePanel()
        panel.title = "Export drawn glyph as SVG"
        panel.prompt = "Export SVG"
        panel.nameFieldStringValue = "\(safeFilename(project.name))-\(safeFilename(character)).svg"
        panel.allowedContentTypes = [.svg]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do {
            try FontLabSVGExporter.data(projectName: project.name, glyph: glyph, metrics: project.metrics).write(to: destination, options: .atomic)
            store.error = ""
            store.status = "Exported glyph \(character) as \(destination.lastPathComponent). SVG contains its outline only; kerning stays in the project."
        } catch {
            store.error = "The SVG could not be exported. " + error.localizedDescription
        }
    }

    private func exportGlyphSVGs(_ project: FontLabProject, characters: [String]) {
        let artifacts = FontLabSVGCollectionExporter.artifacts(for: project.outputProject, characters: Set(characters))
        guard !artifacts.isEmpty else {
            store.status = "Select at least one drawn glyph before exporting."
            return
        }
        let panel = NSOpenPanel()
        panel.title = "Choose a folder for exported SVG glyphs"
        panel.prompt = "Export SVGs"
        panel.message = "Typefield creates a new folder here, so existing files are never replaced."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let parent = panel.url else { return }
        let fileManager = FileManager.default
        var createdDestination: URL?
        do {
            let destination = try createUniqueExportDirectory(in: parent, baseName: safeFilename(project.name) + "-SVG", fileManager: fileManager)
            createdDestination = destination
            for artifact in artifacts {
                let url = destination.appendingPathComponent(artifact.suggestedFilename)
                try artifact.data.write(to: url, options: [.atomic, .withoutOverwriting])
            }
            store.error = ""
            store.status = "Exported \(artifacts.count) SVG \(artifacts.count == 1 ? "glyph" : "glyphs") to \(destination.lastPathComponent). Kerning stays in the project."
            NSWorkspace.shared.activateFileViewerSelecting([destination])
        } catch {
            // Only clean up a directory this export successfully created. A
            // different process may win a candidate name between attempts.
            if let createdDestination { try? fileManager.removeItem(at: createdDestination) }
            store.error = "The SVG set could not be exported. " + error.localizedDescription
        }
    }

    private func exportInstallableFont(_ project: FontLabProject, variable: Bool = false) {
        let scope = FontLabTrueTypeExporter.exportScope(for: project)
        guard variable || !scope.mappedArtworkCharacters.isEmpty else {
            store.status = "Draw or import at least one supported, single-scalar character before exporting an installable font."
            return
        }
        guard variable || scope.mappedOpenContourCharacters.isEmpty else {
            store.error = session.warnAboutOpenContours(scope.mappedOpenContourCharacters, projectID: project.id)
            return
        }
        let panel = NSSavePanel()
        panel.title = variable ? "Export variable TrueType font" : "Export installable TrueType font"
        panel.prompt = "Export Font"
        panel.message = variable ? "Both masters must have compatible outlines for every mapped character. Typefield validates the variable font with macOS before saving." : "\(scope.mappedArtworkCharacters.count) outlined characters will be mapped, plus a blank space; \(scope.skippedCharacters.count) empty or unsupported project characters will be omitted. Kerning uses the legacy kern table. Typefield validates the font with macOS before saving."
        panel.nameFieldStringValue = safeFilename(project.name) + (variable ? "-Variable.ttf" : ".ttf")
        panel.allowedContentTypes = [UTType(filenameExtension: "ttf") ?? .data]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let destination = panel.url else { return }

        isExportingFont = true
        store.error = ""
        store.status = "Building and validating \(project.name)…"
        let projectSnapshot = project
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try variable ? FontLabTrueTypeExporter.writeVariable(projectSnapshot, to: destination) : FontLabTrueTypeExporter.write(projectSnapshot, to: destination) }
            DispatchQueue.main.async {
                isExportingFont = false
                switch result {
                case let .success(artifact):
                    let warning = artifact.warnings.isEmpty ? "" : " " + artifact.warnings.joined(separator: " ")
                    store.status = "Exported \(artifact.exportedArtworkCharacterCount) outlined characters plus a blank space as \(destination.lastPathComponent). " + (variable ? "Weight axis is variable." : "Kerning uses legacy kern.") + warning
                    NSWorkspace.shared.activateFileViewerSelecting([destination])
                case let .failure(error):
                    store.error = "The installable font could not be exported. " + error.localizedDescription
                }
            }
        }
    }

    private func createUniqueExportDirectory(in parent: URL, baseName: String, fileManager: FileManager) throws -> URL {
        let base = baseName.isEmpty ? "Font-Lab-SVG" : baseName
        for suffix in 1..<10_000 {
            let name = suffix == 1 ? base : "\(base)-\(suffix)"
            let candidate = parent.appendingPathComponent(name, isDirectory: true)
            do {
                try fileManager.createDirectory(at: candidate, withIntermediateDirectories: false)
                return candidate
            } catch let error as CocoaError where error.code == .fileWriteFileExists {
                continue
            }
        }
        throw CocoaError(.fileWriteFileExists)
    }

    private func safeFilename(_ value: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>").union(.newlines).union(.controlCharacters)
        let cleaned = value.components(separatedBy: invalid).filter { !$0.isEmpty }.joined(separator: "-")
        return cleaned.isEmpty ? "glyph" : String(cleaned.prefix(80))
    }
}

private struct FontLabMetricsGuideSheet: View {
    @Environment(\.dismiss) private var dismiss
    let metrics: FontLabMetrics
    let glyph: FontLabGlyph

    private let columns = [GridItem(.flexible(), alignment: .topLeading), GridItem(.flexible(), alignment: .topLeading)]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("A quick guide to type metrics").font(.title2.weight(.semibold))
                    Text("The guides are adjustable starting points, not rules you have to obey.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            FontLabMetricExample(metrics: metrics, glyph: glyph)
                .frame(height: 220)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.12)))
            LazyVGrid(columns: columns, alignment: .leading, spacing: 13) {
                definition("Baseline", "The line most letters sit on. Curves may dip slightly below it; descenders such as p and g extend farther below.")
                definition("x-height", "The height of a typical lowercase x. A larger x-height often makes lowercase text feel bigger and more open.")
                definition("Cap height", "The height of flat-topped capitals such as H. Rounded capitals can overshoot it slightly by design.")
                definition("Side bearings", "The blank space to the left and right of this glyph. They control rhythm and spacing; they are not crop lines.")
            }
            Text("Tip: draw H and O to establish capitals, then x, n, o, and p for lowercase proportions and spacing. You can export a font with only the letters you have drawn.")
                .font(.callout).foregroundStyle(.secondary)
        }
        .padding(24).frame(width: 660, height: 570)
    }

    private func definition(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline.weight(.semibold))
            Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct FontLabMetricExample: NSViewRepresentable {
    let metrics: FontLabMetrics
    let glyph: FontLabGlyph

    func makeNSView(context: Context) -> FontLabMetricExampleNSView {
        let view = FontLabMetricExampleNSView()
        view.wantsLayer = true
        view.layer?.cornerRadius = 9
        view.layer?.masksToBounds = true
        return view
    }

    func updateNSView(_ view: FontLabMetricExampleNSView, context: Context) {
        view.metrics = metrics
        view.leftBearing = glyph.leftSideBearing
        view.rightBearing = glyph.rightSideBearing
        view.needsDisplay = true
    }
}

private final class FontLabMetricExampleNSView: NSView {
    var metrics = FontLabMetrics()
    var leftBearing = 0.08
    var rightBearing = 0.08

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.textBackgroundColor.setFill()
        bounds.fill()
        let rect = bounds.insetBy(dx: max(10, bounds.width * 0.05), dy: 10)
        guard rect.width > 0, rect.height > 0 else { return }
        let baselineY = rect.minY + CGFloat(metrics.baseline) * rect.height
        let xHeightY = rect.minY + CGFloat(metrics.xHeight) * rect.height
        let capHeightY = rect.minY + CGFloat(metrics.capHeight) * rect.height
        let leftX = rect.minX + CGFloat(leftBearing) * rect.width
        let rightX = rect.maxX - CGFloat(rightBearing) * rect.width

        drawGuide(from: NSPoint(x: rect.minX, y: baselineY), to: NSPoint(x: rect.maxX, y: baselineY), color: .systemOrange, dash: [], label: "baseline")
        drawGuide(from: NSPoint(x: rect.minX, y: xHeightY), to: NSPoint(x: rect.maxX, y: xHeightY), color: .secondaryLabelColor, dash: [3, 3], label: "x-height")
        drawGuide(from: NSPoint(x: rect.minX, y: capHeightY), to: NSPoint(x: rect.maxX, y: capHeightY), color: .secondaryLabelColor, dash: [7, 3], label: "cap height")
        drawGuide(from: NSPoint(x: leftX, y: rect.minY), to: NSPoint(x: leftX, y: rect.maxY), color: .tertiaryLabelColor, dash: [2, 4], label: nil)
        drawGuide(from: NSPoint(x: rightX, y: rect.minY), to: NSPoint(x: rightX, y: rect.maxY), color: .tertiaryLabelColor, dash: [2, 4], label: nil)

        let capSpan = max(12, capHeightY - baselineY)
        let xSpan = max(10, xHeightY - baselineY)
        let capFont = fittedFont(for: .capHeight, height: capSpan)
        let xFont = fittedFont(for: .xHeight, height: xSpan)
        var cursor = leftX + 8
        cursor += drawLetter("H", font: capFont, at: NSPoint(x: cursor, y: baselineY)) + 7
        cursor += drawLetter("x", font: xFont, at: NSPoint(x: cursor, y: baselineY)) + 6
        if cursor < rightX - 18 { _ = drawLetter("p", font: xFont, at: NSPoint(x: cursor, y: baselineY)) }

        drawRotatedLabel("Left bearing", at: NSPoint(x: leftX + 7, y: rect.midY))
        drawRotatedLabel("Right bearing", at: NSPoint(x: rightX - 7, y: rect.midY))
    }

    private enum FontMetric { case capHeight, xHeight }

    private func fittedFont(for metric: FontMetric, height: CGFloat) -> NSFont {
        let reference = NSFont.systemFont(ofSize: 100, weight: .regular)
        let referenceHeight = metric == .capHeight ? reference.capHeight : reference.xHeight
        return NSFont.systemFont(ofSize: max(9, 100 * height / max(1, referenceHeight)), weight: .regular)
    }

    @discardableResult private func drawLetter(_ letter: String, font: NSFont, at point: NSPoint) -> CGFloat {
        let attributed = NSAttributedString(string: letter, attributes: [.font: font, .foregroundColor: NSColor.labelColor])
        let line = CTLineCreateWithAttributedString(attributed)
        guard let context = NSGraphicsContext.current?.cgContext else { return 0 }
        context.saveGState()
        context.textPosition = point
        CTLineDraw(line, context)
        context.restoreGState()
        return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }

    private func drawGuide(from start: NSPoint, to end: NSPoint, color: NSColor, dash: [CGFloat], label: String?) {
        let path = NSBezierPath()
        path.move(to: start)
        path.line(to: end)
        path.setLineDash(dash, count: dash.count, phase: 0)
        path.lineWidth = 1
        color.setStroke()
        path.stroke()
        if let label { drawBadge(label, at: NSPoint(x: start.x + 4, y: start.y + 2)) }
    }

    private func drawBadge(_ label: String, at point: NSPoint) {
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 8, weight: .medium), .foregroundColor: NSColor.secondaryLabelColor]
        let text = NSAttributedString(string: label, attributes: attributes)
        let box = NSRect(x: point.x - 3, y: point.y - 1, width: text.size().width + 6, height: text.size().height + 2)
        NSColor.textBackgroundColor.withAlphaComponent(0.88).setFill()
        NSBezierPath(roundedRect: box, xRadius: 3, yRadius: 3).fill()
        text.draw(at: NSPoint(x: point.x, y: point.y))
    }

    private func drawRotatedLabel(_ label: String, at point: NSPoint) {
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 7, weight: .medium), .foregroundColor: NSColor.tertiaryLabelColor]
        let text = NSAttributedString(string: label, attributes: attributes)
        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: point.x, yBy: point.y)
        transform.rotate(byDegrees: 90)
        transform.concat()
        text.draw(at: NSPoint(x: -text.size().width / 2, y: -text.size().height / 2))
        NSGraphicsContext.restoreGraphicsState()
    }
}

private struct FontLabGlyphCanvas: NSViewRepresentable {
    let glyph: FontLabGlyph
    let metrics: FontLabMetrics
    let strokeWidth: Double
    let tool: FontLabDrawingTool
    let nibStyle: FontLabNibStyle
    let smoothing: FontLabSmoothingLevel
    let usesTabletPressure: Bool
    let onTabletInput: () -> Void
    let onUndo: () -> Void
    let onRedo: () -> Void
    let onSelectTool: (FontLabDrawingTool) -> Void
    let onCommit: (FontLabGlyph) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onTabletInput: onTabletInput, onCommit: onCommit) }

    func makeNSView(context: Context) -> FontLabDrawingNSView {
        let view = FontLabDrawingNSView()
        view.wantsLayer = true
        view.layer?.cornerRadius = 14
        view.layer?.masksToBounds = true
        view.glyph = glyph
        view.metrics = metrics
        view.strokeWidth = strokeWidth
        view.tool = tool
        view.nibStyle = nibStyle
        view.smoothing = smoothing
        view.usesTabletPressure = usesTabletPressure
        view.onTabletInput = { context.coordinator.onTabletInput() }
        view.onUndo = onUndo
        view.onRedo = onRedo
        view.onSelectTool = onSelectTool
        view.onCommit = { context.coordinator.onCommit($0) }
        return view
    }

    func updateNSView(_ view: FontLabDrawingNSView, context: Context) {
        context.coordinator.onTabletInput = onTabletInput
        view.onUndo = onUndo
        view.onRedo = onRedo
        view.onSelectTool = onSelectTool
        context.coordinator.onCommit = onCommit
        if view.glyph.character != glyph.character || (!view.isDrawing && view.glyph != glyph) { view.replaceGlyph(glyph) }
        view.metrics = metrics
        view.strokeWidth = strokeWidth
        view.tool = tool
        view.nibStyle = nibStyle
        view.smoothing = smoothing
        view.usesTabletPressure = usesTabletPressure
        view.needsDisplay = true
    }

    final class Coordinator {
        var onTabletInput: () -> Void
        var onCommit: (FontLabGlyph) -> Void
        init(onTabletInput: @escaping () -> Void, onCommit: @escaping (FontLabGlyph) -> Void) {
            self.onTabletInput = onTabletInput
            self.onCommit = onCommit
        }
    }
}

final class FontLabDrawingNSView: NSView {
    var glyph = FontLabGlyph(character: "A") { didSet { needsDisplay = true } }
    var metrics = FontLabMetrics() { didSet { needsDisplay = true } }
    var strokeWidth = 0.026
    var tool = FontLabDrawingTool.pen { willSet { if newValue != tool { finishGesture() } } }
    var nibStyle = FontLabNibStyle.round
    var smoothing = FontLabSmoothingLevel.gentle
    var usesTabletPressure = true
    var onTabletInput: (() -> Void)?
    var onUndo: (() -> Void)?
    var onRedo: (() -> Void)?
    var onSelectTool: ((FontLabDrawingTool) -> Void)?
    var onCommit: ((FontLabGlyph) -> Void)?
    private(set) var isDrawing = false
    private var gestureChangedGlyph = false
    private var gestureStart: FontLabGlyph?
    private var reportedTabletInput = false
    private var nodeSelection: FontLabSketchReshape.Target?

    func replaceGlyph(_ value: FontLabGlyph) {
        cancelGesture()
        glyph = value
    }

    private func finishGesture() {
        guard isDrawing else { return }
        isDrawing = false
        let changed = gestureChangedGlyph && glyph != gestureStart
        gestureStart = nil; gestureChangedGlyph = false; nodeSelection = nil
        if changed { onCommit?(glyph) }
        needsDisplay = true
    }

    private func cancelGesture() {
        if let before = gestureStart { glyph = before }
        isDrawing = false; gestureStart = nil; gestureChangedGlyph = false; nodeSelection = nil
        needsDisplay = true
    }

    override func resignFirstResponder() -> Bool {
        finishGesture()
        return super.resignFirstResponder()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { finishGesture() }
        super.viewWillMove(toWindow: newWindow)
    }

    override var acceptsFirstResponder: Bool { true }
    private var drawingRect: NSRect {
        let available = bounds.insetBy(dx: 24, dy: 24)
        guard glyph.contourDesignWidth != nil else { return available }
        let em = min(available.height, available.width / glyph.resolvedDesignWidth)
        return NSRect(x: available.midX - em * glyph.resolvedDesignWidth / 2, y: available.midY - em / 2,
                      width: em * glyph.resolvedDesignWidth, height: em)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Glyph drawing area")
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Glyph drawing area")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.textBackgroundColor.setFill()
        bounds.fill()
        let rect = drawingRect
        drawHorizontalGuide(at: metrics.baseline, color: .systemOrange, dash: [])
        drawHorizontalGuide(at: metrics.xHeight, color: .secondaryLabelColor, dash: [4, 4])
        drawHorizontalGuide(at: metrics.capHeight, color: .secondaryLabelColor, dash: [8, 4])
        drawVerticalGuide(at: glyph.leftSideBearing)
        drawVerticalGuide(at: 1 - glyph.rightSideBearing)
        NSColor.separatorColor.setStroke()
        let border = NSBezierPath(rect: rect)
        border.lineWidth = 1
        border.stroke()
        fontLabDrawStrokes(glyph.strokes, in: rect, color: .labelColor)
        if tool == .reshape {
            NSColor.systemBlue.setFill()
            FontLabSketchReshape.visitPoints(in: glyph) { _, point in
                NSBezierPath(ovalIn: NSRect(x: rect.minX + point.x * rect.width - 2,
                    y: rect.minY + point.y * rect.height - 2, width: 4, height: 4)).fill()
            }
        }
        drawHorizontalLabel("Baseline", at: metrics.baseline, color: .systemOrange)
        drawHorizontalLabel("x-height", at: metrics.xHeight, color: .secondaryLabelColor)
        drawHorizontalLabel("Cap height", at: metrics.capHeight, color: .secondaryLabelColor)
        drawVerticalLabel("Left bearing", at: glyph.leftSideBearing, inwardOffset: 9)
        drawVerticalLabel("Right bearing", at: 1 - glyph.rightSideBearing, inwardOffset: -9)
    }

    override func mouseDown(with event: NSEvent) {
        finishGesture()
        window?.makeFirstResponder(self)
        guard let point = sampledPoint(for: event) else { return }
        gestureStart = glyph
        isDrawing = true
        gestureChangedGlyph = false
        switch tool {
        case .pen:
            guard glyph.strokes.count < 10_000 else { cancelGesture(); return }
            glyph.strokes.append(FontLabStroke(points: [point], width: min(max(strokeWidth, 0.002), 0.2), nibStyle: nibStyle))
            gestureChangedGlyph = true
        case .eraser:
            erase(at: point)
        case .reshape:
            nodeSelection = FontLabSketchReshape.nearest(to: point, in: glyph, displaySize: drawingRect.size)
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDrawing, let sampled = sampledPoint(for: event) else { return }
        switch tool {
        case .pen:
            guard !glyph.strokes.isEmpty, glyph.strokes[glyph.strokes.count - 1].points.count < 50_000 else { return }
            let previous = glyph.strokes[glyph.strokes.count - 1].points.last
            let point = previous.map { FontLabDrawingOperations.smoothed(sampled, after: $0, level: smoothing) } ?? sampled
            if let previous {
                let dx = point.x - previous.x
                let dy = point.y - previous.y
                if dx * dx + dy * dy < 0.000_01 { return }
            }
            glyph.strokes[glyph.strokes.count - 1].points.append(point)
            gestureChangedGlyph = true
        case .eraser:
            erase(at: sampled)
        case .reshape:
            if let node = nodeSelection, let changed = FontLabSketchReshape.moving(node, to: sampled, in: glyph), changed != glyph {
                glyph = changed
                gestureChangedGlyph = true
            }
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        finishGesture()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53, isDrawing { cancelGesture(); return }
        if handleUndoShortcut(event) { return }
        if handleToolShortcut(event) { return }
        super.keyDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if window?.firstResponder === self, handleUndoShortcut(event) { return true }
        return super.performKeyEquivalent(with: event)
    }

    private func handleUndoShortcut(_ event: NSEvent) -> Bool {
        let editingModifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard event.charactersIgnoringModifiers?.lowercased() == "z" else { return false }
        if editingModifiers == [.command, .shift], let onRedo {
            finishGesture()
            onRedo()
            return true
        }
        guard editingModifiers == .command, let onUndo else { return false }
        finishGesture()
        onUndo()
        return true
    }

    private func handleToolShortcut(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection([.command, .shift, .option, .control]).isEmpty,
              let onSelectTool else { return false }
        let tool: FontLabDrawingTool
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "p": tool = .pen
        case "e": tool = .eraser
        case "v": tool = .reshape
        default: return false
        }
        finishGesture()
        onSelectTool(tool)
        return true
    }

    private func sampledPoint(for event: NSEvent) -> FontLabPoint? {
        let point = convert(event.locationInWindow, from: nil)
        let rect = drawingRect
        guard rect.width > 0, rect.height > 0, rect.contains(point) else { return nil }
        let isTabletEvent = event.type == .tabletPoint || event.subtype == .tabletPoint
        if isTabletEvent, !reportedTabletInput {
            reportedTabletInput = true
            onTabletInput?()
        }
        let tilt = isTabletEvent ? event.tilt : .zero
        return FontLabPoint(
            x: min(max(Double((point.x - rect.minX) / rect.width), 0), 1),
            y: min(max(Double((point.y - rect.minY) / rect.height), 0), 1),
            pressure: isTabletEvent && usesTabletPressure ? min(max(Double(event.pressure), 0), 1) : nil,
            tiltX: isTabletEvent ? min(max(Double(tilt.x), -1), 1) : nil,
            tiltY: isTabletEvent ? min(max(Double(tilt.y), -1), 1) : nil
        )
    }

    private func erase(at point: FontLabPoint) {
        let edited = FontLabDrawingOperations.erasing(glyph.strokes, near: point, radius: max(0.018, strokeWidth * 1.7))
        guard edited.count != glyph.strokes.count else { return }
        glyph.strokes = edited
        glyph.importedFrom = nil
        glyph.importFormat = nil
        gestureChangedGlyph = true
    }

    private func drawHorizontalGuide(at position: Double, color: NSColor, dash: [CGFloat]) {
        let rect = drawingRect
        let y = rect.minY + CGFloat(position) * rect.height
        let path = NSBezierPath()
        path.move(to: NSPoint(x: rect.minX, y: y))
        path.line(to: NSPoint(x: rect.maxX, y: y))
        path.setLineDash(dash, count: dash.count, phase: 0)
        path.lineWidth = 1
        color.setStroke()
        path.stroke()
    }

    private func drawVerticalGuide(at position: Double) {
        let rect = drawingRect
        let x = rect.minX + CGFloat(position) * rect.width
        let path = NSBezierPath()
        path.move(to: NSPoint(x: x, y: rect.minY))
        path.line(to: NSPoint(x: x, y: rect.maxY))
        path.setLineDash([3, 5], count: 2, phase: 0)
        path.lineWidth = 1
        NSColor.tertiaryLabelColor.setStroke()
        path.stroke()
    }

    private func drawHorizontalLabel(_ label: String, at position: Double, color: NSColor) {
        let rect = drawingRect
        let y = rect.minY + CGFloat(position) * rect.height
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 9, weight: .semibold), .foregroundColor: color]
        let text = NSAttributedString(string: label, attributes: attributes)
        let origin = NSPoint(x: rect.minX + 7, y: min(max(y + 3, rect.minY + 2), rect.maxY - text.size().height - 2))
        let box = NSRect(x: origin.x - 4, y: origin.y - 2, width: text.size().width + 8, height: text.size().height + 4)
        NSColor.textBackgroundColor.withAlphaComponent(0.9).setFill()
        NSBezierPath(roundedRect: box, xRadius: 4, yRadius: 4).fill()
        text.draw(at: origin)
    }

    private func drawVerticalLabel(_ label: String, at position: Double, inwardOffset: CGFloat) {
        let rect = drawingRect
        let x = rect.minX + CGFloat(position) * rect.width
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 8, weight: .semibold), .foregroundColor: NSColor.tertiaryLabelColor]
        let text = NSAttributedString(string: label, attributes: attributes)
        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: x + inwardOffset, yBy: rect.midY)
        transform.rotate(byDegrees: 90)
        transform.concat()
        let origin = NSPoint(x: -text.size().width / 2, y: -text.size().height / 2)
        let box = NSRect(x: origin.x - 4, y: origin.y - 2, width: text.size().width + 8, height: text.size().height + 4)
        NSColor.textBackgroundColor.withAlphaComponent(0.9).setFill()
        NSBezierPath(roundedRect: box, xRadius: 4, yRadius: 4).fill()
        text.draw(at: origin)
        NSGraphicsContext.restoreGraphicsState()
    }
}

struct FontLabPreviewCanvas: NSViewRepresentable {
    let text: String
    let glyphs: [String: FontLabGlyph]
    let metrics: FontLabMetrics
    var kerningGroups: [FontLabKerningGroup] = []
    var kerningPairs: [FontLabKerningPair] = []
    var maximumEm: CGFloat = 96
    var centered = false
    var previewInkHex: String? = nil
    var selectedCharacter: String? = nil
    var onSelect: ((String) -> Void)? = nil

    func makeNSView(context: Context) -> FontLabPreviewNSView {
        let view = FontLabPreviewNSView()
        view.wantsLayer = true
        view.layer?.cornerRadius = 12
        view.layer?.masksToBounds = true
        return view
    }
    func updateNSView(_ view: FontLabPreviewNSView, context: Context) {
        view.text = text
        view.glyphs = glyphs
        view.metrics = metrics
        view.kerningGroups = kerningGroups
        view.kerningPairs = kerningPairs
        view.maximumEm = maximumEm
        view.centered = centered
        view.inkColor = previewInkHex.map(NSColor.init(hex:)) ?? .labelColor
        view.selectedCharacter = selectedCharacter
        view.onSelect = onSelect
        view.needsDisplay = true
    }
}

final class FontLabPreviewNSView: NSView {
    var text = ""
    var glyphs: [String: FontLabGlyph] = [:]
    var metrics = FontLabMetrics()
    var kerningGroups: [FontLabKerningGroup] = []
    var kerningPairs: [FontLabKerningPair] = []
    var maximumEm: CGFloat = 96
    var centered = false
    var inkColor: NSColor = .labelColor
    var selectedCharacter: String?
    var onSelect: ((String) -> Void)?
    private var hitRegions: [(String, CGRect)] = []
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let match = hitRegions.first(where: { $0.1.contains(point) }) { onSelect?(match.0) }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.textBackgroundColor.setFill()
        bounds.fill()
        hitRegions = []
        let characters = text.map(String.init)
        guard !characters.isEmpty else { return }
        let nominalHeight: CGFloat = min(maximumEm, max(32, bounds.height - 24))
        let nominalWidth = estimatedWidth(characters, em: nominalHeight)
        let em = nominalWidth > bounds.width - 24 ? nominalHeight * max(0.2, (bounds.width - 24) / nominalWidth) : nominalHeight
        var x: CGFloat = centered ? max(12, (bounds.width - estimatedWidth(characters, em: em) + 24) / 2) : 12
        let originY = max(8, (bounds.height - em) / 2)
        let baselineY = originY + CGFloat(metrics.baseline) * em
        let guide = NSBezierPath()
        guide.move(to: NSPoint(x: 10, y: baselineY))
        guide.line(to: NSPoint(x: bounds.maxX - 10, y: baselineY))
        guide.setLineDash([3, 5], count: 2, phase: 0)
        NSColor.separatorColor.setStroke()
        guide.stroke()

        for (index, character) in characters.enumerated() {
            if index > 0 { x += CGFloat(FontLabDesign.kerning(characters[index-1], character, groups: kerningGroups, pairs: kerningPairs)) / 1000 * em }
            if character == " " { x += em * 0.3; continue }
            let glyph = glyphs[character]
            let left = CGFloat(glyph?.leftSideBearing ?? 0.08) * em
            let right = CGFloat(glyph?.rightSideBearing ?? 0.08) * em
            let inkWidth = em * CGFloat(glyph?.resolvedDesignWidth ?? 0.62)
            let hit = CGRect(x: x, y: originY, width: left + inkWidth + right, height: em)
            hitRegions.append((character, hit))
            if character == selectedCharacter {
                ShelfPalette.nativeAccent.withAlphaComponent(0.1).setFill()
                NSBezierPath(roundedRect: hit, xRadius: 4, yRadius: 4).fill()
            }
            if let glyph, glyph.hasArtwork {
                let rect = NSRect(x: x + left, y: originY, width: inkWidth, height: em)
                fontLabDrawStrokes(glyph.strokes, in: rect, color: inkColor)
            } else {
                let placeholder = NSRect(x: x + left, y: originY + em * 0.18, width: inkWidth, height: em * 0.64)
                let path = NSBezierPath(roundedRect: placeholder, xRadius: 5, yRadius: 5)
                path.setLineDash([3, 3], count: 2, phase: 0)
                NSColor.tertiaryLabelColor.setStroke()
                path.stroke()
                let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: max(9, em * 0.18)), .foregroundColor: NSColor.secondaryLabelColor]
                let label = NSAttributedString(string: character, attributes: attributes)
                label.draw(at: NSPoint(x: placeholder.midX - label.size().width / 2, y: placeholder.midY - label.size().height / 2))
            }
            x += left + inkWidth + right
            if x > bounds.maxX { break }
        }
    }

    private func estimatedWidth(_ characters: [String], em: CGFloat) -> CGFloat {
        let adjustment = zip(characters, characters.dropFirst()).reduce(0.0) { $0 + FontLabDesign.kerning($1.0, $1.1, groups: kerningGroups, pairs: kerningPairs) }
        return 24 + CGFloat(adjustment) / 1000 * em + characters.reduce(CGFloat.zero) { result, character in
            if character == " " { return result + em * 0.3 }
            let glyph = glyphs[character]
            return result + em * (CGFloat(glyph?.resolvedDesignWidth ?? 0.62) + CGFloat(glyph?.leftSideBearing ?? 0.08) + CGFloat(glyph?.rightSideBearing ?? 0.08))
        }
    }
}

/// Tool, selection and viewport changes do not invalidate word geometry.
/// Provisional outlines still update live, before the gesture is committed.
private struct FontLabLiveVectorProof: View {
    let project: FontLabProject
    let editor: FontLabVectorEditor
    let vectorEditing: Bool
    let selectedCharacter: String
    let onSelect: (String) -> Void
    @State private var liveGlyph: FontLabGlyph
    init(project: FontLabProject, editor: FontLabVectorEditor, vectorEditing: Bool, selectedCharacter: String, onSelect: @escaping (String) -> Void) {
        self.project = project; self.editor = editor; self.vectorEditing = vectorEditing
        self.selectedCharacter = selectedCharacter; self.onSelect = onSelect
        _liveGlyph = State(initialValue: editor.glyph)
    }
    var body: some View {
        FontLabPreviewCanvas(text: project.previewText,
            glyphs: FontLabProofGeometry.glyphs(in: project, liveGlyph: vectorEditing ? liveGlyph : nil),
            metrics: project.metrics, kerningGroups: project.kerningGroups ?? [], kerningPairs: project.kerningPairs ?? [],
            previewInkHex: project.previewInkHex, selectedCharacter: selectedCharacter, onSelect: onSelect)
            .onReceive(editor.$glyph.removeDuplicates()) { value in
                // @Published emits before editor.glyph itself changes.
                if value != liveGlyph { liveGlyph = value }
            }
    }
}

func fontLabDrawStrokes(_ strokes: [FontLabStroke], in rect: NSRect, color: NSColor) {
    // System label ink can be translucent. Composite a glyph once so reused
    // or freehand strokes do not become darker wherever they overlap.
    let context = NSGraphicsContext.current?.cgContext
    let resolved = color.usingColorSpace(.deviceRGB) ?? color
    context?.saveGState()
    context?.setAlpha(resolved.alphaComponent)
    context?.beginTransparencyLayer(auxiliaryInfo: nil)
    defer { context?.endTransparencyLayer(); context?.restoreGState() }
    let color = resolved.withAlphaComponent(1)
    color.setStroke()
    color.setFill()
    for stroke in strokes {
        if let paths = stroke.vectorPaths {
            FontLabVectorMath.draw(paths, in: rect, color: color)
            continue
        }
        if let contours = stroke.contours {
            let path = NSBezierPath()
            path.windingRule = .nonZero
            for contour in contours {
                guard let first = contour.first else { continue }
                path.move(to: NSPoint(x: rect.minX + first.x * rect.width, y: rect.minY + first.y * rect.height))
                for point in contour.dropFirst() { path.line(to: NSPoint(x: rect.minX + point.x * rect.width, y: rect.minY + point.y * rect.height)) }
                path.close()
            }
            path.fill()
            continue
        }
        guard !stroke.points.isEmpty else { continue }
        let mapped = stroke.points.map { NSPoint(x: rect.minX + CGFloat($0.x) * rect.width, y: rect.minY + CGFloat($0.y) * rect.height) }
        let baseWidth = max(1, CGFloat(stroke.width) * min(rect.width, rect.height))
        if mapped.count == 1 {
            let width = baseWidth * CGFloat(FontLabDrawingOperations.pressureScale(for: stroke.points[0]))
            switch stroke.resolvedNibStyle {
            case .round:
                NSBezierPath(ovalIn: NSRect(x: mapped[0].x - width / 2, y: mapped[0].y - width / 2, width: width, height: width)).fill()
            case .marker:
                let markerRect = NSRect(x: mapped[0].x - width * 0.64, y: mapped[0].y - width * 0.32, width: width * 1.28, height: width * 0.64)
                NSBezierPath(roundedRect: markerRect, xRadius: width * 0.08, yRadius: width * 0.08).fill()
            case .outline:
                let ring = NSBezierPath(ovalIn: NSRect(x: mapped[0].x - width / 2, y: mapped[0].y - width / 2, width: width, height: width))
                ring.lineWidth = max(1, width * 0.14)
                ring.stroke()
            }
        } else if stroke.resolvedNibStyle == .outline {
            for edge in fontLabOutlineEdges(stroke: stroke, mapped: mapped, baseWidth: baseWidth) {
                guard let first = edge.first else { continue }
                let path = NSBezierPath()
                path.move(to: first)
                for point in edge.dropFirst() { path.line(to: point) }
                path.lineWidth = max(1, baseWidth * 0.14)
                path.lineCapStyle = .round
                path.lineJoinStyle = .round
                path.stroke()
            }
        } else if stroke.points.contains(where: { $0.pressure != nil }) {
            for index in 1..<mapped.count {
                let startScale = FontLabDrawingOperations.pressureScale(for: stroke.points[index - 1])
                let endScale = FontLabDrawingOperations.pressureScale(for: stroke.points[index])
                let path = NSBezierPath()
                path.move(to: mapped[index - 1])
                path.line(to: mapped[index])
                path.lineWidth = baseWidth * CGFloat((startScale + endScale) / 2) * (stroke.resolvedNibStyle == .marker ? 1.28 : 1)
                path.lineCapStyle = stroke.resolvedNibStyle == .marker ? .square : .round
                path.lineJoinStyle = stroke.resolvedNibStyle == .marker ? .bevel : .round
                path.stroke()
            }
        } else {
            let path = NSBezierPath()
            path.move(to: mapped[0])
            for point in mapped.dropFirst() { path.line(to: point) }
            path.lineWidth = baseWidth * (stroke.resolvedNibStyle == .marker ? 1.28 : 1)
            path.lineCapStyle = stroke.resolvedNibStyle == .marker ? .square : .round
            path.lineJoinStyle = stroke.resolvedNibStyle == .marker ? .bevel : .round
            path.stroke()
        }
    }
}

private func fontLabOutlineEdges(stroke: FontLabStroke, mapped: [NSPoint], baseWidth: CGFloat) -> [[NSPoint]] {
    guard mapped.count > 1 else { return [] }
    var leading: [NSPoint] = []
    var trailing: [NSPoint] = []
    for index in mapped.indices {
        let before = mapped[index == mapped.startIndex ? index : mapped.index(before: index)]
        let after = mapped[index == mapped.index(before: mapped.endIndex) ? index : mapped.index(after: index)]
        let dx = after.x - before.x
        let dy = after.y - before.y
        let length = max(0.001, hypot(dx, dy))
        let offset = baseWidth * CGFloat(FontLabDrawingOperations.pressureScale(for: stroke.points[index])) / 2
        let ox = -dy / length * offset
        let oy = dx / length * offset
        leading.append(NSPoint(x: mapped[index].x + ox, y: mapped[index].y + oy))
        trailing.append(NSPoint(x: mapped[index].x - ox, y: mapped[index].y - oy))
    }
    return [leading, trailing]
}
