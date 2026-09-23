import SwiftUI
import AppKit
import CoreText
import UniformTypeIdentifiers

struct LibraryBackup: Codable {
    var version = 1
    var library: SavedLibrary
    var pro: ProState
    var spaces: StudioState
    /// Optional so version-1 backups created before Letterform Editor remain decodable.
    var fontLab: FontLabState? = nil
}
enum LibraryBackupTools {
    static func preserve(_ url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let directory = url.deletingLastPathComponent().appendingPathComponent("Backups")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let day = ISO8601DateFormatter().string(from: Date()).prefix(10)
        let target = directory.appendingPathComponent(String(day) + "-" + url.lastPathComponent)
        if !FileManager.default.fileExists(atPath: target.path) { try FileManager.default.copyItem(at: url, to: target) }
    }
    static func export(_ library: Library) {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "Typefield-library.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            guard !library.fontLab.readBlocked else { throw CocoaError(.fileReadCorruptFile) }
            let backup = LibraryBackup(library: library.saved, pro: library.pro, spaces: library.studio.state, fontLab: library.fontLab.state)
            try JSONEncoder().encode(backup).write(to: url, options: .atomic)
            library.message = "Library, Spaces, and Letterform Editor backup exported. Font files are not included."
        } catch { library.message = error.localizedDescription }
    }
    static func merge(_ backup: LibraryBackup, into library: Library) throws {
        let fontLabIsValid = backup.fontLab?.isValid ?? true
        let canImportFontLab = backup.fontLab == nil || !library.fontLab.readBlocked
        guard backup.version == 1, backup.spaces.version == 1, fontLabIsValid, canImportFontLab,
              !library.librarySaveBlocked, !library.proSaveBlocked, !library.studio.readBlocked,
              backup.spaces.spaces.allSatisfy({ $0.boards.allSatisfy(\.isValid) }) else { throw CocoaError(.fileReadCorruptFile) }
        library.saved.favorites.formUnion(backup.library.favorites)
        for (key, values) in backup.library.collections { library.saved.collections[key, default: []].formUnion(values) }
        library.saved.overrides.merge(backup.library.overrides) { existing, _ in existing }
        if let importedUsage = backup.library.fontUsage {
            var usage = library.saved.fontUsage ?? [:]
            for (name, imported) in importedUsage {
                if let existing = usage[name] { usage[name] = FontUsageRecord(lastAppliedAt: max(existing.lastAppliedAt, imported.lastAppliedAt), applicationCount: max(existing.applicationCount, imported.applicationCount)) }
                else { usage[name] = imported }
            }
            library.saved.fontUsage = usage
        }
        library.pro.familyOverrides.merge(backup.pro.familyOverrides) { existing, _ in existing }
        library.pro.mainPreviews.merge(backup.pro.mainPreviews) { existing, _ in existing }
        library.pro.notes.merge(backup.pro.notes) { existing, _ in existing }
        library.pro.axes.merge(backup.pro.axes) { existing, _ in existing }
        library.pro.features.merge(backup.pro.features) { existing, _ in existing }
        for (key, tags) in backup.pro.tags { library.pro.tags[key, default: []].formUnion(tags) }
        for var space in backup.spaces.spaces {
            space.id = UUID(); space.name += " (imported)"
            library.studio.state.spaces.append(space)
        }
        guard library.save(), library.savePro() else { throw NSError(domain: "FontShelf", code: 1, userInfo: [NSLocalizedDescriptionKey: "Import may be partially saved. " + library.message]) }
        guard library.studio.save() else { throw NSError(domain: "FontShelf", code: 1, userInfo: [NSLocalizedDescriptionKey: "Import may be partially saved. " + library.studio.error]) }
        if let fontLab = backup.fontLab, !fontLab.projects.isEmpty {
            guard library.fontLab.importProjects(fontLab.projects) else {
                throw NSError(domain: "FontShelf", code: 1, userInfo: [NSLocalizedDescriptionKey: "Import may be partially saved. " + library.fontLab.error])
            }
        }
        library.regroup()
    }
    static func restore(_ library: Library) {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.message = "Merge a Typefield backup. Existing settings are kept; spaces and Letterform Editor projects are imported as copies."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try merge(JSONDecoder().decode(LibraryBackup.self, from: Data(contentsOf: url)), into: library)
            library.message = "Backup merged. Add font folders separately to grant access on this Mac."
        } catch { library.message = "Backup could not be imported: " + error.localizedDescription }
    }
}

