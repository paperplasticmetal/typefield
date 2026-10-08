import Foundation
import AppKit
import CoreText

enum ProChecks {
    static func run(catalog: [Family]) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("FontShelf-pro-checks-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try checkStoreMigration(in: root)
        checkFilteredFamilySnapshots(in: root)
        let library = Library(storageURL: root.appendingPathComponent("library.json"))
        library.acceptCatalog(catalog)
        library.acceptCatalog([])
        precondition(library.families.isEmpty, "Empty refresh retained stale fonts")
        library.acceptCatalog(catalog)
        if catalog.count > 1 {
            let retainedFamily = catalog[0]
            let removedFamily = catalog[1]
            library.comparison = [retainedFamily.name, removedFamily.name]
            library.selectedFamilies = [retainedFamily.name, removedFamily.name]
            library.acceptCatalog([retainedFamily])
            precondition(library.comparison == [retainedFamily.name] && library.compared.map(\.name) == [retainedFamily.name], "Catalog refresh retained a stale shortlist entry or removed a valid one")
            precondition(library.selectedFamilies == [retainedFamily.name], "Catalog refresh retained a selection for a removed family")
            library.acceptCatalog(catalog)
            library.comparison = []
            library.selectedFamilies = []
        }
        library.search = "Helvetica"
        library.advanced.slant = "Roman"
        precondition(library.saveCurrentSearch(as: "Roman Helvetica"))
        let savedMatches = library.filtered.map(\.name)
        library.search = ""; library.advanced = AdvancedFilter()
        library.applySavedSearch("Roman Helvetica")
        precondition(library.search == "Helvetica" && library.advanced.slant == "Roman" && library.filtered.map(\.name) == savedMatches)
        let reloadedSearches = Library(storageURL: library.saveURL)
        precondition(reloadedSearches.saved.savedSearches?["Roman Helvetica"]?.query == "Helvetica")
        precondition(!library.saveCurrentSearch(as: "Roman Helvetica"))
        precondition(library.deleteSavedSearch("Roman Helvetica") && library.saved.savedSearches?.isEmpty == true)
        library.search = ""; library.advanced = AdvancedFilter()
        let overlayReference = catalog[0].representative.name
        library.toggleOverlay(overlayReference)
        precondition(library.overlayName == overlayReference, "A/B did not activate the selected reference")
        library.toggleOverlay(overlayReference)
        precondition(library.overlayName.isEmpty, "Clicking the active A/B reference did not turn the overlay off")
        let corruptURL = root.appendingPathComponent("corrupt/library.json")
        try FileManager.default.createDirectory(at: corruptURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let corrupt = Data("invalid-json".utf8)
        try corrupt.write(to: corruptURL)
        let broken = Library(storageURL: corruptURL)
        broken.saved.collections["Must not overwrite"] = ["Test"]
        broken.selection = "collection:Must not overwrite"
        let failureFamily = catalog[0]
        precondition(!broken.favorite(failureFamily) && !broken.saved.favorites.contains(failureFamily.name), "Failed favorite save retained an in-memory change")
        precondition(!broken.setCategory(.script, for: failureFamily.name) && broken.saved.overrides[failureFamily.name] == nil, "Failed category save retained an in-memory change")
        precondition(!broken.toggleCollectionMembership(failureFamily.name, in: "Must not overwrite") && broken.saved.collections["Must not overwrite"] == ["Test"], "Failed collection membership save retained an in-memory change")
        precondition(!broken.deleteCollection("Must not overwrite") && broken.saved.collections["Must not overwrite"] == ["Test"] && broken.selection == "collection:Must not overwrite", "Failed collection deletion did not restore membership and selection")
        precondition(!broken.createEmptyCollection("Unsaved") && broken.saved.collections["Unsaved"] == nil && broken.selection == "collection:Must not overwrite", "Failed collection creation retained an in-memory change")
        precondition(!broken.renameCollection("Must not overwrite", to: "Renamed"), "Unreadable library permitted a collection rename")
        precondition(broken.saved.collections["Must not overwrite"] == ["Test"] && broken.saved.collections["Renamed"] == nil && broken.selection == "collection:Must not overwrite", "Failed collection rename was not rolled back")
        broken.save()
        let retained = try Data(contentsOf: corruptURL)
        precondition(retained == corrupt && broken.librarySaveBlocked, "Unreadable library was overwritten")
        broken.pro.tags = ["existing": ["keep"]]
        broken.proSaveBlocked = true
        let previousTags = broken.pro.tags
        precondition(!broken.mergeTagBackup(["imported": ["tag"]]), "Unreadable pro settings permitted a tag import")
        precondition(broken.pro.tags == previousTags, "Failed tag import was not rolled back")
        let blockedInspectorURL = root.appendingPathComponent("blocked-inspector/library.json")
        let blockedInspectorProURL = blockedInspectorURL.deletingLastPathComponent().appendingPathComponent("pro-library.json")
        try FileManager.default.createDirectory(at: blockedInspectorProURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try corrupt.write(to: blockedInspectorProURL)
        let blockedInspector = Library(storageURL: blockedInspectorURL)
        let blockedBefore = blockedInspector.pro
        precondition(!blockedInspector.updatePro { state in
            state.axes["Fixture-Regular"] = [2003265652: 500]
            state.features["Fixture-Regular"] = ["liga": 1]
            state.mainPreviews["Fixture"] = "Fixture-Regular"
        }, "Inspector pro changes succeeded with unreadable settings")
        precondition(blockedInspector.pro.axes == blockedBefore.axes && blockedInspector.pro.features == blockedBefore.features && blockedInspector.pro.mainPreviews == blockedBefore.mainPreviews, "Unreadable Inspector settings left axis, feature, or main-preview changes in memory")
        let blockedInspectorData = try Data(contentsOf: blockedInspectorProURL)
        precondition(blockedInspectorData == corrupt && !blockedInspector.message.isEmpty, "Unreadable Inspector settings were overwritten or did not report the error")
        let diskFailure = Library(storageURL: root.appendingPathComponent("inspector-write-failure/library.json"))
        diskFailure.pro.tags["Fixture-Regular"] = ["baseline"]
        let diskBaseline = diskFailure.pro
        try FileManager.default.createDirectory(at: diskFailure.proURL, withIntermediateDirectories: true)
        precondition(!diskFailure.updatePro { state in
            state.axes["Fixture-Regular"] = [2003265652: 650]
            state.features["Fixture-Regular"] = ["kern": 1]
            state.mainPreviews["Fixture"] = "Fixture-Regular"
        }, "Inspector pro changes succeeded when the settings destination was obstructed")
        precondition(diskFailure.pro.axes == diskBaseline.axes && diskFailure.pro.features == diskBaseline.features && diskFailure.pro.mainPreviews == diskBaseline.mainPreviews && diskFailure.pro.tags == diskBaseline.tags, "Inspector write failure did not restore the previous pro settings")
        let obstructionValues = try diskFailure.proURL.resourceValues(forKeys: [.isDirectoryKey])
        precondition(!diskFailure.message.isEmpty && obstructionValues.isDirectory == true, "Inspector write failure did not report the obstruction or changed its destination")
        let tagFixture = Library(storageURL: root.appendingPathComponent("tag-apply/library.json"))
        tagFixture.acceptCatalog(catalog)
        let taggedFace = catalog[0].representative.name
        tagFixture.pro.tags[taggedFace] = ["keep"]
        precondition(tagFixture.savePro(), "Could not prepare tag apply fixture")
        let tagsBeforeFailedApply = tagFixture.pro.tags
        tagFixture.proSaveBlocked = true
        precondition(!tagFixture.applyTags(["new"], to: [taggedFace], removing: false), "Failed tag addition reported success")
        precondition(tagFixture.pro.tags == tagsBeforeFailedApply, "Failed tag addition remained in memory")
        precondition(!tagFixture.applyTags(["keep"], to: [taggedFace], removing: true), "Failed tag removal reported success")
        precondition(tagFixture.pro.tags == tagsBeforeFailedApply, "Failed tag removal remained in memory")
        let splitURL = root.appendingPathComponent("split-save/library.json")
        let split = Library(storageURL: splitURL)
        split.acceptCatalog(catalog)
        split.saved.collections["Keep"] = [failureFamily.name]
        split.saved.favorites = [failureFamily.name]
        split.comparison = [failureFamily.name]
        split.selectedFamilies = [failureFamily.name]
        precondition(split.save(), "Could not prepare family edit failure fixture")
        let beforeFamilyEdit = try Data(contentsOf: splitURL)
        let beforeFamilyNames = split.families.map(\.name)
        try FileManager.default.createDirectory(at: split.proURL, withIntermediateDirectories: true)
        precondition(!split.editFamily(names: [failureFamily.representative.name], target: "Unsaved merged family"), "Family edit succeeded despite a blocked second settings file")
        let afterFamilyEdit = try Data(contentsOf: splitURL)
        precondition(afterFamilyEdit == beforeFamilyEdit, "Family edit changed the library file after the second save failed")
        precondition(split.families.map(\.name) == beforeFamilyNames && split.pro.familyOverrides.isEmpty && split.saved.collections["Keep"] == [failureFamily.name] && split.saved.favorites == [failureFamily.name] && split.comparison == [failureFamily.name] && split.selectedFamilies == [failureFamily.name], "Failed family edit retained an in-memory remapping")
        precondition(!split.message.isEmpty, "Failed family edit did not report the save error")
        let journal = root.appendingPathComponent("bad-activation.json")
        try corrupt.write(to: journal)
        let manager = ActivationManager(journal: journal)
        precondition(!manager.clear().isEmpty)
        do { _ = try manager.activate(root.appendingPathComponent("missing.ttf")); preconditionFailure("Unreadable activation journal permitted activation") } catch {}
        let retainedJournal = try Data(contentsOf: journal)
        precondition(retainedJournal == corrupt)
        let badAccess = root.appendingPathComponent("bad-access")
        try FileManager.default.createDirectory(at: badAccess, withIntermediateDirectories: true)
        try corrupt.write(to: badAccess.appendingPathComponent("folder-access.json"))
        do { _ = try FolderAccess(directory: badAccess).restore("/unused"); preconditionFailure("Unreadable folder permissions were silently ignored") } catch {}
        let managedAccess = FolderAccess(directory: root.appendingPathComponent("managed"))
        let managedChild = root.appendingPathComponent("managed/Google Fonts/example").path
        let restoredManagedChild = try managedAccess.restore(managedChild)
        precondition(restoredManagedChild == managedChild, "App-managed folders unexpectedly require a bookmark")
        do { _ = try managedAccess.restore(root.appendingPathComponent("external-fonts").path); preconditionFailure("An external folder without a bookmark was accessed") } catch {}
        let external = root.appendingPathComponent("external-fonts")
        let relocated = root.appendingPathComponent("relocated-fonts")
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: relocated, withIntermediateDirectories: true)
        let localAccessRoot = root.appendingPathComponent("local-access")
        let localAccess = FolderAccess(directory: localAccessRoot, sandboxed: false)
        let readableWithoutBookmark = try localAccess.restore(external.path)
        precondition(readableWithoutBookmark == external.path, "A readable folder without a bookmark was mislabeled as needing renewed access in the local build")
        try localAccess.remember(external)
        let restoredLocalBookmark = try FolderAccess(directory: localAccessRoot, sandboxed: false).restore(external.path)
        precondition(restoredLocalBookmark == external.path, "Local folder bookmark did not survive relaunch")
        let alternateSpelling = "/private" + external.path
        precondition(FileManager.default.fileExists(atPath: alternateSpelling), "Expected a temporary-folder alias for the watched-folder check")
        let aliasAccessRoot = root.appendingPathComponent("alias-access")
        let aliasAccess = FolderAccess(directory: aliasAccessRoot, sandboxed: false)
        let restoredAlias = try aliasAccess.restore(alternateSpelling)
        precondition(restoredAlias == alternateSpelling, "Local folder access changed the saved path through a system alias")
        try aliasAccess.remember(URL(fileURLWithPath: alternateSpelling))
        let restoredBookmarkAlias = try FolderAccess(directory: aliasAccessRoot, sandboxed: false).restore(alternateSpelling)
        precondition(restoredBookmarkAlias == alternateSpelling, "Relaunch changed the watched-folder path through a system alias")
        let testHome = root.appendingPathComponent("isolated-home")
        let protectedFonts = testHome.appendingPathComponent("Desktop/fonts")
        try FileManager.default.createDirectory(at: protectedFonts, withIntermediateDirectories: true)
        let protectedAccessRoot = root.appendingPathComponent("protected-access")
        let protectedAccess = FolderAccess(directory: protectedAccessRoot, sandboxed: false, protectedHome: testHome)
        precondition(protectedAccess.needsExplicitResume(protectedFonts.path), "Protected watch should pause before any automatic folder probe")
        precondition(protectedAccess.needsExplicitResume(testHome.appendingPathComponent("Downloads/fonts").path), "Downloads watch should pause")
        precondition(protectedAccess.needsExplicitResume(testHome.appendingPathComponent("Documents/fonts").path), "Documents watch should pause")
        precondition(protectedAccess.needsExplicitResume(testHome.path), "A home-directory watch can descend into protected folders")
        precondition(protectedAccess.needsExplicitResume(testHome.deletingLastPathComponent().path), "An ancestor watch can descend into protected folders")
        do {
            _ = try protectedAccess.restore(testHome.path)
            preconditionFailure("A home-directory watch was probed during automatic restore")
        } catch { precondition(FolderAccess.isPaused(error), "A home-directory watch did not return its paused status") }
        do {
            _ = try protectedAccess.restore(testHome.appendingPathComponent("Downloads/missing").path)
            preconditionFailure("Missing protected watch was probed during automatic restore")
        } catch { precondition(FolderAccess.isPaused(error), "Protected watch was probed before the user resumed it") }
        do {
            _ = try protectedAccess.restore(protectedFonts.path)
            preconditionFailure("Protected watch resumed without an explicit folder choice")
        } catch { precondition(FolderAccess.isPaused(error), "Protected watch did not return its paused status") }
        try protectedAccess.remember(protectedFonts)
        let resumedProtectedPath = try protectedAccess.restore(protectedFonts.path)
        precondition(resumedProtectedPath == protectedFonts.path, "Explicitly chosen protected folder did not resume")
        protectedAccess.pauseWatchAfterError(protectedFonts.path)
        do {
            _ = try protectedAccess.restore(protectedFonts.path)
            preconditionFailure("A protected watch kept reading after a poll access error")
        } catch { precondition(FolderAccess.isPaused(error), "A failed protected watch did not pause") }
        let missingProtectedRoot = testHome.appendingPathComponent("Downloads/missing")
        let failedPoll = FontFolderSnapshot.read([missingProtectedRoot.path], pauseOnError: [missingProtectedRoot.path])
        precondition(failedPoll.failedProtectedRoots == [missingProtectedRoot.path], "A failed protected poll was not marked for suspension")
        try protectedAccess.remember(protectedFonts)
        let restoredAfterPollPause = try protectedAccess.restore(protectedFonts.path)
        precondition(restoredAfterPollPause == protectedFonts.path, "Explicitly choosing a protected folder did not clear its poll pause")
        let nextLaunch = FolderAccess(directory: protectedAccessRoot, sandboxed: false, protectedHome: testHome)
        do {
            _ = try nextLaunch.restore(protectedFonts.path)
            preconditionFailure("A new launch automatically probed a protected watched folder")
        } catch { precondition(FolderAccess.isPaused(error), "Relaunch did not pause protected watch") }
        let sandboxAccess = FolderAccess(directory: root.appendingPathComponent("sandbox-access"), sandboxed: true, protectedHome: testHome)
        do {
            _ = try sandboxAccess.restore(testHome.appendingPathComponent("Downloads/missing").path)
            preconditionFailure("A protected sandbox watch without a bookmark was accepted")
        } catch { precondition(!FolderAccess.isPaused(error), "Sandbox bookmark recovery was incorrectly paused") }
        var watched = SavedLibrary()
        watched.folders = [external.path]
        watched.autoActivateFolders = [external.path]
        watched.replaceWatchedFolder(external.path, with: relocated.path)
        precondition(watched.folders == [relocated.path] && watched.autoActivateFolders == [relocated.path], "Renewal left a failing old path or lost its activation setting")
        watched.folders = [external.path, relocated.path]
        watched.replaceWatchedFolder(external.path, with: relocated.path)
        precondition(watched.folders == [relocated.path], "Renewal duplicated a folder that was already watched")
        try FileManager.default.removeItem(at: external)
        do {
            _ = try localAccess.restore(external.path)
            preconditionFailure("A missing watched folder was treated as readable")
        } catch {
            let issue = error as NSError
            precondition(issue.code == 4 && issue.localizedDescription.contains("unavailable"), "A missing watched folder was mislabeled as an expired permission")
        }
        print("PASS: empty refresh and corrupt library, activation journal, and folder-permission protection.")
        let samples = ["", "i can feel", "अक्षर 日本語 العربية", "a\n\nb\r\nc", "👩🏽‍💻 é " + String(repeating: "W", count: 60)]
        var layouts = 0
        for face in catalog.flatMap(\.faces) {
            let view = BaselineTextView()
            view.font = OpenType.font(name: face.name, size: 131)
            view.wraps = true
            for sample in samples {
                view.text = sample
                let result = view.layout(width: 240)
                precondition(result.height.isFinite && result.height > 0)
                precondition(result.lines.reduce(0) { $0 + CTLineGetStringRange($1).length } == (sample as NSString).length, "Layout lost text")
                layouts += 1
            }
        }
        print("PASS: \(layouts) font layouts including Indic, CJK, Arabic, emoji, combining marks, newlines and long words.")
        let first = catalog.first(where: { $0.faces.count >= 2 })!
        let second = catalog.first(where: { $0.name != first.name })!
        library.saved.collections["Portfolio check"] = [first.name]
        library.saved.favorites = [first.name]
        library.comparison = [first.name]
        let selected = Set([first.faces[0].name, second.faces[0].name])
        library.pro.tags[first.faces[0].name] = ["portfolio", "serif"]
        library.editFamily(names: selected, target: "Test merged family")
        let merged = library.families.first(where: { $0.name == "Test merged family" })!
        precondition(merged.faces.count == 2)
        precondition(library.saved.collections["Portfolio check"]!.contains("Test merged family"))
        precondition(library.saved.collections["Portfolio check"]!.contains(first.name))
        precondition(library.saved.favorites.contains("Test merged family"))
        precondition(library.tags(merged).contains("portfolio"))
        precondition(library.compared.contains { $0.name == "Test merged family" })
        library.editFamily(names: selected, target: nil)
        precondition(!library.families.contains { $0.name == "Test merged family" })
        precondition(library.comparison.allSatisfy { name in library.families.contains { $0.name == name } })
        precondition(library.saved.collections["Portfolio check"]!.contains(first.name))
        library.pro.axes[first.faces[0].name] = [2003265652: 500]
        library.pro.features[first.faces[0].name] = ["liga": 1]
        library.savePro()
        let restored = Library(storageURL: root.appendingPathComponent("library.json"))
        precondition(restored.pro.axes[first.faces[0].name]?[2003265652] == 500)
        precondition(restored.pro.tags[first.faces[0].name] == ["portfolio", "serif"])
        let fixture = Data([0,1,0,0,0,0,0,10,0,0,0,1,108,105,103,97,0,0])
        precondition(OpenType.tags(in: fixture) == ["liga"])
        precondition(OpenType.tags(in: Data([0,1])).isEmpty)
        precondition(OpenType.tags(in: Data([0,1,0,0,0,0,255,255])).isEmpty)
        let source = catalog.flatMap(\.faces).first(where: { $0.url != nil && FileManager.default.fileExists(atPath: $0.url!.path) })!
        let a = root.appendingPathComponent("duplicate-a." + source.url!.pathExtension)
        let b = root.appendingPathComponent("duplicate-b." + source.url!.pathExtension)
        try FileManager.default.copyItem(at: source.url!, to: a); try FileManager.default.copyItem(at: source.url!, to: b)
        precondition(tryEqualHashes(a, b))
        let duplicate = DuplicateFinder.scan(urls: [a,b], folders: [])
        precondition(duplicate.groups.contains { $0.exact && $0.paths.count == 2 })
        precondition(duplicate.groups.contains { !$0.exact && $0.paths.count == 2 })
        let export = root.appendingPathComponent("export")
        try FileManager.default.createDirectory(at: export, withIntermediateDirectories: true)
        let copied = FontExporter.copy(faces: [source,source], to: export)
        precondition(copied.copied.count == 1 && copied.errors.isEmpty)
        precondition(tryEqualHashes(source.url!, export.appendingPathComponent(copied.copied[0])))
        let again = FontExporter.copy(faces: [source], to: export)
        precondition(again.copied.count == 1 && again.copied[0] != copied.copied[0])
        let roman = catalog.flatMap(\.faces).first(where: { !$0.facts.italic })!
        var filter = AdvancedFilter(); filter.slant = "Italic"
        precondition(!filter.matches(roman, tags: []))
        filter = AdvancedFilter(); filter.tag = "portfolio"
        precondition(filter.matches(roman, tags: ["portfolio"]))
        precondition(!filter.matches(roman, tags: ["other"]))
        filter.minimumGlyphs = roman.facts.glyphCount + 1
        precondition(!filter.matches(roman, tags: ["portfolio"]))
        let candidates = catalog.flatMap(\.faces).filter { $0.facts.features.contains("liga") }
        let changesGlyphs = candidates.contains { face in
            glyphs(OpenType.font(name: face.name, size: 24, features: ["liga": 1])) != glyphs(OpenType.font(name: face.name, size: 24, features: ["liga": 0]))
        }
        precondition(changesGlyphs, "Ligature controls did not change shaped glyphs in any supported font")
        try intelligenceChecks(library: library, catalog: catalog)
        print("PASS: family merge/split with collection preservation, stable tags, saved axes/features, OpenType parsing, duplicate hashes/name collisions, original-file export and advanced filters.")
    }

    static func checkFilteredFamilySnapshots(in root: URL) {
        let library = Library(storageURL: root.appendingPathComponent("filter-snapshots/library.json"))
        func face(italic: Bool, coverage: String = "ABC") -> Face {
            let facts = FontFacts(weight: 400, italic: italic, glyphCount: 256, foundry: "Fixture", features: [], widthClass: 5, xHeightRatio: 0.5, capHeightRatio: 0.72, ascenderRatio: 0.8, descenderRatio: 0.2, averageAdvanceRatio: 0.5, panose: [], variable: false, color: false, bitmap: false, monospace: false)
            return Face(name: "FilterFixture-Regular", style: "Regular", originalFamily: "Filter Fixture", facts: facts, url: nil, coverage: CharacterSet(charactersIn: coverage), writingSystems: [.latin])
        }
        func family(_ face: Face) -> Family {
            Family(name: face.originalFamily, faces: [face], automaticCategory: .sans, variable: false, writingSystems: face.writingSystems)
        }
        let original = family(face(italic: false))
        let replacement = family(face(italic: true, coverage: "AB"))
        library.families = [original]
        precondition(library.filteredFaces.count == 1)
        library.families = [replacement]
        library.advanced.slant = "Italic"
        precondition(library.filteredFaces.first?.facts.italic == true, "Catalog replacement retained old style metadata")
        precondition(library.matchingFaces(in: original).isEmpty, "An older same-name family borrowed the replacement's cached faces")
        precondition(library.matchingFaces(in: replacement).count == 1, "A current family lost its matching style")
        precondition(library.chosenFace(replacement).facts.italic, "Preferred preview retained stale font facts")
        library.pro.tags[replacement.faces[0].name] = ["filter-fixture"]
        library.search = "#filter-fixture"
        precondition(library.filteredFaces.count == 1)
        library.pro.tags = [:]
        precondition(library.filteredFaces.isEmpty && library.matchingFaces(in: replacement).isEmpty, "Tag removal retained cached matching styles")
        library.search = ""
        library.requiredText = "C"
        precondition(library.filteredFaces.count == 1, "Preview text filtered fonts with coverage disabled")
        library.requireCoverage = true
        precondition(library.filteredFaces.isEmpty, "Enabling coverage did not inspect the latest preview text")
        library.requiredText = "A"
        precondition(library.filteredFaces.count == 1, "Coverage preview changes retained stale matching styles")
        library.search = "#typefield/upright"
        precondition(library.filteredFaces.isEmpty, "Search edits reused an old parsed query")
        library.search = "#typefield/italic"
        precondition(library.filteredFaces.count == 1, "Changed token filters did not restore matching styles")
        print("PASS: matching-style snapshots preserve same-name catalog replacement, stale inspector isolation, tag changes, and coverage/search invalidation.")
    }

    static func intelligenceChecks(library: Library, catalog: [Family]) throws {
        let panose = [UInt8](arrayLiteral: 2, 2, 6, 3, 8, 2, 2, 2, 2, 4)
        let reference = FontSignature(category: .serif, weight: 400, widthClass: 5, italic: false, monospace: false, xHeightRatio: 0.50, capHeightRatio: 0.72, ascenderRatio: 0.80, descenderRatio: 0.20, averageAdvanceRatio: 0.56, panose: panose, writingSystems: [.latin], visualTags: ["visual/soft"])
        let close = FontSignature(category: .serif, weight: 425, widthClass: 5, italic: false, monospace: false, xHeightRatio: 0.51, capHeightRatio: 0.73, ascenderRatio: 0.81, descenderRatio: 0.20, averageAdvanceRatio: 0.57, panose: panose, writingSystems: [.latin], visualTags: ["visual/soft"])
        let far = FontSignature(category: .sans, weight: 800, widthClass: 2, italic: true, monospace: true, xHeightRatio: 0.68, capHeightRatio: 0.91, ascenderRatio: 1.1, descenderRatio: 0.35, averageAdvanceRatio: 0.9, panose: [2, 11, 9, 8, 2, 8, 8, 8, 8, 9], writingSystems: [.cyrillic], visualTags: ["visual/geometric"])
        let closeAssessment = LibraryIntelligence.assess(reference, close)
        let farAssessment = LibraryIntelligence.assess(reference, far)
        precondition(closeAssessment.distance < farAssessment.distance, "Local similarity did not prefer the closer deterministic signature")
        precondition(closeAssessment.reasons.contains("Similar x-height") && closeAssessment.reasons.contains("Similar stroke contrast"), "Similarity explanations omitted measured matches")

        guard catalog.count >= 4 else { preconditionFailure("Intelligence checks require four local families") }
        let referenceFamily = catalog[0]
        let ranked = LibraryIntelligence.similarFamilies(to: referenceFamily.representative, referenceCategory: referenceFamily.automaticCategory, catalog: catalog, limit: 8)
        precondition(!ranked.isEmpty && ranked.allSatisfy { $0.family.name != referenceFamily.name }, "Similar-family results included the source family")
        precondition(zip(ranked, ranked.dropFirst()).allSatisfy { $0.distance <= $1.distance }, "Similar-family results were not distance ordered")
        let localNames = Set(catalog.map(\.name))
        precondition(ranked.allSatisfy { localNames.contains($0.family.name) }, "Similar-family results escaped the local catalog")

        let scoped = Array(catalog.prefix(4))
        let old = Date(timeIntervalSinceReferenceDate: 10_000)
        let recent = Date(timeIntervalSinceReferenceDate: 20_000)
        let usage = [
            scoped[0].representative.name: FontUsageRecord(lastAppliedAt: old, applicationCount: 1),
            scoped[1].representative.name: FontUsageRecord(lastAppliedAt: recent, applicationCount: 2),
            "RemoteOnly-Regular": FontUsageRecord(lastAppliedAt: .distantPast, applicationCount: 1)
        ]
        let current = [scoped[2].representative.name: 3]
        let discovery = LibraryIntelligence.leastRecentlyUsed(catalog: scoped, usage: usage, currentUseCounts: current, seed: 17, limit: 4)
        let repeated = LibraryIntelligence.leastRecentlyUsed(catalog: scoped, usage: usage, currentUseCounts: current, seed: 17, limit: 4)
        precondition(discovery.map(\.id) == repeated.map(\.id), "Discovery was not deterministic for a fixed seed")
        precondition(discovery.count == 4 && Set(discovery.map(\.id)).isSubset(of: Set(scoped.map(\.name))), "Discovery returned a non-catalog family")
        precondition(discovery.first?.family.name == scoped[3].name, "Discovery did not prefer an unused, unreferenced family")
        precondition(discovery.first(where: { $0.family.name == scoped[0].name }).flatMap(\.lastAppliedAt) == old, "Discovery lost recorded application history")

        let legacyJSON = Data(#"{"favorites":[],"overrides":{},"collections":{},"folders":[]}"#.utf8)
        let legacyLibrary = try JSONDecoder().decode(SavedLibrary.self, from: legacyJSON)
        precondition(legacyLibrary.fontUsage == nil, "Legacy libraries did not decode without usage history")
        let usedFace = scoped[0].representative
        precondition(library.recordFontUse(usedFace.name, at: old), "Could not record local font use")
        precondition(library.recordFontUses([usedFace.name, usedFace.name], at: recent), "Could not update local font use")
        precondition(library.fontUsage(for: usedFace.name) == FontUsageRecord(lastAppliedAt: recent, applicationCount: 2), "Font usage did not deduplicate one application event or retain its newest date")
        precondition(!library.recordFontUse("RemoteOnly-Regular", at: recent), "Usage history accepted a font outside the current local catalog")
        let restored = Library(storageURL: library.saveURL)
        precondition(restored.fontUsage(for: usedFace.name) == library.fontUsage(for: usedFace.name), "Font usage did not survive persistence")
        let previous = library.saved.fontUsage
        library.librarySaveBlocked = true
        precondition(!library.recordFontUse(scoped[1].representative.name, at: recent) && library.saved.fontUsage == previous, "Failed usage persistence was not rolled back")
        library.librarySaveBlocked = false
        print("PASS: deterministic local similarity, explainable rankings, catalog-only discovery, and backward-compatible usage history.")
    }
    static func glyphs(_ font: CTFont) -> [CGGlyph] {
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: "office affine fi fl ffi", attributes: [.font: font as NSFont]))
        return (CTLineGetGlyphRuns(line) as? [CTRun] ?? []).flatMap { run -> [CGGlyph] in
            var glyphs = [CGGlyph](repeating: 0, count: CTRunGetGlyphCount(run)); CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs); return glyphs
        }
    }
    static func tryEqualHashes(_ a: URL, _ b: URL) -> Bool { (try? DuplicateFinder.hash(a)) == (try? DuplicateFinder.hash(b)) }
    private static func checkStoreMigration(in root: URL) throws {
        let fm = FileManager.default
        let source = root.appendingPathComponent("old/FontShelf")
        let destination = root.appendingPathComponent("store/FontShelf")
        try fm.createDirectory(at: source.appendingPathComponent("Google Fonts/example"), withIntermediateDirectories: true)
        var saved = SavedLibrary()
        saved.favorites = ["Example"]
        saved.folders = [source.appendingPathComponent("Google Fonts/example").path, "/external/fonts"]
        saved.autoActivateFolders = [source.appendingPathComponent("Google Fonts/example").path]
        try JSONEncoder().encode(saved).write(to: source.appendingPathComponent("library.json"))
        try JSONEncoder().encode(ProState()).write(to: source.appendingPathComponent("pro-library.json"))
        var studio = StudioState()
        var space = DesignSpace(); space.name = "Existing Space"; space.boards = [TypeBoard()]
        studio.spaces = [space]; studio.selectedSpace = space.id; studio.selectedBoard = space.boards[0].id
        try JSONEncoder().encode(studio).write(to: source.appendingPathComponent("spaces.json"))
        var fontLab = FontLabState()
        let project = FontLabProject(name: "Existing font", characters: ["A"])
        fontLab.projects = [project]; fontLab.selectedProject = project.id
        try JSONEncoder().encode(fontLab).write(to: source.appendingPathComponent("font-lab.json"))
        try Data("font fixture".utf8).write(to: source.appendingPathComponent("Google Fonts/example/example.ttf"))
        let original = try Data(contentsOf: source.appendingPathComponent("library.json"))
        let migratedCount = try StoreMigration.migrate(from: source, to: destination)
        precondition(migratedCount == 5)
        let migrated = try JSONDecoder().decode(SavedLibrary.self, from: Data(contentsOf: destination.appendingPathComponent("library.json")))
        precondition(migrated.favorites == saved.favorites)
        let migratedSpaces = try JSONDecoder().decode(StudioState.self, from: Data(contentsOf: destination.appendingPathComponent("spaces.json")))
        let migratedFontLab = try JSONDecoder().decode(FontLabState.self, from: Data(contentsOf: destination.appendingPathComponent("font-lab.json")))
        precondition(migratedSpaces.spaces.first?.id == space.id && migratedSpaces.spaces.first?.boards.first?.id == space.boards[0].id)
        precondition(migratedFontLab.projects.first?.id == project.id && migratedFontLab.selectedProject == project.id)
        precondition(migrated.folders == [destination.appendingPathComponent("Google Fonts/example").path, "/external/fonts"])
        precondition(migrated.autoActivateFolders == [destination.appendingPathComponent("Google Fonts/example").path])
        let fontCopy = try Data(contentsOf: destination.appendingPathComponent("Google Fonts/example/example.ttf"))
        precondition(fontCopy == Data("font fixture".utf8))
        let sourceAfter = try Data(contentsOf: source.appendingPathComponent("library.json"))
        precondition(sourceAfter == original)
        do { _ = try StoreMigration.migrate(from: source, to: destination); preconditionFailure("Migration overwrote an existing container") } catch {}
        let broken = root.appendingPathComponent("broken/FontShelf")
        try fm.createDirectory(at: broken, withIntermediateDirectories: true)
        try Data("bad json".utf8).write(to: broken.appendingPathComponent("spaces.json"))
        let emptyDestination = root.appendingPathComponent("empty/FontShelf")
        do { _ = try StoreMigration.migrate(from: broken, to: emptyDestination); preconditionFailure("Invalid projects migrated") } catch {}
        precondition(!fm.fileExists(atPath: emptyDestination.appendingPathComponent("spaces.json").path))
        let preferences = root.appendingPathComponent("local.fontshelf.app.plist")
        let preferencesData = try PropertyListSerialization.data(fromPropertyList: ["appearance": "Light", "previewSize": 72.0, "adaptiveGridView": false, "unrelated": "ignore"], format: .binary, options: 0)
        try preferencesData.write(to: preferences)
        let suite = "FontShelf.migration-check." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("Existing", forKey: "appearance")
        let preferenceCount = try StoreMigration.importPreferences(from: preferences, into: defaults)
        precondition(preferenceCount == 2)
        precondition(defaults.string(forKey: "appearance") == "Existing" && defaults.double(forKey: "previewSize") == 72 && !defaults.bool(forKey: "adaptiveGridView") && defaults.object(forKey: "unrelated") == nil)
        print("PASS: clean Store migration, source preservation, managed-font remap, collision and corrupt-data guards.")
    }
}
