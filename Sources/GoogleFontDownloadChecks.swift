import Foundation

enum GoogleFontDownloadChecks {
    static func run() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("typefield-google-download-" + UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
            if !condition() { throw NSError(domain: "Typefield.GoogleDownloadCheck", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        let library = Library(storageURL: root.appendingPathComponent("library.json"))
        let parent = root.appendingPathComponent("Google Fonts")
        let folder = parent.appendingPathComponent("fixture")
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let font = folder.appendingPathComponent("Fixture.ttf")
        try Data("original font".utf8).write(to: font)
        try Data("original license".utf8).write(to: folder.appendingPathComponent("OFL.txt"))

        let failedStage = parent.appendingPathComponent(".fixture-failed")
        try fm.copyItem(at: folder, to: failedStage)
        try Data("new font".utf8).write(to: failedStage.appendingPathComponent("Fixture.ttf"))
        library.librarySaveBlocked = true
        do {
            try GoogleFontStore.commitStagedDownload(failedStage, to: folder, library: library)
            throw NSError(domain: "Typefield.GoogleDownloadCheck", code: 2, userInfo: [NSLocalizedDescriptionKey: "A blocked library save committed downloaded fonts."])
        } catch let error as NSError where error.domain == "Typefield.GoogleDownloadCheck" { throw error }
        catch {}
        let originalAfterFailure = try Data(contentsOf: font)
        try check(originalAfterFailure == Data("original font".utf8), "Failed download changed an existing managed font")
        try check(library.saved.folders.isEmpty, "Failed download retained a managed folder in memory")
        let filesAfterFailure = try fm.contentsOfDirectory(atPath: parent.path)
        try check(!filesAfterFailure.contains { $0.hasPrefix(".typefield-previous-") }, "Failed download stranded the original folder")

        library.librarySaveBlocked = false
        let successStage = parent.appendingPathComponent(".fixture-success")
        try fm.copyItem(at: folder, to: successStage)
        try Data("new font".utf8).write(to: successStage.appendingPathComponent("Fixture.ttf"))
        try GoogleFontStore.commitStagedDownload(successStage, to: folder, library: library)
        let publishedFont = try Data(contentsOf: font)
        let retainedLicense = try Data(contentsOf: folder.appendingPathComponent("OFL.txt"))
        try check(publishedFont == Data("new font".utf8), "Complete download did not publish the new font")
        try check(retainedLicense == Data("original license".utf8), "Complete download lost the existing license")
        try check(Library(storageURL: library.saveURL).saved.folders.contains(folder.path), "Complete download did not persist the managed folder")
        print("PASS: managed Google font download publishes complete folders and rolls back on save failure.")
    }
}
