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
        case .interleave: return "Splice"
        case .alternate: return "Alternate glyphs"
        }
    }

    var explanation: String {
        switch self {
        case .blend:
            return "Blends aligned silhouettes; retains a source shape when structures differ."
        case .interleave:
            return "Joins A’s lower shape to B’s upper shape with one smooth transition."
        case .alternate:
            return "Alternates A and B through the alphabet at 50%; the slider sets B’s share."
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
    var sourceBCharacters: [String]? = nil

    var isValid: Bool {
        (2...3).contains(sourcePostScriptNames.count) &&
            sourcePostScriptNames.allSatisfy { !$0.isEmpty && $0.count <= 300 } &&
            blendAmount.isFinite && (0...1).contains(blendAmount) &&
            !generatorName.isEmpty && generatorName.count <= 200 &&
            !distributionNotice.isEmpty && distributionNotice.count <= 2_000 &&
            (preservedCharacters.map { $0.count <= 2_000 && $0.allSatisfy { $0.count == 1 } } ?? true) &&
            (sourceBCharacters.map { $0.count <= 2_000 && $0.allSatisfy { $0.count == 1 } } ?? true)
    }

    var summary: String {
        "Editable local remix of \(sourcePostScriptNames.joined(separator: " + ")) · \(mode.title) \(Int((blendAmount * 100).rounded()))% · \(preset.title)" + ((preservedCharacters?.isEmpty == false) ? " · \(preservedCharacters!.count) glyphs retain a source shape with combined proportions" : "")
    }
}

struct FontLabRemixResult: Equatable {
    var project: FontLabProject
    var provenance: FontLabRemixProvenance
    var skippedCharacters: [String]
    var preservedCharacters: [String] = []

    var status: String {
        let count = project.completedCount
        let preserved = preservedCharacters.isEmpty ? "" : " · \(preservedCharacters.count) retain a source shape with combined proportions"
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
        case incompatibleLetterforms

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
            case .incompatibleLetterforms:
                return "These fonts use different alphabets: one draws lowercase letters as capitals. Choose Alternate glyphs, or two fonts with compatible lowercase designs."
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
        if recipe.mode != .alternate, recipe.blendAmount > 0, recipe.blendAmount < 1,
           hasCapitalOnlyLowercase(primary) != hasCapitalOnlyLowercase(secondary) {
            throw RemixError.incompatibleLetterforms
        }
        var metrics = FontLabMetrics()
        metrics.baseline = 0.24
        metrics.capHeight = 0.80
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
        var sourceB: [String] = []
        for character in characters {
            let primaryOutline = normalizedOutline(character: character, font: primary, metrics: metrics, scale: aScale)
            let secondaryOutline = normalizedOutline(character: character, font: secondary, metrics: metrics, scale: bScale)
            guard primaryOutline != nil || secondaryOutline != nil,
                  !(recipe.blendAmount <= 0 && primaryOutline == nil),
                  !(recipe.blendAmount >= 1 && secondaryOutline == nil) else {
                skipped.append(character)
                continue
            }

            let (glyph, keptSource) = makeGlyph(character: character, primary: primaryOutline,
                secondary: secondaryOutline, recipe: recipe, metrics: metrics)
            if keptSource { preserved.append(character) }
            if recipe.mode == .alternate, secondaryOutline != nil,
               primaryOutline == nil || alternateUsesB(character: character, amount: recipe.blendAmount) {
                sourceB.append(character)
            }
            project.glyphs[character] = glyph
        }

        provenance.preservedCharacters = preserved.isEmpty ? nil : preserved
        provenance.sourceBCharacters = recipe.mode == .alternate ? sourceB : nil
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
        try silhouetteSelfTest()

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
                            let selected = alternateUsesB(character: character, amount: amount) ? 1 : 0
                            guard geometry(source[selected].glyphs[character]!) == actual,
                                  result.provenance.sourceBCharacters?.contains(character) == (selected == 1) else {
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

    private static func silhouetteSelfTest() throws {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ").map(String.init)
        for amount in [0.0, 0.25, 0.5, 0.75, 1.0] {
            let selected = alphabet.filter { alternateUsesB(character: $0, amount: amount) }
            guard selected.count == Int(floor(Double(alphabet.count) * amount)) else {
                throw FontLabStore.SelfTestError.failed("Alternate glyphs did not distribute both source faces evenly.")
            }
        }
        guard alphabet.enumerated().allSatisfy({ alternateUsesB(character: $0.element, amount: 0.5) == ($0.offset % 2 == 1) }) else {
            throw FontLabStore.SelfTestError.failed("Alternate glyphs did not alternate A/B through the alphabet.")
        }
        let recipe = FontLabRemixRecipe(primaryPostScriptName: "Helvetica", secondaryPostScriptName: "Times-Roman", mode: .alternate)
        let full = try generate(recipe: recipe)
        let subset = try generate(recipe: recipe, characters: ["z", "A", "b", "M"])
        guard subset.project.glyphs.allSatisfy({ full.project.glyphs[$0.key] == $0.value }),
              try JSONDecoder().decode(FontLabProject.self, from: JSONEncoder().encode(full.project)) == full.project else {
            throw FontLabStore.SelfTestError.failed("Alternate source assignments changed with preview order or persistence.")
        }
        // An asymmetric L catches raster y-axis inversion; a matching pair of
        // Hs checks actual stem/counter occupancy after both combination modes.
        func outline(_ coords: [(Double, Double)]) -> Outline {
            let path = CGMutablePath(); path.addLines(between: coords.map { CGPoint(x: $0.0, y: $0.1) }); path.closeSubpath()
            return Outline(contours: flattened(path), advance: 0.7)
        }
        let ell = outline([(0.1,0.2),(0.6,0.2),(0.6,0.3),(0.2,0.3),(0.2,0.8),(0.1,0.8)])
        let raster = Silhouette(ell)
        let roundTrip = traced(raster.field(), bounds: raster.bounds)
        guard roundTrip.count == 1, contains(roundTrip[0], FontLabPoint(x: 0.5, y: 0.25)),
              !contains(roundTrip[0], FontLabPoint(x: 0.5, y: 0.75)) else {
            throw FontLabStore.SelfTestError.failed("Silhouette tracing flipped or lost a source outline.")
        }
        func h(_ thickness: Double) -> Outline {
            outline([(0.1,0.2),(0.1 + thickness,0.2),(0.1 + thickness,0.45),(0.6 - thickness,0.45),
                     (0.6 - thickness,0.2),(0.6,0.2),(0.6,0.8),(0.6 - thickness,0.8),
                     (0.6 - thickness,0.55),(0.1 + thickness,0.55),(0.1 + thickness,0.8),(0.1,0.8)])
        }
        for mode in [FontLabRemixMode.blend, .interleave] {
            var recipe = recipe; recipe.mode = mode
            guard let result = mixedContours(h(0.1), h(0.14), recipe: recipe), result.count == 1,
                  [0.25, 0.35, 0.65, 0.75].allSatisfy({ y in
                      contains(result[0], FontLabPoint(x: 0.15, y: y)) && contains(result[0], FontLabPoint(x: 0.55, y: y)) &&
                      !contains(result[0], FontLabPoint(x: 0.35, y: y))
                  }), contains(result[0], FontLabPoint(x: 0.35, y: 0.5)) else {
                throw FontLabStore.SelfTestError.failed("A silhouette combination bent a straight stem or filled an open counter.")
            }
        }
        let outer = outline([(0.1,0.2),(0.6,0.2),(0.6,0.8),(0.1,0.8)]).contours[0]
        let low = outline([(0.25,0.25),(0.45,0.25),(0.45,0.4),(0.25,0.4)]).contours[0].reversed()
        let high = low.map { FontLabPoint(x: $0.x, y: $0.y + 0.25) }
        guard mixedContours(Outline(contours: [outer, Array(low)], advance: 0.7),
                            Outline(contours: [outer, high], advance: 0.7), recipe: recipe) == nil else {
            throw FontLabStore.SelfTestError.failed("Equal hole counts hid incompatible counter positions.")
        }
        let scaledSources = try ["Helvetica", "Times-Roman", "Avenir-Medium"].map { name in
            try generate(recipe: FontLabRemixRecipe(primaryPostScriptName: name, secondaryPostScriptName: name), characters: ["H", "g"])
        }
        let capHeights = scaledSources.map { $0.project.glyphs["H"]!.strokes[0].contours!.flatMap { $0 }.map(\.y).max()! }
        guard capHeights.allSatisfy({ abs($0 - 0.80) < 0.003 }) else {
            throw FontLabStore.SelfTestError.failed("Source metrics shrank Latin capitals to different point sizes.")
        }
        print("PASS: balanced A/B assignment, subset stability, silhouette orientation, straight stems and incompatible counter positions.")
    }

    /// Disposable visual audit with both sources, every method and explicit
    /// fallback counts. It never opens or writes the user's saved library.
    static func writeSpecimen(to folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let pairs = [("Helvetica", "Times-Roman"), ("Helvetica", "Helvetica-Bold"),
                     ("Georgia", "Times-Roman"), ("Avenir-Medium", "Futura-Medium"),
                     ("HelveticaNeue-CondensedBold", "HelveticaNeue-Bold"),
                     ("Courier", "Helvetica"), ("AdobeClean-Black", "Futura-Bold"),
                     ("AbrilFatface-Regular", "1797-POSTER_V2"),
                     ("1797-COMPRESSED_V2", "Futura-Bold"),
                     ("AdelleSansDevanagari-Semibold", "FuturaStd-Condensed")]
        var report: [String] = []
        for (pairIndex, pair) in pairs.enumerated() {
            let amounts = pairIndex == 1 || pairIndex == 6 ? [0.25, 0.5, 0.75] : [0.5]
            for amount in amounts {
                let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1800, pixelsHigh: 1130,
                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
                NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 1800, height: 1130).fill()
                func label(_ text: String, _ y: Double, size: Double = 18) {
                    let context = NSGraphicsContext.current!.cgContext
                    context.saveGState()
                    context.textMatrix = .identity
                    context.textPosition = CGPoint(x: 24, y: y + 4)
                    let line = CTLineCreateWithAttributedString(NSAttributedString(string: text,
                        attributes: [.font: NSFont.systemFont(ofSize: size), .foregroundColor: NSColor.black]))
                    CTLineDraw(line, context)
                    context.restoreGState()
                }
                label("\(pair.0) × \(pair.1) · \(Int(amount * 100))% B · Clean", 1090, size: 24)
                let recipes = [FontLabRemixRecipe(primaryPostScriptName: pair.0, secondaryPostScriptName: pair.0),
                               FontLabRemixRecipe(primaryPostScriptName: pair.1, secondaryPostScriptName: pair.1)] +
                    FontLabRemixMode.allCases.map { FontLabRemixRecipe(primaryPostScriptName: pair.0,
                        secondaryPostScriptName: pair.1, blendAmount: amount, mode: $0) }
                for (index, recipe) in recipes.enumerated() {
                    let y = 1060.0 - Double(index) * 210
                    let title = index < 2 ? "Source \(index == 0 ? "A" : "B")" : recipe.mode.title
                    do {
                        let start = Date()
                        let result = try generate(recipe: recipe)
                        let detail = "\(title): \(result.preservedCharacters.count)/\(result.project.completedCount) source shapes retained"
                        report.append("\(pair.0) × \(pair.1) \(Int(amount * 100))% \(detail) (\(String(format: "%.3f", Date().timeIntervalSince(start)))s)")
                        label(detail, y - 15)
                        for (row, text) in ["Hamburgefontsiv 0123456789 &@", "ABCDEFGHIJKLMNOPQRSTUVWXYZ abcdefghijklmnopqrstuvwxyz"].enumerated() {
                            let height = row == 0 ? 100.0 : 74.0
                            var x = 24.0
                            for character in text.map(String.init) {
                                guard let glyph = result.project.glyphs[character] else { x += height * 0.3; continue }
                                x += glyph.leftSideBearing * height
                                fontLabDrawStrokes(glyph.strokes, in: NSRect(x: x, y: y - (row == 0 ? 115 : 195),
                                    width: glyph.resolvedDesignWidth * height, height: height), color: .black)
                                x += (glyph.resolvedDesignWidth + glyph.rightSideBearing) * height
                            }
                        }
                        if index >= 2 {
                            NSGraphicsContext.saveGraphicsState()
                            defer { NSGraphicsContext.restoreGraphicsState() }
                            try FontLabTrueTypeExporter.artifact(for: result.project).write(to:
                                folder.appendingPathComponent("pair-\(pairIndex)-\(Int(amount * 100))-\(recipe.mode.rawValue).ttf"))
                        }
                    } catch {
                        label("\(title): \(error.localizedDescription)", y - 45)
                        report.append("\(pair.0) × \(pair.1) \(title): \(error.localizedDescription)")
                    }
                }
                NSGraphicsContext.restoreGraphicsState()
                try bitmap.representation(using: .png, properties: [:])!.write(to:
                    folder.appendingPathComponent("pair-\(pairIndex)-\(Int(amount * 100)).png"))
            }
        }
        try report.joined(separator: "\n").write(to: folder.appendingPathComponent("report.txt"), atomically: true, encoding: .utf8)
        print(report.joined(separator: "\n"))
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

    // One scale per face, independent of preview subsets and glyph width.
    // Global descent metrics can include scripts far outside the Latin starter
    // (Adelle Devanagari reports 600 units). Measure the actual starter outlines
    // so those metrics do not shrink an otherwise ordinary Latin alphabet.
    private static func faceScale(_ font: CTFont, metrics: FontLabMetrics) -> Double {
        let cap = max(1, Double(CTFontGetCapHeight(font)))
        var descent = 1.0, ascent = cap
        for character in FontLabProject.starterCharacters {
            var code = Array(character.utf16)[0], glyph = CGGlyph()
            if CTFontGetGlyphsForCharacters(font, &code, &glyph, 1), glyph != 0,
               let bounds = CTFontCreatePathForGlyph(font, glyph, nil)?.boundingBoxOfPath {
                descent = max(descent, -bounds.minY)
                ascent = max(ascent, bounds.maxY)
            }
        }
        return min((metrics.capHeight - metrics.baseline) / cap,
                   (metrics.baseline - 0.012) / descent, (0.988 - metrics.baseline) / ascent)
    }

    private static func normalizedOutline(character: String, font: CTFont, metrics: FontLabMetrics, scale: Double) -> Outline? {
        let utf16 = Array(character.utf16)
        guard utf16.count == 1 else { return nil }
        var codeUnit = utf16[0]
        var glyph = CGGlyph()
        guard CTFontGetGlyphsForCharacters(font, &codeUnit, &glyph, 1), glyph != 0,
              let path = CTFontCreatePathForGlyph(font, glyph, nil) else { return nil }
        var advance = CGSize.zero
        _ = CTFontGetAdvancesForGlyphs(font, .horizontal, &glyph, &advance, 1)
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

    private struct InkBounds {
        let minX: Double
        let minY: Double
        let width: Double
        let height: Double
        init(_ contours: [[FontLabPoint]]) {
            let points = contours.flatMap { $0 }
            minX = points.map(\.x).min() ?? 0
            minY = points.map(\.y).min() ?? 0
            width = max(0.001, (points.map(\.x).max() ?? 0) - minX)
            height = max(0.001, (points.map(\.y).max() ?? 0) - minY)
        }
        init(mixing a: InkBounds, _ b: InkBounds, amount: Double) {
            minX = mix(a.minX, b.minX, amount)
            minY = mix(a.minY, b.minY, amount)
            width = mix(a.width, b.width, amount)
            height = mix(a.height, b.height, amount)
        }
    }

    private static func fitted(_ source: Outline, to bounds: InkBounds, advance: Double) -> Outline {
        let original = InkBounds(source.contours)
        return Outline(contours: source.contours.map { $0.map { p in
            FontLabPoint(x: bounds.minX + (p.x - original.minX) / original.width * bounds.width,
                         y: bounds.minY + (p.y - original.minY) / original.height * bounds.height)
        } }, advance: advance)
    }

    private struct Silhouette {
        static let size = 320
        static let padding = 12.0
        static var span: Double { Double(size) - 2 * padding }
        let coverage: [UInt8]
        let bounds: InkBounds
        init(_ outline: Outline) {
            let bounds = InkBounds(outline.contours)
            self.bounds = bounds
            var pixels = [UInt8](repeating: 0, count: Self.size * Self.size)
            let path = CGMutablePath()
            for contour in outline.contours {
                path.addLines(between: contour.map { p in
                    CGPoint(x: Self.padding + (p.x - bounds.minX) / bounds.width * Self.span,
                            y: Self.padding + (p.y - bounds.minY) / bounds.height * Self.span)
                })
                path.closeSubpath()
            }
            pixels.withUnsafeMutableBytes { bytes in
                let context = CGContext(data: bytes.baseAddress, width: Self.size, height: Self.size,
                    bitsPerComponent: 8, bytesPerRow: Self.size, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0)!
                context.setAllowsAntialiasing(true)
                context.setShouldAntialias(true)
                context.setFillColor(gray: 1, alpha: 1)
                context.addPath(path)
                context.fillPath(using: .winding)
            }
            // Core Graphics stores the top row first; geometry uses y-up.
            coverage = (0..<Self.size).flatMap { y in
                Array(pixels[((Self.size - 1 - y) * Self.size)..<((Self.size - y) * Self.size)])
            }
        }

        /// Exact separable squared Euclidean distance transform. It measures
        /// distance to ink/space without guessing which outline vertices match.
        func field() -> [Double] {
            let n = Self.size
            func transform(_ f: [Double]) -> [Double] {
                var sites = [Int](repeating: 0, count: n)
                var edges = [Double](repeating: 0, count: n + 1)
                var k = 0
                edges[0] = -.infinity; edges[1] = .infinity
                for q in 1..<n {
                    var s = 0.0
                    while true {
                        let v = sites[k]
                        s = ((f[q] + Double(q * q)) - (f[v] + Double(v * v))) / Double(2 * (q - v))
                        if s > edges[k] { break }
                        k -= 1
                    }
                    k += 1; sites[k] = q; edges[k] = s; edges[k + 1] = .infinity
                }
                k = 0
                return (0..<n).map { q in
                    while edges[k + 1] < Double(q) { k += 1 }
                    let delta = q - sites[k]
                    return Double(delta * delta) + f[sites[k]]
                }
            }
            func distances(toInk: Bool) -> [Double] {
                var values = coverage.map { ($0 >= 128) == toInk ? 0.0 : 1_000_000.0 }
                for y in 0..<n {
                    let row = transform(Array(values[(y * n)..<((y + 1) * n)]))
                    values.replaceSubrange((y * n)..<((y + 1) * n), with: row)
                }
                for x in 0..<n {
                    let column = transform((0..<n).map { values[$0 * n + x] })
                    for y in 0..<n { values[y * n + x] = column[y] }
                }
                return values
            }
            let toInk = distances(toInk: true), toSpace = distances(toInk: false)
            return coverage.indices.map { index in
                let coverage = coverage[index]
                if coverage > 0 && coverage < 255 { return Double(coverage) / 255 - 0.5 }
                return coverage >= 128 ? sqrt(toSpace[index]) - 0.5 : 0.5 - sqrt(toInk[index])
            }
        }
    }

    private static func mixedContours(_ a: Outline, _ b: Outline, recipe: FontLabRemixRecipe) -> [[FontLabPoint]]? {
        guard a.contours.count == b.contours.count,
              a.contours.filter({ area($0) > 0 }).count == b.contours.filter({ area($0) > 0 }).count else { return nil }
        let aBounds = InkBounds(a.contours), bBounds = InkBounds(b.contours)
        func counterCenters(_ outline: Outline, _ bounds: InkBounds) -> [FontLabPoint] {
            outline.contours.filter { area($0) > 0 }.map { contour in
                let hole = InkBounds([contour])
                return FontLabPoint(x: (hole.minX + hole.width / 2 - bounds.minX) / bounds.width,
                                    y: (hole.minY + hole.height / 2 - bounds.minY) / bounds.height)
            }.sorted { $0.y == $1.y ? $0.x < $1.x : $0.y < $1.y }
        }
        // A single-storey a and a double-storey a both have one counter, but
        // that counter occupies a different part of the letter. Do not morph
        // the open shoulder into the bowl and produce an 8-shaped hybrid.
        let aCounters = counterCenters(a, aBounds), bCounters = counterCenters(b, bBounds)
        guard zip(aCounters, bCounters).allSatisfy({ hypot($0.x - $1.x, $0.y - $1.y) <= 0.12 }) else { return nil }
        let lhs = Silhouette(a), rhs = Silhouette(b)
        var inkA = 0, inkB = 0, overlap = 0
        for i in lhs.coverage.indices {
            let a = lhs.coverage[i] >= 128, b = rhs.coverage[i] >= 128
            if a { inkA += 1 }; if b { inkB += 1 }; if a && b { overlap += 1 }
        }
        // Matching hole counts alone cannot distinguish m/M or n/N. Require
        // the normalized silhouettes to share most of their letter structure.
        let similarity = Double(2 * overlap) / Double(max(1, inkA + inkB))
        guard similarity >= 0.72 else { return nil }
        let af = lhs.field(), bf = rhs.field()
        let n = Silhouette.size
        let amount = recipe.blendAmount
        var field = [Double](repeating: 0, count: af.count)
        for y in 0..<n {
            var localAmount = amount
            if recipe.mode == .interleave {
                // One join in an aligned frame, not a sinusoidal displacement
                // of the stem positions. B occupies the upper part of a glyph.
                let height = (Double(y) + 0.5 - Silhouette.padding) / Silhouette.span
                let t = min(1, max(0, (height - (1 - amount) + 0.10) / 0.20))
                localAmount = t * t * (3 - 2 * t)
            }
            for x in 0..<n {
                let i = y * n + x
                field[i] = mix(af[i], bf[i], localAmount)
            }
        }
        let target = InkBounds(mixing: lhs.bounds, rhs.bounds, amount: amount)
        let contours = traced(field, bounds: target)
        let ink = field.filter { $0 > 0 }.count
        guard contours.count == a.contours.count,
              contours.filter({ area($0) > 0 }).count == a.contours.filter({ area($0) > 0 }).count,
              Double(ink) >= Double(min(inkA, inkB)) * 0.80,
              Double(ink) <= Double(max(inkA, inkB)) * 1.15,
              validTopology(contours) else { return nil }
        return contours
    }

    /// Marching squares yields closed vector contours with subpixel crossings.
    /// Shared edge IDs avoid cracks, quantized joins and contour-order matching.
    private static func traced(_ field: [Double], bounds: InkBounds) -> [[FontLabPoint]] {
        let n = Silhouette.size
        var locations: [Int: FontLabPoint] = [:]
        var neighbors: [Int: [Int]] = [:]
        for y in 0..<(n - 1) {
            for x in 0..<(n - 1) {
                let values = [field[y * n + x], field[y * n + x + 1], field[(y + 1) * n + x + 1], field[(y + 1) * n + x]]
                let mask = values.enumerated().reduce(0) { $0 | ($1.element > 0 ? 1 << $1.offset : 0) }
                if mask == 0 || mask == 15 { continue }
                let centerInside = values.reduce(0, +) > 0
                let pairs: [(Int, Int)]
                switch mask {
                case 1, 14: pairs = [(3, 0)]
                case 2, 13: pairs = [(0, 1)]
                case 3, 12: pairs = [(3, 1)]
                case 4, 11: pairs = [(1, 2)]
                case 6, 9: pairs = [(0, 2)]
                case 7, 8: pairs = [(3, 2)]
                case 5: pairs = centerInside ? [(0, 1), (2, 3)] : [(3, 0), (1, 2)]
                case 10: pairs = centerInside ? [(3, 0), (1, 2)] : [(0, 1), (2, 3)]
                default: pairs = []
                }
                func vertex(_ edge: Int) -> Int {
                    let ids = [y * n + x, n * n + y * n + x + 1, (y + 1) * n + x, n * n + y * n + x]
                    let id = ids[edge]
                    if locations[id] == nil {
                        let corners = [(Double(x), Double(y)), (Double(x + 1), Double(y)), (Double(x + 1), Double(y + 1)), (Double(x), Double(y + 1))]
                        let end = (edge + 1) % 4
                        let t = values[edge] / (values[edge] - values[end])
                        let px = mix(corners[edge].0, corners[end].0, t) + 0.5
                        let py = mix(corners[edge].1, corners[end].1, t) + 0.5
                        locations[id] = FontLabPoint(x: bounds.minX + (px - Silhouette.padding) / Silhouette.span * bounds.width,
                            y: bounds.minY + (py - Silhouette.padding) / Silhouette.span * bounds.height)
                    }
                    return id
                }
                for pair in pairs {
                    let a = vertex(pair.0), b = vertex(pair.1)
                    neighbors[a, default: []].append(b)
                    neighbors[b, default: []].append(a)
                }
            }
        }
        guard neighbors.values.allSatisfy({ $0.count == 2 }) else { return [] }
        var visited = Set<Int>()
        let path = CGMutablePath()
        for start in neighbors.keys.sorted() where !visited.contains(start) {
            var current = start, previous = -1
            var ring: [FontLabPoint] = []
            repeat {
                guard !visited.contains(current), let next = neighbors[current]?.first(where: { $0 != previous }), let point = locations[current] else { return [] }
                visited.insert(current); ring.append(point)
                previous = current; current = next
            } while current != start
            let reduced = simplified(ring, tolerance: 0.000_5)
            guard reduced.count >= 3 else { continue }
            path.addLines(between: reduced.map { CGPoint(x: $0.x, y: $0.y) }); path.closeSubpath()
        }
        return flattened(path)
    }

    /// Balanced error diffusion in the fixed character order. Unlike hashing
    /// one-byte strings, this alternates A/B at 50% and assigns every fourth
    /// glyph to B at 25%; preview subsets cannot change a glyph's assignment.
    static func alternateUsesB(character: String, amount: Double) -> Bool {
        let index = FontLabProject.starterCharacters.firstIndex(of: character) ?? Int(character.unicodeScalars.first?.value ?? 0)
        let amount = min(1, max(0, amount))
        return floor(Double(index + 1) * amount) > floor(Double(index) * amount)
    }

    private static func hasCapitalOnlyLowercase(_ font: CTFont) -> Bool {
        let probes = Array("aehmnrst")
        var matches = 0
        for character in probes {
            var code = Array(String(character).utf16)[0], upperCode = Array(String(character).uppercased().utf16)[0]
            var lower = CGGlyph(), upper = CGGlyph()
            guard CTFontGetGlyphsForCharacters(font, &code, &lower, 1), CTFontGetGlyphsForCharacters(font, &upperCode, &upper, 1),
                  let lp = CTFontCreatePathForGlyph(font, lower, nil), let up = CTFontCreatePathForGlyph(font, upper, nil) else { continue }
            if lower == upper || lp == up { matches += 1 }
        }
        return matches >= 5
    }

    private static func interpolate(_ a: FontLabPoint, _ b: FontLabPoint, _ t: Double) -> FontLabPoint {
        FontLabPoint(x: mix(a.x, b.x, t), y: mix(a.y, b.y, t))
    }

    /// Closed Ramer–Douglas–Peucker reduction. This keeps sharp corners while
    /// making the generated outlines practical to edit with a mouse.
    static func simplified(_ points: [FontLabPoint], tolerance: Double) -> [FontLabPoint] {
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
        else if recipe.mode == .alternate { outline = alternateUsesB(character: character, amount: amount) ? b : a }
        else if let contours = mixedContours(a, b, recipe: recipe) {
            outline = Outline(contours: contours, advance: mix(a.advance, b.advance, amount))
        } else {
            let bounds = InkBounds(mixing: InkBounds(a.contours), InkBounds(b.contours), amount: amount)
            outline = fitted(amount < 0.5 ? a : b, to: bounds, advance: mix(a.advance, b.advance, amount))
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
        glyph.strokes = [FontLabStroke(id: stableUUID("\(character)|\(recipe.primaryPostScriptName)|\(recipe.secondaryPostScriptName)|\(recipe.blendAmount)|\(recipe.mode.rawValue)|\(recipe.preset.rawValue)|silhouettes-v3"), contours: normalized)]
        return (glyph, fallback)
    }

    private static func mix(_ lhs: Double, _ rhs: Double, _ amount: Double) -> Double {
        lhs + (rhs - lhs) * amount
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
