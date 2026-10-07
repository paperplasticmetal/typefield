import AppKit
import CoreGraphics
import CoreText
import Foundation

/// A validated OpenType font with TrueType (`glyf`) outlines. The
/// preferred extension is deliberately `.ttf`: `.otf` is normally reserved for
/// OpenType fonts whose outlines use CFF/CFF2 data.
struct FontLabTrueTypeArtifact: Equatable {
    let data: Data
    let familyName: String
    let postScriptName: String
    let suggestedFilename: String
    let mappedCharacters: [String]
    let skippedCharacters: [String]
    let warnings: [String]

    var exportedCharacterCount: Int { mappedCharacters.count }
    var exportedArtworkCharacterCount: Int { mappedCharacters.filter { $0 != " " }.count }

    func write(to destination: URL) throws {
        try data.write(to: destination, options: .atomic)
    }
}

struct FontLabTrueTypeExportScope: Equatable {
    let mappedArtworkCharacters: [String]
    let skippedCharacters: [String]
}

struct FontLabFontValidation: Equatable {
    let familyName: String
    let postScriptName: String
    let glyphCount: Int
    let verifiedCharacters: [String]
}

struct FontLabSVGExportArtifact: Equatable {
    let character: String
    let suggestedFilename: String
    let data: Data
}

enum FontLabSVGCollectionExporter {
    /// Produces a deterministic, collision-resistant batch without touching the
    /// file system. The UI can let the user export all files or only a selection.
    static func artifacts(for project: FontLabProject, characters selection: Set<String>? = nil) -> [FontLabSVGExportArtifact] {
        project.characters.compactMap { character in
            guard selection?.contains(character) ?? true,
                  let glyph = project.resolvedGlyph(character), glyph.hasArtwork else { return nil }
            let scalars = character.unicodeScalars.map { String(format: "U+%04X", $0.value) }.joined(separator: "-")
            let readable = character.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) } ? character : "glyph"
            let filename = "\(safeFilename(project.name))-\(safeFilename(readable))-\(scalars).svg"
            return FontLabSVGExportArtifact(
                character: character,
                suggestedFilename: filename,
                data: FontLabSVGExporter.data(projectName: project.name, glyph: glyph, metrics: project.metrics)
            )
        }
    }

    private static func safeFilename(_ value: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/:\\?%*|\"<>").union(.newlines).union(.controlCharacters)
        let cleaned = value.components(separatedBy: forbidden).filter { !$0.isEmpty }.joined(separator: "-")
        return cleaned.isEmpty ? "font-lab" : String(cleaned.prefix(80))
    }
}

enum FontLabTrueTypeExporter {
    private static let unitsPerEm = 1_000
    private static let designWidth = 620
    // Outline nibs expand each centerline segment into two rails plus round
    // joins (up to roughly 56 TrueType points). Keeping at most 1,000 sampled
    // centerline points guarantees the simple-glyph UInt16 point limit even in
    // that worst case; round and marker nibs remain comfortably below it.
    private static let maximumSamplesPerGlyph = 1_000
    private static let checkSumMagic: UInt32 = 0xB1B0_AFBA

    private struct FontRevision {
        let fixed: UInt32
        let versionName: String
        let fingerprint: String
    }

    /// Only values that can change the emitted font belong in this signature.
    /// UI-only state such as preview text, import labels, stroke UUIDs, and
    /// tablet tilt must not create another install identity.
    private struct RevisionPoint: Encodable {
        let x: Double
        let y: Double
        let pressure: Double?
    }

    private struct RevisionVectorNode: Encodable {
        let point: RevisionPoint
        let incoming: RevisionPoint?
        let outgoing: RevisionPoint?
    }
    private struct RevisionVectorPath: Encodable {
        let nodes: [RevisionVectorNode]
        let closed: Bool
    }
    private struct RevisionStroke: Encodable {
        let points: [RevisionPoint]
        let width: Double
        let nibStyle: String
        let contours: [[RevisionPoint]]?
        let vectorPaths: [RevisionVectorPath]?
    }

    private struct RevisionGlyph: Encodable {
        let scalar: UInt32
        let strokes: [RevisionStroke]
        let leftSideBearing: Double
        let rightSideBearing: Double
        let designWidth: Double?
    }

    private struct RevisionProvenance: Encodable {
        let sourcePostScriptNames: [String]
        let distributionNotice: String
    }

    private struct RevisionKerning: Encodable { let left: String; let right: String; let value: Int }
    private struct RevisionPayload: Encodable {
        // Conversion changes can alter installed outlines without a project
        // edit. Give corrected exports a fresh macOS font-cache identity.
        let outlineEncodingRevision = 2
        let metrics: FontLabMetrics
        let weightClass: UInt16
        let glyphs: [RevisionGlyph]
        let provenance: RevisionProvenance?
        let kerning: [RevisionKerning]?
    }

    enum ExportError: LocalizedError, Equatable {
        case openContours(String)
        case invalidProject
        case noDrawnCharacters
        case glyphTooComplex(String)
        case valueOutOfRange(String)
        case malformedFont(String)
        case coreTextRejectedFont
        case characterMissingAfterValidation(String)
        case incompatibleMasters(String)

        var errorDescription: String? {
            switch self {
            case let .openContours(character):
                return "Close the open vector contours in \(character) before exporting the font. SVG can preserve open paths."
            case .invalidProject:
                return "The Letterform Editor project contains invalid data and cannot be exported."
            case .noDrawnCharacters:
                return "Draw at least one character before exporting an installable font."
            case let .glyphTooComplex(character):
                return "The drawing for \(character) contains too many separate strokes to export safely. Simplify or combine a few strokes and try again."
            case let .valueOutOfRange(value):
                return "The font value \(value) is outside the TrueType format's supported range."
            case let .malformedFont(reason):
                return "The generated font is malformed: \(reason)"
            case .coreTextRejectedFont:
                return "macOS CoreText rejected the generated TrueType font."
            case let .characterMissingAfterValidation(character):
                return "The generated font did not retain its mapping for \(character)."
            case let .incompatibleMasters(reason):
                return "These masters cannot make a variable font: \(reason)"
            }
        }
    }

    /// Builds an in-memory `.ttf`. It maps only single-Unicode-scalar glyphs
    /// that have artwork, plus a blank space and a visible `.notdef` glyph.
    static func artifact(for project: FontLabProject) throws -> FontLabTrueTypeArtifact {
        guard project.isValid else { throw ExportError.invalidProject }
        let activeMaster = project.masters?.first(where: { $0.id == project.activeMasterID })
        let masterName = activeMaster?.name
        let weightClass = UInt16(activeMaster?.weight ?? 400)
        var project = project.outputProject
        if let masterName { project.name += " — " + masterName }
        let mappings = mappedGlyphs(project)
        // Unsupported and unlisted glyphs are omitted by the reviewed export
        // scope. Their unfinished paths must not block the mapped characters.
        for glyph in mappings.compactMap(\.glyph) where glyph.strokes.contains(where: { $0.vectorPaths?.contains(where: { !$0.closed }) == true }) {
            throw ExportError.openContours(glyph.character)
        }
        let revision = try fontRevision(for: project, weightClass: weightClass)
        let familyName = uniqueFamilyName(project.name, projectID: project.id, fingerprint: revision.fingerprint)
        let postScriptName = sanitizedPostScriptName(familyName)
        let scope = exportScope(in: project, mappings: mappings)
        guard mappings.contains(where: { $0.glyph?.hasArtwork == true }) else { throw ExportError.noDrawnCharacters }

        var simplificationCount = 0
        // OpenType recommends .notdef, .null and CR as glyphs zero through
        // two. .null is zero-width; CR must be blank with a positive advance.
        // Project mappings therefore begin with space at GID 3.
        var glyphRecords: [GlyphRecord] = [notdefGlyph(), blankGlyph(advanceWidth: 0), blankGlyph(advanceWidth: 300)]
        glyphRecords.reserveCapacity(mappings.count + 3)
        for mapping in mappings {
            if let glyph = mapping.glyph {
                let result = try glyphRecord(glyph, metrics: project.metrics)
                simplificationCount += result.simplifiedPointCount
                glyphRecords.append(result.record)
            } else {
                glyphRecords.append(blankGlyph(advanceWidth: 300))
            }
        }

        // Keep the recommended first three glyphs meaningful: .null is GID 1
        // and CR is GID 2. Recommended control aliases do not appear in the
        // user's exported-character count, but are encoded for interoperability.
        var scalarMappings: [UInt32: UInt16] = [
            0x0000: 1, // null
            0x0008: 1, // backspace
            0x0009: 3, // horizontal tab uses the space advance
            0x000D: 2, // carriage return
            0x001D: 1, // group separator
            0x00A0: 3  // no-break space uses the space advance
        ]
        for (index, item) in mappings.enumerated() {
            scalarMappings[item.scalar] = UInt16(index + 3)
        }
        let fontData = try buildFont(
            project: project,
            familyName: familyName,
            postScriptName: postScriptName,
            revision: revision,
            glyphs: glyphRecords,
            cmap: scalarMappings,
            weightClass: weightClass
        )

        let mappedCharacters = mappings.map(\.character)
        let skipped = scope.skippedCharacters
        var warnings: [String] = []
        if !skipped.isEmpty {
            warnings.append("\(skipped.count) undrawn or unsupported character\(skipped.count == 1 ? " was" : "s were") left out. The font includes only drawn, single-scalar characters plus a blank space.")
        }
        if simplificationCount > 0 {
            warnings.append("Dense pen input was reduced by \(simplificationCount) sample\(simplificationCount == 1 ? "" : "s") while preserving the stroke path for a portable TrueType outline.")
        }
        if project.remixProvenance != nil {
            warnings.append("Font embedding is marked restricted because Typefield does not know the source fonts’ license permissions. Review both licenses before sharing or embedding this derivative font.")
        }

        let artifact = FontLabTrueTypeArtifact(
            data: fontData,
            familyName: familyName,
            postScriptName: postScriptName,
            suggestedFilename: "\(safeFilename(postScriptName)).ttf",
            mappedCharacters: mappedCharacters,
            skippedCharacters: skipped,
            warnings: warnings
        )
        _ = try validate(artifact)
        return artifact
    }

    @discardableResult
    static func write(_ project: FontLabProject, to destination: URL) throws -> FontLabTrueTypeArtifact {
        let artifact = try artifact(for: project)
        try artifact.write(to: destination)
        return artifact
    }

    /// A real two-endpoint `wght` font. The lower-weight master is the default
    /// `glyf` instance; `gvar` moves its corresponding outline and phantom
    /// points to the upper-weight master. No saved project data is rewritten.
    static func variableArtifact(for original: FontLabProject) throws -> FontLabTrueTypeArtifact {
        guard original.isValid else { throw ExportError.invalidProject }
        var snapshot = original
        snapshot.captureActiveMaster()
        guard let masters = snapshot.masters, masters.count == 2 else {
            throw ExportError.incompatibleMasters("Create exactly two masters with different weights. Export additional designs as static fonts.")
        }
        let endpoints = masters.sorted { $0.weight < $1.weight }
        guard endpoints[0].weight < endpoints[1].weight else {
            throw ExportError.incompatibleMasters("The master weights must be different.")
        }
        guard endpoints[0].metrics == endpoints[1].metrics else {
            throw ExportError.incompatibleMasters("Vertical metrics differ. Match the masters’ metrics before export.")
        }
        func output(_ master: FontLabMaster) -> FontLabProject {
            var copy = snapshot
            copy.glyphs = master.glyphs; copy.metrics = master.metrics
            copy.kerningGroups = master.groups; copy.kerningPairs = master.pairs
            return copy.outputProject
        }
        let light = output(endpoints[0]), heavy = output(endpoints[1])
        let lowerMappings = mappedGlyphs(light), upperMappings = mappedGlyphs(heavy)
        guard lowerMappings.map(\.scalar) == upperMappings.map(\.scalar) else {
            throw ExportError.incompatibleMasters("Draw the same supported characters in both masters. Missing artwork cannot be interpolated.")
        }
        guard lowerMappings.contains(where: { $0.glyph?.hasArtwork == true }) else { throw ExportError.noDrawnCharacters }
        let mappedCharacters = Set(lowerMappings.map(\.character))
        guard try light.resolvedKerning(characters: mappedCharacters) == heavy.resolvedKerning(characters: mappedCharacters) else {
            throw ExportError.incompatibleMasters("Kerning differs between masters. Variable kerning is not exported; match the pairs or export static fonts.")
        }

        var lowerRecords = [notdefGlyph(), blankGlyph(advanceWidth: 0), blankGlyph(advanceWidth: 300)]
        var upperRecords = lowerRecords
        for (lower, upper) in zip(lowerMappings, upperMappings) {
            if let lowerGlyph = lower.glyph, let upperGlyph = upper.glyph {
                let pair = try compatibleGlyphRecords(lowerGlyph, upperGlyph, metrics: light.metrics)
                lowerRecords.append(pair.0); upperRecords.append(pair.1)
            } else {
                lowerRecords.append(blankGlyph(advanceWidth: 300))
                upperRecords.append(blankGlyph(advanceWidth: 300))
            }
        }

        let weight0 = UInt16(endpoints[0].weight), weight1 = UInt16(endpoints[1].weight)
        let defaultRevision = try fontRevision(for: light, weightClass: weight0)
        var identity = BigEndianWriter()
        identity.bytes(Data(defaultRevision.fingerprint.utf8))
        for (master, records) in zip(endpoints, [lowerRecords, upperRecords]) {
            identity.uint16(UInt16(master.weight))
            identity.bytes(Data(master.name.utf8)); identity.uint8(0)
            for record in records { identity.uint32(UInt32(truncatingIfNeeded: record.advanceWidth)); identity.bytes(record.data) }
        }
        let hash = identity.data.reduce(UInt64(0xcbf29ce484222325)) { ($0 ^ UInt64($1)) &* 1_099_511_628_211 }
        let revision = FontRevision(fixed: defaultRevision.fixed, versionName: defaultRevision.versionName,
                                    fingerprint: String(format: "%016llX", locale: Locale(identifier: "en_US_POSIX"), hash))
        let familyName = uniqueFamilyName(original.name, projectID: original.id, fingerprint: revision.fingerprint)
        let postScriptName = sanitizedPostScriptName(familyName)
        var scalarMappings: [UInt32: UInt16] = [0x0000: 1, 0x0008: 1, 0x0009: 3, 0x000D: 2, 0x001D: 1, 0x00A0: 3]
        for (index, item) in lowerMappings.enumerated() { scalarMappings[item.scalar] = UInt16(index + 3) }
        let data = try buildFont(
            project: light, familyName: familyName, postScriptName: postScriptName,
            revision: revision, glyphs: lowerRecords, cmap: scalarMappings, weightClass: weight0,
            extraTables: [
                Table(tag: "STAT", data: statTable(weight0: weight0, weight1: weight1, defaultIsRegular: endpoints[0].name.lowercased() == "regular")),
                Table(tag: "fvar", data: fvarTable(weight0: weight0, weight1: weight1)),
                Table(tag: "gvar", data: try gvarTable(defaultGlyphs: lowerRecords, upperGlyphs: upperRecords))
            ],
            variableStyleName: endpoints[0].name,
            extraNames: [(256, "Weight"), (257, endpoints[0].name), (258, endpoints[1].name)]
        )
        let scope = exportScope(in: light, mappings: lowerMappings)
        var warnings: [String] = ["Kerning is the same at every weight; only compatible outlines and advance widths interpolate."]
        if !scope.skippedCharacters.isEmpty {
            warnings.append("\(scope.skippedCharacters.count) undrawn or unsupported characters were omitted from both masters.")
        }
        if original.remixProvenance != nil {
            warnings.append("Font embedding is marked restricted because Typefield does not know the source fonts’ license permissions. Review both licenses before sharing or embedding this derivative font.")
        }
        let artifact = FontLabTrueTypeArtifact(data: data, familyName: familyName, postScriptName: postScriptName,
                                               suggestedFilename: "\(safeFilename(postScriptName))-Variable.ttf",
                                               mappedCharacters: lowerMappings.map(\.character),
                                               skippedCharacters: scope.skippedCharacters, warnings: warnings)
        _ = try validate(artifact)
        return artifact
    }

