import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct FontLabPoint: Codable, Equatable {
    var x: Double
    var y: Double

    var isValid: Bool { x.isFinite && y.isFinite && (0...1).contains(x) && (0...1).contains(y) }
}

struct FontLabStroke: Codable, Identifiable, Equatable {
    var id = UUID()
    var points: [FontLabPoint] = []
    var width = 0.026

    var isValid: Bool {
        !points.isEmpty && points.count <= 50_000 && width.isFinite && (0.002...0.2).contains(width) && points.allSatisfy(\.isValid)
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
            let width = number(stroke.width * 1_000)
            if stroke.points.count == 1 {
                return "  <circle cx=\"\(number(first.x * 1_000))\" cy=\"\(number((1 - first.y) * 1_000))\" r=\"\(number(stroke.width * 500))\" fill=\"#111111\"/>"
            }
            let points = stroke.points.map { "\(number($0.x * 1_000)),\(number((1 - $0.y) * 1_000))" }.joined(separator: " ")
            return "  <polyline points=\"\(points)\" fill=\"none\" stroke=\"#111111\" stroke-width=\"\(width)\" stroke-linecap=\"round\" stroke-linejoin=\"round\"/>"
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

    init(url: URL) {
        self.url = url
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
        let svg = FontLabSVGExporter.string(projectName: "Test & face", glyph: glyph, metrics: FontLabMetrics())
        guard svg == FontLabSVGExporter.string(projectName: "Test & face", glyph: glyph, metrics: FontLabMetrics()), svg.contains("<polyline"), svg.contains("Test &amp; face") else {
            throw SelfTestError.failed("Deterministic SVG export failed.")
        }
    }
}

struct FontLabView: View {
    @ObservedObject private var library: Library
    @ObservedObject private var store: FontLabStore
    @Binding private var sidebarCollapsed: Bool
    @State private var selectedCharacter = "A"
    @State private var strokeWidth = 0.026
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
            .padding(.horizontal, 20).padding(.vertical, 14)
            if !store.error.isEmpty {
                Text(store.error).font(.caption).foregroundStyle(.orange).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20).padding(.bottom, 10)
            } else if !store.status.isEmpty {
                Text(store.status).font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20).padding(.bottom, 10)
            }
            Text("Drawn glyphs can be exported as SVG now. Installable OTF generation is a later step.")
                .font(.caption2).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20).padding(.bottom, 9)
            Divider()
            HStack(spacing: 0) {
                characterBrowser(project)
                Divider()
                glyphEditor(project)
            }
            Divider()
            preview(project)
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
        .padding(16).frame(width: 270)
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
                FontLabGlyphCanvas(glyph: glyphBinding(glyph, projectID: project.id), metrics: project.metrics, strokeWidth: strokeWidth) {
                    _ = store.save()
                }
                .frame(minWidth: 340, minHeight: 340)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.12)))
                HStack {
                    Text("Stroke").font(.caption).foregroundStyle(.secondary)
                    Slider(value: $strokeWidth, in: 0.008...0.07).frame(maxWidth: 180)
                    Text("Use a mouse or click-drag on a trackpad.").font(.caption).foregroundStyle(.secondary)
                }
            }
            metricsPanel(project, glyph: glyph)
        }
        .padding(20).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func metricsPanel(_ project: FontLabProject, glyph: FontLabGlyph) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("METRICS").font(.system(size: 10, weight: .semibold)).tracking(0.8).foregroundStyle(.secondary)
            metricSlider("Baseline", value: metricBinding(project.id, kind: .baseline), range: 0.04...0.42)
            metricSlider("x-height", value: metricBinding(project.id, kind: .xHeight), range: 0.12...0.88)
            metricSlider("Cap height", value: metricBinding(project.id, kind: .capHeight), range: 0.22...0.96)
            Divider()
            metricSlider("Left bearing", value: bearingBinding(glyph, projectID: project.id, left: true), range: 0...0.4)
            metricSlider("Right bearing", value: bearingBinding(glyph, projectID: project.id, left: false), range: 0...0.4)
            Text("Measurements are proportions of the drawing area. Side bearings apply to this glyph.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(16).frame(width: 210).shelfGlass(radius: 14)
    }

    private func metricSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack { Text(title).font(.caption); Spacer(); Text(value.wrappedValue.formatted(.number.precision(.fractionLength(2)))).font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
            Slider(value: value, in: range)
        }
    }

    private func preview(_ project: FontLabProject) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("PREVIEW").font(.system(size: 10, weight: .semibold)).tracking(0.8).foregroundStyle(.secondary)
                Spacer()
                Text("Drawn glyphs only; outlined tiles mark missing characters.").font(.caption).foregroundStyle(.secondary)
            }
            TextField("Preview text", text: previewBinding(project.id)).textFieldStyle(.roundedBorder).disabled(store.readBlocked)
            FontLabPreviewCanvas(text: project.previewText, glyphs: project.glyphs, metrics: project.metrics)
                .frame(height: 118).background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
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
            store.updateProject(projectID) { project in
                switch kind {
                case .baseline: project.metrics.setBaseline(value)
                case .xHeight: project.metrics.setXHeight(value)
                case .capHeight: project.metrics.setCapHeight(value)
                }
            }
        })
    }

    private func projectNameBinding(_ projectID: UUID) -> Binding<String> {
        Binding(get: { store.state.projects.first(where: { $0.id == projectID })?.name ?? "" }, set: { name in
            store.renameProject(projectID, to: name)
        })
    }

    private func previewBinding(_ projectID: UUID) -> Binding<String> {
        Binding(get: { store.state.projects.first(where: { $0.id == projectID })?.previewText ?? "" }, set: { text in
            store.updateProject(projectID) { $0.previewText = String(text.prefix(2_000)) }
        })
    }

    private func glyphBinding(_ fallback: FontLabGlyph, projectID: UUID) -> Binding<FontLabGlyph> {
        Binding(get: { store.state.projects.first(where: { $0.id == projectID })?.glyphs[fallback.character] ?? fallback }, set: {
            store.setGlyph($0, in: projectID, save: false)
        })
    }

    private func bearingBinding(_ fallback: FontLabGlyph, projectID: UUID, left: Bool) -> Binding<Double> {
        Binding(get: {
            let glyph = store.state.projects.first(where: { $0.id == projectID })?.glyphs[fallback.character] ?? fallback
            return left ? glyph.leftSideBearing : glyph.rightSideBearing
        }, set: { value in
            var glyph = store.state.projects.first(where: { $0.id == projectID })?.glyphs[fallback.character] ?? fallback
            if left { glyph.leftSideBearing = value } else { glyph.rightSideBearing = value }
            store.setGlyph(glyph, in: projectID, save: true)
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

private struct FontLabGlyphCanvas: NSViewRepresentable {
    @Binding var glyph: FontLabGlyph
    let metrics: FontLabMetrics
    let strokeWidth: Double
    let onCommit: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(glyph: $glyph, onCommit: onCommit) }

    func makeNSView(context: Context) -> FontLabDrawingNSView {
        let view = FontLabDrawingNSView()
        view.glyph = glyph
        view.metrics = metrics
        view.strokeWidth = strokeWidth
        view.onChange = { context.coordinator.glyph.wrappedValue = $0 }
        view.onCommit = { context.coordinator.onCommit() }
        return view
    }

    func updateNSView(_ view: FontLabDrawingNSView, context: Context) {
        context.coordinator.glyph = $glyph
        context.coordinator.onCommit = onCommit
        if !view.isDrawing { view.glyph = glyph }
        view.metrics = metrics
        view.strokeWidth = strokeWidth
        view.needsDisplay = true
    }

    final class Coordinator {
        var glyph: Binding<FontLabGlyph>
        var onCommit: () -> Void
        init(glyph: Binding<FontLabGlyph>, onCommit: @escaping () -> Void) {
            self.glyph = glyph
            self.onCommit = onCommit
        }
    }
}

private final class FontLabDrawingNSView: NSView {
    var glyph = FontLabGlyph(character: "A") { didSet { needsDisplay = true } }
    var metrics = FontLabMetrics() { didSet { needsDisplay = true } }
    var strokeWidth = 0.026
    var onChange: ((FontLabGlyph) -> Void)?
    var onCommit: (() -> Void)?
    private(set) var isDrawing = false

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
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        guard let point = normalizedPoint(for: event) else { return }
        isDrawing = true
        glyph.strokes.append(FontLabStroke(points: [point], width: strokeWidth))
        onChange?(glyph)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDrawing, let point = normalizedPoint(for: event), !glyph.strokes.isEmpty else { return }
        if let previous = glyph.strokes[glyph.strokes.count - 1].points.last {
            let dx = point.x - previous.x
            let dy = point.y - previous.y
            if dx * dx + dy * dy < 0.000_01 { return }
        }
        glyph.strokes[glyph.strokes.count - 1].points.append(point)
        onChange?(glyph)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard isDrawing else { return }
        if let point = normalizedPoint(for: event), !glyph.strokes.isEmpty, glyph.strokes[glyph.strokes.count - 1].points.count == 1 {
            glyph.strokes[glyph.strokes.count - 1].points.append(point)
            onChange?(glyph)
        }
        isDrawing = false
        onCommit?()
        needsDisplay = true
    }

    private func normalizedPoint(for event: NSEvent) -> FontLabPoint? {
        let point = convert(event.locationInWindow, from: nil)
        let rect = drawingRect
        guard rect.width > 0, rect.height > 0, rect.contains(point) else { return nil }
        return FontLabPoint(x: min(max(Double((point.x - rect.minX) / rect.width), 0), 1), y: min(max(Double((point.y - rect.minY) / rect.height), 0), 1))
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
}

private struct FontLabPreviewCanvas: NSViewRepresentable {
    let text: String
    let glyphs: [String: FontLabGlyph]
    let metrics: FontLabMetrics

    func makeNSView(context: Context) -> FontLabPreviewNSView { FontLabPreviewNSView() }
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
        let width = max(1, CGFloat(stroke.width) * min(rect.width, rect.height))
        if mapped.count == 1 {
            NSBezierPath(ovalIn: NSRect(x: mapped[0].x - width / 2, y: mapped[0].y - width / 2, width: width, height: width)).fill()
        } else {
            let path = NSBezierPath()
            path.move(to: mapped[0])
            for point in mapped.dropFirst() { path.line(to: point) }
            path.lineWidth = width
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.stroke()
        }
    }
}
