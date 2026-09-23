import SwiftUI
import AppKit
import CoreText
import UniformTypeIdentifiers

struct WebFontUse: Identifiable {
    let id: String
    let canvasID: UUID
    let canvas: String
    let style: TypeStyle
    let text: String
    let width: Double
    let kind: CanvasTextKind
}

struct WebFontAssetFace {
    let postScriptName: String
    let familyName: String
    let coverage: CharacterSet
    let writingSystems: Set<WritingSystem>
    let glyphCount: Int
    let variable: Bool
    let weight: Int
    let italic: Bool
    var axisRanges: [Int: ClosedRange<Double>] = [:]

    func covers(weight requiredWeight: Int, italic requiredItalic: Bool, axes requiredAxes: [Int: Double]) -> Bool {
        if let range = axisRanges[WebFontAxis.weight] {
            guard range.contains(Double(requiredWeight)) else { return false }
        } else if abs(weight - requiredWeight) > 25 { return false }
        if italic != requiredItalic {
            if let range = axisRanges[WebFontAxis.italic] {
                guard range.contains(requiredItalic ? 1 : 0) else { return false }
            } else if let range = axisRanges[WebFontAxis.slant] {
                guard requiredItalic ? (range.lowerBound < 0 || range.upperBound > 0) : range.contains(0) else { return false }
            } else { return false }
        }
        return requiredAxes.allSatisfy { entry in
            let (id, value) = entry
            return axisRanges[id]?.contains(value) ?? (id == WebFontAxis.weight && abs(Double(weight) - value) <= 25)
        }
    }
}

enum WebFontAxis {
    static let weight = Int(0x77676874) // wght
    static let width = Int(0x77647468) // wdth
    static let italic = Int(0x6974616C) // ital
    static let slant = Int(0x736C6E74) // slnt
}

struct WebFontAsset: Identifiable {
    var id: String { url.standardizedFileURL.path }
    let url: URL
    let byteCount: Int
    let faces: [WebFontAssetFace]
    var fileName: String { url.lastPathComponent }
}

enum WebFontAssetResolver {
    static func scan(folders: [String], catalog: [Family]) -> [WebFontAsset] {
        var urls = Set<URL>(catalog.flatMap(\.faces).compactMap { face -> URL? in
            guard let url = face.url?.standardizedFileURL, url.pathExtension.lowercased() == "woff2", automaticallyReadable(url) else { return nil }
            return url
        })
        let keys: [URLResourceKey] = [.isRegularFileKey]
        for path in folders {
            guard let enumerator = FileManager.default.enumerator(at: URL(fileURLWithPath: path), includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let url as URL in enumerator where url.pathExtension.lowercased() == "woff2" { urls.insert(url.standardizedFileURL) }
        }
        return urls.compactMap(asset).sorted { $0.fileName.localizedStandardCompare($1.fileName) == .orderedAscending }
    }

    static func automaticallyReadable(_ url: URL) -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        let roots = ["/System/Library/Fonts", "/Library/Fonts", home + "/Library/Fonts", home + "/Library/Application Support/FontShelf"]
        let path = url.standardizedFileURL.path
        return roots.contains { path == $0 || path.hasPrefix($0 + "/") }
    }

    static func asset(_ url: URL) -> WebFontAsset? {
        guard url.pathExtension.lowercased() == "woff2",
              let bytes = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              bytes > 0 else { return nil }
        let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor] ?? []
        let faces = descriptors.compactMap { descriptor -> WebFontAssetFace? in
            guard let name = CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute) as? String else { return nil }
            let font = CTFontCreateWithFontDescriptor(descriptor, 24, nil)
            let coverage = CTFontCopyCharacterSet(font) as CharacterSet
            let systems = Set(WritingSystem.allCases.filter { $0.supported(by: coverage) })
            let ranges = (CTFontCopyVariationAxes(font) as? [[String: Any]] ?? []).reduce(into: [Int: ClosedRange<Double>]()) { result, axis in
                guard let id = axis[kCTFontVariationAxisIdentifierKey as String] as? Int,
                      let minimum = axis[kCTFontVariationAxisMinimumValueKey as String] as? Double,
                      let maximum = axis[kCTFontVariationAxisMaximumValueKey as String] as? Double,
                      minimum.isFinite, maximum.isFinite, minimum <= maximum else { return }
                result[id] = minimum...maximum
            }
            return WebFontAssetFace(postScriptName: name,
                                    familyName: CTFontCopyFamilyName(font) as String,
                                    coverage: coverage,
                                    writingSystems: systems,
                                    glyphCount: CTFontGetGlyphCount(font),
                                    variable: !(CTFontCopyVariationAxes(font) as? [Any] ?? []).isEmpty,
                                    weight: FontFacts.read(font).weight,
                                    italic: CTFontGetSymbolicTraits(font).contains(.traitItalic),
                                    axisRanges: ranges)
        }
        return WebFontAsset(url: url, byteCount: bytes, faces: faces)
    }
}

