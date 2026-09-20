import Foundation
import AppKit
import CoreText

enum ProChecks {
    static func run(catalog: [Family]) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("FontShelf-pro-checks-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = Library(storageURL: root.appendingPathComponent("library.json"))
        library.acceptCatalog(catalog)
        library.acceptCatalog([])
        precondition(library.families.isEmpty, "Empty refresh retained stale fonts")
        library.acceptCatalog(catalog)
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
}
