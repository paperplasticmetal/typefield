import AppKit
import CoreText

/// A local, dependency-free handoff. Font binaries are deliberately never copied.
enum DeveloperHandoff {
    struct Entry {
        let key: String, board: String, canvas: String, label: String
        let style: TypeStyle
    }
    struct FontAsset {
        let name: String, alias: String, file: String, fallback: String
        let face: Face?
        var weight: Int { face?.facts.weight ?? 400 }
        var italic: Bool { face?.facts.italic ?? false }
    }
    static func entries(_ boards: [TypeBoard]) -> [Entry] {
        var result: [Entry] = []
        for (b, board) in boards.enumerated() {
            for (c, canvas) in board.directions.enumerated() {
                let prefix = "b\(b + 1)-c\(c + 1)"
                func append(_ label: String, _ key: String, _ style: TypeStyle) {
                    result.append(Entry(key: prefix + "-" + key, board: board.name, canvas: board.canvasName(canvas), label: label, style: style))
                }
                if canvas.canvas != .imported {
                    for role in TypeRole.allCases { append(role.rawValue, String(describing: role), canvas.style(role)) }
                }
                // Include visible, individually edited text and template overrides, not just shared roles.
                for (i, element) in CanvasPlan(direction: canvas).elements.enumerated() {
                    guard let style = element.style, element.text != nil else { continue }
                    if let role = element.role, style == canvas.style(role), canvas.canvas != .imported { continue }
                    append(element.role?.rawValue ?? "Text layer \(i + 1)", "text-\(i + 1)", style)
                }
            }
        }
        return result
    }
    static func number(_ value: Double) -> String { String(format: "%.5f", locale: Locale(identifier: "en_US_POSIX"), value).replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression) }
    static func html(_ value: String) -> String { value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;").replacingOccurrences(of: "'", with: "&#39;") }
    static func cssString(_ value: String) -> String {
        "\"" + value.unicodeScalars.map { scalar in
            scalar.value < 32 || [34, 60, 62, 92, 127].contains(scalar.value) ? "\\\(String(scalar.value, radix: 16)) " : String(scalar)
        }.joined() + "\""
    }
    static func quoted(_ value: String) -> String {
        "\"" + value.unicodeScalars.map { scalar -> String in
            switch scalar.value { case 34: return "\\\""; case 92: return "\\\\"; case 10: return "\\n"; case 13: return "\\r"; case 9: return "\\t"; case 0...31, 127: return "\\u{\(String(scalar.value, radix: 16))}"; default: return String(scalar) }
        }.joined() + "\""
    }
    static func json(_ object: Any) throws -> String { String(decoding: try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed, .withoutEscapingSlashes]), as: UTF8.self) }
    static func kotlin(_ value: String) -> String { (try! json(value)).replacingOccurrences(of: "$", with: "\\$") }
    static func tag(_ id: Int) -> String? {
        guard id >= 0, id <= Int(UInt32.max) else { return nil }
        let value = String(bytes: [24, 16, 8, 0].map { UInt8((id >> $0) & 255) }, encoding: .ascii) ?? ""
        return validTag(value) ? value : nil
    }
    static func validTag(_ value: String) -> Bool { value.utf8.count == 4 && value.utf8.allSatisfy { (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) } }
    static func axes(_ style: TypeStyle) -> [String: Double] { Dictionary(uniqueKeysWithValues: style.axes.compactMap { id, value in tag(id).map { ($0, value) } }) }
    static func features(_ style: TypeStyle) -> [String: Int] {
        style.canonicalFeatures.filter { validTag($0.key) }
    }
    static func settings<T>(_ values: [String: T]) -> String { values.isEmpty ? "normal" : values.keys.sorted().map { "\"\($0)\" \(values[$0]!)" }.joined(separator: ", ") }
    static func fluid(_ size: Double) -> String {
        guard size > 20 else { return "\(number(size / 16))rem" }
        let minimum = max(20, size * 0.75), slope = (size - minimum) / 880
        return "clamp(\(number(minimum / 16))rem, \(number((minimum - slope * 320) / 16))rem + \(number(slope * 100))vw, \(number(size / 16))rem)"
    }
    static func selectFolder(title: String, boards: [TypeBoard], catalog: [Family]) throws -> URL? {
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true
        panel.title = "Export developer handoff"; panel.prompt = "Export handoff"
        panel.message = "All canvases → CSS, Tailwind, tokens, SwiftUI, Compose and an HTML specimen. Font files are not included; licensed assets must be supplied separately."
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return try write(title: title, boards: boards, catalog: catalog, parent: url)
    }
    static func write(title: String, boards: [TypeBoard], catalog: [Family], parent: URL) throws -> URL {
        guard !boards.isEmpty, boards.allSatisfy(\.isValid) else { throw NSError(domain: "FontShelfHandoff", code: 1, userInfo: [NSLocalizedDescriptionKey: "Add a valid typeboard before exporting a handoff."]) }
        let items = entries(boards)
        guard !items.isEmpty else { throw NSError(domain: "FontShelfHandoff", code: 2, userInfo: [NSLocalizedDescriptionKey: "There are no visible text styles to export."]) }
        guard items.allSatisfy({ item in
            let s = item.style
            return [s.size, s.leading, s.tracking, s.lineHeight ?? s.size * s.leading, s.paragraphSpacing ?? 0, s.indent ?? 0, s.wordSpacing ?? 0].allSatisfy { $0.isFinite && abs($0) <= 1_000_000 } && s.size > 0 && (s.lineHeight ?? s.size * s.leading) > 0 && s.axes.values.allSatisfy { $0.isFinite && abs($0) <= 1_000_000 }
        }) else { throw NSError(domain: "FontShelfHandoff", code: 3, userInfo: [NSLocalizedDescriptionKey: "A text style contains invalid or out-of-range values. Check its size, spacing and variable axes before exporting."]) }
        let assets = Set(items.map { $0.style.fontName }).sorted().enumerated().map { i, name -> FontAsset in
            let family = catalog.first { $0.faces.contains { $0.name == name } }
            let face = family?.faces.first { $0.name == name }
            let fallback = face?.facts.monospace == true ? "ui-monospace, Menlo, Consolas, monospace" : family?.automaticCategory == .serif ? "Georgia, 'Times New Roman', serif" : "system-ui, -apple-system, 'Segoe UI', sans-serif"
            return FontAsset(name: name, alias: "FontShelf \(i + 1)", file: "fonts/font_\(i + 1).woff2", fallback: fallback, face: face)
        }
        let byName = Dictionary(uniqueKeysWithValues: assets.map { ($0.name, $0) })
        var css = "/* FontShelf: supply licensed WOFF2 assets before deployment. See README.md. */\n"
        var manifest: [[String: Any]] = []
        for asset in assets {
            let font = CTFontCreateWithName(asset.name as CFString, 1000, nil)
            let ranges = asset.face == nil ? [] : (CTFontCopyVariationAxes(font) as? [[String: Any]] ?? []).compactMap { axis -> [String: Any]? in
                guard let id = axis[kCTFontVariationAxisIdentifierKey as String] as? Int, let tag = tag(id) else { return nil }
                return ["tag": tag, "min": axis[kCTFontVariationAxisMinimumValueKey as String] ?? 0, "max": axis[kCTFontVariationAxisMaximumValueKey as String] ?? 0, "default": axis[kCTFontVariationAxisDefaultValueKey as String] ?? 0]
            }
            let weightRange = ranges.first { $0["tag"] as? String == "wght" }
            let weight = weightRange.map { "\($0["min"]!) \($0["max"]!)" } ?? String(asset.weight)
            css += "@font-face { font-family: '\(asset.alias)'; src: url('\(asset.file)') format('woff2'); font-weight: \(weight); font-style: \(asset.italic ? "italic" : "normal"); font-display: swap; }\n"
            var record: [String: Any] = ["postScriptName": asset.name, "cssFamily": asset.alias, "requiredWebAsset": asset.file, "assetIncluded": false, "availableOnExportingMac": asset.face != nil, "fallbackStack": asset.fallback, "weight": asset.weight, "italic": asset.italic, "axes": ranges, "sourceFormat": asset.face?.url?.pathExtension.lowercased() ?? "unknown", "fontDisplayRecommendation": "swap", "licenseStatus": "Not verified. Obtain web and app embedding rights."]
            if asset.face != nil { record["metricsAt1000px"] = ["ascent": CTFontGetAscent(font), "descent": CTFontGetDescent(font), "lineGap": CTFontGetLeading(font), "capHeight": CTFontGetCapHeight(font), "xHeight": CTFontGetXHeight(font)] }
            manifest.append(record)
        }
        css += "\n:root {\n"
        var tokens: [String: Any] = [:], sizes: [String: Any] = [:], families: [String: Any] = [:]
        var classes = "", theme = "@import \"tailwindcss\";\n@import \"./typography.css\";\n\n@theme inline {\n"
        var cards = "", swiftEntries: [String] = [], composeEntries: [String] = []
        for entry in items {
            let s = entry.style, a = byName[s.fontName]!, key = entry.key
            let axis = axes(s), feature = features(s), line = s.lineHeight ?? s.size * s.leading
            let weight = min(1000, max(1, axis["wght"] ?? Double(a.weight)))
            let alignment = s.alignment == .justified ? "justify" : (s.alignment ?? .left).rawValue.lowercased()
            let casing = s.casing == .upper ? "uppercase" : s.casing == .lower ? "lowercase" : "none"
            let decoration = [s.underline == true ? "underline" : nil, s.strikethrough == true ? "line-through" : nil].compactMap { $0 }.joined(separator: " ")
            let stack = "'\(a.alias)', \(a.fallback)"
            css += "  --\(key)-font: \(stack);\n  --\(key)-size: \(fluid(s.size));\n  --\(key)-line-height: \(number(line / s.size));\n  --\(key)-tracking: \(number(s.tracking / s.size))em;\n"
            classes += ".fs-\(key) { font-family: var(--\(key)-font); font-size: var(--\(key)-size); line-height: var(--\(key)-line-height); letter-spacing: var(--\(key)-tracking); font-weight: \(number(weight)); font-style: \(a.italic ? "italic" : "normal"); font-synthesis: none; font-variation-settings: \(settings(axis)); font-feature-settings: \(settings(feature)); font-kerning: \(s.effectiveKerning ? "normal" : "none"); text-align: \(alignment); text-transform: \(casing); text-decoration: \(decoration.isEmpty ? "none" : decoration); word-spacing: \(number(s.wordSpacing ?? 0))px; text-indent: \(number(s.indent ?? 0))px; margin-block: 0 \(number(s.paragraphSpacing ?? 0))px; }\n"
            let value: [String: Any] = ["fontFamily": s.fontName, "fontSize": s.size, "fontSizeUnit": "px", "fontWeight": weight, "fontStyle": a.italic ? "italic" : "normal", "lineHeight": line, "letterSpacing": s.tracking, "wordSpacing": s.wordSpacing ?? 0, "paragraphSpacing": s.paragraphSpacing ?? 0, "firstLineIndent": s.indent ?? 0, "alignment": alignment, "textTransform": casing, "decoration": decoration, "axes": axis, "features": feature, "fallbackStack": a.fallback, "fluidCSS": fluid(s.size)]
            tokens[key] = ["$type": "typography", "$value": value, "board": entry.board, "canvas": entry.canvas, "role": entry.label, "sampleText": s.text]
            sizes[key] = ["var(--\(key)-size)", ["lineHeight": "var(--\(key)-line-height)", "letterSpacing": "var(--\(key)-tracking)", "fontWeight": number(weight)]]
            families[key] = ["var(--\(key)-font)"]
            theme += "  --font-\(key): var(--\(key)-font);\n  --text-\(key): var(--\(key)-size);\n  --text-\(key)--line-height: var(--\(key)-line-height);\n  --text-\(key)--letter-spacing: var(--\(key)-tracking);\n  --text-\(key)--font-weight: \(number(weight));\n"
            cards += "<article><p class='meta'>\(html(entry.board)) / \(html(entry.canvas)) · \(html(entry.label))</p><p class='sample fs-\(key)'>\(html(s.text))</p><p class='meta'>\(html(s.fontName)) · \(number(s.size)) px · line \(number(line)) px · tracking \(number(s.tracking)) px</p><code>.fs-\(key)</code></article>\n"
            let swiftAxes = s.axes.keys.sorted().map { "\($0): \(number(s.axes[$0]!))" }.joined(separator: ", ")
            let swiftFeatures = feature.keys.sorted().map { "\(quoted($0)): \(feature[$0]!)" }.joined(separator: ", ")
            swiftEntries.append("        \(quoted(key)): Style(postScriptName: \(quoted(s.fontName)), size: \(number(s.size)), lineHeight: \(number(line)), tracking: \(number(s.tracking)), axes: [\(swiftAxes.isEmpty ? ":" : swiftAxes)], features: [\(swiftFeatures.isEmpty ? ":" : swiftFeatures)], sample: \(quoted(s.text)))")
            let kotlinAxes = axis.keys.sorted().map { "\(kotlin($0)) to \(number(axis[$0]!))f" }.joined(separator: ", ")
            let align = s.alignment == .center ? "Center" : s.alignment == .right ? "Right" : s.alignment == .justified ? "Justify" : "Left"
            composeEntries.append("        \(kotlin(key)) to Spec(\(kotlin(s.fontName)), mapOf(\(kotlinAxes)), \(kotlin(s.text)), TextStyle(fontFamily = resolveFont(\(kotlin(s.fontName)), mapOf(\(kotlinAxes))), fontSize = \(number(s.size)).sp, lineHeight = \(number(line)).sp, letterSpacing = \(number(s.tracking)).sp, fontWeight = FontWeight(\(Int(weight))), fontStyle = FontStyle.\(a.italic ? "Italic" : "Normal"), fontFeatureSettings = \(kotlin(settings(feature) == "normal" ? "" : settings(feature))), textAlign = TextAlign.\(align)))")
        }
        css += "}\n\n" + classes; theme += "}\n"
        // Preview can use fonts installed on the recipient's Mac; production CSS uses explicit assets.
        var specimenCSS = css
        for asset in assets { specimenCSS = specimenCSS.replacingOccurrences(of: "src: url('\(asset.file)')", with: "src: local(\(cssString(asset.name))), url('\(asset.file)')") }
        let missing = assets.filter { $0.face == nil }.map(\.name)
        let tokenDocument: [String: Any] = ["format": "FontShelf typography handoff", "version": 1, "title": title, "units": "Saved values: CSS px / SwiftUI pt / Compose sp. Validate on target devices.", "fluidDefaults": ["minimumViewportPx": 320, "maximumViewportPx": 1200, "rootFontSizePx": 16, "minimumSizeFactor": 0.75, "minimumFluidSizePx": 20], "typography": tokens, "sourceBoards": try JSONSerialization.jsonObject(with: JSONEncoder().encode(boards))]
        let preloads = assets.prefix(2).map { "<link rel=\"preload\" href=\"\($0.file)\" as=\"font\" type=\"font/woff2\" crossorigin>" }.joined(separator: "\n")
        let specimen = """
        <!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>\(html(title)) — FontShelf handoff</title>
        <style>\(specimenCSS)
        *{box-sizing:border-box}body{margin:0;background:#f5f3ed;color:#242421;font:16px/1.55 system-ui,sans-serif}main{max-width:1200px;margin:auto;padding:48px 24px}h1{font-size:36px;line-height:1.2;overflow-wrap:anywhere}.intro{max-width:760px}.notice{padding:18px 22px;background:#eee3b8;border-radius:12px}article{background:#fffefa;padding:28px;margin:24px 0;border:1px solid #dedbd3;border-radius:12px;overflow-wrap:anywhere}.meta{font:13px/1.6 system-ui,sans-serif;color:#66645f}.sample{white-space:pre-wrap;overflow-wrap:anywhere;margin-top:22px;margin-bottom:22px}code{font:12px/1.6 ui-monospace,monospace}a{color:inherit}@media print{body{background:white}main{padding:0}article{break-inside:avoid;border-radius:0}.notice{background:white;border:1px solid #aaa}}
        </style></head><body><main><p class="meta">FONTSHELF / DEVELOPER HANDOFF</p><h1>\(html(title))</h1><div class="intro"><p>\(boards.count) typeboard(s) · \(boards.reduce(0) { $0 + $1.directions.count }) canvases · \(items.count) text styles.</p><p class="notice">Font files are not bundled. This preview uses locally installed fonts when available, then licensed WOFF2 assets at the paths in fonts.json, then fallback fonts. It is a typography specimen, not a pixel-perfect canvas export.</p><p>Sizes above 20 px use a suggested fluid scale between 320 and 1200 px viewports. Saved maximum sizes and exact source data are in tokens.json. Print this page to save a PDF.</p><p>\(missing.isEmpty ? "All requested fonts were available on the exporting Mac." : "Unavailable on exporting Mac: " + html(missing.joined(separator: ", ")))</p></div>\(cards)</main></body></html>
        """
        let swift = """
        // Generated by FontShelf. Register licensed fonts in your app before use.
        // Fixed saved sizes; Dynamic Type and paragraph layout need app-specific integration.
        import SwiftUI
        import CoreText

        enum FontShelfTypography {
            struct Style {
                let postScriptName: String
                let size: CGFloat
                let lineHeight: CGFloat
                let tracking: CGFloat
                let axes: [Int: Double]
                let features: [String: Int]
                let sample: String
                var font: Font {
                    let base = CTFontCreateWithName(postScriptName as CFString, size, nil)
                    let attributes: [CFString: Any] = [kCTFontVariationAttribute: axes, kCTFontFeatureSettingsAttribute: features.map { [kCTFontOpenTypeFeatureTag: $0.key, kCTFontOpenTypeFeatureValue: $0.value] }]
                    let descriptor = CTFontDescriptorCreateWithAttributes(attributes as CFDictionary)
                    return Font(CTFontCreateCopyWithAttributes(base, size, nil, descriptor))
                }
                // Apply .tracking(tracking). SwiftUI lineSpacing is NOT an exact line-height setter.
                // Use tokens.json or an attributed text renderer for exact paragraph spacing/alignment.
            }
            static let styles: [String: Style] = [
        \(swiftEntries.joined(separator: ",\n"))
            ]
        }
        """
        let compose = """
        // Generated by FontShelf. Add your package declaration and licensed res/font assets.
        import androidx.compose.ui.text.TextStyle
        import androidx.compose.ui.text.font.FontFamily
        import androidx.compose.ui.text.font.FontStyle
        import androidx.compose.ui.text.font.FontWeight
        import androidx.compose.ui.text.style.TextAlign
        import androidx.compose.ui.unit.sp

        object FontShelfTypography {
            data class Spec(val postScriptName: String, val axes: Map<String, Float>, val sample: String, val style: TextStyle)
            // Resolve each PostScript name + axis map to your own bundled FontFamily.
            // Variable fonts require Android API 26+; supply static alternatives on older devices.
            // See README for FontVariation.Settings integration. No guessed R.font IDs.
            fun styles(resolveFont: (String, Map<String, Float>) -> FontFamily): Map<String, Spec> = mapOf(
        \(composeEntries.joined(separator: ",\n"))
            )
        }
        """
        let readme = """
        # FontShelf developer handoff

        Open index.html for the standalone, printable specimen. No scripts, CDN, analytics or network services are required. This is a type-system handoff, not a full website or exact canvas-layout export.

        ## Start here
        1. Review fonts.json. Obtain the correct **web and app embedding licenses**; FontShelf does not verify redistribution rights. No font binaries or local file paths are included.
        2. Supply licensed WOFF2 assets at the numbered fonts/ paths in the manifest. These are placeholders, NOT converted files. Do not rename TTF/OTF/TTC to WOFF2. Collections may need separately licensed individual web faces. Retain the exact style/axis support; check metadata after conversion.
        3. Import typography.css and use a class such as `.fs-\(items[0].key)`. Font families use unique aliases to avoid static-style collisions. Missing fonts fall back visibly; metadata for unavailable fonts is unknown/defaulted, not a measurement of a substitute.
        4. Use tokens.json as the source of truth. It has a versioned FontShelf schema using $type/$value conventions, NOT a promise of DTCG or token-plugin compatibility. sourceBoards preserves all saved canvas text, colors, settings and layout data.

        ## Fluid scale and web behavior
        Above 20 px, generated sizes interpolate from max(20 px, 75% of saved size) at 320 px to the saved size at 1200 px. Smaller roles remain fixed rem values. These are suggested defaults, not designer-authored breakpoints. Calculations assume a 16 px root; browser font-size preferences remain respected through rem. Line height and tracking scale proportionally. Native definitions use the saved fixed sizes, not the fluid formula.

        font-display: swap is the default recommendation for immediately readable text. Consider optional for nonessential typography when layout stability matters more than showing the custom face; review fallback metrics and layout shifts in a real browser. preload.html contains at most two example candidates, not a loading prescription: keep ONLY fonts used above the fold on the actual page, after adding licensed files. Cross-origin preloads need matching CORS headers. No preloads are embedded in the specimen.

        ## Tailwind
        v3: merge theme.extend from tailwind.config.cjs into your config, keep your own content globs, and import typography.css. Combine `font-\(items[0].key) text-\(items[0].key)` for family/size/line height/tracking. Use the `.fs-` class for full axes, feature and paragraph settings.
        v4: use tailwind.theme.css (imports Tailwind and typography.css) through your normal Tailwind build. @theme inline exports matching font-* and text-* utilities. Do not load unprocessed @theme CSS directly in the browser.

        ## SwiftUI
        Add Typography.swift and register licensed fonts in the app bundle (UIAppFonts on iOS, app-specific registration on macOS). `FontShelfTypography.styles["\(items[0].key)"]` supplies a Core Text-backed SwiftUI Font, axis/feature settings, saved lineHeight and tracking. Apply .font(style.font).tracking(style.tracking). Dynamic Type scaling, alignment, case/decorations and exact paragraph layout must be wired by your app using tokens.json. SwiftUI .lineSpacing is additional spacing, NOT an exact line-height substitute. Core Text may substitute an unavailable font; validate registration.

        ## Android Compose
        Add your package declaration to Typography.kt. Call FontShelfTypography.styles with a resolver mapping each PostScript name AND axis map to a licensed FontFamily. For variable fonts on API 26+, construct Font(resId = yourFontResource, variationSettings = FontVariation.Settings(*axes.map { FontVariation.Setting(it.key, it.value) }.toTypedArray())) inside a FontFamily, with @OptIn(ExperimentalTextApi::class) where required by your Compose version. Provide static alternatives below API 26. Weight, italic, line height, tracking, alignment and OpenType features are in TextStyle; text case, decoration, indent, word and paragraph spacing are retained in tokens.json for application-specific rendering. px → sp/pt uses the same numeric value as a starting point, not guaranteed physical or shaping equivalence. Android output must be integrated and compiled against your project's Compose version.

        ## References
        - https://tailwindcss.com/docs/theme
        - https://developer.apple.com/documentation/swiftui/applying-custom-fonts-to-text
        - https://developer.android.com/develop/ui/compose/text/fonts
        - https://developer.mozilla.org/en-US/docs/Web/CSS/@font-face/font-display
        - https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Attributes/rel/preload
        """
        let files: [String: String] = ["typography.css": css, "tokens.json": try json(tokenDocument), "fonts.json": try json(manifest), "tailwind.config.cjs": "// Tailwind v3: merge into your app config; keep your content globs.\nmodule.exports = " + (try json(["theme": ["extend": ["fontFamily": families, "fontSize": sizes]]])) + ";\n", "tailwind.theme.css": theme, "preload.html": "<!-- Examples only: supply assets, choose critical above-the-fold fonts, and remove unused tags. -->\n" + preloads + "\n", "Typography.swift": swift, "Typography.kt": compose, "index.html": specimen, "README.md": readme]
        let fm = FileManager.default, id = UUID().uuidString
        let staging = parent.appendingPathComponent(".FontShelf-Handoff-" + id), destination = parent.appendingPathComponent("FontShelf-Handoff-" + id.prefix(8))
        try fm.createDirectory(at: staging, withIntermediateDirectories: false)
        do {
            try fm.createDirectory(at: staging.appendingPathComponent("fonts"), withIntermediateDirectories: false)
            for (name, content) in files { try content.write(to: staging.appendingPathComponent(name), atomically: true, encoding: .utf8) }
            try fm.moveItem(at: staging, to: destination)
            return destination
        } catch { try? fm.removeItem(at: staging); throw error }
    }
}

