import Foundation
import AppKit
import CoreText
import CoreGraphics

/// The local remix modes are deliberately described as vector operations, not AI.
/// They turn outlines from fonts already available to CoreText into editable Font Lab
/// contours without copying or embedding either source font file.
enum FontLabRemixMode: String, Codable, CaseIterable, Identifiable {
    case blend
    case interleave
    case alternate

    var id: String { rawValue }

    var title: String {
        switch self {
        case .blend: return "Blend"
        case .interleave: return "Interleave"
        case .alternate: return "Alternate glyphs"
        }
    }

    var explanation: String {
        switch self {
        case .blend:
            return "Morphs matching contours while preserving open counters."
        case .interleave:
            return "Varies the blend in broad, smoothly connected horizontal bands."
        case .alternate:
            return "Chooses one source face per character with a repeatable pattern."
        }
    }
}

/// Deterministic, offline styling for a generated starter. These presets are small
/// geometric transforms and never contact a model or remote service.
enum FontLabStarterPreset: String, Codable, CaseIterable, Identifiable {
    case clean
    case soft
    case poster
    case kinetic

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    fileprivate var widthScale: Double {
        switch self {
        case .clean: return 1
        case .soft: return 0.98
        case .poster: return 1.08
        case .kinetic: return 0.96
        }
    }

    fileprivate var slant: Double {
        switch self {
        case .kinetic: return 0.15
        default: return 0
        }
    }

    var explanation: String {
        switch self {
        case .clean: return "Faithful contours and natural proportions. No extra rounding, weight, or slant."
        case .soft: return "Gently rounds corners and narrows the letterforms by 2%."
        case .poster: return "Adds weight to the outlines and widens the letterforms by 8%."
        case .kinetic: return "Leans the letterforms forward by about 9° and narrows them by 4%."
        }
    }

}

struct FontLabRemixRecipe: Codable, Equatable, Hashable {
    var primaryPostScriptName: String
    var secondaryPostScriptName: String
    var blendAmount: Double = 0.5
    var mode: FontLabRemixMode = .blend
    var preset: FontLabStarterPreset = .clean

    var isValid: Bool {
        !primaryPostScriptName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !secondaryPostScriptName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            primaryPostScriptName.count <= 300 && secondaryPostScriptName.count <= 300 &&
            blendAmount.isFinite && (0...1).contains(blendAmount)
    }
}

/// Saved with a remixed project so the source faces and derivative-font warning do
/// not disappear after the transient creation sheet closes.
struct FontLabRemixProvenance: Codable, Equatable {
    static let generator = "FontShelf local outline remix"
    static let licenseNotice = "Source font binaries were not copied or bundled. Review both source font licenses before exporting, installing, or distributing this derivative font."

    var sourcePostScriptNames: [String]
    var blendAmount: Double
    var mode: FontLabRemixMode
    var preset: FontLabStarterPreset
    var generatorName = FontLabRemixProvenance.generator
    var distributionNotice = FontLabRemixProvenance.licenseNotice
    var preservedCharacters: [String]? = nil

    var isValid: Bool {
        (2...3).contains(sourcePostScriptNames.count) &&
            sourcePostScriptNames.allSatisfy { !$0.isEmpty && $0.count <= 300 } &&
            blendAmount.isFinite && (0...1).contains(blendAmount) &&
            !generatorName.isEmpty && generatorName.count <= 200 &&
            !distributionNotice.isEmpty && distributionNotice.count <= 2_000 &&
            (preservedCharacters.map { $0.count <= 2_000 && $0.allSatisfy { $0.count == 1 } } ?? true)
    }

    var summary: String {
        "Editable local remix of \(sourcePostScriptNames.joined(separator: " + ")) · \(mode.title) \(Int((blendAmount * 100).rounded()))% · \(preset.title)" + ((preservedCharacters?.isEmpty == false) ? " · \(preservedCharacters!.count) glyphs retain the dominant source structure" : "")
    }
}

struct FontLabRemixResult: Equatable {
    var project: FontLabProject
    var provenance: FontLabRemixProvenance
    var skippedCharacters: [String]
    var preservedCharacters: [String] = []

    var status: String {
        let count = project.completedCount
        let preserved = preservedCharacters.isEmpty ? "" : " · \(preservedCharacters.count) kept from the dominant source to preserve their structure"
        let skipped = skippedCharacters.isEmpty ? "" : " · \(skippedCharacters.count) unsupported"
        return "Created \(count) editable glyphs from \(provenance.sourcePostScriptNames.joined(separator: " + "))\(skipped)\(preserved). \(FontLabRemixProvenance.licenseNotice)"
    }
}

enum FontLabRemixEngine {
    enum RemixError: LocalizedError, Equatable {
        case invalidRecipe
        case invalidProjectName
        case invalidCharacters
        case unavailableFont(String)
        case noSupportedCharacters

