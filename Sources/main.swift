import SwiftUI
import AppKit
import Combine
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
struct SavedSearch: Codable, Equatable {
    var section: String
    var query: String
    var sort: String
    var source: String
    var writing: String?
    var variableOnly: Bool
    var tagQuery: TagQuery
    var advanced: AdvancedFilter
    var requireCoverage: Bool
    var requiredText: String
    /// Added after saved searches were introduced; nil keeps older files readable.
    var previewText: String? = nil
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
    var savedSearches: [String: SavedSearch]?
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

enum WorkspaceMode: String, CaseIterable, Identifiable {
    case library = "Library"
    case spaces = "Spaces"
    case fontLab = "Letterform Editor"
    var id: String { rawValue }
}

final class Library: ObservableObject {
    @Published var workspace = WorkspaceMode.library
    @Published var typeboardDraft: TypeboardSeedDraft?
    @Published var tagQuery = TagQuery() { didSet { invalidateFilteredCatalog() } }
    @Published var folderStatus = ""
    let folderWatcher = FolderWatcher()
    var autoActivatedPaths: Set<String> = []
    var autoActivatedStamps: [String: FontFileStamp] = [:]
    lazy var studio = StudioStore(url: saveURL.deletingLastPathComponent().appendingPathComponent("spaces.json"), recoveryError: backupRecoveryError)
    private var retainedStudioSession: StudioEditorSession?
    func editorSession(for board: TypeBoard) -> StudioEditorSession {
        if let retainedStudioSession, retainedStudioSession.board.id == board.id { return retainedStudioSession }
        let session = StudioEditorSession(board: board)
        retainedStudioSession = session
        return session
    }
    lazy var fontLab = FontLabStore(url: saveURL.deletingLastPathComponent().appendingPathComponent("font-lab.json"), recoveryError: backupRecoveryError)
    func pairSelection(_ names: [String], source: String = "Selected fonts", spaceID: UUID? = nil) {
        guard !studio.readBlocked else { message = studio.error; return }
        let unique = names.reduce(into: [String]()) { values, name in if !values.contains(name) { values.append(name) } }
        if !unique.isEmpty { typeboardDraft = TypeboardSeedDraft(fonts: unique, source: source, spaceID: spaceID); return }
        let active = studio.state.spaces.first(where: { $0.id == studio.focusedSpace })?.id
        guard studio.createBoard(in: active ?? studio.state.spaces.first?.id, defaultSpaceName: "My projects") != nil else { message = studio.error; return }
        workspace = .spaces
    }
    func createTypeboard(from draft: TypeboardSeedDraft, roles: [String: String]) {
        guard !studio.readBlocked else { message = studio.error; return }
        let requested = draft.spaceID.flatMap { id in studio.state.spaces.first(where: { $0.id == id })?.id }
        let active = requested ?? studio.state.spaces.first(where: { $0.id == studio.focusedSpace })?.id
        guard studio.createBoard(in: active ?? studio.state.spaces.first?.id, defaultSpaceName: "My projects", fonts: draft.fonts, roleFonts: roles) != nil else { message = studio.error; return }
        _ = recordFontUses(Array(Set(roles.values)))
        typeboardDraft = nil
        workspace = .spaces
    }
    func contextualTypeboardSeed() -> (fonts: [String], source: String) {
        if !selectedFamilies.isEmpty {
            return (families.filter { selectedFamilies.contains($0.name) }.map { chosenFace($0).name }, "Selected Library fonts")
        }
        if selection == "Favorites" || selection.hasPrefix("collection:") {
            let values = families.filter { matchesSection($0, selection) }.map { chosenFace($0).name }
            let label = selection == "Favorites" ? "Favorites" : "Collection “" + String(selection.dropFirst(11)) + "”"
            if !values.isEmpty { return (values, label) }
        }
        return (compared.map { chosenFace($0).name }, comparison.isEmpty ? "Blank typeboard" : "Shortlist")
    }
    @Published var families: [Family] = [] {
        willSet { rebuildCatalogIndexes(for: newValue) }
        didSet { invalidateFilteredCatalog() }
    }
    var originalFamilies: [Family] = []
    @Published var pro = ProState() { didSet { invalidateFilteredCatalog() } }
    @Published var advanced = AdvancedFilter() { didSet { invalidateFilteredCatalog() } }
    @Published var selectedFamilies: Set<String> = []
    @Published var showTools = false
    @Published var toolsTab = "Tags"
    @Published var repairURL: URL?
    @Published var showAdvanced = false
    var librarySaveBlocked = false
    var backupRecoveryError: String?
    var pendingImportFolder: String?
    var queuedReload = false
    var queuedRegistration = false
    var resolvedFolders: [String] = []
    var savedPathsByResolvedFolder: [String: Set<String>] = [:]
    @Published var pausedFolders: Set<String> = []
    var reportedFolderAccessFailures: Set<String> = []
    var proSaveBlocked = false
    var proURL: URL { saveURL.deletingLastPathComponent().appendingPathComponent("pro-library.json") }
    private var catalogFaces: [Face] = []
    private var catalogFacesByName: [String: Face] = [:]
    private var catalogFamiliesByName: [String: Family] = [:]
    private var catalogFaceNames: Set<String> = []
    private(set) var styleCount = 0
    var allFaces: [Face] { catalogFaces }
    var availableFaceNames: Set<String> { catalogFaceNames }
    func face(named postScriptName: String) -> Face? { catalogFacesByName[postScriptName] }
    func family(named familyName: String) -> Family? { catalogFamiliesByName[familyName] }
    var selectedFaces: [Face] { families.filter { selectedFamilies.contains($0.name) }.flatMap(\.faces) }
    private func rebuildCatalogIndexes(for families: [Family]) {
        var faces: [Face] = []
        faces.reserveCapacity(families.reduce(0) { $0 + $1.faces.count })
        var facesByName: [String: Face] = [:]
        var familiesByName: [String: Family] = [:]
        for family in families {
            familiesByName[family.name] = family
            for face in family.faces {
                faces.append(face)
                facesByName[face.name] = face
            }
        }
        catalogFaces = faces
        catalogFacesByName = facesByName
        catalogFamiliesByName = familiesByName
        catalogFaceNames = Set(facesByName.keys)
        styleCount = faces.count
    }
    func openTools(_ tab: String) {
        if tab == "Folders", let delegate = NSApp.delegate as? AppDelegate { delegate.settingsWindow.show(library: self, page: .folders); return }
        toolsTab = tab; showTools = true
    }
    @discardableResult func savePro() -> Bool {
        guard !proSaveBlocked else { message = "Pro settings could not be read. The existing file has been preserved."; return false }
        do { try FileManager.default.createDirectory(at: proURL.deletingLastPathComponent(), withIntermediateDirectories: true); try LibraryBackupTools.preserve(proURL); try JSONEncoder().encode(pro).write(to: proURL, options: .atomic); return true }
        catch { message = "Could not save settings: " + error.localizedDescription; return false }
    }
    @discardableResult func updatePro(_ change: (inout ProState) -> Void) -> Bool {
        let previous = pro
        change(&pro)
        guard savePro() else { pro = previous; return false }
        return true
    }
    func acceptCatalog(_ catalog: [Family]) {
        originalFamilies = catalog
        regroup()
        let availableNames = Set(families.map(\.name))
        comparison.removeAll { !availableNames.contains($0) }
        selectedFamilies.formIntersection(availableNames)
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
        let automaticCategories = originalFamilies.reduce(into: [String: Category]()) { values, family in values[family.name] = family.automaticCategory }
        families = groups.map { name, faces in
            let sorted = faces.sorted { $0.style.localizedStandardCompare($1.style) == .orderedAscending }
            let rep = sorted.first(where: { $0.name == pro.mainPreviews[name] }) ?? sorted.first(where: { $0.style == "Regular" }) ?? sorted[0]
            let category = automaticCategories[rep.originalFamily] ?? .other
            return Family(name: name, faces: sorted, automaticCategory: category, variable: sorted.contains { $0.facts.variable }, writingSystems: sorted.reduce(into: []) { $0.formUnion($1.writingSystems) })
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    @discardableResult func editFamily(names: Set<String>, target: String?) -> Bool {
        guard !librarySaveBlocked else { _ = save(); return false }
        guard !proSaveBlocked else { _ = savePro(); return false }
        let previousLibraryFile: Data?
        do {
            previousLibraryFile = FileManager.default.fileExists(atPath: saveURL.path) ? try Data(contentsOf: saveURL) : nil
        } catch {
            message = "Could not read the existing library before changing families: \(error.localizedDescription)"
            return false
        }
        let previousSaved = saved
        let previousPro = pro
        let previousFamilies = families
        let previousComparison = comparison
        let previousSelection = selectedFamilies
        func restoreMemory() {
            saved = previousSaved
            pro = previousPro
            families = previousFamilies
            comparison = previousComparison
            selectedFamilies = previousSelection
        }
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
        guard save() else { restoreMemory(); return false }
        guard savePro() else {
            let saveError = message
            do {
                if let previousLibraryFile {
                    try previousLibraryFile.write(to: saveURL, options: .atomic)
                } else if FileManager.default.fileExists(atPath: saveURL.path) {
                    try FileManager.default.removeItem(at: saveURL)
                }
                message = saveError
            } catch {
                message = saveError + " The previous library file could not be restored: \(error.localizedDescription)"
            }
            restoreMemory()
            return false
        }
        return true
    }
    func tags(_ family: Family) -> Set<String> { family.faces.reduce(into: []) { $0.formUnion(pro.tags[$1.name] ?? []) } }

    @Published var saved: SavedLibrary { didSet { invalidateFilteredCatalog() } }
    @Published var loading = false
    @Published var message = ""
    @Published var resultNotice = ""
    @Published var selection = "All Fonts" { didSet { invalidateFilteredCatalog() } }
    @Published var search = "" { didSet { invalidateFilteredCatalog() } }
    @Published var sort = "Name A–Z" { didSet { invalidateFilteredCatalog() } }
    @Published var source = "All sources" { didSet { invalidateFilteredCatalog() } }
    @Published var variableOnly = false { didSet { invalidateFilteredCatalog() } }
    @Published var detail: Family?
    @Published var writing: WritingSystem? { didSet { invalidateFilteredCatalog() } }
    @Published var requiredText = "" { didSet { invalidateFilteredCatalog() } }
    @Published var requireCoverage = false { didSet { invalidateFilteredCatalog() } }
    @Published var comparison: [String] = []
    @Published var overlayName = ""
    @Published var showCompare = false
    func toggleOverlay(_ postScriptName: String) { overlayName = overlayName == postScriptName ? "" : postScriptName }
    private func faceMatches(_ face: Face, in family: Family, query: FontSearchQuery) -> Bool {
        (writing == nil || face.writingSystems.contains(writing!)) &&
        tagQuery.matches(pro.tags[face.name] ?? []) &&
        (selection != "Last Import" || saved.lastImportNames?.contains(face.name) == true) &&
        (!selection.hasPrefix("tag:") || TagQuery.contains(String(selection.dropFirst(4)), in: pro.tags[face.name] ?? [])) &&
        (!requireCoverage || FontCoverage.missing(requiredText, in: face.coverage).isEmpty) &&
        advanced.matches(face, tags: pro.tags[face.name] ?? []) &&
        query.matches(face, tags: pro.tags[face.name] ?? []) &&
        (query.text.isEmpty || family.name.localizedCaseInsensitiveContains(query.text) || face.name.localizedCaseInsensitiveContains(query.text) || face.style.localizedCaseInsensitiveContains(query.text))
    }
    func matchingFaces(in family: Family) -> [Face] {
        let query = FontSearchQuery(search)
        return family.faces.filter { faceMatches($0, in: family, query: query) }
    }
    func chosenFace(_ family: Family) -> Face {
        let matching = matchingFaces(in: family)
        return matching.first(where: { $0.name == pro.mainPreviews[family.name] }) ?? matching.first(where: { $0.name == family.representative.name }) ?? matching.first ?? family.representative
    }
    func compare(_ family: Family) {
        if comparison.contains(family.name) { comparison.removeAll { $0 == family.name } }
        else if comparison.count < 6 { comparison.append(family.name) }
        else { message = "Compare up to six families. Remove one to add another." }
    }
    var compared: [Family] { comparison.compactMap { family(named: $0) } }

    let saveURL: URL
    lazy var folderAccess = FolderAccess(directory: saveURL.deletingLastPathComponent())
    init(storageURL: URL? = nil) {
        saveURL = storageURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("FontShelf/library.json")
        saved = SavedLibrary()
        do {
            switch try LibraryBackupTools.recoverPendingImport(in: saveURL.deletingLastPathComponent()) {
            case .none: break
            case .rolledBack: message = "An interrupted backup import was rolled back. Your previous saved data is intact."
            case .completed: message = "An interrupted backup import was completed from its saved copies."
            }
        } catch {
            let warning = "Backup import recovery needs attention. Saved files were preserved and editing is disabled. " + error.localizedDescription
            backupRecoveryError = warning
            librarySaveBlocked = true
            proSaveBlocked = true
            message = warning
            return
        }
        do {
            try TypefieldInputFile.requireRegularFileIfPresent(saveURL)
            if FileManager.default.fileExists(atPath: saveURL.path) { saved = try JSONDecoder().decode(SavedLibrary.self, from: Data(contentsOf: saveURL)) }
        } catch { librarySaveBlocked = true; message = "Could not read your library. The existing file was preserved; restore it from a backup before making changes." }
        do {
            try TypefieldInputFile.requireRegularFileIfPresent(proURL)
            if FileManager.default.fileExists(atPath: proURL.path) { pro = try JSONDecoder().decode(ProState.self, from: Data(contentsOf: proURL)) }
        } catch { proSaveBlocked = true; message = "Could not read advanced library settings. Existing settings were preserved." }
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
        var sources: [String: Set<String>] = [:]
        var paused: Set<String> = []
        for path in saved.folders {
            do {
                let resolved = try folderAccess.restore(path)
                folders.append(resolved)
                sources[resolved, default: []].insert(path)
                reportedFolderAccessFailures.remove(path)
            }
            catch {
                if FolderAccess.isPaused(error) { paused.insert(path); continue }
                if reportedFolderAccessFailures.insert(path).inserted {
                    message = error.localizedDescription
                }
            }
        }
        pausedFolders = paused
        resolvedFolders = folders
        savedPathsByResolvedFolder = sources
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
    @discardableResult func updateSaved(_ change: (inout SavedLibrary) -> Void) -> Bool {
        let previous = saved
        change(&saved)
        guard save() else { saved = previous; return false }
        return true
    }
    @discardableResult func favorite(_ f: Family) -> Bool {
        updateSaved { saved in
            if saved.favorites.contains(f.name) { saved.favorites.remove(f.name) }
            else { saved.favorites.insert(f.name) }
        }
    }
    @discardableResult func setCategory(_ category: Category?, for familyName: String) -> Bool {
        updateSaved { saved in saved.overrides[familyName] = category }
    }
    @discardableResult func toggleCollectionMembership(_ familyName: String, in name: String) -> Bool {
        guard saved.collections[name] != nil else { message = "That collection is no longer available."; return false }
        let wasMember = saved.collections[name]?.contains(familyName) == true
        let changed = updateSaved { saved in
            if saved.collections[name, default: []].contains(familyName) { saved.collections[name]?.remove(familyName) }
            else { saved.collections[name]?.insert(familyName) }
        }
        if changed { resultNotice = "\(familyName) \(wasMember ? "removed from" : "added to") collection “\(name)”." }
        return changed
    }
    @discardableResult func createEmptyCollection(_ name: String) -> Bool {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return false }
        if saved.collections[name] == nil {
            guard updateSaved({ $0.collections[name] = [] }) else { return false }
        }
        selection = "collection:" + name
        resultNotice = "Collection “\(name)” is ready. Add families from their More menu."
        return true
    }
    @discardableResult func deleteCollection(_ name: String) -> Bool {
        guard saved.collections[name] != nil else { return false }
        guard updateSaved({ $0.collections.removeValue(forKey: name) }) else { return false }
        if selection == "collection:" + name { selection = "All Fonts" }
        return true
    }
    func matchesSection(_ f: Family, _ section: String) -> Bool {
        if section == "All Fonts" { return true }
        if section == "Last Import" { return f.faces.contains { saved.lastImportNames?.contains($0.name) == true } }
        if section == "Favorites" { return saved.favorites.contains(f.name) }
        if section.hasPrefix("tag:") { return TagQuery.contains(String(section.dropFirst(4)), in: tags(f)) }
        if section.hasPrefix("collection:") { return saved.collections[String(section.dropFirst(11))]?.contains(f.name) ?? false }
        return category(f).rawValue == section
    }
    @discardableResult func saveCurrentSearch(as name: String, previewText: String? = nil) -> Bool {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, saved.savedSearches?[name] == nil else { return false }
        let snapshot = SavedSearch(section: selection, query: search, sort: sort, source: source,
                                   writing: writing?.rawValue, variableOnly: variableOnly, tagQuery: tagQuery,
                                   advanced: advanced, requireCoverage: requireCoverage, requiredText: requiredText,
                                   previewText: previewText)
        let previous = saved.savedSearches
        saved.savedSearches?[name] = snapshot
        if saved.savedSearches == nil { saved.savedSearches = [name: snapshot] }
        guard save() else { saved.savedSearches = previous; return false }
        return true
    }
    @discardableResult func applySavedSearch(_ name: String) -> String? {
        guard let snapshot = saved.savedSearches?[name] else { return nil }
        selection = snapshot.section; search = snapshot.query; sort = snapshot.sort; source = snapshot.source
        writing = snapshot.writing.flatMap(WritingSystem.init(rawValue:))
        variableOnly = snapshot.variableOnly; tagQuery = snapshot.tagQuery; advanced = snapshot.advanced
        requireCoverage = snapshot.requireCoverage; requiredText = snapshot.requiredText
        workspace = .library
        return snapshot.previewText ?? (snapshot.requireCoverage ? snapshot.requiredText : nil)
    }
    @discardableResult func deleteSavedSearch(_ name: String) -> Bool {
        guard saved.savedSearches?[name] != nil else { return false }
        let previous = saved.savedSearches
        saved.savedSearches?.removeValue(forKey: name)
        guard save() else { saved.savedSearches = previous; return false }
        return true
    }
    // Retain only the current result. Selection, preview size and other UI changes
    // must not re-run every font predicate and localized sort in a large catalog.
    private var cachedFilteredCatalog: (families: [Family], styleCount: Int)?
    fileprivate func invalidateFilteredCatalog() { cachedFilteredCatalog = nil }
    var filtered: [Family] { filteredCatalog.families }
    var matchingStyleCount: Int { filteredCatalog.styleCount }
    private var filteredCatalog: (families: [Family], styleCount: Int) {
        // Activation predicates also read live Core Text registration state.
        let canCache = advanced.activation == "Any" && !search.lowercased().contains("/active")
        if canCache, let cachedFilteredCatalog { return cachedFilteredCatalog }
        let query = FontSearchQuery(search)
        var styleCount = 0
        let result = families.filter { family in
            guard matchesSection(family, selection), !variableOnly || family.variable,
                  source == "All sources" || (source == "User / third-party" ? family.userFont : !family.userFont) else { return false }
            let matches = family.faces.reduce(0) { $0 + (faceMatches($1, in: family, query: query) ? 1 : 0) }
            styleCount += matches
            return matches > 0
        }
        let sorted = result.sorted { a,b in
            if sort == "Most styles", a.faces.count != b.faces.count { return a.faces.count > b.faces.count }
            if sort == "Category", category(a) != category(b) { return category(a).rawValue < category(b).rawValue }
            return a.name.localizedStandardCompare(b.name) == (sort == "Name Z–A" ? .orderedDescending : .orderedAscending)
        }
        let snapshot = (families: sorted, styleCount: styleCount)
        if canCache { cachedFilteredCatalog = snapshot }
        return snapshot
    }
    var filteredFaces: [Face] { filtered.flatMap { matchingFaces(in: $0) } }
    var selectedOutsideViewCount: Int { selectedFamilies.subtracting(Set(filtered.map(\.name))).count }
    var selectedScopeLabel: String {
        let outside = selectedOutsideViewCount
        return "\(selectedFamilies.count) selected (\(outside) outside this view)"
    }
    func selectVisibleFamilies() { selectedFamilies = Set(filtered.map(\.name)) }
    var hasActiveFilters: Bool {
        !search.isEmpty || source != "All sources" || variableOnly || advanced.active || tagQuery.active || writing != nil || requireCoverage
    }
    func clearFiltersPreservingSection() {
        search = ""; source = "All sources"; variableOnly = false; advanced = AdvancedFilter()
        tagQuery = TagQuery(); writing = nil; requireCoverage = false
    }
    func addFolder(replacing oldPath: String? = nil) {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        panel.prompt = oldPath == nil ? "Add & Watch" : "Use Folder"
        panel.message = oldPath == nil ? "Add this folder and watch it live. Fonts in its subfolders are included, and additions, replacements and removals update automatically every three seconds while Typefield is open. Nothing is installed or moved." : "Choose the watched folder again, or choose its new location. Typefield will replace the old saved path and keep its activation setting."
        if let oldPath { panel.directoryURL = URL(fileURLWithPath: oldPath).deletingLastPathComponent() }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try folderAccess.remember(url) } catch { message = "Could not retain folder access: " + error.localizedDescription; return }
        reportedFolderAccessFailures.remove(url.path)
        if let oldPath { reportedFolderAccessFailures.remove(oldPath) }
        let previous = saved
        if let oldPath, saved.folders.contains(oldPath) { saved.replaceWatchedFolder(oldPath, with: url.path) }
        else if !saved.folders.contains(url.path) { saved.folders.append(url.path) }
        if let oldPath, oldPath != url.path, saved.folders != previous.folders || saved.autoActivateFolders != previous.autoActivateFolders {
            guard save() else { saved = previous; return }
        } else if oldPath == nil, saved.folders != previous.folders {
            guard save() else { saved = previous; return }
        }
        if !resolvedFolders.contains(url.path) { resolvedFolders.append(url.path) }
        savedPathsByResolvedFolder[url.path, default: []].insert(url.path)
        openTools("Folders")
        if let oldPath {
            resolvedFolders.removeAll { $0 == oldPath && $0 != url.path }
            reload(register: true)
            message = "Watching \(url.lastPathComponent). The previous folder location has been replaced."
            return
        }
        if loading {
            folderStatus = "Folder added. Its first scan is queued behind the current scan; live watching starts when that scan finishes."
            reload(register: true)
            return
        }
        loading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let count = FontCatalog.registerFolder(url.path)
            let result = FontCatalog.scan()
            DispatchQueue.main.async { self.acceptCatalog(result); if count > 0 { self.recordImport(folder: url.path) }; self.configureWatcher(); self.applyFolderActivation(); self.finishLoading(); self.message = "Watching \(url.lastPathComponent) and its subfolders. Loaded \(count) new font files; changes update automatically while Typefield is open." }
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
    var maximumLines: Int? = nil
    var previewFont: CGFont? = nil
    @AppStorage("customPreviewColors") var customColors = false
    @AppStorage("previewInkHex") var inkHex = "EEEEEE"
    @AppStorage("previewPaperHex") var paperHex = "202020"
    struct Configuration: Equatable {
        let text: String, name: String, ink: String, paper: String?, appearance: String, previewName: String?
        let maximumLines: Int?
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
        let configuration = Configuration(text: text, name: name, ink: resolvedInk.rgbHex, paper: resolvedPaper?.rgbHex, appearance: NSApp.effectiveAppearance.name.rawValue, previewName: previewFont.map { $0.postScriptName as String? } ?? nil, maximumLines: maximumLines, previewHash: previewFont.map(CFHash), size: size, wraps: wraps, baseline: baseline, variations: variations, features: features)
        guard configuration != context.coordinator.configuration else { return }
        context.coordinator.configuration = configuration
        view.text = text
        view.font = previewFont.map { CTFontCreateWithGraphicsFont($0, size, nil, nil) } ?? OpenType.font(name: name, size: size, axes: variations, features: features)
        view.ink = resolvedInk
        view.paper = resolvedPaper
        view.wraps = wraps
        view.baseline = baseline
        view.maximumLines = maximumLines
        view.invalidateContent()
        view.setAccessibilityLabel(text)
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView view: BaselineTextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0 else { return nil }
        return CGSize(width: width, height: view.layout(width: width).height)
    }
}

private struct LibrarySidebarSnapshot {
    private let sections: [String: Int]
    private let writingSystems: [WritingSystem: Int]
    let tags: [String]

    init(library: Library) {
        let families = library.families
        let visibleTags = TagQuery.hierarchy(Set(library.pro.tags.values.flatMap { $0 }))
        var sectionCounts: [String: Int] = ["All Fonts": families.count]
        var writingCounts: [WritingSystem: Int] = [:]
        for family in families {
            sectionCounts[library.category(family).rawValue, default: 0] += 1
            if library.saved.favorites.contains(family.name) { sectionCounts["Favorites", default: 0] += 1 }
            if family.faces.contains(where: { library.saved.lastImportNames?.contains($0.name) == true }) { sectionCounts["Last Import", default: 0] += 1 }
            for writing in family.writingSystems { writingCounts[writing, default: 0] += 1 }
            let familyTags = library.tags(family)
            for tag in visibleTags where TagQuery.contains(tag, in: familyTags) { sectionCounts["tag:" + tag, default: 0] += 1 }
        }
        let loadedNames = Set(families.map(\.name))
        for (name, members) in library.saved.collections {
            sectionCounts["collection:" + name] = members.intersection(loadedNames).count
        }
        sections = sectionCounts
        writingSystems = writingCounts
        tags = visibleTags
    }

    func count(section: String) -> Int { sections[section] ?? 0 }
    func count(writingSystem: WritingSystem) -> Int { writingSystems[writingSystem] ?? 0 }
    var checksum: Int { sections.values.reduce(0) { $0 &+ $1 } &+ writingSystems.values.reduce(0) { $0 &+ $1 } &+ tags.count }
}

struct ContentView: View {
    @ObservedObject var library: Library
    @ObservedObject var windows: WorkspaceWindows
    @AppStorage("previewText") var preview = "The quick brown fox jumps over the lazy dog."
    @AppStorage("previewSize") var size = 64.0
    @AppStorage("adaptiveGridView") var grid = true
    @State var metadataView = false
    @AppStorage("appearance") var appearance = "Dark"
    @AppStorage("typefield.palette") private var palette = "neutral"
    @Environment(\.colorScheme) private var systemScheme
    @State var collectionName = ""
    @State var showCollection = false
    @State private var licenseFace: Face?
    @State var showColors = false
    @State var showTagFilters = false
    @State var showDiscovery = false
    @State private var showTour = false
    @State private var pendingTourWorkspace: WorkspaceMode?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("typefield.onboardingComplete") private var onboardingComplete = false
    @AppStorage(WorkspaceSidebarPreference.key) var sidebarCollapsed = false
    @FocusState private var searchFocused: Bool
    var body: some View {
        ZStack(alignment: .topLeading) {
        HStack(spacing: 0) {
            if library.workspace == .library && !sidebarCollapsed { WorkspaceSidebarShell { sidebar }.transition(.move(edge: .leading).combined(with: .opacity)) }
            switch library.workspace {
            case .spaces:
                WorkspaceEditorSlot(windows: windows, mode: .spaces)
            case .fontLab:
                WorkspaceEditorSlot(windows: windows, mode: .fontLab)
            case .library:
                VStack(spacing: 0) {
                let visibleFamilies = library.filtered
                let matchingStyleCount = library.matchingStyleCount
                topControls
                libraryContent(visibleFamilies)
                Divider()
                HStack { Circle().fill(Color.accentColor).frame(width: 6, height: 6); Text("\(visibleFamilies.count) \(visibleFamilies.count == 1 ? "family" : "families") with \(matchingStyleCount) matching styles; \(library.styleCount) styles in library"); Spacer() }.font(.caption).foregroundStyle(.secondary).padding(12)
                }.accessibilityIdentifier("library-workspace")
            }
        }
        if sidebarCollapsed && library.workspace == .library {
            WorkspaceSidebarRevealButton(collapsed: $sidebarCollapsed)
                .padding(.top, 8)
                .zIndex(2)
                .transition(.move(edge: .leading).combined(with: .opacity))
        }
        }
        .background(ShelfPalette.canvas)
        .tint(Color(nsColor: TypefieldPalette.resolve(palette).accent(dark: appearance == "Dark" || (appearance == "System" && systemScheme == .dark))))
        .accentColor(ShelfPalette.ink)
        .onChange(of: systemScheme) { _ in TypefieldIcon.apply() }
        .frame(minWidth: 980, minHeight: 620)
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("TypefieldMenu"))) { event in
            guard (NSApp.delegate as? AppDelegate)?.window.isKeyWindow == true else { return }
            switch event.object as? String {
            case "collection": library.workspace = .library; showCollection = true
            case "colors": showColors = true
            case "find": if library.workspace == .library { searchFocused = true }
            case "larger": size = min(160, size + 4)
            case "smaller": size = max(16, size - 4)
            case "resetSize": size = 64
            case "list": grid = false
            case "grid": grid = true
            case "toggleSidebar":
                if (NSApp.delegate as? AppDelegate)?.activeWorkspace == .library {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { sidebarCollapsed.toggle() }
                }
            case "tour": showTour = true
            default: break
            }
        }
        .onChange(of: appearance) { value in NSApp.appearance = value == "System" ? nil : NSAppearance(named: value == "Dark" ? .darkAqua : .aqua); TypefieldIcon.apply() }
        .onAppear {
            library.requiredText = preview == "{family}" ? "" : preview
            presentInitialTourIfReady()
        }
        .onChange(of: library.message) { _ in presentInitialTourIfReady() }
        .onChange(of: preview) { value in library.requiredText = value == "{family}" ? "" : value; if value == "{family}" { library.requireCoverage = false } }
        .sheet(item: $licenseFace) { FontLicenseSourcesView(face: $0) }
        .sheet(isPresented: $library.showTools) { LibraryToolsView(library: library) }
        .sheet(isPresented: $library.showCompare) { CompareView(library: library, preview: preview, size: size) }
        .sheet(item: $library.typeboardDraft) { draft in TypeboardRoleMapper(library: library, draft: draft) }
        .sheet(isPresented: $showDiscovery) { FontDiscoveryView(library: library, eligibleFamilies: library.filtered, preview: preview == "{family}" ? "Hamburgefontsiv 0123456789" : preview) }
        .sheet(item: $library.detail) { family in DetailView(library: library, family: family, preview: preview == "{family}" ? family.name : preview, size: size) }
        .sheet(isPresented: $showTour, onDismiss: {
            onboardingComplete = true
            if let destination = pendingTourWorkspace {
                pendingTourWorkspace = nil
                library.workspace = destination
                if windows.detached.contains(destination) { windows.detach(destination) }
            }
        }) {
            TypefieldTour(dismiss: { finishTour() }, open: { finishTour($0) })
        }
        .alert("New collection", isPresented: $showCollection) {
            TextField("Collection name", text: $collectionName)
            Button("Create") { _ = library.createEmptyCollection(collectionName); collectionName = "" }
            Button("Cancel", role: .cancel) { collectionName = "" }
        } message: { Text("Add families through their ••• menu or by right-clicking a preview.") }
        .alert("Typefield", isPresented: Binding(get: { !library.message.isEmpty }, set: { if !$0 { library.message = "" } })) { Button("OK") { library.message = "" } } message: { Text(library.message) }
    }
    private func finishTour(_ destination: WorkspaceMode? = nil) {
        // Complete immediately so a late startup notification cannot reopen the
        // tour during dismissal. Mount the chosen workspace in onDismiss above.
        onboardingComplete = true
        pendingTourWorkspace = destination
        showTour = false
    }
    private func presentInitialTourIfReady() {
        guard !onboardingComplete, !showTour, library.message.isEmpty,
              !library.showTools, !library.showCompare, library.detail == nil,
              library.typeboardDraft == nil, licenseFace == nil else { return }
        showTour = true
    }
    var topControls: some View {
        VStack(spacing: 0) {
                header
                if !library.resultNotice.isEmpty {
                    HStack(spacing: 8) {
                        Label(library.resultNotice, systemImage: "checkmark.circle.fill")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                        Button("Dismiss") { library.resultNotice = "" }
                    }.font(.caption).padding(.horizontal, 20).padding(.vertical, 6)
                        .background(Color.accentColor.opacity(0.08))
                        .accessibilityElement(children: .combine)
                }
                SearchTokenChips(library: library).padding(.horizontal, 20)
                VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: "text.cursor").foregroundStyle(.secondary)
                    TextField("Type your own preview…", text: $preview).textFieldStyle(.plain)
                    Menu {
                        Button("The quick brown fox…") { preview = "The quick brown fox jumps over the lazy dog." }
                        Button("Alphabet & numbers") { preview = "ABCDEFGHIJKLMNOPQRSTUVWXYZ abcdefghijklmnopqrstuvwxyz 0123456789" }
                        ForEach(WritingSystem.allCases, id: \.self) { writing in Button(writing.displayName) { preview = writing.sample } }
                        Button("Family names") { preview = "{family}" }
                    } label: { Image(systemName: "text.quote") }.shelfIconMenu().help("Preview text presets").accessibilityLabel("Preview text presets")
                    Divider().frame(height: 20)
                    Text("Aa").font(.system(size: 12))
                    Slider(value: $size, in: 16...160, step: 1)
                        .frame(width: 135)
                        .accessibilityLabel("Preview size")
                        .accessibilityValue("\(Int(size)) points")
                        .accessibilityHint("Adjusts the size of Library font previews")
                    Text("\(Int(size)) pt").monospacedDigit().foregroundStyle(.secondary).frame(width: 48)
                }.padding(14).shelfGlass(radius: 16).padding(.horizontal, 16).padding(.bottom, 12)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        tagFilterControl
                        sourceFilterControl
                        variableFilterControl
                        Spacer(minLength: 0)
                        sortFilterControl
                        layoutFilterControl
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            tagFilterControl
                            sourceFilterControl
                            variableFilterControl
                            Spacer(minLength: 0)
                        }
                        HStack(spacing: 10) {
                            sortFilterControl
                            layoutFilterControl
                            Spacer(minLength: 0)
                        }
                    }
                }.padding(.horizontal, 16).padding(.vertical, 10)
                HStack {
                    if let writing = library.writing {
                        Button { library.writing = nil } label: { Label(writing.displayName, systemImage: "xmark.circle") }
                        Button("Use script sample") { preview = writing.sample }
                    }
                    Toggle("Contains preview characters", isOn: $library.requireCoverage).toggleStyle(.checkbox).disabled(preview == "{family}")
                    Spacer()
                    if !library.comparison.isEmpty {
                        Button("Shortlist (\(library.comparison.count))") { library.showCompare = true }
                        Button("Open shortlist window") { windows.openBrowser(scope: "Shortlist") }
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
                        Text("Cyan shows the reference; orange shows the preview.").foregroundStyle(.secondary)
                        Spacer()
                        Button("End overlay") { library.overlayName = "" }
                    }.font(.caption).padding(.horizontal, 16).padding(.bottom, 10)
                }
                if !library.selectedFamilies.isEmpty {
                    HStack(spacing: 10) {
                        Text(library.selectedScopeLabel)
                        Text("\(library.selectedFaces.count) styles affected").foregroundStyle(.secondary)
                        Menu("Batch actions") {
                            Button("Tag \(library.selectedFaces.count) styles…") { library.openTools("Tags") }
                            Button("Create typeboard with \(library.selectedFamilies.count) families") { library.pairSelection(library.families.filter { library.selectedFamilies.contains($0.name) }.map { library.chosenFace($0).name }, source: "Selected Library fonts") }
                            Button("Export specimen PDF for \(library.selectedFamilies.count) families…") { SpecimenExporter.export(faces: library.families.filter { library.selectedFamilies.contains($0.name) }.map { library.chosenFace($0) }, library: library, sample: preview == "{family}" ? "Hamburgefontsiv 0123456789" : preview) }
                            Button("Edit \(library.selectedFaces.count) styles…") { library.openTools("Families") }
                            Button("Export \(library.selectedFaces.count) font styles…") { reportFontExport(library.selectedFaces) }
                        }
                        Button("Replace selection with visible") { library.selectVisibleFamilies() }
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
                    VStack(spacing: 12) {
                        Image(systemName: "text.magnifyingglass").font(.system(size: 38)).foregroundStyle(.secondary)
                        Text(emptyLibraryTitle).font(.title2)
                        Text(emptyLibraryHint).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 440)
                        if library.hasActiveFilters { Button("Clear filters") { library.clearFiltersPreservingSection() } }
                        if library.selection != "All Fonts" { Button("Browse all fonts") { library.selection = "All Fonts" } }
                    }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
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
                                    let previewWidth = max(1, (width - Double(columns - 1) * 10) / Double(columns) - 40)
                                    let metrics = rowPreviewMetrics(row, faces: faces, width: previewWidth)
                                    HStack(alignment: .top, spacing: 10) {
                                        ForEach(0..<columns, id: \.self) { column in
                                            if start + column < families.count {
                                                card(families[start + column], face: faces[column], metrics: metrics).frame(maxWidth: .infinity)
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
    var emptyLibraryTitle: String {
        if library.selection == "Last Import" && !library.hasActiveFilters {
            return library.saved.lastImportNames?.isEmpty == false ? "Recent import unavailable" : "No imports yet"
        }
        if library.selection.hasPrefix("collection:") && library.saved.collections[String(library.selection.dropFirst(11))]?.isEmpty == true {
            return "This collection is empty"
        }
        return library.hasActiveFilters ? "No matching fonts" : "No fonts in this section yet"
    }
    var emptyLibraryHint: String {
        if library.selection == "Last Import" && !library.hasActiveFilters {
            return library.saved.lastImportNames?.isEmpty == false ? "The last import has no fonts available in the current catalog. Choose its folder again in Live folders or import it again." : "Your next font-folder import or Google Fonts download will appear here."
        }
        if library.selection.hasPrefix("collection:") && library.saved.collections[String(library.selection.dropFirst(11))]?.isEmpty == true {
            return "Browse fonts, then add families through their More menu."
        }
        return library.hasActiveFilters ? "Try a different search or filter. Your current collection or Library section will stay selected." : "Browse all fonts or add a font folder."
    }
    var sidebar: some View {
        let snapshot = LibrarySidebarSnapshot(library: library)
        return VStack(alignment: .leading, spacing: 6) {
            WorkspaceSidebarHeader(library: library, collapsed: $sidebarCollapsed)
            ScrollView { VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Library")
            nav("All Fonts", icon: "square.stack.3d.up", key: "All Fonts", count: snapshot.count(section: "All Fonts"))
            nav("Last Import", icon: "clock.arrow.circlepath", key: "Last Import", count: snapshot.count(section: "Last Import"))
            nav("Favorites", icon: "star", key: "Favorites", count: snapshot.count(section: "Favorites"))
            Button { library.showCompare = true } label: {
                HStack { Image(systemName: "square.on.square").frame(width: 20); Text("Shortlist"); Spacer(); Text("\(library.comparison.count)").foregroundStyle(.secondary) }.padding(.horizontal, 10).padding(.vertical, 9).contentShape(Rectangle())
            }.buttonStyle(.plain).padding(.horizontal, 8).help("Compare up to six families added with +")
            Button("Google Fonts…") { library.openTools("Google Fonts") }.buttonStyle(.plain).padding(.horizontal, 18).padding(.vertical, 8)
            SidebarSection(title: "Categories", key: "sidebar.categories") {
            ForEach(Category.allCases, id: \.self) { category in nav(category.rawValue, icon: category.icon, key: category.rawValue, count: snapshot.count(section: category.rawValue)) }
            }
            SidebarSection(title: "Languages / Scripts", key: "sidebar.languages") {
            ForEach(WritingSystem.allCases, id: \.self) { writing in
                Button { library.writing = library.writing == writing ? nil : writing } label: {
                    HStack { Text(writing.mark).frame(width: 20); Text(writing.displayName).lineLimit(1); Spacer(); Text("\(snapshot.count(writingSystem: writing))").font(.caption).foregroundStyle(.secondary) }.padding(.horizontal, 10).padding(.vertical, 8).contentShape(Rectangle())
                }.buttonStyle(.plain).background(library.writing == writing ? Color.accentColor.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 10)).padding(.horizontal, 8)
                    .accessibilityAddTraits(library.writing == writing ? .isSelected : [])
            }
            }
            SidebarSection(title: "Tags", key: "sidebar.tags") {
            ForEach(snapshot.tags, id: \.self) { tag in
                nav(tag, icon: "tag", key: "tag:" + tag, count: snapshot.count(section: "tag:" + tag)).padding(.leading, CGFloat(tag.filter { $0 == "/" }.count) * 8).contextMenu {
                    Button("Include tag") { library.tagQuery.included.insert(tag); library.tagQuery.excluded.remove(tag); library.workspace = .library; library.selection = "All Fonts" }
                    Button("Exclude tag") { library.tagQuery.excluded.insert(tag); library.tagQuery.included.remove(tag); library.workspace = .library; library.selection = "All Fonts" }
                }
            }
            }
            SidebarSection(title: "Saved searches", key: "sidebar.saved-searches", addLabel: "Save current search", onAdd: { saveSearch() }) {
                ForEach((library.saved.savedSearches ?? [:]).keys.sorted(), id: \.self) { name in
                    Button { if let restoredPreview = library.applySavedSearch(name) { preview = restoredPreview } } label: {
                        HStack { Image(systemName: "magnifyingglass").frame(width: 20); Text(name).lineLimit(1); Spacer() }
                            .padding(.horizontal, 10).padding(.vertical, 8).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).padding(.horizontal, 8)
                    .contextMenu { Button("Delete saved search", role: .destructive) { _ = library.deleteSavedSearch(name) } }
                }
                if library.saved.savedSearches?.isEmpty != false {
                    Text("Save filters to revisit live results").font(.caption).foregroundStyle(.tertiary).padding(.horizontal, 14)
                }
            }
            SidebarSection(title: "Collections", key: "sidebar.collections", onAdd: { showCollection = true }) {
            Group {
                VStack(spacing: 6) {
                    ForEach(library.saved.collections.keys.sorted(), id: \.self) { name in
                        HStack(spacing: 0) {
                            Button { library.workspace = .library; library.selection = "collection:" + name } label: { Image(systemName: "folder").frame(width: 28) }.buttonStyle(.plain).accessibilityLabel("Open collection " + name)
                                .accessibilityAddTraits(library.workspace == .library && library.selection == "collection:" + name ? .isSelected : [])
                            ShelfEditableName(name: name, selected: library.selection == "collection:" + name, onSelect: { library.workspace = .library; library.selection = "collection:" + name }, onRename: { library.renameCollection(name, to: $0) })
                                .accessibilityAddTraits(library.workspace == .library && library.selection == "collection:" + name ? .isSelected : [])
                            Text("\(snapshot.count(section: "collection:" + name))").font(.caption).monospacedDigit().foregroundStyle(.secondary)
                            Menu {
                                Button("Rename collection…") { renameCollection(name) }
                                Button("Delete collection…", role: .destructive) { confirmDeleteCollection(name) }
                            } label: { Image(systemName: "ellipsis").frame(width: 28, height: 28) }
                                .shelfIconMenu().accessibilityLabel("Actions for collection \(name)")
                        }.padding(.horizontal, 10).padding(.vertical, 9).background(library.selection == "collection:" + name ? Color.accentColor.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 10)).padding(.horizontal, 8).contextMenu { Button("Open in new window") { windows.openBrowser(scope: "collection:" + name) }; Button("Rename collection…") { renameCollection(name) }; Button("Delete collection…", role: .destructive) { confirmDeleteCollection(name) } }
                    }
                    if library.saved.collections.isEmpty { Text("No collections yet. Use + to create one.").font(.caption).foregroundStyle(.tertiary).padding(.horizontal, 14).padding(.top, 5) }
                }
            }
            }
            } }
            Spacer(minLength: 4)
            Button { library.addFolder() } label: { Label("Add font folder", systemImage: "folder.badge.plus").frame(maxWidth: .infinity, alignment: .leading) }.buttonStyle(.plain).foregroundStyle(systemScheme == .dark ? Color.black : Color.white).padding(10).background(ShelfPalette.ink, in: RoundedRectangle(cornerRadius: 12)).padding(12)
            Button { library.openTools("Folders") } label: { Label("Live folders (\(library.saved.folders.count))", systemImage: "arrow.triangle.2.circlepath").frame(maxWidth: .infinity, alignment: .leading) }.buttonStyle(.plain).padding(.horizontal, 22).padding(.bottom, 8).help("Manage folders that update automatically, including subfolders")
            HStack { Button { (NSApp.delegate as? AppDelegate)?.settingsWindow.show(library: library) } label: { Image(systemName: "gearshape") }.buttonStyle(.plain).help("Settings").accessibilityLabel("Settings"); ShelfDropdown(title: "Appearance", selection: $appearance, options: ["Dark", "Light", "System"].map { ($0, $0) }, showsTitle: false); Button { library.reload() } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.plain).foregroundStyle(ShelfPalette.ink).padding(6).help("Refresh installed fonts").accessibilityLabel("Refresh installed fonts").disabled(library.loading) }.padding(.horizontal, 12).padding(.bottom, 14)
        }
    }
    private var tagFilterControl: some View {
        Button(library.tagQuery.active ? "Tag filters (active)" : "Tag filters") { showTagFilters.toggle() }
            .popover(isPresented: $showTagFilters) { TagFilterView(library: library) }
            .fixedSize(horizontal: true, vertical: false)
    }
    private var sourceFilterControl: some View {
        ShelfDropdown(title: "Source", selection: $library.source, options: ["All sources", "User / third-party", "System"].map { ($0, $0) }, showsTitle: false)
            .frame(width: 165)
    }
    private var variableFilterControl: some View {
        Toggle("Variable fonts", isOn: $library.variableOnly).toggleStyle(.checkbox)
            .fixedSize(horizontal: true, vertical: false)
    }
    private var sortFilterControl: some View {
        ShelfDropdown(title: "Sort", selection: $library.sort, options: ["Name A–Z", "Name Z–A", "Most styles", "Category"].map { ($0, $0) })
            .frame(width: 180)
    }
    private var layoutFilterControl: some View {
        Picker("Layout", selection: $grid) {
            Image(systemName: "list.bullet").help("Full-width list").tag(false)
            Image(systemName: "square.grid.2x2").help("Adaptive grid: cards fit your preview text").tag(true)
        }.pickerStyle(.segmented).labelsHidden().frame(width: 70)
    }
    func sectionLabel(_ title: String) -> some View { Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.horizontal, 14).padding(.bottom, 5) }
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
    func nav(_ title: String, icon: String, key: String, count: Int) -> some View {
        Button { library.workspace = .library; library.selection = key } label: {
            HStack { navIcon(icon, key: key); Text(title).lineLimit(1); Spacer(); Text("\(count)").font(.caption).monospacedDigit().foregroundStyle(.secondary) }.padding(.horizontal, 10).padding(.vertical, 9).contentShape(Rectangle())
        }.buttonStyle(.plain).background(library.workspace == .library && library.selection == key ? Color.accentColor.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 10)).padding(.horizontal, 8)
            .accessibilityAddTraits(library.workspace == .library && library.selection == key ? .isSelected : [])
    }
    func renameCollection(_ name: String) {
        if let renamed = ShelfRename.prompt("Rename collection", current: name, validate: { candidate in candidate != name && library.saved.collections[candidate] != nil ? "A collection with this name already exists. Choose another name." : nil }) {
            if library.renameCollection(name, to: renamed) { library.resultNotice = "Collection “\(name)” renamed to “\(renamed)”." }
            else if library.message.isEmpty { library.message = "The collection could not be renamed." }
        }
    }
    func confirmDeleteCollection(_ name: String) {
        let count = library.saved.collections[name]?.count ?? 0
        let alert = NSAlert()
        alert.messageText = "Delete collection “\(name)”?"
        alert.informativeText = "Remove this collection and its \(count) saved \(count == 1 ? "family" : "families")? The font files and other collections stay in place."
        alert.addButton(withTitle: "Delete Collection")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        if library.deleteCollection(name) { library.resultNotice = "Collection “\(name)” deleted. Font files were not changed." }
        else if library.message.isEmpty { library.message = "The collection could not be deleted." }
    }
    func saveSearch() {
        if let name = ShelfRename.prompt("Save current Library search", current: "My search", actionTitle: "Save", validate: { candidate in library.saved.savedSearches?[candidate] != nil ? "A saved search with this name already exists." : nil }) {
            if library.saveCurrentSearch(as: name, previewText: preview) { library.resultNotice = "Saved search “\(name)” with its preview text and filters." }
            else { library.message = "Could not save this search. " + library.message }
        }
    }
    func createContextualTypeboard() {
        let seed = library.contextualTypeboardSeed()
        library.pairSelection(seed.fonts, source: seed.source)
    }
    var header: some View {
        HStack(spacing: 12) {
            if library.selection.hasPrefix("collection:") {
                let name = String(library.selection.dropFirst(11))
                ShelfEditableName(name: name, onRename: { library.renameCollection(name, to: $0) })
                    .font(.system(size: WorkspaceHeaderLayout.titleSize, weight: .semibold))
                    .frame(minWidth: 110, maxWidth: 165, minHeight: WorkspaceHeaderLayout.titleHeight)
                    .help(name)
                let count = library.saved.collections[name]?.count ?? 0
                Text("\(count) \(count == 1 ? "family" : "families")").font(.caption).foregroundStyle(.secondary)
                Menu {
                    Button("Rename collection…") { renameCollection(name) }
                    Button("Delete collection…", role: .destructive) { confirmDeleteCollection(name) }
                } label: { Image(systemName: "ellipsis.circle") }
                    .shelfIconMenu().accessibilityLabel("Actions for collection \(name)")
            } else {
                Text(library.selection.replacingOccurrences(of: "tag:", with: ""))
                    .font(.system(size: WorkspaceHeaderLayout.titleSize, weight: .semibold))
                    .lineLimit(1).truncationMode(.middle)
                    .frame(maxWidth: 170, minHeight: WorkspaceHeaderLayout.titleHeight)
            }
            Spacer()
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    Button("Rediscover", systemImage: "shuffle") { showDiscovery = true }.help("Find local fonts you have not applied recently")
                    Button("New typeboard", systemImage: "text.badge.plus") { createContextualTypeboard() }.help("Create a typeboard and choose the initial font for every role")
                }
                HStack(spacing: 8) {
                    Button { showDiscovery = true } label: { Image(systemName: "shuffle") }.help("Rediscover local fonts").accessibilityLabel("Rediscover local fonts")
                    Button { createContextualTypeboard() } label: { Image(systemName: "text.badge.plus") }.help("New typeboard").accessibilityLabel("New typeboard")
                }
            }
            Button { library.showAdvanced.toggle() } label: { Image(systemName: library.advanced.active ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle") }.buttonStyle(.plain).foregroundStyle(ShelfPalette.ink).padding(8).shelfGlass(radius: 16).help("Advanced filters").accessibilityLabel("Advanced filters").accessibilityValue(library.showAdvanced ? "Open" : "Closed").popover(isPresented: $library.showAdvanced) { AdvancedFiltersView(library: library) }
            Button { showColors.toggle() } label: { Image(systemName: "paintpalette") }.buttonStyle(.plain).foregroundStyle(ShelfPalette.ink).padding(8).shelfGlass(radius: 16).help("Preview colors").accessibilityLabel("Preview colors").popover(isPresented: $showColors) { PreviewColorsView() }
            Menu("Tools") {
                Menu("Organization") {
                    Button("Tags…") { library.openTools("Tags") }
                    Button("Families…") { library.openTools("Families") }
                    Toggle("Metadata table", isOn: $metadataView)
                    Button("Save current search…") { saveSearch() }
                    Button("Replace selection with visible") { library.selectVisibleFamilies() }
                }
                Menu("Font files") {
                    Button("Duplicates…") { library.openTools("Duplicates") }
                    Button("Font Health…") { library.openTools("Font Health") }
                    Button("Google Fonts…") { library.openTools("Google Fonts") }
                    Button("Activation…") { library.openTools("Activation") }
                    Button("Folders…") { library.openTools("Folders") }
                }
                Menu("Backup & migration") {
                    Button("Export library backup…") { LibraryBackupTools.export(library) }
                    Button("Import library backup…") { LibraryBackupTools.restore(library) }
                    Button("Migrate FontShelf data to Typefield…") { StoreMigration.chooseSource(for: library) }
                    Button("Import earlier preferences…") { StoreMigration.choosePreferences(for: library) }
                    Button("Show automatic backups") { NSWorkspace.shared.open(library.saveURL.deletingLastPathComponent().appendingPathComponent("Backups")) }
                }
            }.menuStyle(.borderlessButton).foregroundStyle(Color.primary).padding(8).shelfGlass(radius: 16).frame(width: 85)
            LibrarySearchView(library: library).focused($searchFocused).frame(minWidth: 165, idealWidth: 250, maxWidth: 350)
        }
        .frame(minHeight: WorkspaceHeaderLayout.rowHeight)
        .padding(.horizontal, WorkspaceHeaderLayout.horizontalPadding)
        .padding(.vertical, WorkspaceHeaderLayout.verticalPadding)
        .padding(.leading, sidebarCollapsed ? WorkspaceSidebarLayout.revealWidth + 8 : 0)
    }
    struct LibraryRowPreviewMetrics {
        let baseline: Double
        let height: Double
    }
    func rowPreviewMetrics(_ families: [Family], faces: [Face], width: Double) -> LibraryRowPreviewMetrics {
        let samples: [(text: String, font: CTFont)] = zip(families, faces).flatMap { family, face in
            let text = preview == "{family}" ? family.name : preview
            let names = library.overlayName.isEmpty ? [face.name] : [face.name, library.overlayName]
            return names.map { name in
                (text, OpenType.font(name: name, size: size, axes: library.pro.axes[name] ?? [:], features: library.pro.features[name] ?? [:]))
            }
        }
        // Measure only the first three visible lines, matching FontPreview's limit.
        // This also includes the real fallback glyph bounds for mixed scripts.
        let layouts = samples.map { sample -> (ascent: Double, descent: Double, lines: Int, font: CTFont) in
            let text = String(sample.text.prefix(512))
            let attributed = NSAttributedString(string: text, attributes: [.font: sample.font])
            let typesetter = CTTypesetterCreateWithAttributedString(attributed)
            var offset = 0
            var lines = 0
            var ascent = Double(CTFontGetAscent(sample.font))
            var descent = Double(CTFontGetDescent(sample.font))
            while offset < attributed.length && lines < 3 {
                let length = max(1, CTTypesetterSuggestLineBreak(typesetter, offset, width))
                let line = CTTypesetterCreateLine(typesetter, CFRange(location: offset, length: length))
                var lineAscent: CGFloat = 0
                var lineDescent: CGFloat = 0
                CTLineGetTypographicBounds(line, &lineAscent, &lineDescent, nil)
                let inkBounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
                ascent = max(ascent, lineAscent, inkBounds.maxY)
                descent = max(descent, lineDescent, -inkBounds.minY)
                offset += length
                lines += 1
            }
            return (ascent, descent, lines, sample.font)
        }
        let baseline = ceil(layouts.map(\.ascent).max() ?? size) + 4
        let shortPreview = preview != "{family}" && preview.trimmingCharacters(in: .whitespacesAndNewlines).count <= 3 && !preview.contains("\n")
        let minimumHeight = library.overlayName.isEmpty && shortPreview ? max(44, size * 1.18) : size * 1.5
        let height = layouts.reduce(minimumHeight) { tallest, layout in
            let advance = max(baseline + CTFontGetDescent(layout.font) + CTFontGetLeading(layout.font), size * 1.2)
            return max(tallest, baseline + Double(max(0, layout.lines - 1)) * advance + layout.descent + 6)
        }
        return LibraryRowPreviewMetrics(baseline: baseline, height: ceil(height))
    }
    func reportFontExport(_ faces: [Face]) {
        guard let result = FontExporter.export(faces) else { return }
        if result.hasPrefix("Export failed:") || result.contains("\n") { library.message = result }
        else { library.resultNotice = result + " See the export folder in Finder." }
    }
    func card(_ family: Family, face: Face, metrics: LibraryRowPreviewMetrics) -> some View {
        let shortPreview = preview != "{family}" && preview.trimmingCharacters(in: .whitespacesAndNewlines).count <= 3 && !preview.contains("\n")
        return VStack(alignment: .leading, spacing: shortPreview ? 6 : 14) {
            HStack(spacing: 8) {
                Button { if library.selectedFamilies.contains(family.name) { library.selectedFamilies.remove(family.name) } else { library.selectedFamilies.insert(family.name) } } label: { Image(systemName: library.selectedFamilies.contains(family.name) ? "checkmark.circle.fill" : "circle").font(.system(size: 16)).frame(width: 28, height: 28) }.buttonStyle(.plain).help("Select family for batch actions")
                    .accessibilityLabel("Select \(family.name) for batch actions")
                    .accessibilityValue(library.selectedFamilies.contains(family.name) ? "Selected" : "Not selected")
                    .accessibilityAddTraits(library.selectedFamilies.contains(family.name) ? .isSelected : [])
                VStack(alignment: .leading, spacing: 3) {
                    Text(family.name).font(.system(size: 14, weight: .medium)).lineLimit(2)
                    Text(library.category(family).rawValue + (family.variable ? " (variable)" : "")).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }.frame(height: 42, alignment: .top)
            HStack(spacing: 4) {
                if grid {
                    Button { library.detail = family } label: {
                        Text("\(family.faces.count) \(family.faces.count == 1 ? "style" : "styles")").font(.system(size: 12, weight: .semibold)).fixedSize(horizontal: true, vertical: false).padding(.horizontal, 8).frame(height: 28).background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                    }.buttonStyle(.plain).help("View all styles").accessibilityLabel("Inspect \(family.name), \(family.faces.count) \(family.faces.count == 1 ? "style" : "styles")")
                } else {
                    Text("\(family.faces.count) \(family.faces.count == 1 ? "style" : "styles")").font(.caption).foregroundStyle(.secondary)
                    Button("Inspect \(family.name)") { library.detail = family }.buttonStyle(.bordered)
                }
                Spacer(minLength: 0)
                if grid {
                    Button { library.favorite(family) } label: { Image(systemName: library.saved.favorites.contains(family.name) ? "star.fill" : "star").foregroundStyle(library.saved.favorites.contains(family.name) ? ShelfPalette.ink : Color.primary).font(.system(size: 17)).frame(width: 30, height: 30) }.buttonStyle(.plain).help("Toggle favorite")
                        .accessibilityLabel(library.saved.favorites.contains(family.name) ? "Remove \(family.name) from favorites" : "Add \(family.name) to favorites")
                        .accessibilityValue(library.saved.favorites.contains(family.name) ? "Favorite" : "Not favorite")
                        .accessibilityAddTraits(library.saved.favorites.contains(family.name) ? .isSelected : [])
                    Button { library.compare(family) } label: { Image(systemName: library.comparison.contains(family.name) ? "checkmark.square.fill" : "plus.square").font(.system(size: 17)).frame(width: 30, height: 30) }.buttonStyle(.plain).help("Add or remove from shortlist — open Shortlist in the sidebar")
                        .accessibilityLabel(library.comparison.contains(family.name) ? "Remove \(family.name) from shortlist" : "Add \(family.name) to shortlist")
                        .accessibilityValue(library.comparison.contains(family.name) ? "Shortlisted" : "Not shortlisted")
                        .accessibilityAddTraits(library.comparison.contains(family.name) ? .isSelected : [])
                    Button { library.toggleOverlay(face.name) } label: {
                        Text("AB").font(.system(size: 13, weight: .bold)).foregroundStyle(library.overlayName == face.name ? Color.cyan : Color.primary).frame(width: 30, height: 30)
                    }.buttonStyle(.plain).help(library.overlayName == face.name ? "Turn off the library overlay" : "Compare this font over every preview in the library")
                        .accessibilityLabel(library.overlayName == face.name ? "Turn off \(family.name) library overlay" : "Use \(family.name) as library overlay")
                        .accessibilityValue(library.overlayName == face.name ? "Active overlay" : "Inactive overlay")
                        .accessibilityAddTraits(library.overlayName == face.name ? .isSelected : [])
                }
                Menu { actions(family) } label: { Image(systemName: "ellipsis").font(.system(size: 17)) }.shelfIconMenu().help("More actions for \(family.name)").accessibilityLabel("More actions for \(family.name)")
            }
            if !library.overlayName.isEmpty {
                OverlayPreview(text: preview == "{family}" ? family.name : preview, candidate: face.name, reference: library.overlayName, size: size, library: library, baseline: metrics.baseline, maximumLines: 3).frame(height: metrics.height, alignment: .topLeading).allowsHitTesting(false)
            } else {
                FontPreview(text: preview == "{family}" ? family.name : preview, name: face.name, size: size, wraps: true, variations: library.pro.axes[face.name] ?? [:], features: library.pro.features[face.name] ?? [:], baseline: metrics.baseline, maximumLines: 3).frame(height: metrics.height, alignment: .topLeading).allowsHitTesting(false)
            }
            if grid && !shortPreview { Button("Expand preview…") { library.detail = family }.buttonStyle(.plain).font(.caption).foregroundStyle(.secondary).help("Open all preview text and font styles").accessibilityLabel("Expand \(family.name) preview") }
        }.frame(maxWidth: .infinity, alignment: .topLeading).modifier(ShelfCardSurface(selected: library.selectedFamilies.contains(family.name))).contentShape(Rectangle()).onTapGesture { library.detail = family }.onDrag { FontDragPayload.provider(library.chosenFace(family).name) }.contextMenu { actions(family) }
    }
    @ViewBuilder func actions(_ family: Family) -> some View {
        FontActivationButton(face: library.chosenFace(family)) { library.message = $0 }
        Button("License sources…") { licenseFace = library.chosenFace(family) }
        Divider()
        Button("New typeboard with this font") { library.pairSelection([library.chosenFace(family).name], source: family.name) }
        Button(library.comparison.contains(family.name) ? "Remove from comparison" : "Add to comparison") { library.compare(family) }
        Button("Use as overlay reference") { library.overlayName = library.chosenFace(family).name }
        Button("View all styles") { library.detail = family }
        Button(library.saved.favorites.contains(family.name) ? "Remove favorite" : "Add favorite") { library.favorite(family) }
        Menu("Set category") {
            Button("Automatic (\(family.automaticCategory.rawValue))") { _ = library.setCategory(nil, for: family.name) }
            ForEach(Category.allCases, id: \.self) { c in Button(c.rawValue) { _ = library.setCategory(c, for: family.name) } }
        }
        Menu("Collections") {
            if library.saved.collections.isEmpty { Button("Create a collection…") { showCollection = true } }
            ForEach(library.saved.collections.keys.sorted(), id: \.self) { name in
                Button((library.saved.collections[name]!.contains(family.name) ? "✓ " : "") + name) { _ = library.toggleCollectionMembership(family.name, in: name) }
            }
        }
        Button("Export font family…") { reportFontExport(family.faces) }
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
    let library: Library
    init(library: Library = Library()) { self.library = library; super.init() }
    let settingsWindow = TypefieldSettingsWindow()
    lazy var workspaceWindows = WorkspaceWindows(library: library)
    var activeWorkspace: WorkspaceMode {
        if let mode = workspaceWindows.mode(for: NSApp.keyWindow) { return mode }
        if NSApp.keyWindow?.title == "Typefield: Inspector" { return .spaces }
        if workspaceWindows.isBrowser(NSApp.keyWindow) { return .library }
        return library.workspace
    }
    var activeEditorWindow: NSWindow { NSApp.keyWindow ?? window }
    var editorIsKey: Bool { window.isKeyWindow || workspaceWindows.mode(for: NSApp.keyWindow) != nil }
    func applicationDidFinishLaunching(_ notification: Notification) {
        if Bundle.main.bundleIdentifier == "local.typefield.app", !UserDefaults.standard.bool(forKey: "typefield.legacyPreferencesChecked") {
            let old = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Preferences/local.fontshelf.app.plist")
            if FileManager.default.fileExists(atPath: old.path) { _ = try? StoreMigration.importPreferences(from: old) }
            UserDefaults.standard.set(true, forKey: "typefield.legacyPreferencesChecked")
        }
        NSApp.setActivationPolicy(.regular)
        let theme = UserDefaults.standard.string(forKey: "appearance") ?? "Dark"
        NSApp.appearance = theme == "System" ? nil : NSAppearance(named: theme == "Dark" ? .darkAqua : .aqua)
        TypefieldIcon.apply()
        let root = ContentView(library: library, windows: workspaceWindows)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1240, height: 850), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.titlebarAppearsTransparent = false
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.title = "Typefield"; window.minSize = NSSize(width: 980, height: 660)
        window.contentView = NSHostingView(rootView: root)
        window.center(); window.setFrameAutosaveName("TypefieldWindow"); window.makeKeyAndOrderFront(nil)
        let menu = NSMenu()
        let appItem = NSMenuItem(title: "Typefield", action: nil, keyEquivalent: ""); menu.addItem(appItem)
        let appMenu = NSMenu(); appItem.submenu = appMenu
        addCommand("About Typefield", "about", to: appMenu)
        addCommand("Privacy & Permissions…", "privacy", to: appMenu)
        addCommand("Settings…", "settings", to: appMenu, key: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Typefield", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Typefield", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let fileMenu = addMenu("File", to: menu)
        addCommand("Add Font Folder…", "folder", to: fileMenu, key: "o")
        addCommand("New Font Browser Window", "newWindow", to: fileMenu, key: "n")
        addCommand("New Collection…", "collection", to: fileMenu, key: "n", modifiers: [.command, .shift])
        addCommand("New Typeboard", "pair", to: fileMenu, key: "k")
        fileMenu.addItem(.separator())
        addCommand("Export Library Backup…", "backup", to: fileMenu)
        addCommand("Import Library Backup…", "restoreBackup", to: fileMenu)
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
        addCommand("Replace Selection with Visible", "select", to: editMenu)
        addCommand("Deselect Families", "deselect", to: editMenu)
        let objectsMenu = addMenu("Spaces Objects", to: editMenu)
        for (title, command, key, modifiers) in [
            ("Duplicate", "duplicate", "d", NSEvent.ModifierFlags.command),
            ("New Text Box", "insertText", "t", [.command, .shift]), ("New Rectangle", "insertShape", "r", [.command, .shift]),
            ("Paste in Place", "pasteInPlace", "v", [.command, .shift]),
            ("Group", "group", "g", [.command]), ("Ungroup", "ungroup", "g", [.command, .shift]),
            ("Flip Horizontally", "flipHorizontal", "h", [.command, .shift]),
            ("Flip Vertically", "flipVertical", "v", [.command, .option]),
            ("Mirror Copy across Vertical Canvas Axis", "mirrorVertical", "h", [.command, .option, .shift]),
            ("Mirror Copy across Horizontal Canvas Axis", "mirrorHorizontal", "v", [.command, .option, .shift]),
            ("Mirror Copies into Four Quadrants", "mirrorBoth", "b", [.command, .option, .shift])
        ] { addCommand(title, "studio.object." + command, to: objectsMenu, key: key, modifiers: modifiers) }
        let fontMenu = addMenu("Font", to: menu)
        addCommand("Inspect Selected Family…", "inspect", to: fontMenu, key: "i")
        addCommand("Edit Tags…", "tagSelected", to: fontMenu, key: "t")
        addCommand("Edit Selected Families…", "familySelected", to: fontMenu)
        addCommand("Toggle Favorites", "favorite", to: fontMenu)
        addCommand("Compare Selected Families…", "compareSelected", to: fontMenu)
        addCommand("Copy Family Names", "copyNames", to: fontMenu)
        fontMenu.addItem(.separator())
        addCommand("Browse Google Fonts…", "Google Fonts", to: fontMenu)
        addCommand("Watched Folders…", "Folders", to: fontMenu)
        addCommand("Inspect Font Files…", "Font Health", to: fontMenu)
        addCommand("Find Duplicates…", "Duplicates", to: fontMenu)
        addCommand("Manage Families…", "Families", to: fontMenu)
        addCommand("Tag Backups…", "Tags", to: fontMenu)
        addCommand("Temporary Activations…", "Activation", to: fontMenu)
        let viewMenu = addMenu("View", to: menu)
        let workspacesMenu = addMenu("Workspaces", to: viewMenu)
        addCommand("Library", "library", to: workspacesMenu, key: "1")
        addCommand("Spaces", "spaces", to: workspacesMenu, key: "2")
        addCommand("Letterform Editor", "fontLab", to: workspacesMenu, key: "3")
        viewMenu.addItem(.separator())
        let sidebarItem = addCommand("Hide Sidebar", "toggleSidebar", to: viewMenu, key: "s")
        sidebarItem.keyEquivalentModifierMask = [.command, .control]
        viewMenu.addItem(.separator())
        let inspectorMenu = addMenu("Inspector", to: viewMenu)
        addCommand("Toggle Inspector", "studio.inspector.toggle", to: inspectorMenu, key: "i", modifiers: [.command, .option])
        addCommand("Typography", "studio.inspector.typography", to: inspectorMenu, key: "t", modifiers: [.command, .option])
        addCommand("Arrangement", "studio.inspector.arrangement", to: inspectorMenu, key: "a", modifiers: [.command, .option])
        inspectorMenu.addItem(.separator())
        addCommand("Full", "studio.inspector.full", to: inspectorMenu, key: "1", modifiers: [.command, .option])
        addCommand("Slim", "studio.inspector.slim", to: inspectorMenu, key: "2", modifiers: [.command, .option])
        addCommand("Hidden", "studio.inspector.hidden", to: inspectorMenu, key: "3", modifiers: [.command, .option])
        addCommand("Floating", "studio.inspector.floating", to: inspectorMenu, key: "4", modifiers: [.command, .option])
        let toolsMenu = addMenu("Spaces Tools", to: viewMenu)
        for (index, tool) in CanvasInteractionTool.allCases.enumerated() {
            addCommand(tool.rawValue, "studio.tool." + tool.rawValue.lowercased(), to: toolsMenu, key: String(index), modifiers: [.command, .shift])
        }
        let canvasMenu = addMenu("Canvas", to: viewMenu)
        addCommand("Focus Canvas", "studio.canvasFocus", to: canvasMenu, key: ".")
        addCommand("Fit Canvas Width", "studio.canvas.fit", to: canvasMenu, key: "0")
        canvasMenu.addItem(.separator())
        addCommand("Previous Canvas", "studio.previousCanvas", to: canvasMenu, key: "\u{F702}", modifiers: [.command, .option])
        addCommand("Next Canvas", "studio.nextCanvas", to: canvasMenu, key: "\u{F703}", modifiers: [.command, .option])
        viewMenu.addItem(.separator())
        let libraryViewMenu = addMenu("Library View", to: viewMenu)
        addCommand("List", "list", to: libraryViewMenu, key: "l", modifiers: [.command, .shift])
        addCommand("Grid", "grid", to: libraryViewMenu, key: "g", modifiers: [.command, .shift])
        libraryViewMenu.addItem(.separator())
        addCommand("Larger Preview", "larger", to: libraryViewMenu, key: "+")
        addCommand("Smaller Preview", "smaller", to: libraryViewMenu, key: "-")
        addCommand("Reset Preview Size", "resetSize", to: libraryViewMenu, key: "0")
        addCommand("Preview Colors…", "colors", to: libraryViewMenu)
        libraryViewMenu.addItem(.separator())
        addCommand("Advanced Filters…", "filters", to: libraryViewMenu)
        addCommand("Clear Filters", "clearFilters", to: libraryViewMenu)
        addCommand("Show Shortlist…", "comparison", to: libraryViewMenu)
        addCommand("Refresh Fonts", "refresh", to: libraryViewMenu, key: "r")
        let windowItem = NSMenuItem()
        menu.addItem(windowItem)
        let windowMenu = NSMenu(title: "Window")
        windowItem.submenu = windowMenu
        NSApp.windowsMenu = windowMenu
        addCommand("Pop Out Spaces", "popSpaces", to: windowMenu, key: "2", modifiers: [.command, .option, .shift])
        addCommand("Pop Out Letterform Editor", "popFontLab", to: windowMenu, key: "3", modifiers: [.command, .option, .shift])
        addCommand("Dock Editor Window", "dockEditor", to: windowMenu, key: "0", modifiers: [.command, .option, .shift])
        addCommand("New Font Browser Window", "newWindow", to: windowMenu)
        windowMenu.addItem(.separator())
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        let fullScreenItem = windowMenu.addItem(withTitle: "Enter Full Screen", action: #selector(toggleMainFullScreen(_:)), keyEquivalent: "f")
        fullScreenItem.target = self
        fullScreenItem.keyEquivalentModifierMask = [.command, .control]
        windowMenu.addItem(.separator())
        addCommand("Dock Inspector to Main Window", "dockInspector", to: windowMenu)
        let helpMenu = addMenu("Help", to: menu)
        addCommand("Getting Started Tour…", "tour", to: helpMenu)
        addCommand("Keyboard Shortcuts…", "shortcuts", to: helpMenu, key: "/")
        helpMenu.addItem(.separator())
        addCommand("Send Feedback…", "feedback", to: helpMenu)
        addCommand("Report a Bug…", "bugReport", to: helpMenu)
        NSApp.helpMenu = helpMenu
        NSApp.mainMenu = menu
        NSApp.addWindowsItem(window, title: "Typefield", filename: false)
        NSApp.activate(ignoringOtherApps: true)
        let activationErrors = CommandLine.arguments.contains("--window-qa") ? [] : ActivationManager.shared.clear(restore: false)
        if !activationErrors.isEmpty { library.message = "Some previous temporary activations could not be cleared: " + activationErrors.joined(separator: "\n") }
        library.reload(register: !CommandLine.arguments.contains("--window-qa"))
    }
    func addMenu(_ title: String, to parent: NSMenu) -> NSMenu {
        let item = NSMenuItem(); parent.addItem(item)
        let submenu = NSMenu(title: title); item.submenu = submenu; return submenu
    }
    @discardableResult func addCommand(_ title: String, _ command: String, to menu: NSMenu, key: String = "", modifiers: NSEvent.ModifierFlags = [.command]) -> NSMenuItem {
        let item = menu.addItem(withTitle: title, action: #selector(runMenuCommand(_:)), keyEquivalent: key)
        item.target = self; item.representedObject = command; item.keyEquivalentModifierMask = modifiers
        return item
    }
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(undo(_:)) {
            if let manager = activeUndoManager { item.title = manager.undoMenuItemTitle; return manager.canUndo }
            let editorOwnsHistory = activeWorkspace == .fontLab && editorIsKey && activeEditorWindow.attachedSheet == nil && !(activeEditorWindow.firstResponder is NSTextView)
            item.title = editorOwnsHistory ? FontLabEditMenuBridge.shared.undoTitle : "Undo"
            return editorOwnsHistory && FontLabEditMenuBridge.shared.canUndo
        }
        if item.action == #selector(redo(_:)) {
            if let manager = activeUndoManager { item.title = manager.redoMenuItemTitle; return manager.canRedo }
            let editorOwnsHistory = activeWorkspace == .fontLab && editorIsKey && activeEditorWindow.attachedSheet == nil && !(activeEditorWindow.firstResponder is NSTextView)
            item.title = editorOwnsHistory ? FontLabEditMenuBridge.shared.redoTitle : "Redo"
            return editorOwnsHistory && FontLabEditMenuBridge.shared.canRedo
        }
        if item.action == #selector(toggleMainFullScreen(_:)) {
            item.title = activeEditorWindow.styleMask.contains(.fullScreen) ? "Exit Full Screen" : "Enter Full Screen"
            return NSApp.isActive && activeEditorWindow.attachedSheet == nil
        }
        guard let command = item.representedObject as? String else { return true }
        if ["settings", "about", "privacy", "shortcuts", "feedback", "bugReport"].contains(command) { return true }
        let inspectorIsKey = NSApp.keyWindow?.title == "Typefield: Inspector" && activeWorkspace == .spaces
        if command == "dockInspector" { return NSApp.isActive && inspectorIsKey && window.attachedSheet == nil }
        if ["newWindow", "popSpaces", "popFontLab"].contains(command) { return NSApp.isActive && NSApp.keyWindow?.attachedSheet == nil }
        if command == "dockEditor" { return workspaceWindows.mode(for: NSApp.keyWindow) != nil && activeEditorWindow.attachedSheet == nil }
        guard NSApp.isActive, activeEditorWindow.attachedSheet == nil, window.isKeyWindow || workspaceWindows.mode(for: NSApp.keyWindow) != nil || inspectorIsKey else { return false }
        if command.hasPrefix("studio.object.") || command.hasPrefix("studio.tool.") { return activeWorkspace == .spaces && !(NSApp.keyWindow?.firstResponder is NSTextView) }
        let inLibrary = activeWorkspace == .library
        let selected = library.families.filter { library.selectedFamilies.contains($0.name) }
        switch command {
        case "library", "spaces", "fontLab":
            item.state = (command == "library" && inLibrary) || (command == "spaces" && activeWorkspace == .spaces) || (command == "fontLab" && activeWorkspace == .fontLab) ? .on : .off
        case "inspect": return inLibrary && selected.count == 1
        case "export", "tagSelected", "familySelected", "favorite", "copyNames", "deselect": return inLibrary && !selected.isEmpty
        case "compareSelected": return inLibrary && (2...6).contains(selected.count)
        case "select": return inLibrary && !library.filtered.isEmpty
        case "find": item.title = activeWorkspace == .spaces ? "Choose Font…" : "Find Fonts…"; return inLibrary || activeWorkspace == .spaces
        case "list", "grid":
            item.state = (UserDefaults.standard.object(forKey: "adaptiveGridView") as? Bool ?? true) == (command == "grid") ? .on : .off
            return inLibrary
        case "larger", "smaller", "resetSize", "colors", "filters", "clearFilters": return inLibrary
        case "comparison": return inLibrary
        case "studio.previousCanvas", "studio.nextCanvas", "studio.canvas.fit", "studio.inspector.full", "studio.inspector.slim", "studio.inspector.hidden", "studio.inspector.floating", "studio.inspector.toggle", "studio.inspector.typography", "studio.inspector.arrangement", "studio.canvasFocus":
            return activeWorkspace == .spaces && !(NSApp.keyWindow?.firstResponder is NSTextView)
        case "refresh": return inLibrary && !library.loading
        case "toggleSidebar": item.title = WorkspaceSidebarPreference.collapsed() ? "Show Sidebar" : "Hide Sidebar"
        default: break
        }
        return true
    }
    var activeUndoManager: UndoManager? {
        if let text = NSApp.keyWindow?.firstResponder as? NSTextView, !(activeWorkspace == .spaces && text.isFieldEditor), let manager = text.undoManager, manager.canUndo || manager.canRedo { return manager }
        guard NSApp.keyWindow === window || workspaceWindows.mode(for: NSApp.keyWindow) != nil || NSApp.keyWindow?.title == "Typefield: Inspector" else { return nil }
        return activeWorkspace == .spaces ? library.studio.undoManager : nil
    }
    @objc func undo(_ sender: Any?) {
        if let manager = activeUndoManager {
            if manager === library.studio.undoManager { activeEditorWindow.makeFirstResponder(nil) }
            manager.undo()
        } else if activeWorkspace == .fontLab && editorIsKey && activeEditorWindow.attachedSheet == nil && !(activeEditorWindow.firstResponder is NSTextView) {
            FontLabEditMenuBridge.shared.requestUndo()
        }
    }
    @objc func redo(_ sender: Any?) {
        if let manager = activeUndoManager {
            if manager === library.studio.undoManager { activeEditorWindow.makeFirstResponder(nil) }
            manager.redo()
        } else if activeWorkspace == .fontLab && editorIsKey && activeEditorWindow.attachedSheet == nil && !(activeEditorWindow.firstResponder is NSTextView) {
            FontLabEditMenuBridge.shared.requestRedo()
        }
    }
    @objc func toggleMainFullScreen(_ sender: Any?) { activeEditorWindow.toggleFullScreen(sender) }
    @objc func runMenuCommand(_ sender: NSMenuItem) {
        guard validateMenuItem(sender), let command = sender.representedObject as? String else { return }
        let selected = library.families.filter { library.selectedFamilies.contains($0.name) }
        switch command {
        case "newWindow": workspaceWindows.openBrowser()
        case "popSpaces": workspaceWindows.detach(.spaces)
        case "popFontLab": workspaceWindows.detach(.fontLab)
        case "dockEditor": if let mode = workspaceWindows.mode(for: NSApp.keyWindow) { workspaceWindows.dock(mode) }
        case "folder": library.addFolder()
        case "library": library.workspace = .library; window.makeKeyAndOrderFront(nil)
        case "spaces":
            library.workspace = .spaces
            if workspaceWindows.detached.contains(.spaces) { workspaceWindows.detach(.spaces) } else { window.makeKeyAndOrderFront(nil) }
        case "fontLab":
            library.workspace = .fontLab
            if workspaceWindows.detached.contains(.fontLab) { workspaceWindows.detach(.fontLab) } else { window.makeKeyAndOrderFront(nil) }
        case "dockInspector":
            NotificationCenter.default.post(name: Notification.Name("TypefieldMenu"), object: "studio.inspector.full")
            if workspaceWindows.detached.contains(.spaces) { workspaceWindows.detach(.spaces) } else { window.makeKeyAndOrderFront(nil) }
        case "settings": settingsWindow.show(library: library)
        case "about": settingsWindow.show(library: library, page: .about)
        case "privacy": settingsWindow.show(library: library, page: .privacy)
        case "shortcuts": settingsWindow.show(library: library, page: .shortcuts)
        case "feedback": NSWorkspace.shared.open(TypefieldSupportLinks.feedback)
        case "bugReport": NSWorkspace.shared.open(TypefieldSupportLinks.bugReport)
        case "Folders": settingsWindow.show(library: library, page: .folders)
        case "tour":
            window.makeKeyAndOrderFront(nil)
            NotificationCenter.default.post(name: Notification.Name("TypefieldMenu"), object: command)
        case "pair":
            if activeWorkspace == .library {
                let seed = library.contextualTypeboardSeed()
                library.pairSelection(selected.isEmpty ? seed.fonts : selected.map { library.chosenFace($0).name }, source: selected.isEmpty ? seed.source : "Selected Library fonts")
            } else { library.pairSelection([], source: "Blank typeboard") }
        case "backup": LibraryBackupTools.export(library)
        case "restoreBackup": LibraryBackupTools.restore(library)
        case "Tags", "Families", "Duplicates", "Font Health", "Google Fonts", "Activation": library.openTools(command)
        case "tagSelected": library.openTools("Tags")
        case "familySelected": library.openTools("Families")
        case "export": if let result = FontExporter.export(library.selectedFaces) { if result.hasPrefix("Export failed:") || result.contains("\n") { library.message = result } else { library.resultNotice = result + " See the export folder in Finder." } }
        case "select": library.selectVisibleFamilies()
        case "deselect": library.selectedFamilies = []
        case "inspect": library.detail = selected.first
        case "favorite": for family in selected { library.favorite(family) }
        case "compareSelected": library.comparison = selected.map(\.name); library.showCompare = true
        case "comparison": library.showCompare = true
        case "copyNames": NSPasteboard.general.clearContents(); NSPasteboard.general.setString(selected.map(\.name).joined(separator: "\n"), forType: .string)
        case "filters": library.showAdvanced.toggle()
        case "clearFilters": library.clearFiltersPreservingSection()
        case "refresh": library.reload(register: true)
        default: NotificationCenter.default.post(name: Notification.Name("TypefieldMenu"), object: command)
        }
    }
    func applicationWillTerminate(_ notification: Notification) { if !CommandLine.arguments.contains("--window-qa") { ActivationManager.shared.clear(restore: false) } }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { window.makeKeyAndOrderFront(nil) }
        return true
    }
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
        let expectedStyleCount = catalog.reduce(0) { $0 + $1.faces.count }
        precondition(library.styleCount == expectedStyleCount && library.allFaces.count == expectedStyleCount, "Catalog indexes changed the style count")
        precondition(library.availableFaceNames == Set(catalog.flatMap(\.faces).map(\.name)), "Catalog name index changed its contents")
        let catalogAccess = measure(iterations: 10_000) { library.allFaces.count &+ library.availableFaceNames.count }
        let sidebarCounts = measure(iterations: 100) { LibrarySidebarSnapshot(library: library).checksum }
        library.search = "a"
        let filtering = measure(iterations: 100) {
            library.invalidateFilteredCatalog()
            return library.filtered.reduce(0) { $0 &+ $1.faces.count }
        }
        let cachedFiltering = measure(iterations: 100) { library.filtered.reduce(0) { $0 &+ $1.faces.count } }
        precondition(filtering.checksum == cachedFiltering.checksum, "Cached filtering changed catalog results")
        let reference = catalog.first(where: { $0.automaticCategory != .symbol })?.representative
        let pairing = measure(iterations: 10) {
            guard let reference else { return 0 }
            return FontPairingEngine.recommendations(for: reference, intendedRole: .heading, catalog: catalog, limit: 16).reduce(0) { $0 &+ Int($1.score) }
        }
        let similarity = measure(iterations: 10) {
            guard let reference, let family = catalog.first(where: { $0.faces.contains(where: { $0.name == reference.name }) }) else { return 0 }
            return LibraryIntelligence.similarFamilies(to: reference, referenceCategory: family.automaticCategory, catalog: catalog, limit: 12).reduce(0) { $0 &+ Int($1.distance * 1_000) }
        }

        var direction = TypeDirection(name: "Performance audit", fonts: ["Helvetica", "Times-Roman"])
        direction.canvas = .editorial
        direction.width = 1_200
        let direct = measure(iterations: 20) { CanvasPlan(direction: direction).elements.count }
        CanvasPlanCache.removeAll()
        _ = CanvasPlanCache.plan(for: direction)
        let cached = measure(iterations: 200) { CanvasPlanCache.plan(for: direction).elements.count }
        precondition(direct.checksum / 20 == cached.checksum / 200, "Cached canvas plan changed its output")

        print(String(format: "PERF catalog scan: %.2f ms (%d families, %d styles)", scanMilliseconds, catalog.count, catalog.reduce(0) { $0 + $1.faces.count }))
        print(String(format: "PERF cached catalog access: %.6f ms/pass", catalogAccess.milliseconds))
        print(String(format: "PERF sidebar count snapshot: %.3f ms/pass", sidebarCounts.milliseconds))
        print(String(format: "PERF library filter: %.3f ms uncached, %.6f ms cached", filtering.milliseconds, cachedFiltering.milliseconds))
        print(String(format: "PERF pairing rank: %.3f ms/pass; similarity rank: %.3f ms/pass", pairing.milliseconds, similarity.milliseconds))
        print(String(format: "PERF canvas plan: %.3f ms uncached, %.6f ms cached (%.1fx faster)", direct.milliseconds, cached.milliseconds, direct.milliseconds / max(0.000_001, cached.milliseconds)))

        // Exercise the real Spaces read and selection paths without opening or
        // changing the user's saved projects. Every fixture is removed on exit.
        let fixtureRoot = FileManager.default.temporaryDirectory.appendingPathComponent("Typefield-navigation-audit-" + UUID().uuidString)
        do {
            try FileManager.default.createDirectory(at: fixtureRoot, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: fixtureRoot) }
            func percentile(_ samples: [Double], _ fraction: Double) -> Double {
                let sorted = samples.sorted()
                return sorted[min(sorted.count - 1, max(0, Int(ceil(Double(sorted.count) * fraction)) - 1))]
            }
            func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
                if !condition() {
                    throw NSError(domain: "Typefield.PerformanceAudit", code: 1,
                                  userInfo: [NSLocalizedDescriptionKey: message])
                }
            }
            for boardCount in [2, 50, 200] {
                let url = fixtureRoot.appendingPathComponent("spaces-\(boardCount).json")
                var space = DesignSpace(name: "Performance fixture")
                space.boards = (0..<boardCount).map { TypeBoard(name: "Typeboard \($0 + 1)") }
                let seed = StudioStore(url: url)
                seed.state.spaces = [space]
                seed.focusedSpace = space.id
                seed.focusedBoard = space.boards[0].id
                try require(seed.save(), "Could not write disposable Spaces fixture")

                var loadTimes: [Double] = []
                loadTimes.reserveCapacity(10)
                for _ in 0..<10 {
                    let start = CFAbsoluteTimeGetCurrent()
                    let loaded = StudioStore(url: url)
                    loadTimes.append((CFAbsoluteTimeGetCurrent() - start) * 1_000)
                    try require(!loaded.readBlocked && loaded.state.spaces.first?.boards.count == boardCount,
                                "Disposable Spaces fixture did not round-trip")
                }

                let selected = StudioStore(url: url)
                let first = space.boards[0].id
                let last = space.boards[boardCount - 1].id
                var selectTimes: [Double] = []
                selectTimes.reserveCapacity(20)
                for index in 0..<20 {
                    let target = index.isMultiple(of: 2) ? last : first
                    let start = CFAbsoluteTimeGetCurrent()
                    let saved = selected.select(space: space.id, board: target)
                    selectTimes.append((CFAbsoluteTimeGetCurrent() - start) * 1_000)
                    try require(saved && selected.focusedBoard == target,
                                "Disposable Spaces selection failed")
                }
                let reopened = StudioStore(url: url)
                try require(reopened.focusedBoard == first, "Disposable Spaces selection was not persisted")
                let kilobytes = Double((try? Data(contentsOf: url).count) ?? 0) / 1_024
                print(String(format: "PERF Spaces %d boards (%.0f KB): first load %.3f ms, fresh-store load median %.3f ms, p95 %.3f ms; selection save median %.3f ms, p95 %.3f ms",
                             boardCount, kilobytes, loadTimes[0], percentile(loadTimes, 0.5), percentile(loadTimes, 0.95),
                             percentile(selectTimes, 0.5), percentile(selectTimes, 0.95)))
            }
        } catch {
            fputs("PERF Spaces navigation audit failed: \(error.localizedDescription)\n", stderr)
        }
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
} else if let index = CommandLine.arguments.firstIndex(of: "--font-lab-artwork-fixtures"), CommandLine.arguments.count > index + 1 {
    do { try FontLabArtworkChecks.writeFixtures(to: URL(fileURLWithPath: CommandLine.arguments[index + 1])) }
    catch { fputs("Artwork fixtures failed: \(error.localizedDescription)\n", stderr); exit(1) }
} else if CommandLine.arguments.contains("--performance-audit") {
    PerformanceAudit.run()
} else if CommandLine.arguments.contains("--starter-quality-audit") {
    exit(FontLabStarterQualityAudit.run() ? 0 : 1)
} else if CommandLine.arguments.contains("--stress-regression-check") {
    do { try StudioChecks.stress(); try FontLabVectorChecks.run(); try FontLabDesignChecks.run(); try FontLabStarterAssistChecks.run() }
    catch { fputs("Stress regression failed: \(error.localizedDescription)\n",stderr);exit(1) }
} else if CommandLine.arguments.contains("--window-self-test") {
    WorkspaceWindowChecks.run()
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
    precondition(PreviewLayout.cardWidth(text: String(repeating: "long sentence ", count: 20), size: 160, available: 800) == 600)
    precondition(PreviewLayout.cardWidth(text: "there is", size: 32, available: 1500) < PreviewLayout.cardWidth(text: "there is", size: 160, available: 1500))
    let fonts = FontCatalog.scan()
    precondition(!fonts.isEmpty, "No installed fonts found")
    precondition(Set(fonts.map(\.id)).count == fonts.count, "Duplicate families")
    for (name, expected) in [("Times-Roman", Category.serif), ("Helvetica", .sans), ("Courier", .mono)] {
        let font = CTFontCreateWithName(name as CFString, 24, nil)
        precondition(FontCatalog.category(font) == expected, "Classification failed for \(name)")
    }
    let testLibrary = Library(storageURL: FileManager.default.temporaryDirectory.appendingPathComponent("FontShelf-tests-" + UUID().uuidString + "/library.json"))
    var publishedCatalogWasCoherent = false
    let catalogSubscription = testLibrary.$families.dropFirst().sink { publishedFamilies in
        publishedCatalogWasCoherent = testLibrary.styleCount == publishedFamilies.reduce(0) { $0 + $1.faces.count }
    }
    testLibrary.families = fonts
    let indexedFaces = fonts.flatMap(\.faces)
    precondition(publishedCatalogWasCoherent, "Catalog indexes must be updated before the new family list is published")
    precondition(testLibrary.styleCount == indexedFaces.count)
    precondition(testLibrary.allFaces.map(\.name) == indexedFaces.map(\.name))
    precondition(testLibrary.availableFaceNames == Set(indexedFaces.map(\.name)))
    precondition(indexedFaces.first.map { testLibrary.face(named: $0.name)?.name == $0.name } ?? true)
    withExtendedLifetime(catalogSubscription) {}
    // Warm the snapshot before each mutation, then compare with a fresh scan.
    // Nested value-type edits must invalidate just like replacing the property.
    func checkFilterInvalidation(_ change: () -> Void) {
        _ = testLibrary.filtered
        change()
        let names = testLibrary.filtered.map(\.name)
        let count = testLibrary.matchingStyleCount
        testLibrary.invalidateFilteredCatalog()
        precondition(names == testLibrary.filtered.map(\.name), "Library filter cache retained stale families")
        precondition(count == testLibrary.matchingStyleCount, "Library filter cache retained stale style count")
        precondition(count == testLibrary.filtered.reduce(0) { $0 + testLibrary.matchingFaces(in: $1).count })
    }
    checkFilterInvalidation { testLibrary.search = "Helvetica" }
    checkFilterInvalidation { testLibrary.search = "" }
    checkFilterInvalidation { testLibrary.sort = "Name Z–A" }
    checkFilterInvalidation { testLibrary.source = "User / third-party" }
    checkFilterInvalidation { testLibrary.source = "All sources" }
    checkFilterInvalidation { testLibrary.variableOnly = true }
    checkFilterInvalidation { testLibrary.variableOnly = false }
    checkFilterInvalidation { testLibrary.writing = .devanagari }
    checkFilterInvalidation { testLibrary.writing = nil }
    checkFilterInvalidation { testLibrary.requiredText = "हिन्दी"; testLibrary.requireCoverage = true }
    checkFilterInvalidation { testLibrary.requiredText = "Hello" }
    checkFilterInvalidation { testLibrary.requireCoverage = false }
    checkFilterInvalidation { testLibrary.advanced.slant = "Italic" }
    checkFilterInvalidation { testLibrary.advanced = AdvancedFilter() }
    checkFilterInvalidation { testLibrary.tagQuery.included = ["cache-test"] }
    checkFilterInvalidation { testLibrary.pro.tags[fonts[0].faces[0].name] = ["cache-test"] }
    checkFilterInvalidation { testLibrary.tagQuery = TagQuery() }
    checkFilterInvalidation { testLibrary.selection = "Favorites" }
    checkFilterInvalidation { testLibrary.saved.favorites.insert(fonts[0].name) }
    checkFilterInvalidation { testLibrary.selection = "All Fonts" }
    checkFilterInvalidation { testLibrary.families = Array(fonts.prefix(1)) }
    checkFilterInvalidation { testLibrary.families = fonts }
    testLibrary.saved.favorites = []; testLibrary.pro.tags = [:]; testLibrary.sort = "Name A–Z"
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
    let sidebarSnapshot = LibrarySidebarSnapshot(library: testLibrary)
    let sidebarSections = ["All Fonts", "Last Import", "Favorites", "collection:Test"] + Category.allCases.map(\.rawValue)
    precondition(sidebarSections.allSatisfy { section in sidebarSnapshot.count(section: section) == fonts.filter { testLibrary.matchesSection($0, section) }.count })
    precondition(WritingSystem.allCases.allSatisfy { writing in sidebarSnapshot.count(writingSystem: writing) == fonts.filter { $0.writingSystems.contains(writing) }.count })
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
    testLibrary.requireCoverage = false; testLibrary.requiredText = ""
    testLibrary.advanced.slant = "Italic"
    precondition(!testLibrary.filteredFaces.isEmpty && testLibrary.filteredFaces.allSatisfy { $0.facts.italic }, "Style filter must apply to metadata rows")
    precondition(testLibrary.filteredFaces.count == testLibrary.filtered.reduce(0) { $0 + testLibrary.matchingFaces(in: $1).count }, "Metadata and grid must share face counts")
    testLibrary.advanced = AdvancedFilter()
    if let multiStyleFamily = fonts.first(where: { $0.faces.count > 1 }) {
        let taggedFace = multiStyleFamily.faces[0]
        testLibrary.pro.tags[taggedFace.name, default: []].insert("qa/face-only")
        testLibrary.tagQuery.included.insert("qa/face-only")
        precondition(testLibrary.filtered.map(\.name) == [multiStyleFamily.name] && testLibrary.filteredFaces.map(\.name) == [taggedFace.name], "Tag filters must not include untagged sibling styles")
        testLibrary.tagQuery = TagQuery()
        testLibrary.selection = "tag:qa/face-only"
        precondition(testLibrary.filteredFaces.map(\.name) == [taggedFace.name], "Tag sections must count only matching styles")
        testLibrary.selection = "All Fonts"
    }
    testLibrary.search = "Helvetica"; testLibrary.requiredText = "Hello"; testLibrary.requireCoverage = true
    precondition(testLibrary.saveCurrentSearch(as: "Preview round trip", previewText: "Hello"))
    let collectionChecks = Library(storageURL: FileManager.default.temporaryDirectory.appendingPathComponent("Typefield-collection-check-" + UUID().uuidString + "/library.json"))
    defer { try? FileManager.default.removeItem(at: collectionChecks.saveURL.deletingLastPathComponent()) }
    collectionChecks.families = fonts
    collectionChecks.saved.collections["Before"] = [fonts[0].name]
    collectionChecks.selection = "collection:Before"
    precondition(collectionChecks.saveCurrentSearch(as: "Scoped", previewText: "Custom specimen"))
    collectionChecks.selection = "All Fonts"
    precondition(collectionChecks.saveCurrentSearch(as: "Global", previewText: "Global specimen"))
    precondition(collectionChecks.renameCollection("Before", to: "After"))
    precondition(collectionChecks.applySavedSearch("Scoped") == "Custom specimen")
    precondition(collectionChecks.selection == "collection:After" && collectionChecks.filtered.map(\.name) == [fonts[0].name], "Saved searches must follow renamed collections")
    precondition(collectionChecks.saved.savedSearches?["Global"]?.section == "All Fonts")
    precondition(Library(storageURL: collectionChecks.saveURL).saved.savedSearches?["Scoped"]?.section == "collection:After", "Renamed saved-search scope must persist")
    let previousCollectionSearches = collectionChecks.saved.savedSearches
    collectionChecks.librarySaveBlocked = true
    precondition(!collectionChecks.renameCollection("After", to: "Rejected"))
    precondition(collectionChecks.saved.savedSearches == previousCollectionSearches && collectionChecks.saved.collections["After"] != nil && collectionChecks.saved.collections["Rejected"] == nil && collectionChecks.selection == "collection:After", "A failed rename must roll back searches, members and selection together")
    let savedSearchData = try JSONEncoder().encode(testLibrary.saved.savedSearches!["Preview round trip"]!)
    let restoredSavedSearch = try JSONDecoder().decode(SavedSearch.self, from: savedSearchData)
    testLibrary.saved.savedSearches = ["Preview round trip": restoredSavedSearch]
    testLibrary.search = ""; testLibrary.requiredText = "Different"; testLibrary.requireCoverage = false
    precondition(testLibrary.applySavedSearch("Preview round trip") == "Hello" && testLibrary.requiredText == "Hello" && testLibrary.requireCoverage, "Saved search must restore its visible preview and coverage text")
    var legacySearchObject = try JSONSerialization.jsonObject(with: savedSearchData) as! [String: Any]
    legacySearchObject.removeValue(forKey: "previewText")
    let legacySearch = try JSONDecoder().decode(SavedSearch.self, from: JSONSerialization.data(withJSONObject: legacySearchObject))
    precondition(legacySearch.previewText == nil, "Earlier saved searches must remain readable")
    testLibrary.search = ""; testLibrary.requireCoverage = false; testLibrary.requiredText = ""
    testLibrary.requireCoverage = false; testLibrary.compare(fonts[0]); precondition(testLibrary.compared.count == 1)
    testLibrary.compare(fonts[0]); precondition(testLibrary.compared.isEmpty)
    AdobeBridge.selfTest()
    AdobeTypeSystemExporter.selfTest()
    AdobeTypeSystemReturnBridge.selfTest()
    precondition(FontPairingEngine.selfTest(), "Font pairing engine checks failed")
    do { try GlyphBrowserChecks.run(); try TypefieldSettingsChecks.run(); try FontLabStore.selfTest(); try FontLabArtworkChecks.run(); try FontLabVectorChecks.run(); try FontLabDesignChecks.run(); try FontLabStarterAssistChecks.run(); try FontLabRemixEngine.selfTest(); try FontLabTrueTypeExporter.selfTest(); try ProChecks.run(catalog: fonts); try GoogleFontDownloadChecks.run(); try StudioChecks.stress(); try StudioChecks.run(catalog: fonts); try FontRepairChecks.run(catalog: fonts) }
    catch { fputs("Regression check failed: \(error.localizedDescription)\n", stderr); exit(1) }
    print("PASS: script probes, combined filters, missing characters, comparison and Adobe export DOM fixtures.")
    print("PASS: \(fonts.count) families, \(fonts.reduce(0) { $0 + $1.faces.count }) styles. Classification, search, filters, sorting, collections, overrides and persistence verified.")
    for c in Category.allCases { print("\(c.rawValue): \(fonts.filter { $0.automaticCategory == c }.count)") }
} else {
    let app = NSApplication.shared
    let delegate: AppDelegate
    if CommandLine.arguments.contains("--window-qa") {
        let fixture = Library(storageURL: FileManager.default.temporaryDirectory.appendingPathComponent("Typefield-window-qa-" + UUID().uuidString + "/library.json"))
        _ = fixture.studio.createBoard(in: nil, defaultSpaceName: "Window QA", fonts: ["Helvetica", "Times-Roman"])
        if CommandLine.arguments.contains("--spaces-interaction-qa"), let space = fixture.studio.state.spaces.first, var board = space.boards.first {
            board.directions = [SpacesInteractionChecks.importedFixture()]
            board.selectedDirection = board.directions[0].id
            _ = fixture.studio.update(space: space.id, board: board)
        }
        _ = fixture.fontLab.addProject(name: "Window QA")
        fixture.comparison = ["Helvetica", "Times"]
        fixture.workspace = .spaces
        delegate = AppDelegate(library: fixture)
    } else { delegate = AppDelegate() }
    app.delegate = delegate
    app.run()
}