enum WebTextScript {
    static func names(in text: String) -> [String] {
        var names = Set<String>()
        for scalar in text.unicodeScalars where CharacterSet.letters.contains(scalar) {
            let value = scalar.value
            let name: String
            switch value {
            case 0x0041...0x024F, 0x1E00...0x1EFF: name = "Latin"
            case 0x0370...0x03FF: name = "Greek"
            case 0x0400...0x052F: name = "Cyrillic"
            case 0x0590...0x05FF: name = "Hebrew"
            case 0x0600...0x06FF, 0x0750...0x077F, 0x08A0...0x08FF: name = "Arabic"
            case 0x0900...0x097F: name = "Devanagari"
            case 0x0980...0x09FF: name = "Bengali"
            case 0x0A80...0x0AFF: name = "Gujarati"
            case 0x0B80...0x0BFF: name = "Tamil"
            case 0x0C00...0x0C7F: name = "Telugu"
            case 0x0E00...0x0E7F: name = "Thai"
            case 0x3040...0x309F: name = "Hiragana"
            case 0x30A0...0x30FF, 0x31F0...0x31FF: name = "Katakana"
            case 0x3130...0x318F, 0xAC00...0xD7AF: name = "Hangul"
            case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF: name = "Han"
            default: name = "Other"
            }
            names.insert(name)
        }
        return names.sorted()
    }
}

struct WebFallbackImpact {
    let fallbackName: String
    let available: Bool
    let note: String
    let primaryXHeight: Double
    let fallbackXHeight: Double
    let maxWidthDelta: Double
    let maxHeightDelta: Double
    let maxLineDelta: Int
    let buttonWidthDelta: Double?
    let missingScalars: [Unicode.Scalar]
    var xHeightDelta: Double { (fallbackXHeight - primaryXHeight) / max(0.01, primaryXHeight) }
}

enum WebFontCoverageSource: String {
    case exactWebAsset = "Exact WOFF2"
    case desktopSource = "Desktop source only"
    case unavailable = "Unavailable"
}

struct WebFontStyleAudit: Identifiable {
    var id: String { postScriptName }
    let postScriptName: String
    let family: String
    let sourceFamily: String
    let styleName: String
    let weight: Int
    let italic: Bool
    let useCount: Int
    let instanceCount: Int
    let asset: WebFontAsset?
    let assetFace: WebFontAssetFace?
    let assetCandidateCount: Int
    let assetIncompatible: Bool
    let desktopBytes: Int?
    let desktopFormat: String?
    let usedCharacterCount: Int
    let missingCharacters: [Unicode.Scalar]
    let scriptsUsed: [String]
    let supportedSystems: [String]
    let coverageSource: WebFontCoverageSource
    let glyphCount: Int?
    let subsetOpportunity: String
    let fallback: WebFallbackImpact
    let variable: Bool
}

struct WebFontComparison: Identifiable {
    var id: String { family }
    let family: String
    let variableFile: String
    let variableBytes: Int
    let staticCount: Int
    let staticBytes: Int
    var delta: Int { staticBytes - variableBytes }
}

struct WebFontAuditReport {
    let rows: [WebFontStyleAudit]
    let knownBytes: Int
    let missingAssetNames: [String]
    let ambiguousAssetNames: [String]
    let incompatibleAssetNames: [String]
    let excludedBytes: Int
    let excludedAssetCount: Int
    let comparisons: [WebFontComparison]
    let canvasCount: Int
    static let empty = WebFontAuditReport(rows: [], knownBytes: 0, missingAssetNames: [], ambiguousAssetNames: [], incompatibleAssetNames: [], excludedBytes: 0, excludedAssetCount: 0, comparisons: [], canvasCount: 0)

    var text: String {
        var lines = ["What will this typography cost my page?", "", "Selected canvases: \(canvasCount)", "Known WOFF2 transfer: \(WebFontAuditFormat.bytes(knownBytes))"]
        if !missingAssetNames.isEmpty { lines.append("Missing WOFF2 assets: " + missingAssetNames.joined(separator: ", ")) }
        if !ambiguousAssetNames.isEmpty { lines.append("Ambiguous WOFF2 assets (remove duplicates or narrow the asset folder): " + ambiguousAssetNames.joined(separator: ", ")) }
        if !incompatibleAssetNames.isEmpty { lines.append("Incompatible WOFF2 assets (selected axes or style are outside the file): " + incompatibleAssetNames.joined(separator: ", ")) }
        if excludedBytes > 0 { lines.append("Savings when excluded styles are not loaded: \(WebFontAuditFormat.bytes(excludedBytes)) across \(excludedAssetCount) asset(s)") }
        lines.append("")
        for row in rows {
            let asset = row.asset.map { "\(WebFontAuditFormat.bytes($0.byteCount)) exact WOFF2 (\($0.fileName))" } ?? (row.assetCandidateCount > 1 ? "WOFF2 ambiguous (\(row.assetCandidateCount) matches)" : row.assetIncompatible ? "WOFF2 incompatible with the selected instance" : "WOFF2 missing")
            lines.append("\(row.family) — \(row.styleName) [\(row.postScriptName)]")
            lines.append("  \(asset); \(row.usedCharacterCount) unique page characters; scripts: \(row.scriptsUsed.isEmpty ? "none detected" : row.scriptsUsed.joined(separator: ", "))")
            lines.append("  Coverage [\(row.coverageSource.rawValue)]: \(row.coverageSource == .unavailable ? "not available" : row.missingCharacters.isEmpty ? "all page characters present" : "\(row.missingCharacters.count) page characters missing"); subsetting opportunity: \(row.subsetOpportunity)")
            lines.append(row.fallback.available ? "  Fallback \(row.fallback.fallbackName): x-height \(WebFontAuditFormat.percent(row.fallback.xHeightDelta)); max width \(WebFontAuditFormat.percent(row.fallback.maxWidthDelta)); lines \(WebFontAuditFormat.signed(row.fallback.maxLineDelta))" : "  Fallback reflow unavailable: \(row.fallback.note)")
        }
        if !comparisons.isEmpty {
            lines += ["", "Variable versus static WOFF2 assets"]
            for comparison in comparisons { lines.append("\(comparison.family): \(comparison.variableFile) \(WebFontAuditFormat.bytes(comparison.variableBytes)) vs \(comparison.staticCount) static assets \(WebFontAuditFormat.bytes(comparison.staticBytes)); delta \(WebFontAuditFormat.signedBytes(comparison.delta))") }
        }
        lines += ["", "Measurements use the exact supplied WOFF2 bytes. Fallback reflow is a local Core Text proxy, not browser CLS. Coverage does not guarantee shaping. Subsetting byte savings require a real subset build and are not fabricated from glyph percentages."]
        return lines.joined(separator: "\n")
    }
}

