import Foundation
import Security

/// Holds user-granted folder access for the catalog's lifetime, including after relaunch.
final class FolderAccess {
    private static let processIsSandboxed: Bool = {
        guard let task = SecTaskCreateFromSelf(nil) else { return true }
        return SecTaskCopyValueForEntitlement(task, "com.apple.security.app-sandbox" as CFString, nil) as? Bool == true
    }()
    private let file: URL
    private let managedDirectory: URL
    private let sandboxed: Bool
    private var bookmarks: [String: Data] = [:]
    private var active: [String: URL] = [:]
    private var loadFailed = false
    init(directory: URL, sandboxed: Bool? = nil) {
        managedDirectory = directory.standardizedFileURL
        file = managedDirectory.appendingPathComponent("folder-access.json")
        self.sandboxed = sandboxed ?? Self.processIsSandboxed
        do {
            try TypefieldInputFile.requireRegularFileIfPresent(file)
            if FileManager.default.fileExists(atPath: file.path) { bookmarks = try JSONDecoder().decode([String: Data].self, from: Data(contentsOf: file)) }
        } catch { loadFailed = true }
    }
    private var bookmarkOptions: URL.BookmarkCreationOptions {
        sandboxed ? [.withSecurityScope, .securityScopeAllowOnlyReadAccess] : []
    }
    private func issue(_ code: Int, _ description: String) -> NSError {
        NSError(domain: "FontShelf", code: code, userInfo: [NSLocalizedDescriptionKey: description])
    }
    private func isUnavailable(_ url: URL) -> Bool {
        do { return try FileManager.default.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType != .typeDirectory }
        catch {
            let error = error as NSError
            return (error.domain == CocoaError.errorDomain && [CocoaError.fileReadNoSuchFile.rawValue, CocoaError.fileNoSuchFile.rawValue].contains(error.code)) ||
                (error.domain == NSPOSIXErrorDomain && [Int(ENOENT), Int(ENOTDIR)].contains(error.code))
        }
    }
    private func unavailableError(_ url: URL) -> NSError {
        issue(4, "The watched folder \(url.lastPathComponent) is unavailable at its saved location. Reconnect its volume or choose its new location in Live folders.")
    }
    private func renewalError(_ url: URL) -> NSError {
        issue(3, "Saved access is no longer valid for \(url.lastPathComponent). Choose that folder again in Live folders.")
    }
    private func readableLocalFolder(_ url: URL) throws -> String {
        do { _ = try FileManager.default.contentsOfDirectory(atPath: url.path); return url.path }
        catch { throw isUnavailable(url) ? unavailableError(url) : renewalError(url) }
    }
    private func persist() throws {
        guard !loadFailed else { throw NSError(domain: "FontShelf", code: 1, userInfo: [NSLocalizedDescriptionKey: "Saved folder access could not be read. The existing file was preserved."]) }
        try TypefieldInputFile.requireRegularFileIfPresent(file)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(bookmarks).write(to: file, options: .atomic)
    }
    func remember(_ url: URL) throws {
        let started = sandboxed && url.startAccessingSecurityScopedResource()
        do {
            let data = try url.bookmarkData(options: bookmarkOptions, includingResourceValuesForKeys: nil, relativeTo: nil)
            let previous = bookmarks[url.path]
            bookmarks[url.path] = data
            do { try persist() } catch { bookmarks[url.path] = previous; throw error }
            if let former = active.removeValue(forKey: url.path) { former.stopAccessingSecurityScopedResource() }
            if started { active[url.path] = url }
        } catch {
            if started { url.stopAccessingSecurityScopedResource() }
            throw error
        }
    }
    func restore(_ path: String) throws -> String {
        guard !loadFailed else { throw NSError(domain: "FontShelf", code: 1, userInfo: [NSLocalizedDescriptionKey: "Saved folder permissions are unreadable and were preserved."]) }
        let requested = URL(fileURLWithPath: path).standardizedFileURL
        let managedRoot = managedDirectory.path.hasSuffix("/") ? managedDirectory.path : managedDirectory.path + "/"
        if requested.path == managedDirectory.path || requested.path.hasPrefix(managedRoot) { return path }
        if !sandboxed {
            if let data = bookmarks[path] {
                var stale = false
                if let url = try? URL(resolvingBookmarkData: data, options: [.withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale),
                   let resolved = try? readableLocalFolder(url) {
                    if stale, let renewed = try? url.bookmarkData(options: bookmarkOptions, includingResourceValuesForKeys: nil, relativeTo: nil) {
                        let previous = bookmarks[path]
                        bookmarks[path] = renewed
                        if (try? persist()) == nil { bookmarks[path] = previous }
                    }
                    // URL.standardizedFileURL also normalizes aliases such as
                    // /private/tmp to /tmp. Keep the exact saved spelling when
                    // it still identifies the same folder: the watched-folder
                    // UI compares saved and resolved paths by string value.
                    if url.resolvingSymlinksInPath().standardizedFileURL.path == requested.resolvingSymlinksInPath().standardizedFileURL.path {
                        return path
                    }
                    return resolved
                }
            }
            _ = try readableLocalFolder(requested)
            return path
        }
        guard let data = bookmarks[path] else {
            if isUnavailable(requested) { throw unavailableError(requested) }
            throw issue(2, "Access is not saved for \(requested.lastPathComponent). Choose that folder again in Live folders.")
        }
        if let url = active[path] {
            if isUnavailable(url) { throw unavailableError(url) }
            return url.resolvingSymlinksInPath().standardizedFileURL.path == requested.resolvingSymlinksInPath().standardizedFileURL.path ? path : url.path
        }
        var stale = false
        let url: URL
        do { url = try URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale) }
        catch { throw isUnavailable(requested) ? unavailableError(requested) : renewalError(requested) }
        if isUnavailable(url) { throw unavailableError(url) }
        guard url.startAccessingSecurityScopedResource() else { throw renewalError(requested) }
        active[path] = url
        if stale {
            let previous = bookmarks[path]
            do {
                bookmarks[path] = try url.bookmarkData(options: bookmarkOptions, includingResourceValuesForKeys: nil, relativeTo: nil)
                try persist()
            } catch {
                bookmarks[path] = previous
                // Keep the valid scope for this session and retry the bookmark refresh later.
            }
        }
        return url.resolvingSymlinksInPath().standardizedFileURL.path == requested.resolvingSymlinksInPath().standardizedFileURL.path ? path : url.path
    }
    deinit { for url in active.values { url.stopAccessingSecurityScopedResource() } }
}