    @discardableResult
    static func writeVariable(_ project: FontLabProject, to destination: URL) throws -> FontLabTrueTypeArtifact {
        let artifact = try variableArtifact(for: project)
        try artifact.write(to: destination)
        return artifact
    }

    /// Uses the same CoreText/Quartz font stack that macOS applications and
    /// Font Book use to parse the generated binary, then verifies every cmap.
    static func validate(_ artifact: FontLabTrueTypeArtifact) throws -> FontLabFontValidation {
        guard let provider = CGDataProvider(data: artifact.data as CFData),
              let graphicsFont = CGFont(provider) else { throw ExportError.coreTextRejectedFont }
        let font = CTFontCreateWithGraphicsFont(graphicsFont, 18, nil, nil)
        let characterSet = CTFontCopyCharacterSet(font)
        for character in artifact.mappedCharacters {
            guard let scalar = singleScalar(character),
                  CFCharacterSetIsLongCharacterMember(characterSet, scalar.value) else {
                throw ExportError.characterMissingAfterValidation(character)
            }
        }
        let reportedFamily = (CTFontCopyFamilyName(font) as String?) ?? artifact.familyName
        let reportedPostScript = (CTFontCopyPostScriptName(font) as String?) ?? artifact.postScriptName
        guard graphicsFont.numberOfGlyphs >= artifact.mappedCharacters.count + 3 else {
            throw ExportError.coreTextRejectedFont
        }
        return FontLabFontValidation(
            familyName: reportedFamily,
            postScriptName: reportedPostScript,
            glyphCount: graphicsFont.numberOfGlyphs,
            verifiedCharacters: artifact.mappedCharacters
        )
    }