enum WebFontAuditFormat {
    static func bytes(_ value: Int) -> String {
        let formatter = ByteCountFormatter(); formatter.allowedUnits = value < 1_000_000 ? [.useKB] : [.useMB]; formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(value))
    }
    static func percent(_ value: Double) -> String { String(format: "%+.1f%%", value * 100) }
    static func signed(_ value: Int) -> String { value == 0 ? "0" : value > 0 ? "+\(value)" : "\(value)" }
    static func signedBytes(_ value: Int) -> String { value == 0 ? "0 KB" : (value > 0 ? "+" : "−") + bytes(abs(value)) }
}

enum WebTextLayoutMetrics {
    struct Value { let lineCount: Int; let width: Double; let height: Double }
    static func attributed(style: TypeStyle, text: String, fontName: String?) -> NSAttributedString {
        let value = style.attributed(text, color: .black).mutableCopy() as! NSMutableAttributedString
        if let fontName {
            let font = OpenType.font(name: fontName, size: style.size, axes: [:], features: style.canonicalFeatures)
            value.addAttribute(.font, value: font as NSFont, range: NSRange(location: 0, length: value.length))
        }
        return value
    }
    static func measure(_ value: NSAttributedString, width: Double) -> Value {
        guard value.length > 0 else { return Value(lineCount: 0, width: 0, height: 0) }
        let framesetter = CTFramesetterCreateWithAttributedString(value)
        let path = CGPath(rect: CGRect(x: 0, y: 0, width: max(1, width), height: 100_000), transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: value.length), path, nil)
        let lines = CTFrameGetLines(frame) as? [CTLine] ?? []
        let suggested = CTFramesetterSuggestFrameSizeWithConstraints(framesetter, CFRange(location: 0, length: value.length), nil, CGSize(width: max(1, width), height: .greatestFiniteMagnitude), nil)
        let renderedWidth = lines.map { CTLineGetTypographicBounds($0, nil, nil, nil) }.max() ?? 0
        return Value(lineCount: lines.count, width: renderedWidth, height: suggested.height)
    }
}

enum WebFontAuditAnalyzer {
    static func uses(board: TypeBoard, canvasIDs: Set<UUID>) -> [WebFontUse] {
        var result: [WebFontUse] = []
        for direction in board.directions where canvasIDs.contains(direction.id) {
            let plan = CanvasPlanCache.plan(for: direction)
            for (index, element) in plan.elements.enumerated() {
                guard let style = element.style, let text = element.text?.string, !text.isEmpty else { continue }
                result.append(WebFontUse(id: direction.id.uuidString + ":" + (element.textID ?? element.sectionID + ":\(index)"), canvasID: direction.id, canvas: board.canvasName(direction), style: style, text: text, width: element.rect.width, kind: element.textKind))
            }
        }
        return result
    }

