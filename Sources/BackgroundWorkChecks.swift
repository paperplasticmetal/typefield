import Foundation

/// Disposable files only: no installed fonts, registrations or saved library data.
enum BackgroundWorkChecks {
    static func run() throws {
        func require(_ condition: Bool, _ message: String) throws {
            if !condition { throw NSError(domain: "Typefield.BackgroundWorkChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        func wait(_ predicate: () -> Bool) -> Bool {
            let deadline = Date().addingTimeInterval(5)
            while !predicate() && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
            return predicate()
        }
        try require(Thread.isMainThread, "Background delivery checks must start on the main thread")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Typefield-background-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        // Known words, overflow, partial words and every possible alignment of
        // a nonzero-index Data slice exercise the optimized SFNT checksum.
        func referenceChecksum(_ data: Data) -> UInt32 {
            var result: UInt32 = 0, word: UInt32 = 0
            for (index, byte) in data.enumerated() {
                word |= UInt32(byte) << (24 - (index % 4) * 8)
                if index % 4 == 3 { result = result &+ word; word = 0 }
            }
            return result &+ word
        }
        let bytes = Data((0..<517).map { UInt8(truncatingIfNeeded: $0 * 73 + 19) })
        for offset in 0..<8 {
            for count in 0..<256 {
                let slice = bytes[offset..<(offset + count)]
                try require(FontRepairEngine.checksum(slice) == referenceChecksum(slice), "SFNT checksum changed for slice offset \(offset), length \(count)")
            }
        }
        try require(FontRepairEngine.checksum(Data([1, 2, 3, 4, 5])) == 0x06020304, "SFNT checksum must pad its final word with zeroes")
        try require(FontRepairEngine.checksum(Data(repeating: 255, count: 8)) == 0xFFFFFFFE, "SFNT checksum must wrap on overflow")

        let font = root.appendingPathComponent("fixture.ttf")
        try Data([0, 1, 2, 3]).write(to: font)
        for index in 0..<100 { try Data([0]).write(to: root.appendingPathComponent("entry-\(index).ttf")) }
        let full = FontFolderSnapshot.read([root.path])
        try require(full.files.count == 101 && full.errors.isEmpty, "Recursive snapshot fixture was not read")
        var visits = 0
        let partial = FontFolderSnapshot.read([root.path], isCancelled: { visits += 1; return visits > 10 })
        try require(partial.files.count < full.files.count && visits <= 11, "Cancellation must stop an in-progress folder walk")
        let missing = root.appendingPathComponent("missing").path
        let cancelled = FontFolderSnapshot.read([missing], pauseOnError: [missing], isCancelled: { true })
        try require(cancelled.errors.isEmpty && cancelled.failedProtectedRoots.isEmpty, "A cancelled snapshot must not probe a protected root")

        let queue = DispatchQueue(label: "Typefield.folder-watch-checks")
        let watcher = FolderWatcher(queue: queue, pollInterval: 0.025)
        var obsoleteInitializations = 0, initializations = 0, changes = 0, watcherErrors: [String] = []
        watcher.configure(roots: [], initialized: { _, _ in obsoleteInitializations += 1 }, changed: { _, _ in })
        queue.sync {} // Its empty-root callback is queued, while the main queue is held here.
        watcher.configure(roots: [root.path], initialized: { errors, _ in initializations += 1; watcherErrors += errors },
                          changed: { errors, _ in changes += 1; watcherErrors += errors })
        try require(wait { initializations == 1 }, "Replacement watch did not initialize")
        try require(obsoleteInitializations == 0 && changes == 0, "A superseded watch delivered its queued callback or triggered an initial reload")
        let nested = root.appendingPathComponent("new/nested")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let nestedFont = nested.appendingPathComponent("new.otf")
        try Data([1]).write(to: nestedFont)
        try require(wait { changes >= 1 }, "Watcher missed a new nested folder/font")
        let previous = changes
        try Data([2, 3]).write(to: nestedFont, options: .atomic)
        try require(wait { changes > previous }, "Watcher missed atomic replacement")
        let beforeRemoval = changes
        try FileManager.default.removeItem(at: nested.deletingLastPathComponent())
        try require(wait { changes > beforeRemoval }, "Watcher missed nested folder removal")
        try require(watcherErrors.isEmpty, "Disposable watch unexpectedly reported an access error")
        watcher.configure(roots: [], changed: { _, _ in })
        queue.sync {}

        var protectedFailed = false, resumed = false, resumedChanges = 0
        watcher.configure(roots: [missing], pauseOnError: [missing], initialized: { _, failures in protectedFailed = failures == [missing] }, changed: { _, _ in })
        try require(wait { protectedFailed }, "An unavailable protected watch was not paused")
        try FileManager.default.createDirectory(atPath: missing, withIntermediateDirectories: true)
        // Queue both configurations together, so the removal can be superseded
        // before its worker runs. An explicit resume must still clear suppression.
        queue.suspend()
        watcher.configure(roots: [], changed: { _, _ in })
        watcher.configure(roots: [missing], pauseOnError: [missing], initialized: { _, _ in resumed = true }, changed: { _, _ in resumedChanges += 1 })
        queue.resume()
        try require(wait { resumed }, "A protected watch did not resume after removal and re-addition")
        try Data([1]).write(to: URL(fileURLWithPath: missing).appendingPathComponent("resumed.ttf"))
        try require(wait { resumedChanges > 0 }, "A quickly resumed root remained suppressed")
        watcher.configure(roots: [], changed: { _, _ in })
        queue.sync {}

        var releasedDelivery = false
        var released: FolderWatcher? = FolderWatcher(queue: queue)
        released?.configure(roots: [], initialized: { _, _ in releasedDelivery = true }, changed: { _, _ in })
        queue.sync {}
        released = nil

        let cancellation = BackgroundWorkCancellation()
        var inspected = 0
        let stopped = FontHealthWork.inspect([font, font, font], cancellation: cancellation) { url in
            inspected += 1; cancellation.cancel()
            return FontRepairEngine.inspect(url)
        }
        try require(stopped == nil && inspected == 1, "Cancelled font inspection must stop before the next file and discard partial results")
        try require(FontHealthWork.libraryURLs([font], watched: [root.path], userFontsOnly: true, cancellation: cancellation) == nil,
                    "Cancelled font discovery must stop before file-system work")
        let selection = FontHealthWork.libraryURLs([font, font], watched: [root.path], userFontsOnly: true, cancellation: BackgroundWorkCancellation())
        try require(selection == [font.standardizedFileURL], "Background discovery changed duplicate-path handling or watched-folder eligibility")

        let obsolete = BackgroundWorkCancellation()
        var obsoleteDelivery = false, discoveryOnMain = true, delivered = false
        FontHealthWork.schedule(cancellation: obsolete, urls: { obsolete.cancel(); return [font] }, completion: { _ in obsoleteDelivery = true })
        FontHealthWork.schedule(cancellation: BackgroundWorkCancellation(), urls: { discoveryOnMain = Thread.isMainThread; return [font] }) { values in
            delivered = Thread.isMainThread && values.count == 1 && values[0].url == font
        }
        try require(wait { delivered }, "Font inspection did not return its result on the main queue")
        try require(!discoveryOnMain, "Font inspection discovery ran on the main thread")
        try require(!obsoleteDelivery && !releasedDelivery, "Cancelled or released background work delivered stale state")
        print("PASS: cancellable folder snapshots, stale watcher delivery, recursive updates, background font-health scans and 2,050 SFNT checksum fixtures.")
    }
}