        var errorDescription: String? {
            switch self {
            case .invalidRecipe:
                return "Choose two installed font faces and a blend amount between 0% and 100%."
            case .invalidProjectName:
                return "Enter a project name between 1 and 200 characters."
            case .invalidCharacters:
                return "The starter character list must contain unique, single characters."
            case let .unavailableFont(name):
                return "The font face “\(name)” is no longer available. Refresh the Library and choose another face."
            case .noSupportedCharacters:
                return "The selected sources and balance do not provide any of the requested characters."
            }
        }
    }

    /// Generates editable compound outlines from two installed outline fonts.
    /// The default project ID is intentionally new for each user-created project;
    /// every glyph and outline inside it remains deterministic for a given recipe.
    static func generate(
        recipe: FontLabRemixRecipe,
        projectName: String = "Remixed font",
        characters: [String] = FontLabProject.starterCharacters,
        projectID: UUID = UUID()
    ) throws -> FontLabRemixResult {
        guard recipe.isValid else { throw RemixError.invalidRecipe }
        let cleanedName = projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedName.isEmpty, cleanedName.count <= 200 else { throw RemixError.invalidProjectName }
        guard !characters.isEmpty, characters.count <= 2_000,
              Set(characters).count == characters.count,
              characters.allSatisfy({ $0.count == 1 }) else {
            throw RemixError.invalidCharacters
        }

        let primary = try exactFont(named: recipe.primaryPostScriptName)
        let secondary = try exactFont(named: recipe.secondaryPostScriptName)
        var metrics = FontLabMetrics()
        let aScale = faceScale(primary, metrics: metrics), bScale = faceScale(secondary, metrics: metrics)
        metrics.capHeight = metrics.baseline + mix(Double(CTFontGetCapHeight(primary)) * aScale,
            Double(CTFontGetCapHeight(secondary)) * bScale, recipe.blendAmount)
        metrics.xHeight = min(metrics.capHeight - 0.05, max(metrics.baseline + 0.05,
            metrics.baseline + mix(Double(CTFontGetXHeight(primary)) * aScale, Double(CTFontGetXHeight(secondary)) * bScale, recipe.blendAmount)))
        var project = FontLabProject(id: projectID, name: cleanedName, characters: characters)
        project.metrics = metrics
        var provenance = FontLabRemixProvenance(
            sourcePostScriptNames: [
                CTFontCopyPostScriptName(primary) as String,
                CTFontCopyPostScriptName(secondary) as String
            ],
            blendAmount: recipe.blendAmount,
            mode: recipe.mode,
            preset: recipe.preset
        )
        project.remixProvenance = provenance

        var skipped: [String] = []
        var preserved: [String] = []
        for character in characters {
            let primaryOutline = normalizedOutline(character: character, font: primary, metrics: metrics)
            let secondaryOutline = normalizedOutline(character: character, font: secondary, metrics: metrics)
            guard primaryOutline != nil || secondaryOutline != nil,
                  !(recipe.blendAmount <= 0 && primaryOutline == nil),
                  !(recipe.blendAmount >= 1 && secondaryOutline == nil) else {
                skipped.append(character)
                continue
            }

            let (glyph, keptSource) = makeGlyph(character: character, primary: primaryOutline,
                secondary: secondaryOutline, recipe: recipe, metrics: metrics)
            if keptSource { preserved.append(character) }
            project.glyphs[character] = glyph
        }

        provenance.preservedCharacters = preserved.isEmpty ? nil : preserved
        project.remixProvenance = provenance
        guard project.completedCount > 0 else { throw RemixError.noSupportedCharacters }
        guard project.isValid else { throw RemixError.invalidCharacters }
        return FontLabRemixResult(project: project, provenance: provenance, skippedCharacters: skipped, preservedCharacters: preserved)
    }