    static func report(board: TypeBoard, canvasIDs: Set<UUID>, fontNames: Set<String>, catalog: [Family], assets: [WebFontAsset]) -> WebFontAuditReport {
        let allUses = uses(board: board, canvasIDs: canvasIDs)
        let selectedUses = allUses.filter { fontNames.contains($0.style.fontName) }
        var faces: [String: (Family, Face)] = [:]
        for family in catalog { for face in family.faces where faces[face.name] == nil { faces[face.name] = (family, face) } }
        var assetCandidatesByName: [String: [(WebFontAsset, WebFontAssetFace)]] = [:]
        var seenCandidates = Set<String>()
        for asset in assets {
            for face in asset.faces {
                let key = asset.id + "|" + face.postScriptName
                if seenCandidates.insert(key).inserted { assetCandidatesByName[face.postScriptName, default: []].append((asset, face)) }
            }
        }
        func uniqueAsset(for name: String) -> (WebFontAsset, WebFontAssetFace)? {
            let candidates = assetCandidatesByName[name] ?? []
            return candidates.count == 1 ? candidates[0] : nil
        }
        func requirement(for use: WebFontUse, fallbackFace: WebFontAssetFace? = nil) -> (weight: Int, italic: Bool, axes: [Int: Double]) {
            let catalogFace = faces[use.style.fontName]?.1
            let fallbackWeight = catalogFace?.facts.weight ?? fallbackFace?.weight ?? 400
            let requestedWeight = use.style.axes[WebFontAxis.weight] ?? Double(fallbackWeight)
            let safeWeight = requestedWeight.isFinite ? min(1_000, max(1, requestedWeight.rounded())) : Double(fallbackWeight)
            var italic = catalogFace?.facts.italic ?? fallbackFace?.italic ?? false
            if let value = use.style.axes[WebFontAxis.italic], value.isFinite { italic = value > 0.01 }
            else if let value = use.style.axes[WebFontAxis.slant], value.isFinite { italic = abs(value) > 0.01 }
            return (Int(safeWeight), italic, use.style.axes)
        }
        func compatibleAsset(for name: String, uses: [WebFontUse]) -> (WebFontAsset, WebFontAssetFace)? {
            guard let candidate = uniqueAsset(for: name) else { return nil }
            return uses.allSatisfy {
                let value = requirement(for: $0, fallbackFace: candidate.1)
                return candidate.1.covers(weight: value.weight, italic: value.italic, axes: value.axes)
            } ? candidate : nil
        }
        let grouped = Dictionary(grouping: selectedUses, by: { $0.style.fontName })
        let rows = grouped.keys.sorted().map { name -> WebFontStyleAudit in
            let uses = grouped[name]!, catalogValue = faces[name]
            let assetCandidates = assetCandidatesByName[name] ?? []
            let soleCandidate = assetCandidates.count == 1 ? assetCandidates[0] : nil
            let mapped = compatibleAsset(for: name, uses: uses)
            let assetIncompatible = soleCandidate != nil && mapped == nil
            let text = uses.map(\.text).joined(separator: "\n")
            let coverage: CharacterSet?
            let coverageSource: WebFontCoverageSource
            if let mapped { coverage = mapped.1.coverage; coverageSource = .exactWebAsset }
            else if let catalogValue { coverage = catalogValue.1.coverage; coverageSource = .desktopSource }
            else { coverage = nil; coverageSource = .unavailable }
            let missing = coverage.map { FontCoverage.missing(text, in: $0) } ?? []
            let scalars = Set(text.unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) && $0.properties.generalCategory != .format }.map(\.value))
            let glyphs = mapped?.1.glyphCount
            let opportunity: String
            if let glyphs, glyphs > 0 {
                let ratio = Double(scalars.count) / Double(glyphs)
                opportunity = ratio < 0.05 ? "High (\(scalars.count) characters / \(glyphs) WOFF2 glyphs)" : ratio < 0.2 ? "Moderate (\(scalars.count) characters / \(glyphs) WOFF2 glyphs)" : "Limited (\(scalars.count) characters / \(glyphs) WOFF2 glyphs)"
            } else { opportunity = "Requires one unambiguous WOFF2 asset" }
            let family = catalogValue?.0.name ?? soleCandidate?.1.familyName ?? "Unavailable family"
            let sourceFamily = soleCandidate?.1.familyName ?? catalogValue?.1.originalFamily ?? family
            let requirements = uses.map { requirement(for: $0, fallbackFace: soleCandidate?.1) }
            let selectedWeight = requirements.first?.weight ?? 400
            let selectedItalic = requirements.contains { $0.italic }
            let fallbackName = (catalogValue?.1.facts.monospace == true ? "Menlo-Regular" : catalogValue?.0.automaticCategory == .serif ? "Times-Roman" : "Helvetica")
            let fallbackImpact: WebFallbackImpact
            if catalogValue != nil {
                let primaryFont = CTFontCreateWithName(name as CFString, 100, nil)
                let resolvedName = CTFontCopyPostScriptName(primaryFont) as String
                if resolvedName.caseInsensitiveCompare(name) == .orderedSame {
                    let fallbackFont = CTFontCreateWithName(fallbackName as CFString, 100, nil)
                    let primaryX = CTFontGetXHeight(primaryFont) / max(1, CTFontGetSize(primaryFont)), fallbackX = CTFontGetXHeight(fallbackFont) / max(1, CTFontGetSize(fallbackFont))
                    let fallbackCoverage = CTFontCopyCharacterSet(fallbackFont) as CharacterSet
                    var maxWidth = 0.0, maxHeight = 0.0, maxLines = 0, buttonDelta: Double?, fallbackMissing: [Unicode.Scalar] = []
                    for use in uses {
                        let primaryValue = WebTextLayoutMetrics.attributed(style: use.style, text: use.text, fontName: nil)
                        let primary = WebTextLayoutMetrics.measure(primaryValue, width: use.width)
                        let fallbackValue = WebTextLayoutMetrics.attributed(style: use.style, text: use.text, fontName: fallbackName)
                        let fallback = WebTextLayoutMetrics.measure(fallbackValue, width: use.width)
                        let widthDelta = (fallback.width - primary.width) / max(1, primary.width)
                        let heightDelta = (fallback.height - primary.height) / max(1, primary.height)
                        if abs(widthDelta) > abs(maxWidth) { maxWidth = widthDelta }
                        if abs(heightDelta) > abs(maxHeight) { maxHeight = heightDelta }
                        if abs(fallback.lineCount - primary.lineCount) > abs(maxLines) { maxLines = fallback.lineCount - primary.lineCount }
                        if use.kind == .buttonLabel {
                            let primaryLine = CTLineGetTypographicBounds(CTLineCreateWithAttributedString(primaryValue), nil, nil, nil)
                            let fallbackLine = CTLineGetTypographicBounds(CTLineCreateWithAttributedString(fallbackValue), nil, nil, nil)
                            let delta = fallbackLine - primaryLine
                            if buttonDelta == nil || abs(delta) > abs(buttonDelta!) { buttonDelta = delta }
                        }
                        fallbackMissing.append(contentsOf: FontCoverage.missing(use.text, in: fallbackCoverage))
                    }
                    let uniqueFallbackMissing = Dictionary(grouping: fallbackMissing, by: \.value).compactMap { $0.value.first }.sorted { $0.value < $1.value }
                    fallbackImpact = WebFallbackImpact(fallbackName: fallbackName, available: true, note: "Core Text estimate from the installed desktop source", primaryXHeight: primaryX, fallbackXHeight: fallbackX, maxWidthDelta: maxWidth, maxHeightDelta: maxHeight, maxLineDelta: maxLines, buttonWidthDelta: buttonDelta, missingScalars: uniqueFallbackMissing)
                } else {
                    fallbackImpact = WebFallbackImpact(fallbackName: fallbackName, available: false, note: "The selected font is not available as an exact installed face", primaryXHeight: 0, fallbackXHeight: 0, maxWidthDelta: 0, maxHeightDelta: 0, maxLineDelta: 0, buttonWidthDelta: nil, missingScalars: [])
                }
            } else {
                fallbackImpact = WebFallbackImpact(fallbackName: fallbackName, available: false, note: "Install the selected desktop face to measure local reflow", primaryXHeight: 0, fallbackXHeight: 0, maxWidthDelta: 0, maxHeightDelta: 0, maxLineDelta: 0, buttonWidthDelta: nil, missingScalars: [])
            }
            let desktopBytes = catalogValue?.1.url.flatMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize }
            let desktopFormat = catalogValue?.1.url?.pathExtension.uppercased()
            let instances = Set(uses.map { use in
                let axes = use.style.axes.keys.sorted().map { "\($0)=\(use.style.axes[$0]!)" }.joined(separator: ";")
                let features = use.style.canonicalFeatures.keys.sorted().map { "\($0)=\(use.style.canonicalFeatures[$0]!)" }.joined(separator: ";")
                return "\(axes)|\(use.style.size)|\(features)"
            }).count
            return WebFontStyleAudit(postScriptName: name,
                                     family: family,
                                     sourceFamily: sourceFamily,
                                     styleName: catalogValue?.1.style ?? name,
                                     weight: selectedWeight,
                                     italic: selectedItalic,
                                     useCount: uses.count,
                                     instanceCount: instances,
                                     asset: mapped?.0,
                                     assetFace: mapped?.1,
                                     assetCandidateCount: assetCandidates.count,
                                     assetIncompatible: assetIncompatible,
                                     desktopBytes: desktopBytes,
                                     desktopFormat: desktopFormat,
                                     usedCharacterCount: scalars.count,
                                     missingCharacters: missing,
                                     scriptsUsed: WebTextScript.names(in: text),
                                     supportedSystems: (mapped?.1.writingSystems ?? catalogValue?.1.writingSystems ?? []).map(\.rawValue).sorted(),
                                     coverageSource: coverageSource,
                                     glyphCount: glyphs,
                                     subsetOpportunity: opportunity,
                                     fallback: fallbackImpact,
                                     variable: mapped?.1.variable ?? false)
        }
        var selectedAssets: [String: WebFontAsset] = [:]
        for row in rows { if let asset = row.asset { selectedAssets[asset.id] = asset } }
        let knownBytes = selectedAssets.values.reduce(0) { $0 + $1.byteCount }
        let allBoardUses = uses(board: board, canvasIDs: Set(board.directions.map(\.id)))
        let allBoardUsesByName = Dictionary(grouping: allBoardUses, by: { $0.style.fontName })
        var allBoardAssets: [String: WebFontAsset] = [:]
        for (name, nameUses) in allBoardUsesByName { if let asset = compatibleAsset(for: name, uses: nameUses)?.0 { allBoardAssets[asset.id] = asset } }
        let excluded = allBoardAssets.filter { selectedAssets[$0.key] == nil }
        let relevantFamilies = Set(rows.map(\.sourceFamily))
        let comparisons = relevantFamilies.compactMap { sourceFamily -> WebFontComparison? in
            let familyCandidates: [(WebFontAsset, WebFontAssetFace)] = assets.flatMap { asset in asset.faces.filter { $0.familyName.caseInsensitiveCompare(sourceFamily) == .orderedSame }.map { (asset, $0) } }
            let familyUses = selectedUses.filter { use in
                let mapped = uniqueAsset(for: use.style.fontName)?.1
                let value = mapped?.familyName ?? faces[use.style.fontName]?.1.originalFamily
                return value?.caseInsensitiveCompare(sourceFamily) == .orderedSame
            }
            let staticAxes = Set([WebFontAxis.weight, WebFontAxis.italic, WebFontAxis.slant])
            let staticallyRepresentable = familyUses.allSatisfy { use in
                let axes = use.style.axes
                guard Set(axes.keys).isSubset(of: staticAxes) else { return false }
                if let italic = axes[WebFontAxis.italic], !italic.isFinite || (abs(italic) > 0.001 && abs(italic - 1) > 0.001) { return false }
                if let slant = axes[WebFontAxis.slant], !slant.isFinite || abs(slant) > 0.001 { return false }
                return true
            }
            guard staticallyRepresentable else { return nil }
            let required: [(weight: Int, italic: Bool, axes: [Int: Double])] = familyUses.map { use in
                let mapped = uniqueAsset(for: use.style.fontName)?.1
                return requirement(for: use, fallbackFace: mapped)
            }
            guard !required.isEmpty else { return nil }
            var variableAssets: [String: WebFontAsset] = [:]
            for candidate in familyCandidates where candidate.1.variable && required.allSatisfy({ candidate.1.covers(weight: $0.weight, italic: $0.italic, axes: $0.axes) }) { variableAssets[candidate.0.id] = candidate.0 }
            guard variableAssets.count == 1, let variable = variableAssets.values.first else { return nil }
            var chosenStatics: [String: WebFontAsset] = [:]
            for item in required {
                var matches: [String: WebFontAsset] = [:]
                for candidate in familyCandidates where !candidate.1.variable && candidate.1.weight == item.weight && candidate.1.italic == item.italic { matches[candidate.0.id] = candidate.0 }
                guard matches.count == 1, let match = matches.values.first else { return nil }
                chosenStatics[match.id] = match
            }
            guard !chosenStatics.isEmpty else { return nil }
            return WebFontComparison(family: sourceFamily, variableFile: variable.fileName, variableBytes: variable.byteCount, staticCount: chosenStatics.count, staticBytes: chosenStatics.values.reduce(0) { $0 + $1.byteCount })
        }.sorted { $0.family.localizedStandardCompare($1.family) == .orderedAscending }
        return WebFontAuditReport(rows: rows,
                                  knownBytes: knownBytes,
                                  missingAssetNames: rows.filter { $0.assetCandidateCount == 0 }.map(\.postScriptName),
                                  ambiguousAssetNames: rows.filter { $0.assetCandidateCount > 1 }.map(\.postScriptName),
                                  incompatibleAssetNames: rows.filter(\.assetIncompatible).map(\.postScriptName),
                                  excludedBytes: excluded.values.reduce(0) { $0 + $1.byteCount },
                                  excludedAssetCount: excluded.count,
                                  comparisons: comparisons,
                                  canvasCount: canvasIDs.count)
    }
}

