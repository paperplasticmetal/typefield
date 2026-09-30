import Foundation
import SwiftUI
import CoreText

struct FontFileStamp: Equatable {
    let size: Int
    let modified: Date
    let identity: String
    static func read(_ url: URL) -> FontFileStamp? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .fileResourceIdentifierKey, .isRegularFileKey]), values.isRegularFile == true else { return nil }
        return FontFileStamp(size: values.fileSize ?? 0, modified: values.contentModificationDate ?? .distantPast, identity: String(describing: values.fileResourceIdentifier))
    }
}
enum FontFolderSnapshot {
    static func read(_ roots: [String], pauseOnError: Set<String> = []) -> (files: [String: FontFileStamp], errors: [String], failedProtectedRoots: Set<String>) {
        var files: [String: FontFileStamp] = [:], errors: [String] = []
        var failedProtectedRoots = Set<String>()
        for root in roots {
            let protected = pauseOnError.contains(root)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: root, isDirectory: &isDirectory), isDirectory.boolValue else {
                errors.append(root + ": Folder unavailable")
                if protected { failedProtectedRoots.insert(root) }
                continue
            }
            guard let enumerator = FileManager.default.enumerator(at: URL(fileURLWithPath: root), includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .fileResourceIdentifierKey, .isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { url, error in
                errors.append(url.path + ": " + error.localizedDescription)
                if protected { failedProtectedRoots.insert(root) }
                return !protected
            }) else {
                errors.append(root + ": Cannot read folder")
                if protected { failedProtectedRoots.insert(root) }
                continue
            }
            for case let url as URL in enumerator where DuplicateFinder.extensions.contains(url.pathExtension.lowercased()) {
                if let stamp = FontFileStamp.read(url) { files[url.standardizedFileURL.path] = stamp }
                else {
                    errors.append(url.path + ": Cannot read font")
                    if protected { failedProtectedRoots.insert(root); break }
                }
            }
        }
        return (files, errors, failedProtectedRoots)
    }
    static func contains(_ path: String, root: String) -> Bool {
        let file = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
        let folder = URL(fileURLWithPath: root).standardizedFileURL.resolvingSymlinksInPath().path
        guard file != folder else { return false }
        return file.hasPrefix(folder == "/" ? "/" : folder + "/")
    }
}
/// Poll recursively on a private queue. This also handles removable and cloud-backed folders.
final class FolderWatcher {
    private let queue = DispatchQueue(label: "FontShelf.folder-watch", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var roots: [String] = []
    private var activeRoots: [String] = []
    private var protectedRoots: Set<String> = []
    private var suppressedRoots: Set<String> = []
    private var last: [String: FontFileStamp]?
    private var errors: [String] = []
    func configure(roots: [String], pauseOnError: Set<String> = [], initialized: (([String], Set<String>) -> Void)? = nil, changed: @escaping ([String], Set<String>) -> Void) {
        queue.async { [weak self] in
            guard let self, self.roots != roots || self.protectedRoots != pauseOnError || self.timer == nil else { return }
            self.timer?.cancel(); self.timer = nil; self.roots = roots; self.protectedRoots = pauseOnError; self.last = nil
            // A removed root may be added again only after the user explicitly
            // chooses it through the picker and Library configures that root.
            self.suppressedRoots.formIntersection(roots)
            self.activeRoots = roots.filter { !self.suppressedRoots.contains($0) }
            self.errors = []
            guard !roots.isEmpty else {
                self.last = [:]
                if let initialized { DispatchQueue.main.async { initialized([], []) } }
                return
            }
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now(), repeating: 3, leeway: .milliseconds(500))
            timer.setEventHandler { [weak self] in
                guard let self else { return }
                let current = FontFolderSnapshot.read(self.activeRoots, pauseOnError: self.protectedRoots)
                if !current.failedProtectedRoots.isEmpty {
                    self.suppressedRoots.formUnion(current.failedProtectedRoots)
                    self.activeRoots.removeAll { current.failedProtectedRoots.contains($0) }
                }
                guard self.last != nil else {
                    self.last = current.files; self.errors = current.errors
                    if let initialized { DispatchQueue.main.async { initialized(current.errors, current.failedProtectedRoots) } }
                    return
                }
                let differs = self.last != current.files || self.errors != current.errors || !current.failedProtectedRoots.isEmpty
                self.last = current.files; self.errors = current.errors
                if differs { DispatchQueue.main.async { changed(current.errors, current.failedProtectedRoots) } }
            }
            self.timer = timer; timer.resume()
        }
    }
    deinit { timer?.cancel() }
}