    /// Fast deterministic checks that use only ubiquitous macOS system faces and
    /// a tiny character fixture. No user projects or font files are read or changed.
    static func selfTest() throws {
        let id = UUID(uuidString: "4F3620A0-6979-4E13-AF84-2C29D0C044F7")!
        let recipe = FontLabRemixRecipe(
            primaryPostScriptName: "Helvetica",
            secondaryPostScriptName: "Times-Roman",
            blendAmount: 0.42,
            mode: .blend,
            preset: .kinetic
        )
        let characters = ["A", "g", "0", "?"]
        let first = try generate(recipe: recipe, projectName: "Deterministic remix", characters: characters, projectID: id)
        let second = try generate(recipe: recipe, projectName: "Deterministic remix", characters: characters, projectID: id)
        guard first == second, first.project.isValid,
              first.project.completedCount == characters.count,
              first.project.remixProvenance == first.provenance,
              first.provenance.sourcePostScriptNames == ["Helvetica", "Times-Roman"],
              first.status.contains("were not copied or bundled"),
              first.project.glyphs.values.allSatisfy({ glyph in
                  glyph.strokes.allSatisfy { $0.contours?.isEmpty == false && $0.isValid }
              }) else {
            throw FontLabStore.SelfTestError.failed("Deterministic Font Lab remix generation failed.")
        }

        let originalArtifact = try FontLabTrueTypeExporter.artifact(for: first.project)
        var editedProject = first.project
        editedProject.glyphs["A"]!.strokes[0].contours![0][0].x = min(0.99, editedProject.glyphs["A"]!.strokes[0].contours![0][0].x + 0.005)
        let editedArtifact = try FontLabTrueTypeExporter.artifact(for: editedProject)
        guard originalArtifact.postScriptName != editedArtifact.postScriptName else {
            throw FontLabStore.SelfTestError.failed("Outline point edits did not change the installable font identity.")
        }
        let svg = FontLabSVGExporter.string(projectName: first.project.name, glyph: first.project.glyphs["0"]!, metrics: first.project.metrics)
        guard svg.contains("fill-rule=\"nonzero\""), svg.contains("<path"), !svg.contains("<polyline") else {
            throw FontLabStore.SelfTestError.failed("A generated contour was exported as separate SVG strokes.")
        }

        var legacyObject = try JSONSerialization.jsonObject(with: JSONEncoder().encode(first.project)) as! [String: Any]
        legacyObject.removeValue(forKey: "remixProvenance")
        let legacyData = try JSONSerialization.data(withJSONObject: legacyObject, options: [.sortedKeys])
        let decodedLegacy = try JSONDecoder().decode(FontLabProject.self, from: legacyData)
        guard decodedLegacy.remixProvenance == nil else {
            throw FontLabStore.SelfTestError.failed("Legacy Font Lab projects unexpectedly acquired remix metadata.")
        }
        var futureCopy = first.provenance
        futureCopy.generatorName = "Localized generator name"
        futureCopy.distributionNotice = "Updated license guidance"
        guard futureCopy.isValid else {
            throw FontLabStore.SelfTestError.failed("Harmless future provenance wording would invalidate saved Font Lab data.")
        }

        var invalid = recipe
        invalid.blendAmount = 2
        do {
            _ = try generate(recipe: invalid, characters: ["A"], projectID: id)
            throw FontLabStore.SelfTestError.failed("An invalid Font Lab remix recipe was accepted.")
        } catch RemixError.invalidRecipe {
            // Expected.
        }

        for mode in FontLabRemixMode.allCases {
            var modeRecipe = recipe
            modeRecipe.mode = mode
            let result = try generate(recipe: modeRecipe, projectName: mode.title, characters: ["A"], projectID: id)
            guard result.project.completedCount == 1 else {
                throw FontLabStore.SelfTestError.failed("Font Lab \(mode.title) remix mode produced no editable glyph.")
            }
        }

        try geometrySelfTest()

        var unavailable = recipe
        unavailable.primaryPostScriptName = "FontShelf-Definitely-Missing-Face"
        do {
            _ = try generate(recipe: unavailable, characters: ["A"], projectID: id)
            throw FontLabStore.SelfTestError.failed("An unavailable Font Lab source face was accepted.")
        } catch let RemixError.unavailableFont(name) where name == "FontShelf-Definitely-Missing-Face" {
            // Expected; CoreText's silent fallback must never be mistaken for the requested face.
        }
    }

