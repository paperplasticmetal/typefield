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
        print("PASS: family merge/split with collection preservation, stable tags, saved axes/features, OpenType parsing, duplicate hashes/name collisions, original-file export and advanced filters.")
    }
    static func glyphs(_ font: CTFont) -> [CGGlyph] {
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: "office affine fi fl ffi", attributes: [.font: font as NSFont]))
        return (CTLineGetGlyphRuns(line) as? [CTRun] ?? []).flatMap { run -> [CGGlyph] in
            var glyphs = [CGGlyph](repeating: 0, count: CTRunGetGlyphCount(run)); CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs); return glyphs
        }
    }
    static func tryEqualHashes(_ a: URL, _ b: URL) -> Bool { (try? DuplicateFinder.hash(a)) == (try? DuplicateFinder.hash(b)) }
}