/// Moves a pre-sandbox FontShelf support folder into a fresh Store container.
/// The source is chosen in an open panel; saved security scopes cannot be
/// transferred between app identities and must be granted again by the user.
enum StoreMigration {
    static let dataFiles = ["library.json", "pro-library.json", "spaces.json", "font-lab.json"]
    static let stringPreferences = ["appearance", "previewText", "previewInkHex", "previewPaperHex"]
    static let boolPreferences = ["adaptiveGridView", "customPreviewColors", "workspaceSidebarCollapsed"]
    static let numberPreferences = ["previewSize", "studioInspectorWidth", "fontLabCharacterBrowserWidth"]

    static func migrate(from source: URL, to destination: URL) throws -> Int {
        let source = source.standardizedFileURL
        let destination = destination.standardizedFileURL
        func invalid(_ detail: String) -> NSError {
            NSError(domain: "FontShelf.Migration", code: 1, userInfo: [NSLocalizedDescriptionKey: detail])
        }
        guard source != destination, source.lastPathComponent == "FontShelf" else {
            throw invalid("Choose the earlier FontShelf Application Support folder.")
        }
        let fm = FileManager.default
        let present = dataFiles.filter { fm.fileExists(atPath: source.appendingPathComponent($0).path) }
        guard !present.isEmpty else { throw invalid("No FontShelf library or project files were found in that folder.") }
        let googleSource = source.appendingPathComponent("Google Fonts")
        let hasGoogle = fm.fileExists(atPath: googleSource.path)
        guard !dataFiles.contains(where: { fm.fileExists(atPath: destination.appendingPathComponent($0).path) }),
              !fm.fileExists(atPath: destination.appendingPathComponent("Google Fonts").path) else {
            throw invalid("This Typefield container already has saved data. Export a backup before using the separate merge command; migration will not overwrite or duplicate it.")
        }

        var files: [String: Data] = [:]
        for name in present {
            let file = source.appendingPathComponent(name)
            let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else { throw invalid("\(name) is not a regular file.") }
            let data = try Data(contentsOf: file)
            switch name {
            case "library.json":
                var saved = try JSONDecoder().decode(SavedLibrary.self, from: data)
                func remap(_ path: String) -> String {
                    let old = source.path + "/"
                    return path.hasPrefix(old) ? destination.path + "/" + path.dropFirst(old.count) : path
                }
                saved.folders = saved.folders.map(remap)
                saved.autoActivateFolders = saved.autoActivateFolders.map { Set($0.map(remap)) }
                saved.webAssetFolders = saved.webAssetFolders.map { $0.map(remap) }
                files[name] = try JSONEncoder().encode(saved)
            case "pro-library.json": _ = try JSONDecoder().decode(ProState.self, from: data); files[name] = data
            case "spaces.json":
                let state = try JSONDecoder().decode(StudioState.self, from: data)
                guard state.version == 1, state.spaces.allSatisfy({ $0.boards.allSatisfy(\.isValid) }) else { throw invalid("Spaces data is invalid or needs a newer Typefield version.") }
                files[name] = data
            case "font-lab.json":
                let state = try JSONDecoder().decode(FontLabState.self, from: data)
                guard state.isValid else { throw invalid("Letterform Editor data is invalid or needs a newer Typefield version.") }
                files[name] = data
            default: break
            }
        }
        if hasGoogle {
            let values = try googleSource.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isDirectory == true, values.isSymbolicLink != true else { throw invalid("Google Fonts is not a regular folder.") }
            let enumerator = fm.enumerator(at: googleSource, includingPropertiesForKeys: [.isSymbolicLinkKey], options: [])
            while let entry = enumerator?.nextObject() as? URL {
                if try entry.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true {
                    throw invalid("Google Fonts contains a symbolic link. Remove it from the copy before migration.")
                }
            }
        }
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        let stage = destination.appendingPathComponent(".migration-" + UUID().uuidString)
        try fm.createDirectory(at: stage, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: stage) }
        for (name, data) in files { try data.write(to: stage.appendingPathComponent(name), options: .atomic) }
        if hasGoogle { try fm.copyItem(at: googleSource, to: stage.appendingPathComponent("Google Fonts")) }
        var installed: [URL] = []
        do {
            for name in present + (hasGoogle ? ["Google Fonts"] : []) {
                let target = destination.appendingPathComponent(name)
                guard !fm.fileExists(atPath: target.path) else { throw invalid("The destination changed during migration. No existing data was replaced.") }
                try fm.moveItem(at: stage.appendingPathComponent(name), to: target)
                installed.append(target)
            }
        } catch {
            for target in installed { try? fm.removeItem(at: target) }
            throw error
        }
        return present.count + (hasGoogle ? 1 : 0)
    }

    static func chooseSource(for library: Library) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.message = "Quit the earlier FontShelf app, then choose its FontShelf folder in Library/Application Support. Its files will be copied into this empty Store container."
        guard panel.runModal() == .OK, let source = panel.url else { return }
        let alert = NSAlert()
        alert.messageText = "Copy your FontShelf data?"
        alert.informativeText = "Library, Spaces, Letterform Editor and downloaded Google fonts will be copied. The originals stay in place. External font and WOFF2 folders need access granted again. Files outside this folder are not moved."
        alert.addButton(withTitle: "Copy and Quit")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            _ = try migrate(from: source, to: library.saveURL.deletingLastPathComponent())
            NSApp.terminate(nil)
        } catch { library.message = "Migration did not finish: " + error.localizedDescription }
    }

    static func importPreferences(from file: URL, into defaults: UserDefaults = .standard) throws -> Int {
        guard file.lastPathComponent == "local.fontshelf.app.plist",
              let values = try PropertyListSerialization.propertyList(from: Data(contentsOf: file), format: nil) as? [String: Any] else {
            throw NSError(domain: "FontShelf.Migration", code: 2, userInfo: [NSLocalizedDescriptionKey: "Choose the earlier local.fontshelf.app.plist preferences file."])
        }
        var imported = 0
        for key in stringPreferences {
            if defaults.object(forKey: key) == nil, let value = values[key] as? String {
                defaults.set(value, forKey: key); imported += 1
            }
        }
        for key in boolPreferences {
            if defaults.object(forKey: key) == nil, let value = values[key] as? NSNumber {
                defaults.set(value.boolValue, forKey: key); imported += 1
            }
        }
        for key in numberPreferences {
            if defaults.object(forKey: key) == nil, let value = values[key] as? NSNumber, value.doubleValue.isFinite {
                defaults.set(value.doubleValue, forKey: key); imported += 1
            }
        }
        return imported
    }

    static func choosePreferences(for library: Library) {
        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.canChooseFiles = true
        panel.allowedContentTypes = [.propertyList]
        panel.message = "Choose local.fontshelf.app.plist in Library/Preferences. Existing Store preferences are kept."
        guard panel.runModal() == .OK, let file = panel.url else { return }
        do { library.message = "Imported \(try importPreferences(from: file)) earlier preferences. Reopen Typefield to see them everywhere." }
        catch { library.message = "Preferences were not imported: " + error.localizedDescription }
    }
}
struct MetadataTable: View {
    @ObservedObject var library: Library
    var body: some View {
        Table(library.filtered.flatMap(\.faces)) {
            TableColumn("Family") { Text($0.originalFamily) }
            TableColumn("Style") { Text($0.style) }
            TableColumn("Foundry") { Text($0.facts.foundry) }
            TableColumn("Weight") { Text(String($0.facts.weight)) }
            TableColumn("Glyphs") { Text(String($0.facts.glyphCount)) }
            TableColumn("Format") { Text($0.url?.pathExtension.uppercased() ?? "—") }
            TableColumn("File") { face in
                Button(face.url?.lastPathComponent ?? "Unavailable") { if let family = library.families.first(where: { $0.faces.contains { $0.name == face.name } }) { library.detail = family } }.buttonStyle(.plain).help(face.url?.path ?? "")
            }
        }
    }
}
enum SpecimenExporter {
    static func data(faces: [Face], library: Library, sample: String) -> Data {
        let result = NSMutableData()
        var page = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let consumer = CGDataConsumer(data: result as CFMutableData), let context = CGContext(consumer: consumer, mediaBox: &page, nil) else { return Data() }
        for face in faces {
            var cursor = 690.0
            func beginPage() {
                context.beginPDFPage(nil); context.setFillColor(NSColor.white.cgColor); context.fill(page)
                let title = NSAttributedString(string: face.originalFamily + " · " + face.style, attributes: [.font: NSFont.systemFont(ofSize: 14, weight: .semibold), .foregroundColor: NSColor.black])
                context.textPosition = CGPoint(x: 44, y: 746); CTLineDraw(CTLineCreateWithAttributedString(title), context)
                let footer = NSAttributedString(string: "Typefield · " + face.name, attributes: [.font: NSFont.systemFont(ofSize: 9), .foregroundColor: NSColor.darkGray])
                context.textPosition = CGPoint(x: 44, y: 26); CTLineDraw(CTLineCreateWithAttributedString(footer), context)
                cursor = 708
            }
            beginPage()
            for size in [48.0, 36, 24, 18, 12] {
                if cursor < size * 1.5 + 60 { context.endPDFPage(); beginPage() }
                let text = sample.isEmpty ? face.originalFamily : sample
                let name = face.name, axes = library.pro.axes[name] ?? [:], features = library.pro.features[name] ?? [:]
                let font = OpenType.font(name: name, size: size, axes: axes, features: features)
                let value = NSAttributedString(string: text, attributes: [.font: font as NSFont, .foregroundColor: NSColor.black])
                let framesetter = CTFramesetterCreateWithAttributedString(value)
                var offset = 0
                while offset < value.length {
                    let available = cursor - 48
                    let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: offset, length: 0), CGPath(rect: CGRect(x: 44, y: 48, width: 524, height: available), transform: nil), nil)
                    let range = CTFrameGetVisibleStringRange(frame)
                    if range.length == 0 { context.endPDFPage(); beginPage(); continue }
                    CTFrameDraw(frame, context)
                    offset += range.length
                    if offset < value.length { context.endPDFPage(); beginPage() }
                    else {
                        let measured = CTFramesetterSuggestFrameSizeWithConstraints(framesetter, range, nil, CGSize(width: 524, height: CGFloat.greatestFiniteMagnitude), nil)
                        cursor -= ceil(measured.height) + 24
                    }
                }
            }
            context.endPDFPage()
        }
        context.closePDF(); return result as Data
    }
    static func export(faces: [Face], library: Library, sample: String) {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.pdf]; panel.nameFieldStringValue = "Typefield specimens.pdf"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try data(faces: faces, library: library, sample: sample).write(to: url, options: .atomic); library.message = "Specimen PDF exported." } catch { library.message = error.localizedDescription }
    }
}