    private static func geometrySelfTest() throws {
        let names = ["Helvetica", "Times-Roman"]
        let characters = ["H", "W", "i", "O", "8", "g", "&"]
        func geometry(_ glyph: FontLabGlyph) -> FontLabGlyph {
            var value = glyph
            value.strokes = value.strokes.map { stroke in
                var copy = stroke; copy.id = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!; return copy
            }
            return value
        }
        for preset in FontLabStarterPreset.allCases {
            let source = try names.map { name in
                try generate(recipe: FontLabRemixRecipe(primaryPostScriptName: name, secondaryPostScriptName: name,
                    blendAmount: 0, preset: preset), characters: characters).project
            }
            for mode in FontLabRemixMode.allCases {
                for amount in [0.0, 0.35, 0.5, 1.0] {
                    let result = try generate(recipe: FontLabRemixRecipe(primaryPostScriptName: names[0],
                        secondaryPostScriptName: names[1], blendAmount: amount, mode: mode, preset: preset), characters: characters)
                    for character in characters {
                        let actual = geometry(result.project.glyphs[character]!)
                        if amount == 0 || amount == 1 {
                            guard actual == geometry(source[amount == 0 ? 0 : 1].glyphs[character]!) else {
                                throw FontLabStore.SelfTestError.failed("A remix endpoint contains geometry from the other source.")
                            }
                        } else if mode == .alternate {
                            guard source.contains(where: { geometry($0.glyphs[character]!) == actual }) else {
                                throw FontLabStore.SelfTestError.failed("Alternate glyphs mixed rows from different sources.")
                            }
                        }
                    }
                    // Exercise the complete compound-outline export, not only the editor.
                    let artifact = try FontLabTrueTypeExporter.artifact(for: result.project)
                    guard let provider = CGDataProvider(data: artifact.data as CFData), let cgFont = CGFont(provider) else {
                        throw FontLabStore.SelfTestError.failed("Remixed outline export was unreadable.")
                    }
                    let exported = CTFontCreateWithGraphicsFont(cgFont, 1000, nil, nil)
                    let original = result.project.glyphs["O"]!
                    var code: UniChar = 79, glyphID = CGGlyph()
                    guard CTFontGetGlyphsForCharacters(exported, &code, &glyphID, 1),
                          let exportedPath = CTFontCreatePathForGlyph(exported, glyphID, nil) else {
                        throw FontLabStore.SelfTestError.failed("An exported remix lost its O outline.")
                    }
                    let expected = CGMutablePath()
                    for contour in original.strokes[0].contours! {
                        expected.addLines(between: contour.map { CGPoint(x: (original.leftSideBearing + $0.x * original.resolvedDesignWidth) * 1000,
                            y: ($0.y - result.project.metrics.baseline) * 1000) })
                        expected.closeSubpath()
                    }
                    var mismatches = 0
                    for x in 0..<40 { for y in 0..<40 {
                        let p = CGPoint(x: Double(x) * 25 + 0.37, y: Double(y) * 25 - 200 + 0.37)
                        if expected.contains(p) != exportedPath.contains(p) { mismatches += 1 }
                    } }
                    guard mismatches <= 6 else {
                        throw FontLabStore.SelfTestError.failed("TrueType export changed a remixed counter or outline.")
                    }
                }
            }
        }
        let result = try generate(recipe: FontLabRemixRecipe(primaryPostScriptName: "Helvetica", secondaryPostScriptName: "Helvetica", blendAmount: 0), characters: characters)
        let h = result.project.glyphs["H"]!, w = result.project.glyphs["W"]!, i = result.project.glyphs["i"]!
        func top(_ glyph: FontLabGlyph) -> Double { glyph.strokes.flatMap { ($0.contours ?? []).flatMap { $0 } }.map(\.y).max()! }
        guard abs(top(h) - top(w)) < 0.002, w.resolvedDesignWidth > i.resolvedDesignWidth * 2,
              result.project.glyphs["O"]!.strokes[0].contours!.contains(where: { area($0) > 0 }),
              try JSONDecoder().decode(FontLabProject.self, from: JSONEncoder().encode(result.project)) == result.project else {
            throw FontLabStore.SelfTestError.failed("Generated widths, cap heights, counters, or persistence regressed.")
        }
        let outer = [FontLabPoint(x: 0.1, y: 0.2), FontLabPoint(x: 0.1, y: 0.7), FontLabPoint(x: 0.6, y: 0.7), FontLabPoint(x: 0.6, y: 0.2)]
        let hole = [FontLabPoint(x: 0.2, y: 0.3), FontLabPoint(x: 0.5, y: 0.3), FontLabPoint(x: 0.5, y: 0.6), FontLabPoint(x: 0.2, y: 0.6)]
        let recipe = FontLabRemixRecipe(primaryPostScriptName: "Helvetica", secondaryPostScriptName: "Times-Roman")
        guard mixedContours(Outline(contours: [outer], advance: 0.7), Outline(contours: [outer, hole], advance: 0.7), recipe: recipe) == nil,
              !validTopology([[outer[0], outer[2], outer[1], outer[3]]]) else {
            throw FontLabStore.SelfTestError.failed("Incompatible or self-crossing outlines were accepted for blending.")
        }
        print("PASS: continuous remix contours, source endpoints, proportional widths, counters, all styles/modes, persistence and TrueType shape fidelity.")
    }

