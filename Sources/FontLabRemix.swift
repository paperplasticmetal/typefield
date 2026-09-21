import Foundation
import CoreText
import CoreGraphics

/// The local remix modes are deliberately described as vector operations, not AI.
/// They turn outlines from fonts already available to CoreText into editable Font Lab
/// strokes without copying or embedding either source font file.
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
            return "Morphs corresponding horizontal slices of both outlines."
        case .interleave:
            return "Weaves coherent slices from both source faces."
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

    fileprivate var weightScale: Double {
        switch self {
        case .clean: return 1
        case .soft: return 1.14
        case .poster: return 1.38
        case .kinetic: return 1.05
        }
    }

    fileprivate var rowCount: Int {
        switch self {
        case .poster: return 70
        default: return 82
        }
    }
}

struct FontLabRemixRecipe: Codable, Equatable {
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

    var isValid: Bool {
        (2...3).contains(sourcePostScriptNames.count) &&
            sourcePostScriptNames.allSatisfy { !$0.isEmpty && $0.count <= 300 } &&
            blendAmount.isFinite && (0...1).contains(blendAmount) &&
            !generatorName.isEmpty && generatorName.count <= 200 &&
            !distributionNotice.isEmpty && distributionNotice.count <= 2_000
    }

    var summary: String {
        "Editable local remix of \(sourcePostScriptNames.joined(separator: " + ")) · \(mode.title) \(Int((blendAmount * 100).rounded()))% · \(preset.title)"
    }
}

struct FontLabRemixResult: Equatable {
    var project: FontLabProject
    var provenance: FontLabRemixProvenance
    var skippedCharacters: [String]

