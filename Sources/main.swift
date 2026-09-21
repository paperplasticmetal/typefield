import SwiftUI
import AppKit
import CoreText

enum Category: String, CaseIterable, Codable {
    case serif = "Serif", sans = "Sans Serif", mono = "Monospaced", script = "Script", display = "Display", symbol = "Symbols", other = "Unclassified"
    var icon: String {
        switch self { case .serif: return "textformat"; case .sans: return "textformat.abc"; case .mono: return "chevron.left.forwardslash.chevron.right"; case .script: return "signature"; case .display: return "sparkles"; case .symbol: return "star.circle"; case .other: return "questionmark.folder" }
    }
}
struct Face: Identifiable {
    var id: String { name }
    let name: String
    let style: String
    let originalFamily: String
    let facts: FontFacts
    let url: URL?
    let coverage: CharacterSet
    let writingSystems: Set<WritingSystem>
}
struct Family: Identifiable {
    var id: String { name }
    let name: String
    let faces: [Face]
    let automaticCategory: Category
    let variable: Bool
    let writingSystems: Set<WritingSystem>
    var representative: Face { faces.first(where: { ["Regular", "Book", "Roman", "Normal"].contains($0.style) }) ?? faces[0] }
    var userFont: Bool { faces.contains { face in guard let p = face.url?.path else { return false }; return !p.hasPrefix("/System/") && !p.hasPrefix("/Library/Apple/") } }
}
struct SavedLibrary: Codable {
    var favorites: Set<String> = []
    var overrides: [String: Category] = [:]
    var collections: [String: Set<String>] = [:]
    var folders: [String] = []
    var lastImportNames: Set<String>?
    var lastImportDate: Date?
    var lastImportSource: String?
    var autoActivateFolders: Set<String>?
    var fontUsage: [String: FontUsageRecord]?
    var webAssetFolders: [String]?
}

