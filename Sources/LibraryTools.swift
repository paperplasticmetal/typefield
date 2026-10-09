import SwiftUI
import AppKit
import CoreText

/// Names are the edit target. Sidebar names select first, then edit on a second click.
struct ShelfEditableName: View {
    let name: String
    var selected = true
    var onSelect: () -> Void = {}
    let onRename: (String) -> Bool
    @State private var editing = false
    @State private var draft = ""
    @State private var invalid = false
    @FocusState private var focused: Bool
    var body: some View {
        Group {
            if editing {
                TextField("Name", text: $draft).textFieldStyle(.plain).focused($focused)
                    .onSubmit { commit() }
                    .onExitCommand { editing = false; focused = false; invalid = false }
                    .onChange(of: focused) { value in if !value && editing && !invalid { commit() } }
                    .onAppear { DispatchQueue.main.async { focused = true } }
            } else {
                Text(name).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    .onTapGesture(count: 2) { begin() }
                    .onTapGesture { if selected { begin() } else { onSelect() } }
                    .help(selected ? "Click to rename" : "Click to select; double-click to rename")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { if selected { begin() } else { onSelect() } }
                    .accessibilityAction(named: Text("Rename")) { begin() }
            }
        }.alert("Choose another name", isPresented: $invalid) {
            Button("OK") { focused = true }
        } message: { Text("Enter a nonempty name. Collection names must also be unique.") }
    }
    private func begin() { draft = name; editing = true }
    private func commit() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, onRename(trimmed) else { invalid = true; return }
        editing = false; focused = false
    }
}

enum ShelfRename {
    static func prompt(_ title: String, current: String, actionTitle: String = "Rename", validate: (String) -> String? = { _ in nil }) -> String? {
        let alert = NSAlert(); alert.messageText = TypefieldL10n.text(title); alert.informativeText = TypefieldL10n.text("Choose a name. Existing contents will stay unchanged.")
        alert.addButton(withTitle: TypefieldL10n.text(actionTitle)); alert.addButton(withTitle: TypefieldL10n.text("Cancel"))
        let field = NSTextField(string: current); field.frame = NSRect(x: 0, y: 0, width: 320, height: 24)
        field.setAccessibilityLabel("Name"); alert.accessoryView = field; alert.window.initialFirstResponder = field
        while alert.runModal() == .alertFirstButtonReturn {
            let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if name.isEmpty { alert.informativeText = "Please enter a name." }
            else if let error = validate(name) { alert.informativeText = error }
            else { return name }
        }
        return nil
    }
}

enum CollectionCreationResult: Equatable {
    case created(name: String, count: Int)
    case invalidName, duplicateName, noAvailableFonts, saveFailed
}

enum ShelfCollectionPrompt {
    static func prompt(suggestedName: String, source: String, count: Int, unavailable: Int, validate: (String) -> String?) -> String? {
        let alert = NSAlert(); alert.messageText = "Create font collection"
        alert.informativeText = "Save " + String(count) + " font " + (count == 1 ? "family" : "families") + " used in " + source + " as a Library collection."
        if unavailable > 0 { alert.informativeText += " " + String(unavailable) + " unavailable font " + (unavailable == 1 ? "is" : "styles are") + " not currently in the Library and will be skipped." }
        alert.addButton(withTitle: TypefieldL10n.text("Create")); alert.addButton(withTitle: TypefieldL10n.text("Cancel"))
        let field = NSTextField(string: suggestedName); field.frame = NSRect(x: 0, y: 0, width: 340, height: 24)
        field.setAccessibilityLabel("Collection name"); alert.accessoryView = field; alert.window.initialFirstResponder = field
        while alert.runModal() == .alertFirstButtonReturn {
            let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if name.isEmpty { alert.informativeText = "Enter a collection name." }
            else if let error = validate(name) { alert.informativeText = error }
            else { return name }
        }
        return nil
    }
}

