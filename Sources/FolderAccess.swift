import Foundation

/// Holds user-granted folder access for the catalog's lifetime, including after relaunch.
final class FolderAccess {
    private let file: URL
    private let managedDirectory: URL
    private var bookmarks: [String: Data] = [:]
    private var active: [String: URL] = [:]
    private var loadFailed = false
    init(directory: URL) {
        managedDirectory = directory.standardizedFileURL
        file = managedDirectory.appendingPathComponent("folder-access.json")
        do {
            try TypefieldInputFile.requireRegularFileIfPresent(file)
            if FileManager.default.fileExists(atPath: file.path) { bookmarks = try JSONDecoder().decode([String: Data].self, from: Data(contentsOf: file)) }
        } catch { loadFailed = true }
    }
    private func persist() throws {
        guard !loadFailed else { throw NSError(domain: "FontShelf", code: 1, userInfo: [NSLocalizedDescriptionKey: "Saved folder access could not be read. The existing file was preserved."]) }
        try TypefieldInputFile.requireRegularFileIfPresent(file)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(bookmarks).write(to: file, options: .atomic)
    }
    func remember(_ url: URL) throws {
        let started = active[url.path] == nil && url.startAccessingSecurityScopedResource()
        if started { active[url.path] = url }
        do {
            let data = try url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess], includingResourceValuesForKeys: nil, relativeTo: nil)
            let previous = bookmarks[url.path]
            bookmarks[url.path] = data
            do { try persist() } catch { bookmarks[url.path] = previous; throw error }
        } catch {
            if started { url.stopAccessingSecurityScopedResource(); active.removeValue(forKey: url.path) }
            throw error
        }
    }
    func restore(_ path: String) throws -> String {
        guard !loadFailed else { throw NSError(domain: "FontShelf", code: 1, userInfo: [NSLocalizedDescriptionKey: "Saved folder permissions are unreadable and were preserved."]) }
        let requested = URL(fileURLWithPath: path).standardizedFileURL
        let managedRoot = managedDirectory.path.hasSuffix("/") ? managedDirectory.path : managedDirectory.path + "/"
        if requested.path == managedDirectory.path || requested.path.hasPrefix(managedRoot) { return requested.path }
        guard let data = bookmarks[path] else {
            throw NSError(domain: "FontShelf", code: 2, userInfo: [NSLocalizedDescriptionKey: "Access is not saved for \(requested.lastPathComponent). Choose that folder again in Live folders."])
        }
        if let url = active[path] { return url.path }
        var stale = false
        let url = try URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
        guard url.startAccessingSecurityScopedResource() else {
            throw NSError(domain: "FontShelf", code: 3, userInfo: [NSLocalizedDescriptionKey: "Saved access is no longer valid for \(requested.lastPathComponent). Choose that folder again in Live folders."])
        }
        active[path] = url
        if stale {
            let previous = bookmarks[path]
            do {
                bookmarks[path] = try url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess], includingResourceValuesForKeys: nil, relativeTo: nil)
                try persist()
            } catch {
                bookmarks[path] = previous
                active.removeValue(forKey: path)
                url.stopAccessingSecurityScopedResource()
                throw error
            }
        }
        return url.path
    }
    deinit { for url in active.values { url.stopAccessingSecurityScopedResource() } }
}