extension SavedLibrary {
    mutating func replaceWatchedFolder(_ oldPath: String, with newPath: String) {
        guard let oldIndex = folders.firstIndex(of: oldPath) else { return }
        if folders.contains(newPath) && oldPath != newPath { folders.removeAll { $0 == oldPath } }
        else {
            folders.removeAll { $0 == oldPath }
            folders.insert(newPath, at: min(oldIndex, folders.count))
        }
        if autoActivateFolders?.remove(oldPath) != nil { autoActivateFolders?.insert(newPath) }
    }
}

extension Library {
    func pauseProtectedWatchRoots(_ roots: Set<String>) {
        guard !roots.isEmpty else { return }
        for root in roots {
            for savedPath in savedPathsByResolvedFolder[root] ?? [] {
                folderAccess.pauseWatchAfterError(savedPath)
                pausedFolders.insert(savedPath)
            }
            savedPathsByResolvedFolder.removeValue(forKey: root)
        }
        resolvedFolders.removeAll { roots.contains($0) }
        // Reconfigure with only the remaining roots. Neither the saved paths
        // nor the bookmarks are changed, and the failed root is not probed.
        configureWatcher()
    }
    @discardableResult func stopWatchingFolder(_ path: String) -> Bool {
        let previous = saved
        saved.folders.removeAll { $0 == path }
        saved.autoActivateFolders?.remove(path)
        guard save() else { saved = previous; return false }
        reload(register: true)
        return true
    }
    @discardableResult func setFolderActivation(_ path: String, enabled: Bool) -> Bool {
        let previous = saved
        var paths = saved.autoActivateFolders ?? []
        if enabled { paths.insert(path) } else { paths.remove(path) }
        saved.autoActivateFolders = paths
        guard save() else { saved = previous; return false }
        applyFolderActivation()
        return true
    }
    func configureWatcher() {
        let protectedRoots = Set(resolvedFolders.filter { root in
            folderAccess.shouldPauseWatchOnError(root) ||
                (savedPathsByResolvedFolder[root] ?? []).contains(where: folderAccess.shouldPauseWatchOnError)
        })
        folderWatcher.configure(
            roots: resolvedFolders,
            pauseOnError: protectedRoots,
            initialized: { [weak self] errors, failedRoots in
                guard let self else { return }
                self.pauseProtectedWatchRoots(failedRoots)
                if !errors.isEmpty {
                    self.folderStatus = failedRoots.isEmpty ? errors.joined(separator: "\n") :
                        "A protected watched folder was paused after an access error. Choose it again in Live folders to resume."
                }
            },
            changed: { [weak self] errors, failedRoots in
                guard let self else { return }
                if !failedRoots.isEmpty {
                    self.pauseProtectedWatchRoots(failedRoots)
                    self.folderStatus = "A protected watched folder was paused after an access error. Choose it again in Live folders to resume."
                    return
                }
                self.folderStatus = errors.isEmpty ? "Changes detected; refreshing…" : errors.joined(separator: "\n")
                self.reload(register: true)
            }
        )
    }
    func applyFolderActivation() {
        let roots = (saved.autoActivateFolders ?? []).compactMap { try? folderAccess.restore($0) }
        let urls = Set(allFaces.compactMap(\.url).filter { url in roots.contains { FontFolderSnapshot.contains(url.path, root: $0) } })
        var errors: [String] = []
        for path in autoActivatedPaths where !urls.contains(URL(fileURLWithPath: path)) {
            do { try ActivationManager.shared.deactivate(URL(fileURLWithPath: path), restore: FileManager.default.fileExists(atPath: path)); autoActivatedPaths.remove(path); autoActivatedStamps.removeValue(forKey: path) }
            catch { errors.append(error.localizedDescription) }
        }
        for url in urls where !ActivationManager.shared.owns(url) {
            do { _ = try ActivationManager.shared.activate(url); if ActivationManager.shared.owns(url) { autoActivatedPaths.insert(url.path); autoActivatedStamps[url.path] = FontFileStamp.read(url) } }
            catch { errors.append(url.lastPathComponent + ": " + error.localizedDescription) }
        }
        if !errors.isEmpty { folderStatus = errors.joined(separator: "\n") }
    }
}
struct WatchedFoldersView: View {
    @ObservedObject var library: Library
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("Watched folders").font(.headline); Spacer(); Button("Add folder…") { library.addFolder() }; Button("Refresh now") { library.reload(register: true) }.disabled(library.loading) }
            Text("Folders and subfolders are checked every three seconds while Typefield is open.").font(.caption).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(library.saved.folders, id: \.self) { path in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack { Label(URL(fileURLWithPath: path).lastPathComponent, systemImage: "folder").font(.headline); Spacer(); Button("Stop watching") { library.stopWatchingFolder(path) }.disabled(library.loading) }
                            Text(path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                            HStack {
                                Button("Show in Finder") { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path) }
                                if library.pausedFolders.contains(path) {
                                    Label("Paused to avoid macOS permission prompts", systemImage: "pause.circle").font(.caption).foregroundStyle(.secondary)
                                    Button("Resume watching…") { library.addFolder(replacing: path) }
                                } else if !library.resolvedFolders.contains(path) {
                                    Label("Access needs attention", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                                    Button("Choose Folder Again…") { library.addFolder(replacing: path) }
                                }
                            }
                            Toggle("Activate fonts for other apps", isOn: Binding(get: { library.saved.autoActivateFolders?.contains(path) == true }, set: { enabled in library.setFolderActivation(path, enabled: enabled) })).toggleStyle(.checkbox).disabled(library.loading)
                        }.padding(14).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
                    }
                    if library.saved.folders.isEmpty { Text("No watched folders").foregroundStyle(.secondary).padding(25) }
                }
            }
            Text("Activation uses the original files. Activated fonts are cleared when Typefield quits normally or you log out. Stopping a watch keeps your font files.").font(.caption).foregroundStyle(.secondary)
            Text(library.folderStatus).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
        }.padding(12)
    }
}