enum FontCatalog {
    static var registeredFiles: [String: FontFileStamp] = [:]
    @discardableResult static func reconcileFolders(_ folders: [String]) -> Bool {
        var changed = false
        for (path, stamp) in registeredFiles {
            let inScope = folders.contains { FontFolderSnapshot.contains(path, root: $0) }
            if !inScope || FontFileStamp.read(URL(fileURLWithPath: path)) != stamp {
                let url = URL(fileURLWithPath: path)
                if CTFontManagerGetScopeForURL(url as CFURL) == .process { changed = CTFontManagerUnregisterFontsForURL(url as CFURL, .process, nil) || changed }
                registeredFiles.removeValue(forKey: path)
            }
        }
        for path in folders { changed = registerFolder(path) > 0 || changed }
        return changed
    }
    static func category(_ font: CTFont) -> Category {
        let traits = CTFontGetSymbolicTraits(font).rawValue
        if traits & CTFontSymbolicTraits.traitMonoSpace.rawValue != 0 { return .mono }
        // OpenType OS/2 PANOSE serif style, then IBM family class.
        if let data = CTFontCopyTable(font, CTFontTableTag(0x4F532F32), []) as Data?, data.count >= 42 {
            if data[32] == 2 {
                if (2...10).contains(data[33]) { return .serif }
                if (11...15).contains(data[33]) { return .sans }
            }
            if data[32] == 3 { return .script }
            if data[32] == 4 { return .display }
            if data[32] == 5 { return .symbol }
            switch data[30] { case 1,2,3,4,5,7: return .serif; case 8: return .sans; case 9: return .display; case 10: return .script; case 12: return .symbol; default: break }
        }
        switch (traits >> 28) & 15 { case 1,2,3,4,5,7: return .serif; case 8: return .sans; case 9: return .display; case 10: return .script; case 12: return .symbol; default: return knownFontCategories[CTFontCopyFamilyName(font) as String] ?? .other }
    }
    static func scan() -> [Family] {
        OpenType.clearFontCache()
        CanvasPlanCache.removeAll()
        let descriptors = CTFontCollectionCreateMatchingFontDescriptors(CTFontCollectionCreateFromAvailableFonts(nil)) as? [CTFontDescriptor] ?? []
        var groups: [String: [Face]] = [:]
        var seen = Set<String>()
        for descriptor in descriptors {
            let font = CTFontCreateWithFontDescriptor(descriptor, 24, nil)
            let name = CTFontCopyPostScriptName(font) as String
            let family = CTFontCopyFamilyName(font) as String
            guard !family.hasPrefix("."), seen.insert(name).inserted else { continue }
            let coverage = CTFontCopyCharacterSet(font) as CharacterSet
            let writing = Set(WritingSystem.allCases.filter { $0.supported(by: coverage) })
            let url = CTFontDescriptorCopyAttribute(descriptor, kCTFontURLAttribute) as? URL
            groups[family, default: []].append(Face(name: name, style: CTFontCopyName(font, kCTFontStyleNameKey) as String? ?? "Regular", originalFamily: family, facts: FontFacts.read(font), url: url, coverage: coverage, writingSystems: writing))
        }
        return groups.map { name, faces in
            let sorted = faces.sorted { $0.style.localizedStandardCompare($1.style) == .orderedAscending }
            let rep = sorted.first(where: { ["Regular", "Book", "Roman", "Normal"].contains($0.style) }) ?? sorted[0]
            let font = CTFontCreateWithName(rep.name as CFString, 24, nil)
            let variable = sorted.contains { $0.facts.variable }
            return Family(name: name, faces: sorted, automaticCategory: category(font), variable: variable, writingSystems: sorted.reduce(into: []) { $0.formUnion($1.writingSystems) })
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    static func registerFolder(_ path: String) -> Int {
        let keys: [URLResourceKey] = [.isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(at: URL(fileURLWithPath: path), includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return 0 }
        var count = 0
        var available = Set((CTFontManagerCopyAvailablePostScriptNames() as? [String]) ?? [])
        let urls = enumerator.compactMap { $0 as? URL }.filter { DuplicateFinder.extensions.contains($0.pathExtension.lowercased()) }.sorted {
            func rank(_ url: URL) -> Int { (url.lastPathComponent.contains("-subset") ? 10 : 0) + (["otf", "ttf", "ttc", "otc", "dfont"].contains(url.pathExtension.lowercased()) ? 0 : 1) }
            return rank($0) == rank($1) ? $0.path < $1.path : rank($0) < rank($1)
        }
        for url in urls {
            let names = Set((CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor] ?? []).compactMap { CTFontDescriptorCopyAttribute($0, kCTFontNameAttribute) as? String })
            if !names.isEmpty && names.isSubset(of: available) { continue }
            if CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil) { count += 1; available.formUnion(names); registeredFiles[url.path] = FontFileStamp.read(url) }
        }
        return count
    }
}

final class Library: ObservableObject {
    @Published var workspace = false
    @Published var tagQuery = TagQuery()
    @Published var folderStatus = ""
    let folderWatcher = FolderWatcher()
    var autoActivatedPaths: Set<String> = []
    var autoActivatedStamps: [String: FontFileStamp] = [:]
    lazy var studio = StudioStore(url: saveURL.deletingLastPathComponent().appendingPathComponent("spaces.json"))
    func pairSelection(_ names: [String]) {
        guard !studio.readBlocked else { message = studio.error; return }
        let active = studio.state.spaces.first(where: { $0.id == studio.focusedSpace })?.id
        guard let space = active ?? studio.state.spaces.first?.id ?? studio.addSpace("My projects") else { message = studio.error; return }
        guard studio.addBoard(space: space, fonts: names) != nil else { message = studio.error; return }
        if !names.isEmpty { _ = recordFontUses(names) }
        workspace = true
    }
    @Published var families: [Family] = []
    var originalFamilies: [Family] = []
    @Published var pro = ProState()
    @Published var advanced = AdvancedFilter()
    @Published var selectedFamilies: Set<String> = []
    @Published var showTools = false
    @Published var toolsTab = "Tags"
    @Published var repairURL: URL?
    @Published var showAdvanced = false
    var librarySaveBlocked = false
    var pendingImportFolder: String?
    var queuedReload = false
    var queuedRegistration = false
    var resolvedFolders: [String] = []
    var reportedFolderAccessFailures: Set<String> = []
    var proSaveBlocked = false
    var proURL: URL { saveURL.deletingLastPathComponent().appendingPathComponent("pro-library.json") }
    var allFaces: [Face] { families.flatMap(\.faces) }
    var selectedFaces: [Face] { families.filter { selectedFamilies.contains($0.name) }.flatMap(\.faces) }
    func openTools(_ tab: String) { toolsTab = tab; showTools = true }
    @discardableResult func savePro() -> Bool {
        guard !proSaveBlocked else { message = "Pro settings could not be read. The existing file has been preserved."; return false }
        do { try FileManager.default.createDirectory(at: proURL.deletingLastPathComponent(), withIntermediateDirectories: true); try LibraryBackupTools.preserve(proURL); try JSONEncoder().encode(pro).write(to: proURL, options: .atomic); return true }
        catch { message = "Could not save settings: " + error.localizedDescription; return false }
    }
    func acceptCatalog(_ catalog: [Family]) {
        originalFamilies = catalog
        regroup()
        if let folder = pendingImportFolder { pendingImportFolder = nil; recordImport(folder: folder) }
    }
    func recordImport(folder: String) {
        let root = URL(fileURLWithPath: folder).resolvingSymlinksInPath().path + "/"
        let names = Set(allFaces.filter { $0.url?.resolvingSymlinksInPath().path.hasPrefix(root) == true }.map(\.name))
        guard !names.isEmpty else { return }
        saved.lastImportNames = names; saved.lastImportDate = Date()
        saved.lastImportSource = URL(fileURLWithPath: folder).lastPathComponent
        save()
    }
    func regroup() {
        guard !originalFamilies.isEmpty else { families = []; return }
        let groups = Dictionary(grouping: originalFamilies.flatMap(\.faces)) { pro.familyOverrides[$0.name] ?? $0.originalFamily }
        families = groups.map { name, faces in
            let sorted = faces.sorted { $0.style.localizedStandardCompare($1.style) == .orderedAscending }
            let rep = sorted.first(where: { $0.name == pro.mainPreviews[name] }) ?? sorted.first(where: { $0.style == "Regular" }) ?? sorted[0]
            let category = originalFamilies.first(where: { $0.name == rep.originalFamily })?.automaticCategory ?? .other
            return Family(name: name, faces: sorted, automaticCategory: category, variable: sorted.contains { $0.facts.variable }, writingSystems: sorted.reduce(into: []) { $0.formUnion($1.writingSystems) })
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    func editFamily(names: Set<String>, target: String?) {
        let old = families
        for name in names { if let target = target { pro.familyOverrides[name] = target } else { pro.familyOverrides.removeValue(forKey: name) } }
        regroup()
        func remap(_ members: Set<String>) -> Set<String> {
            let fontNames = Set(old.filter { members.contains($0.name) }.flatMap { $0.faces.map(\.name) })
            return Set(families.filter { !$0.faces.allSatisfy { !fontNames.contains($0.name) } }.map(\.name)).union(members.subtracting(Set(old.map(\.name))))
        }
        saved.favorites = remap(saved.favorites)
        for (key, members) in saved.collections { saved.collections[key] = remap(members) }
        comparison = Array(remap(Set(comparison))).sorted().prefix(6).map { $0 }
        selectedFamilies = remap(selectedFamilies)
        savePro(); save()
    }
    func tags(_ family: Family) -> Set<String> { family.faces.reduce(into: []) { $0.formUnion(pro.tags[$1.name] ?? []) } }

    @Published var saved: SavedLibrary
    @Published var loading = false
    @Published var message = ""
    @Published var selection = "All Fonts"
    @Published var search = ""
    @Published var sort = "Name A–Z"
    @Published var source = "All sources"
    @Published var variableOnly = false
    @Published var detail: Family?
    @Published var writing: WritingSystem?
    @Published var requiredText = ""
    @Published var requireCoverage = false
    @Published var comparison: [String] = []
    @Published var overlayName = ""
    @Published var showCompare = false
    func toggleOverlay(_ postScriptName: String) { overlayName = overlayName == postScriptName ? "" : postScriptName }
    func chosenFace(_ family: Family) -> Face {
        let query = FontSearchQuery(search)
        let matching = family.faces.filter { face in
            (writing == nil || face.writingSystems.contains(writing!)) && (!requireCoverage || FontCoverage.missing(requiredText, in: face.coverage).isEmpty) && advanced.matches(face, tags: pro.tags[face.name] ?? []) && query.matches(face, tags: pro.tags[face.name] ?? []) && (query.text.isEmpty || family.name.localizedCaseInsensitiveContains(query.text) || face.name.localizedCaseInsensitiveContains(query.text) || face.style.localizedCaseInsensitiveContains(query.text))
        }
        return matching.first(where: { $0.name == pro.mainPreviews[family.name] }) ?? matching.first(where: { $0.name == family.representative.name }) ?? matching.first ?? family.representative
    }
    func compare(_ family: Family) {
        if comparison.contains(family.name) { comparison.removeAll { $0 == family.name } }
        else if comparison.count < 6 { comparison.append(family.name) }
        else { message = "Compare up to six families. Remove one to add another." }
    }
    var compared: [Family] { comparison.compactMap { name in families.first { $0.name == name } } }

    let saveURL: URL
    lazy var folderAccess = FolderAccess(directory: saveURL.deletingLastPathComponent())
    init(storageURL: URL? = nil) {
        saveURL = storageURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("FontShelf/library.json")
        saved = SavedLibrary()
        if FileManager.default.fileExists(atPath: saveURL.path) {
            do { saved = try JSONDecoder().decode(SavedLibrary.self, from: Data(contentsOf: saveURL)) }
            catch { librarySaveBlocked = true; message = "Could not read your library. The existing file was preserved; restore it from a backup before making changes." }
        }
        if FileManager.default.fileExists(atPath: proURL.path) {
            do { pro = try JSONDecoder().decode(ProState.self, from: Data(contentsOf: proURL)) }
            catch { proSaveBlocked = true; message = "Could not read advanced library settings. Existing settings were preserved." }
        }
    }
    @discardableResult func save() -> Bool {
        guard !librarySaveBlocked else { message = "The unreadable library file was preserved. Restore it from a backup before saving changes."; return false }
        do { try FileManager.default.createDirectory(at: saveURL.deletingLastPathComponent(), withIntermediateDirectories: true); try LibraryBackupTools.preserve(saveURL); try JSONEncoder().encode(saved).write(to: saveURL, options: .atomic); return true }
        catch { message = "Could not save your library: \(error.localizedDescription)"; return false }
    }
    func reload(register: Bool = false) {
        guard !loading else { queuedReload = true; queuedRegistration = queuedRegistration || register; return }
        loading = true
        var folders: [String] = []
        for path in saved.folders {
            do { folders.append(try folderAccess.restore(path)) }
            catch {
                if reportedFolderAccessFailures.insert(path).inserted {
                    message = "Folder access needs to be renewed. Open Live folders and choose \(URL(fileURLWithPath: path).lastPathComponent) again."
                }
            }
        }
        resolvedFolders = folders
        configureWatcher()
        for path in autoActivatedPaths where FontFileStamp.read(URL(fileURLWithPath: path)) != autoActivatedStamps[path] || !folders.contains(where: { FontFolderSnapshot.contains(path, root: $0) }) {
            do { try ActivationManager.shared.deactivate(URL(fileURLWithPath: path), restore: false); autoActivatedPaths.remove(path); autoActivatedStamps.removeValue(forKey: path) }
            catch { folderStatus = error.localizedDescription }
        }
        let accessibleFolders = folders
        let showInstalledFirst = originalFamilies.isEmpty
        DispatchQueue.global(qos: .userInitiated).async {
            if showInstalledFirst && register && !accessibleFolders.isEmpty {
                let installed = FontCatalog.scan()
                DispatchQueue.main.async { self.originalFamilies = installed; self.regroup() }
                if !FontCatalog.reconcileFolders(accessibleFolders) {
                    DispatchQueue.main.async { self.acceptCatalog(installed); self.applyFolderActivation(); if self.folderStatus == "Changes detected; refreshing…" { self.folderStatus = "Up to date" }; self.finishLoading() }
                    return
                }
            } else if register {
                FontCatalog.reconcileFolders(accessibleFolders)
            }
            let result = FontCatalog.scan()
            DispatchQueue.main.async { self.acceptCatalog(result); self.applyFolderActivation(); if self.folderStatus == "Changes detected; refreshing…" { self.folderStatus = "Up to date" }; self.finishLoading() }
        }
    }
    func finishLoading() {
        loading = false
        if queuedReload {
            let register = queuedRegistration
            queuedReload = false; queuedRegistration = false
            reload(register: register)
        }
    }
    func category(_ f: Family) -> Category { saved.overrides[f.name] ?? f.automaticCategory }
    func favorite(_ f: Family) { if saved.favorites.contains(f.name) { saved.favorites.remove(f.name) } else { saved.favorites.insert(f.name) }; save() }
    func matchesSection(_ f: Family, _ section: String) -> Bool {
        if section == "All Fonts" { return true }
        if section == "Last Import" { return f.faces.contains { saved.lastImportNames?.contains($0.name) == true } }
        if section == "Favorites" { return saved.favorites.contains(f.name) }
        if section.hasPrefix("tag:") { return TagQuery.contains(String(section.dropFirst(4)), in: tags(f)) }
        if section.hasPrefix("collection:") { return saved.collections[String(section.dropFirst(11))]?.contains(f.name) ?? false }
        return category(f).rawValue == section
    }
    var filtered: [Family] {
        let parsed = FontSearchQuery(search)
        let query = parsed.text
        let result = families.filter { f in
            matchesSection(f, selection) && tagQuery.matches(tags(f)) && f.faces.contains { face in (writing == nil || face.writingSystems.contains(writing!)) && (!requireCoverage || FontCoverage.missing(requiredText, in: face.coverage).isEmpty) && advanced.matches(face, tags: pro.tags[face.name] ?? []) && parsed.matches(face, tags: pro.tags[face.name] ?? []) && (query.isEmpty || f.name.localizedCaseInsensitiveContains(query) || face.name.localizedCaseInsensitiveContains(query) || face.style.localizedCaseInsensitiveContains(query)) } && (!variableOnly || f.variable) && (source == "All sources" || (source == "User / third-party" ? f.userFont : !f.userFont))
        }
        return result.sorted { a,b in
            if sort == "Most styles", a.faces.count != b.faces.count { return a.faces.count > b.faces.count }
            if sort == "Category", category(a) != category(b) { return category(a).rawValue < category(b).rawValue }
            return a.name.localizedStandardCompare(b.name) == (sort == "Name Z–A" ? .orderedDescending : .orderedAscending)
        }
    }
    func addFolder() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        panel.prompt = "Add & Watch"
        panel.message = "Add this folder and watch it live. Fonts in its subfolders are included, and additions, replacements and removals update automatically every three seconds while FontShelf is open. Nothing is installed or moved."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try folderAccess.remember(url) } catch { message = "Could not retain folder access: " + error.localizedDescription; return }
        reportedFolderAccessFailures.remove(url.path)
        if !saved.folders.contains(url.path) { saved.folders.append(url.path); save() }
        if !resolvedFolders.contains(url.path) { resolvedFolders.append(url.path) }
        openTools("Folders")
        if loading {
            folderStatus = "Folder added. Its first scan is queued behind the current scan; live watching starts when that scan finishes."
            reload(register: true)
            return
        }
        loading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let count = FontCatalog.registerFolder(url.path)
            let result = FontCatalog.scan()
            DispatchQueue.main.async { self.acceptCatalog(result); if count > 0 { self.recordImport(folder: url.path) }; self.configureWatcher(); self.applyFolderActivation(); self.finishLoading(); self.message = "Watching \(url.lastPathComponent) and its subfolders. Loaded \(count) new font files; changes update automatically while FontShelf is open." }
        }
    }
}