final class WebFontAuditCancellation {
    private let lock = NSLock()
    private var cancelled = false
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
}

enum WebFontAuditWork {
    static let analysis = DispatchQueue(label: "FontShelf.web-font-audit", qos: .userInitiated)
}

struct WebFontAuditView: View {
    let board: TypeBoard
    @ObservedObject var library: Library
    @Environment(\.dismiss) private var dismiss
    @State private var canvasIDs: Set<UUID>
    @State private var fontNames: Set<String> = []
    @State private var assets: [WebFontAsset] = []
    @State private var report = WebFontAuditReport.empty
    @State private var message = ""
    @State private var assetScanToken = UUID()
    @State private var analysisToken = UUID()
    @State private var loadingAssets = false
    @State private var analyzing = false
    @State private var inaccessibleFolderNames: Set<String> = []
    @State private var analysisCancellation: WebFontAuditCancellation?

    init(board: TypeBoard, library: Library, initialCanvasIDs: Set<UUID>) {
        self.board = board
        self.library = library
        _canvasIDs = State(initialValue: initialCanvasIDs.isEmpty ? Set(board.directions.map(\.id)) : initialCanvasIDs)
    }

    var availableFontNames: [String] { Array(Set(WebFontAuditAnalyzer.uses(board: board, canvasIDs: canvasIDs).map { $0.style.fontName })).sorted() }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) { Text("What will this typography cost my page?").font(.title2); Text("Exact web assets, character coverage, and fallback reflow for the canvases you choose.").foregroundStyle(.secondary) }
                Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding(20)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    scope
                    assetsSection
                    styleScope
                    summary
                    styleRows
                    if !report.comparisons.isEmpty { comparisons }
                    Text("Exact transfer totals require the licensed WOFF2 files your site will ship. Desktop TTF/OTF sizes are shown only as source context and never converted into fake WOFF2 numbers. Fallback measurements are a local Core Text reflow proxy, not Web Vitals CLS; browsers may shape and resolve system fallbacks differently. Coverage does not prove shaping or regional-form support. Subsetting opportunities show glyph utilization, while exact byte savings require a real subset build.").font(.caption).foregroundStyle(.secondary)
                }.padding(20)
            }
            Divider()
            HStack {
                if analyzing { ProgressView().controlSize(.small) }
                Text(message).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                Spacer()
                Button("Copy report") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(report.text, forType: .string); message = "Web-font report copied" }
            }.padding(14)
        }.frame(width: min(980, max(680, (NSScreen.main?.visibleFrame.width ?? 1_060) - 80)), height: min(780, max(560, (NSScreen.main?.visibleFrame.height ?? 880) - 100))).onAppear { loadAssets(); resetStyles() }.onDisappear { assetScanToken = UUID(); analysisToken = UUID(); analysisCancellation?.cancel() }
    }

    var scope: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Canvases to test").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 14) { ForEach(board.directions) { canvas in
                Toggle(board.canvasName(canvas), isOn: Binding(get: { canvasIDs.contains(canvas.id) }, set: { included in
                    if included { canvasIDs.insert(canvas.id) } else if canvasIDs.count > 1 { canvasIDs.remove(canvas.id) }
                    resetStyles()
                })).toggleStyle(.checkbox).disabled(canvasIDs.count == 1 && canvasIDs.contains(canvas.id))
            } } }
        }
    }

    var assetsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { Text("Licensed web assets").font(.caption.weight(.semibold)).foregroundStyle(.secondary); if loadingAssets { ProgressView().controlSize(.small) }; Spacer(); Button("Refresh") { loadAssets() }.disabled(loadingAssets); Button("Add WOFF2 folder…") { addFolder() }.disabled(loadingAssets) }
            let paths = library.saved.webAssetFolders ?? []
            if paths.isEmpty { Text("No web-asset folder added. Installed WOFF2 sources are detected automatically; other selected styles will be marked missing.").foregroundStyle(.secondary) }
            else { ForEach(paths, id: \.self) { path in HStack { let name = URL(fileURLWithPath: path).lastPathComponent; Label(name, systemImage: inaccessibleFolderNames.contains(name) ? "exclamationmark.triangle" : "folder"); Text(inaccessibleFolderNames.contains(name) ? "· access needs renewal" : "· \(assets.filter { $0.url.path.hasPrefix(path + "/") || $0.url.deletingLastPathComponent().path == path }.count) WOFF2").foregroundStyle(inaccessibleFolderNames.contains(name) ? Color.orange : Color.secondary); Spacer(); Button("Remove") { removeFolder(path) }.buttonStyle(.borderless) } } }
        }.padding(14).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
    }

    var styleScope: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Styles to load").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), alignment: .leading)], alignment: .leading, spacing: 7) {
                ForEach(availableFontNames, id: \.self) { name in Toggle(name, isOn: Binding(get: { fontNames.contains(name) }, set: { included in if included { fontNames.insert(name) } else { fontNames.remove(name) }; analyze() })).toggleStyle(.checkbox) }
            }
        }
    }

    var summary: some View {
        HStack(spacing: 12) {
            let unresolved = report.missingAssetNames.count + report.ambiguousAssetNames.count + report.incompatibleAssetNames.count
            card("Known WOFF2", WebFontAuditFormat.bytes(report.knownBytes), unresolved == 0 ? "Complete selected payload" : "+ \(report.missingAssetNames.count) missing · \(report.ambiguousAssetNames.count) ambiguous · \(report.incompatibleAssetNames.count) incompatible")
            card("Styles", "\(report.rows.count)", "\(report.rows.filter { $0.variable }.count) variable")
            card("Excludable vs typeboard", WebFontAuditFormat.bytes(report.excludedBytes), report.excludedAssetCount == 0 ? "No unselected mapped assets" : "\(report.excludedAssetCount) mapped asset(s)")
            let risks = report.rows.filter { $0.fallback.available }.map { max(abs($0.fallback.maxWidthDelta), abs($0.fallback.maxHeightDelta)) }
            card("Fallback reflow", risks.max().map { WebFontAuditFormat.percent($0) } ?? "Unavailable", "largest local difference")
        }
    }
    func card(_ title: String, _ value: String, _ note: String) -> some View { VStack(alignment: .leading, spacing: 5) { Text(title).font(.caption2).foregroundStyle(.secondary); Text(value).font(.title3).monospacedDigit(); Text(note).font(.caption).foregroundStyle(.secondary) }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 9)) }

    var styleRows: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Style details").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(report.rows) { row in
                VStack(alignment: .leading, spacing: 9) {
                    HStack { VStack(alignment: .leading) { Text(row.family + " · " + row.styleName).font(.headline); Text(row.postScriptName).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }; Spacer(); if let asset = row.asset { Text(WebFontAuditFormat.bytes(asset.byteCount) + " WOFF2").monospacedDigit(); Text("Exact").font(.caption).foregroundStyle(.green) } else if row.assetCandidateCount > 1 { Text("WOFF2 ambiguous · \(row.assetCandidateCount) matches").foregroundStyle(.orange) } else if row.assetIncompatible { Text("WOFF2 incompatible with selected axes/style").foregroundStyle(.orange) } else { Text("WOFF2 missing").foregroundStyle(.orange) } }
                    if row.asset == nil, let bytes = row.desktopBytes { Text("Desktop source: \(row.desktopFormat ?? "font") · \(WebFontAuditFormat.bytes(bytes)). This is not counted as web transfer.").font(.caption).foregroundStyle(.secondary) }
                    HStack(alignment: .top, spacing: 24) {
                        detail("Page use", "\(row.useCount) text element(s) · \(row.instanceCount) setting(s)\n\(row.usedCharacterCount) unique characters" + (row.glyphCount.map { " · \($0) WOFF2 glyphs" } ?? "") + "\nSubsetting opportunity: \(row.subsetOpportunity)")
                        detail("Coverage · \(row.coverageSource.rawValue)", (row.coverageSource == .unavailable ? "Add one unambiguous WOFF2 asset or install the desktop face" : row.missingCharacters.isEmpty ? "All required characters present" : "Missing: " + row.missingCharacters.prefix(12).map { "\(String($0)) U+\(String(format: "%04X", $0.value))" }.joined(separator: " · ")) + "\nPage scripts: " + (row.scriptsUsed.isEmpty ? "none detected" : row.scriptsUsed.joined(separator: ", ")) + "\nBroad probes: " + (row.supportedSystems.isEmpty ? "none" : row.supportedSystems.joined(separator: ", ")))
                        detail(row.fallback.available ? "Fallback · \(row.fallback.fallbackName)" : "Fallback reflow", row.fallback.available ? "x-height \(String(format: "%.2f", row.fallback.primaryXHeight)) → \(String(format: "%.2f", row.fallback.fallbackXHeight)) (\(WebFontAuditFormat.percent(row.fallback.xHeightDelta)))\nWidth \(WebFontAuditFormat.percent(row.fallback.maxWidthDelta)) · height \(WebFontAuditFormat.percent(row.fallback.maxHeightDelta)) · lines \(WebFontAuditFormat.signed(row.fallback.maxLineDelta))" + (row.fallback.buttonWidthDelta.map { "\nButton width \(String(format: "%+.1f px", $0))" } ?? "") + (row.fallback.missingScalars.isEmpty ? "" : "\nFallback misses \(row.fallback.missingScalars.count) character(s); Core Text may cascade") : row.fallback.note)
                    }
                }.padding(14).background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 10))
            }
            if report.rows.isEmpty { Text("Select at least one style used by the chosen canvases.").foregroundStyle(.secondary).padding(20) }
        }
    }
    func detail(_ title: String, _ value: String) -> some View { VStack(alignment: .leading, spacing: 4) { Text(title).font(.caption2).foregroundStyle(.secondary); Text(value).font(.caption).fixedSize(horizontal: false, vertical: true).textSelection(.enabled) }.frame(maxWidth: .infinity, alignment: .leading) }

    var comparisons: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Variable vs chosen static styles · exact compatible assets").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(report.comparisons) { item in HStack { Text(item.family).font(.headline); Spacer(); Text("Variable \(WebFontAuditFormat.bytes(item.variableBytes))"); Image(systemName: "arrow.left.arrow.right"); Text("\(item.staticCount) static \(WebFontAuditFormat.bytes(item.staticBytes))"); Text(item.delta >= 0 ? "Variable saves \(WebFontAuditFormat.bytes(item.delta))" : "Static saves \(WebFontAuditFormat.bytes(-item.delta))").foregroundStyle(item.delta >= 0 ? Color.green : Color.secondary) }.padding(12).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8)) }
        }
    }

    func resolvedFolders() -> (paths: [String], failures: Set<String>) {
        var paths: [String] = [], failures = Set<String>()
        for path in library.saved.webAssetFolders ?? [] {
            do { paths.append(try library.folderAccess.restore(path)) }
            catch { failures.insert(URL(fileURLWithPath: path).lastPathComponent) }
        }
        return (paths, failures)
    }
    func loadAssets() {
        let token = UUID(), resolved = resolvedFolders(), catalog = library.families
        inaccessibleFolderNames = resolved.failures
        assetScanToken = token; loadingAssets = true; message = resolved.failures.isEmpty ? "Reading WOFF2 metadata…" : "Reading available WOFF2 assets; renew access for \(resolved.failures.sorted().joined(separator: ", "))"
        DispatchQueue.global(qos: .userInitiated).async {
            let found = WebFontAssetResolver.scan(folders: resolved.paths, catalog: catalog)
            DispatchQueue.main.async {
                guard assetScanToken == token else { return }
                assets = found; loadingAssets = false
                let result = found.isEmpty ? "No exact WOFF2 assets found" : "Read \(found.count) exact WOFF2 asset\(found.count == 1 ? "" : "s")"
                message = resolved.failures.isEmpty ? result : result + " · renew access for " + resolved.failures.sorted().joined(separator: ", ")
                analyze()
            }
        }
    }
    func resetStyles() { fontNames = Set(availableFontNames); analyze() }
    func analyze() {
        let token = UUID(), selectedBoard = board, selectedCanvases = canvasIDs, selectedFonts = fontNames, catalog = library.families, exactAssets = assets
        analysisCancellation?.cancel()
        let cancellation = WebFontAuditCancellation()
        analysisCancellation = cancellation; analysisToken = token; analyzing = true
        WebFontAuditWork.analysis.asyncAfter(deadline: .now() + .milliseconds(120)) {
            guard !cancellation.isCancelled else { return }
            let value = WebFontAuditAnalyzer.report(board: selectedBoard, canvasIDs: selectedCanvases, fontNames: selectedFonts, catalog: catalog, assets: exactAssets)
            guard !cancellation.isCancelled else { return }
            DispatchQueue.main.async { guard analysisToken == token, !cancellation.isCancelled else { return }; report = value; analyzing = false; analysisCancellation = nil }
        }
    }
    func addFolder() {
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = false; panel.allowsMultipleSelection = false; panel.title = "Add licensed WOFF2 folder"; panel.prompt = "Use folder"; panel.message = "Typefield reads exact WOFF2 sizes and metadata. It does not copy, register, convert, or upload these assets."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try library.folderAccess.remember(url)
            var paths = library.saved.webAssetFolders ?? []
            if !paths.contains(url.path) { paths.append(url.path); library.saved.webAssetFolders = paths; guard library.save() else { throw NSError(domain: "FontShelf", code: 1, userInfo: [NSLocalizedDescriptionKey: library.message]) } }
            loadAssets(); message = "Loaded exact WOFF2 metadata from \(url.lastPathComponent)"
        } catch { message = "Could not remember that folder: " + error.localizedDescription }
    }
    func removeFolder(_ path: String) { library.saved.webAssetFolders?.removeAll { $0 == path }; library.save(); loadAssets(); message = "Removed web-asset folder" }
}