    /// Exercises binary determinism, BMP and supplementary-plane cmap entries,
    /// table checksums, metric preservation, batch SVG naming, disk writing, and
    /// CoreText parsing. All fixtures are temporary.
    static func selfTest() throws {
        var project = FontLabProject(
            id: UUID(uuidString: "5F111111-2222-4333-8444-555555555555")!,
            name: "Letterform Editor Export Test",
            characters: ["A", "x", "é", "😀", "Z"]
        )
        let diagonal = FontLabStroke(
            id: UUID(uuidString: "A1111111-2222-4333-8444-555555555555")!,
            points: [FontLabPoint(x: 0.12, y: 0.2), FontLabPoint(x: 0.5, y: 0.82), FontLabPoint(x: 0.88, y: 0.2)],
            width: 0.05,
            nibStyle: .round
        )
        let crossbar = FontLabStroke(
            id: UUID(uuidString: "B1111111-2222-4333-8444-555555555555")!,
            points: [FontLabPoint(x: 0.3, y: 0.46), FontLabPoint(x: 0.7, y: 0.46)],
            width: 0.04,
            nibStyle: .marker
        )
        project.glyphs["A"]?.strokes = [diagonal, crossbar]
        project.glyphs["x"]?.strokes = [diagonal]
        project.glyphs["é"]?.strokes = [diagonal]
        var supplementaryStroke = diagonal
        supplementaryStroke.nibStyle = .outline
        project.glyphs["😀"]?.strokes = [supplementaryStroke]

        let first = try artifact(for: project)
        let second = try artifact(for: project)
        guard first == second else { throw ExportError.malformedFont("repeated exports were not deterministic") }
        guard first.suggestedFilename.hasSuffix(".ttf"), !first.suggestedFilename.hasSuffix(".otf") else {
            throw ExportError.malformedFont("the TrueType flavor was given a misleading extension")
        }
        guard first.postScriptName.contains("-5F111111-") else {
            throw ExportError.malformedFont("the installable font identity is not tied to its project")
        }
        guard first.mappedCharacters == [" ", "A", "x", "é", "😀"], first.skippedCharacters == ["Z"] else {
            throw ExportError.malformedFont("the drawn-character export policy changed")
        }
        let scope = exportScope(for: project)
        guard scope.mappedArtworkCharacters == ["A", "x", "é", "😀"],
              scope.skippedCharacters == first.skippedCharacters,
              first.exportedArtworkCharacterCount == scope.mappedArtworkCharacters.count else {
            throw ExportError.malformedFont("the export review scope disagreed with the generated font")
        }
        let decomposed = "e\u{301}"
        var limited = FontLabProject(name: "Limited mapping", characters: ["A", decomposed, "Z"])
        limited.glyphs["A"]?.strokes = [diagonal]
        limited.glyphs[decomposed]?.strokes = [diagonal]
        var orphan = FontLabGlyph(character: "Q")
        orphan.strokes = [diagonal]
        limited.glyphs["Q"] = orphan
        let limitedScope = exportScope(for: limited)
        guard limited.completedCount == 2,
              limitedScope.mappedArtworkCharacters == ["A"],
              limitedScope.skippedCharacters == [decomposed, "Z"] else {
            throw ExportError.malformedFont("the export review counted an orphan or unsupported glyph")
        }
        let unfinished = FontLabStroke(vectorPaths: [FontLabVectorPath(nodes: [
            .init(point: .init(x: 0.2, y: 0.3)), .init(point: .init(x: 0.7, y: 0.8))
        ])])
        limited.glyphs[decomposed]?.strokes = [unfinished]
        limited.glyphs["Q"]?.strokes = [unfinished]
        let limitedArtifact = try artifact(for: limited)
        guard limitedArtifact.mappedCharacters == [" ", "A"], limitedArtifact.skippedCharacters == [decomposed, "Z"] else {
            throw ExportError.malformedFont("omitted unfinished artwork changed the reviewed export scope")
        }
        limited.glyphs["A"]?.strokes = [unfinished]
        do {
            _ = try artifact(for: limited)
            throw ExportError.malformedFont("an open contour in a mapped character was accepted")
        } catch ExportError.openContours("A") { }
        let validation = try validate(first)
        guard validation.glyphCount == 8, validation.verifiedCharacters == first.mappedCharacters else {
            throw ExportError.malformedFont("CoreText returned unexpected glyph metadata")
        }
        try verifyDirectoryAndChecksums(first.data)
        try verifyMetricTables(first.data, project: project)
        try verifyRequiredControlGlyphs(first.data)
        try verifyNameRecords(first.data)

        var sameName = project
        sameName.id = UUID(uuidString: "6F111111-2222-4333-8444-555555555555")!
        let sameNameArtifact = try artifact(for: sameName)
        guard sameNameArtifact.familyName != first.familyName,
              sameNameArtifact.postScriptName != first.postScriptName else {
            throw ExportError.malformedFont("two projects with the same display name produced a conflicting install identity")
        }
        var editedVersion = project
        editedVersion.glyphs["A"]?.strokes[0].width = 0.051
        let editedArtifact = try artifact(for: editedVersion)
        guard editedArtifact.familyName != first.familyName,
              editedArtifact.postScriptName != first.postScriptName,
              editedArtifact.data != first.data,
              tableData("head", in: editedArtifact.data).map({ readUInt32($0, 4) }) == 0x0001_0000,
              tableData("head", in: first.data).map({ readUInt32($0, 4) }) == 0x0001_0000 else {
            throw ExportError.malformedFont("an edited re-export did not receive a distinct content identity")
        }
        var previewOnlyEdit = project
        previewOnlyEdit.previewText = "This text is not part of the exported font."
        guard try artifact(for: previewOnlyEdit) == first else {
            throw ExportError.malformedFont("preview-only state changed the installable font identity")
        }

        var emojiNamed = project
        emojiNamed.id = UUID(uuidString: "9F111111-2222-4333-8444-555555555555")!
        emojiNamed.name = "Font 😀 Lab"
        let emojiNamedArtifact = try artifact(for: emojiNamed)
        try verifyNameRecords(emojiNamedArtifact.data, fullRepertoireNameIDs: [1, 4])
        guard emojiNamedArtifact.familyName.contains("😀") else {
            throw ExportError.malformedFont("a supplementary character was lost from the family name")
        }

        var denseOutline = FontLabProject(
            id: UUID(uuidString: "7F111111-2222-4333-8444-555555555555")!,
            name: "Dense Outline",
            characters: ["O"]
        )
        let densePoints = (0..<1_050).map { index -> FontLabPoint in
            let progress = Double(index) / 1_049
            return FontLabPoint(x: 0.05 + progress * 0.9, y: 0.5 + sin(progress * .pi * 8) * 0.18)
        }
        denseOutline.glyphs["O"]?.strokes = [FontLabStroke(points: densePoints, width: 0.025, nibStyle: .outline)]
        let denseArtifact = try artifact(for: denseOutline)
        guard denseArtifact.warnings.contains(where: { $0.contains("reduced by 50 samples") }) else {
            throw ExportError.malformedFont("dense outline input was not reduced to a safe TrueType point budget")
        }
        try verifyMetricTables(denseArtifact.data, project: denseOutline)

        // A long stroke beside many short strokes previously consumed their
        // endpoint budgets, silently exporting hundreds of lines as dots.
        let shortStroke = FontLabStroke(points: [.init(x: 0.1, y: 0.2), .init(x: 0.8, y: 0.8)])
        let longStroke = FontLabStroke(points: (0..<1_000).map { index in
            FontLabPoint(x: 0.1 + Double(index) / 1_000 * 0.7, y: 0.5)
        })
        let mixedGlyph = FontLabGlyph(character: "M", strokes: Array(repeating: shortStroke, count: 450) + [longStroke])
        let mixedSamples = try sampledStrokes(mixedGlyph)
        guard mixedSamples.strokes.count == mixedGlyph.strokes.count,
              mixedSamples.strokes.reduce(0, { $0 + $1.points.count }) == maximumSamplesPerGlyph,
              zip(mixedSamples.strokes, mixedGlyph.strokes).allSatisfy({ sample, original in
                  sample.points.first == original.points.first && sample.points.last == original.points.last
              }) else {
            throw ExportError.malformedFont("dense pen export lost a stroke endpoint")
        }
        let overBudget = FontLabGlyph(character: "M", strokes: Array(repeating: shortStroke, count: 501))
        do {
            _ = try sampledStrokes(overBudget)
            throw ExportError.malformedFont("an impossible endpoint budget silently damaged pen strokes")
        } catch ExportError.glyphTooComplex("M") { }

        var remixed = project
        remixed.id = UUID(uuidString: "8F111111-2222-4333-8444-555555555555")!
        remixed.remixProvenance = FontLabRemixProvenance(
            sourcePostScriptNames: ["Helvetica", "Times-Roman"],
            blendAmount: 0.5,
            mode: .blend,
            preset: .soft
        )
        let remixedArtifact = try artifact(for: remixed)
        try verifyMetricTables(remixedArtifact.data, project: remixed)
        guard remixedArtifact.warnings.contains(where: { $0.contains("embedding is marked restricted") }) else {
            throw ExportError.malformedFont("a derivative export did not disclose its conservative embedding permission")
        }

        let batch = FontLabSVGCollectionExporter.artifacts(for: project)
        guard batch.map(\.character) == ["A", "x", "é", "😀"],
              Set(batch.map(\.suggestedFilename)).count == batch.count,
              batch.allSatisfy({ $0.suggestedFilename.hasSuffix(".svg") && !$0.data.isEmpty }) else {
            throw ExportError.malformedFont("batch SVG planning was not deterministic")
        }

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("FontShelf-TTFExport-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
        try? FileManager.default.removeItem(at: root)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let output = root.appendingPathComponent(first.suggestedFilename)
        let secondOutput = root.appendingPathComponent(sameNameArtifact.suggestedFilename)
        try first.write(to: output)
        try sameNameArtifact.write(to: secondOutput)
        guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(output as CFURL) as? [CTFontDescriptor],
              descriptors.count == 1 else { throw ExportError.coreTextRejectedFont }
        let registeredFirst = CTFontManagerRegisterFontsForURL(output as CFURL, .process, nil)
        defer { if registeredFirst { CTFontManagerUnregisterFontsForURL(output as CFURL, .process, nil) } }
        let registeredSecond = CTFontManagerRegisterFontsForURL(secondOutput as CFURL, .process, nil)
        defer { if registeredSecond { CTFontManagerUnregisterFontsForURL(secondOutput as CFURL, .process, nil) } }
        let availableNames = Set((CTFontManagerCopyAvailablePostScriptNames() as? [String]) ?? [])
        guard registeredFirst, registeredSecond,
              availableNames.contains(first.postScriptName),
              availableNames.contains(sameNameArtifact.postScriptName) else {
            throw ExportError.malformedFont("same-display-name fonts could not be registered and resolved independently")
        }
        try variableSelfTest()
        try compoundWindingSelfTest()
    }

    private static func variableSelfTest() throws {
        func expectRejected(_ project: FontLabProject, reason: String) throws {
            do {
                _ = try variableArtifact(for: project)
                throw ExportError.malformedFont("incompatible \(reason) masters were accepted")
            } catch ExportError.incompatibleMasters { }
        }
        var project = FontLabProject(id: UUID(uuidString: "D1111111-2222-4333-8444-555555555555")!,
                                     name: "Variable export test", characters: ["A", "O", "Z"])
        let outline = FontLabVectorMath.rectangle(CGRect(x: 0.12, y: 0.2, width: 0.5, height: 0.6), ellipse: true)
        project.glyphs["A"] = FontLabGlyph(character: "A", strokes: [FontLabStroke(vectorPaths: [outline])], contourDesignWidth: 0.62)
        let outer = FontLabVectorMath.rectangle(CGRect(x: 0.1, y: 0.16, width: 0.68, height: 0.66), ellipse: true)
        var inner = FontLabVectorMath.rectangle(CGRect(x: 0.28, y: 0.32, width: 0.32, height: 0.34), ellipse: true)
        inner.reverse()
        project.glyphs["O"] = FontLabGlyph(character: "O", strokes: [FontLabStroke(vectorPaths: [outer, inner])], contourDesignWidth: 0.62)
        project.addMaster(name: "Bold", weight: 700)
        let lightID = project.masters![0].id
        project.glyphs["A"]?.strokes[0].vectorPaths?[0].nodes[0].point.x += 0.04
        project.glyphs["A"]?.rightSideBearing += 0.07
        project.glyphs["O"]?.strokes[0].vectorPaths?[0].nodes[0].point.x += 0.04
        let untouched = project
        let artifact = try variableArtifact(for: project)
        guard try variableArtifact(for: project) == artifact, project == untouched,
              artifact.mappedCharacters == [" ", "A", "O"], artifact.skippedCharacters == ["Z"],
              tableData("fvar", in: artifact.data) != nil,
              tableData("STAT", in: artifact.data) != nil,
              tableData("gvar", in: artifact.data) != nil else {
            throw ExportError.malformedFont("variable export was nondeterministic, rewrote the project, or omitted required variation data")
        }
        if let fixturePath = ProcessInfo.processInfo.environment["TYPEFIELD_VARIABLE_TEST_OUTPUT"] {
            try artifact.write(to: URL(fileURLWithPath: fixturePath))
        }
        try verifyDirectoryAndChecksums(artifact.data)
        try verifyRequiredControlGlyphs(artifact.data)
        let provider = CGDataProvider(data: artifact.data as CFData)!
        let font = CTFontCreateWithGraphicsFont(CGFont(provider)!, 1_000, nil, nil)
        let axes = CTFontCopyVariationAxes(font) as? [[String: Any]] ?? []
        guard axes.count == 1,
              axes[0][kCTFontVariationAxisIdentifierKey as String] as? Int == 0x77676874,
              axes[0][kCTFontVariationAxisMinimumValueKey as String] as? Double == 400,
              axes[0][kCTFontVariationAxisDefaultValueKey as String] as? Double == 400,
              axes[0][kCTFontVariationAxisMaximumValueKey as String] as? Double == 700 else {
            throw ExportError.malformedFont("CoreText did not expose the 400–700 weight axis")
        }
        func instance(_ weight: Int) -> CTFont {
            let variation: [NSNumber: NSNumber] = [NSNumber(value: 0x77676874): NSNumber(value: weight)]
            let attributes: [CFString: Any] = [kCTFontVariationAttribute: variation]
            let descriptor = CTFontDescriptorCreateWithAttributes(attributes as CFDictionary)
            return CTFontCreateCopyWithAttributes(font, 1_000, nil, descriptor)
        }
        func glyph(_ character: UniChar, in font: CTFont) throws -> (CGRect, CGFloat) {
            var character = character, glyphID: CGGlyph = 0, advance = CGSize.zero
            guard CTFontGetGlyphsForCharacters(font, &character, &glyphID, 1),
                  let path = CTFontCreatePathForGlyph(font, glyphID, nil) else {
                throw ExportError.malformedFont("CoreText could not render a variable glyph")
            }
            _ = CTFontGetAdvancesForGlyphs(font, .horizontal, &glyphID, &advance, 1)
            return (path.boundingBoxOfPath, advance.width)
        }
        let a400 = try glyph(65, in: instance(400)), a550 = try glyph(65, in: instance(550)), a700 = try glyph(65, in: instance(700))
        guard a700.0 != a400.0, a550.0 != a400.0, a550.0 != a700.0,
              a400.1 < a550.1, a550.1 < a700.1 else {
            throw ExportError.malformedFont("CoreText did not interpolate outlines and advance widths across the weight axis")
        }
        let o400 = try glyph(79, in: instance(400)), o700 = try glyph(79, in: instance(700))
        guard o400.0 != o700.0 else { throw ExportError.malformedFont("the counter glyph did not vary") }
        var changed = project
        changed.glyphs["A"]?.strokes[0].vectorPaths?[0].nodes[0].point.x += 0.01
        guard try variableArtifact(for: changed).postScriptName != artifact.postScriptName else {
            throw ExportError.malformedFont("a master edit reused the variable font identity")
        }
        var wrongNodes = project
        wrongNodes.glyphs["A"]?.strokes[0].vectorPaths?[0].insertNode(segment: 0, t: 0.5)
        try expectRejected(wrongNodes, reason: "node-count")
        var reversed = project
        reversed.glyphs["O"]?.strokes[0].vectorPaths?[1].reverse()
        try expectRejected(reversed, reason: "winding")
        var missing = project
        missing.glyphs["O"]?.strokes = []
        try expectRejected(missing, reason: "missing-glyph")
        var wrongMetrics = project
        wrongMetrics.metrics.baseline += 0.01
        try expectRejected(wrongMetrics, reason: "vertical-metric")
        var wrongKerning = project
        wrongKerning.kerningPairs = [FontLabKerningPair(left: "A", right: "O", value: -20)]
        try expectRejected(wrongKerning, reason: "kerning")
        var sameWeight = project
        sameWeight.masters?[0].weight = 700
        try expectRejected(sameWeight, reason: "same-weight")
        var three = project
        three.addMaster(name: "Black", weight: 900)
        try expectRejected(three, reason: "three-master")
        var inactiveEdit = project
        inactiveEdit.switchMaster(lightID)
        guard try variableArtifact(for: inactiveEdit) == artifact else {
            throw ExportError.malformedFont("switching the active master changed variable export")
        }
    }

    private static func compoundWindingSelfTest() throws {
        var project = FontLabProject(name: "Independent fill export", characters: ["A", "O"])
        let left = FontLabVectorMath.rectangle(CGRect(x: 0.1, y: 0.2, width: 0.6, height: 0.6), ellipse: false)
        var right = FontLabVectorMath.rectangle(CGRect(x: 0.4, y: 0.2, width: 0.5, height: 0.6), ellipse: false)
        right.reverse()
        let containedPen = FontLabStroke(points: [.init(x: 0.45, y: 0.5), .init(x: 0.55, y: 0.5)], width: 0.05)
        project.glyphs["A"]?.strokes = [FontLabStroke(vectorPaths: [left]), FontLabStroke(vectorPaths: [right]), containedPen]
        let outer = FontLabVectorMath.rectangle(CGRect(x: 0.1, y: 0.2, width: 0.8, height: 0.6), ellipse: false)
        var inner = FontLabVectorMath.rectangle(CGRect(x: 0.3, y: 0.35, width: 0.4, height: 0.3), ellipse: false)
        inner.reverse()
        project.glyphs["O"]?.strokes = [FontLabStroke(vectorPaths: [outer, inner])]

        func matchesPreview(_ data: Data, project: FontLabProject, weight: Int? = nil) throws {
            let base = CTFontCreateWithGraphicsFont(CGFont(CGDataProvider(data: data as CFData)!)!, 1_000, nil, nil)
            let font: CTFont
            if let weight {
                let variation: [NSNumber: NSNumber] = [NSNumber(value: 0x77676874): NSNumber(value: weight)]
                let descriptor = CTFontDescriptorCreateWithAttributes([kCTFontVariationAttribute: variation] as CFDictionary)
                font = CTFontCreateCopyWithAttributes(base, 1_000, nil, descriptor)
            } else { font = base }
            for character in project.characters {
                let glyph = project.glyphs[character]!
                var code = character.utf16.first!, glyphID: CGGlyph = 0
                guard CTFontGetGlyphsForCharacters(font, &code, &glyphID, 1), let actual = CTFontCreatePathForGlyph(font, glyphID, nil) else {
                    throw ExportError.malformedFont("independent fill fixture did not render")
                }
                let strokes = glyph.strokes.compactMap { stroke -> CGPath? in
                    guard let paths = stroke.vectorPaths else { return nil }
                    let compound = CGMutablePath(); paths.forEach { compound.addPath($0.cgPath) }; return compound
                }
                var intersection = 0, union = 0
                for y in 0..<96 { for x in 0..<96 {
                    let px = (Double(x) + 0.5) / 96, py = (Double(y) + 0.5) / 96
                    // The test pen is entirely inside the rectangles, so the
                    // source-stroke union is represented by these vector fills.
                    let expected = strokes.contains { $0.contains(CGPoint(x: px * 1000, y: py * 1000)) }
                    let rendered = actual.contains(CGPoint(x: (glyph.leftSideBearing + px * glyph.resolvedDesignWidth) * 1000,
                                                          y: (py - project.metrics.baseline) * 1000))
                    if expected && rendered { intersection += 1 }
                    if expected || rendered { union += 1 }
                } }
                guard union > 0, Double(intersection) / Double(union) > 0.995 else {
                    throw ExportError.malformedFont("\(character) changed independent stroke fill or a counter in native TrueType rendering")
                }
            }
            guard let maxp = tableData("maxp", in: data), readUInt16(maxp, 6) <= 48 else {
                throw ExportError.malformedFont("simple compound normalization produced excessive export points")
            }
        }
        let original = project
        let staticArtifact = try artifact(for: project)
        try matchesPreview(staticArtifact.data, project: project)
        project.addMaster(name: "Bold", weight: 700)
        project.glyphs["A"]?.strokes[0].vectorPaths?[0].nodes[0].point.x += 0.03
        let variable = try variableArtifact(for: project)
        try matchesPreview(variable.data, project: original, weight: 400)
        try matchesPreview(variable.data, project: project, weight: 700)

        var ambiguous = project
        let first = FontLabVectorMath.rectangle(CGRect(x: 0.05, y: 0.25, width: 0.25, height: 0.5), ellipse: false)
        var second = FontLabVectorMath.rectangle(CGRect(x: 0.65, y: 0.25, width: 0.25, height: 0.5), ellipse: false)
        second.reverse()
        let mixed = FontLabGlyph(character: "A", strokes: [FontLabStroke(vectorPaths: [first, second])])
        ambiguous.glyphs["A"] = mixed
        ambiguous.masters?[0].glyphs["A"] = mixed
        do {
            _ = try variableArtifact(for: ambiguous)
            throw ExportError.malformedFont("ambiguous compound winding was accepted for variable interpolation")
        } catch ExportError.incompatibleMasters { }
        print("PASS: native static and variable independent stroke fills, reversed outer contours, counters, pen overlap and bounded export points.")
    }

    // MARK: - Character selection

    private struct MappedGlyph {
        let character: String
        let scalar: UInt32
        let glyph: FontLabGlyph?
    }

    static func exportScope(for project: FontLabProject) -> FontLabTrueTypeExportScope {
        let output = project.outputProject
        return exportScope(in: output, mappings: mappedGlyphs(output))
    }

    private static func exportScope(in project: FontLabProject, mappings: [MappedGlyph]) -> FontLabTrueTypeExportScope {
        let mapped = Set(mappings.map(\.character))
        return FontLabTrueTypeExportScope(
            mappedArtworkCharacters: mappings.compactMap { $0.glyph == nil ? nil : $0.character },
            skippedCharacters: project.characters.filter { !mapped.contains($0) }
        )
    }

    private static func mappedGlyphs(_ project: FontLabProject) -> [MappedGlyph] {
        var byScalar: [UInt32: MappedGlyph] = [0x20: MappedGlyph(character: " ", scalar: 0x20, glyph: nil)]
        for character in project.characters {
            guard character != " ", let glyph = project.glyphs[character], glyph.hasArtwork,
                  let scalar = singleScalar(character), scalar.value != 0x000D,
                  isSupportedScalar(scalar.value) else { continue }
            if byScalar[scalar.value] == nil {
                byScalar[scalar.value] = MappedGlyph(character: character, scalar: scalar.value, glyph: glyph)
            }
        }
        return byScalar.values.sorted { $0.scalar < $1.scalar }
    }

    private static func singleScalar(_ character: String) -> Unicode.Scalar? {
        let scalars = character.unicodeScalars
        guard scalars.count == 1 else { return nil }
        return scalars.first
    }

    private static func isSupportedScalar(_ value: UInt32) -> Bool {
        value >= 0x20 && value != 0x00A0 && !(0x7F...0x9F).contains(value) && value <= 0x10_FFFF && !(0xD800...0xDFFF).contains(value) &&
            value & 0xFFFF != 0xFFFE && value & 0xFFFF != 0xFFFF
    }

    // MARK: - Outline conversion

    private struct TTPoint: Equatable {
        var x: Int
        var y: Int
    }

    private struct GlyphRecord {
        let data: Data
        let advanceWidth: Int
        let leftSideBearing: Int
        let xMin: Int
        let yMin: Int
        let xMax: Int
        let yMax: Int
        let pointCount: Int
        let contourCount: Int
        let contours: [[TTPoint]]
    }

    private static func blankGlyph(advanceWidth: Int) -> GlyphRecord {
        GlyphRecord(data: Data(), advanceWidth: advanceWidth, leftSideBearing: 0, xMin: 0, yMin: 0, xMax: 0, yMax: 0, pointCount: 0, contourCount: 0, contours: [])
    }

    private static func notdefGlyph() -> GlyphRecord {
        let outer = rectangle(x0: 50, y0: -40, x1: 550, y1: 700, clockwise: true)
        let inner = rectangle(x0: 120, y0: 30, x1: 480, y1: 630, clockwise: false)
        return try! glyphRecord(contours: [outer, inner], advanceWidth: 600)
    }

    private static func glyphRecord(_ glyph: FontLabGlyph, metrics: FontLabMetrics, retainContours: Bool = false) throws -> (record: GlyphRecord, simplifiedPointCount: Int) {
        let sampled = try sampledStrokes(glyph)
        var outlineContours: [[TTPoint]] = []
        for stroke in sampled.strokes {
            let raw = contours(for: stroke, metrics: metrics, leftBearing: glyph.leftSideBearing, width: glyph.resolvedDesignWidth * Double(unitsPerEm))
            // The preview fills each stroke independently. Canonical winding
            // makes their combined TrueType fill a union, even when a user has
            // reversed an outer contour. Variable records are paired below and
            // must retain corresponding points instead of normalizing them.
            if !retainContours, stroke.contours != nil || stroke.vectorPaths != nil {
                outlineContours.append(contentsOf: try canonicalFilledContours(raw))
            } else { outlineContours.append(contentsOf: raw) }
        }
        let advance = Int((glyph.resolvedDesignWidth * Double(unitsPerEm) + (glyph.leftSideBearing + glyph.rightSideBearing) * Double(unitsPerEm)).rounded())
        return (try glyphRecord(contours: outlineContours, advanceWidth: advance, retainContours: retainContours), sampled.removedPointCount)
    }

    private static func glyphRecord(contours rawContours: [[TTPoint]], advanceWidth: Int, retainContours: Bool = false) throws -> GlyphRecord {
        let contours = rawContours.compactMap(cleanContour)
        let points = contours.flatMap { $0 }
        guard points.count <= Int(UInt16.max), contours.count <= Int(Int16.max) else {
            throw ExportError.valueOutOfRange("glyph outline complexity")
        }
        guard let first = points.first else { return blankGlyph(advanceWidth: advanceWidth) }
        let xMin = points.dropFirst().reduce(first.x) { min($0, $1.x) }
        let yMin = points.dropFirst().reduce(first.y) { min($0, $1.y) }
        let xMax = points.dropFirst().reduce(first.x) { max($0, $1.x) }
        let yMax = points.dropFirst().reduce(first.y) { max($0, $1.y) }
        for (label, value) in [("xMin", xMin), ("yMin", yMin), ("xMax", xMax), ("yMax", yMax)] {
            guard value >= Int(Int16.min), value <= Int(Int16.max) else { throw ExportError.valueOutOfRange(label) }
        }

        var writer = BigEndianWriter()
        writer.int16(Int16(contours.count))
        writer.int16(Int16(xMin)); writer.int16(Int16(yMin)); writer.int16(Int16(xMax)); writer.int16(Int16(yMax))
        var endpoint = -1
        for contour in contours {
            endpoint += contour.count
            writer.uint16(UInt16(endpoint))
        }
        writer.uint16(0) // instruction length
        for index in points.indices {
            // All generated stroke polygons may overlap at joins. Setting
            // OVERLAP_SIMPLE on the first flag asks rasterizers to preserve the
            // intended non-zero fill rather than punching holes at overlaps.
            writer.uint8(index == points.startIndex ? 0x41 : 0x01)
        }
        var previousX = 0
        for point in points {
            let delta = point.x - previousX
            guard delta >= Int(Int16.min), delta <= Int(Int16.max) else { throw ExportError.valueOutOfRange("x coordinate delta") }
            writer.int16(Int16(delta)); previousX = point.x
        }
        var previousY = 0
        for point in points {
            let delta = point.y - previousY
            guard delta >= Int(Int16.min), delta <= Int(Int16.max) else { throw ExportError.valueOutOfRange("y coordinate delta") }
            writer.int16(Int16(delta)); previousY = point.y
        }
        return GlyphRecord(
            data: writer.data,
            advanceWidth: advanceWidth,
            leftSideBearing: xMin,
            xMin: xMin, yMin: yMin, xMax: xMax, yMax: yMax,
            pointCount: points.count,
            contourCount: contours.count,
            contours: retainContours ? contours : []
        )
    }

    private struct SampledStrokes {
        let strokes: [FontLabStroke]
        let removedPointCount: Int
    }

    private static func sampledStrokes(_ glyph: FontLabGlyph) throws -> SampledStrokes {
        let filled = glyph.strokes.filter { $0.contours != nil || $0.vectorPaths != nil }
        let nonempty = glyph.strokes.filter { $0.contours == nil && $0.vectorPaths == nil && !$0.points.isEmpty }
        guard nonempty.count <= maximumSamplesPerGlyph else { throw ExportError.glyphTooComplex(glyph.character) }
        let originalCount = nonempty.reduce(0) { $0 + $1.points.count }
        guard originalCount > maximumSamplesPerGlyph else { return SampledStrokes(strokes: filled + nonempty, removedPointCount: 0) }

        // Keep both ends of every line; a single-sample stroke is a deliberate
        // dot. If even those cannot fit, fail instead of silently erasing lines.
        let minimumBudgets = nonempty.map { min(2, $0.points.count) }
        let mandatory = minimumBudgets.reduce(0, +)
        guard mandatory <= maximumSamplesPerGlyph else { throw ExportError.glyphTooComplex(glyph.character) }
        let extraCapacity = maximumSamplesPerGlyph - mandatory
        let availableExtra = originalCount - mandatory
        var budgets = minimumBudgets
        var assignedExtra = 0
        if availableExtra > 0 {
            for index in nonempty.indices {
                let available = nonempty[index].points.count - minimumBudgets[index]
                let share = min(available, Int((Double(extraCapacity) * Double(available) / Double(availableExtra)).rounded(.down)))
                budgets[index] += share
                assignedExtra += share
            }
        }
        var remainder = extraCapacity - assignedExtra
        var index = 0
        while remainder > 0 && !nonempty.isEmpty {
            if budgets[index] < nonempty[index].points.count { budgets[index] += 1; remainder -= 1 }
            index = (index + 1) % nonempty.count
        }

        let reduced = zip(nonempty, budgets).map { stroke, budget -> FontLabStroke in
            guard stroke.points.count > budget else { return stroke }
            var copy = stroke
            if budget == 1 {
                copy.points = [stroke.points[0]]
            } else {
                copy.points = (0..<budget).map { sampleIndex in
                    let source = Int((Double(sampleIndex) * Double(stroke.points.count - 1) / Double(budget - 1)).rounded())
                    return stroke.points[source]
                }
            }
            return copy
        }
        return SampledStrokes(strokes: filled + reduced, removedPointCount: originalCount - reduced.reduce(0) { $0 + $1.points.count })
    }

    private static func contours(for stroke: FontLabStroke, metrics: FontLabMetrics, leftBearing: Double, width: Double) -> [[TTPoint]] {
        if let contours = stroke.vectorPaths?.filter(\.closed).map({ $0.flattened(tolerance: 0.00003) }) ?? stroke.contours {
            return contours.map { $0.map { point in
                TTPoint(x: Int((leftBearing * Double(unitsPerEm) + point.x * width).rounded()),
                        y: Int(((point.y - metrics.baseline) * Double(unitsPerEm)).rounded()))
            } }
        }
        let points = stroke.points.map { point in
            TTPoint(
                x: Int((leftBearing * Double(unitsPerEm) + point.x * width).rounded()),
                y: Int(((point.y - metrics.baseline) * Double(unitsPerEm)).rounded())
            )
        }
        guard !points.isEmpty else { return [] }
        let radii = stroke.points.map { point in
            max(1.0, stroke.width * min(width, Double(unitsPerEm)) * FontLabDrawingOperations.pressureScale(for: point) / 2)
        }
        switch stroke.resolvedNibStyle {
        case .round:
            return roundStrokeContours(points: points, radii: radii)
        case .marker:
            return markerStrokeContours(points: points, radii: radii)
        case .outline:
            return outlineStrokeContours(points: points, radii: radii)
        }
    }

    private static func roundStrokeContours(points: [TTPoint], radii: [Double]) -> [[TTPoint]] {
        var result = zip(points, radii).map { circle(center: $0.0, radius: $0.1, clockwise: true) }
        for index in 1..<points.count {
            if let quad = segment(from: points[index - 1], to: points[index], startRadius: radii[index - 1], endRadius: radii[index]) {
                result.append(quad)
            }
        }
        return result
    }

    private static func markerStrokeContours(points: [TTPoint], radii: [Double]) -> [[TTPoint]] {
        // Letterform Editor's marker is 1.28× the nominal pen width with square caps
        // and bevel-style joins. Extending every segment by its half-width
        // produces the same square cap while overlaps close the bevel joins.
        guard points.count > 1 else {
            guard let point = points.first, let radius = radii.first else { return [] }
            let halfWidth = radius * 1.28
            let halfHeight = max(1, radius * 0.64)
            return [[
                TTPoint(x: Int((Double(point.x) - halfWidth).rounded()), y: Int((Double(point.y) + halfHeight).rounded())),
                TTPoint(x: Int((Double(point.x) + halfWidth).rounded()), y: Int((Double(point.y) + halfHeight).rounded())),
                TTPoint(x: Int((Double(point.x) + halfWidth).rounded()), y: Int((Double(point.y) - halfHeight).rounded())),
                TTPoint(x: Int((Double(point.x) - halfWidth).rounded()), y: Int((Double(point.y) - halfHeight).rounded()))
            ]]
        }
        var result: [[TTPoint]] = []
        for index in 1..<points.count {
            if let quad = squareCappedSegment(
                from: points[index - 1],
                to: points[index],
                startRadius: radii[index - 1] * 1.28,
                endRadius: radii[index] * 1.28
            ) {
                result.append(quad)
            }
        }
        return result
    }

    private static func outlineStrokeContours(points: [TTPoint], radii: [Double]) -> [[TTPoint]] {
        guard points.count > 1 else {
            guard let point = points.first, let radius = radii.first else { return [] }
            let railHalfWidth = max(1, radius * 0.14)
            return [
                circle(center: point, radius: radius + railHalfWidth, clockwise: true),
                circle(center: point, radius: max(1, radius - railHalfWidth), clockwise: false)
            ]
        }
        var result: [[TTPoint]] = []
        for index in 1..<points.count {
            let start = points[index - 1]
            let end = points[index]
            let dx = Double(end.x - start.x)
            let dy = Double(end.y - start.y)
            let length = hypot(dx, dy)
            guard length >= 0.5 else { continue }
            let nx = -dy / length
            let ny = dx / length
            for side in [-1.0, 1.0] {
                let startCenter = TTPoint(
                    x: Int((Double(start.x) + nx * radii[index - 1] * side).rounded()),
                    y: Int((Double(start.y) + ny * radii[index - 1] * side).rounded())
                )
                let endCenter = TTPoint(
                    x: Int((Double(end.x) + nx * radii[index] * side).rounded()),
                    y: Int((Double(end.y) + ny * radii[index] * side).rounded())
                )
                let startRail = max(1, radii[index - 1] * 0.14)
                let endRail = max(1, radii[index] * 0.14)
                if let rail = segment(from: startCenter, to: endCenter, startRadius: startRail, endRadius: endRail) {
                    result.append(rail)
                }
                result.append(circle(center: startCenter, radius: startRail, clockwise: true))
                result.append(circle(center: endCenter, radius: endRail, clockwise: true))
            }
        }
        return result
    }

    private static func squareCappedSegment(from start: TTPoint, to end: TTPoint, startRadius: Double, endRadius: Double) -> [TTPoint]? {
        let dx = Double(end.x - start.x)
        let dy = Double(end.y - start.y)
        let length = hypot(dx, dy)
        guard length >= 0.5 else { return nil }
        let tx = dx / length
        let ty = dy / length
        let nx = -ty
        let ny = tx
        return [
            TTPoint(x: Int((Double(start.x) - tx * startRadius + nx * startRadius).rounded()), y: Int((Double(start.y) - ty * startRadius + ny * startRadius).rounded())),
            TTPoint(x: Int((Double(end.x) + tx * endRadius + nx * endRadius).rounded()), y: Int((Double(end.y) + ty * endRadius + ny * endRadius).rounded())),
            TTPoint(x: Int((Double(end.x) + tx * endRadius - nx * endRadius).rounded()), y: Int((Double(end.y) + ty * endRadius - ny * endRadius).rounded())),
            TTPoint(x: Int((Double(start.x) - tx * startRadius - nx * startRadius).rounded()), y: Int((Double(start.y) - ty * startRadius - ny * startRadius).rounded()))
        ]
    }

    private static func segment(from start: TTPoint, to end: TTPoint, startRadius: Double, endRadius: Double) -> [TTPoint]? {
        let dx = Double(end.x - start.x)
        let dy = Double(end.y - start.y)
        let length = hypot(dx, dy)
        guard length >= 0.5 else { return nil }
        let nx = -dy / length
        let ny = dx / length
        return [
            TTPoint(x: Int((Double(start.x) + nx * startRadius).rounded()), y: Int((Double(start.y) + ny * startRadius).rounded())),
            TTPoint(x: Int((Double(end.x) + nx * endRadius).rounded()), y: Int((Double(end.y) + ny * endRadius).rounded())),
            TTPoint(x: Int((Double(end.x) - nx * endRadius).rounded()), y: Int((Double(end.y) - ny * endRadius).rounded())),
            TTPoint(x: Int((Double(start.x) - nx * startRadius).rounded()), y: Int((Double(start.y) - ny * startRadius).rounded()))
        ]
    }

    private static func circle(center: TTPoint, radius: Double, clockwise: Bool, segments: Int = 12) -> [TTPoint] {
        (0..<segments).map { index in
            let angle = (clockwise ? -1.0 : 1.0) * Double(index) * 2 * .pi / Double(segments)
            return TTPoint(
                x: Int((Double(center.x) + cos(angle) * radius).rounded()),
                y: Int((Double(center.y) + sin(angle) * radius).rounded())
            )
        }
    }

    private static func rectangle(x0: Int, y0: Int, x1: Int, y1: Int, clockwise: Bool) -> [TTPoint] {
        let clockwisePoints = [TTPoint(x: x0, y: y1), TTPoint(x: x1, y: y1), TTPoint(x: x1, y: y0), TTPoint(x: x0, y: y0)]
        return clockwise ? clockwisePoints : Array(clockwisePoints.reversed())
    }

    private static func cleanContour(_ contour: [TTPoint]) -> [TTPoint]? {
        var cleaned: [TTPoint] = []
        for point in contour where cleaned.last != point { cleaned.append(point) }
        if cleaned.count > 1, cleaned.first == cleaned.last { cleaned.removeLast() }
        return cleaned.count >= 3 ? cleaned : nil
    }

    private static func polygonPath(_ contours: [[TTPoint]]) -> CGPath {
        let path = CGMutablePath()
        for contour in contours {
            guard let first = contour.first else { continue }
            path.move(to: CGPoint(x: first.x, y: first.y))
            for point in contour.dropFirst() { path.addLine(to: CGPoint(x: point.x, y: point.y)) }
            path.closeSubpath()
        }
        return path
    }

    private static func canonicalFilledContours(_ contours: [[TTPoint]]) throws -> [[TTPoint]] {
        var output: [[TTPoint]] = [], current: [TTPoint] = [], unexpectedCurve = false
        polygonPath(contours).normalized(using: .winding).applyWithBlock { pointer in
            let element = pointer.pointee
            switch element.type {
            case .moveToPoint: current = [TTPoint(x: Int(element.points[0].x.rounded()), y: Int(element.points[0].y.rounded()))]
            case .addLineToPoint: current.append(TTPoint(x: Int(element.points[0].x.rounded()), y: Int(element.points[0].y.rounded())))
            case .closeSubpath:
                // Quartz normalizes outer polygons counterclockwise. Reverse
                // the whole compound to match our clockwise pen outlines;
                // the relative winding of every counter is retained.
                if let contour = cleanContour(current) { output.append(Array(contour.reversed())) }
                current = []
            default: unexpectedCurve = true
            }
        }
        guard !unexpectedCurve else { throw ExportError.malformedFont("polygon fill normalization produced an unsupported curve") }
        return output
    }

    /// A variable compound may be reversed as a whole without changing point
    /// correspondence. Disconnected outer regions with conflicting direction
    /// require boolean normalization, so leave those to static export.
    private static func reverseVariableCompound(_ contours: [[TTPoint]], character: String) throws -> Bool {
        let paths = contours.map { polygonPath([$0]) }
        let roots = contours.indices.filter { index in
            guard let first = contours[index].first else { return false }
            return !contours.indices.contains { other in
                other != index && paths[other].boundingBoxOfPath.contains(paths[index].boundingBoxOfPath) &&
                    paths[other].contains(CGPoint(x: first.x, y: first.y))
            }
        }
        let areas = roots.map { signedArea(contours[$0]) }
        guard let direction = areas.first, direction != 0,
              areas.allSatisfy({ $0 != 0 && ($0 > 0) == (direction > 0) }) else {
            throw ExportError.incompatibleMasters("\(character) has mixed outer contour directions within an outline part. Match the outer winding in both masters, or export static fonts.")
        }
        return direction > 0
    }

    private static func compatibleGlyphRecords(_ lowerSource: FontLabGlyph, _ upperSource: FontLabGlyph, metrics: FontLabMetrics) throws -> (GlyphRecord, GlyphRecord) {
        let character = lowerSource.character
        guard lowerSource.strokes.count == upperSource.strokes.count else {
            throw ExportError.incompatibleMasters("\(character) has a different number of outline parts.")
        }
        var lower = lowerSource, upper = upperSource
        for index in lower.strokes.indices {
            let a = lower.strokes[index], b = upper.strokes[index]
            if let aPaths = a.vectorPaths, let bPaths = b.vectorPaths {
                guard aPaths.count == bPaths.count else {
                    throw ExportError.incompatibleMasters("\(character) has a different number of contours.")
                }
                var aContours: [[FontLabPoint]] = [], bContours: [[FontLabPoint]] = []
                for (ap, bp) in zip(aPaths, bPaths) {
                    guard ap.closed, bp.closed else { throw ExportError.openContours(character) }
                    guard ap.nodes.count == bp.nodes.count,
                          ap.nodes.indices.allSatisfy({ ap.isCurve($0) == bp.isCurve($0) }) else {
                        throw ExportError.incompatibleMasters("\(character) needs corresponding nodes and curve segments in both masters.")
                    }
                    let sampled = synchronizedContours(ap, bp)
                    aContours.append(sampled.0); bContours.append(sampled.1)
                }
                lower.strokes[index].vectorPaths = nil; lower.strokes[index].contours = aContours
                upper.strokes[index].vectorPaths = nil; upper.strokes[index].contours = bContours
            } else if let ac = a.contours, let bc = b.contours, a.vectorPaths == nil, b.vectorPaths == nil {
                guard ac.count == bc.count,
                      zip(ac, bc).allSatisfy({ pair in pair.0.count == pair.1.count }) else {
                    throw ExportError.incompatibleMasters("\(character) has polygon contours with different point counts.")
                }
            } else if a.vectorPaths == nil, b.vectorPaths == nil, a.contours == nil, b.contours == nil {
                guard a.points.count == b.points.count, a.resolvedNibStyle == b.resolvedNibStyle else {
                    throw ExportError.incompatibleMasters("\(character) has pen strokes with different sample counts or nibs.")
                }
            } else {
                throw ExportError.incompatibleMasters("\(character) mixes different outline types between masters.")
            }
        }
        for index in lower.strokes.indices where lower.strokes[index].contours != nil {
            let a = contours(for: lower.strokes[index], metrics: metrics, leftBearing: lower.leftSideBearing, width: lower.resolvedDesignWidth * Double(unitsPerEm))
            let b = contours(for: upper.strokes[index], metrics: metrics, leftBearing: upper.leftSideBearing, width: upper.resolvedDesignWidth * Double(unitsPerEm))
            let reverse = try reverseVariableCompound(a, character: character)
            _ = try reverseVariableCompound(b, character: character)
            // Use the SAME reversal in both masters. Independently repairing
            // their winding would hide incompatible point order.
            if reverse {
                lower.strokes[index].contours = lower.strokes[index].contours?.map { Array($0.reversed()) }
                upper.strokes[index].contours = upper.strokes[index].contours?.map { Array($0.reversed()) }
            }
        }
        let a = try glyphRecord(lower, metrics: metrics, retainContours: true).record
        let b = try glyphRecord(upper, metrics: metrics, retainContours: true).record
        guard !a.contours.isEmpty,
              a.contours.count == b.contours.count,
              zip(a.contours, b.contours).allSatisfy({ pair in pair.0.count == pair.1.count }),
              zip(a.contours, b.contours).allSatisfy({ pair in
                  let aa = signedArea(pair.0), bb = signedArea(pair.1)
                  return aa != 0 && bb != 0 && (aa > 0) == (bb > 0)
              }) else {
            throw ExportError.incompatibleMasters("\(character) changes contour topology, winding or export point correspondence.")
        }
        return (a, b)
    }

    /// Both cubics use the same subdivision tree. Independent adaptive
    /// flattening can silently pair unrelated points after a small edit.
    private static func synchronizedContours(_ a: FontLabVectorPath, _ b: FontLabVectorPath) -> ([FontLabPoint], [FontLabPoint]) {
        var first = [a.nodes[0].point], second = [b.nodes[0].point]
        func flatEnough(_ p: [FontLabPoint]) -> Bool {
            let chord = hypot(p[3].x - p[0].x, p[3].y - p[0].y)
            let polygon = hypot(p[1].x - p[0].x, p[1].y - p[0].y) +
                hypot(p[2].x - p[1].x, p[2].y - p[1].y) + hypot(p[3].x - p[2].x, p[3].y - p[2].y)
            return polygon - chord < 0.00003
        }
        func visit(_ pa: [FontLabPoint], _ pb: [FontLabPoint], _ depth: Int) {
            if depth >= 12 || (flatEnough(pa) && flatEnough(pb)) {
                first.append(pa[3]); second.append(pb[3]); return
            }
            let sa = FontLabVectorMath.split(pa, at: 0.5), sb = FontLabVectorMath.split(pb, at: 0.5)
            visit(sa.0, sb.0, depth + 1); visit(sa.1, sb.1, depth + 1)
        }
        for segment in 0..<a.segmentCount {
            if a.isCurve(segment) { visit(a.controls(segment), b.controls(segment), 0) }
            else { first.append(a.controls(segment)[3]); second.append(b.controls(segment)[3]) }
        }
        first.removeLast(); second.removeLast() // closed path repeats its first point
        return (first, second)
    }

    private static func signedArea(_ contour: [TTPoint]) -> Double {
        guard contour.count >= 3 else { return 0 }
        var sum = 0.0
        for i in contour.indices {
            let next = contour[(i + 1) % contour.count]
            sum += Double(contour[i].x) * Double(next.y) - Double(next.x) * Double(contour[i].y)
        }
        return sum
    }

    private static func fvarTable(weight0: UInt16, weight1: UInt16) -> Data {
        var out = BigEndianWriter()
        out.uint16(1); out.uint16(0); out.uint16(16); out.uint16(2)
        out.uint16(1); out.uint16(20); out.uint16(2); out.uint16(8)
        out.tag("wght"); out.uint32(UInt32(weight0) << 16); out.uint32(UInt32(weight0) << 16)
        out.uint32(UInt32(weight1) << 16); out.uint16(0); out.uint16(256)
        out.uint16(257); out.uint16(0); out.uint32(UInt32(weight0) << 16)
        out.uint16(258); out.uint16(0); out.uint32(UInt32(weight1) << 16)
        return out.data
    }

    private static func statTable(weight0: UInt16, weight1: UInt16, defaultIsRegular: Bool) -> Data {
        var out = BigEndianWriter()
        out.uint16(1); out.uint16(2); out.uint16(8); out.uint16(1); out.uint32(20)
        out.uint16(2); out.uint32(28); out.uint16(2) // fallback name ID: default subfamily
        out.tag("wght"); out.uint16(256); out.uint16(0)
        out.uint16(4); out.uint16(16) // offsets from the start of this array
        out.uint16(1); out.uint16(0); out.uint16(defaultIsRegular ? 2 : 0); out.uint16(257); out.uint32(UInt32(weight0) << 16)
        out.uint16(1); out.uint16(0); out.uint16(0); out.uint16(258); out.uint32(UInt32(weight1) << 16)
        return out.data
    }

    private static func gvarTable(defaultGlyphs: [GlyphRecord], upperGlyphs: [GlyphRecord]) throws -> Data {
        guard defaultGlyphs.count == upperGlyphs.count else { throw ExportError.malformedFont("variable glyph count differs") }
        var contents = BigEndianWriter(), offsets: [UInt32] = []
        for (a, b) in zip(defaultGlyphs, upperGlyphs) {
            guard contents.data.count <= Int(UInt32.max) else { throw ExportError.valueOutOfRange("gvar size") }
            offsets.append(UInt32(contents.data.count))
            let basePoints = a.contours.flatMap { $0 }, alternatePoints = b.contours.flatMap { $0 }
            guard basePoints.count == alternatePoints.count else { throw ExportError.malformedFont("variable point count differs") }
            var x: [Int] = [], y: [Int] = []
            x.reserveCapacity(basePoints.count + 4); y.reserveCapacity(basePoints.count + 4)
            for (p, q) in zip(basePoints, alternatePoints) { x.append(q.x - p.x); y.append(q.y - p.y) }
            // Four phantom points follow every simple glyph. In this exporter
            // LSB equals xMin, so the first x phantom stays at zero; the second
            // carries the interpolated advance. Vertical metrics are fixed.
            x.append(contentsOf: [0, b.advanceWidth - a.advanceWidth, 0, 0])
            y.append(contentsOf: [0, 0, 0, 0])
            guard x.contains(where: { $0 != 0 }) || y.contains(where: { $0 != 0 }) else { continue }
            let xd = try packedDeltas(x), yd = try packedDeltas(y)
            let size = 1 + xd.count + yd.count // 0 means all point numbers
            guard size <= Int(UInt16.max) else { throw ExportError.valueOutOfRange("gvar deltas for one glyph") }
            contents.uint16(1); contents.uint16(10) // one tuple, data begins after embedded peak
            contents.uint16(UInt16(size)); contents.uint16(0xA000) // embedded peak, private points
            contents.int16(0x4000) // positive end of the normalized weight axis
            contents.uint8(0); contents.bytes(xd); contents.bytes(yd)
            contents.pad(toMultipleOf: 2)
        }
        guard contents.data.count <= Int(UInt32.max) else { throw ExportError.valueOutOfRange("gvar size") }
        offsets.append(UInt32(contents.data.count))
        let arrayOffset = 20 + 4 * offsets.count
        var out = BigEndianWriter()
        out.uint16(1); out.uint16(0); out.uint16(1); out.uint16(0)
        out.uint32(UInt32(arrayOffset)); out.uint16(UInt16(defaultGlyphs.count)); out.uint16(1)
        out.uint32(UInt32(arrayOffset))
        for offset in offsets { out.uint32(offset) }
        out.bytes(contents.data)
        return out.data
    }

    private static func packedDeltas(_ values: [Int]) throws -> Data {
        guard values.allSatisfy({ (Int(Int16.min)...Int(Int16.max)).contains($0) }) else {
            throw ExportError.valueOutOfRange("gvar coordinate delta")
        }
        var out = BigEndianWriter(), index = 0
        while index < values.count {
            let end = min(index + 64, values.count), run = values[index..<end]
            if run.allSatisfy({ $0 == 0 }) { out.uint8(0x80 | UInt8(run.count - 1)) }
            else if run.allSatisfy({ (-128...127).contains($0) }) {
                out.uint8(UInt8(run.count - 1))
                for value in run { out.uint8(UInt8(bitPattern: Int8(value))) }
            } else {
                out.uint8(0x40 | UInt8(run.count - 1))
                for value in run { out.int16(Int16(value)) }
            }
            index = end
        }
        return out.data
    }

    // MARK: - sfnt tables

    private struct Table {
        let tag: String
        let data: Data
    }

    private static func buildFont(
        project: FontLabProject,
        familyName: String,
        postScriptName: String,
        revision: FontRevision,
        glyphs: [GlyphRecord],
        cmap: [UInt32: UInt16],
        weightClass: UInt16,
        extraTables: [Table] = [],
        variableStyleName: String? = nil,
        extraNames: [(UInt16, String)] = []
    ) throws -> Data {
        guard glyphs.count <= Int(UInt16.max) else { throw ExportError.valueOutOfRange("glyph count") }
        let glyfAndLoca = try glyfAndLocaTables(glyphs)
        let globalXMin = glyphs.map(\.xMin).min() ?? 0
        let globalYMin = glyphs.map(\.yMin).min() ?? 0
        let globalXMax = glyphs.map(\.xMax).max() ?? 0
        let globalYMax = glyphs.map(\.yMax).max() ?? 0
        let ascent = max(globalYMax, Int(((1 - project.metrics.baseline) * Double(unitsPerEm)).rounded()))
        let descent = min(globalYMin, -Int((project.metrics.baseline * Double(unitsPerEm)).rounded()))

        var tables = [
            Table(tag: "OS/2", data: try os2Table(project: project, glyphs: glyphs, cmap: cmap, ascent: ascent, descent: descent, weightClass: weightClass)),
            Table(tag: "cmap", data: cmapTable(cmap)),
            Table(tag: "glyf", data: glyfAndLoca.glyf),
            Table(tag: "head", data: try headTable(revision: revision, xMin: globalXMin, yMin: globalYMin, xMax: globalXMax, yMax: globalYMax)),
            Table(tag: "hhea", data: try hheaTable(glyphs: glyphs, ascent: ascent, descent: descent)),
            Table(tag: "hmtx", data: try hmtxTable(glyphs)),
            Table(tag: "loca", data: glyfAndLoca.loca),
            Table(tag: "maxp", data: try maxpTable(glyphs)),
            Table(tag: "name", data: try nameTable(project: project, familyName: familyName, postScriptName: postScriptName, revision: revision, variableStyleName: variableStyleName, extraNames: extraNames)),
            Table(tag: "post", data: postTable())
        ]
        if let kern = try kerningTable(project: project, cmap: cmap) { tables.append(Table(tag: "kern", data: kern)) }
        tables.append(contentsOf: extraTables)
        tables.sort { $0.tag < $1.tag }

        let numberOfTables = tables.count
        let entrySelector = Int(floor(log2(Double(numberOfTables))))
        let searchRange = (1 << entrySelector) * 16
        let rangeShift = numberOfTables * 16 - searchRange
        var offset = 12 + numberOfTables * 16
        struct DirectoryEntry { let table: Table; let offset: Int }
        var entries: [DirectoryEntry] = []
        for table in tables {
            offset = aligned4(offset)
            entries.append(DirectoryEntry(table: table, offset: offset))
            offset += aligned4(table.data.count)
        }

        var writer = BigEndianWriter()
        writer.uint32(0x0001_0000)
        writer.uint16(UInt16(numberOfTables)); writer.uint16(UInt16(searchRange)); writer.uint16(UInt16(entrySelector)); writer.uint16(UInt16(rangeShift))
        for entry in entries {
            writer.tag(entry.table.tag)
            writer.uint32(checksum(entry.table.data))
            writer.uint32(UInt32(entry.offset))
            writer.uint32(UInt32(entry.table.data.count))
        }
        for entry in entries {
            writer.pad(toMultipleOf: 4)
            guard writer.data.count == entry.offset else { throw ExportError.malformedFont("table offset calculation failed") }
            writer.bytes(entry.table.data)
            writer.pad(toMultipleOf: 4)
        }
        guard let head = entries.first(where: { $0.table.tag == "head" }) else { throw ExportError.malformedFont("head table is missing") }
        let adjustment = checkSumMagic &- checksum(writer.data)
        writer.patchUInt32(adjustment, at: head.offset + 8)
        guard checksum(writer.data) == checkSumMagic else { throw ExportError.malformedFont("font checksum adjustment failed") }
        return writer.data
    }

    private static func glyfAndLocaTables(_ glyphs: [GlyphRecord]) throws -> (glyf: Data, loca: Data) {
        var glyf = BigEndianWriter()
        var offsets: [UInt32] = []
        for glyph in glyphs {
            guard glyf.data.count <= Int(UInt32.max) else { throw ExportError.valueOutOfRange("glyf table size") }
            offsets.append(UInt32(glyf.data.count))
            glyf.bytes(glyph.data)
            glyf.pad(toMultipleOf: 4)
        }
        offsets.append(UInt32(glyf.data.count))
        var loca = BigEndianWriter()
        offsets.forEach { loca.uint32($0) }
        return (glyf.data, loca.data)
    }

    private static func headTable(revision: FontRevision, xMin: Int, yMin: Int, xMax: Int, yMax: Int) throws -> Data {
        guard [xMin, yMin, xMax, yMax].allSatisfy({ $0 >= Int(Int16.min) && $0 <= Int(Int16.max) }) else {
            throw ExportError.valueOutOfRange("global font bounds")
        }
        var writer = BigEndianWriter()
        writer.uint32(0x0001_0000); writer.uint32(revision.fixed); writer.uint32(0)
        writer.uint32(0x5F0F_3CF5); writer.uint16(0x000B); writer.uint16(UInt16(unitsPerEm))
        writer.uint64(0); writer.uint64(0) // deterministic creation/modification dates
        writer.int16(Int16(xMin)); writer.int16(Int16(yMin)); writer.int16(Int16(xMax)); writer.int16(Int16(yMax))
        writer.uint16(0); writer.uint16(8); writer.int16(2); writer.int16(1); writer.int16(0)
        return writer.data
    }

    private static func hheaTable(glyphs: [GlyphRecord], ascent: Int, descent: Int) throws -> Data {
        let maximumAdvance = glyphs.map(\.advanceWidth).max() ?? 0
        let minimumLSB = glyphs.map(\.leftSideBearing).min() ?? 0
        let minimumRSB = glyphs.map { $0.advanceWidth - $0.leftSideBearing - ($0.xMax - $0.xMin) }.min() ?? 0
        let maximumExtent = glyphs.map { $0.leftSideBearing + ($0.xMax - $0.xMin) }.max() ?? 0
        guard ascent <= Int(Int16.max), descent >= Int(Int16.min), maximumAdvance <= Int(UInt16.max),
              [minimumLSB, minimumRSB, maximumExtent].allSatisfy({ $0 >= Int(Int16.min) && $0 <= Int(Int16.max) }) else {
            throw ExportError.valueOutOfRange("horizontal font metrics")
        }
        var writer = BigEndianWriter()
        writer.uint32(0x0001_0000)
        writer.int16(Int16(ascent)); writer.int16(Int16(descent)); writer.int16(0)
        writer.uint16(UInt16(maximumAdvance)); writer.int16(Int16(minimumLSB)); writer.int16(Int16(minimumRSB)); writer.int16(Int16(maximumExtent))
        writer.int16(1); writer.int16(0); writer.int16(0)
        for _ in 0..<4 { writer.int16(0) }
        writer.int16(0); writer.uint16(UInt16(glyphs.count))
        return writer.data
    }

    private static func maxpTable(_ glyphs: [GlyphRecord]) throws -> Data {
        let maxPoints = glyphs.map(\.pointCount).max() ?? 0
        let maxContours = glyphs.map(\.contourCount).max() ?? 0
        guard maxPoints <= Int(UInt16.max), maxContours <= Int(UInt16.max) else { throw ExportError.valueOutOfRange("maximum glyph profile") }
        var writer = BigEndianWriter()
        writer.uint32(0x0001_0000); writer.uint16(UInt16(glyphs.count))
        writer.uint16(UInt16(maxPoints)); writer.uint16(UInt16(maxContours))
        writer.uint16(0); writer.uint16(0); writer.uint16(2)
        for _ in 0..<8 { writer.uint16(0) }
        return writer.data
    }

    private static func hmtxTable(_ glyphs: [GlyphRecord]) throws -> Data {
        var writer = BigEndianWriter()
        for glyph in glyphs {
            guard glyph.advanceWidth >= 0, glyph.advanceWidth <= Int(UInt16.max),
                  glyph.leftSideBearing >= Int(Int16.min), glyph.leftSideBearing <= Int(Int16.max) else {
                throw ExportError.valueOutOfRange("glyph advance or side bearing")
            }
            writer.uint16(UInt16(glyph.advanceWidth)); writer.int16(Int16(glyph.leftSideBearing))
        }
        return writer.data
    }

    private static func cmapTable(_ mappings: [UInt32: UInt16]) -> Data {
        let sorted = mappings.sorted { $0.key < $1.key }
        let bmp = Dictionary(uniqueKeysWithValues: sorted.filter { $0.key < 0xFFFF })
        let format4 = cmapFormat4(bmp)
        let format12 = cmapFormat12(Dictionary(uniqueKeysWithValues: sorted))
        let headerLength = 4 + 3 * 8
        let format4Offset = headerLength
        let format12Offset = format4Offset + format4.count
        var writer = BigEndianWriter()
        writer.uint16(0); writer.uint16(3)
        writer.uint16(0); writer.uint16(4); writer.uint32(UInt32(format12Offset))
        writer.uint16(3); writer.uint16(1); writer.uint32(UInt32(format4Offset))
        writer.uint16(3); writer.uint16(10); writer.uint32(UInt32(format12Offset))
        writer.bytes(format4); writer.bytes(format12)
        return writer.data
    }

    private static func cmapFormat4(_ mappings: [UInt32: UInt16]) -> Data {
        struct Segment { let start: UInt16; let end: UInt16; let delta: UInt16 }
        let sorted = mappings.sorted { $0.key < $1.key }
        var segments: [Segment] = []
        for (codepoint, glyph) in sorted {
            let code = UInt16(codepoint)
            let delta = glyph &- code
            if let last = segments.last, UInt32(last.end) + 1 == codepoint, last.delta == delta {
                segments[segments.count - 1] = Segment(start: last.start, end: code, delta: delta)
            } else {
                segments.append(Segment(start: code, end: code, delta: delta))
            }
        }
        segments.append(Segment(start: 0xFFFF, end: 0xFFFF, delta: 1))
        let count = segments.count
        let entrySelector = Int(floor(log2(Double(count))))
        let searchRange = (1 << entrySelector) * 2
        let length = 16 + count * 8
        var writer = BigEndianWriter()
        writer.uint16(4); writer.uint16(UInt16(length)); writer.uint16(0); writer.uint16(UInt16(count * 2))
        writer.uint16(UInt16(searchRange)); writer.uint16(UInt16(entrySelector)); writer.uint16(UInt16(count * 2 - searchRange))
        segments.forEach { writer.uint16($0.end) }
        writer.uint16(0)
        segments.forEach { writer.uint16($0.start) }
        segments.forEach { writer.uint16($0.delta) }
        segments.forEach { _ in writer.uint16(0) }
        return writer.data
    }

    private static func cmapFormat12(_ mappings: [UInt32: UInt16]) -> Data {
        struct Group { let start: UInt32; let end: UInt32; let startGlyph: UInt32 }
        let sorted = mappings.sorted { $0.key < $1.key }
        var groups: [Group] = []
        for (codepoint, glyph) in sorted {
            if let last = groups.last,
               last.end + 1 == codepoint,
               last.startGlyph + (last.end - last.start) + 1 == UInt32(glyph) {
                groups[groups.count - 1] = Group(start: last.start, end: codepoint, startGlyph: last.startGlyph)
            } else {
                groups.append(Group(start: codepoint, end: codepoint, startGlyph: UInt32(glyph)))
            }
        }
        var writer = BigEndianWriter()
        writer.uint16(12); writer.uint16(0); writer.uint32(UInt32(16 + groups.count * 12)); writer.uint32(0); writer.uint32(UInt32(groups.count))
        for group in groups { writer.uint32(group.start); writer.uint32(group.end); writer.uint32(group.startGlyph) }
        return writer.data
    }

    private static func kerningTable(project: FontLabProject, cmap: [UInt32: UInt16]) throws -> Data? {
        // Control/NBSP cmap aliases share glyph IDs with space or .null. Only
        // real project mappings may create pairs, matching the revision hash.
        let characters = Set(mappedGlyphs(project).map(\.character))
        let pairs = try project.resolvedKerning(characters: characters).compactMap { pair -> (UInt16, UInt16, Int16)? in
            guard pair.left.unicodeScalars.count == 1, pair.right.unicodeScalars.count == 1,
                  let left = cmap[pair.left.unicodeScalars.first!.value], let right = cmap[pair.right.unicodeScalars.first!.value] else { return nil }
            return (left, right, Int16(pair.value))
        }.sorted { ($0.0, $0.1) < ($1.0, $1.1) }
        guard !pairs.isEmpty else { return nil }
        let selector = Int(floor(log2(Double(pairs.count)))), power = 1 << selector
        var writer = BigEndianWriter()
        writer.uint16(0); writer.uint16(1)
        writer.uint16(0); writer.uint16(UInt16(14 + pairs.count * 6)); writer.uint16(1)
        writer.uint16(UInt16(pairs.count)); writer.uint16(UInt16(power * 6)); writer.uint16(UInt16(selector)); writer.uint16(UInt16((pairs.count-power)*6))
        for pair in pairs { writer.uint16(pair.0); writer.uint16(pair.1); writer.int16(pair.2) }
        return writer.data
    }

    private static func nameTable(project: FontLabProject, familyName: String, postScriptName: String, revision: FontRevision, variableStyleName: String? = nil, extraNames: [(UInt16, String)] = []) throws -> Data {
        let uniqueID = "Typefield:\(postScriptName):\(project.id.uuidString.lowercased()):\(revision.fingerprint)"
        var names: [(UInt16, String)] = [
            (1, familyName), (2, variableStyleName ?? "Regular"), (3, uniqueID),
            (4, variableStyleName.map { familyName + " " + $0 } ?? familyName),
            (5, revision.versionName), (6, postScriptName)
        ]
        if let variableStyleName {
            names.append((16, familyName)); names.append((17, variableStyleName))
        }
        names.append(contentsOf: extraNames)
        if let provenance = project.remixProvenance {
            names.append((10, "Typefield derivative remix of " + provenance.sourcePostScriptNames.joined(separator: " + ") + "."))
            names.append((13, provenance.distributionNotice))
        }

        struct NameEntry {
            let platformID: UInt16
            let encodingID: UInt16
            let languageID: UInt16
            let nameID: UInt16
            let encoded: Data

            init(nameID: UInt16, string: String) {
                platformID = 3
                encodingID = string.unicodeScalars.contains(where: { $0.value > 0xFFFF }) ? 10 : 1
                languageID = 0x0409
                self.nameID = nameID
                encoded = FontLabTrueTypeExporter.utf16BE(string)
            }
        }

        var entries = names.map { NameEntry(nameID: $0.0, string: $0.1) }
        entries.sort {
            if $0.platformID != $1.platformID { return $0.platformID < $1.platformID }
            if $0.encodingID != $1.encodingID { return $0.encodingID < $1.encodingID }
            if $0.languageID != $1.languageID { return $0.languageID < $1.languageID }
            return $0.nameID < $1.nameID
        }
        let recordAreaLength = 6 + entries.count * 12
        guard entries.count <= Int(UInt16.max), recordAreaLength <= Int(UInt16.max) else {
            throw ExportError.valueOutOfRange("name table records")
        }
        var strings = BigEndianWriter()
        var records = BigEndianWriter()
        for entry in entries {
            guard entry.encoded.count <= Int(UInt16.max), strings.data.count <= Int(UInt16.max),
                  strings.data.count + entry.encoded.count <= Int(UInt16.max) else {
                throw ExportError.valueOutOfRange("name table strings")
            }
            records.uint16(entry.platformID); records.uint16(entry.encodingID)
            records.uint16(entry.languageID); records.uint16(entry.nameID)
            records.uint16(UInt16(entry.encoded.count)); records.uint16(UInt16(strings.data.count))
            strings.bytes(entry.encoded)
        }
        var writer = BigEndianWriter()
        writer.uint16(0); writer.uint16(UInt16(entries.count)); writer.uint16(UInt16(recordAreaLength))
        writer.bytes(records.data); writer.bytes(strings.data)
        return writer.data
    }

    private static func os2Table(project: FontLabProject, glyphs: [GlyphRecord], cmap: [UInt32: UInt16], ascent: Int, descent: Int, weightClass: UInt16) throws -> Data {
        let nonzeroAdvances = glyphs.map(\.advanceWidth).filter { $0 > 0 }
        let average = nonzeroAdvances.isEmpty ? 0 : nonzeroAdvances.reduce(0, +) / nonzeroAdvances.count
        let firstBMP = cmap.keys.filter { $0 <= 0xFFFF }.min().map(UInt16.init) ?? 0xFFFF
        let lastBMP = cmap.keys.filter { $0 <= 0xFFFF }.max().map(UInt16.init) ?? 0xFFFF
        let lastCharacter: UInt16 = cmap.keys.contains(where: { $0 > 0xFFFF }) ? 0xFFFF : lastBMP
        let xHeight = cmap[0x0078] == nil ? 0 : Int(((project.metrics.xHeight - project.metrics.baseline) * Double(unitsPerEm)).rounded())
        let capHeight = cmap[0x0048] == nil ? 0 : Int(((project.metrics.capHeight - project.metrics.baseline) * Double(unitsPerEm)).rounded())
        guard [average, ascent, descent, xHeight, capHeight].allSatisfy({ $0 >= Int(Int16.min) && $0 <= Int(Int16.max) }) else {
            throw ExportError.valueOutOfRange("OS/2 metrics")
        }
        var writer = BigEndianWriter()
        let embeddingPermission: UInt16 = project.remixProvenance == nil ? 0 : 0x0002
        writer.uint16(4); writer.int16(Int16(average)); writer.uint16(weightClass); writer.uint16(5); writer.uint16(embeddingPermission)
        for value: Int16 in [650, 600, 0, 75, 650, 600, 0, 350, 50, 300, 0] { writer.int16(value) }
        for _ in 0..<10 { writer.uint8(0) } // PANOSE: Any
        let functionalScalars = Set(mappedGlyphs(project).compactMap { $0.glyph == nil ? nil : $0.scalar })
        unicodeRangeWords(for: functionalScalars).forEach { writer.uint32($0) }
        // This is intentionally a private, lowercase vendor tag. Uppercase-only
        // tags conventionally identify vendors registered with Microsoft.
        writer.tag("fshf"); writer.uint16(0x0040); writer.uint16(firstBMP); writer.uint16(lastCharacter)
        writer.int16(Int16(ascent)); writer.int16(Int16(descent)); writer.int16(0)
        writer.uint16(UInt16(max(0, ascent))); writer.uint16(UInt16(max(0, -descent)))
        // Sparse, user-drawn fonts do not establish functional support for a
        // complete legacy code page. Unicode cmap coverage remains authoritative.
        writer.uint32(0); writer.uint32(0)
        writer.int16(Int16(xHeight)); writer.int16(Int16(capHeight)); writer.uint16(0); writer.uint16(0x20); writer.uint16(1)
        return writer.data
    }

    private static func unicodeRangeWords(for scalars: Set<UInt32>) -> [UInt32] {
        typealias Assignment = (bit: Int, ranges: [ClosedRange<UInt32>])
        let assignments: [Assignment] = [
            (0, [0x0000...0x007F]),
            (1, [0x0080...0x00FF]),
            (2, [0x0100...0x017F]),
            (3, [0x0180...0x024F]),
            (4, [0x0250...0x02AF, 0x1D00...0x1DBF]),
            (5, [0x02B0...0x02FF, 0xA700...0xA71F]),
            (6, [0x0300...0x036F, 0x1DC0...0x1DFF]),
            (7, [0x0370...0x03FF]),
            (8, [0x2C80...0x2CFF]),
            (9, [0x0400...0x052F, 0x2DE0...0x2DFF, 0xA640...0xA69F]),
            (10, [0x0530...0x058F]),
            (11, [0x0590...0x05FF]),
            (12, [0xA500...0xA63F]),
            (13, [0x0600...0x06FF, 0x0750...0x077F]),
            (14, [0x07C0...0x07FF]),
            (15, [0x0900...0x097F]),
            (16, [0x0980...0x09FF]),
            (17, [0x0A00...0x0A7F]),
            (18, [0x0A80...0x0AFF]),
            (19, [0x0B00...0x0B7F]),
            (20, [0x0B80...0x0BFF]),
            (21, [0x0C00...0x0C7F]),
            (22, [0x0C80...0x0CFF]),
            (23, [0x0D00...0x0D7F]),
            (24, [0x0E00...0x0E7F]),
            (25, [0x0E80...0x0EFF]),
            (26, [0x10A0...0x10FF, 0x2D00...0x2D2F]),
            (27, [0x1B00...0x1B7F]),
            (28, [0x1100...0x11FF]),
            (29, [0x1E00...0x1EFF, 0x2C60...0x2C7F, 0xA720...0xA7FF]),
            (30, [0x1F00...0x1FFF]),
            (31, [0x2000...0x206F, 0x2E00...0x2E7F]),
            (32, [0x2070...0x209F]),
            (33, [0x20A0...0x20CF]),
            (34, [0x20D0...0x20FF]),
            (35, [0x2100...0x214F]),
            (36, [0x2150...0x218F]),
            (37, [0x2190...0x21FF, 0x27F0...0x27FF, 0x2900...0x297F, 0x2B00...0x2BFF]),
            (38, [0x2200...0x22FF, 0x2A00...0x2AFF, 0x27C0...0x27EF, 0x2980...0x29FF]),
            (39, [0x2300...0x23FF]),
            (40, [0x2400...0x243F]),
            (41, [0x2440...0x245F]),
            (42, [0x2460...0x24FF]),
            (43, [0x2500...0x257F]),
            (44, [0x2580...0x259F]),
            (45, [0x25A0...0x25FF]),
            (46, [0x2600...0x26FF]),
            (47, [0x2700...0x27BF]),
            (48, [0x3000...0x303F]),
            (49, [0x3040...0x309F]),
            (50, [0x30A0...0x30FF, 0x31F0...0x31FF]),
            (51, [0x3100...0x312F, 0x31A0...0x31BF]),
            (52, [0x3130...0x318F]),
            (53, [0xA840...0xA87F]),
            (54, [0x3200...0x32FF]),
            (55, [0x3300...0x33FF]),
            (56, [0xAC00...0xD7AF]),
            (57, [0x10000...0x10FFFF]),
            (58, [0x10900...0x1091F]),
            (59, [0x4E00...0x9FFF, 0x2E80...0x2FFF, 0x3400...0x4DBF, 0x20000...0x2A6DF, 0x3190...0x319F]),
            (60, [0xE000...0xF8FF]),
            (61, [0x31C0...0x31EF, 0xF900...0xFAFF, 0x2F800...0x2FA1F]),
            (62, [0xFB00...0xFB4F]),
            (63, [0xFB50...0xFDFF]),
            (64, [0xFE20...0xFE2F]),
            (65, [0xFE10...0xFE1F, 0xFE30...0xFE4F]),
            (66, [0xFE50...0xFE6F]),
            (67, [0xFE70...0xFEFF]),
            (68, [0xFF00...0xFFEF]),
            (69, [0xFFF0...0xFFFF]),
            (70, [0x0F00...0x0FFF]),
            (71, [0x0700...0x074F]),
            (72, [0x0780...0x07BF]),
            (73, [0x0D80...0x0DFF]),
            (74, [0x1000...0x109F]),
            (75, [0x1200...0x139F, 0x2D80...0x2DDF]),
            (76, [0x13A0...0x13FF]),
            (77, [0x1400...0x167F]),
            (78, [0x1680...0x169F]),
            (79, [0x16A0...0x16FF]),
            (80, [0x1780...0x17FF, 0x19E0...0x19FF]),
            (81, [0x1800...0x18AF]),
            (82, [0x2800...0x28FF]),
            (83, [0xA000...0xA4CF]),
            (84, [0x1700...0x177F]),
            (85, [0x10300...0x1032F]),
            (86, [0x10330...0x1034F]),
            (87, [0x10400...0x1044F]),
            (88, [0x1D000...0x1D24F]),
            (89, [0x1D400...0x1D7FF]),
            (90, [0xF0000...0xFFFFD, 0x100000...0x10FFFD]),
            (91, [0xFE00...0xFE0F, 0xE0100...0xE01EF]),
            (92, [0xE0000...0xE007F]),
            (93, [0x1900...0x194F]),
            (94, [0x1950...0x197F]),
            (95, [0x1980...0x19DF]),
            (96, [0x1A00...0x1A1F]),
            (97, [0x2C00...0x2C5F]),
            (98, [0x2D30...0x2D7F]),
            (99, [0x4DC0...0x4DFF]),
            (100, [0xA800...0xA82F]),
            (101, [0x10000...0x1013F]),
            (102, [0x10140...0x1018F]),
            (103, [0x10380...0x1039F]),
            (104, [0x103A0...0x103DF]),
            (105, [0x10450...0x1047F]),
            (106, [0x10480...0x104AF]),
            (107, [0x10800...0x1083F]),
            (108, [0x10A00...0x10A5F]),
            (109, [0x1D300...0x1D35F]),
            (110, [0x12000...0x1247F]),
            (111, [0x1D360...0x1D37F]),
            (112, [0x1B80...0x1BBF]),
            (113, [0x1C00...0x1C4F]),
            (114, [0x1C50...0x1C7F]),
            (115, [0xA880...0xA8DF]),
            (116, [0xA900...0xA92F]),
            (117, [0xA930...0xA95F]),
            (118, [0xAA00...0xAA5F]),
            (119, [0x10190...0x101CF]),
            (120, [0x101D0...0x101FF]),
            (121, [0x10280...0x102DF, 0x10920...0x1093F]),
            (122, [0x1F000...0x1F09F])
        ]

        var words = [UInt32](repeating: 0, count: 4)
        for assignment in assignments where assignment.ranges.contains(where: { range in scalars.contains(where: range.contains) }) {
            words[assignment.bit / 32] |= UInt32(1) << UInt32(assignment.bit % 32)
        }
        return words
    }

    private static func postTable() -> Data {
        var writer = BigEndianWriter()
        writer.uint32(0x0003_0000); writer.uint32(0); writer.int16(-100); writer.int16(50); writer.uint32(0)
        for _ in 0..<4 { writer.uint32(0) }
        return writer.data
    }

    // MARK: - Test inspection and binary helpers

    private static func verifyDirectoryAndChecksums(_ data: Data) throws {
        guard readUInt32(data, 0) == 0x0001_0000 else { throw ExportError.malformedFont("wrong sfnt flavor") }
        let tableCount = Int(readUInt16(data, 4))
        var tags: Set<String> = []
        for index in 0..<tableCount {
            let record = 12 + index * 16
            guard record + 16 <= data.count else { throw ExportError.malformedFont("truncated table directory") }
            let tag = String(data: data.subdata(in: record..<(record + 4)), encoding: .ascii) ?? ""
            tags.insert(tag)
            let expected = readUInt32(data, record + 4)
            let offset = Int(readUInt32(data, record + 8))
            let length = Int(readUInt32(data, record + 12))
            guard offset >= 0, length >= 0, offset + length <= data.count else { throw ExportError.malformedFont("invalid \(tag) bounds") }
            var table = data.subdata(in: offset..<(offset + length))
            if tag == "head", table.count >= 12 { table.replaceSubrange(8..<12, with: [0, 0, 0, 0]) }
            guard checksum(table) == expected else { throw ExportError.malformedFont("\(tag) checksum mismatch") }
        }
        let required = Set(["OS/2", "cmap", "glyf", "head", "hhea", "hmtx", "loca", "maxp", "name", "post"])
        guard required.isSubset(of: tags), checksum(data) == checkSumMagic else { throw ExportError.malformedFont("required tables or checksum are missing") }
    }

    private static func verifyMetricTables(_ data: Data, project: FontLabProject) throws {
        guard let os2 = tableData("OS/2", in: data), os2.count == 96 else { throw ExportError.malformedFont("OS/2 version 4 table is missing") }
        let mappings = mappedGlyphs(project)
        let mappedScalars = Set(mappings.map(\.scalar))
        let functionalScalars = Set(mappings.compactMap { $0.glyph == nil ? nil : $0.scalar })
        let expectedXHeight: Int16 = mappedScalars.contains(0x0078)
            ? Int16(((project.metrics.xHeight - project.metrics.baseline) * Double(unitsPerEm)).rounded()) : 0
        let expectedCapHeight: Int16 = mappedScalars.contains(0x0048)
            ? Int16(((project.metrics.capHeight - project.metrics.baseline) * Double(unitsPerEm)).rounded()) : 0
        let expectedLastCharacter: UInt16 = mappedScalars.contains(where: { $0 > 0xFFFF })
            ? 0xFFFF : UInt16(max(mappedScalars.max() ?? 0x0020, 0x00A0))
        let expectedRanges = unicodeRangeWords(for: functionalScalars)
        let expectedEmbedding: UInt16 = project.remixProvenance == nil ? 0 : 0x0002
        guard Int16(bitPattern: readUInt16(os2, 86)) == expectedXHeight,
              Int16(bitPattern: readUInt16(os2, 88)) == expectedCapHeight,
              readUInt16(os2, 8) == expectedEmbedding,
              readUInt16(os2, 64) == 0,
              readUInt16(os2, 66) == expectedLastCharacter,
              String(data: os2.subdata(in: 58..<62), encoding: .ascii) == "fshf",
              readUInt32(os2, 78) == 0,
              readUInt32(os2, 82) == 0,
              (0..<4).allSatisfy({ readUInt32(os2, 42 + $0 * 4) == expectedRanges[$0] }) else {
            throw ExportError.malformedFont("OS/2 coverage, metrics, or embedding permissions were not preserved")
        }
    }

    private static func verifyRequiredControlGlyphs(_ data: Data) throws {
        guard glyphID(for: 0x0000, in: data) == 1,
              glyphID(for: 0x0008, in: data) == 1,
              glyphID(for: 0x0009, in: data) == 3,
              glyphID(for: 0x000D, in: data) == 2,
              glyphID(for: 0x001D, in: data) == 1,
              glyphID(for: 0x0020, in: data) == 3,
              glyphID(for: 0x00A0, in: data) == 3,
              let hmtx = tableData("hmtx", in: data), hmtx.count >= 16,
              readUInt16(hmtx, 4) == 0,
              readUInt16(hmtx, 8) > 0,
              readUInt16(hmtx, 12) > 0 else {
            throw ExportError.malformedFont("the required .null, CR, and space glyph mappings or advances are invalid")
        }
    }

    private static func glyphID(for scalar: UInt32, in data: Data) -> UInt16? {
        guard let cmap = tableData("cmap", in: data), cmap.count >= 4 else { return nil }
        let recordCount = Int(readUInt16(cmap, 2))
        for index in 0..<recordCount {
            let record = 4 + index * 8
            guard record + 8 <= cmap.count else { return nil }
            let platformID = readUInt16(cmap, record)
            let encodingID = readUInt16(cmap, record + 2)
            guard platformID == 3, encodingID == 10 else { continue }
            let subtableOffset = Int(readUInt32(cmap, record + 4))
            guard subtableOffset + 16 <= cmap.count,
                  readUInt16(cmap, subtableOffset) == 12 else { return nil }
            let length = Int(readUInt32(cmap, subtableOffset + 4))
            let groupCount = Int(readUInt32(cmap, subtableOffset + 12))
            guard length >= 16, subtableOffset + length <= cmap.count,
                  groupCount <= (length - 16) / 12 else { return nil }
            for groupIndex in 0..<groupCount {
                let group = subtableOffset + 16 + groupIndex * 12
                let start = readUInt32(cmap, group)
                let end = readUInt32(cmap, group + 4)
                guard scalar >= start, scalar <= end else { continue }
                let glyph = readUInt32(cmap, group + 8) + scalar - start
                return glyph <= UInt32(UInt16.max) ? UInt16(glyph) : nil
            }
        }
        return nil
    }

    private static func verifyNameRecords(_ data: Data, fullRepertoireNameIDs: Set<UInt16> = []) throws {
        guard let name = tableData("name", in: data), name.count >= 6,
              readUInt16(name, 0) == 0 else {
            throw ExportError.malformedFont("the name table is missing or has an unexpected format")
        }
        let count = Int(readUInt16(name, 2))
        let storageOffset = Int(readUInt16(name, 4))
        guard storageOffset >= 6 + count * 12, storageOffset <= name.count else {
            throw ExportError.malformedFont("the name table record area is invalid")
        }
        var previousKey: [UInt16]?
        var remainingFullRepertoireIDs = fullRepertoireNameIDs
        for index in 0..<count {
            let record = 6 + index * 12
            guard record + 12 <= name.count else { throw ExportError.malformedFont("a name record is truncated") }
            let platformID = readUInt16(name, record)
            let encodingID = readUInt16(name, record + 2)
            let languageID = readUInt16(name, record + 4)
            let nameID = readUInt16(name, record + 6)
            let length = Int(readUInt16(name, record + 8))
            let offset = Int(readUInt16(name, record + 10))
            let key = [platformID, encodingID, languageID, nameID]
            if let previousKey, key.lexicographicallyPrecedes(previousKey) {
                throw ExportError.malformedFont("name records are not sorted by platform, encoding, language, and name ID")
            }
            guard storageOffset + offset + length <= name.count else {
                throw ExportError.malformedFont("a name string points outside its storage area")
            }
            if platformID == 3, encodingID == 10 {
                remainingFullRepertoireIDs.remove(nameID)
            }
            previousKey = key
        }
        guard remainingFullRepertoireIDs.isEmpty else {
            throw ExportError.malformedFont("a supplementary name was not labeled with the full-repertoire encoding")
        }
    }

    private static func tableData(_ wantedTag: String, in data: Data) -> Data? {
        let tableCount = Int(readUInt16(data, 4))
        for index in 0..<tableCount {
            let record = 12 + index * 16
            guard record + 16 <= data.count else { return nil }
            let tag = String(data: data.subdata(in: record..<(record + 4)), encoding: .ascii)
            if tag == wantedTag {
                let offset = Int(readUInt32(data, record + 8)); let length = Int(readUInt32(data, record + 12))
                guard offset + length <= data.count else { return nil }
                return data.subdata(in: offset..<(offset + length))
            }
        }
        return nil
    }

    private static func sanitizedFamilyName(_ input: String) -> String {
        let filtered = input.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
        let cleaned = String(String.UnicodeScalarView(filtered)).trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Typefield Lab" : String(cleaned.prefix(63))
    }

    private static func uniqueFamilyName(_ input: String, projectID: UUID, fingerprint: String) -> String {
        let suffix = " " + String(projectID.uuidString.prefix(8)).uppercased() + "-" + fingerprint
        let base = sanitizedFamilyName(input)
        return String(base.prefix(max(1, 63 - suffix.count))) + suffix
    }

    private static func sanitizedPostScriptName(_ familyName: String) -> String {
        let permitted = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-")
        let transformed = familyName.replacingOccurrences(of: " ", with: "-").unicodeScalars.filter { permitted.contains($0) }
        let result = String(String.UnicodeScalarView(transformed))
        return String((result.isEmpty ? "Typefield-Lab" : result).prefix(63))
    }

    private static func fontRevision(for project: FontLabProject, weightClass: UInt16) throws -> FontRevision {
        let glyphs = mappedGlyphs(project).compactMap { mapping -> RevisionGlyph? in
            guard let glyph = mapping.glyph else { return nil }
            return RevisionGlyph(
                scalar: mapping.scalar,
                strokes: glyph.strokes.map { stroke in
                    RevisionStroke(
                        points: stroke.points.map { RevisionPoint(x: $0.x, y: $0.y, pressure: $0.pressure) },
                        width: stroke.width,
                        nibStyle: stroke.resolvedNibStyle.rawValue,
                        contours: stroke.contours?.map { $0.map { RevisionPoint(x: $0.x, y: $0.y, pressure: nil) } },
                        vectorPaths: stroke.vectorPaths?.map { path in
                            RevisionVectorPath(nodes: path.nodes.map { node in
                                RevisionVectorNode(point: RevisionPoint(x: node.point.x, y: node.point.y, pressure: nil),
                                    incoming: node.incoming.map { RevisionPoint(x: $0.x, y: $0.y, pressure: nil) },
                                    outgoing: node.outgoing.map { RevisionPoint(x: $0.x, y: $0.y, pressure: nil) })
                            }, closed: path.closed)
                        }
                    )
                },
                leftSideBearing: glyph.leftSideBearing,
                rightSideBearing: glyph.rightSideBearing,
                designWidth: glyph.contourDesignWidth
            )
        }
        let provenance = project.remixProvenance.map {
            RevisionProvenance(
                sourcePostScriptNames: $0.sourcePostScriptNames,
                distributionNotice: $0.distributionNotice
            )
        }
        let kern = try project.resolvedKerning(characters: Set(mappedGlyphs(project).map(\.character))).map { RevisionKerning(left: $0.left, right: $0.right, value: $0.value) }
        let payload = RevisionPayload(metrics: project.metrics, weightClass: weightClass, glyphs: glyphs, provenance: provenance, kerning: kern.isEmpty ? nil : kern)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let encoded = try encoder.encode(payload)
        let hash = encoded.reduce(UInt64(0xcbf29ce484222325)) { value, byte in
            (value ^ UInt64(byte)) &* 1_099_511_628_211
        }
        // A content hash has no chronological ordering, so presenting part of
        // it as an ever-newer numeric version would be false. Instead each
        // export-affecting revision gets a distinct family/PostScript identity
        // and starts honestly at version 1.000. Re-exporting unchanged content
        // remains byte-for-byte deterministic.
        return FontRevision(
            fixed: 0x0001_0000,
            versionName: "Version 1.000",
            fingerprint: String(format: "%016llX", locale: Locale(identifier: "en_US_POSIX"), hash)
        )
    }

    private static func safeFilename(_ value: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/:\\?%*|\"<>").union(.newlines).union(.controlCharacters)
        let cleaned = value.components(separatedBy: forbidden).filter { !$0.isEmpty }.joined(separator: "-")
        return cleaned.isEmpty ? "Typefield-Lab" : String(cleaned.prefix(80))
    }