enum TypographySummaryDetail: String, CaseIterable, Identifiable {
    case fonts = "Font names", roles = "Fonts + roles", full = "Full settings"
    var id: String { rawValue }
}

struct CanvasTypographySummary {
    struct Entry: Hashable {
        let role: String
        let font: String
        let size: Double
        let lineHeight: Double
        let tracking: Double
        let axes: String
        let features: String
    }
    let canvas: String
    let format: String
    let entries: [Entry]
    var fonts: [String] { Set(entries.map(\.font)).sorted { $0.localizedStandardCompare($1) == .orderedAscending } }
    private static func markdownText(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "*", with: "\\*")
            .replacingOccurrences(of: "_", with: "\\_")
            .replacingOccurrences(of: "[", with: "\\[")
            .replacingOccurrences(of: "]", with: "\\]")
            .replacingOccurrences(of: "\n", with: " ")
    }
    private static func inlineCode(_ value: String) -> String {
        let runs = value.split(separator: "`", omittingEmptySubsequences: false)
        let longest = value.split(whereSeparator: { $0 != "`" }).map(\.count).max() ?? 0
        let fence = String(repeating: "`", count: max(1, longest + (runs.count > 1 ? 1 : 0)))
        let padding = value.hasPrefix("`") || value.hasSuffix("`") || value.hasPrefix(" ") || value.hasSuffix(" ") ? " " : ""
        return fence + padding + value.replacingOccurrences(of: "\n", with: " ") + padding + fence
    }
    init(canvas: String, direction: TypeDirection) {
        self.canvas = canvas; format = direction.canvas.rawValue
        let plan = CanvasPlan(direction: direction)
        var values: [Entry] = []
        for element in plan.elements {
            guard let style = element.style, element.text != nil else { continue }
            let section = plan.sections.first { $0.id == element.sectionID }?.title
            let role = element.role?.rawValue ?? section ?? "Text layer"
            let axes = DeveloperHandoff.axes(style).keys.sorted().map { "\($0) \(DeveloperHandoff.number(DeveloperHandoff.axes(style)[$0]!))" }.joined(separator: ", ")
            let features = DeveloperHandoff.features(style).keys.sorted().map { "\($0) \(DeveloperHandoff.features(style)[$0]!)" }.joined(separator: ", ")
            let entry = Entry(role: role, font: style.fontName, size: style.size, lineHeight: style.lineHeight ?? style.size * style.leading, tracking: style.tracking, axes: axes, features: features)
            if !values.contains(entry) { values.append(entry) }
        }
        entries = values
    }
    func text(_ detail: TypographySummaryDetail, markdown: Bool = false) -> String {
        let title = "\(canvas) · \(format)"
        if markdown {
            var lines = ["# " + Self.markdownText(title), ""]
            if detail == .fonts { lines += fonts.map { "- " + Self.inlineCode($0) } }
            else { lines += entries.map { entry in
                var value = "- **\(Self.markdownText(entry.role))** — " + Self.inlineCode(entry.font)
                if detail == .full {
                    value += " — \(DeveloperHandoff.number(entry.size)) px / \(DeveloperHandoff.number(entry.lineHeight)) px line height / \(DeveloperHandoff.number(entry.tracking)) px tracking"
                    if !entry.axes.isEmpty { value += " — axes: \(entry.axes)" }
                    if !entry.features.isEmpty { value += " — features: \(entry.features)" }
                }
                return value
            } }
            return lines.joined(separator: "\n") + "\n"
        }
        var lines = [title, String(repeating: "=", count: max(8, title.count)), ""]
        if detail == .fonts { lines += fonts }
        else { lines += entries.map { entry in
            var value = "\(entry.role): \(entry.font)"
            if detail == .full {
                value += " | \(DeveloperHandoff.number(entry.size)) px | line \(DeveloperHandoff.number(entry.lineHeight)) px | tracking \(DeveloperHandoff.number(entry.tracking)) px"
                if !entry.axes.isEmpty { value += " | axes \(entry.axes)" }
                if !entry.features.isEmpty { value += " | features \(entry.features)" }
            }
            return value
        } }
        return lines.joined(separator: "\n") + "\n"
    }
}

struct TypographySummaryDocument {
    let summaries: [CanvasTypographySummary]
    var fonts: [String] { Set(summaries.flatMap(\.fonts)).sorted { $0.localizedStandardCompare($1) == .orderedAscending } }
    func text(_ detail: TypographySummaryDetail, markdown: Bool = false) -> String {
        summaries.map { $0.text(detail, markdown: markdown).trimmingCharacters(in: .whitespacesAndNewlines) }
            .joined(separator: "\n\n") + "\n"
    }
}

enum StudioFontCollection {
    static func fontNames(in direction: TypeDirection) -> Set<String> {
        Set(CanvasTypographySummary(canvas: direction.name, direction: direction).fonts)
    }
    static func fontNames(in board: TypeBoard) -> Set<String> {
        board.directions.reduce(into: Set<String>()) { $0.formUnion(fontNames(in: $1)) }
    }
    static func fontNames(in boards: [TypeBoard]) -> Set<String> {
        boards.reduce(into: Set<String>()) { $0.formUnion(fontNames(in: $1)) }
    }
}
