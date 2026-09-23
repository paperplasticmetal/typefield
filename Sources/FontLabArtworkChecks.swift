import Foundation
import AppKit
import CoreText
import zlib

/// Original geometric artwork, unrelated to the user's fonts or projects.
/// Also exported through --font-lab-artwork-fixtures for manual import QA.
enum FontLabArtworkChecks {
    private static let alphabetPaths: [(String, String)] = [
        ("A", "M10 110 L50 15 L90 110 M27 73 H73"),
        ("B", "M15 110 V15 H52 C98 15 98 61 52 61 H15 M52 61 C102 61 102 110 52 110 H15"),
        ("C", "M85 27 C20 -10 -10 85 48 110 Q70 119 87 101"),
        ("D", "M15 110 V15 H45 C109 15 109 110 45 110 Z"),
        ("E", "M85 15 H15 V110 H85 M15 60 H68"),
        ("F", "M85 15 H15 V110 M15 60 H68"),
        ("G", "M85 27 C20 -10 -10 85 48 110 Q70 119 87 101 V66 H58"),
        ("H", "M15 15 V110 M85 15 V110 M15 60 H85"),
        ("I", "M20 15 H80 M50 15 V110 M20 110 H80"),
        ("J", "M25 15 H85 M68 15 V85 Q68 129 20 103"),
        ("K", "M15 15 V110 M85 15 L15 68 M43 47 L87 110"),
        ("L", "M15 15 V110 H85"),
        ("M", "M10 110 V15 L50 70 L90 15 V110"),
        ("N", "M15 110 V15 L85 110 V15"),
        ("O", "M50 15 C-3 15 -3 110 50 110 C103 110 103 15 50 15 Z"),
        ("P", "M15 110 V15 H53 C101 15 101 65 53 65 H15"),
        ("Q", "M50 15 C-3 15 -3 110 50 110 C103 110 103 15 50 15 Z M60 85 L93 118"),
        ("R", "M15 110 V15 H53 C101 15 101 65 53 65 H15 M53 65 L90 110"),
        ("S", "M85 26 C40 -8 -14 48 50 62 C116 77 71 137 15 101"),
        ("T", "M10 15 H90 M50 15 V110"),
        ("U", "M15 15 V78 C15 123 85 123 85 78 V15"),
        ("V", "M10 15 L50 110 L90 15"),
        ("W", "M8 15 L27 110 L50 57 L73 110 L92 15"),
        ("X", "M12 15 L88 110 M88 15 L12 110"),
        ("Y", "M10 15 L50 65 L90 15 M50 65 V110"),
        ("Z", "M15 15 H85 L15 110 H85")
    ]
    static func alphabetSVG() -> String {
        let paths = alphabetPaths.enumerated().map { index, item in
            "<g transform=\"translate(\(20 + index % 7 * 150) \(20 + index / 7 * 160))\"><path d=\"\(item.1)\"/></g>"
        }.joined()
        return "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"1050\" height=\"640\" viewBox=\"0 0 1050 640\"><g fill=\"none\" stroke=\"black\" stroke-width=\"12\" stroke-linecap=\"round\" stroke-linejoin=\"round\">\(paths)</g></svg>"
    }
    static let singleSVG = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"240\" height=\"260\"><path d=\"M120 25 C5 25 5 235 120 235 C235 235 235 25 120 25 Z M120 65 C180 65 180 195 120 195 C60 195 60 65 120 65 Z\" fill=\"black\"/></svg>"
    static let dottedSVG = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"360\" height=\"200\"><g fill=\"black\"><circle cx=\"50\" cy=\"30\" r=\"10\"/><rect x=\"42\" y=\"65\" width=\"16\" height=\"95\"/><circle cx=\"150\" cy=\"30\" r=\"10\"/><path d=\"M142 65 H158 V154 Q158 193 120 188 V172 Q142 178 142 153 Z\"/><rect x=\"243\" y=\"20\" width=\"16\" height=\"95\"/><circle cx=\"251\" cy=\"151\" r=\"10\"/></g></svg>"