extension Library {
    func familyNames(forPostScriptNames names: Set<String>) -> Set<String> {
        Set(families.filter { family in family.faces.contains { names.contains($0.name) } }.map(\.name))
    }
    @discardableResult func createCollection(_ proposed: String, postScriptNames: Set<String>) -> CollectionCreationResult {
        let name = proposed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return .invalidName }
        guard saved.collections[name] == nil else { return .duplicateName }
        let members = familyNames(forPostScriptNames: postScriptNames)
        guard !members.isEmpty else { return .noAvailableFonts }
        saved.collections[name] = members
        guard save() else { saved.collections.removeValue(forKey: name); return .saveFailed }
        return .created(name: name, count: members.count)
    }
    @discardableResult func renameCollection(_ old: String, to proposed: String) -> Bool {
        let name = proposed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let members = saved.collections[old], !name.isEmpty, name == old || saved.collections[name] == nil else { return false }
        guard name != old else { return true }
        let previousCollections = saved.collections
        let previousSearches = saved.savedSearches
        let previousSelection = selection
        saved.collections[name] = members; saved.collections.removeValue(forKey: old)
        if var searches = saved.savedSearches {
            for key in searches.keys where searches[key]?.section == "collection:" + old {
                searches[key]?.section = "collection:" + name
            }
            saved.savedSearches = searches
        }
        if selection == "collection:" + old { selection = "collection:" + name }
        guard save() else {
            saved.collections = previousCollections
            saved.savedSearches = previousSearches
            selection = previousSelection
            return false
        }
        return true
    }

    @discardableResult func mergeTagBackup(_ tags: [String: Set<String>]) -> Bool {
        let previous = pro.tags
        for (name, values) in tags { pro.tags[name, default: []].formUnion(values) }
        guard savePro() else {
            pro.tags = previous
            return false
        }
        return true
    }

    @discardableResult func applyTags(_ tags: Set<String>, to postScriptNames: [String], removing: Bool) -> Bool {
        guard !tags.isEmpty, !postScriptNames.isEmpty else { return false }
        let previous = pro.tags
        for name in postScriptNames {
            var values = pro.tags[name] ?? []
            if removing { values.subtract(tags) } else { values.formUnion(tags) }
            pro.tags[name] = values
        }
        guard savePro() else {
            pro.tags = previous
            return false
        }
        return true
    }
}