struct FontPreview: NSViewRepresentable {
    let text: String
    let name: String
    let size: Double
    var wraps = false
    var ink: NSColor? = nil
    var variations: [Int: Double] = [:]
    var features: [String: Int] = [:]
    var baseline: Double? = nil
    var previewFont: CGFont? = nil
    @AppStorage("customPreviewColors") var customColors = false
    @AppStorage("previewInkHex") var inkHex = "EEEEEE"
    @AppStorage("previewPaperHex") var paperHex = "202020"
    struct Configuration: Equatable {
        let text: String, name: String, ink: String, paper: String?, appearance: String, previewName: String?
        let previewHash: UInt?
        let size: Double, wraps: Bool, baseline: Double?
        let variations: [Int: Double], features: [String: Int]
    }
    final class Coordinator { var configuration: Configuration? }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> BaselineTextView { BaselineTextView() }
    func updateNSView(_ view: BaselineTextView, context: Context) {
        let resolvedInk = ink ?? (customColors ? NSColor(hex: inkHex) : .labelColor)
        let resolvedPaper = ink == nil && customColors ? NSColor(hex: paperHex) : nil
        let configuration = Configuration(text: text, name: name, ink: resolvedInk.rgbHex, paper: resolvedPaper?.rgbHex, appearance: NSApp.effectiveAppearance.name.rawValue, previewName: previewFont.map { $0.postScriptName as String? } ?? nil, previewHash: previewFont.map(CFHash), size: size, wraps: wraps, baseline: baseline, variations: variations, features: features)
        guard configuration != context.coordinator.configuration else { return }
        context.coordinator.configuration = configuration
        view.text = text
        view.font = previewFont.map { CTFontCreateWithGraphicsFont($0, size, nil, nil) } ?? OpenType.font(name: name, size: size, axes: variations, features: features)
        view.ink = resolvedInk
        view.paper = resolvedPaper
        view.wraps = wraps
        view.baseline = baseline
        view.invalidateContent()
        view.setAccessibilityLabel(text)
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView view: BaselineTextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0 else { return nil }
        return CGSize(width: width, height: view.layout(width: width).height)
    }
}