    static func writeFixtures(to folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for (name, svg) in [("alphabet-A-Z", alphabetSVG()), ("single-O", singleSVG), ("detached-ij!", dottedSVG)] {
            let data = Data(svg.utf8)
            try data.write(to: folder.appendingPathComponent(name + ".svg"))
            let image = try FontLabArtworkReader.svgImage(data)
            try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent(name + ".png"))
        }
        let png = try Data(contentsOf: folder.appendingPathComponent("alphabet-A-Z.png"))
        let plist = try PropertyListSerialization.data(fromPropertyList: ["$archiver": "NSKeyedArchiver", "$version": 100000, "$objects": ["$null"], "$top": [:]] as [String: Any], format: .binary, options: 0)
        try archive([("Document.archive", plist), ("QuickLook/Thumbnail.png", png)]).write(to: folder.appendingPathComponent("synthetic-preview.procreate"))
        try """
        Letterform Editor artwork import fixtures

        alphabet-A-Z.svg / .png — Original geometric A–Z artwork, left to right in four rows. Use Detect letters and Apply order → A–Z, or Grid sheet with 7 columns / 4 rows. Review all 26 outlines, then import into a new project.
        single-O.svg / .png — A single letter with an open counter. Choose Single letter, label O and inspect the white hole.
        detached-ij!.svg / .png — Tests detached dots and a descender. The order is ij!.
        synthetic-preview.procreate — A synthetic ZIP container with Document.archive and an embedded flattened PNG, matching the supported Procreate preview layout. It is an importer fixture, not a document produced or editable by Procreate; it does not validate every Procreate version or native layer codec.

        The SVG and PNG artwork here is original test geometry. No installed font outlines or user projects were used.
        """.write(to: folder.appendingPathComponent("README.txt"), atomically: true, encoding: .utf8)
        print("Wrote artwork import fixtures to \(folder.path)")
    }

    static func run() throws {
        func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
            if !condition() { throw FontLabStore.SelfTestError.failed(message) }
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("fontshelf-artwork-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        try writeFixtures(to: folder)
        let source = try FontLabArtworkReader.load(folder.appendingPathComponent("alphabet-A-Z.png"))
        var sheet = try FontLabArtworkEngine.scan(source, options: FontLabArtworkOptions(), recognize: false)
        try check(sheet.regions.count == 26, "Alphabet segmentation found \(sheet.regions.count) regions instead of 26.")
        for index in sheet.regions.indices { sheet.regions[index].character = alphabetPaths[index].0 }
        let project = try FontLabArtworkEngine.project(from: sheet, name: "Original test alphabet")
        try check(project.isValid && project.completedCount == 26, "A traced alphabet did not form a valid editable project.")
        let decoded = try JSONDecoder().decode(FontLabProject.self, from: JSONEncoder().encode(project))
        try check(decoded == project, "Imported contour geometry or source attribution did not persist.")
        let artifact = try FontLabTrueTypeExporter.artifact(for: project)
        let provider = CGDataProvider(data: artifact.data as CFData)!, font = CTFontCreateWithGraphicsFont(CGFont(provider)!, 1000, nil, nil)
        var code: UniChar = 79, gid = CGGlyph(); CTFontGetGlyphsForCharacters(font, &code, &gid, 1)
        let path = CTFontCreatePathForGlyph(font, gid, nil)!, box = path.boundingBoxOfPath
        try check(!path.contains(CGPoint(x: box.midX, y: box.midY)), "An imported O lost its counter in TrueType export.")
        let svg = FontLabSVGExporter.data(projectName: project.name, glyph: project.glyphs["B"]!, metrics: project.metrics)
        try check(String(data: svg, encoding: .utf8)!.contains("path"), "Imported outlines did not export as SVG paths.")
        var grid = FontLabArtworkOptions(); grid.layout = .grid; grid.columns = 7; grid.rows = 4
        let gridScan = try FontLabArtworkEngine.scan(source, options: grid, recognize: false)
        try check(gridScan.regions.count == 26, "Grid import lost letters or generated empty-cell glyphs.")
        var one = FontLabArtworkOptions(); one.layout = .single
        var single = try FontLabArtworkEngine.scan(FontLabArtworkReader.load(folder.appendingPathComponent("single-O.svg")), options: one, recognize: false)
        try check(single.regions.count == 1 && single.regions[0].contours.count == 2, "Single SVG tracing lost a counter.")
        single.regions[0].character = "O"
        let imported = try FontLabArtworkEngine.project(from: single, name: "Single")
        try check(imported.glyphs["O"]!.importFormat == .svg, "SVG source provenance was not saved.")
        let dotted = try FontLabArtworkEngine.scan(FontLabArtworkReader.load(folder.appendingPathComponent("detached-ij!.png")), options: FontLabArtworkOptions(), recognize: false)
        try check(dotted.regions.count == 3 && dotted.regions.allSatisfy { $0.contours.count == 2 }, "Detached i/j/! marks were lost or assigned to separate glyphs.")
        let procreate = try FontLabArtworkReader.load(folder.appendingPathComponent("synthetic-preview.procreate"))
        let procreateScan = try FontLabArtworkEngine.scan(procreate, options: FontLabArtworkOptions(), recognize: false)
        try check(procreate.format == .procreate && !procreate.notices.isEmpty && procreateScan.regions.count == 26, "Procreate preview extraction or resolution disclosure failed.")
        var badLabels = sheet; badLabels.regions[1].character = "A"
        do { _ = try FontLabArtworkEngine.project(from: badLabels, name: "Bad"); throw FontLabStore.SelfTestError.failed("Duplicate character assignments were accepted.") }
        catch FontLabArtworkError.message { }
        do { _ = try FontLabArtworkEngine.project(from: single, name: "Unused", existing: project, replace: false); throw FontLabStore.SelfTestError.failed("Import silently overwrote an existing glyph.") }
        catch FontLabArtworkError.message { }
        let replaced = try FontLabArtworkEngine.project(from: single, name: "Unused", existing: project, replace: true)
        try check(replaced.glyphs["A"] == project.glyphs["A"] && replaced.glyphs["O"] != project.glyphs["O"], "Explicit replacement changed unrelated glyphs.")
        let unsafe = Data("<svg xmlns=\"http://www.w3.org/2000/svg\"><image href=\"https://example.com/image.png\"/></svg>".utf8)
        do { _ = try FontLabArtworkReader.svgImage(unsafe); throw FontLabStore.SelfTestError.failed("An SVG external resource was accepted.") }
        catch FontLabArtworkError.message { }
        do { _ = try FontLabArtworkZIP(data: Data([1,2,3])); throw FontLabStore.SelfTestError.failed("A malformed Procreate archive was accepted.") }
        catch FontLabArtworkError.message { }
        let compressedPreview = archive([("QuickLook/Thumbnail.png", try Data(contentsOf: folder.appendingPathComponent("single-O.png")))], compressed: true)
        let compressedZIP = try FontLabArtworkZIP(data: compressedPreview)
        let unzipped = try compressedZIP.read("QuickLook/Thumbnail.png")
        let originalPreview = try Data(contentsOf: folder.appendingPathComponent("single-O.png"))
        try check(unzipped == originalPreview, "Deflated Procreate previews did not decode exactly.")
        let whiteSVG = singleSVG.replacingOccurrences(of: "fill=\"black\"", with: "fill=\"white\"")
        let whiteSource = FontLabArtworkSource(image: try FontLabArtworkReader.svgImage(Data(whiteSVG.utf8)), filename: "white.svg", format: .svg, notices: [])
        var whiteOptions = one; whiteOptions.lightInk = true
        let whiteScan = try FontLabArtworkEngine.scan(whiteSource, options: whiteOptions, recognize: false)
        try check(whiteScan.regions.count == 1 && whiteScan.regions[0].contours.count == 2, "Light ink on transparency lost the letter or counter.")
        let ell = project.glyphs["L"]!
        func contains(_ x: Double, _ y: Double) -> Bool {
            let path = CGMutablePath()
            for ring in ell.strokes[0].contours! { path.addLines(between: ring.map { CGPoint(x: $0.x, y: $0.y) }); path.closeSubpath() }
            return path.contains(CGPoint(x: x, y: y))
        }
        try check(contains(0.8, project.metrics.baseline + 0.025) && !contains(0.8, project.metrics.capHeight - 0.025), "Artwork tracing flipped the vertical axis.")
        var damaged = try Data(contentsOf: folder.appendingPathComponent("synthetic-preview.procreate")); damaged[100] ^= 1
        do { let zip = try FontLabArtworkZIP(data: damaged); _ = try zip.read("Document.archive"); throw FontLabStore.SelfTestError.failed("Archive integrity corruption was ignored.") }
        catch FontLabArtworkError.message { }
        print("PASS: artwork sheet/single/grid tracing, detached dots, counters, Procreate preview extraction, source protection, persistence and SVG/TrueType fidelity.")
    }

    /// Stored entries are sufficient for portable synthetic fixtures. Production
    /// reads additionally support raw DEFLATE and validate the CRC/size.
    static func archive(_ files: [(String, Data)], compressed: Bool = false) -> Data {
        var output = Data(), central = Data()
        func integer(_ value: UInt32, bytes: Int, to data: inout Data) { for i in 0..<bytes { data.append(UInt8(truncatingIfNeeded: value >> (i * 8))) } }
        for (name, content) in files {
            let nameData = Data(name.utf8), offset = UInt32(output.count)
            var payload = content
            if compressed {
                var length = compressBound(uLong(content.count))
                var buffer = [UInt8](repeating: 0, count: Int(length))
                let status = content.withUnsafeBytes { bytes in compress2(&buffer, &length, bytes.bindMemory(to: UInt8.self).baseAddress, uLong(content.count), Z_BEST_SPEED) }
                precondition(status == Z_OK)
                payload = Data(buffer[2..<(Int(length) - 4)]) // raw DEFLATE, without zlib header/checksum
            }
            let method: UInt32 = compressed ? 8 : 0
            let crc = content.withUnsafeBytes { UInt32(crc32(0, $0.bindMemory(to: UInt8.self).baseAddress, uInt(content.count))) }
            for (v,n) in [(UInt32(0x04034b50),4),(20,2),(0,2),(method,2),(0,2),(0,2),(crc,4),(UInt32(payload.count),4),(UInt32(content.count),4),(UInt32(nameData.count),2),(0,2)] { integer(v,bytes:n,to:&output) }
            output.append(nameData);output.append(payload)
            for (v,n) in [(UInt32(0x02014b50),4),(20,2),(20,2),(0,2),(method,2),(0,2),(0,2),(crc,4),(UInt32(payload.count),4),(UInt32(content.count),4),(UInt32(nameData.count),2),(0,2),(0,2),(0,2),(0,2),(0,4),(offset,4)] { integer(v,bytes:n,to:&central) }
            central.append(nameData)
        }
        let offset = UInt32(output.count);output.append(central)
        for (v,n) in [(UInt32(0x06054b50),4),(0,2),(0,2),(UInt32(files.count),2),(UInt32(files.count),2),(UInt32(central.count),4),(offset,4),(0,2)] { integer(v,bytes:n,to:&output) }
        return output
    }
}