struct AdvancedFiltersView: View {
    @ObservedObject var library: Library
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Text("Advanced filters").font(.headline); Spacer(); Button("Reset") { library.advanced = AdvancedFilter() } }
            TextField("Manufacturer / foundry", text: $library.advanced.foundry)
            TextField("OpenType tag, e.g. smcp", text: $library.advanced.feature)
            ShelfDropdown(title: "File type", selection: $library.advanced.format, options: ["Any", "TTF", "OTF", "TTC", "OTC", "DFONT", "WOFF", "WOFF2"].map { ($0, $0) })
            ShelfDropdown(title: "Style", selection: $library.advanced.slant, options: ["Any", "Roman", "Italic"].map { ($0, $0) })
            HStack { Text("Weight"); TextField("Min", value: $library.advanced.minimumWeight, format: .number).frame(width: 65); Text("to"); TextField("Max", value: $library.advanced.maximumWeight, format: .number).frame(width: 65) }
            TextField("Minimum glyph count", value: $library.advanced.minimumGlyphs, format: .number)
            ShelfDropdown(title: "Tag", selection: $library.advanced.tag, options: [("Any", "")] + Set(library.pro.tags.values.flatMap { $0 }).sorted().map { ($0, $0) })
            ShelfDropdown(title: "Activation", selection: $library.advanced.activation, options: ["Any", "Temporary", "Typefield only"].map { ($0, $0) })
            Text("Filters must match the same font style. They combine with language, category, and preview-character filters.").font(.caption).foregroundStyle(.secondary)
        }.textFieldStyle(.roundedBorder).padding(22).frame(width: 330)
    }
}
struct LibraryToolsView: View {
    @ObservedObject var library: Library
    @Environment(\.dismiss) var dismiss
    private var preferredSize: CGSize {
        switch library.toolsTab {
        case "Tags": return CGSize(width: 700, height: 500)
        case "Families": return CGSize(width: 900, height: 690)
        case "Duplicates": return CGSize(width: 870, height: 650)
        case "Font Health": return CGSize(width: 1000, height: 735)
        case "Google Fonts": return CGSize(width: 870, height: 675)
        case "Activation": return CGSize(width: 740, height: 470)
        default: return CGSize(width: 900, height: 650)
        }
    }
    var body: some View {
        let screen = NSScreen.main?.visibleFrame.size ?? CGSize(width: 1100, height: 850)
        VStack(spacing: 14) {
            HStack {
                Text(library.toolsTab).font(.title2)
                Spacer()
                Picker("Library task", selection: $library.toolsTab) {
                    Section("Organization") { Text("Tags").tag("Tags"); Text("Families").tag("Families") }
                    Section("Font files") { Text("Duplicates").tag("Duplicates"); Text("Font Health").tag("Font Health"); Text("Google Fonts").tag("Google Fonts"); Text("Activation").tag("Activation"); Text("Folders").tag("Folders") }
                }.pickerStyle(.menu).frame(width: 185)
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Group {
                switch library.toolsTab {
                case "Folders": WatchedFoldersView(library: library)
                case "Families": FamilyEditorView(library: library)
                case "Duplicates": DuplicateView(library: library)
                case "Google Fonts": GoogleFontsView(library: library)
                case "Activation": ActivationView(library: library)
                case "Font Health": FontHealthView(library: library)
                default: TagEditorView(library: library)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }.padding(22).frame(width: min(preferredSize.width, max(580, screen.width - 90)),
                            height: min(preferredSize.height, max(400, screen.height - 90)))
    }
}
struct TagEditorView: View {
    @ObservedObject var library: Library
    @State var input = ""
    @State var status = ""
    var entries: [String] { Array(Set(input.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })).sorted() }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text(library.selectedScopeLabel + " (\(library.selectedFaces.count) \(library.selectedFaces.count == 1 ? "style" : "styles") affected)"); Spacer(); Button("Replace selection with visible") { library.selectVisibleFamilies() }; Button("Clear selection") { library.selectedFamilies = [] } }
            TextField("Tags separated by commas; use / for nested tags", text: $input).textFieldStyle(.roundedBorder)
            HStack {
                Button("Add tags to \(library.selectedFaces.count) \(library.selectedFaces.count == 1 ? "style" : "styles")") { apply(remove: false) }.disabled(entries.isEmpty || library.selectedFaces.isEmpty)
                Button("Remove tags from \(library.selectedFaces.count) \(library.selectedFaces.count == 1 ? "style" : "styles")") { apply(remove: true) }.disabled(entries.isEmpty || library.selectedFaces.isEmpty)
                Spacer()
                Button("Export tag backup…") { backup() }
                Button("Import tag backup…") { restore() }
            }
            Text(status).font(.caption).foregroundStyle(.secondary)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(library.families.filter { library.selectedFamilies.contains($0.name) }) { family in
                        HStack { Text(family.name).fontWeight(.medium); Spacer(); Text(library.tags(family).sorted().joined(separator: ", ")).foregroundStyle(.secondary) }.padding(9).background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 5))
                    }
                }
            }
            Text("Select families using the circle on each card. Tags apply to every style in each selected family and survive family regrouping.").font(.caption).foregroundStyle(.secondary)
        }.padding(10)
    }
    func apply(remove: Bool) {
        let faces = library.selectedFaces
        guard library.applyTags(Set(entries), to: faces.map(\.name), removing: remove) else {
            status = library.message.isEmpty ? "Could not save tag settings." : library.message
            return
        }
        status = "\(remove ? "Removed" : "Added") tags for \(faces.count) \(faces.count == 1 ? "style" : "styles") in \(library.selectedFamilies.count) \(library.selectedFamilies.count == 1 ? "family" : "families"). Saved in Library."
    }
    func backup() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "Typefield-tags.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try JSONEncoder().encode(library.pro.tags).write(to: url, options: .atomic); status = "Tag backup saved to \(url.lastPathComponent)." } catch { status = error.localizedDescription }
    }
    func restore() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let tags = try JSONDecoder().decode([String: Set<String>].self, from: TypefieldInputFile.read(url, maximumBytes: 20_000_000))
            guard library.mergeTagBackup(tags) else {
                status = library.message.isEmpty ? "Could not save tag settings." : library.message
                return
            }
            status = "Merged tags for \(tags.count) \(tags.count == 1 ? "style" : "styles") into Library."
        } catch { status = error.localizedDescription }
    }
}
struct FamilyEditorView: View {
    @ObservedObject var library: Library
    @State var query = ""
    @State var selected: Set<String> = []
    @State var name = ""
    @State var modifiedOnly = false
    @State var status = ""
    var faces: [Face] {
        library.allFaces.filter { (!modifiedOnly || library.pro.familyOverrides[$0.name] != nil) && (query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.originalFamily.localizedCaseInsensitiveContains(query) || (library.pro.familyOverrides[$0.name] ?? "").localizedCaseInsensitiveContains(query)) }.sorted { $0.name < $1.name }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { TextField("Search fonts or families", text: $query); Toggle("Modified only", isOn: $modifiedOnly).toggleStyle(.checkbox) }
            HStack { Text("\(selected.count) \(selected.count == 1 ? "style" : "styles") selected (\(selected.subtracting(Set(faces.map(\.name))).count) outside results)"); Button("Select results") { selected = Set(faces.map(\.name)) }; Button("Clear") { selected = [] }; Spacer() }
            HStack { TextField("Family name to group selected styles under", text: $name); Button("Group \(selected.count) \(selected.count == 1 ? "style" : "styles")") { let target = name.trimmingCharacters(in: .whitespacesAndNewlines); if library.editFamily(names: selected, target: target) { status = "Grouped \(selected.count) \(selected.count == 1 ? "style" : "styles") under \(target). Saved in Library." } else { status = library.message.isEmpty ? "Could not save family changes." : library.message } }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selected.isEmpty); Button("Restore \(selected.count) original \(selected.count == 1 ? "style" : "styles")") { if library.editFamily(names: selected, target: nil) { status = "Restored original families for \(selected.count) \(selected.count == 1 ? "style" : "styles"). Saved in Library." } else { status = library.message.isEmpty ? "Could not save family changes." : library.message } }.disabled(selected.isEmpty) }
            Text(status).font(.caption).foregroundStyle(.secondary)
            Text("Group selected styles to merge families, or assign a subset to split a family. Font files are not modified.").font(.caption).foregroundStyle(.secondary)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(faces) { face in
                        HStack {
                            Toggle("", isOn: Binding(get: { selected.contains(face.name) }, set: { if $0 { selected.insert(face.name) } else { selected.remove(face.name) } })).labelsHidden().toggleStyle(.checkbox)
                            VStack(alignment: .leading, spacing: 3) { Text(face.name).font(.system(size: 12, weight: .medium)); Text("Original: \(face.originalFamily), \(face.style)").font(.caption).foregroundStyle(.secondary) }
                            Spacer()
                            Text(library.pro.familyOverrides[face.name] ?? face.originalFamily).font(.caption)
                        }.padding(8).background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 5))
                    }
                }
            }
        }.textFieldStyle(.roundedBorder).padding(10).onAppear { selected = Set(library.selectedFaces.map(\.name)) }
    }
}
struct DuplicateView: View {
    @ObservedObject var library: Library
    @State var groups: [DuplicateGroup] = []
    @State var errors: [String] = []
    @State var busy = false
    @State var scanned = false
    @State var exact = true
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Button(busy ? "Scanning…" : "Scan font files") { scan() }.disabled(busy); Picker("Match", selection: $exact) { Text("Identical file contents").tag(true); Text("Same PostScript name").tag(false) }.pickerStyle(.segmented); if busy { ProgressView().controlSize(.small) } }
            Text("Same-name matches may be different versions or formats. Identical copies can be moved to Trash individually.").font(.caption).foregroundStyle(.secondary)
            if scanned { Text("\(groups.filter { $0.exact == exact }.count) \(groups.filter { $0.exact == exact }.count == 1 ? "group" : "groups"); \(errors.count) unreadable files or folders").font(.caption) }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 15) {
                    ForEach(groups.filter { $0.exact == exact }) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(group.title).font(.headline)
                            ForEach(group.paths, id: \.self) { path in HStack { Text(path).font(.caption).textSelection(.enabled); Spacer(); Button("Reveal") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }; if group.exact && !path.hasPrefix("/System/") && !path.hasPrefix("/Library/") { Button("Trash…") { trash(path, group: group) } } } }
                        }.padding(12).background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 7))
                    }
                    if scanned && groups.filter({ $0.exact == exact }).isEmpty { Text("No matches found.").foregroundStyle(.secondary) }
                    if !errors.isEmpty { DisclosureGroup("Scan errors") { Text(errors.joined(separator: "\n")).font(.caption).textSelection(.enabled) } }
                }
            }
        }.padding(10)
    }
    func scan() {
        busy = true
        let urls = library.allFaces.compactMap(\.url), folders = library.resolvedFolders
        DispatchQueue.global(qos: .userInitiated).async {
            let result = DuplicateFinder.scan(urls: urls, folders: folders)
            DispatchQueue.main.async { groups = result.groups; errors = result.errors; busy = false; scanned = true }
        }
    }
    func trash(_ path: String, group: DuplicateGroup) {
        let other = group.paths.filter { $0 != path }.first { FileManager.default.fileExists(atPath: $0) }
        guard let other, let hash = try? DuplicateFinder.hash(URL(fileURLWithPath: path)), let otherHash = try? DuplicateFinder.hash(URL(fileURLWithPath: other)), hash == otherHash else { errors.append("The duplicate changed or could not be read. Scan again before removing it."); return }
        let panel = NSOpenPanel(); panel.directoryURL = URL(fileURLWithPath: path).deletingLastPathComponent(); panel.message = "Select \(URL(fileURLWithPath: path).lastPathComponent) to grant access for moving this duplicate to Trash."
        guard panel.runModal() == .OK, let url = panel.url, url.standardizedFileURL.path == URL(fileURLWithPath: path).standardizedFileURL.path else { return }
        let alert = NSAlert(); alert.messageText = "Move this duplicate to Trash?"; alert.informativeText = path + "\n\nAn identical copy remains at:\n" + other; alert.addButton(withTitle: "Move to Trash"); alert.addButton(withTitle: TypefieldL10n.text("Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard let currentHash = try? DuplicateFinder.hash(url), let remainingHash = try? DuplicateFinder.hash(URL(fileURLWithPath: other)), currentHash == remainingHash else { errors.append("The files changed or could not be read. Nothing was removed."); return }
        do { if ActivationManager.shared.owns(url) { try ActivationManager.shared.deactivate(url, restore: false) }; try FileManager.default.trashItem(at: url, resultingItemURL: nil); library.reload(register: true); scan() }
        catch { errors.append(error.localizedDescription) }
    }
}
struct ActivationView: View {
    @ObservedObject var library: Library
    @ObservedObject var manager = ActivationManager.shared
    @State var status = ""
    private var selectedFileCount: Int { Set(library.selectedFaces.compactMap(\.url)).count }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text("\(manager.records.count) files temporarily activated").font(.headline)
                HStack(spacing: 10) {
                    Button("Activate \(selectedFileCount) selected files") {
                        var messages: [String] = []
                        for url in Set(library.selectedFaces.compactMap(\.url)) { do { messages.append(url.lastPathComponent + ": " + (try manager.activate(url))) } catch { messages.append(url.lastPathComponent + ": " + error.localizedDescription) } }
                        status = "Processed \(messages.count) font files for \(library.selectedFamilies.count) families.\n" + messages.joined(separator: "\n")
                    }.disabled(selectedFileCount == 0)
                    Button("Clear temporary activations") { let errors = manager.clear(); status = errors.isEmpty ? "Temporary activations cleared." : errors.joined(separator: "\n") }.disabled(manager.records.isEmpty)
                    Spacer(minLength: 0)
                }
            }
            Text(library.selectedScopeLabel + " (\(library.selectedFaces.count) \(library.selectedFaces.count == 1 ? "style" : "styles") affected)").font(.caption).foregroundStyle(.secondary)
            if !library.selectedFaces.isEmpty && selectedFileCount == 0 {
                Text("The selected styles have no font file available to activate. Select styles from accessible files instead.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("Fonts are available across apps for this login session. Typefield clears its own activations on normal quit. If it crashes, they are cleared at the next launch or logout. Installed fonts are not deactivated.").font(.caption).foregroundStyle(.secondary)
            ScrollView { VStack(alignment: .leading, spacing: 12) {
                ForEach(manager.records, id: \.path) { record in HStack { Text(record.path).font(.caption).textSelection(.enabled); Spacer(); Button("Deactivate") { do { try manager.deactivate(URL(fileURLWithPath: record.path)) } catch { status = error.localizedDescription } } } }
                Text(status).font(.caption).textSelection(.enabled)
            } }
        }.padding(10)
    }
}
struct GoogleVariableFont: Codable, Identifiable {
    var id: String { family }
    let family: String
    let category: String
    let axes: [GoogleAxis]
    let subsets: [String]
}
struct GoogleAxis: Codable { let tag: String; let min: Double; let max: Double; let defaultValue: Double }
struct GitHubFontFile: Decodable { let name: String; let download_url: String?; let size: Int }
final class GoogleFontStore: ObservableObject {
    @Published var catalog: [GoogleVariableFont] = []
    @Published var busy: String?
    @Published var status = ""
    @Published var statusByFamily: [String: String] = [:]
    @Published var licenseByFamily: [String: String] = [:]
    @Published var failedFamilies: Set<String> = []
    init() {
        if let url = Bundle.main.url(forResource: "GoogleVariableFonts", withExtension: "json") { catalog = (try? JSONDecoder().decode([GoogleVariableFont].self, from: Data(contentsOf: url))) ?? [] }
        if catalog.isEmpty { status = "The bundled Google Fonts catalog is unavailable." }
    }
    static func fetch(_ url: URL, session: URLSession = .shared) async throws -> Data {
        var request = URLRequest(url: url); request.timeoutInterval = 45; request.setValue("Typefield", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else { throw NSError(domain: "Typefield", code: (response as? HTTPURLResponse)?.statusCode ?? 0, userInfo: [NSLocalizedDescriptionKey: "Download failed (HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)). Check connectivity or try again later."]) }
        guard data.count <= 50_000_000 else { throw NSError(domain: "Typefield", code: 3, userInfo: [NSLocalizedDescriptionKey: "Font download exceeded 50 MB."]) }
        return data
    }
    /// Publish the complete licensed download together. A failed library save
    /// restores the previous managed folder and the in-memory folder list.
    static func commitStagedDownload(_ staged: URL, to folder: URL, library: Library) throws {
        let fm = FileManager.default
        let previous = folder.deletingLastPathComponent().appendingPathComponent(".typefield-previous-" + UUID().uuidString)
        let savedFolders = library.saved.folders
        var movedPrevious = false
        var movedStaged = false
        do {
            if fm.fileExists(atPath: folder.path) {
                let values = try folder.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard values.isDirectory == true, values.isSymbolicLink != true else { throw CocoaError(.fileReadInvalidFileName) }
                try fm.moveItem(at: folder, to: previous)
                movedPrevious = true
            }
            try fm.moveItem(at: staged, to: folder)
            movedStaged = true
            if !library.saved.folders.contains(folder.path) { library.saved.folders.append(folder.path) }
            guard library.save() else {
                throw NSError(domain: "Typefield.GoogleFonts", code: 8, userInfo: [NSLocalizedDescriptionKey: library.message])
            }
        } catch {
            library.saved.folders = savedFolders
            do {
                if movedStaged { try fm.removeItem(at: folder) }
                if movedPrevious { try fm.moveItem(at: previous, to: folder) }
            } catch let recoveryError {
                throw NSError(domain: "Typefield.GoogleFonts", code: 9, userInfo: [NSLocalizedDescriptionKey: "Download was not completed. The earlier font files remain at \(previous.path). Restore them before retrying. \(recoveryError.localizedDescription)"])
            }
            throw error
        }
        if movedPrevious { try? fm.removeItem(at: previous) }
    }
    func download(_ font: GoogleVariableFont, library: Library) {
        guard busy == nil else { return }
        busy = font.family; status = "Downloading \(font.family)…"
        statusByFamily[font.family] = "Checking source and license for \(font.family)…"
        failedFamilies.remove(font.family)
        Task {
            do {
                let slug = font.family.lowercased().filter { $0.isLetter || $0.isNumber }
                var listing: [GitHubFontFile] = []
                var sourceRoot = ""
                for root in ["ofl", "apache", "ufl"] {
                    let url = URL(string: "https://api.github.com/repos/google/fonts/contents/\(root)/\(slug)")!
                    do { listing = try JSONDecoder().decode([GitHubFontFile].self, from: await Self.fetch(url)); if !listing.isEmpty { sourceRoot = root; break } }
                    catch let error as NSError { if error.code != 404 { throw error } }
                }
                let files = listing.filter { ($0.name.hasSuffix(".ttf") && $0.name.contains("[")) || ["OFL.txt", "LICENSE.txt", "LICENSE"].contains($0.name) }
                guard files.contains(where: { $0.name.hasSuffix(".ttf") }) else { throw NSError(domain: "Typefield", code: 4, userInfo: [NSLocalizedDescriptionKey: "No variable TTF files found in Google’s repository for this family."]) }
                guard files.contains(where: { ["OFL.txt", "LICENSE.txt", "LICENSE"].contains($0.name) }) else {
                    throw NSError(domain: "Typefield", code: 7, userInfo: [NSLocalizedDescriptionKey: "No license found for this download."])
                }
                let licenseFile = files.first(where: { ["OFL.txt", "LICENSE.txt", "LICENSE"].contains($0.name) })!.name
                let licenseSource = "\(licenseFile) (google/fonts/\(sourceRoot)/\(slug))"
                await MainActor.run {
                    licenseByFamily[font.family] = licenseSource
                    statusByFamily[font.family] = "License located. Downloading font files…"
                }
                let folder = library.saveURL.deletingLastPathComponent().appendingPathComponent("Google Fonts/" + slug)
                let parent = folder.deletingLastPathComponent()
                let staged = parent.appendingPathComponent(".typefield-download-" + UUID().uuidString)
                let fm = FileManager.default
                try fm.createDirectory(at: parent, withIntermediateDirectories: true)
                if fm.fileExists(atPath: folder.path) {
                    let values = try folder.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                    guard values.isDirectory == true, values.isSymbolicLink != true else { throw CocoaError(.fileReadInvalidFileName) }
                    try fm.copyItem(at: folder, to: staged)
                } else { try fm.createDirectory(at: staged, withIntermediateDirectories: false) }
                defer { try? fm.removeItem(at: staged) }
                var fontCount = 0
                var licenseCount = 0
                for file in files.sorted(by: { !$0.name.hasSuffix(".ttf") && $1.name.hasSuffix(".ttf") }) {
                    guard file.name == (file.name as NSString).lastPathComponent, let address = file.download_url, let url = URL(string: address), url.scheme == "https", url.host == "raw.githubusercontent.com", url.path.hasPrefix("/google/fonts/"), file.size <= 50_000_000 else { throw NSError(domain: "Typefield.GoogleFonts", code: 10, userInfo: [NSLocalizedDescriptionKey: "A font or license download has an invalid source path."]) }
                    let data = try await Self.fetch(url)
                    if file.name.hasSuffix(".ttf") {
                        guard licenseCount > 0 else { throw NSError(domain: "Typefield", code: 7, userInfo: [NSLocalizedDescriptionKey: "The license could not be saved. No font files were installed."]) }
                        guard let descriptors = CTFontManagerCreateFontDescriptorsFromData(data as CFData) as? [CTFontDescriptor], !descriptors.isEmpty else { throw NSError(domain: "Typefield", code: 5, userInfo: [NSLocalizedDescriptionKey: "Downloaded file is not a readable font."]) }
                        fontCount += 1
                    }
                    let target = staged.appendingPathComponent(file.name)
                    if (try? target.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true { throw CocoaError(.fileReadInvalidFileName) }
                    try data.write(to: target, options: .atomic)
                    if !file.name.hasSuffix(".ttf") { licenseCount += 1 }
                }
                guard fontCount > 0 && licenseCount > 0 else { throw NSError(domain: "Typefield", code: 6, userInfo: [NSLocalizedDescriptionKey: "No font files were downloaded."]) }
                let downloadedCount = fontCount
                try await MainActor.run {
                    try Self.commitStagedDownload(staged, to: folder, library: library)
                    library.pendingImportFolder = folder.path
                    library.reload(register: true)
                    status = "Downloaded \(font.family) (\(downloadedCount) files). Available in the library; use its inspector to tune variable axes."
                    statusByFamily[font.family] = "Downloaded \(downloadedCount) font \(downloadedCount == 1 ? "file" : "files") into your Library. License saved beside the fonts."
                    busy = nil
                }
            } catch { await MainActor.run {
                status = "Could not download \(font.family): " + error.localizedDescription
                statusByFamily[font.family] = status + " Select Retry download to try again."
                failedFamilies.insert(font.family)
                busy = nil
            } }
        }
    }
}
struct GoogleFontsView: View {
    @ObservedObject var library: Library
    @StateObject var store = GoogleFontStore()
    @State var query = ""
    @State private var previewText = "The quick brown fox jumps over the lazy dog."
    @State private var previewSize = 42.0
    var matches: [GoogleVariableFont] { store.catalog.filter { query.isEmpty || $0.family.localizedCaseInsensitiveContains(query) || $0.category.localizedCaseInsensitiveContains(query) || $0.subsets.contains { $0.localizedCaseInsensitiveContains(query) } } }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Search Google families, categories, or scripts", text: $query).textFieldStyle(.roundedBorder)
            HStack {
                TextField("Preview text", text: $previewText).textFieldStyle(.roundedBorder)
                Slider(value: $previewSize, in: 20...100, step: 1).frame(width: 140)
                Text("\(Int(previewSize)) pt").monospacedDigit().frame(width: 48)
            }
            Text("\(store.catalog.count) families. Previews load from the Google Fonts repository on GitHub. A license file is checked and saved with every download.").font(.caption).foregroundStyle(.secondary)
            if !store.status.isEmpty { Text(store.status).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
            ScrollView { LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(matches) { font in
                    VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 5) { Text(font.family).font(.headline); Text("\(font.category): " + font.axes.map { "\($0.tag) \(Int($0.min))–\(Int($0.max))" }.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary) }
                        Spacer()
                        if library.originalFamilies.contains(where: { $0.name == font.family }) {
                            Button("Inspect installed") { if let family = library.families.first(where: { $0.name == font.family || $0.faces.contains { $0.originalFamily == font.family } }) { library.showTools = false; DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { library.detail = family } } }
                        }
                        Button(store.busy == font.family ? "Downloading…" : store.failedFamilies.contains(font.family) ? "Retry download" : "Download variable") { store.download(font, library: library) }.disabled(store.busy != nil || library.loading)
                    }
                    Text("Source: Google Fonts (google/fonts on GitHub). License: \(store.licenseByFamily[font.family] ?? "repository license file checked before installation")")
                        .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    if let result = store.statusByFamily[font.family] { Text(result).font(.caption).foregroundStyle(store.failedFamilies.contains(font.family) ? .red : .secondary).textSelection(.enabled) }
                    GoogleFontSample(font: font, text: previewText, size: previewSize, installed: library.originalFamilies.first(where: { $0.name == font.family })?.representative.name)
                    }.padding(14).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
                }
            } }
        }.padding(10)
    }
}