struct TagFilterView: View {
    @ObservedObject var library: Library
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("Tag filters").font(.headline); Spacer(); Button("Clear") { library.tagQuery = TagQuery() } }
            Picker("Combine included tags", selection: $library.tagQuery.matchAll) { Text("All included (AND)").tag(true); Text("Any included (OR)").tag(false) }.pickerStyle(.segmented)
            Text("Excluded tags always take precedence. Parent tags include descendants.").font(.caption).foregroundStyle(.secondary)
            ScrollView {
                ForEach(TagQuery.hierarchy(Set(library.pro.tags.values.flatMap { $0 })), id: \.self) { tag in
                    HStack {
                        Text(tag).lineLimit(1); Spacer()
                        ShelfDropdown(title: tag, selection: Binding(get: { library.tagQuery.excluded.contains(tag) ? -1 : library.tagQuery.included.contains(tag) ? 1 : 0 }, set: { value in library.tagQuery.included.remove(tag); library.tagQuery.excluded.remove(tag); if value == 1 { library.tagQuery.included.insert(tag) }; if value == -1 { library.tagQuery.excluded.insert(tag) } }), options: [("Any", 0), ("Include", 1), ("Exclude", -1)], showsTitle: false).frame(width: 110)
                    }.padding(.vertical, 4)
                }
            }
        }.padding(20).frame(width: 420, height: 400)
    }
}