    var status: String {
        let count = project.completedCount
        let skipped = skippedCharacters.isEmpty ? "" : " · \(skippedCharacters.count) unsupported"
        return "Created \(count) editable glyphs from \(provenance.sourcePostScriptNames.joined(separator: " + "))\(skipped). \(FontLabRemixProvenance.licenseNotice)"
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
                return "Neither source font contains any of the requested characters."
            }
        }
    }

    /// Generates editable horizontal strokes from two installed outline fonts.
    /// The default project ID is intentionally new for each user-created project;
    /// every glyph and stroke inside it remains deterministic for a given recipe.
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
        let metrics = FontLabMetrics()
        var project = FontLabProject(id: projectID, name: cleanedName, characters: characters)
        project.metrics = metrics
        let provenance = FontLabRemixProvenance(
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
        for character in characters {
            let primaryOutline = normalizedOutline(character: character, font: primary, metrics: metrics)
            let secondaryOutline = normalizedOutline(character: character, font: secondary, metrics: metrics)
            guard primaryOutline != nil || secondaryOutline != nil else {
                skipped.append(character)
                continue
            }

            var glyph = project.glyphs[character] ?? FontLabGlyph(character: character)
            glyph.strokes = strokes(
                character: character,
                primary: primaryOutline,
                secondary: secondaryOutline,
                recipe: recipe,
                metrics: metrics
            )
            project.glyphs[character] = glyph
        }

        guard project.completedCount > 0 else { throw RemixError.noSupportedCharacters }
        guard project.isValid else { throw RemixError.invalidCharacters }
        return FontLabRemixResult(project: project, provenance: provenance, skippedCharacters: skipped)
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
                  glyph.strokes.allSatisfy { $0.points.count == 2 && $0.isValid }
              }) else {
            throw FontLabStore.SelfTestError.failed("Deterministic Font Lab remix generation failed.")
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

        var unavailable = recipe
        unavailable.primaryPostScriptName = "FontShelf-Definitely-Missing-Face"
        do {
            _ = try generate(recipe: unavailable, characters: ["A"], projectID: id)
            throw FontLabStore.SelfTestError.failed("An unavailable Font Lab source face was accepted.")
        } catch let RemixError.unavailableFont(name) where name == "FontShelf-Definitely-Missing-Face" {
            // Expected; CoreText's silent fallback must never be mistaken for the requested face.
        }
    }

    private static func exactFont(named postScriptName: String) throws -> CTFont {
        let font = CTFontCreateWithName(postScriptName as CFString, 1_000, nil)
        guard (CTFontCopyPostScriptName(font) as String) == postScriptName else {
            throw RemixError.unavailableFont(postScriptName)
        }
        return font
    }

    private static func normalizedOutline(character: String, font: CTFont, metrics: FontLabMetrics) -> CGPath? {
        let utf16 = Array(character.utf16)
        guard utf16.count == 1 else { return nil }
        var codeUnit = utf16[0]
        var glyph = CGGlyph()
        guard CTFontGetGlyphsForCharacters(font, &codeUnit, &glyph, 1), glyph != 0,
              let path = CTFontCreatePathForGlyph(font, glyph, nil) else { return nil }

        var advance = CGSize.zero
        var mutableGlyph = glyph
        _ = CTFontGetAdvancesForGlyphs(font, .horizontal, &mutableGlyph, &advance, 1)
        let capHeight = max(Double(CTFontGetCapHeight(font)), Double(CTFontGetAscent(font)) * 0.68, 1)
        let verticalScale = (metrics.capHeight - metrics.baseline) / capHeight
        let safeAdvance = max(Double(advance.width), Double(path.boundingBoxOfPath.width), 1)
        let scale = min(verticalScale, 0.86 / safeAdvance)
        let originX = (1 - Double(advance.width) * scale) / 2
        var transform = CGAffineTransform(
            a: CGFloat(scale), b: 0,
            c: 0, d: CGFloat(scale),
            tx: CGFloat(originX), ty: CGFloat(metrics.baseline)
        )
        return path.copy(using: &transform)
    }

    private struct Interval {
        var lower: Double
        var upper: Double
    }

    private static func strokes(
        character: String,
        primary: CGPath?,
        secondary: CGPath?,
        recipe: FontLabRemixRecipe,
        metrics: FontLabMetrics
    ) -> [FontLabStroke] {
        let rows = recipe.preset.rowCount
        let columns = 104
        let rowStep = 1 / Double(rows)
        let strokeWidth = min(max(rowStep * 1.22 * recipe.preset.weightScale, 0.002), 0.2)
        var result: [FontLabStroke] = []

        for row in 0..<rows {
            let y = (Double(row) + 0.5) / Double(rows)
            let primaryIntervals = intervals(in: primary, y: y, columns: columns)
            let secondaryIntervals = intervals(in: secondary, y: y, columns: columns)
            let combined: [Interval]
            switch recipe.mode {
            case .blend:
                combined = blended(primaryIntervals, secondaryIntervals, amount: recipe.blendAmount)
            case .interleave:
                combined = interleaved(
                    primaryIntervals,
                    secondaryIntervals,
                    character: character,
                    row: row,
                    amount: recipe.blendAmount
                )
            case .alternate:
                combined = alternate(
                    primaryIntervals,
                    secondaryIntervals,
                    character: character,
                    amount: recipe.blendAmount
                )
            }

            for (intervalIndex, interval) in combined.enumerated() where interval.upper - interval.lower >= 0.002 {
                let lower = transformedX(interval.lower, y: y, metrics: metrics, preset: recipe.preset)
                let upper = transformedX(interval.upper, y: y, metrics: metrics, preset: recipe.preset)
                guard upper - lower >= 0.002 else { continue }
                var stroke = FontLabStroke()
                stroke.id = stableUUID(
                    "\(character)|\(row)|\(intervalIndex)|\(recipe.primaryPostScriptName)|\(recipe.secondaryPostScriptName)|\(recipe.blendAmount)|\(recipe.mode.rawValue)|\(recipe.preset.rawValue)"
                )
                stroke.points = [FontLabPoint(x: lower, y: y), FontLabPoint(x: upper, y: y)]
                stroke.width = strokeWidth
                result.append(stroke)
            }
        }
        return result
    }

    private static func intervals(in path: CGPath?, y: Double, columns: Int) -> [Interval] {
        guard let path else { return [] }
        var result: [Interval] = []
        var start: Int?
        for column in 0..<columns {
            let x = (Double(column) + 0.5) / Double(columns)
            let inside = path.contains(CGPoint(x: x, y: y), using: .winding, transform: .identity)
            if inside, start == nil { start = column }
            if !inside, let first = start {
                result.append(Interval(lower: Double(first) / Double(columns), upper: Double(column) / Double(columns)))
                start = nil
            }
        }
        if let first = start {
            result.append(Interval(lower: Double(first) / Double(columns), upper: 1))
        }
        return result
    }

    private static func blended(_ primary: [Interval], _ secondary: [Interval], amount: Double) -> [Interval] {
        if primary.isEmpty { return secondary }
        if secondary.isEmpty { return primary }
        let count = max(primary.count, secondary.count)
        return (0..<count).compactMap { index in
            let lhs = interval(primary, at: index, fallingBackTo: secondary)
            let rhs = interval(secondary, at: index, fallingBackTo: primary)
            let lower = mix(lhs.lower, rhs.lower, amount)
            let upper = mix(lhs.upper, rhs.upper, amount)
            return upper > lower ? Interval(lower: lower, upper: upper) : nil
        }
    }

    private static func interval(_ values: [Interval], at index: Int, fallingBackTo other: [Interval]) -> Interval {
        if index < values.count { return values[index] }
        let source = other[min(index, other.count - 1)]
        let midpoint = (source.lower + source.upper) / 2
        return Interval(lower: midpoint, upper: midpoint)
    }

    private static func interleaved(
        _ primary: [Interval],
        _ secondary: [Interval],
        character: String,
        row: Int,
        amount: Double
    ) -> [Interval] {
        if primary.isEmpty { return secondary }
        if secondary.isEmpty { return primary }
        if amount <= 0 { return primary }
        if amount >= 1 { return secondary }
        let phase = hashUnit(character)
        let sequence = (Double(row) * 0.618_033_988_75 + phase).truncatingRemainder(dividingBy: 1)
        return sequence < amount ? secondary : primary
    }

    private static func alternate(
        _ primary: [Interval],
        _ secondary: [Interval],
        character: String,
        amount: Double
    ) -> [Interval] {
        if primary.isEmpty { return secondary }
        if secondary.isEmpty { return primary }
        return hashUnit(character) < amount ? secondary : primary
    }

    private static func transformedX(_ x: Double, y: Double, metrics: FontLabMetrics, preset: FontLabStarterPreset) -> Double {
        let scaled = 0.5 + (x - 0.5) * preset.widthScale
        let slanted = scaled + (y - metrics.baseline) * preset.slant
        return min(max(slanted, 0.002), 0.998)
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