private final class PreviewFontBox {
    let font: CGFont
    init(_ font: CGFont) { self.font = font }
}

/// Memory-only previews: no registration, activation, font-folder writes or catalog changes.
private actor GooglePreviewLoader {
    static let shared = GooglePreviewLoader()
    private let cache = NSCache<NSString, PreviewFontBox>()
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()
    private var active = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []
    init() { cache.countLimit = 48; cache.totalCostLimit = 64 * 1024 * 1024 }
    private func acquire() async {
        if active < 3 { active += 1; return }
        await withCheckedContinuation { waiting.append($0) }
    }
    private func release() {
        if waiting.isEmpty { active -= 1 } else { waiting.removeFirst().resume() }
    }
    func load(_ family: String) async throws -> CGFont {
        if let cached = cache.object(forKey: family as NSString) { return cached.font }
        await acquire()
        defer { release() }
        try Task.checkCancellation()
        if let cached = cache.object(forKey: family as NSString) { return cached.font }
        let slug = family.lowercased().filter { $0.isLetter || $0.isNumber }
        for root in ["ofl", "apache", "ufl"] {
            let folder = URL(string: "https://raw.githubusercontent.com/google/fonts/main/")!.appendingPathComponent(root).appendingPathComponent(slug)
            let metadata: Data
            do { metadata = try await GoogleFontStore.fetch(folder.appendingPathComponent("METADATA.pb"), session: session) }
            catch let error as NSError { if error.code == 404 { continue }; throw error }
            let source = String(decoding: metadata, as: UTF8.self)
            let expression = try NSRegularExpression(pattern: #"filename:\s*"([^"]+\.ttf)""#)
            let filenames = expression.matches(in: source, range: NSRange(source.startIndex..., in: source)).compactMap { match -> String? in
                guard let range = Range(match.range(at: 1), in: source) else { return nil }
                let name = String(source[range])
                return name == (name as NSString).lastPathComponent ? name : nil
            }
            guard let filename = filenames.first(where: { !$0.lowercased().contains("italic") }) ?? filenames.first else { continue }
            try Task.checkCancellation()
            let data = try await GoogleFontStore.fetch(folder.appendingPathComponent(filename), session: session)
            try Task.checkCancellation()
            guard let provider = CGDataProvider(data: data as CFData), let font = CGFont(provider) else {
                throw NSError(domain: "Typefield", code: 5, userInfo: [NSLocalizedDescriptionKey: "The preview font could not be read."])
            }
            cache.setObject(PreviewFontBox(font), forKey: family as NSString, cost: data.count)
            return font
        }
        throw NSError(domain: "Typefield", code: 4, userInfo: [NSLocalizedDescriptionKey: "No preview file found for this family."])
    }
}

private struct GoogleFontSample: View {
    let font: GoogleVariableFont
    let text: String
    let size: Double
    let installed: String?
    @State private var loaded: CGFont?
    @State private var error = ""
    @State private var attempt = 0
    var body: some View {
        Group {
            if let installed {
                FontPreview(text: text, name: installed, size: size, wraps: true)
            } else if let loaded {
                FontPreview(text: text, name: font.family, size: size, wraps: true, previewFont: loaded)
            } else if !error.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Preview unavailable: " + error).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    Button("Retry preview") { error = ""; attempt += 1 }
                }
            } else {
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Loading preview…").foregroundStyle(.secondary) }
            }
        }.frame(maxWidth: .infinity, minHeight: size * 1.5, alignment: .leading)
        .onDisappear { loaded = nil }
        .task(id: attempt) {
            guard installed == nil, loaded == nil else { return }
            do { loaded = try await GooglePreviewLoader.shared.load(font.family) }
            catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
}