struct FontSearchQuery {
    struct Token: Identifiable, Equatable { let raw: String; let name: String; let excluded: Bool; var id: String { raw } }
    var text: String
    var tokens: [Token] = []
    init(_ source: String) {
        let regex = try! NSRegularExpression(pattern: #"(?<!\S)#!?(?:"[^"]+"|[^\s"]+)"#)
        let ns = source as NSString
        let matches = regex.matches(in: source, range: NSRange(location: 0, length: ns.length))
        for match in matches {
            let raw = ns.substring(with: match.range), excluded = ns.substring(with: match.range).hasPrefix("#!")
            let name = String(raw.dropFirst(excluded ? 2 : 1)).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            if !tokens.contains(where: { $0.raw == raw }) { tokens.append(Token(raw: raw, name: name, excluded: excluded)) }
        }
        text = regex.stringByReplacingMatches(in: source, range: NSRange(location: 0, length: ns.length), withTemplate: "").trimmingCharacters(in: .whitespacesAndNewlines)
        if text == "#" || text == "#!" { text = "" }
    }
    static func token(_ name: String, excluded: Bool = false) -> String { (excluded ? "#!" : "#") + (name.contains(where: \.isWhitespace) ? "\"" + name.replacingOccurrences(of: "\"", with: "") + "\"" : name) }
    static func removing(_ token: String, from text: String) -> String {
        let expression = try! NSRegularExpression(pattern: "(?<!\\S)" + NSRegularExpression.escapedPattern(for: token) + "(?=\\s|$)")
        return expression.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: (text as NSString).length), withTemplate: "").trimmingCharacters(in: .whitespaces)
    }
    func matches(_ face: Face, tags: Set<String>) -> Bool { tokens.allSatisfy { $0.excluded != Self.match($0.name, face: face, tags: tags) } }
    static func match(_ name: String, face: Face, tags: Set<String>) -> Bool {
        guard let prefix = ["typefield/", "fontshelf/", "typeface/"].first(where: { name.lowercased().hasPrefix($0) }) else {
            return tags.contains { $0.caseInsensitiveCompare(name) == .orderedSame || $0.lowercased().hasPrefix(name.lowercased() + "/") }
        }
        let key = String(name.dropFirst(prefix.count)).lowercased(), facts = face.facts
        switch key {
        case "user": return face.url.map { !$0.path.hasPrefix("/System/") && !$0.path.hasPrefix("/Library/Apple/") } ?? false
        case "active": return face.url.map { let scope = CTFontManagerGetScopeForURL($0 as CFURL); return scope == .session || scope == .persistent || $0.path.hasPrefix("/System/") || $0.path.hasPrefix("/Library/Fonts/") } ?? true
        case "tagged": return !tags.isEmpty
        case "variable": return facts.variable
        case "color": return facts.color
        case "bitmap": return facts.bitmap
        case "monospace": return facts.monospace
        case "italic": return facts.italic
        case "upright": return !facts.italic
        case "light": return facts.weight < 350
        case "regular": return (350...449).contains(facts.weight)
        case "medium": return (450...599).contains(facts.weight)
        case "bold": return (600...799).contains(facts.weight)
        case "black": return facts.weight >= 800
        case "condensed": return facts.widthClass < 5
        case "normal-width": return facts.widthClass == 5
        case "expanded": return facts.widthClass > 5
        case "high-contrast": return facts.panoseIndicatesHighContrast
        case "small-xheight": return facts.xHeightRatio < 0.45
        case "medium-xheight": return (0.45...0.55).contains(facts.xHeightRatio)
        case "large-xheight": return facts.xHeightRatio > 0.55
        default:
            if key.hasPrefix("feature/") { return facts.features.contains(String(key.dropFirst(8))) }
            if key.hasPrefix("script/") { return face.writingSystems.contains { $0.rawValue.lowercased() == String(key.dropFirst(7)) } }
            return false
        }
    }
}
struct SearchTokenChips: View {
    @ObservedObject var library: Library
    var body: some View {
        let tokens = FontSearchQuery(library.search).tokens
        if !tokens.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(tokens) { token in
                        Button {
                            library.search = FontSearchQuery.removing(token.raw, from: library.search)
                        } label: {
                            HStack(spacing: 4) { Text(token.raw); Image(systemName: "xmark") }
                                .font(.caption)
                                .padding(.horizontal, 9)
                                .frame(minHeight: 28)
                                .foregroundStyle(token.excluded ? ShelfPalette.exclusion : ShelfPalette.ink)
                                .background((token.excluded ? ShelfPalette.exclusion : ShelfPalette.ink).opacity(0.09), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .help("Remove search filter \(token.raw)")
                        .accessibilityLabel(token.excluded ? "Remove excluded search filter \(token.raw)" : "Remove search filter \(token.raw)")
                    }
                }
            }.padding(.bottom, 10)
        }
    }
}
struct LibrarySearchView: View {
    @ObservedObject var library: Library
    @State private var suggestions = false
    @State private var exclude = false
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search fonts", text: $library.search).textFieldStyle(.plain).onSubmit { suggestions = false }
                .accessibilityLabel("Search fonts or tags")
            if !library.search.isEmpty { Button { library.search = "" } label: { Image(systemName: "xmark.circle.fill").frame(minWidth: 28, minHeight: 28) }.buttonStyle(.plain).help("Clear search").accessibilityLabel("Clear font search") }
            Button { suggestions.toggle() } label: { Image(systemName: "tag").frame(minWidth: 28, minHeight: 28) }.buttonStyle(.plain).help("Search tags and font properties")
                .accessibilityLabel("Search tags and font properties")
                .accessibilityValue(suggestions ? "Open" : "Closed")
                .popover(isPresented: $suggestions, arrowEdge: .bottom) { panel }
        }.padding(10).background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
        .onChange(of: library.search) { value in if value.hasSuffix("#") || value.hasSuffix("#!") { suggestions = true; exclude = value.hasSuffix("#!") } }
    }
    func add(_ name: String) {
        var text = library.search.trimmingCharacters(in: .whitespaces)
        if library.search.last?.isWhitespace != true, let range = text.range(of: #"(?:^|\s)#!?[^\s]*$"#, options: .regularExpression) { text.removeSubrange(range) }
        let token = FontSearchQuery.token(name, excluded: exclude)
        if !FontSearchQuery(text).tokens.contains(where: { $0.raw == token }) { text += (text.isEmpty ? "" : " ") + token }
        library.search = text + " "; suggestions = false
    }
    func preset(_ label: String, _ key: String) -> some View { Button(label) { add("typefield/" + key) }.buttonStyle(.bordered).foregroundStyle(.primary).help(FontSearchQuery.token("typefield/" + key, excluded: exclude)) }
    var panel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Text("Search filters").font(.headline); Spacer(); Button("Done") { suggestions = false } }
            TextField("Search fonts or #tags", text: $library.search).textFieldStyle(.roundedBorder).onSubmit { suggestions = false }
            Picker("Filter mode", selection: $exclude) { Text("Include #").tag(false); Text("Exclude #!").tag(true) }.pickerStyle(.segmented)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack { preset("User fonts", "user"); preset("Active", "active"); preset("Tagged", "tagged"); preset("Variable", "variable") }
                    Text("Tags").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    let fragment = library.search.split(separator: "#").last.map(String.init)?.trimmingCharacters(in: CharacterSet(charactersIn: "!\" ")) ?? ""
                    let tags = TagQuery.hierarchy(Set(library.pro.tags.values.flatMap { $0 }))
                    ForEach(tags.filter { !library.search.contains("#") || fragment.isEmpty || $0.localizedCaseInsensitiveContains(fragment) }, id: \.self) { tag in
                        Button { add(tag) } label: { Text(FontSearchQuery.token(tag, excluded: exclude)).foregroundStyle(exclude ? ShelfPalette.exclusion : ShelfPalette.ink).padding(.vertical, 4) }.buttonStyle(.plain)
                    }
                    if tags.isEmpty { Text("Add tags from Library → Tools → Tags.").font(.caption).foregroundStyle(.secondary) }
                    Divider()
                    Text("Weight").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    HStack { preset("Light", "light"); preset("Regular", "regular"); preset("Medium", "medium"); preset("Bold", "bold"); preset("Black", "black") }
                    HStack { preset("Condensed", "condensed"); preset("Normal", "normal-width"); preset("Expanded", "expanded"); preset("High contrast", "high-contrast") }
                    HStack { preset("Upright", "upright"); preset("Italic", "italic") }
                    HStack { preset("Monospace", "monospace"); preset("Color", "color"); preset("Bitmap", "bitmap") }
                    Text("x-height").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    HStack { preset("Small h", "small-xheight"); preset("Medium h", "medium-xheight"); preset("Large h", "large-xheight") }
                    Text("OpenType support").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 125))], alignment: .leading) {
                        ForEach(["lnum", "onum", "tnum", "pnum", "liga", "dlig", "smcp", "frac", "sups", "kern"], id: \.self) { tag in preset(OpenType.label(tag), "feature/" + tag) }
                    }
                    Menu("Language / script") { ForEach(WritingSystem.allCases, id: \.self) { script in Button(script.rawValue) { add("typefield/script/" + script.rawValue) } } }
                    Text("Filters combine with AND. #! excludes a tag or property. Parent tags include their children.").font(.caption).foregroundStyle(.secondary)
                }
            }
        }.padding(18).frame(width: 460, height: 590)
    }
}
