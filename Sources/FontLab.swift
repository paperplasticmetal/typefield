import SwiftUI
import AppKit
import CoreText
import UniformTypeIdentifiers

struct FontLabPoint: Codable, Equatable {
    var x: Double
    var y: Double
    /// Optional native tablet data. Keeping these fields optional preserves
    /// decoding for Font Lab projects created before pressure support existed.
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

struct FontLabStroke: Codable, Identifiable, Equatable {
    var id = UUID()
    var points: [FontLabPoint] = []
    var width = 0.026

    var isValid: Bool {
        !points.isEmpty && points.count <= 50_000 && width.isFinite && (0.002...0.2).contains(width) && points.allSatisfy(\.isValid)
    }
}

enum FontLabDrawingTool: String, CaseIterable, Identifiable {
    case pen
    case eraser

    var id: String { rawValue }
    var title: String { self == .pen ? "Pen" : "Eraser" }
    var systemImage: String { self == .pen ? "pencil.tip" : "eraser" }
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

    var displayName: String { rawValue.uppercased() }
    var filenameExtensions: Set<String> { [rawValue] }
}

/// A validated handoff object for a future vector/raster tracing engine. Creating a
/// request never reads, changes, or installs a font and does not imply that tracing
/// is currently available.
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
            case .unsupportedFormat: return "Choose an SVG or PNG file."
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
        let elements = glyph.strokes.compactMap { stroke -> String? in
            guard let first = stroke.points.first else { return nil }
            let firstWidth = stroke.width * FontLabDrawingOperations.pressureScale(for: first) * 1_000
            if stroke.points.count == 1 {
                return "  <circle cx=\"\(number(first.x * 1_000))\" cy=\"\(number((1 - first.y) * 1_000))\" r=\"\(number(firstWidth / 2))\" fill=\"#111111\"/>"
            }
            if stroke.points.contains(where: { $0.pressure != nil }) {
                return zip(stroke.points, stroke.points.dropFirst()).map { start, end in
                    let scale = (FontLabDrawingOperations.pressureScale(for: start) + FontLabDrawingOperations.pressureScale(for: end)) / 2
                    let width = number(stroke.width * scale * 1_000)
                    return "  <line x1=\"\(number(start.x * 1_000))\" y1=\"\(number((1 - start.y) * 1_000))\" x2=\"\(number(end.x * 1_000))\" y2=\"\(number((1 - end.y) * 1_000))\" stroke=\"#111111\" stroke-width=\"\(width)\" stroke-linecap=\"round\"/>"
                }.joined(separator: "\n")
            }
            let points = stroke.points.map { "\(number($0.x * 1_000)),\(number((1 - $0.y) * 1_000))" }.joined(separator: " ")
            return "  <polyline points=\"\(points)\" fill=\"none\" stroke=\"#111111\" stroke-width=\"\(number(stroke.width * 1_000))\" stroke-linecap=\"round\" stroke-linejoin=\"round\"/>"
        }.joined(separator: "\n")
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1000 1000" role="img" aria-label="\(escaped(projectName)) glyph \(escaped(glyph.character))">
          <metadata>FontShelf Font Lab; character=\(escaped(glyph.character)); baseline=\(number(metrics.baseline)); x-height=\(number(metrics.xHeight)); cap-height=\(number(metrics.capHeight)); left-side-bearing=\(number(glyph.leftSideBearing)); right-side-bearing=\(number(glyph.rightSideBearing))</metadata>
        \(elements)
        </svg>
        """
    }

    private static func number(_ value: Double) -> String {
        String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), value)
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

    var hasArtwork: Bool { strokes.contains { !$0.points.isEmpty } }
    var isValid: Bool {
        character.count == 1 && strokes.count <= 10_000 && strokes.allSatisfy(\.isValid) &&
            leftSideBearing.isFinite && rightSideBearing.isFinite &&
            (0...0.4).contains(leftSideBearing) && (0...0.4).contains(rightSideBearing) &&
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

    init(id: UUID = UUID(), name: String = "Untitled font", characters: [String] = FontLabProject.starterCharacters) {
        self.id = id
        self.name = name
        self.characters = characters
        glyphs = Dictionary(uniqueKeysWithValues: characters.map { ($0, FontLabGlyph(character: $0)) })
    }

    var completedCount: Int { glyphs.values.filter(\.hasArtwork).count }
    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name.count <= 200 &&
            !characters.isEmpty && characters.count <= 2_000 && Set(characters).count == characters.count &&
            characters.allSatisfy { $0.count == 1 } && metrics.isValid && previewText.count <= 2_000 &&
            glyphs.count <= 2_000 && glyphs.allSatisfy { key, glyph in key == glyph.character && glyph.isValid }
    }
}

struct FontLabState: Codable, Equatable {
    var version = 1
    var projects: [FontLabProject] = []
    var selectedProject: UUID?

    var isValid: Bool {
        version == 1 && Set(projects.map(\.id)).count == projects.count && projects.allSatisfy(\.isValid) &&
            (selectedProject == nil || projects.contains { $0.id == selectedProject })
    }
}

final class FontLabStore: ObservableObject {
    @Published private(set) var state = FontLabState()
    @Published var error = ""
    @Published var status = ""
    @Published private(set) var savedAt: Date?

    let url: URL
    private(set) var readBlocked = false
    private var pendingSave: DispatchWorkItem?
    private var terminationObserver: NSObjectProtocol?

    init(url: URL) {
        self.url = url
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in self?.flushPendingSave() }
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let loaded = try JSONDecoder().decode(FontLabState.self, from: Data(contentsOf: url))
            guard loaded.isValid else {
                throw NSError(domain: "FontShelf.FontLab", code: 1, userInfo: [NSLocalizedDescriptionKey: "The file contains invalid or unsupported Font Lab data."])
            }
            state = loaded
        } catch {
            readBlocked = true
            self.error = "Font Lab could not be opened. The original file has been preserved and saving is disabled. " + error.localizedDescription
        }
    }

    deinit {
        if let terminationObserver { NotificationCenter.default.removeObserver(terminationObserver) }
    }

    var selectedProject: FontLabProject? {
        if let id = state.selectedProject { return state.projects.first { $0.id == id } }
        return state.projects.first
    }

    @discardableResult func addProject(name: String) -> UUID? {
        guard !readBlocked else { return nil }
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let project = FontLabProject(name: cleaned.isEmpty ? nextProjectName : cleaned)
        state.projects.append(project)
        state.selectedProject = project.id
        _ = save()
        return project.id
    }

    func selectProject(_ id: UUID) {
        guard state.projects.contains(where: { $0.id == id }) else { return }
        state.selectedProject = id
        _ = save()
    }

    func updateProject(_ id: UUID, save shouldSave: Bool = true, _ edit: (inout FontLabProject) -> Void) {
        guard !readBlocked, let index = state.projects.firstIndex(where: { $0.id == id }) else { return }
        var project = state.projects[index]
        edit(&project)
        guard project.isValid else {
            error = "Font Lab contains invalid project data and was not saved."
            return
        }
        state.projects[index] = project
        if shouldSave { _ = save() }
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
        guard projects.allSatisfy(\.isValid) else {
            error = "The backup contains invalid Font Lab project data."
            return false
        }
        guard !projects.isEmpty else { return true }
        let previous = state
        let suffix = " (imported)"
        let copies = projects.map { project -> FontLabProject in
            var copy = project
            copy.id = UUID()
            copy.name = String(project.name.prefix(max(1, 200 - suffix.count))) + suffix
            return copy
        }
        state.projects.append(contentsOf: copies)
        if state.selectedProject == nil { state.selectedProject = copies.first?.id }
        guard save() else {
            state = previous
            return false
        }
        return true
    }

    @discardableResult func save() -> Bool {
        pendingSave?.cancel()
        pendingSave = nil
        guard !readBlocked else { return false }
        guard state.isValid else {
            error = "Font Lab contains invalid project data and was not saved."
            return false
        }
        do {
            let folder = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(state)
            try LibraryBackupTools.preserve(url)
            if FileManager.default.fileExists(atPath: url.path) {
                let existing = try Data(contentsOf: url)
                try existing.write(to: url.appendingPathExtension("backup"), options: .atomic)
            }
            try data.write(to: url, options: .atomic)
            savedAt = Date()
            error = ""
            return true
        } catch {
            self.error = "Font Lab could not be saved. " + error.localizedDescription
            return false
        }
    }

    /// Coalesces rapid UI edits so sliders and text entry do not rewrite and
    /// back up the entire project file for every intermediate value.
    func scheduleSave(after delay: TimeInterval = 0.35) {
        guard !readBlocked else { return }
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in _ = self?.save() }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    func flushPendingSave() {
        guard pendingSave != nil else { return }
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
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("FontShelf-FontLabSelfTest-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
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
        guard loaded.selectedProject?.completedCount == 1 else { throw SelfTestError.failed("Glyph completion was not restored.") }
        guard loaded.selectedProject?.name == "Untitled font" else { throw SelfTestError.failed("The safe project name did not round-trip.") }
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("Backups").path) else {
            throw SelfTestError.failed("Font Lab did not create an automatic state backup.")
        }

        let importFile = root.appendingPathComponent("imported-font-lab.json")
        let importStore = FontLabStore(url: importFile)
        guard importStore.importProjects(loaded.state.projects),
              importStore.state.projects.count == 1,
              importStore.state.projects[0].id != id,
              importStore.state.projects[0].name == "Untitled font (imported)",
              importStore.state.projects[0].glyphs["A"] == glyph else {
            throw SelfTestError.failed("Font Lab backup projects did not import as independent copies.")
        }

        let corruptFile = root.appendingPathComponent("corrupt.json")
        let corruptData = Data("{ definitely-not-json".utf8)
        try corruptData.write(to: corruptFile, options: .atomic)
        let corruptStore = FontLabStore(url: corruptFile)
        guard corruptStore.readBlocked, !corruptStore.save() else { throw SelfTestError.failed("A corrupt project was not write-blocked.") }
        guard try Data(contentsOf: corruptFile) == corruptData else { throw SelfTestError.failed("A corrupt project was overwritten.") }

        guard (try FontLabImportAPI.request(sourceURL: URL(fileURLWithPath: "/tmp/glyph.svg"), targetCharacter: "A")).format == .svg else {
            throw SelfTestError.failed("SVG import request validation failed.")
        }
        let legacyPoint = try JSONDecoder().decode(FontLabPoint.self, from: Data("{\"x\":0.2,\"y\":0.3}".utf8))
        guard legacyPoint.isValid, legacyPoint.pressure == nil, legacyPoint.tiltX == nil, legacyPoint.tiltY == nil else {
            throw SelfTestError.failed("Pre-pressure Font Lab points are no longer backward compatible.")
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
    }
}

struct FontLabView: View {
    @ObservedObject private var library: Library
    @ObservedObject private var store: FontLabStore
    @Binding private var sidebarCollapsed: Bool
    @State private var selectedCharacter = "A"
    @State private var strokeWidth = 0.026
    @State private var drawingTool = FontLabDrawingTool.pen
    @State private var smoothing = FontLabSmoothingLevel.gentle
    @State private var usesTabletPressure = true
    @State private var tabletInputDetected = false
    @State private var showInputHelp = false
    @State private var showMetricsGuide = false
    @State private var clearRequest: ClearRequest?

    private struct ClearRequest: Identifiable {
        let id = UUID()
        let projectID: UUID
        let glyph: FontLabGlyph
    }

    init(library: Library, sidebarCollapsed: Binding<Bool>) {
        self.library = library
        _sidebarCollapsed = sidebarCollapsed
        _store = ObservedObject(wrappedValue: library.fontLab)
    }

    private var project: FontLabProject? { store.selectedProject }

    var body: some View {
        HStack(spacing: 0) {
            if !sidebarCollapsed {
                WorkspaceSidebarShell { projectSidebar }
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
            Group {
                if let project {
                    projectWorkspace(project)
                } else {
                    emptyState
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            if let project = store.selectedProject, !project.characters.contains(selectedCharacter) {
                selectedCharacter = project.characters.first ?? "A"
            }
        }
        .onChange(of: store.state.selectedProject) { _ in
            if let project = store.selectedProject, !project.characters.contains(selectedCharacter) {
                selectedCharacter = project.characters.first ?? "A"
            }
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
        .sheet(isPresented: $showMetricsGuide) {
            let currentProject = store.selectedProject
            let currentGlyph = currentProject?.glyphs[selectedCharacter] ?? FontLabGlyph(character: selectedCharacter)
            FontLabMetricsGuideSheet(metrics: currentProject?.metrics ?? FontLabMetrics(), glyph: currentGlyph)
        }
        .onDisappear { store.flushPendingSave() }
        .accessibilityIdentifier("font-lab-workspace")
    }

    private var projectSidebar: some View {
        VStack(alignment: .leading, spacing: 6) {
            WorkspaceSidebarHeader(library: library, collapsed: $sidebarCollapsed)
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("FONT LAB").font(.caption).foregroundStyle(.secondary)
                        Text("Draw and test letterforms").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { _ = store.addProject(name: "") } label: { Image(systemName: "plus") }
                        .buttonStyle(.plain).help("New Font Lab project").disabled(store.readBlocked)
                }
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
                        }
                    }
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

    private func projectWorkspace(_ project: FontLabProject) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                TextField("Project name", text: projectNameBinding(project.id))
                    .font(.system(size: 22, weight: .semibold)).textFieldStyle(.plain)
                    .onSubmit { store.flushPendingSave() }
                    .disabled(store.readBlocked)
                Spacer()
                Text("\(project.completedCount)/\(project.characters.count) glyphs")
                    .font(.caption).foregroundStyle(.secondary)
                Menu {
                    Button("SVG tracing — planned") { explainImport(.svg) }
                    Button("PNG / Procreate tracing — planned") { explainImport(.png) }
                    Divider()
                    Button("Blend two or three fonts — research") {
                        store.status = "Font blending needs outline compatibility, interpolation, and license safeguards before it can create truthful results. It is on the Font Lab research path; no font data was changed."
                    }
                } label: { Label("Roadmap", systemImage: "map") }
                    .disabled(store.readBlocked)
                Menu {
                    Button("Export \(selectedCharacter) as SVG…") { exportGlyphSVG(project) }
                        .disabled(project.glyphs[selectedCharacter]?.hasArtwork != true)
                    Divider()
                    Button("Export installable OTF — planned") { }
                        .disabled(true)
                } label: { Label("Export", systemImage: "square.and.arrow.up") }
                    .disabled(store.readBlocked)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .padding(.leading, sidebarCollapsed ? WorkspaceSidebarLayout.revealWidth + 8 : 0)
            if !store.error.isEmpty {
                Text(store.error).font(.caption).foregroundStyle(.orange).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20).padding(.bottom, 10)
                    .padding(.leading, sidebarCollapsed ? WorkspaceSidebarLayout.revealWidth + 8 : 0)
            } else if !store.status.isEmpty {
                Text(store.status).font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20).padding(.bottom, 10)
                    .padding(.leading, sidebarCollapsed ? WorkspaceSidebarLayout.revealWidth + 8 : 0)
            }
            Text("Drawn glyphs can be exported as SVG now. Installable OTF generation is a later step.")
                .font(.caption2).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20).padding(.bottom, 9)
                .padding(.leading, sidebarCollapsed ? WorkspaceSidebarLayout.revealWidth + 8 : 0)
            Divider()
            GeometryReader { proxy in
                ScrollView([.horizontal, .vertical]) {
                    VStack(spacing: 0) {
                        HStack(spacing: 0) {
                            characterBrowser(project)
                            Divider()
                            glyphEditor(project)
                        }
                        .frame(height: max(520, proxy.size.height - 160))
                        Divider()
                        preview(project)
                    }
                    .frame(minWidth: max(930, proxy.size.width), alignment: .topLeading)
                }
            }
        }
    }

    private func characterBrowser(_ project: FontLabProject) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CHARACTERS").font(.system(size: 10, weight: .semibold)).tracking(0.8).foregroundStyle(.secondary)
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 6) {
                    ForEach(project.characters, id: \.self) { character in
                        let complete = project.glyphs[character]?.hasArtwork == true
                        Button { selectedCharacter = character } label: {
                            ZStack(alignment: .topTrailing) {
                                Text(character).font(.system(size: 18, design: .serif)).frame(maxWidth: .infinity, minHeight: 34)
                                if complete { Circle().fill(Color.green).frame(width: 6, height: 6).padding(4) }
                            }
                            .background(selectedCharacter == character ? ShelfPalette.indiaYellow.opacity(0.22) : Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 7))
                            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(selectedCharacter == character ? ShelfPalette.indiaYellow : Color.primary.opacity(0.08)))
                        }
                        .buttonStyle(.plain).accessibilityLabel("\(character), \(complete ? "drawn" : "empty")")
                    }
                }
            }
        }
        .padding(16).frame(width: 270).frame(maxHeight: .infinity, alignment: .topLeading)
    }

    private func glyphEditor(_ project: FontLabProject) -> some View {
        let glyph = project.glyphs[selectedCharacter] ?? FontLabGlyph(character: selectedCharacter)
        return HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Draw \(selectedCharacter)").font(.title3.weight(.semibold))
                    Spacer()
                    Button("Undo stroke") { undoStroke(glyph, projectID: project.id) }.disabled(glyph.strokes.isEmpty || store.readBlocked)
                    Button("Clear", role: .destructive) { clearRequest = ClearRequest(projectID: project.id, glyph: glyph) }
                        .disabled(glyph.strokes.isEmpty || store.readBlocked)
                }
                FontLabGlyphCanvas(
                    glyph: glyph,
                    metrics: project.metrics,
                    strokeWidth: strokeWidth,
                    tool: drawingTool,
                    smoothing: smoothing,
                    usesTabletPressure: usesTabletPressure,
                    onTabletInput: { tabletInputDetected = true }
                ) { editedGlyph in
                    store.setGlyph(editedGlyph, in: project.id, save: true)
                }
                .frame(minWidth: 340, minHeight: 340)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.12)))
                VStack(alignment: .leading, spacing: 9) {
                    HStack(spacing: 12) {
                        Picker("Tool", selection: $drawingTool) {
                            ForEach(FontLabDrawingTool.allCases) { tool in
                                Label(tool.title, systemImage: tool.systemImage).tag(tool)
                            }
                        }
                        .labelsHidden().pickerStyle(.segmented).frame(width: 154)
                        Divider().frame(height: 22)
                        Text(drawingTool == .pen ? "Stroke" : "Eraser size").font(.caption).foregroundStyle(.secondary)
                        Slider(value: $strokeWidth, in: 0.008...0.07).frame(maxWidth: 170)
                        Text(strokeWidth.formatted(.number.precision(.fractionLength(3))))
                            .font(.caption2.monospacedDigit()).foregroundStyle(.secondary).frame(width: 38, alignment: .trailing)
                    }
                    HStack(spacing: 14) {
                        Picker("Smoothing", selection: $smoothing) {
                            ForEach(FontLabSmoothingLevel.allCases) { level in Text(level.title).tag(level) }
                        }
                        .pickerStyle(.menu).frame(width: 150)
                        Toggle("Pressure", isOn: $usesTabletPressure)
                            .toggleStyle(.switch).controlSize(.small).disabled(drawingTool == .eraser)
                        Spacer(minLength: 4)
                        Button { showInputHelp.toggle() } label: {
                            Label(tabletInputDetected ? "Tablet active" : "Tablet & iPad", systemImage: tabletInputDetected ? "checkmark.circle.fill" : "ipad.and.apple.pencil")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(tabletInputDetected ? Color.green : Color.secondary)
                        .help("Set up Apple Pencil with Sidecar or a macOS drawing tablet")
                        .popover(isPresented: $showInputHelp, arrowEdge: .bottom) { FontLabInputHelp() }
                    }
                    Text(drawingTool == .pen ? "Draw with a mouse, trackpad, Apple Pencil through Sidecar, or a macOS-compatible pen tablet. ⌘Z removes the last stroke." : "Drag across a line to erase that entire stroke.")
                        .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            }
            metricsPanel(project, glyph: glyph)
        }
        .padding(20).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func metricsPanel(_ project: FontLabProject, glyph: FontLabGlyph) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("METRICS").font(.system(size: 10, weight: .semibold)).tracking(0.8).foregroundStyle(.secondary)
                Spacer()
                Button { showMetricsGuide = true } label: { Label("Guide", systemImage: "questionmark.circle") }
                    .buttonStyle(.plain).font(.caption).help("Learn what each type metric controls")
            }
            FontLabMetricExample(metrics: project.metrics, glyph: glyph)
                .frame(height: 118)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color.primary.opacity(0.1)))
            Text("H reaches cap height; x reaches x-height. Both sit on the baseline.")
                .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            metricSlider("Baseline", value: metricBinding(project.id, kind: .baseline), range: 0.04...0.42)
            metricSlider("x-height", value: metricBinding(project.id, kind: .xHeight), range: 0.12...0.88)
            metricSlider("Cap height", value: metricBinding(project.id, kind: .capHeight), range: 0.22...0.96)
            Divider()
            metricSlider("Left bearing", value: bearingBinding(glyph, projectID: project.id, left: true), range: 0...0.4)
            metricSlider("Right bearing", value: bearingBinding(glyph, projectID: project.id, left: false), range: 0...0.4)
            Text("Measurements are proportions of the drawing area. Side bearings apply to this glyph.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(16).frame(width: 232).shelfGlass(radius: 14)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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
                Text("PREVIEW").font(.system(size: 10, weight: .semibold)).tracking(0.8).foregroundStyle(.secondary)
                Spacer()
                Text("Drawn glyphs only; outlined tiles mark missing characters.").font(.caption).foregroundStyle(.secondary)
            }
            TextField("Preview text", text: previewBinding(project.id)).textFieldStyle(.roundedBorder)
                .onSubmit { store.flushPendingSave() }.disabled(store.readBlocked)
            FontLabPreviewCanvas(text: project.previewText, glyphs: project.glyphs, metrics: project.metrics)
                .frame(height: 118).background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.1)))
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "pencil.and.outline").font(.system(size: 42)).foregroundStyle(.secondary)
            Text(store.readBlocked ? "Font Lab data needs attention" : "Start a Font Lab project").font(.title2)
            Text(store.error.isEmpty ? "Draw characters one at a time, tune their metrics, preview them in words, and export finished glyphs as SVG. Tracing, font blending, and installable OTF output are clearly marked as later work." : store.error)
                .foregroundStyle(Color(nsColor: store.error.isEmpty ? .secondaryLabelColor : .systemOrange)).multilineTextAlignment(.center).frame(maxWidth: 520)
            if !store.readBlocked { Button("New project") { _ = store.addProject(name: "") } }
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
            store.setGlyph(glyph, in: projectID, save: false)
            store.scheduleSave()
        })
    }

    private func undoStroke(_ glyph: FontLabGlyph, projectID: UUID) {
        var edited = glyph
        if !edited.strokes.isEmpty { edited.strokes.removeLast() }
        store.setGlyph(edited, in: projectID, save: true)
    }

    private func clearGlyph(_ glyph: FontLabGlyph, projectID: UUID) {
        var edited = glyph
        edited.strokes = []
        edited.importedFrom = nil
        edited.importFormat = nil
        store.setGlyph(edited, in: projectID, save: true)
    }

    private func explainImport(_ format: FontLabImportFormat) {
        store.status = "\(format.displayName) artwork import is prepared as a tracing API, but tracing is not enabled yet. Your artwork and font library were not changed."
    }

    private func exportGlyphSVG(_ project: FontLabProject) {
        guard let glyph = project.glyphs[selectedCharacter], glyph.hasArtwork else {
            store.status = "Draw \(selectedCharacter) before exporting it."
            return
        }
        let panel = NSSavePanel()
        panel.title = "Export drawn glyph as SVG"
        panel.prompt = "Export SVG"
        panel.nameFieldStringValue = "\(safeFilename(project.name))-\(safeFilename(selectedCharacter)).svg"
        panel.allowedContentTypes = [.svg]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do {
            try FontLabSVGExporter.data(projectName: project.name, glyph: glyph, metrics: project.metrics).write(to: destination, options: .atomic)
            store.status = "Exported \(selectedCharacter) as \(destination.lastPathComponent)."
        } catch {
            store.error = "The SVG could not be exported. " + error.localizedDescription
        }
    }

    private func safeFilename(_ value: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>").union(.newlines).union(.controlCharacters)
        let cleaned = value.components(separatedBy: invalid).filter { !$0.isEmpty }.joined(separator: "-")
        return cleaned.isEmpty ? "glyph" : String(cleaned.prefix(80))
    }
}

private struct FontLabInputHelp: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Drawing input", systemImage: "ipad.and.apple.pencil")
                .font(.headline)
            inputSection(
                "Apple Pencil + iPad",
                icon: "ipad",
                text: "Set up Sidecar in macOS Displays, wirelessly or over USB, then put the FontShelf window on the iPad. Sidecar sends Apple Pencil input to the Mac app."
            )
            inputSection(
                "Pen tablet",
                icon: "rectangle.and.pencil.and.ellipsis",
                text: "Connect the tablet as its maker recommends and install its macOS driver when required. FontShelf uses the standard tablet events macOS provides."
            )
            Divider()
            Text("FontShelf does not pair Bluetooth or USB hardware itself. With Pressure enabled, reported pressure changes the round pen's thickness. Reported tilt is retained with the stroke, although the current round nib does not rotate with tilt.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(18).frame(width: 390)
    }

    private func inputSection(_ title: String, icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: icon).frame(width: 24).foregroundStyle(ShelfPalette.ink)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(text).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
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
            Text("Tip: draw H and O to establish capitals, then x, n, o, and p for lowercase proportions and spacing before completing the full character set.")
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

        drawRotatedLabel("LEFT BEARING", at: NSPoint(x: leftX + 7, y: rect.midY))
        drawRotatedLabel("RIGHT BEARING", at: NSPoint(x: rightX - 7, y: rect.midY))
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
    let smoothing: FontLabSmoothingLevel
    let usesTabletPressure: Bool
    let onTabletInput: () -> Void
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
        view.smoothing = smoothing
        view.usesTabletPressure = usesTabletPressure
        view.onTabletInput = { context.coordinator.onTabletInput() }
        view.onCommit = { context.coordinator.onCommit($0) }
        return view
    }

    func updateNSView(_ view: FontLabDrawingNSView, context: Context) {
        context.coordinator.onTabletInput = onTabletInput
        context.coordinator.onCommit = onCommit
        if !view.isDrawing { view.glyph = glyph }
        view.metrics = metrics
        view.strokeWidth = strokeWidth
        view.tool = tool
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

private final class FontLabDrawingNSView: NSView {
    var glyph = FontLabGlyph(character: "A") { didSet { needsDisplay = true } }
    var metrics = FontLabMetrics() { didSet { needsDisplay = true } }
    var strokeWidth = 0.026
    var tool = FontLabDrawingTool.pen
    var smoothing = FontLabSmoothingLevel.gentle
    var usesTabletPressure = true
    var onTabletInput: (() -> Void)?
    var onCommit: ((FontLabGlyph) -> Void)?
    private(set) var isDrawing = false
    private var gestureChangedGlyph = false
    private var reportedTabletInput = false

    override var acceptsFirstResponder: Bool { true }
    private var drawingRect: NSRect { bounds.insetBy(dx: 24, dy: 24) }

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
        drawHorizontalLabel("BASELINE", at: metrics.baseline, color: .systemOrange)
        drawHorizontalLabel("x-HEIGHT", at: metrics.xHeight, color: .secondaryLabelColor)
        drawHorizontalLabel("CAP HEIGHT", at: metrics.capHeight, color: .secondaryLabelColor)
        drawVerticalLabel("LEFT BEARING", at: glyph.leftSideBearing, inwardOffset: 9)
        drawVerticalLabel("RIGHT BEARING", at: 1 - glyph.rightSideBearing, inwardOffset: -9)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        guard let point = sampledPoint(for: event) else { return }
        isDrawing = true
        gestureChangedGlyph = false
        switch tool {
        case .pen:
            guard glyph.strokes.count < 10_000 else { isDrawing = false; return }
            glyph.strokes.append(FontLabStroke(points: [point], width: min(max(strokeWidth, 0.002), 0.2)))
            gestureChangedGlyph = true
        case .eraser:
            erase(at: point)
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
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard isDrawing else { return }
        isDrawing = false
        if gestureChangedGlyph { onCommit?(glyph) }
        gestureChangedGlyph = false
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        if handleUndoShortcut(event) { return }
        super.keyDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if window?.firstResponder === self, handleUndoShortcut(event) { return true }
        return super.performKeyEquivalent(with: event)
    }

    private func handleUndoShortcut(_ event: NSEvent) -> Bool {
        let editingModifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard editingModifiers == .command,
              event.charactersIgnoringModifiers?.lowercased() == "z", !glyph.strokes.isEmpty else { return false }
        glyph.strokes.removeLast()
        onCommit?(glyph)
        needsDisplay = true
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

private struct FontLabPreviewCanvas: NSViewRepresentable {
    let text: String
    let glyphs: [String: FontLabGlyph]
    let metrics: FontLabMetrics

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
        view.needsDisplay = true
    }
}

private final class FontLabPreviewNSView: NSView {
    var text = ""
    var glyphs: [String: FontLabGlyph] = [:]
    var metrics = FontLabMetrics()

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.textBackgroundColor.setFill()
        bounds.fill()
        let characters = text.map(String.init)
        guard !characters.isEmpty else { return }
        let nominalHeight: CGFloat = min(96, max(32, bounds.height - 24))
        let nominalWidth = estimatedWidth(characters, em: nominalHeight)
        let em = nominalWidth > bounds.width - 24 ? nominalHeight * max(0.2, (bounds.width - 24) / nominalWidth) : nominalHeight
        var x: CGFloat = 12
        let originY = max(8, (bounds.height - em) / 2)
        let baselineY = originY + CGFloat(metrics.baseline) * em
        let guide = NSBezierPath()
        guide.move(to: NSPoint(x: 10, y: baselineY))
        guide.line(to: NSPoint(x: bounds.maxX - 10, y: baselineY))
        guide.setLineDash([3, 5], count: 2, phase: 0)
        NSColor.separatorColor.setStroke()
        guide.stroke()

        for character in characters {
            if character == " " { x += em * 0.3; continue }
            let glyph = glyphs[character]
            let left = CGFloat(glyph?.leftSideBearing ?? 0.08) * em
            let right = CGFloat(glyph?.rightSideBearing ?? 0.08) * em
            let inkWidth = em * 0.62
            if let glyph, glyph.hasArtwork {
                let rect = NSRect(x: x + left, y: originY, width: inkWidth, height: em)
                fontLabDrawStrokes(glyph.strokes, in: rect, color: .labelColor)
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
        24 + characters.reduce(CGFloat.zero) { result, character in
            if character == " " { return result + em * 0.3 }
            let glyph = glyphs[character]
            return result + em * (0.62 + CGFloat(glyph?.leftSideBearing ?? 0.08) + CGFloat(glyph?.rightSideBearing ?? 0.08))
        }
    }
}

private func fontLabDrawStrokes(_ strokes: [FontLabStroke], in rect: NSRect, color: NSColor) {
    color.setStroke()
    color.setFill()
    for stroke in strokes where !stroke.points.isEmpty {
        let mapped = stroke.points.map { NSPoint(x: rect.minX + CGFloat($0.x) * rect.width, y: rect.minY + CGFloat($0.y) * rect.height) }
        let baseWidth = max(1, CGFloat(stroke.width) * min(rect.width, rect.height))
        if mapped.count == 1 {
            let width = baseWidth * CGFloat(FontLabDrawingOperations.pressureScale(for: stroke.points[0]))
            NSBezierPath(ovalIn: NSRect(x: mapped[0].x - width / 2, y: mapped[0].y - width / 2, width: width, height: width)).fill()
        } else if stroke.points.contains(where: { $0.pressure != nil }) {
            for index in 1..<mapped.count {
                let startScale = FontLabDrawingOperations.pressureScale(for: stroke.points[index - 1])
                let endScale = FontLabDrawingOperations.pressureScale(for: stroke.points[index])
                let path = NSBezierPath()
                path.move(to: mapped[index - 1])
                path.line(to: mapped[index])
                path.lineWidth = baseWidth * CGFloat((startScale + endScale) / 2)
                path.lineCapStyle = .round
                path.lineJoinStyle = .round
                path.stroke()
            }
        } else {
            let path = NSBezierPath()
            path.move(to: mapped[0])
            for point in mapped.dropFirst() { path.line(to: point) }
            path.lineWidth = baseWidth
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.stroke()
        }
    }
}