    private static func utf16BE(_ string: String) -> Data {
        var writer = BigEndianWriter()
        string.utf16.forEach { writer.uint16($0) }
        return writer.data
    }

    private static func checksum(_ data: Data) -> UInt32 {
        var sum: UInt32 = 0
        var index = 0
        while index < data.count {
            var word: UInt32 = 0
            for byteIndex in 0..<4 {
                word <<= 8
                if index + byteIndex < data.count { word |= UInt32(data[index + byteIndex]) }
            }
            sum = sum &+ word
            index += 4
        }
        return sum
    }

    private static func aligned4(_ value: Int) -> Int { (value + 3) & ~3 }

    private static func readUInt16(_ data: Data, _ offset: Int) -> UInt16 {
        guard offset + 2 <= data.count else { return 0 }
        return UInt16(data[offset]) << 8 | UInt16(data[offset + 1])
    }

    private static func readUInt32(_ data: Data, _ offset: Int) -> UInt32 {
        guard offset + 4 <= data.count else { return 0 }
        return UInt32(data[offset]) << 24 | UInt32(data[offset + 1]) << 16 | UInt32(data[offset + 2]) << 8 | UInt32(data[offset + 3])
    }
}

private struct BigEndianWriter {
    var data = Data()

    mutating func uint8(_ value: UInt8) { data.append(value) }
    mutating func uint16(_ value: UInt16) {
        data.append(UInt8((value >> 8) & 0xFF)); data.append(UInt8(value & 0xFF))
    }
    mutating func int16(_ value: Int16) { uint16(UInt16(bitPattern: value)) }
    mutating func uint32(_ value: UInt32) {
        data.append(UInt8((value >> 24) & 0xFF)); data.append(UInt8((value >> 16) & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF)); data.append(UInt8(value & 0xFF))
    }
    mutating func uint64(_ value: UInt64) {
        uint32(UInt32((value >> 32) & 0xFFFF_FFFF)); uint32(UInt32(value & 0xFFFF_FFFF))
    }
    mutating func bytes(_ bytes: Data) { data.append(bytes) }
    mutating func tag(_ value: String) {
        let bytes = Array(value.utf8.prefix(4))
        data.append(contentsOf: bytes)
        if bytes.count < 4 { data.append(contentsOf: repeatElement(UInt8(ascii: " "), count: 4 - bytes.count)) }
    }
    mutating func pad(toMultipleOf multiple: Int) {
        let remainder = data.count % multiple
        if remainder != 0 { data.append(contentsOf: repeatElement(0, count: multiple - remainder)) }
    }
    mutating func patchUInt32(_ value: UInt32, at offset: Int) {
        data[offset] = UInt8((value >> 24) & 0xFF); data[offset + 1] = UInt8((value >> 16) & 0xFF)
        data[offset + 2] = UInt8((value >> 8) & 0xFF); data[offset + 3] = UInt8(value & 0xFF)
    }
}