    /// A disposable visual specimen; never opens or writes the user's library.
    static func writeSpecimen(to folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let pairs = [("Helvetica", "Times-Roman"), ("AdobeClean-Black", "Futura-Bold"),
                     ("AbrilFatface-Regular", "1797-POSTER_V2")]
        let characters = Array("AHOWMagnesio08&@").map(String.init)
        for (pairIndex, pair) in pairs.enumerated() {
            for preset in FontLabStarterPreset.allCases {
                let recipe = FontLabRemixRecipe(primaryPostScriptName: pair.0, secondaryPostScriptName: pair.1, preset: preset)
                guard let result = try? generate(recipe: recipe, characters: characters) else { continue }
                let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1960, pixelsHigh: 420,
                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
                NSColor.white.setFill()
                NSRect(x: 0, y: 0, width: 1960, height: 420).fill()
                ("\(pair.0) × \(pair.1) · \(preset.title) · 50%" as NSString).draw(at: NSPoint(x: 24, y: 380), withAttributes: [.font: NSFont.systemFont(ofSize: 22), .foregroundColor: NSColor.black])
                for (index, character) in characters.enumerated() {
                    if let glyph = result.project.glyphs[character] {
                        let width = min(106, glyph.resolvedDesignWidth * 210)
                        fontLabDrawStrokes(glyph.strokes, in: NSRect(x: 24 + Double(index) * 120 + (106 - width) / 2, y: 145, width: width, height: 210), color: .black)
                    }
                }
                let view = FontLabPreviewNSView(frame: NSRect(x: 20, y: 20, width: 1910, height: 120))
                view.text = "Hamburgefontsiv 0123"
                view.glyphs = try generate(recipe: recipe).project.glyphs
                view.metrics = result.project.metrics
                // Draw in a translated context so the specimen uses the same renderer as the app.
                let transform = NSAffineTransform()
                transform.translateX(by: 20, yBy: 20)
                transform.concat()
                view.draw(view.bounds)
                NSGraphicsContext.restoreGraphicsState()
                try bitmap.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent("pair-\(pairIndex)-\(preset.rawValue).png"))
                let font = try FontLabTrueTypeExporter.artifact(for: result.project)
                try font.write(to: folder.appendingPathComponent("pair-\(pairIndex)-\(preset.rawValue).ttf"))
            }
        }
    }

    private static func exactFont(named postScriptName: String) throws -> CTFont {
        let font = CTFontCreateWithName(postScriptName as CFString, 1_000, nil)
        guard (CTFontCopyPostScriptName(font) as String) == postScriptName else {
            throw RemixError.unavailableFont(postScriptName)
        }
        return font
    }

    private struct Outline {
        var contours: [[FontLabPoint]]
        var advance: Double
    }

    // One scale per face, independent of character width. Previously W/M were
    // shrunk vertically while i/l retained their height.
    private static func faceScale(_ font: CTFont, metrics: FontLabMetrics) -> Double {
        let cap = max(1, Double(CTFontGetCapHeight(font)))
        let descent = max(1, Double(CTFontGetDescent(font)))
        return min((metrics.capHeight - metrics.baseline) / cap, (metrics.baseline - 0.012) / descent)
    }

    private static func normalizedOutline(character: String, font: CTFont, metrics: FontLabMetrics) -> Outline? {
        let utf16 = Array(character.utf16)
        guard utf16.count == 1 else { return nil }
        var codeUnit = utf16[0]
        var glyph = CGGlyph()
        guard CTFontGetGlyphsForCharacters(font, &codeUnit, &glyph, 1), glyph != 0,
              let path = CTFontCreatePathForGlyph(font, glyph, nil) else { return nil }
        var advance = CGSize.zero
        _ = CTFontGetAdvancesForGlyphs(font, .horizontal, &glyph, &advance, 1)
        let scale = faceScale(font, metrics: FontLabMetrics())
        var transform = CGAffineTransform(a: scale, b: 0, c: 0, d: scale, tx: 0, ty: metrics.baseline)
        guard let normalized = path.copy(using: &transform) else { return nil }
        let contours = flattened(normalized)
        guard !contours.isEmpty else { return nil }
        return Outline(contours: contours, advance: Double(advance.width) * scale)
    }

    /// Adaptive curve flattening, with a sub-unit error at the export's 1,000 UPM.
    /// Source vertices are retained so sharp serifs and corners stay sharp.
    private static func flattened(_ path: CGPath) -> [[FontLabPoint]] {
        var contours: [[FontLabPoint]] = []
        var current: [FontLabPoint] = []
        func point(_ p: CGPoint) -> FontLabPoint { FontLabPoint(x: p.x, y: p.y) }
        func finish() {
            if current.count > 1, current.first == current.last { current.removeLast() }
            if current.count >= 3, abs(area(current)) > 0.000_000_1 { contours.append(current) }
            current = []
        }
        func curve(_ a: FontLabPoint, _ b: FontLabPoint, _ c: FontLabPoint, _ d: FontLabPoint, _ depth: Int) {
            let chord = hypot(d.x - a.x, d.y - a.y)
            let net = hypot(b.x - a.x, b.y - a.y) + hypot(c.x - b.x, c.y - b.y) + hypot(d.x - c.x, d.y - c.y)
            if depth >= 12 || (net - chord < 0.000_08 && net < 0.035) {
                current.append(d)
                return
            }
            let ab = interpolate(a, b, 0.5), bc = interpolate(b, c, 0.5), cd = interpolate(c, d, 0.5)
            let abc = interpolate(ab, bc, 0.5), bcd = interpolate(bc, cd, 0.5)
            let middle = interpolate(abc, bcd, 0.5)
            curve(a, ab, abc, middle, depth + 1)
            curve(middle, bcd, cd, d, depth + 1)
        }
        path.applyWithBlock { pointer in
            let element = pointer.pointee
            switch element.type {
            case .moveToPoint:
                finish(); current = [point(element.points[0])]
            case .addLineToPoint: current.append(point(element.points[0]))
            case .addQuadCurveToPoint:
                guard let a = current.last else { return }
                let b = point(element.points[0]), d = point(element.points[1])
                curve(a, interpolate(a, b, 2.0 / 3), interpolate(d, b, 2.0 / 3), d, 0)
            case .addCurveToPoint:
                guard let a = current.last else { return }
                curve(a, point(element.points[0]), point(element.points[1]), point(element.points[2]), 0)
            case .closeSubpath: finish()
            @unknown default: break
            }
        }
        finish()
        // Determine holes by containment, independent of each font's winding.
        return contours.enumerated().map { index, contour in
            let sample = contour[0]
            let depth = contours.enumerated().filter { otherIndex, other in
                otherIndex != index && abs(area(other)) > abs(area(contour)) && contains(other, sample)
            }.count
            let clockwise = depth % 2 == 0
            return (area(contour) < 0) == clockwise ? contour : contour.reversed()
        }
    }

    private static func area(_ points: [FontLabPoint]) -> Double {
        guard !points.isEmpty else { return 0 }
        return points.indices.reduce(0) { value, i in
            let next = points[(i + 1) % points.count]
            return value + points[i].x * next.y - next.x * points[i].y
        } / 2
    }

    private static func contains(_ contour: [FontLabPoint], _ p: FontLabPoint) -> Bool {
        let path = CGMutablePath()
        path.addLines(between: contour.map { CGPoint(x: $0.x, y: $0.y) })
        path.closeSubpath()
        return path.contains(CGPoint(x: p.x, y: p.y))
    }

    private struct Ring {
        let points: [FontLabPoint]
        let stops: [Double]
        init(_ points: [FontLabPoint]) {
            self.points = points
            var lengths = [0.0]
            for index in points.indices {
                let next = points[(index + 1) % points.count]
                lengths.append(lengths.last! + hypot(next.x - points[index].x, next.y - points[index].y))
            }
            let total = max(lengths.last!, 0.000_001)
            stops = lengths.map { $0 / total }
        }
        func at(_ position: Double) -> FontLabPoint {
            let t = position - floor(position)
            var lo = 0, hi = points.count
            while lo + 1 < hi {
                let middle = (lo + hi) / 2
                if stops[middle] <= t { lo = middle } else { hi = middle }
            }
            return interpolate(points[lo], points[(lo + 1) % points.count], (t - stops[lo]) / max(0.000_000_1, stops[lo + 1] - stops[lo]))
        }
    }

    private static func interpolate(_ a: FontLabPoint, _ b: FontLabPoint, _ t: Double) -> FontLabPoint {
        FontLabPoint(x: mix(a.x, b.x, t), y: mix(a.y, b.y, t))
    }

    private static func mixedContours(_ a: Outline, _ b: Outline, recipe: FontLabRemixRecipe) -> [[FontLabPoint]]? {
        // Mixing incompatible counter structures (e.g. single/double-storey g)
        // produces torn bowls. Keep the dominant source for that character.
        guard a.contours.allSatisfy({ $0.count <= 1_200 }), b.contours.allSatisfy({ $0.count <= 1_200 }),
              a.contours.count == b.contours.count,
              a.contours.filter({ area($0) > 0 }).count == b.contours.filter({ area($0) > 0 }).count else { return nil }
        func center(_ contour: [FontLabPoint]) -> FontLabPoint {
            let xs = contour.map(\.x), ys = contour.map(\.y)
            return FontLabPoint(x: (xs.min()! + xs.max()!) / 2, y: (ys.min()! + ys.max()!) / 2)
        }
        var available = Set(b.contours.indices)
        var result: [[FontLabPoint]] = []
        for lhs in a.contours {
            let lc = center(lhs), la = area(lhs)
            guard let match = available.filter({ (area(b.contours[$0]) > 0) == (la > 0) }).min(by: { i, j in
                func cost(_ index: Int) -> Double {
                    let rc = center(b.contours[index])
                    return pow(lc.x - rc.x, 2) + pow(lc.y - rc.y, 2) + abs(abs(la) - abs(area(b.contours[index])))
                }
                let x = cost(i), y = cost(j)
                return x == y ? i < j : x < y
            }) else { return nil }
            available.remove(match)
            let left = Ring(lhs), right = Ring(b.contours[match])
            // Find a consistent starting point before interpolating perimeters.
            let samples = 96
            let l = (0..<samples).map { left.at(Double($0) / Double(samples)) }
            let r = (0..<samples).map { right.at(Double($0) / Double(samples)) }
            let shift = (0..<samples).min { first, second in
                func score(_ offset: Int) -> Double {
                    (0..<samples).reduce(0) { sum, index in
                        let a = l[index], b = r[(index + offset) % samples]
                        return sum + pow(a.x - b.x, 2) + pow(a.y - b.y, 2)
                    }
                }
                return score(first) < score(second)
            } ?? 0
            let phase = Double(shift) / Double(samples)
            // Monotone spatial correspondence keeps baselines, stems and serif
            // junctions aligned even when the two perimeters have different lengths.
            let leftStops = Array(Set(left.stops.dropLast() + (0..<samples).map { Double($0) / Double(samples) })).sorted()
            let rightStops = Array(Set(right.stops.dropLast().map { ($0 - phase + 1).truncatingRemainder(dividingBy: 1) } + (0..<samples).map { Double($0) / Double(samples) })).sorted()
            let lp = (leftStops + [1]).map { left.at($0) }
            let rp = (rightStops + [1]).map { right.at($0 + phase) }
            let columns = rp.count
            var costs = [Double](repeating: .infinity, count: lp.count * columns)
            var previous = [UInt8](repeating: 0, count: costs.count)
            let leftCenter = center(lhs), rightCenter = center(b.contours[match])
            let leftWidth = max(0.02, lhs.map(\.x).max()! - lhs.map(\.x).min()!)
            let rightWidth = max(0.02, b.contours[match].map(\.x).max()! - b.contours[match].map(\.x).min()!)
            let commonWidth = (leftWidth + rightWidth) / 2
            for i in lp.indices {
                for j in rp.indices {
                    let dx = ((lp[i].x - leftCenter.x) / leftWidth - (rp[j].x - rightCenter.x) / rightWidth) * commonWidth
                    let dy = lp[i].y - rp[j].y
                    let local = dx * dx + dy * dy
                    let index = i * columns + j
                    if i == 0 && j == 0 { costs[index] = local; continue }
                    let diagonal = i > 0 && j > 0 ? costs[(i - 1) * columns + j - 1] : .infinity
                    let up = i > 0 ? costs[(i - 1) * columns + j] + 0.000_002 : .infinity
                    let across = j > 0 ? costs[i * columns + j - 1] + 0.000_002 : .infinity
                    if diagonal <= up && diagonal <= across { costs[index] = local + diagonal; previous[index] = 0 }
                    else if up <= across { costs[index] = local + up; previous[index] = 1 }
                    else { costs[index] = local + across; previous[index] = 2 }
                }
            }
            var i = lp.count - 1, j = rp.count - 1
            var ring: [FontLabPoint] = []
            while true {
                let p = lp[i], q = rp[j]
                var amount = recipe.blendAmount
                if recipe.mode == .interleave {
                    let y = mix(p.y, q.y, amount)
                    amount = min(1, max(0, amount + sin((y - 0.18) * .pi * 6) * min(amount, 1 - amount) * 0.85))
                }
                ring.append(interpolate(p, q, amount))
                if i == 0 && j == 0 { break }
                switch previous[i * columns + j] {
                case 1: i -= 1
                case 2: j -= 1
                default: i -= 1; j -= 1
                }
            }
            ring.reverse()
            if ring.first == ring.last { ring.removeLast() }
            ring = simplified(ring, tolerance: 0.000_45)
            guard ring.count >= 3, (area(ring) > 0) == (la > 0), abs(area(ring)) > 0.000_001 else { return nil }
            result.append(ring)
        }
        return validTopology(result) ? result : nil
    }

    /// Closed Ramer–Douglas–Peucker reduction. This keeps sharp corners while
    /// making the generated outlines practical to edit with a mouse.
    private static func simplified(_ points: [FontLabPoint], tolerance: Double) -> [FontLabPoint] {
        guard points.count > 6 else { return points }
        func open(_ values: [FontLabPoint]) -> [FontLabPoint] {
            guard values.count > 2 else { return values }
            let a = values.first!, b = values.last!
            let dx = b.x - a.x, dy = b.y - a.y, length = dx * dx + dy * dy
            var farthest = 0, distance = 0.0
            for index in 1..<(values.count - 1) {
                let p = values[index]
                let t = length > 0 ? min(1, max(0, ((p.x - a.x) * dx + (p.y - a.y) * dy) / length)) : 0
                let d = hypot(p.x - a.x - t * dx, p.y - a.y - t * dy)
                if d > distance { distance = d; farthest = index }
            }
            guard distance > tolerance else { return [a, b] }
            return open(Array(values[...farthest])).dropLast() + open(Array(values[farthest...]))
        }
        let anchor = points[0]
        let split = points.indices.max { i, j in
            hypot(points[i].x - anchor.x, points[i].y - anchor.y) < hypot(points[j].x - anchor.x, points[j].y - anchor.y)
        }!
        let result = Array(open(Array(points[...split])).dropLast()) + Array(open(Array(points[split...]) + [anchor]).dropLast())
        return result.count >= 3 ? result : points
    }

    private static func validTopology(_ contours: [[FontLabPoint]]) -> Bool {
        func crosses(_ a: FontLabPoint, _ b: FontLabPoint, _ c: FontLabPoint, _ d: FontLabPoint) -> Bool {
            func side(_ p: FontLabPoint, _ q: FontLabPoint, _ r: FontLabPoint) -> Double {
                (q.x - p.x) * (r.y - p.y) - (q.y - p.y) * (r.x - p.x)
            }
            return side(a, b, c) * side(a, b, d) < -1e-14 && side(c, d, a) * side(c, d, b) < -1e-14
        }
        for (index, contour) in contours.enumerated() {
            guard abs(area(contour)) > 0.000_001 else { return false }
            for i in contour.indices {
                for j in contour.indices where j > i + 1 && !(i == 0 && j == contour.count - 1) {
                    if crosses(contour[i], contour[(i + 1) % contour.count], contour[j], contour[(j + 1) % contour.count]) { return false }
                }
            }
            if area(contour) > 0, !contours.contains(where: { area($0) < 0 && contains($0, contour[0]) }) { return false }
            for other in contours.dropFirst(index + 1) {
                for i in contour.indices {
                    for j in other.indices {
                        if crosses(contour[i], contour[(i + 1) % contour.count], other[j], other[(j + 1) % other.count]) { return false }
                    }
                }
            }
        }
        return true
    }

    private static func styled(_ contours: [[FontLabPoint]], preset: FontLabStarterPreset, baseline: Double) -> [[FontLabPoint]] {
        contours.map { contour in
            var points = simplified(contour, tolerance: 0.000_35)
            if preset == .soft {
                // Round only the corners, keeping straight stems and bowl sizes.
                points = points.indices.flatMap { i -> [FontLabPoint] in
                    let p = points[i], before = points[(i + points.count - 1) % points.count], after = points[(i + 1) % points.count]
                    let incoming = hypot(p.x - before.x, p.y - before.y), outgoing = hypot(p.x - after.x, p.y - after.y)
                    let start = interpolate(p, before, min(0.4, 0.005 / max(incoming, 0.000_001)))
                    let end = interpolate(p, after, min(0.4, 0.005 / max(outgoing, 0.000_001)))
                    return [0.0, 0.25, 0.5, 0.75, 1.0].map { t in
                        interpolate(interpolate(start, p, t), interpolate(p, end, t), t)
                    }
                }
            }
            if preset == .poster {
                points = points.indices.map { i in
                    let p = points[i], before = points[(i + points.count - 1) % points.count], after = points[(i + 1) % points.count]
                    let dx = after.x - before.x, dy = after.y - before.y
                    let length = max(0.000_001, hypot(dx, dy))
                    // Clockwise outer contours expand; counter-clockwise holes contract.
                    return FontLabPoint(x: p.x - dy / length * 0.006, y: p.y + dx / length * 0.006)
                }
            }
            return points.map { p in
                FontLabPoint(x: p.x * preset.widthScale + (p.y - baseline) * preset.slant, y: p.y)
            }
        }
    }

    private static func makeGlyph(character: String, primary: Outline?, secondary: Outline?, recipe: FontLabRemixRecipe, metrics: FontLabMetrics) -> (FontLabGlyph, Bool) {
        let a = primary ?? secondary!, b = secondary ?? primary!
        let amount = recipe.blendAmount
        var fallback = false
        let outline: Outline
        if amount <= 0 { outline = a }
        else if amount >= 1 { outline = b }
        else if a.contours == b.contours { outline = a }
        else if recipe.mode == .alternate { outline = hashUnit(character) < amount ? b : a }
        else if let contours = mixedContours(a, b, recipe: recipe) {
            outline = Outline(contours: contours, advance: mix(a.advance, b.advance, amount))
        } else {
            outline = amount < 0.5 ? a : b
            fallback = true
        }
        let contours = styled(outline.contours, preset: recipe.preset, baseline: metrics.baseline)
        let points = contours.flatMap { $0 }
        let minX = points.map(\.x).min()!, maxX = points.map(\.x).max()!
        let width = max(0.02, maxX - minX)
        let normalized = contours.map { $0.map { FontLabPoint(x: min(1, max(0, ($0.x - minX) / width)), y: min(0.998, max(0.002, $0.y))) } }
        var glyph = FontLabGlyph(character: character)
        glyph.contourDesignWidth = min(width, 3)
        glyph.leftSideBearing = min(0.4, max(0.015, minX))
        glyph.rightSideBearing = min(0.4, max(0.015, outline.advance * recipe.preset.widthScale - maxX))
        glyph.strokes = [FontLabStroke(id: stableUUID("\(character)|\(recipe.primaryPostScriptName)|\(recipe.secondaryPostScriptName)|\(recipe.blendAmount)|\(recipe.mode.rawValue)|\(recipe.preset.rawValue)|contours-v2"), contours: normalized)]
        return (glyph, fallback)
    }

    private static func mix(_ lhs: Double, _ rhs: Double, _ amount: Double) -> Double {
        lhs + (rhs - lhs) * amount
    }

    private static func hashUnit(_ text: String) -> Double {
        Double(fnv1a(text, seed: 0xcbf29ce484222325)) / Double(UInt64.max)
    }

    private static func stableUUID(_ text: String) -> UUID {
        let first = fnv1a(text, seed: 0xcbf29ce484222325)
        let second = fnv1a(text, seed: 0x84222325cbf29ce4)
        let bytes: [UInt8] = [
            UInt8(truncatingIfNeeded: first >> 56), UInt8(truncatingIfNeeded: first >> 48),
            UInt8(truncatingIfNeeded: first >> 40), UInt8(truncatingIfNeeded: first >> 32),
            UInt8(truncatingIfNeeded: first >> 24), UInt8(truncatingIfNeeded: first >> 16),
            UInt8(truncatingIfNeeded: first >> 8), UInt8(truncatingIfNeeded: first),
            UInt8(truncatingIfNeeded: second >> 56), UInt8(truncatingIfNeeded: second >> 48),
            UInt8(truncatingIfNeeded: second >> 40), UInt8(truncatingIfNeeded: second >> 32),
            UInt8(truncatingIfNeeded: second >> 24), UInt8(truncatingIfNeeded: second >> 16),
            UInt8(truncatingIfNeeded: second >> 8), UInt8(truncatingIfNeeded: second)
        ]
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    private static func fnv1a(_ text: String, seed: UInt64) -> UInt64 {
        text.utf8.reduce(seed) { hash, byte in (hash ^ UInt64(byte)) &* 1_099_511_628_211 }
    }
}