struct WaterfallView: View {
    let face: Face
    let text: String
    let axes: [Int: Double]
    let features: [String: Int]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ForEach([10.0, 12, 14, 18, 24, 36, 48, 72, 96], id: \.self) { size in
                    VStack(alignment: .leading, spacing: 7) { Text("\(Int(size)) pt").font(.caption).foregroundStyle(.secondary); FontPreview(text: text, name: face.name, size: size, wraps: true, variations: axes, features: features) }
                    Divider()
                }
            }.padding(20)
        }
    }
}

enum FigmaLayoutExporter {
    static func color(_ color: NSColor) -> [String: Double] {
        let c = color.usingColorSpace(.sRGB) ?? .black
        return ["r": c.redComponent, "g": c.greenComponent, "b": c.blueComponent, "a": c.alphaComponent]
    }
    static func payload(board: TypeBoard) -> [String: Any] {
        let frames: [[String: Any]] = board.directions.map { direction in
            let plan = CanvasPlan(direction: direction)
            let elements: [[String: Any]] = plan.elements.map { item in
                var object: [String: Any] = ["x": item.rect.minX, "y": item.rect.minY, "width": item.rect.width, "height": item.rect.height, "section": plan.sections.first { $0.id == item.sectionID }?.title ?? "Section"]
                if let text = item.text, let style = item.style {
                    let font = style.font
                    var axes: [String: Double] = [:]
                    for (key, value) in style.axes { axes[String(bytes: [UInt8((key >> 24) & 255), UInt8((key >> 16) & 255), UInt8((key >> 8) & 255), UInt8(key & 255)], encoding: .ascii) ?? ""] = value }
                    object.merge(["kind": "text", "text": text.string, "role": item.role?.rawValue ?? "Text", "fontFamily": CTFontCopyFamilyName(font) as String, "fontStyle": CTFontCopyName(font, kCTFontStyleNameKey) as String? ?? "Regular", "fontName": style.fontName, "fontSize": style.size, "lineHeight": style.lineHeight ?? style.size * style.leading, "letterSpacing": style.tracking, "paragraphSpacing": style.paragraphSpacing ?? 0, "paragraphIndent": style.indent ?? 0, "wordSpacing": style.wordSpacing ?? 0, "alignment": (style.alignment ?? .left).rawValue.uppercased(), "underline": style.underline ?? false, "strikethrough": style.strikethrough ?? false, "kerning": style.effectiveKerning, "features": style.featuresWithoutKerning, "axes": axes, "color": color((text.length > 0 ? text.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor : nil) ?? NSColor(hex: direction.ink))]) { _, new in new }
                } else { object["kind"] = "rectangle"; object["color"] = color(item.color ?? .clear); object["radius"] = item.radius }
                return object
            }
            return ["name": direction.name, "width": plan.size.width, "height": plan.size.height, "paper": color(plan.paper), "elements": elements]
        }
        return ["format": "fontshelf-figma", "version": 1, "name": board.name, "frames": frames]
    }
    static func write(board: TypeBoard, parent: URL) throws -> URL {
        guard let resources = Bundle.main.resourceURL?.appendingPathComponent("FigmaImport"), FileManager.default.fileExists(atPath: resources.appendingPathComponent("code.js").path) else { throw NSError(domain: "FontShelf", code: 1, userInfo: [NSLocalizedDescriptionKey: "The Figma importer is missing from this build."]) }
        let folder = parent.appendingPathComponent("Typefield-Figma-" + UUID().uuidString.prefix(8))
        try FileManager.default.copyItem(at: resources, to: folder)
        try JSONSerialization.data(withJSONObject: payload(board: board), options: [.prettyPrinted, .sortedKeys]).write(to: folder.appendingPathComponent("layout.typefield.json"), options: .atomic)
        return folder
    }
}

