import AppKit

enum FontLabPersistenceEncodingChecks {
    private static func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw FontLabStore.SelfTestError.failed(message) }
    }
    private static func reference(_ state: FontLabState) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(state)
    }
    private static func matching(_ cache: FontLabPersistenceEncoder, _ state: FontLabState,
                                 _ revisions: [UUID: UUID]) throws {
        let actual = try cache.encode(state, revisions: revisions)
        let expected = try reference(state)
        try check(actual == expected, "Cached Letterform JSON must exactly match the sorted Codable bytes")
    }
    private static func saved(_ store: FontLabStore) throws {
        let actual = try Data(contentsOf: store.url), expected = try reference(store.state)
        try check(actual == expected && FontLabStore(url: store.url).state == store.state,
                  "Saved Letterform revisions must match the current state byte for byte and reopen exactly")
    }

    private static func project(_ name: String = "Café \"\\ / 雨\n\u{2028}") -> FontLabProject {
        var project = FontLabProject(name: name, characters: ["A", "é", "O"])
        let path = FontLabVectorPath(nodes: [
            .init(point: .init(x: 0.1, y: 0.2), outgoing: .init(x: 0.3, y: -0.0)),
            .init(point: .init(x: 0.8, y: 0.3), incoming: .init(x: 0.7, y: 0.1), smooth: true),
            .init(point: .init(x: 0.5, y: 0.9))
        ], closed: true)
        project.glyphs["A"] = FontLabGlyph(character: "A", strokes: [
            .init(points: [.init(x: 0.1, y: 0.2, pressure: 0.75, tiltX: -0.2, tiltY: 0.1)], nibStyle: .marker),
            .init(vectorPaths: [path])
        ], importedFrom: "Ink \"\\ / 雨.png", importFormat: .png, starterOrigin: "origin e\u{301}", contourDesignWidth: 0.62)
        project.glyphs["é"]?.components = [.init(source: "A", x: 0.02, y: 0)]
        project.kerningGroups = [.init(name: "group \"\\ é", members: ["A"], side: .left)]
        project.kerningPairs = [.init(left: "A", right: "O", value: -20)]
        project.previewText = "A/é\tO \"quoted\" \\ \u{0001}"
        project.previewInkHex = "123ABC"
        project.remixProvenance = .init(sourcePostScriptNames: ["Source-é", "Source-e\u{301}"], blendAmount: 0.5,
            mode: .blend, preset: .clean, generatorName: "generator / \\", distributionNotice: "Notice \"é\"\n",
            preservedCharacters: ["é"], sourceBCharacters: ["A"])
        project.addMaster(name: "Bold é", weight: 700)
        return project
    }

    static func run() throws {
        try check(Thread.isMainThread, "Persistence store checks must run on the main thread")
        try encoderParityAndBounds()
        try storeTransactions()
        print("PASS: Letterform cached JSON bytes, UTF-8, bounds, revisions, rollback, backups and latest-save ordering")
    }

    private static func encoderParityAndBounds() throws {
        let first = project(), second = project("Other")
        try check(first.isValid && second.isValid, "Persistence fixtures must contain valid editable projects")
        var state = FontLabState(projects: [first, second], selectedProject: first.id)
        var revisions = [first.id: UUID(), second.id: UUID()]
        let cache = FontLabPersistenceEncoder()
        try matching(cache, state, revisions)
        try check(cache.lastEncodedProjectCount == 2, "A cold persistence cache must encode every project")
        try matching(cache, state, revisions)
        try check(cache.lastEncodedProjectCount == 0, "Unchanged projects must reuse their encoded fragments")
        state.projects.reverse(); state.selectedProject = second.id
        try matching(cache, state, revisions)
        state.deletedProjects = [state.projects.removeLast()]
        try matching(cache, state, revisions)
        try check(cache.lastEncodedProjectCount == 0, "Reordering, selecting or deleting projects must preserve cached artwork bytes")
        state.projects.append(state.deletedProjects!.removeFirst()); state.selectedProject = nil
        try matching(cache, state, revisions)
        state.deletedProjects = nil
        try matching(cache, state, revisions)

        let previous = state.projects[0].name
        state.projects[0].name = "é"
        revisions[state.projects[0].id] = UUID()
        try matching(cache, state, revisions)
        state.projects[0].name = "e\u{301}"
        try check(state.projects[0].name == "é", "UTF-8 fixture must exercise canonical String equality")
        revisions[state.projects[0].id] = UUID()
        try matching(cache, state, revisions)
        state.projects[0].name = previous
        state.projects[0].glyphs["A"]!.strokes[1].vectorPaths![0].nodes[0].outgoing!.y = 0.0
        revisions[state.projects[0].id] = UUID()
        try matching(cache, state, revisions)
        try check(cache.lastEncodedProjectCount == 1, "A changed project revision must not invalidate unrelated projects")

        let count = cache.entryCount, bytes = cache.retainedByteCount
        var invalid = state
        invalid.projects[0].name = "Not cached after failure"
        invalid.projects[1].metrics.baseline = .nan
        let badRevisions = Dictionary(uniqueKeysWithValues: invalid.projects.map { ($0.id, UUID()) })
        do {
            _ = try cache.encode(invalid, revisions: badRevisions)
            throw FontLabStore.SelfTestError.failed("Non-finite JSON must fail instead of publishing partial cache entries")
        } catch is EncodingError { }
        try check(cache.entryCount == count && cache.retainedByteCount == bytes,
                  "An encoding failure must not publish partially encoded cache entries")
        try matching(cache, state, revisions)
        try check(cache.lastEncodedProjectCount == 0, "Failed encoding must preserve the previous successful fragments")

        let bounded = FontLabPersistenceEncoder(maximumBytes: 100_000, maximumEntries: 1)
        try matching(bounded, state, revisions)
        try matching(bounded, state, revisions)
        try check(bounded.entryCount == 1 && bounded.retainedByteCount <= 100_000,
                  "Project fragments must obey the configured entry and byte limits")
        let projectEncoder = JSONEncoder(); projectEncoder.outputFormatting = [.sortedKeys]
        let sizes = try state.projects.map { try projectEncoder.encode($0).count }
        let byteLimit = sizes.max()! + sizes.min()! / 2
        let byteBounded = FontLabPersistenceEncoder(maximumBytes: byteLimit, maximumEntries: 128)
        try matching(byteBounded, state, revisions)
        try matching(byteBounded, state, revisions)
        try check(byteBounded.entryCount == 1 && byteBounded.retainedByteCount <= byteLimit,
                  "The aggregate byte limit must evict fragments even when each project fits individually")
        let tooSmall = FontLabPersistenceEncoder(maximumBytes: 1, maximumEntries: 128)
        try matching(tooSmall, state, revisions)
        try matching(tooSmall, state, revisions)
        try check(tooSmall.entryCount == 0 && tooSmall.retainedByteCount == 0 && tooSmall.lastEncodedProjectCount == 2,
                  "Oversized project fragments must encode correctly without being retained")
        let missingRevisions = FontLabPersistenceEncoder()
        try matching(missingRevisions, state, [:])
        try check(missingRevisions.entryCount == 0, "A project without a revision must never become a reusable cache entry")
        var duplicate = state; duplicate.projects[1].id = duplicate.projects[0].id
        try matching(cache, duplicate, revisions)
        try matching(cache, FontLabState(), [:])
        try check(cache.entryCount == 0 && cache.retainedByteCount == 0, "Removed projects must release their cached bytes")
    }

    private static func storeTransactions() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Typefield-EncodingChecks-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("font-lab.json")
        let first = project(), second = project("Unrelated")
        let initial = FontLabState(projects: [first, second], selectedProject: first.id, deletedProjects: [project("Deleted")])
        let original = try reference(initial)
        try original.write(to: file)
        let store = FontLabStore(url: file)
        try check(store.save(), "Initial Letterform cache population must succeed")
        try saved(store)
        store.renameProject(first.id, to: "é")
        let beforeChange = try Data(contentsOf: file)
        store.renameProject(first.id, to: "e\u{301}")
        try saved(store)
        let rotating = try Data(contentsOf: file.appendingPathExtension("backup"))
        try check(rotating == beforeChange, "Cached saves must retain the exact previous-file backup")
        let daily = try FileManager.default.contentsOfDirectory(at: folder.appendingPathComponent("Backups"), includingPropertiesForKeys: nil)
        try check(daily.count == 1, "Saving must still create one daily Letterform backup")
        let dailyBytes = try Data(contentsOf: daily[0])
        try check(dailyBytes == original, "Cached saves must preserve the day's original project bytes")

        let beforeGlyph = store.selectedProject!.glyphs["A"]!
        var edited = beforeGlyph
        edited.strokes[1].vectorPaths![0].nodes[0].point.x = 0.15
        store.setGlyph(edited, in: first.id, save: true); try saved(store)
        store.setGlyph(beforeGlyph, in: first.id, save: true); try saved(store)
        store.setGlyph(edited, in: first.id, save: true); try saved(store)
        store.updateProject(first.id) { $0.captureActiveMaster(); $0.previewInkHex = "00AABB" }
        try saved(store)
        let artworkBefore = store.selectedProject!
        var artworkAfter = artworkBefore; artworkAfter.previewText = "Artwork replacement"
        try check(store.replaceArtworkProject(artworkBefore, with: artworkAfter), "Artwork replacement must invalidate its encoded fragment")
        store.flushPendingSave(); try saved(store)
        try check(store.replaceArtworkProject(artworkAfter, with: artworkBefore), "Artwork import undo must invalidate its encoded fragment")
        store.flushPendingSave(); try saved(store)
        store.selectProject(second.id); store.flushPendingSave(); try saved(store)
        try check(store.deleteProject(first.id) && store.restoreProject(first.id), "Cached projects must survive delete and restore")
        try saved(store)
        try check(store.importProjects([project("Imported")]), "Project import must save independent cached projects")
        try saved(store)
        try check(store.addGeneratedProject(project("Generated")) != nil, "Generated projects must enter the revisioned save path")
        store.flushPendingSave(); try saved(store)

        // A committed multi-file backup can replace content while retaining IDs.
        try check(store.prepareForBackupImport(), "Backup preparation must drain queued cached saves")
        var replacement = store.state
        replacement.projects[0].name = "Replacement retaining UUID"
        replacement.projects[0].glyphs["A"]!.strokes[1].vectorPaths![0].nodes[0].point.x = 0.18
        try reference(replacement).write(to: file, options: .atomic)
        store.acceptSavedBackupImport(replacement)
        try check(store.save(), "Accepted backup contents must be saveable")
        try saved(store)

        func failedTransaction(_ operation: () -> Void) throws {
            let before = store.state, data = try Data(contentsOf: file)
            try FileManager.default.removeItem(at: file)
            try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
            operation()
            try check(store.state == before && store.canRetrySave,
                      "A failed synchronous cached save must roll back observable state and remain retryable")
            try FileManager.default.removeItem(at: file)
            try data.write(to: file)
            try check(store.save(), "Retry after rollback must encode the restored revision")
            try saved(store)
        }
        try failedTransaction { store.renameProject(first.id, to: "Must roll back") }
        try failedTransaction { _ = store.addProject(name: "Must not persist") }
        try failedTransaction { _ = store.deleteProject(first.id) }
        let deletedID = store.state.deletedProjects!.first!.id
        try failedTransaction { _ = store.restoreProject(deletedID) }
        try failedTransaction { _ = store.importProjects([project("Failed import")]) }

        let beforeAsync = try Data(contentsOf: file)
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
        store.updateProject(first.id, save: false) { $0.previewText = "Retained after async failure" }
        store.scheduleSave(after: 0)
        let deadline = Date().addingTimeInterval(5)
        while !store.canRetrySave && Date() < deadline {
            _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        try check(store.canRetrySave, "Background cached failure must surface as retryable")
        try FileManager.default.removeItem(at: file); try beforeAsync.write(to: file)
        store.error = ""; store.flushPendingSave(); try saved(store)

        // Give queued requests a chance to start, then supersede them with the
        // synchronous snapshot. Later callbacks must not restore old fragments.
        for index in 0..<12 {
            store.updateProject(first.id, save: false) { $0.previewText = "Queued \(index)" }
            store.scheduleSave(after: 0)
            _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.001))
        }
        store.updateProject(first.id, save: false) { $0.previewText = "Latest synchronous revision" }
        try check(store.save(), "Latest synchronous cached snapshot must save")
        let settle = Date().addingTimeInterval(0.1)
        while Date() < settle { _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.005)) }
        try saved(store)
        try check(store.state.projects.first(where: { $0.id == first.id })?.previewText == "Latest synchronous revision",
                  "Deferred background completion must retain the latest synchronous project revision")
    }
}
