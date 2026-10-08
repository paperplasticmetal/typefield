import SwiftUI
import AppKit
import CoreText
import UniformTypeIdentifiers
import Darwin
import CryptoKit

/// Read user-selected interchange files without allowing a changed or unusually
/// large file to consume unbounded memory before its format is validated.
enum TypefieldInputFile {
    private static func unsupportedFile() -> NSError {
        NSError(domain: "Typefield.InputFile", code: 1, userInfo: [NSLocalizedDescriptionKey: "Choose a regular file. Symbolic links and special files are not supported."])
    }

    static func requireRegularFileIfPresent(_ url: URL) throws {
        var metadata = stat()
        let result = url.path.withCString { Darwin.lstat($0, &metadata) }
        if result < 0 {
            if errno == ENOENT { return }
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        guard metadata.st_mode & S_IFMT == S_IFREG else { throw unsupportedFile() }
    }

    static func read(_ url: URL, maximumBytes: Int) throws -> Data {
        guard maximumBytes > 0, maximumBytes < Int.max else { throw unsupportedFile() }
        let descriptor = url.path.withCString { Darwin.open($0, O_RDONLY | O_NOFOLLOW) }
        if descriptor < 0 {
            if errno == ELOOP { throw unsupportedFile() }
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        var metadata = stat()
        guard Darwin.fstat(descriptor, &metadata) == 0 else {
            let code = errno
            Darwin.close(descriptor)
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(code))
        }
        guard metadata.st_mode & S_IFMT == S_IFREG else {
            Darwin.close(descriptor)
            throw unsupportedFile()
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var data = Data()
        while true {
            let remaining = maximumBytes + 1 - data.count
            let chunk = try handle.read(upToCount: min(1_048_576, remaining)) ?? Data()
            if chunk.isEmpty { return data }
            data.append(chunk)
            if data.count > maximumBytes { throw CocoaError(.fileReadTooLarge) }
        }
    }
}

struct LibraryBackup: Codable {
    var version = 1
    var library: SavedLibrary
    var pro: ProState
    var spaces: StudioState
    /// Optional so version-1 backups created before Letterform Editor remain decodable.
    var fontLab: FontLabState? = nil
}
enum LibraryBackupTools {
    struct ImportJournal: Codable {
        struct Entry: Codable {
            let name: String
            let oldDigest: String?
            let newDigest: String
        }
        enum Phase: String, Codable { case prepared, committed }
        let version: Int
        let stageName: String
        let entries: [Entry]
        var phase: Phase
    }

    enum RecoveryResult { case none, rolledBack, completed }
    private static let journalName = ".typefield-backup-import-journal.json"
    private static let stagePrefix = ".typefield-backup-import-"
    private static let importFileNames: Set<String> = ["library.json", "pro-library.json", "spaces.json", "font-lab.json"]

    static func journalURL(in folder: URL) -> URL { folder.appendingPathComponent(journalName) }

    private static func syncFile(_ url: URL) throws {
        let descriptor = url.path.withCString { Darwin.open($0, O_RDONLY | O_NOFOLLOW) }
        guard descriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        defer { Darwin.close(descriptor) }
        guard Darwin.fsync(descriptor) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
    }

    private static func syncDirectory(_ url: URL) throws {
        let descriptor = url.path.withCString { Darwin.open($0, O_RDONLY) }
        guard descriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        defer { Darwin.close(descriptor) }
        guard Darwin.fsync(descriptor) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
    }

    private static func digest(_ url: URL) throws -> String {
        try TypefieldInputFile.requireRegularFileIfPresent(url)
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty { hash.update(data: chunk) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func writeJournal(_ journal: ImportJournal, in folder: URL) throws {
        let marker = journalURL(in: folder)
        try JSONEncoder().encode(journal).write(to: marker, options: .atomic)
        try syncFile(marker)
        try syncDirectory(folder)
    }

    /// The journal is the only signal that targets may be between versions.
    /// Unmarked older staging folders are left alone, including any copies
    /// retained after a failed rollback in an older Typefield release.
    static func prepareImport(_ replacements: [(URL, Data)], in folder: URL) throws -> ImportJournal {
        let fm = FileManager.default
        try TypefieldInputFile.requireRegularFileIfPresent(journalURL(in: folder))
        guard !fm.fileExists(atPath: journalURL(in: folder).path) else {
            throw backupError("An earlier backup import still needs recovery. Relaunch Typefield before importing another backup.")
        }
        guard !replacements.isEmpty,
              Set(replacements.map { $0.0.lastPathComponent }).count == replacements.count,
              replacements.allSatisfy({ importFileNames.contains($0.0.lastPathComponent) &&
                  $0.0.deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL }) else {
            throw backupError("Backup import requires known saved files in one data folder.")
        }
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let stageName = stagePrefix + UUID().uuidString
        let stage = folder.appendingPathComponent(stageName)
        try fm.createDirectory(at: stage, withIntermediateDirectories: false)
        var prepared = false
        // An atomic marker write can succeed just before its fsync fails.
        // Keep its staged sources if the marker exists so the next recovery
        // never sees a journal pointing at files we already deleted.
        defer {
            if !prepared && !fm.fileExists(atPath: journalURL(in: folder).path) {
                try? fm.removeItem(at: stage)
            }
        }
        var entries: [ImportJournal.Entry] = []
        for (target, data) in replacements {
            let name = target.lastPathComponent
            let new = stage.appendingPathComponent("new-" + name)
            try data.write(to: new, options: .atomic)
            try syncFile(new)
            var oldDigest: String?
            try TypefieldInputFile.requireRegularFileIfPresent(target)
            if fm.fileExists(atPath: target.path) {
                let old = stage.appendingPathComponent("old-" + name)
                // A real copy stays intact even if a future writer changes an
                // existing inode in place instead of replacing it atomically.
                try fm.copyItem(at: target, to: old)
                try syncFile(old)
                oldDigest = try digest(old)
            }
            entries.append(.init(name: name, oldDigest: oldDigest, newDigest: digest(data)))
        }
        try syncDirectory(stage)
        let journal = ImportJournal(version: 1, stageName: stageName, entries: entries, phase: .prepared)
        try writeJournal(journal, in: folder)
        prepared = true
        return journal
    }

    static func markImportCommitted(_ journal: ImportJournal, in folder: URL) throws {
        var committed = journal
        committed.phase = .committed
        try writeJournal(committed, in: folder)
    }

    private static func finishImportJournal(_ journal: ImportJournal, in folder: URL) throws {
        let fm = FileManager.default
        let marker = journalURL(in: folder)
        // Keep staged copies until removal of the marker itself is durable.
        try fm.removeItem(at: marker)
        try syncDirectory(folder)
        try? fm.removeItem(at: folder.appendingPathComponent(journal.stageName))
    }

    private static func replaceTarget(with source: URL, target: URL) throws {
        let fm = FileManager.default
        let temporary = target.deletingLastPathComponent().appendingPathComponent(".typefield-backup-recovery-" + UUID().uuidString)
        defer { try? fm.removeItem(at: temporary) }
        try fm.copyItem(at: source, to: temporary)
        try syncFile(temporary)
        let result = temporary.path.withCString { from in target.path.withCString { to in Darwin.rename(from, to) } }
        guard result == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        try syncDirectory(target.deletingLastPathComponent())
    }

    /// Reapply every file from an immutable stage, so another interruption
    /// during recovery can safely retry on the next launch.
    @discardableResult static func recoverPendingImport(in folder: URL) throws -> RecoveryResult {
        let marker = journalURL(in: folder)
        try TypefieldInputFile.requireRegularFileIfPresent(marker)
        guard FileManager.default.fileExists(atPath: marker.path) else { return .none }
        let journal = try JSONDecoder().decode(ImportJournal.self, from: TypefieldInputFile.read(marker, maximumBytes: 16_384))
        let prefix = stagePrefix
        guard journal.version == 1, journal.stageName.hasPrefix(prefix),
              UUID(uuidString: String(journal.stageName.dropFirst(prefix.count))) != nil,
              !journal.entries.isEmpty,
              Set(journal.entries.map(\.name)).count == journal.entries.count,
              journal.entries.allSatisfy({ importFileNames.contains($0.name) && (($0.oldDigest == nil) || $0.oldDigest!.count == 64) && $0.newDigest.count == 64 }) else {
            throw backupError("The backup recovery journal is invalid. Saved files were left untouched.")
        }
        let stage = folder.appendingPathComponent(journal.stageName)
        var metadata = stat()
        let stageResult = stage.path.withCString { Darwin.lstat($0, &metadata) }
        guard stageResult == 0, metadata.st_mode & S_IFMT == S_IFDIR else {
            throw backupError("The backup recovery copies are missing. Saved files were left untouched.")
        }
        let committed = journal.phase == .committed
        // Verify all staged sources before changing even one saved file.
        for entry in journal.entries {
            guard let expected = committed ? entry.newDigest : entry.oldDigest else { continue }
            let source = stage.appendingPathComponent((committed ? "new-" : "old-") + entry.name)
            guard try digest(source) == expected else {
                throw backupError("A staged backup recovery copy is damaged. Saved files were left untouched at \(stage.path).")
            }
        }
        for entry in journal.entries {
            let target = folder.appendingPathComponent(entry.name)
            if committed {
                try replaceTarget(with: stage.appendingPathComponent("new-" + entry.name), target: target)
            } else if entry.oldDigest != nil {
                try replaceTarget(with: stage.appendingPathComponent("old-" + entry.name), target: target)
            } else {
                // An absent pre-import file can only become a regular file
                // through this transaction. Never recursively delete a
                // directory or follow a link left at that path.
                var targetMetadata = stat()
                let found = target.path.withCString { Darwin.lstat($0, &targetMetadata) }
                if found == 0 {
                    guard targetMetadata.st_mode & S_IFMT == S_IFREG else {
                        throw backupError("Recovery found a non-file at \(target.path). It was preserved for review.")
                    }
                    let removed = target.path.withCString { Darwin.unlink($0) }
                    guard removed == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
                    try syncDirectory(folder)
                } else if errno != ENOENT {
                    throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
                }
            }
        }
        try syncDirectory(folder)
        try finishImportJournal(journal, in: folder)
        return committed ? .completed : .rolledBack
    }

    private static func backupError(_ message: String) -> NSError {
        NSError(domain: "Typefield.Backup", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    /// Never describe default in-memory state as a backup of a file that failed
    /// to load. The saved source files are intentionally left untouched.
    static func snapshot(_ library: Library) throws -> LibraryBackup {
        guard !library.librarySaveBlocked else { throw backupError("The Library file could not be read. Repair or restore it before exporting a backup.") }
        guard !library.proSaveBlocked else { throw backupError("The advanced Library settings could not be read. Repair or restore them before exporting a backup.") }
        guard !library.studio.readBlocked else { throw backupError("The Spaces file could not be read. Repair or restore it before exporting a backup.") }
        guard !library.fontLab.readBlocked else { throw backupError("The Letterform Editor file could not be read. Repair or restore it before exporting a backup.") }
        let backup = LibraryBackup(library: library.saved, pro: library.pro, spaces: library.studio.state, fontLab: library.fontLab.state)
        guard backup.spaces.version == 1,
              backup.spaces.spaces.allSatisfy({ $0.boards.allSatisfy(\.isValid) }),
              backup.fontLab?.isValid == true else {
            throw backupError("The current projects contain invalid data. The backup was not exported.")
        }
        _ = try JSONEncoder().encode(backup)
        return backup
    }

    static func preserve(_ url: URL) throws {
        try TypefieldInputFile.requireRegularFileIfPresent(url)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let directory = url.deletingLastPathComponent().appendingPathComponent("Backups")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let day = ISO8601DateFormatter().string(from: Date()).prefix(10)
        let target = directory.appendingPathComponent(String(day) + "-" + url.lastPathComponent)
        if !FileManager.default.fileExists(atPath: target.path) { try FileManager.default.copyItem(at: url, to: target) }
    }
    static func export(_ library: Library) {
        do {
            let backup = try snapshot(library)
            let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "Typefield-library.json"
            guard panel.runModal() == .OK, let url = panel.url else { return }
            try JSONEncoder().encode(backup).write(to: url, options: .atomic)
            library.message = "Backup saved to \(url.lastPathComponent): Library, Spaces, and Letterform Editor. Font files are not included."
        } catch { library.message = error.localizedDescription }
    }
    struct MergePreview: Equatable {
        let newCollections: Int
        let existingCollections: Int
        let addedMemberships: Int
        let addedFavorites: Int
        let spaces: Int
        let typeboards: Int
        let editorProjects: Int
        var description: String {
            "Collections: \(newCollections) new; \(existingCollections) existing collections receive memberships (\(addedMemberships) memberships added).\n" +
            "Favorites: \(addedFavorites) added.\n" +
            "Spaces: \(spaces) copies with \(typeboards) typeboards.\n" +
            "Letterform Editor: \(editorProjects) project copies.\n\n" +
            "Existing settings stay in place. Font files and watched-folder access are not included. Typefield keeps recovery copies while merging."
        }
    }
    static func previewMerge(_ backup: LibraryBackup, into library: Library) throws -> MergePreview {
        guard backup.version == 1, backup.spaces.version == 1,
              backup.spaces.spaces.allSatisfy({ $0.boards.allSatisfy(\.isValid) }),
              backup.fontLab?.isValid ?? true,
              !library.librarySaveBlocked, !library.proSaveBlocked, !library.studio.readBlocked,
              backup.fontLab == nil || !library.fontLab.readBlocked else {
            throw backupError("This backup is invalid or current saved data needs recovery before a merge.")
        }
        let newCollections = backup.library.collections.keys.filter { library.saved.collections[$0] == nil }.count
        let existingCollections = backup.library.collections.keys.filter { library.saved.collections[$0] != nil }.count
        let memberships = backup.library.collections.reduce(0) { count, entry in
            count + entry.value.subtracting(library.saved.collections[entry.key] ?? []).count
        }
        return MergePreview(newCollections: newCollections, existingCollections: existingCollections,
                            addedMemberships: memberships,
                            addedFavorites: backup.library.favorites.subtracting(library.saved.favorites).count,
                            spaces: backup.spaces.spaces.count,
                            typeboards: backup.spaces.spaces.reduce(0) { $0 + $1.boards.count },
                            editorProjects: backup.fontLab?.projects.count ?? 0)
    }
    static func merge(_ backup: LibraryBackup, into library: Library,
                      writeFile: (Data, URL) throws -> Void = { data, url in try data.write(to: url, options: .atomic) }) throws {
        let fontLabIsValid = backup.fontLab?.isValid ?? true
        let canImportFontLab = backup.fontLab == nil || !library.fontLab.readBlocked
        guard backup.version == 1, backup.spaces.version == 1, fontLabIsValid, canImportFontLab,
              !library.librarySaveBlocked, !library.proSaveBlocked, !library.studio.readBlocked,
              backup.spaces.spaces.allSatisfy({ $0.boards.allSatisfy(\.isValid) }) else { throw CocoaError(.fileReadCorruptFile) }
        let previousLibrary = library.saved, previousPro = library.pro, previousSpaces = library.studio.state
        var mergedLibrary = previousLibrary, mergedPro = previousPro, mergedSpaces = previousSpaces
        mergedLibrary.favorites.formUnion(backup.library.favorites)
        for (key, values) in backup.library.collections { mergedLibrary.collections[key, default: []].formUnion(values) }
        mergedLibrary.overrides.merge(backup.library.overrides) { existing, _ in existing }
        if let importedUsage = backup.library.fontUsage {
            var usage = mergedLibrary.fontUsage ?? [:]
            for (name, imported) in importedUsage {
                if let existing = usage[name] { usage[name] = FontUsageRecord(lastAppliedAt: max(existing.lastAppliedAt, imported.lastAppliedAt), applicationCount: max(existing.applicationCount, imported.applicationCount)) }
                else { usage[name] = imported }
            }
            mergedLibrary.fontUsage = usage
        }
        mergedPro.familyOverrides.merge(backup.pro.familyOverrides) { existing, _ in existing }
        mergedPro.mainPreviews.merge(backup.pro.mainPreviews) { existing, _ in existing }
        mergedPro.notes.merge(backup.pro.notes) { existing, _ in existing }
        mergedPro.axes.merge(backup.pro.axes) { existing, _ in existing }
        mergedPro.features.merge(backup.pro.features) { existing, _ in existing }
        for (key, tags) in backup.pro.tags { mergedPro.tags[key, default: []].formUnion(tags) }
        for var space in backup.spaces.spaces {
            space.id = UUID(); space.name += " (imported)"
            for index in space.boards.indices {
                space.boards[index].id = UUID()
                space.boards[index].directions = space.boards[index].directions.map { $0.copy(name: $0.name) }
                space.boards[index].selectedDirection = nil
                space.boards[index].checkpoints = space.boards[index].checkpoints?.map { checkpoint in
                    var copy = checkpoint
                    copy.id = UUID()
                    copy.direction = checkpoint.direction.copy(name: checkpoint.direction.name)
                    return copy
                }
            }
            mergedSpaces.spaces.append(space)
        }
        mergedSpaces.selectedSpace = library.studio.focusedSpace
        mergedSpaces.selectedBoard = library.studio.focusedBoard
        guard mergedSpaces.spaces.allSatisfy({ $0.boards.allSatisfy(\.isValid) }) else { throw CocoaError(.fileReadCorruptFile) }

        // A synchronous Letterform Editor save drains older background writes
        // before its state joins this multi-file transaction.
        let importedProjects = backup.fontLab?.projects ?? []
        var mergedFontLab: FontLabState?
        if !importedProjects.isEmpty {
            guard library.fontLab.prepareForBackupImport(),
                  let state = library.fontLab.stateByImportingProjects(importedProjects) else {
                throw backupError(library.fontLab.error.isEmpty ? "Letterform Editor projects could not be imported." : library.fontLab.error)
            }
            mergedFontLab = state
        }

        var replacements: [(URL, Data)] = [
            (library.saveURL, try JSONEncoder().encode(mergedLibrary)),
            (library.proURL, try JSONEncoder().encode(mergedPro)),
            (library.studio.url, try JSONEncoder().encode(mergedSpaces))
        ]
        if let mergedFontLab {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            replacements.append((library.fontLab.url, try encoder.encode(mergedFontLab)))
        }
        let fm = FileManager.default
        let folder = library.saveURL.deletingLastPathComponent()
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        for (target, _) in replacements { try preserve(target) }
        if fm.fileExists(atPath: library.studio.url.path) {
            try Data(contentsOf: library.studio.url).write(to: library.studio.url.appendingPathExtension("backup"), options: .atomic)
        }
        if mergedFontLab != nil, fm.fileExists(atPath: library.fontLab.url.path) {
            try Data(contentsOf: library.fontLab.url).write(to: library.fontLab.url.appendingPathExtension("backup"), options: .atomic)
        }

        func blockAfterRecoveryFailure(_ warning: String) {
            library.backupRecoveryError = warning
            library.librarySaveBlocked = true
            library.proSaveBlocked = true
            library.studio.blockForBackupRecovery(warning)
            library.fontLab.blockForBackupRecovery(warning)
            library.message = warning
        }
        let journal: ImportJournal
        do { journal = try prepareImport(replacements, in: folder) }
        catch {
            // The atomic marker may have been installed before a failed sync.
            // Leave its sources intact and prevent newer edits until startup
            // can reconcile the journal against the on-disk stores.
            if fm.fileExists(atPath: journalURL(in: folder).path) {
                let warning = "Backup import preparation left a recovery journal. Restart Typefield before editing. " + error.localizedDescription
                blockAfterRecoveryFailure(warning)
                throw backupError(warning)
            }
            throw error
        }
        func acceptMergedState() {
            library.saved = mergedLibrary
            library.pro = mergedPro
            library.studio.state = mergedSpaces
            library.studio.savedAt = Date()
            library.studio.error = ""
            if let mergedFontLab {
                library.fontLab.acceptSavedBackupImport(mergedFontLab)
            }
            library.regroup()
        }

        do {
            for (target, data) in replacements {
                try writeFile(data, target)
                try syncFile(target)
                try syncDirectory(folder)
            }
            try markImportCommitted(journal, in: folder)
        } catch {
            let writeError = error
            let recovery: RecoveryResult
            do { recovery = try recoverPendingImport(in: folder) }
            catch {
                let warning = "Backup import stopped and automatic recovery could not finish. Restart Typefield; staged copies remain in \(folder.path). " + error.localizedDescription
                blockAfterRecoveryFailure(warning)
                throw backupError(warning)
            }
            switch recovery {
            case .rolledBack:
                library.saved = previousLibrary
                library.pro = previousPro
                library.studio.state = previousSpaces
                throw backupError("Backup import did not finish. Existing data was restored. " + writeError.localizedDescription)
            case .completed:
                acceptMergedState()
                return
            case .none:
                let warning = "Backup import state could not be verified after a write error. Restart Typefield before editing. " + writeError.localizedDescription
                blockAfterRecoveryFailure(warning)
                throw backupError(warning)
            }
        }
        acceptMergedState()
        do { try finishImportJournal(journal, in: folder) }
        catch {
            let warning = "Backup import data was saved, but recovery cleanup did not finish. Restart Typefield before editing; staged copies remain in \(folder.path). " + error.localizedDescription
            blockAfterRecoveryFailure(warning)
            throw backupError(warning)
        }
    }
    static func restore(_ library: Library) {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.message = "Merge a Typefield backup. Existing settings are kept; spaces and Letterform Editor projects are imported as copies."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let backup = try JSONDecoder().decode(LibraryBackup.self, from: TypefieldInputFile.read(url, maximumBytes: 512_000_000))
            let summary = try previewMerge(backup, into: library)
            let alert = NSAlert()
            alert.messageText = "Merge backup “\(url.lastPathComponent)”?"
            alert.informativeText = summary.description
            alert.addButton(withTitle: "Merge Backup")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            try merge(backup, into: library)
            library.message = "Backup merged: \(summary.newCollections) new collections, \(summary.spaces) Spaces copies, \(summary.editorProjects) Letterform Editor project copies. Regrant external font folders if needed."
        } catch { library.message = "Backup could not be imported: " + error.localizedDescription }
    }
}

/// Moves a pre-sandbox FontShelf support folder into a fresh Store container.
/// The source is chosen in an open panel; saved security scopes cannot be
/// transferred between app identities and must be granted again by the user.
enum StoreMigration {
    static let dataFiles = ["library.json", "pro-library.json", "spaces.json", "font-lab.json"]
    static let stringPreferences = ["appearance", "previewText", "previewInkHex", "previewPaperHex", "typefield.palette", "typefield.iconPalette", "typefield.iconAppearance"]
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
            let data = try TypefieldInputFile.read(file, maximumBytes: 512_000_000)
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
        panel.message = "To set up Typefield with earlier data, quit FontShelf and choose its FontShelf folder in Library/Application Support. The files will be copied into this empty Store container."
        guard panel.runModal() == .OK, let source = panel.url else { return }
        let alert = NSAlert()
        alert.messageText = "Copy earlier data into Typefield?"
        alert.informativeText = "FontShelf Library, Spaces, Letterform Editor and downloaded Google fonts will be copied. The originals stay in place. External font and WOFF2 folders need access granted again. Files outside this folder are not moved."
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
              let values = try PropertyListSerialization.propertyList(from: TypefieldInputFile.read(file, maximumBytes: 4_000_000), format: nil) as? [String: Any] else {
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
        panel.message = "To import earlier preferences into Typefield, choose local.fontshelf.app.plist in Library/Preferences. Existing Store preferences are kept."
        guard panel.runModal() == .OK, let file = panel.url else { return }
        do { library.message = "Imported \(try importPreferences(from: file)) earlier preferences. Reopen Typefield to see them everywhere." }
        catch { library.message = "Preferences were not imported: " + error.localizedDescription }
    }
}
struct MetadataTable: View {
    @ObservedObject var library: Library
    var body: some View {
        Table(library.filteredFaces) {
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
                let title = NSAttributedString(string: face.originalFamily + ", " + face.style, attributes: [.font: NSFont.systemFont(ofSize: 14, weight: .semibold), .foregroundColor: NSColor.black])
                context.textPosition = CGPoint(x: 44, y: 746); CTLineDraw(CTLineCreateWithAttributedString(title), context)
                let footer = NSAttributedString(string: "Typefield: " + face.name, attributes: [.font: NSFont.systemFont(ofSize: 9), .foregroundColor: NSColor.darkGray])
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
        do { try data(faces: faces, library: library, sample: sample).write(to: url, options: .atomic); library.resultNotice = "Specimen PDF saved to \(url.lastPathComponent) for \(faces.count) font styles." }
        catch { library.message = "Specimen PDF could not be exported: " + error.localizedDescription }
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
            let elements: [[String: Any]] = plan.elements.filter { $0.image == nil }.map { item in
                var object: [String: Any] = ["flipX": item.flipX, "flipY": item.flipY, "x": item.rect.minX, "y": item.rect.minY, "width": item.rect.width, "height": item.rect.height, "section": plan.sections.first { $0.id == item.sectionID }?.title ?? "Section"]
                if let text = item.text, let style = item.style {
                    let font = style.font
                    var axes: [String: Double] = [:]
                    for (key, value) in style.axes { axes[String(bytes: [UInt8((key >> 24) & 255), UInt8((key >> 16) & 255), UInt8((key >> 8) & 255), UInt8(key & 255)], encoding: .ascii) ?? ""] = value }
                    object.merge(["kind": "text", "text": text.string, "role": item.role?.rawValue ?? "Text", "fontFamily": CTFontCopyFamilyName(font) as String, "fontStyle": CTFontCopyName(font, kCTFontStyleNameKey) as String? ?? "Regular", "fontName": style.fontName, "fontSize": style.size, "lineHeight": style.lineHeight ?? style.size * style.leading, "letterSpacing": style.tracking, "paragraphSpacing": style.paragraphSpacing ?? 0, "paragraphIndent": style.indent ?? 0, "wordSpacing": style.wordSpacing ?? 0, "alignment": (style.alignment ?? .left).rawValue.uppercased(), "underline": style.underline ?? false, "strikethrough": style.strikethrough ?? false, "kerning": style.effectiveKerning, "features": style.featuresWithoutKerning, "axes": axes, "color": color((text.length > 0 ? text.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor : nil) ?? NSColor(hex: direction.ink))]) { _, new in new }
                } else {
                    object["kind"] = "rectangle"; object["color"] = color(item.color ?? .clear); object["radius"] = item.radius
                    if let stroke = item.strokeColor, item.strokeWidth > 0 {
                        object["stroke"] = color(stroke)
                        object["strokeWidth"] = item.strokeWidth
                    }
                }
                return object
            }
            return ["name": direction.name, "width": plan.size.width, "height": plan.size.height, "paper": color(plan.paper), "elements": elements]
        }
        var payload: [String: Any] = ["format": "fontshelf-figma", "version": 1, "name": board.name, "frames": frames]
        if board.directions.contains(where: { !($0.artworkLayers ?? []).isEmpty }) {
            payload["warnings"] = ["Spaces image artwork is omitted from editable Figma export. Use Preview PDF for a visual handoff."]
        }
        return payload
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
        guard data.count <= 20_000_000, let root = try JSONSerialization.jsonObject(with: data) as? [String: Any], root["format"] as? String == "fontshelf-figma", root["version"] as? Int == 1,
              let title = root["name"] as? String, title.utf16.count <= 256,
              let frames = root["frames"] as? [[String: Any]], !frames.isEmpty, frames.count <= 30 else { throw invalid("Choose a Typefield layout JSON exported by the Figma bridge. Native .fig files are not supported.") }
        if let rawWarnings = root["warnings"], !(rawWarnings is [String]) { throw invalid("The Figma warnings are invalid.") }
        func number(_ object: [String: Any], _ key: String, fallback: Double? = nil) throws -> Double {
            guard let n = object[key] as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite else { if let fallback, object[key] == nil { return fallback }; throw invalid("Invalid numeric value: " + key) }; return n.doubleValue
        }
        func color(_ value: Any?) throws -> (String, Double) {
            guard let c = value as? [String: Any] else { throw invalid("A layer is missing its color.") }
            let r = try number(c, "r"), g = try number(c, "g"), b = try number(c, "b"), a = try number(c, "a", fallback: 1)
            guard [r, g, b, a].allSatisfy({ (0...1).contains($0) }) else { throw invalid("A layer has an invalid color.") }
            return (NSColor(srgbRed: r, green: g, blue: b, alpha: a).rgbHex, a)
        }
        struct FontKey: Hashable { let family: String; let style: String }
        // Many layers repeat the same font. Cache both matches and misses for
        // this import only, retaining the catalog's first-match behavior.
        var resolvedFonts: [FontKey: Int] = [:]
        var directions: [TypeDirection] = []
        var totalLayers = 0
        var totalTextBytes = 0
        for frame in frames {
            guard let frameName = frame["name"] as? String, frameName.utf16.count <= 256 else { throw invalid("A frame has an invalid name.") }
            let width = try number(frame, "width"), height = try number(frame, "height")
            guard let elements = frame["elements"] as? [[String: Any]], elements.count <= 5000 else { throw invalid("The frame contains too many layers.") }
            totalLayers += elements.count
            guard totalLayers <= 50_000 else { throw invalid("The layout contains too many layers.") }
            var warnings = Array((root["warnings"] as? [String] ?? []).prefix(500)).map { String($0.prefix(512)) }
            var layers: [ImportedLayer] = []
            for e in elements {
                guard let section = e["section"] as? String, section.utf16.count <= 256,
                      (e["name"] == nil || (e["name"] as? String).map { $0.utf16.count <= 256 } == true),
                      (e["role"] == nil || (e["role"] as? String).map { $0.utf16.count <= 256 } == true) else { throw invalid("A layer has an invalid name.") }
                let (hex, opacity) = try color(e["color"])
                var layer = ImportedLayer(name: e["name"] as? String ?? section, x: try number(e, "x"), y: try number(e, "y"), width: try number(e, "width"), height: try number(e, "height"), color: hex, opacity: opacity, radius: try number(e, "radius", fallback: 0))
                if e["kind"] as? String == "text" {
                    guard e["stroke"] == nil && e["strokeWidth"] == nil else { throw invalid("Text strokes are not supported.") }
                    guard let text = e["text"] as? String, let family = e["fontFamily"] as? String, let fontStyle = e["fontStyle"] as? String else { throw invalid("A text layer is incomplete.") }
                    guard TypeDirection.acceptsCanvasText(text), family.count <= 256, fontStyle.count <= 256 else { throw invalid("A text layer is too large.") }
                    totalTextBytes += text.utf8.count
                    guard totalTextBytes <= 5_000_000 else { throw invalid("The layout contains too much text.") }
                    let key = FontKey(family: family, style: fontStyle)
                    let index: Int
                    if let cached = resolvedFonts[key] { index = cached }
                    else {
                        index = fonts.firstIndex { $0.originalFamily.caseInsensitiveCompare(family) == .orderedSame && $0.style.caseInsensitiveCompare(fontStyle) == .orderedSame } ?? -1
                        resolvedFonts[key] = index
                    }
                    let face = index >= 0 ? fonts[index] : nil
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
                } else if e["kind"] as? String == "rectangle" {
                    if e["stroke"] != nil || e["strokeWidth"] != nil {
                        guard e["stroke"] != nil && e["strokeWidth"] != nil else { throw invalid("A shape has an incomplete stroke.") }
                        let (strokeHex, strokeOpacity) = try color(e["stroke"])
                        layer.strokeColor = strokeHex
                        layer.strokeOpacity = strokeOpacity
                        layer.strokeWidth = try number(e, "strokeWidth")
                    }
                } else { throw invalid("Unsupported layer kind. Export it again with the Typefield bridge.") }
                guard ["flipX", "flipY"].allSatisfy({ e[$0] == nil || e[$0] is Bool }) else { throw invalid("Invalid reflection.") }
                layer.flipX = e["flipX"] as? Bool; layer.flipY = e["flipY"] as? Bool
                layers.append(layer)
            }
            let layout = ImportedLayout(width: width, height: height, layers: layers)
            guard layout.isValid else { throw invalid("The layout has invalid bounds or typography.") }
            var direction = TypeDirection(name: frameName)
            direction.canvas = .imported; direction.width = width; direction.paper = try color(frame["paper"]).0; direction.importedLayout = layout; direction.importedSource = .figma
            direction.importWarnings = Array(Set(warnings)).sorted(); directions.append(direction)
        }
        return TypeBoard(name: title, directions: directions, selectedDirection: directions.first?.id)
    }
}