enum FigmaLayoutImporter {
    static func board(data: Data, fonts: [Face]) throws -> TypeBoard {
        func invalid(_ message: String) -> NSError { NSError(domain: "FontShelf", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        guard data.count <= 20_000_000, let root = try JSONSerialization.jsonObject(with: data) as? [String: Any], root["format"] as? String == "fontshelf-figma", root["version"] as? Int == 1, let frames = root["frames"] as? [[String: Any]], !frames.isEmpty, frames.count <= 30 else { throw invalid("Choose a Typefield layout JSON exported by the Figma bridge. Native .fig files are not supported.") }
        func number(_ object: [String: Any], _ key: String, fallback: Double? = nil) throws -> Double {
            guard let n = object[key] as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite else { if let fallback, object[key] == nil { return fallback }; throw invalid("Invalid numeric value: " + key) }; return n.doubleValue
        }
        func color(_ value: Any?) throws -> (String, Double) {
            guard let c = value as? [String: Any] else { throw invalid("A layer is missing its color.") }
            let r = try number(c, "r"), g = try number(c, "g"), b = try number(c, "b"), a = try number(c, "a", fallback: 1)
            guard [r, g, b, a].allSatisfy({ (0...1).contains($0) }) else { throw invalid("A layer has an invalid color.") }
            return (NSColor(srgbRed: r, green: g, blue: b, alpha: a).rgbHex, a)
        }
        var directions: [TypeDirection] = []
        for frame in frames {
            let width = try number(frame, "width"), height = try number(frame, "height")
            guard let elements = frame["elements"] as? [[String: Any]], elements.count <= 5000 else { throw invalid("The frame contains too many layers.") }
            var warnings = root["warnings"] as? [String] ?? []
            var layers: [ImportedLayer] = []
            for e in elements {
                let (hex, opacity) = try color(e["color"])
                var layer = ImportedLayer(name: e["name"] as? String ?? e["section"] as? String ?? "Layer", x: try number(e, "x"), y: try number(e, "y"), width: try number(e, "width"), height: try number(e, "height"), color: hex, opacity: opacity, radius: try number(e, "radius", fallback: 0))
                if e["kind"] as? String == "text" {
                    guard let text = e["text"] as? String, let family = e["fontFamily"] as? String, let fontStyle = e["fontStyle"] as? String else { throw invalid("A text layer is incomplete.") }
                    let face = fonts.first { $0.originalFamily.caseInsensitiveCompare(family) == .orderedSame && $0.style.caseInsensitiveCompare(fontStyle) == .orderedSame }
                    let name = face?.name ?? family
                    if face == nil { warnings.append("Font “\(family) \(fontStyle)” is unavailable; check the fallback for \(layer.name).") }
                    var style = TypeStyle(fontName: name, size: try number(e, "fontSize"), tracking: try number(e, "letterSpacing", fallback: 0), text: text)
                    style.lineHeight = try number(e, "lineHeight"); style.paragraphSpacing = try number(e, "paragraphSpacing", fallback: 0); style.indent = try number(e, "paragraphIndent", fallback: 0)
                    style.alignment = TextAlignmentOption.allCases.first { $0.rawValue.uppercased() == e["alignment"] as? String } ?? .left
                    style.underline = e["underline"] as? Bool; style.strikethrough = e["strikethrough"] as? Bool
                    style.features = e["features"] as? [String: Int] ?? [:]
                    if let kerning = e["kerning"] as? Bool { style.setKerning(kerning) }
                    style.wordSpacing = try number(e, "wordSpacing", fallback: 0)
                    for (tag, value) in e["axes"] as? [String: Double] ?? [:] where tag.utf8.count == 4 { style.axes[tag.utf8.reduce(0) { ($0 << 8) | Int($1) }] = value }
                    layer.style = style
                } else if e["kind"] as? String != "rectangle" { throw invalid("Unsupported layer kind. Export it again with the Typefield bridge.") }
                layers.append(layer)
            }
            let layout = ImportedLayout(width: width, height: height, layers: layers)
            guard layout.isValid else { throw invalid("The layout has invalid bounds or typography.") }
            var direction = TypeDirection(name: frame["name"] as? String ?? "Figma frame")
            direction.canvas = .imported; direction.width = width; direction.paper = try color(frame["paper"]).0; direction.importedLayout = layout; direction.importedSource = .figma
            direction.importWarnings = Array(Set(warnings)).sorted(); directions.append(direction)
        }
        return TypeBoard(name: root["name"] as? String ?? "Figma typeboard", directions: directions, selectedDirection: directions.first?.id)
    }
}