struct ContentView: View {
    @ObservedObject var library: Library
    @AppStorage("previewText") var preview = "The quick brown fox jumps over the lazy dog."
    @AppStorage("previewSize") var size = 64.0
    @AppStorage("adaptiveGridView") var grid = true
    @State var metadataView = false
    @AppStorage("appearance") var appearance = "Dark"
    @State var collectionName = ""
    @State var showCollection = false
    @State var showColors = false
    @State var showTagFilters = false
    @State var showDiscovery = false
    @AppStorage(WorkspaceSidebarPreference.key) var sidebarCollapsed = false
    @FocusState private var searchFocused: Bool
    var body: some View {
        ZStack(alignment: .leading) {
        HStack(spacing: 0) {
            if !library.workspace && !sidebarCollapsed { WorkspaceSidebarShell { sidebar }.transition(.move(edge: .leading).combined(with: .opacity)) }
            if library.workspace {
                StudioView(library: library, store: library.studio, sidebarCollapsed: $sidebarCollapsed)
            } else { VStack(spacing: 0) {
                let visibleFamilies = library.filtered
                topControls
                libraryContent(visibleFamilies)
                Divider()
                HStack { Circle().fill(Color.accentColor).frame(width: 6, height: 6); Text("\(visibleFamilies.count) \(visibleFamilies.count == 1 ? "family" : "families")"); Text("·"); Text("\(library.families.reduce(0) { $0 + $1.faces.count }) styles in library"); Spacer() }.font(.caption).foregroundStyle(.secondary).padding(12)
            }.accessibilityIdentifier("library-workspace") }
        }
        if sidebarCollapsed { WorkspaceSidebarRevealButton(collapsed: $sidebarCollapsed).padding(.leading, 4).zIndex(2) }
        }
        .background(ShelfPalette.canvas)
        .frame(minWidth: 980, minHeight: 620)
        .preferredColorScheme(appearance == "System" ? nil : appearance == "Dark" ? .dark : .light)
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("FontShelfMenu"))) { event in
            switch event.object as? String {
            case "collection": showCollection = true
            case "colors": showColors = true
            case "find": searchFocused = true
            case "larger": size = min(160, size + 4)
            case "smaller": size = max(16, size - 4)
            case "resetSize": size = 64
            case "list": grid = false
            case "grid": grid = true
            case "toggleSidebar": sidebarCollapsed.toggle()
            default: break
            }
        }
        .onChange(of: appearance) { value in NSApp.appearance = value == "System" ? nil : NSAppearance(named: value == "Dark" ? .darkAqua : .aqua) }
        .onAppear { library.requiredText = preview == "{family}" ? "" : preview }
        .onChange(of: preview) { value in library.requiredText = value == "{family}" ? "" : value; if value == "{family}" { library.requireCoverage = false } }
        .sheet(isPresented: $library.showTools) { LibraryToolsView(library: library) }
        .sheet(isPresented: $library.showCompare) { CompareView(library: library, preview: preview, size: size) }
        .sheet(isPresented: $showDiscovery) { FontDiscoveryView(library: library, eligibleFamilies: library.filtered, preview: preview == "{family}" ? "Hamburgefontsiv 0123456789" : preview) }
        .sheet(item: $library.detail) { family in DetailView(library: library, family: family, preview: preview == "{family}" ? family.name : preview, size: size) }
        .alert("New collection", isPresented: $showCollection) {
            TextField("Collection name", text: $collectionName)
            Button("Create") { let name = collectionName.trimmingCharacters(in: .whitespacesAndNewlines); if !name.isEmpty { if library.saved.collections[name] == nil { library.saved.collections[name] = [] }; library.save(); library.selection = "collection:" + name }; collectionName = "" }
            Button("Cancel", role: .cancel) { collectionName = "" }
        } message: { Text("Add families through their ••• menu or by right-clicking a preview.") }
        .alert("FontShelf", isPresented: Binding(get: { !library.message.isEmpty }, set: { if !$0 { library.message = "" } })) { Button("OK") { library.message = "" } } message: { Text(library.message) }
    }
    var topControls: some View {
        VStack(spacing: 0) {
                header
                SearchTokenChips(library: library).padding(.horizontal, 20)
                VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: "text.cursor").foregroundStyle(.secondary)
                    TextField("Type your own preview…", text: $preview).textFieldStyle(.plain)
                    Menu {
                        Button("The quick brown fox…") { preview = "The quick brown fox jumps over the lazy dog." }
                        Button("Alphabet & numbers") { preview = "ABCDEFGHIJKLMNOPQRSTUVWXYZ abcdefghijklmnopqrstuvwxyz 0123456789" }
                        ForEach(WritingSystem.allCases, id: \.self) { writing in Button(writing.rawValue) { preview = writing.sample } }
                        Button("Family names") { preview = "{family}" }
                    } label: { Image(systemName: "text.quote") }.shelfIconMenu().help("Preview text presets")
                    Divider().frame(height: 20)
                    Text("Aa").font(.system(size: 12))
                    Slider(value: $size, in: 16...160, step: 1).frame(width: 135)
                    Text("\(Int(size)) pt").monospacedDigit().foregroundStyle(.secondary).frame(width: 48)
                }.padding(14).shelfGlass(radius: 16).padding(.horizontal, 16).padding(.bottom, 12)
                HStack {
                    Button(library.tagQuery.active ? "Tag filters •" : "Tag filters") { showTagFilters.toggle() }.popover(isPresented: $showTagFilters) { TagFilterView(library: library) }
                    ShelfDropdown(title: "Source", selection: $library.source, options: ["All sources", "User / third-party", "System"].map { ($0, $0) }, showsTitle: false).frame(width: 165)
                    Toggle("Variable fonts", isOn: $library.variableOnly).toggleStyle(.checkbox)
                    Spacer()
                    ShelfDropdown(title: "Sort", selection: $library.sort, options: ["Name A–Z", "Name Z–A", "Most styles", "Category"].map { ($0, $0) }).frame(width: 180)
                    Picker("Layout", selection: $grid) { Image(systemName: "list.bullet").help("Full-width list").tag(false); Image(systemName: "square.grid.2x2").help("Adaptive grid: cards fit your preview text").tag(true) }.pickerStyle(.segmented).labelsHidden().frame(width: 70)
                }.padding(.horizontal, 16).padding(.vertical, 10)
                HStack {
                    if let writing = library.writing {
                        Button { library.writing = nil } label: { Label(writing.rawValue, systemImage: "xmark.circle") }
                        Button("Use script sample") { preview = writing.sample }
                    }
                    Toggle("Contains preview characters", isOn: $library.requireCoverage).toggleStyle(.checkbox).disabled(preview == "{family}")
                    Spacer()
                    if !library.comparison.isEmpty {
                        Button("Shortlist (\(library.comparison.count))") { library.showCompare = true }
                        Button("Clear shortlist") { library.comparison = [] }
                    }
                }.font(.caption).padding(.horizontal, 16).padding(.bottom, 10)
                if !library.overlayName.isEmpty {
                    HStack {
                        Label("Overlay", systemImage: "square.on.square").fontWeight(.semibold)
                        if let referenceFamily = library.families.first(where: { $0.faces.contains(where: { $0.name == library.overlayName }) }) {
                            Text(referenceFamily.name).foregroundStyle(.cyan).lineLimit(1)
                            ShelfDropdown(title: "Reference style", selection: $library.overlayName, options: referenceFamily.faces.map { ($0.style, $0.name) }, showsTitle: false).frame(width: 180)
                        }
                        Text("Cyan: reference · Orange: preview").foregroundStyle(.secondary)
                        Spacer()
                        Button("End overlay") { library.overlayName = "" }
                    }.font(.caption).padding(.horizontal, 16).padding(.bottom, 10)
                }
                if !library.selectedFamilies.isEmpty {
                    HStack {
                        Text("\(library.selectedFamilies.count) selected")
                        Button("Tag…") { library.openTools("Tags") }
                        Button("Create typeboard") { library.pairSelection(library.families.filter { library.selectedFamilies.contains($0.name) }.map { library.chosenFace($0).name }) }
                        Button("PDF…") { SpecimenExporter.export(faces: library.families.filter { library.selectedFamilies.contains($0.name) }.map { library.chosenFace($0) }, library: library, sample: preview == "{family}" ? "Hamburgefontsiv 0123456789" : preview) }
                        Button("Edit families…") { library.openTools("Families") }
                        Button("Export fonts…") { if let result = FontExporter.export(library.selectedFaces) { library.message = result } }
                        Button("Select visible") { library.selectedFamilies.formUnion(library.filtered.map(\.name)) }
                        Button("Clear selection") { library.selectedFamilies = [] }
                        Spacer()
                    }.font(.caption).padding(.horizontal, 16).padding(.bottom, 10)
                }
                }

        }
    }
    @ViewBuilder func libraryContent(_ visibleFamilies: [Family]) -> some View {
                if library.loading && library.families.isEmpty { ProgressView("Reading your fonts…").frame(maxWidth: .infinity, maxHeight: .infinity) }
                else if metadataView { MetadataTable(library: library) }
                else if visibleFamilies.isEmpty {
                    VStack(spacing: 12) { Image(systemName: "text.magnifyingglass").font(.system(size: 38)).foregroundStyle(.secondary); Text(library.selection == "Last Import" && library.saved.lastImportNames == nil ? "No imports yet" : "No matching fonts").font(.title2); Text(library.selection == "Last Import" && library.saved.lastImportNames == nil ? "Your next font-folder import or Google Fonts download will appear here." : "Try a different search or filter, or add fonts to this collection.").foregroundStyle(.secondary)
                        Button("Clear filters") { library.search = ""; library.source = "All sources"; library.variableOnly = false; library.advanced = AdvancedFilter(); library.tagQuery = TagQuery(); library.writing = nil; library.requireCoverage = false; library.selection = "All Fonts" }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    GeometryReader { geometry in
                        let width = max(1, geometry.size.width - 32)
                        let cardWidth = PreviewLayout.cardWidth(text: preview == "{family}" ? "Font family" : preview, size: size, available: width)
                        let columns = grid ? max(1, Int((width + 10) / (cardWidth + 10))) : 1
                        let families = visibleFamilies
                        ScrollView {
                            LazyVStack(spacing: 10) {
                                ForEach(Array(stride(from: 0, to: families.count, by: columns)), id: \.self) { start in
                                    let row = Array(families[start..<min(start + columns, families.count)])
                                    let faces = row.map { library.chosenFace($0) }
                                    let baseline = rowBaseline(faces)
                                    HStack(alignment: .top, spacing: 10) {
                                        ForEach(0..<columns, id: \.self) { column in
                                            if start + column < families.count {
                                                card(families[start + column], face: faces[column], baseline: baseline).frame(maxWidth: .infinity, maxHeight: .infinity)
                                            } else {
                                                Color.clear.frame(maxWidth: .infinity)
                                            }
                                        }
                                    }.fixedSize(horizontal: false, vertical: true)
                                }
                            }.padding(16)
                        }
                    }
                }
    }
    var sidebar: some View {
        VStack(alignment: .leading, spacing: 6) {
            WorkspaceSidebarHeader(library: library, collapsed: $sidebarCollapsed)
            ScrollView { VStack(alignment: .leading, spacing: 6) {
            sectionLabel("LIBRARY")
            nav("All Fonts", icon: "square.stack.3d.up", key: "All Fonts")
            nav("Last Import", icon: "clock.arrow.circlepath", key: "Last Import")
            nav("Favorites", icon: "star", key: "Favorites")
            Button { library.showCompare = true } label: {
                HStack { Image(systemName: "square.on.square").frame(width: 20); Text("Shortlist"); Spacer(); Text("\(library.comparison.count)").foregroundStyle(.secondary) }.padding(.horizontal, 10).padding(.vertical, 9).contentShape(Rectangle())
            }.buttonStyle(.plain).padding(.horizontal, 8).help("Compare up to six families added with +")
            Button("Google Fonts…") { library.openTools("Google Fonts") }.buttonStyle(.plain).padding(.horizontal, 18).padding(.vertical, 8)
            SidebarSection(title: "CATEGORIES", key: "sidebar.categories") {
            ForEach(Category.allCases, id: \.self) { category in nav(category.rawValue, icon: category.icon, key: category.rawValue) }
            }
            SidebarSection(title: "LANGUAGES / SCRIPTS", key: "sidebar.languages") {
            ForEach(WritingSystem.allCases, id: \.self) { writing in
                Button { library.writing = library.writing == writing ? nil : writing } label: {
                    HStack { Text(writing.mark).frame(width: 20); Text(writing.rawValue).lineLimit(1); Spacer(); Text("\(library.families.filter { $0.writingSystems.contains(writing) }.count)").font(.caption).foregroundStyle(.secondary) }.padding(.horizontal, 10).padding(.vertical, 8).contentShape(Rectangle())
                }.buttonStyle(.plain).background(library.writing == writing ? Color.accentColor.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 10)).padding(.horizontal, 8)
            }
            }
            SidebarSection(title: "TAGS", key: "sidebar.tags") {
            ForEach(TagQuery.hierarchy(Set(library.pro.tags.values.flatMap { $0 })), id: \.self) { tag in
                nav(tag, icon: "tag", key: "tag:" + tag).padding(.leading, CGFloat(tag.filter { $0 == "/" }.count) * 8).contextMenu {
                    Button("Include tag") { library.tagQuery.included.insert(tag); library.tagQuery.excluded.remove(tag); library.workspace = false; library.selection = "All Fonts" }
                    Button("Exclude tag") { library.tagQuery.excluded.insert(tag); library.tagQuery.included.remove(tag); library.workspace = false; library.selection = "All Fonts" }
                }
            }
            }
            SidebarSection(title: "COLLECTIONS", key: "sidebar.collections", onAdd: { showCollection = true }) {
            Group {
                VStack(spacing: 6) {
                    ForEach(library.saved.collections.keys.sorted(), id: \.self) { name in
                        HStack(spacing: 0) {
                            Button { library.workspace = false; library.selection = "collection:" + name } label: { Image(systemName: "folder").frame(width: 28) }.buttonStyle(.plain).accessibilityLabel("Open collection " + name)
                            ShelfEditableName(name: name, selected: library.selection == "collection:" + name, onSelect: { library.workspace = false; library.selection = "collection:" + name }, onRename: { library.renameCollection(name, to: $0) })
                            Text("\(library.families.filter { library.matchesSection($0, "collection:" + name) }.count)").font(.caption).monospacedDigit().foregroundStyle(.secondary)
                        }.padding(.horizontal, 10).padding(.vertical, 9).background(library.selection == "collection:" + name ? Color.accentColor.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 10)).padding(.horizontal, 8).contextMenu { Button("Rename collection…") { renameCollection(name) }; Button("Delete collection", role: .destructive) { library.saved.collections.removeValue(forKey: name); library.save(); if library.selection == "collection:" + name { library.selection = "All Fonts" } } }
                    }
                    if library.saved.collections.isEmpty { Text("No collections").font(.caption).foregroundStyle(.tertiary).padding(.horizontal, 14).padding(.top, 5) }
                }
            }
            }
            } }
            Spacer(minLength: 4)
            Button { library.addFolder() } label: { Label("Add font folder", systemImage: "folder.badge.plus").frame(maxWidth: .infinity, alignment: .leading) }.buttonStyle(.plain).foregroundStyle(Color.black.opacity(0.85)).padding(10).background(ShelfPalette.indiaYellow, in: RoundedRectangle(cornerRadius: 12)).padding(12)
            Button { library.openTools("Folders") } label: { Label("Live folders · \(library.saved.folders.count)", systemImage: "arrow.triangle.2.circlepath").frame(maxWidth: .infinity, alignment: .leading) }.buttonStyle(.plain).padding(.horizontal, 22).padding(.bottom, 8).help("Manage folders that update automatically, including subfolders")
            HStack { ShelfDropdown(title: "Appearance", selection: $appearance, options: ["Dark", "Light", "System"].map { ($0, $0) }, showsTitle: false); Button { library.reload() } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.plain).foregroundStyle(ShelfPalette.ink).padding(6).help("Refresh installed fonts").disabled(library.loading) }.padding(.horizontal, 12).padding(.bottom, 14)
        }
    }
    func sectionLabel(_ title: String) -> some View { Text(title).font(.system(size: 10, weight: .semibold)).tracking(0.8).foregroundStyle(.secondary).padding(.horizontal, 14).padding(.bottom, 5) }
    @ViewBuilder func navIcon(_ icon: String, key: String) -> some View {
        if key == Category.serif.rawValue {
            Text("A")
                .font(.system(size: 17, weight: .semibold, design: .serif))
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)
        } else if key == Category.sans.rawValue {
            Text("A")
                .font(.system(size: 17, weight: .semibold, design: .default))
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)
        } else {
            Image(systemName: icon).frame(width: 20)
        }
    }
    func nav(_ title: String, icon: String, key: String) -> some View {
        Button { library.workspace = false; library.selection = key } label: {
            HStack { navIcon(icon, key: key); Text(title).lineLimit(1); Spacer(); Text("\(library.families.filter { library.matchesSection($0, key) }.count)").font(.caption).monospacedDigit().foregroundStyle(.secondary) }.padding(.horizontal, 10).padding(.vertical, 9).contentShape(Rectangle())
        }.buttonStyle(.plain).background(!library.workspace && library.selection == key ? Color.accentColor.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 10)).padding(.horizontal, 8)
    }
    func renameCollection(_ name: String) {
        if let renamed = ShelfRename.prompt("Rename collection", current: name, validate: { candidate in candidate != name && library.saved.collections[candidate] != nil ? "A collection with this name already exists. Choose another name." : nil }) { _ = library.renameCollection(name, to: renamed) }
    }
    var header: some View {
        HStack {
            if library.selection.hasPrefix("collection:") {
                let name = String(library.selection.dropFirst(11))
                ShelfEditableName(name: name, onRename: { library.renameCollection(name, to: $0) }).font(.system(size: 25, weight: .semibold)).frame(minWidth: 110)
            } else { Text(library.selection.replacingOccurrences(of: "tag:", with: "")).font(.system(size: 25, weight: .semibold)) }
            Spacer()
            Button("Rediscover", systemImage: "shuffle") { showDiscovery = true }.help("Find local fonts you have not applied recently")
            Button("New typeboard", systemImage: "text.badge.plus") {
                let selected = library.families.filter { library.selectedFamilies.contains($0.name) }.map { library.chosenFace($0).name }
                library.pairSelection(selected.isEmpty ? library.compared.map { library.chosenFace($0).name } : selected)
            }.help(library.selectedFamilies.isEmpty ? "Create a typeboard in the current space using your shortlisted fonts" : "Create a typeboard in the current space using the selected fonts")
            Button { library.showAdvanced.toggle() } label: { Image(systemName: library.advanced.active ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle") }.buttonStyle(.plain).foregroundStyle(ShelfPalette.ink).padding(8).shelfGlass(radius: 16).help("Advanced filters").popover(isPresented: $library.showAdvanced) { AdvancedFiltersView(library: library) }
            Button { showColors.toggle() } label: { Image(systemName: "paintpalette") }.buttonStyle(.plain).foregroundStyle(ShelfPalette.ink).padding(8).shelfGlass(radius: 16).help("Preview colors").popover(isPresented: $showColors) { PreviewColorsView() }
            Menu("Tools") {
                ForEach(["Tags", "Families", "Duplicates", "Font Health", "Google Fonts", "Activation", "Folders"], id: \.self) { tab in Button(tab) { library.openTools(tab) } }
                Divider()
                Toggle("Metadata table", isOn: $metadataView)
                Button("Export library backup…") { LibraryBackupTools.export(library) }
                Button("Import library backup…") { LibraryBackupTools.restore(library) }
                Button("Show automatic backups") { NSWorkspace.shared.open(library.saveURL.deletingLastPathComponent().appendingPathComponent("Backups")) }
                Button("Select visible families") { library.selectedFamilies.formUnion(library.filtered.map(\.name)) }
            }.menuStyle(.borderlessButton).foregroundStyle(Color.primary).padding(8).shelfGlass(radius: 16).frame(width: 85)
            LibrarySearchView(library: library).focused($searchFocused).frame(minWidth: 220, idealWidth: 290, maxWidth: 350)
        }.padding(.horizontal, 20).padding(.vertical, 18)
    }
    func rowBaseline(_ faces: [Face]) -> Double {
        let names = faces.map(\.name) + (library.overlayName.isEmpty ? [] : [library.overlayName])
        return ceil(names.map { CTFontGetAscent(OpenType.font(name: $0, size: size, axes: library.pro.axes[$0] ?? [:], features: library.pro.features[$0] ?? [:])) }.max() ?? size) + 4
    }
    func card(_ family: Family, face: Face, baseline: Double) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Button { if library.selectedFamilies.contains(family.name) { library.selectedFamilies.remove(family.name) } else { library.selectedFamilies.insert(family.name) } } label: { Image(systemName: library.selectedFamilies.contains(family.name) ? "checkmark.circle.fill" : "circle").font(.system(size: 16)).frame(width: 28, height: 28) }.buttonStyle(.plain).help("Select family for batch actions")
                VStack(alignment: .leading, spacing: 3) {
                    Text(family.name).font(.system(size: 14, weight: .medium)).lineLimit(2)
                    Text(library.category(family).rawValue + (family.variable ? " · Variable" : "")).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }.frame(height: 42, alignment: .top)
            HStack(spacing: 8) {
                Button { library.detail = family } label: {
                    Text("\(family.faces.count) \(family.faces.count == 1 ? "style" : "styles")").font(.system(size: 13, weight: .semibold)).padding(.horizontal, 10).frame(height: 30).background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                }.buttonStyle(.plain).help("View all styles")
                Spacer(minLength: 0)
                Button { library.favorite(family) } label: { Image(systemName: library.saved.favorites.contains(family.name) ? "star.fill" : "star").foregroundStyle(library.saved.favorites.contains(family.name) ? ShelfPalette.ink : Color.primary).font(.system(size: 17)).frame(width: 30, height: 30) }.buttonStyle(.plain).help("Toggle favorite")
                Button { library.compare(family) } label: { Image(systemName: library.comparison.contains(family.name) ? "checkmark.square.fill" : "plus.square").font(.system(size: 17)).frame(width: 30, height: 30) }.buttonStyle(.plain).help("Add or remove from shortlist — open Shortlist in the sidebar")
                Button { library.toggleOverlay(face.name) } label: {
                    Text("AB").font(.system(size: 13, weight: .bold)).foregroundStyle(library.overlayName == face.name ? Color.cyan : Color.primary).frame(width: 30, height: 30)
                }.buttonStyle(.plain).help(library.overlayName == face.name ? "Turn off the library overlay" : "Compare this font over every preview in the library").accessibilityLabel(library.overlayName == face.name ? "Turn off \(family.name) library overlay" : "Use \(family.name) as library overlay")
                Menu { actions(family) } label: { Image(systemName: "ellipsis").font(.system(size: 17)) }.shelfIconMenu().help("Font actions")
            }
            if !library.overlayName.isEmpty {
                OverlayPreview(text: preview == "{family}" ? family.name : preview, candidate: face.name, reference: library.overlayName, size: size, library: library, baseline: baseline).allowsHitTesting(false)
            } else {
                FontPreview(text: preview == "{family}" ? family.name : preview, name: face.name, size: size, wraps: true, variations: library.pro.axes[face.name] ?? [:], features: library.pro.features[face.name] ?? [:], baseline: baseline).frame(minHeight: size * 1.5, alignment: .top).allowsHitTesting(false)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).modifier(ShelfCardSurface(selected: library.selectedFamilies.contains(family.name))).contentShape(Rectangle()).onTapGesture { library.detail = family }.contextMenu { actions(family) }
    }
    @ViewBuilder func actions(_ family: Family) -> some View {
        Button("New typeboard with this font") { library.pairSelection([library.chosenFace(family).name]) }
        Button(library.comparison.contains(family.name) ? "Remove from comparison" : "Add to comparison") { library.compare(family) }
        Button("Use as overlay reference") { library.overlayName = library.chosenFace(family).name }
        Button("View all styles") { library.detail = family }
        Button(library.saved.favorites.contains(family.name) ? "Remove favorite" : "Add favorite") { library.favorite(family) }
        Menu("Set category") {
            Button("Automatic (\(family.automaticCategory.rawValue))") { library.saved.overrides.removeValue(forKey: family.name); library.save() }
            ForEach(Category.allCases, id: \.self) { c in Button(c.rawValue) { library.saved.overrides[family.name] = c; library.save() } }
        }
        Menu("Collections") {
            if library.saved.collections.isEmpty { Button("Create a collection…") { showCollection = true } }
            ForEach(library.saved.collections.keys.sorted(), id: \.self) { name in
                Button((library.saved.collections[name]!.contains(family.name) ? "✓ " : "") + name) { if library.saved.collections[name]!.contains(family.name) { library.saved.collections[name]!.remove(family.name) } else { library.saved.collections[name]!.insert(family.name) }; library.save() }
            }
        }
        Button("Export font family…") { if let result = FontExporter.export(family.faces) { library.message = result } }
        Button("Edit tags…") { library.selectedFamilies = [family.name]; library.openTools("Tags") }
        Button("Edit family…") { library.selectedFamilies = [family.name]; library.openTools("Families") }
        if let url = family.representative.url { Button("Inspect font file…") { library.repairURL = url; library.openTools("Font Health") } }
        Button("Copy family name") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(family.name, forType: .string) }
        if let url = family.representative.url { Button("Show font file in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) } }
    }
}

struct Axis: Identifiable {
    let id: Int
    let name: String
    let min: Double
    let max: Double
    let defaultValue: Double
}
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    var window: NSWindow!
    let library = Library()
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        let theme = UserDefaults.standard.string(forKey: "appearance") ?? "Dark"
        NSApp.appearance = theme == "System" ? nil : NSAppearance(named: theme == "Dark" ? .darkAqua : .aqua)
        let root = ContentView(library: library).tint(ShelfPalette.indiaYellow).accentColor(ShelfPalette.indiaYellow)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1240, height: 850), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = false
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.title = "FontShelf"; window.minSize = NSSize(width: 980, height: 660)
        window.contentView = NSHostingView(rootView: root)
        window.center(); window.setFrameAutosaveName("FontShelfWindow"); window.makeKeyAndOrderFront(nil)
        let menu = NSMenu()
        let appItem = NSMenuItem(); menu.addItem(appItem)
        let appMenu = NSMenu(); appItem.submenu = appMenu
        appMenu.addItem(withTitle: "About FontShelf", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(withTitle: "Privacy…", action: #selector(showPrivacy), keyEquivalent: "")
        appMenu.addItem(.separator()); appMenu.addItem(withTitle: "Quit FontShelf", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let fileMenu = addMenu("File", to: menu)
        addCommand("Add Font Folder…", "folder", to: fileMenu, key: "o")
        addCommand("Browse Google Fonts…", "Google Fonts", to: fileMenu)
        addCommand("New Collection…", "collection", to: fileMenu, key: "n")
        addCommand("Spaces", "spaces", to: fileMenu)
        addCommand("New Typeboard", "pair", to: fileMenu, key: "k")
        addCommand("Watched Folders…", "Folders", to: fileMenu)
        addCommand("Inspect Font Files…", "Font Health", to: fileMenu)
        addCommand("Export Library Backup…", "backup", to: fileMenu)
        addCommand("Import Library Backup…", "restoreBackup", to: fileMenu)
        fileMenu.addItem(.separator())
        addCommand("Find Duplicates…", "Duplicates", to: fileMenu)
        addCommand("Manage Families…", "Families", to: fileMenu)
        addCommand("Tag Backups…", "Tags", to: fileMenu)
        addCommand("Export Selected Fonts…", "export", to: fileMenu)
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        let editItem = NSMenuItem(); menu.addItem(editItem); let editMenu = NSMenu(title: "Edit"); editItem.submenu = editMenu
        for (title, action, key) in [("Undo", "undo:", "z"), ("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] { editMenu.addItem(withTitle: title, action: Selector(action), keyEquivalent: key) }
        let redo = editMenu.insertItem(withTitle: "Redo", action: NSSelectorFromString("redo:"), keyEquivalent: "z", at: 1)
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.item(at: 0)?.target = self; redo.target = self
        editMenu.addItem(.separator())
        addCommand("Find Fonts…", "find", to: editMenu, key: "f")
        addCommand("Select Visible Families", "select", to: editMenu)
        addCommand("Deselect Families", "deselect", to: editMenu)
        let fontMenu = addMenu("Font", to: menu)
        addCommand("Inspect Selected Family…", "inspect", to: fontMenu, key: "i")
        addCommand("Edit Tags…", "tagSelected", to: fontMenu, key: "t")
        addCommand("Edit Selected Families…", "familySelected", to: fontMenu)
        addCommand("Toggle Favorites", "favorite", to: fontMenu)
        addCommand("Compare Selected Families…", "compareSelected", to: fontMenu)
        addCommand("Copy Family Names", "copyNames", to: fontMenu)
        fontMenu.addItem(.separator())
        addCommand("Temporary Activations…", "Activation", to: fontMenu)
        let viewMenu = addMenu("View", to: menu)
        addCommand("List", "list", to: viewMenu, key: "1")
        addCommand("Grid", "grid", to: viewMenu, key: "2")
        viewMenu.addItem(.separator())
        let sidebarItem = addCommand("Hide Sidebar", "toggleSidebar", to: viewMenu, key: "s")
        sidebarItem.keyEquivalentModifierMask = [.command, .control]
        viewMenu.addItem(.separator())
        addCommand("Larger Preview", "larger", to: viewMenu, key: "+")
        addCommand("Smaller Preview", "smaller", to: viewMenu, key: "-")
        addCommand("Reset Preview Size", "resetSize", to: viewMenu, key: "0")
        addCommand("Preview Colors…", "colors", to: viewMenu)
        viewMenu.addItem(.separator())
        addCommand("Advanced Filters…", "filters", to: viewMenu)
        addCommand("Clear Filters", "clearFilters", to: viewMenu)
        addCommand("Show Shortlist…", "comparison", to: viewMenu)
        addCommand("Refresh Fonts", "refresh", to: viewMenu, key: "r")
        let windowItem = NSMenuItem()
        menu.addItem(windowItem)
        let windowMenu = NSMenu(title: "Window")
        windowItem.submenu = windowMenu
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        let fullScreenItem = windowMenu.addItem(withTitle: "Enter Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        fullScreenItem.keyEquivalentModifierMask = [.command, .control]
        NSApp.windowsMenu = windowMenu
        NSApp.mainMenu = menu
        NSApp.activate(ignoringOtherApps: true)
        let activationErrors = ActivationManager.shared.clear(restore: false)
        if !activationErrors.isEmpty { library.message = "Some previous temporary activations could not be cleared: " + activationErrors.joined(separator: "\n") }
        library.reload(register: true)
    }
    func addMenu(_ title: String, to parent: NSMenu) -> NSMenu {
        let item = NSMenuItem(); parent.addItem(item)
        let submenu = NSMenu(title: title); item.submenu = submenu; return submenu
    }
    @discardableResult func addCommand(_ title: String, _ command: String, to menu: NSMenu, key: String = "") -> NSMenuItem {
        let item = menu.addItem(withTitle: title, action: #selector(runMenuCommand(_:)), keyEquivalent: key)
        item.target = self; item.representedObject = command
        return item
    }
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(undo(_:)) { item.title = activeUndoManager?.undoMenuItemTitle ?? "Undo"; return activeUndoManager?.canUndo == true }
        if item.action == #selector(redo(_:)) { item.title = activeUndoManager?.redoMenuItemTitle ?? "Redo"; return activeUndoManager?.canRedo == true }
        guard let command = item.representedObject as? String else { return true }
        guard window.isKeyWindow, window.attachedSheet == nil else { return false }
        let selected = library.families.filter { library.selectedFamilies.contains($0.name) }
        switch command {
        case "inspect": return selected.count == 1
        case "export", "tagSelected", "familySelected", "favorite", "copyNames", "deselect": return !selected.isEmpty
        case "compareSelected": return (2...6).contains(selected.count)
        case "comparison": return true
        case "refresh": return !library.loading
        case "toggleSidebar": item.title = WorkspaceSidebarPreference.collapsed() ? "Show Sidebar" : "Hide Sidebar"
        case "list", "grid": item.state = (UserDefaults.standard.object(forKey: "adaptiveGridView") as? Bool ?? true) == (command == "grid") ? .on : .off
        default: break
        }
        return true
    }
    var activeUndoManager: UndoManager? {
        if let text = window.firstResponder as? NSTextView, !(library.workspace && text.isFieldEditor), let manager = text.undoManager, manager.canUndo || manager.canRedo { return manager }
        return library.workspace ? library.studio.undoManager : nil
    }
    @objc func undo(_ sender: Any?) { let manager = activeUndoManager; if manager === library.studio.undoManager { window.makeFirstResponder(window) }; manager?.undo() }
    @objc func redo(_ sender: Any?) { let manager = activeUndoManager; if manager === library.studio.undoManager { window.makeFirstResponder(window) }; manager?.redo() }
    @objc func runMenuCommand(_ sender: NSMenuItem) {
        guard validateMenuItem(sender), let command = sender.representedObject as? String else { return }
        let selected = library.families.filter { library.selectedFamilies.contains($0.name) }
        switch command {
        case "folder": library.addFolder()
        case "spaces": library.workspace = true
        case "pair": library.pairSelection(selected.isEmpty ? library.compared.map { library.chosenFace($0).name } : selected.map { library.chosenFace($0).name })
        case "backup": LibraryBackupTools.export(library)
        case "restoreBackup": LibraryBackupTools.restore(library)
        case "Tags", "Families", "Duplicates", "Font Health", "Google Fonts", "Activation", "Folders": library.openTools(command)
        case "tagSelected": library.openTools("Tags")
        case "familySelected": library.openTools("Families")
        case "export": if let result = FontExporter.export(library.selectedFaces) { library.message = result }
        case "select": library.selectedFamilies.formUnion(library.filtered.map(\.name))
        case "deselect": library.selectedFamilies = []
        case "inspect": library.detail = selected.first
        case "favorite": for family in selected { library.favorite(family) }
        case "compareSelected": library.comparison = selected.map(\.name); library.showCompare = true
        case "comparison": library.showCompare = true
        case "copyNames": NSPasteboard.general.clearContents(); NSPasteboard.general.setString(selected.map(\.name).joined(separator: "\n"), forType: .string)
        case "filters": library.showAdvanced.toggle()
        case "clearFilters": library.search = ""; library.source = "All sources"; library.variableOnly = false; library.advanced = AdvancedFilter(); library.tagQuery = TagQuery(); library.writing = nil; library.requireCoverage = false; library.selection = "All Fonts"
        case "refresh": library.reload(register: true)
        default: NotificationCenter.default.post(name: Notification.Name("FontShelfMenu"), object: command)
        }
    }
    @objc func showPrivacy() {
        let alert = NSAlert(); alert.messageText = "FontShelf privacy"
        alert.informativeText = "FontShelf stores your collections, tags, notes, and preferences on this Mac. It has no account, analytics, advertising, or tracking. Your fonts and library are not uploaded.\n\nWhen you browse Google font previews or request a download, FontShelf connects to GitHub to retrieve that public font and its license. GitHub receives ordinary connection information, including your IP address and the requested file.\n\nFolder access is granted through the system picker. Exports are written only to the destination you choose. Adobe scripts are saved for you to run yourself; FontShelf does not control Adobe apps."
        alert.addButton(withTitle: "OK"); alert.runModal()
    }
    func applicationWillTerminate(_ notification: Notification) { ActivationManager.shared.clear(restore: false) }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

enum PerformanceAudit {
    private static func measure(iterations: Int, _ work: () -> Int) -> (milliseconds: Double, checksum: Int) {
        let start = CFAbsoluteTimeGetCurrent()
        var checksum = 0
        for _ in 0..<iterations { autoreleasepool { checksum &+= work() } }
        return ((CFAbsoluteTimeGetCurrent() - start) * 1_000 / Double(iterations), checksum)
    }

    static func run() {
        let scanStart = CFAbsoluteTimeGetCurrent()
        let catalog = FontCatalog.scan()
        let scanMilliseconds = (CFAbsoluteTimeGetCurrent() - scanStart) * 1_000

        let library = Library(storageURL: FileManager.default.temporaryDirectory.appendingPathComponent("FontShelf-performance-audit-" + UUID().uuidString + "/library.json"))
        library.families = catalog
        library.search = "a"
        let filtering = measure(iterations: 100) { library.filtered.reduce(0) { $0 &+ $1.faces.count } }

        var direction = TypeDirection(name: "Performance audit", fonts: ["Helvetica", "Times-Roman"])
        direction.canvas = .editorial
        direction.width = 1_200
        let direct = measure(iterations: 20) { CanvasPlan(direction: direction).elements.count }
        CanvasPlanCache.removeAll()
        _ = CanvasPlanCache.plan(for: direction)
        let cached = measure(iterations: 200) { CanvasPlanCache.plan(for: direction).elements.count }
        precondition(direct.checksum / 20 == cached.checksum / 200, "Cached canvas plan changed its output")

        print(String(format: "PERF catalog scan: %.2f ms (%d families, %d styles)", scanMilliseconds, catalog.count, catalog.reduce(0) { $0 + $1.faces.count }))
        print(String(format: "PERF library filter: %.3f ms/pass", filtering.milliseconds))
        print(String(format: "PERF canvas plan: %.3f ms uncached, %.6f ms cached (%.1fx faster)", direct.milliseconds, cached.milliseconds, direct.milliseconds / max(0.000_001, cached.milliseconds)))
    }
}

if let index = CommandLine.arguments.firstIndex(of: "--font-available"), CommandLine.arguments.count > index + 1 {
    let names = CTFontManagerCopyAvailablePostScriptNames() as? [String] ?? []
    exit(names.contains(CommandLine.arguments[index + 1]) ? 0 : 1)
} else if let index = CommandLine.arguments.firstIndex(of: "--integration-check"), CommandLine.arguments.count > index + 1 {
    do { try StudioChecks.integration(source: URL(fileURLWithPath: CommandLine.arguments[index + 1])) }
    catch { fputs("Integration check failed: \(error.localizedDescription)\n", stderr); exit(1) }
} else if let index = CommandLine.arguments.firstIndex(of: "--handoff-fixture"), CommandLine.arguments.count > index + 1 {
    do { print(try StudioChecks.handoff(catalog: FontCatalog.scan(), parent: URL(fileURLWithPath: CommandLine.arguments[index + 1])).path) }
    catch { fputs("Handoff check failed: \(error.localizedDescription)\n", stderr); exit(1) }
} else if CommandLine.arguments.contains("--performance-audit") {
    PerformanceAudit.run()
} else if CommandLine.arguments.contains("--self-test") {
    for pointSize in [52.0, 131.0] {
        let views = ["Helvetica", "Times-Roman"].map { name -> BaselineTextView in
            let view = BaselineTextView()
            view.font = CTFontCreateWithName(name as CFString, pointSize, nil)
            view.text = "i can feel the quick brown fox jumping over the lazy dog"
            view.wraps = true
            view.baseline = pointSize * 1.4
            return view
        }
        precondition(views[0].layout(width: 320).first == views[1].layout(width: 320).first)
        for view in views {
            let wrapped = view.layout(width: 320)
            precondition(wrapped.lines.count > 1)
            precondition(wrapped.height > wrapped.first + Double(wrapped.lines.count - 1) * wrapped.advance)
            precondition(view.layout(width: 4000).lines.count == 1)
        }
    }

    precondition(PreviewLayout.cardWidth(text: "h", size: 160, available: 1500) < PreviewLayout.cardWidth(text: "there is", size: 160, available: 1500))
    precondition(PreviewLayout.cardWidth(text: String(repeating: "long sentence ", count: 20), size: 160, available: 800) == 800)
    precondition(PreviewLayout.cardWidth(text: "there is", size: 32, available: 1500) < PreviewLayout.cardWidth(text: "there is", size: 160, available: 1500))
    let fonts = FontCatalog.scan()
    precondition(!fonts.isEmpty, "No installed fonts found")
    precondition(Set(fonts.map(\.id)).count == fonts.count, "Duplicate families")
    for (name, expected) in [("Times-Roman", Category.serif), ("Helvetica", .sans), ("Courier", .mono)] {
        let font = CTFontCreateWithName(name as CFString, 24, nil)
        precondition(FontCatalog.category(font) == expected, "Classification failed for \(name)")
    }
    let testLibrary = Library(storageURL: FileManager.default.temporaryDirectory.appendingPathComponent("FontShelf-tests-" + UUID().uuidString + "/library.json")); testLibrary.families = fonts
    testLibrary.search = "Helvetica"
    precondition(!testLibrary.filtered.isEmpty && testLibrary.filtered.allSatisfy { $0.name.localizedCaseInsensitiveContains("Helvetica") || $0.faces.contains { $0.name.localizedCaseInsensitiveContains("Helvetica") } })
    testLibrary.search = ""; testLibrary.selection = "Monospaced"
    precondition(testLibrary.filtered.allSatisfy { testLibrary.category($0) == .mono })
    testLibrary.selection = "All Fonts"; testLibrary.sort = "Most styles"
    let sorted = testLibrary.filtered
    precondition(zip(sorted, sorted.dropFirst()).allSatisfy { $0.faces.count >= $1.faces.count })
    testLibrary.saved.collections["Test"] = [fonts[0].name]; testLibrary.selection = "collection:Test"
    precondition(testLibrary.filtered.count == 1)
    testLibrary.saved.overrides[fonts[0].name] = .script
    precondition(testLibrary.category(fonts[0]) == .script)
    testLibrary.saved.lastImportNames = [fonts[0].faces[0].name]
    testLibrary.saved.lastImportDate = Date()
    precondition(testLibrary.matchesSection(fonts[0], "Last Import"))
    let legacyData = Data("{\"favorites\":[],\"overrides\":{},\"collections\":{},\"folders\":[]}".utf8)
    let legacyLibrary = try JSONDecoder().decode(SavedLibrary.self, from: legacyData)
    precondition(legacyLibrary.lastImportNames == nil)
    let encoded = try JSONEncoder().encode(testLibrary.saved)
    let decoded = try JSONDecoder().decode(SavedLibrary.self, from: encoded)
    precondition(decoded.collections["Test"] == [fonts[0].name])
    precondition(decoded.lastImportNames == testLibrary.saved.lastImportNames)
    let ascii = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")
    precondition(WritingSystem.latin.supported(by: ascii))
    precondition(!WritingSystem.devanagari.supported(by: ascii))
    precondition(!WritingSystem.japanese.supported(by: ascii))
    for script in WritingSystem.allCases {
        precondition(script.supported(by: CharacterSet(charactersIn: script.probe)))
    }
    precondition(!WritingSystem.japanese.supported(by: CharacterSet(charactersIn: WritingSystem.simplified.probe)))
    precondition(FontCoverage.missing("Hello हह", in: ascii).count == 1)
    precondition(FontCoverage.missing("Hello \n", in: ascii).isEmpty)
    testLibrary.selection = "All Fonts"; testLibrary.writing = .devanagari
    precondition(testLibrary.filtered.allSatisfy { $0.writingSystems.contains(.devanagari) })
    testLibrary.writing = nil; testLibrary.requireCoverage = true; testLibrary.requiredText = "हिन्दी"
    precondition(testLibrary.filtered.allSatisfy { family in family.faces.contains { FontCoverage.missing("हिन्दी", in: $0.coverage).isEmpty } })
    testLibrary.requireCoverage = false; testLibrary.compare(fonts[0]); precondition(testLibrary.compared.count == 1)
    testLibrary.compare(fonts[0]); precondition(testLibrary.compared.isEmpty)
    AdobeBridge.selfTest()
    do { try ProChecks.run(catalog: fonts); try StudioChecks.run(catalog: fonts); try FontRepairChecks.run(catalog: fonts) }
    catch { fputs("Regression check failed: \(error.localizedDescription)\n", stderr); exit(1) }
    print("PASS: script probes, combined filters, missing characters, comparison and Adobe export DOM fixtures.")
    print("PASS: \(fonts.count) families, \(fonts.reduce(0) { $0 + $1.faces.count }) styles. Classification, search, filters, sorting, collections, overrides and persistence verified.")
    for c in Category.allCases { print("\(c.rawValue): \(fonts.filter { $0.automaticCategory == c }.count)") }
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
