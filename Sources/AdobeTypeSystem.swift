import AppKit
import Foundation
import JavaScriptCore

enum AdobeTypeSystemTarget: String, CaseIterable, Identifiable {
    case illustrator
    case indesign

    var id: String { rawValue }
    var displayName: String { self == .illustrator ? "Illustrator" : "InDesign" }
    var scriptExtension: String { "jsx" }
    var documentExtension: String { self == .illustrator ? "ai" : "indd" }
}

/// Builds scripts which run inside Adobe applications. Typefield never drives the
/// applications, writes proprietary document formats, or bundles font binaries.
enum AdobeTypeSystemExporter {
    enum ExportError: LocalizedError {
        case emptySelection
        case tooManyCanvases
        case invalidCanvas(String)
        case tooMuchContent
        case encodingFailed

        var errorDescription: String? {
            switch self {
            case .emptySelection:
                return "Select at least one canvas to export."
            case .tooManyCanvases:
                return "Adobe export supports up to 100 canvases at a time."
            case .invalidCanvas(let name):
                return "The canvas \(name) contains invalid or out-of-range layout data."
            case .tooMuchContent:
                return "The selected canvases contain too much text or too many layers for one Adobe export."
            case .encodingFailed:
                return "Typefield could not encode the Adobe builder script."
            }
        }
    }

    private struct RGBA: Codable {
        let r: Double
        let g: Double
        let b: Double
        let a: Double
    }

    private struct Item: Codable {
        let kind: String
        let name: String
        let section: String
        let role: String?
        let x: Double
        let y: Double
        let width: Double
        let height: Double
        let color: RGBA
        let radius: Double
        let stroke: RGBA?
        let strokeWidth: Double?
        let text: String?
        let fontName: String?
        let fontSize: Double?
        let lineHeight: Double?
        let trackingPoints: Double?
        let trackingThousandths: Double?
        let alignment: String?
        let paragraphSpacing: Double?
        let wordSpacing: Double?
        let firstLineIndent: Double?
        let underline: Bool?
        let strikethrough: Bool?
        let kerning: Bool?
        let axes: [String: Double]?
        let features: [String: Int]?
        let paragraphStyle: String?
        let characterStyle: String?
        let warnings: [String]
    }

    private struct Canvas: Codable {
        let name: String
        let sourceKind: String
        let width: Double
        let height: Double
        let paper: RGBA
        let sourceWarnings: [String]
        let items: [Item]
    }

    private struct Manifest: Codable {
        let format: String
        let version: Int
        let generator: String
        let target: String
        let title: String
        let suggestedDocumentName: String
        let units: String
        let limitations: [String]
        let warnings: [String]
        let canvases: [Canvas]
    }

    static func safeBaseName(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " -_()."))
        var result = ""
        var pendingSeparator = false
        for scalar in value.precomposedStringWithCanonicalMapping.unicodeScalars {
            if allowed.contains(scalar) && !CharacterSet.controlCharacters.contains(scalar) {
                if pendingSeparator && !result.isEmpty && !result.hasSuffix("-") { result.append("-") }
                pendingSeparator = false
                result.unicodeScalars.append(scalar)
            } else {
                pendingSeparator = true
            }
        }
        result = result.trimmingCharacters(in: CharacterSet(charactersIn: " .-_"))
        while result.contains("  ") { result = result.replacingOccurrences(of: "  ", with: " ") }
        while result.contains("--") { result = result.replacingOccurrences(of: "--", with: "-") }
        if result.count > 80 { result = String(result.prefix(80)).trimmingCharacters(in: CharacterSet(charactersIn: " .-_")) }
        let reserved = ["con", "prn", "aux", "nul"] + (1...9).flatMap { ["com\($0)", "lpt\($0)"] }
        if result.isEmpty || result == "." || result == ".." || reserved.contains(result.lowercased()) { return "Typefield-Type-System" }
        return result
    }

    static func suggestedScriptFilename(title: String, target: AdobeTypeSystemTarget) -> String {
        safeBaseName(title) + "-" + target.displayName + "." + target.scriptExtension
    }

    static func suggestedDocumentFilename(title: String, target: AdobeTypeSystemTarget) -> String {
        safeBaseName(title) + "." + target.documentExtension
    }

    static func script(directions: [TypeDirection], title: String, target: AdobeTypeSystemTarget) throws -> String {
        let manifest = try makeManifest(directions: directions, title: title, target: target)
        let json = try jsonString(manifest)
        let metadataLiteral = quoted(json)
        switch target {
        case .illustrator:
            return illustratorScript(manifestJSON: json, metadataLiteral: metadataLiteral)
        case .indesign:
            return indesignScript(manifestJSON: json, metadataLiteral: metadataLiteral)
        }
    }

    static func data(directions: [TypeDirection], title: String, target: AdobeTypeSystemTarget) throws -> Data {
        guard let data = try script(directions: directions, title: title, target: target).data(using: .utf8) else { throw ExportError.encodingFailed }
        return data
    }

    private static func makeManifest(directions: [TypeDirection], title: String, target: AdobeTypeSystemTarget) throws -> Manifest {
        guard !directions.isEmpty else { throw ExportError.emptySelection }
        guard directions.count <= 100 else { throw ExportError.tooManyCanvases }
        var styleNumbers: [String: Int] = [:]
        var nextStyleNumber = 1
        var totalItems = 0
        var totalTextBytes = 0
        var collectedWarnings = Set<String>()
        var canvases: [Canvas] = []

        for (canvasIndex, direction) in directions.enumerated() {
            guard direction.isValid else { throw ExportError.invalidCanvas(direction.name) }
            let plan = CanvasPlan(direction: direction)
            guard plan.size.width.isFinite, plan.size.height.isFinite, plan.size.width > 0, plan.size.height > 0 else { throw ExportError.invalidCanvas(direction.name) }
            let exportElements = plan.elements.filter { $0.image == nil }
            totalItems += exportElements.count
            var items: [Item] = []
            for (itemIndex, element) in exportElements.enumerated() {
                let values = [element.rect.minX, element.rect.minY, element.rect.width, element.rect.height, element.radius]
                guard values.allSatisfy(\.isFinite), element.rect.width > 0, element.rect.height > 0 else { throw ExportError.invalidCanvas(direction.name) }
                let section = plan.sections.first { $0.id == element.sectionID }?.title ?? "Canvas"
                if let attributed = element.text, let style = element.style {
                    let text = attributed.string
                    totalTextBytes += text.utf8.count
                    let axes = axisSettings(style)
                    let features = featureSettings(style)
                    var warnings: [String] = []
                    if !axes.isEmpty {
                        warnings.append("Variable axes \(axes.keys.sorted().joined(separator: ", ")) are retained in metadata but are not applied automatically by the Adobe builder.")
                    }
                    if !features.isEmpty {
                        warnings.append("OpenType features \(features.keys.sorted().joined(separator: ", ")) are retained in metadata but are not applied automatically by the Adobe builder.")
                    }
                    if let spacing = style.wordSpacing, spacing != 0 {
                        warnings.append("Word spacing is retained in metadata because Adobe exposes it as percentages rather than Typefield points.")
                    }
                    if style.kerningOverride != nil {
                        warnings.append("The explicit kerning preference is retained in metadata; Adobe's kerning engines vary by application and version.")
                    }
                    warnings.forEach { collectedWarnings.insert($0) }
                    let role = element.role?.rawValue
                    let key = styleKey(style)
                    let styleNumber: Int
                    if let existing = styleNumbers[key] { styleNumber = existing }
                    else {
                        styleNumber = nextStyleNumber
                        styleNumbers[key] = styleNumber
                        nextStyleNumber += 1
                    }
                    let styleLabel = safeStyleLabel(role ?? section)
                    let prefix = String(format: "%02d", styleNumber)
                    let fontSize = rounded(style.size)
                    let tracking = rounded(style.tracking)
                    let foreground = attributed.length > 0 ? attributed.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor : nil
                    items.append(Item(
                        kind: "text",
                        name: itemName(role ?? "Text", index: itemIndex),
                        section: section,
                        role: role,
                        x: rounded(element.rect.minX), y: rounded(element.rect.minY), width: rounded(element.rect.width), height: rounded(element.rect.height),
                        color: rgba(foreground ?? plan.ink), radius: 0, stroke: nil, strokeWidth: nil,
                        text: text, fontName: style.fontName, fontSize: fontSize,
                        lineHeight: rounded(style.lineHeight ?? style.size * style.leading),
                        trackingPoints: tracking,
                        trackingThousandths: rounded(style.size == 0 ? 0 : style.tracking / style.size * 1000),
                        alignment: (style.alignment ?? .left).rawValue.lowercased(),
                        paragraphSpacing: rounded(style.paragraphSpacing ?? 0),
                        wordSpacing: rounded(style.wordSpacing ?? 0),
                        firstLineIndent: rounded(style.indent ?? 0),
                        underline: style.underline ?? false,
                        strikethrough: style.strikethrough ?? false,
                        kerning: style.effectiveKerning,
                        axes: axes, features: features,
                        paragraphStyle: "Typefield P\(prefix): \(styleLabel)",
                        characterStyle: "Typefield C\(prefix): \(styleLabel)",
                        warnings: warnings
                    ))
                } else {
                    items.append(Item(
                        kind: "shape", name: itemName("Shape", index: itemIndex), section: section, role: nil,
                        x: rounded(element.rect.minX), y: rounded(element.rect.minY), width: rounded(element.rect.width), height: rounded(element.rect.height),
                        color: rgba(element.color ?? .clear), radius: rounded(max(0, element.radius)),
                        stroke: element.strokeColor.flatMap { element.strokeWidth > 0 ? rgba($0) : nil },
                        strokeWidth: element.strokeWidth > 0 ? rounded(element.strokeWidth) : nil,
                        text: nil, fontName: nil, fontSize: nil, lineHeight: nil, trackingPoints: nil, trackingThousandths: nil,
                        alignment: nil, paragraphSpacing: nil, wordSpacing: nil, firstLineIndent: nil, underline: nil, strikethrough: nil, kerning: nil,
                        axes: nil, features: nil, paragraphStyle: nil, characterStyle: nil, warnings: []
                    ))
                }
            }
            var sourceWarnings = Set(direction.importWarnings ?? [])
            if exportElements.count != plan.elements.count {
                sourceWarnings.insert("Spaces image artwork is omitted from editable Adobe builders. Use Preview PDF for a visual handoff.")
            }
            let sortedSourceWarnings = sourceWarnings.sorted()
            sortedSourceWarnings.forEach { collectedWarnings.insert($0) }
            let fallbackName = "Canvas \(canvasIndex + 1)"
            canvases.append(Canvas(
                name: direction.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallbackName : direction.name,
                sourceKind: direction.canvasDisplayName,
                width: rounded(plan.size.width), height: rounded(plan.size.height), paper: rgba(plan.paper),
                sourceWarnings: sortedSourceWarnings, items: items
            ))
        }
        guard totalItems <= 50_000, totalTextBytes <= 5_000_000 else { throw ExportError.tooMuchContent }
        var limitations = [
            "Font files are not included. Every referenced font must be installed and licensed on the Adobe workstation.",
            "One Typefield canvas unit is mapped to one Adobe point; line wrapping can change between Core Text and Adobe text engines.",
            "Variable-axis coordinates and arbitrary OpenType feature tags are preserved in legacy export metadata but are not applied automatically.",
            "Word spacing and explicit kerning preferences remain metadata because the Illustrator and InDesign DOMs use different controls.",
            "The builder creates a new native document and never modifies an already-open Adobe document."
        ]
        if target == .illustrator {
            limitations.append("Illustrator scripting applies one opacity to each path. Shapes with different fill and stroke opacities use the stroke opacity for both; keep the Typefield canvas for exact appearance.")
        }
        limitations.forEach { collectedWarnings.insert($0) }
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Typefield Type System" : title
        return Manifest(
            format: "FontShelf Adobe type system", version: 1, generator: "Typefield", target: target.displayName,
            title: cleanTitle, suggestedDocumentName: suggestedDocumentFilename(title: cleanTitle, target: target), units: "points",
            limitations: limitations, warnings: collectedWarnings.sorted(), canvases: canvases
        )
    }

    private static func rounded(_ value: CGFloat) -> Double { rounded(Double(value)) }
    private static func rounded(_ value: Double) -> Double { (value * 100_000).rounded() / 100_000 }

    private static func rgba(_ value: NSColor) -> RGBA {
        let color = value.usingColorSpace(.sRGB) ?? .clear
        func component(_ number: CGFloat) -> Double { rounded(min(1, max(0, Double(number)))) }
        return RGBA(r: component(color.redComponent), g: component(color.greenComponent), b: component(color.blueComponent), a: component(color.alphaComponent))
    }

    private static func itemName(_ label: String, index: Int) -> String {
        safeStyleLabel(label) + " " + String(index + 1)
    }

    private static func safeStyleLabel(_ value: String) -> String {
        let disallowed = CharacterSet.controlCharacters.union(CharacterSet(charactersIn: "[]/:\\"))
        let scalars = value.unicodeScalars.map { disallowed.contains($0) ? " " : String($0) }.joined()
        let words = scalars.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        let result = String(words.prefix(36))
        return result.isEmpty ? "Text" : result
    }

    private static func styleKey(_ style: TypeStyle) -> String {
        let axes = axisSettings(style).keys.sorted().map { "\($0)=\(number(axisSettings(style)[$0]!))" }.joined(separator: ",")
        let features = featureSettings(style).keys.sorted().map { "\($0)=\(featureSettings(style)[$0]!)" }.joined(separator: ",")
        return [style.fontName, number(style.size), number(style.lineHeight ?? style.size * style.leading), number(style.tracking), (style.alignment ?? .left).rawValue, number(style.paragraphSpacing ?? 0), number(style.wordSpacing ?? 0), number(style.indent ?? 0), String(style.underline ?? false), String(style.strikethrough ?? false), String(style.effectiveKerning), axes, features].joined(separator: "\u{1f}")
    }

    private static func number(_ value: Double) -> String {
        String(format: "%.5f", locale: Locale(identifier: "en_US_POSIX"), rounded(value))
    }

    private static func tag(_ value: Int) -> String? {
        guard value >= 0, value <= Int(UInt32.max) else { return nil }
        let bytes = [24, 16, 8, 0].map { UInt8((value >> $0) & 255) }
        guard let result = String(bytes: bytes, encoding: .ascii), result.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) }) else { return nil }
        return result
    }

    private static func axisSettings(_ style: TypeStyle) -> [String: Double] {
        Dictionary(uniqueKeysWithValues: style.axes.compactMap { key, value in tag(key).map { ($0, rounded(value)) } })
    }

    private static func featureSettings(_ style: TypeStyle) -> [String: Int] {
        style.canonicalFeatures.filter { key, _ in key.utf8.count == 4 && key.utf8.allSatisfy { (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) } }
    }

    private static func jsonString<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let result = String(decoding: try encoder.encode(value), as: UTF8.self)
        return result.replacingOccurrences(of: "\u{2028}", with: "\\u2028").replacingOccurrences(of: "\u{2029}", with: "\\u2029")
    }

    private static func quoted(_ value: String) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let data = try! encoder.encode(value)
        return String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\u{2028}", with: "\\u2028").replacingOccurrences(of: "\u{2029}", with: "\\u2029")
    }

    private static func commonScriptPrelude(manifestJSON: String, metadataLiteral: String, extensionName: String) -> String {
        """
        // Generated by Typefield. Run this file inside Adobe; it does not use Apple events.
        // No font binaries are included. Install and license the referenced fonts separately.
        (function () {
            var manifest = \(manifestJSON);
            var metadataJSON = \(metadataLiteral);
            var runtimeWarnings = [];

            function warn(message) {
                for (var i = 0; i < runtimeWarnings.length; i++) if (runtimeWarnings[i] === message) return;
                runtimeWarnings.push(message);
            }
            function ensureExtension(file, extensionName) {
                var pattern = new RegExp("\\\\." + extensionName + "$", "i");
                return pattern.test(file.name) ? file : new File(file.fsName + "." + extensionName);
            }
            function chooseOutput() {
                var candidate = new File(Folder.desktop.fsName + "/" + manifest.suggestedDocumentName);
                var chosen = candidate.saveDlg ? candidate.saveDlg("Save the native " + manifest.target + " document", "*.\(extensionName)") : File.saveDialog("Save the native " + manifest.target + " document", "*.\(extensionName)");
                return chosen ? ensureExtension(chosen, "\(extensionName)") : null;
            }
            function rgbColor(item) {
                var color = new RGBColor();
                color.red = Math.round(item.r * 255);
                color.green = Math.round(item.g * 255);
                color.blue = Math.round(item.b * 255);
                return color;
            }
            function changedNewlines(value) { return value.replace(/\\r\\n|\\r|\\n/g, "\\r"); }
            function warningSummary(savedFile) {
                var lines = ["Saved an editable " + manifest.target + " document:", savedFile.fsName, "", "Fonts are referenced, not bundled."];
                if (manifest.warnings.length || runtimeWarnings.length) lines.push("Review the hidden ‘Typefield Export Metadata’ layer for retained settings and limitations.");
                if (runtimeWarnings.length) {
                    lines.push("", "Runtime warnings:");
                    var count = Math.min(runtimeWarnings.length, 8);
                    for (var i = 0; i < count; i++) lines.push("• " + runtimeWarnings[i]);
                    if (runtimeWarnings.length > count) lines.push("• " + (runtimeWarnings.length - count) + " more warning(s) in the document metadata.");
                }
                return lines.join("\\n");
            }
        """
    }

    private static func illustratorScript(manifestJSON: String, metadataLiteral: String) -> String {
        let prelude = commonScriptPrelude(manifestJSON: manifestJSON, metadataLiteral: metadataLiteral, extensionName: "ai")
        return """
        #target illustrator
        \(prelude)
            function findFont(postScriptName) {
                try { return app.textFonts.getByName(postScriptName); }
                catch (ignored) { warn("Font unavailable in Illustrator: " + postScriptName); return null; }
            }
            function justification(value) {
                if (value === "center") return Justification.CENTER;
                if (value === "right") return Justification.RIGHT;
                if (value === "justified") return Justification.FULLJUSTIFY;
                return Justification.LEFT;
            }
            function ensureStyles(doc, item, font) {
                var characterStyle;
                try { characterStyle = doc.characterStyles.getByName(item.characterStyle); }
                catch (ignoredCharacter) { characterStyle = doc.characterStyles.add(item.characterStyle); }
                try {
                    var ca = characterStyle.characterAttributes;
                    if (font) ca.textFont = font;
                    ca.size = item.fontSize;
                    ca.autoLeading = false;
                    ca.leading = item.lineHeight;
                    ca.tracking = item.trackingThousandths;
                    ca.underline = item.underline;
                    ca.strikeThrough = item.strikethrough;
                } catch (styleError) { warn("Could not fully configure character style “" + item.characterStyle + "”."); }
                var paragraphStyle;
                try { paragraphStyle = doc.paragraphStyles.getByName(item.paragraphStyle); }
                catch (ignoredParagraph) { paragraphStyle = doc.paragraphStyles.add(item.paragraphStyle); }
                try {
                    var pa = paragraphStyle.paragraphAttributes;
                    pa.justification = justification(item.alignment);
                    pa.spaceAfter = item.paragraphSpacing;
                    pa.firstLineIndent = item.firstLineIndent;
                } catch (paragraphError) { warn("Could not fully configure paragraph style “" + item.paragraphStyle + "”."); }
                return { characterStyle: characterStyle, paragraphStyle: paragraphStyle };
            }
            function addShape(layer, item, left, top) {
                var shape;
                if (item.radius > 0) shape = layer.pathItems.roundedRectangle(top - item.y, left + item.x, item.width, item.height, item.radius, item.radius);
                else shape = layer.pathItems.rectangle(top - item.y, left + item.x, item.width, item.height);
                shape.name = item.name;
                shape.stroked = !!item.stroke && item.strokeWidth > 0;
                if (shape.stroked) { shape.strokeColor = rgbColor(item.stroke); shape.strokeWidth = item.strokeWidth; }
                shape.filled = item.color.a > 0;
                if (shape.filled) shape.fillColor = rgbColor(item.color);
                if (shape.stroked && shape.filled && Math.abs(item.stroke.a - item.color.a) > .01) warn("Fill and stroke opacity differ for “" + item.name + "”; review opacity in Illustrator.");
                shape.opacity = (shape.stroked ? item.stroke.a : item.color.a) * 100;
                return shape;
            }
            function addText(doc, layer, item, left, top) {
                var box = layer.pathItems.rectangle(top - item.y, left + item.x, item.width, item.height);
                box.stroked = false; box.filled = false;
                var frame = layer.textFrames.areaText(box);
                frame.name = item.name;
                frame.contents = changedNewlines(item.text);
                frame.opacity = item.color.a * 100;
                var font = findFont(item.fontName);
                var styles = ensureStyles(doc, item, font);
                try { styles.paragraphStyle.applyTo(frame.textRange, true); } catch (ignoredParagraphStyle) {}
                try { styles.characterStyle.applyTo(frame.textRange, false); } catch (ignoredCharacterStyle) {}
                var characters = frame.textRange.characterAttributes;
                if (font) characters.textFont = font;
                characters.size = item.fontSize;
                characters.autoLeading = false;
                characters.leading = item.lineHeight;
                characters.tracking = item.trackingThousandths;
                characters.fillColor = rgbColor(item.color);
                try { characters.underline = item.underline; characters.strikeThrough = item.strikethrough; } catch (ignoredDecoration) {}
                var paragraphs = frame.textRange.paragraphAttributes;
                paragraphs.justification = justification(item.alignment);
                try { paragraphs.spaceAfter = item.paragraphSpacing; paragraphs.firstLineIndent = item.firstLineIndent; } catch (ignoredSpacing) {}
                try { frame.note = "Typefield: " + item.section + (item.warnings.length ? " | " + item.warnings.join(" | ") : ""); } catch (ignoredNote) {}
                return frame;
            }
            function addMetadata(doc, firstRect) {
                var layer = doc.layers.add();
                layer.name = "Typefield Export Metadata";
                var width = Math.max(20, Math.min(500, firstRect[2] - firstRect[0] - 8));
                var height = Math.max(20, Math.min(500, firstRect[1] - firstRect[3] - 8));
                var box = layer.pathItems.rectangle(firstRect[1] - 4, firstRect[0] + 4, width, height);
                box.stroked = false; box.filled = false;
                var frame = layer.textFrames.areaText(box);
                frame.name = "Typefield Manifest v1";
                frame.contents = metadataJSON;
                try { frame.textRange.characterAttributes.size = 4; } catch (ignoredSize) {}
                layer.visible = false;
            }

            var outputFile = chooseOutput();
            if (!outputFile) return;
            var doc = null;
            try {
                var first = manifest.canvases[0];
                doc = app.documents.add(DocumentColorSpace.RGB, first.width, first.height);
                doc.name = manifest.title;
                var maximumWidth = 0, maximumHeight = 0;
                for (var measureIndex = 0; measureIndex < manifest.canvases.length; measureIndex++) {
                    maximumWidth = Math.max(maximumWidth, manifest.canvases[measureIndex].width);
                    maximumHeight = Math.max(maximumHeight, manifest.canvases[measureIndex].height);
                }
                var columns = Math.min(4, Math.ceil(Math.sqrt(manifest.canvases.length)));
                var firstRect = null;
                for (var canvasIndex = 0; canvasIndex < manifest.canvases.length; canvasIndex++) {
                    var canvas = manifest.canvases[canvasIndex];
                    var column = canvasIndex % columns, row = Math.floor(canvasIndex / columns);
                    var left = column * (maximumWidth + 72), top = -row * (maximumHeight + 72);
                    var artboardRect = [left, top, left + canvas.width, top - canvas.height];
                    var artboard;
                    if (canvasIndex === 0) { artboard = doc.artboards[0]; artboard.artboardRect = artboardRect; firstRect = artboardRect; }
                    else artboard = doc.artboards.add(artboardRect);
                    artboard.name = (canvasIndex + 1) + ". " + canvas.name;
                    var layer = doc.layers.add();
                    layer.name = (canvasIndex + 1) + ". " + canvas.name;
                    var background = layer.pathItems.rectangle(top, left, canvas.width, canvas.height);
                    background.name = "Canvas background";
                    background.stroked = false; background.filled = true; background.fillColor = rgbColor(canvas.paper); background.opacity = canvas.paper.a * 100;
                    for (var itemIndex = 0; itemIndex < canvas.items.length; itemIndex++) {
                        var item = canvas.items[itemIndex];
                        if (item.kind === "text") addText(doc, layer, item, left, top);
                        else addShape(layer, item, left, top);
                    }
                }
                addMetadata(doc, firstRect);
                var options = new IllustratorSaveOptions();
                try { options.pdfCompatible = false; options.compressed = true; } catch (ignoredOptions) {}
                doc.saveAs(outputFile, options);
                alert(warningSummary(outputFile));
            } catch (error) {
                alert("Typefield could not build the Illustrator document.\\n\\n" + error.message + "\\n\\nNo existing document was modified.");
            }
        })();
        """
    }

    private static func indesignScript(manifestJSON: String, metadataLiteral: String) -> String {
        let prelude = commonScriptPrelude(manifestJSON: manifestJSON, metadataLiteral: metadataLiteral, extensionName: "indd")
        return """
        #target indesign
        \(prelude)
            function findFont(postScriptName) {
                for (var i = 0; i < app.fonts.length; i++) {
                    try { if (app.fonts[i].postscriptName === postScriptName) return app.fonts[i]; } catch (ignoredPostScriptName) {}
                }
                warn("Font unavailable in InDesign: " + postScriptName);
                return null;
            }
            function justification(value) {
                if (value === "center") return Justification.CENTER_ALIGN;
                if (value === "right") return Justification.RIGHT_ALIGN;
                if (value === "justified") return Justification.FULLY_JUSTIFIED;
                return Justification.LEFT_ALIGN;
            }
            function getColor(doc, value) {
                var name = "Typefield RGB " + Math.round(value.r * 255) + " " + Math.round(value.g * 255) + " " + Math.round(value.b * 255);
                var color = doc.colors.itemByName(name);
                if (!color.isValid) color = doc.colors.add({ name: name, model: ColorModel.PROCESS, space: ColorSpace.RGB, colorValue: [Math.round(value.r * 255), Math.round(value.g * 255), Math.round(value.b * 255)] });
                return color;
            }
            function ensureStyles(doc, item, font) {
                var characterStyle = doc.characterStyles.itemByName(item.characterStyle);
                if (!characterStyle.isValid) characterStyle = doc.characterStyles.add({ name: item.characterStyle });
                try {
                    characterStyle.pointSize = item.fontSize;
                    characterStyle.tracking = item.trackingThousandths;
                    characterStyle.underline = item.underline;
                    characterStyle.strikeThru = item.strikethrough;
                    if (font) characterStyle.appliedFont = font;
                } catch (characterError) { warn("Could not fully configure character style “" + item.characterStyle + "”."); }
                var paragraphStyle = doc.paragraphStyles.itemByName(item.paragraphStyle);
                if (!paragraphStyle.isValid) paragraphStyle = doc.paragraphStyles.add({ name: item.paragraphStyle });
                try {
                    paragraphStyle.leading = item.lineHeight;
                    paragraphStyle.justification = justification(item.alignment);
                    paragraphStyle.spaceAfter = item.paragraphSpacing;
                    paragraphStyle.firstLineIndent = item.firstLineIndent;
                } catch (paragraphError) { warn("Could not fully configure paragraph style “" + item.paragraphStyle + "”."); }
                return { characterStyle: characterStyle, paragraphStyle: paragraphStyle };
            }
            function pageBounds(page, item) {
                var bounds = page.bounds;
                return [bounds[0] + item.y, bounds[1] + item.x, bounds[0] + item.y + item.height, bounds[1] + item.x + item.width];
            }
            function setOpacity(pageItem, value) {
                try { pageItem.transparencySettings.blendingSettings.opacity = value * 100; } catch (ignoredOpacity) {}
            }
            function addShape(doc, page, layer, item) {
                var shape = page.rectangles.add();
                shape.itemLayer = layer;
                shape.name = item.name;
                shape.geometricBounds = pageBounds(page, item);
                shape.fillColor = getColor(doc, item.color);
                shape.strokeColor = item.stroke && item.strokeWidth > 0 ? getColor(doc, item.stroke) : doc.swatches.itemByName("None");
                shape.strokeWeight = item.stroke && item.strokeWidth > 0 ? item.strokeWidth : 0;
                shape.strokeAlignment = StrokeAlignment.CENTER_ALIGNMENT;
                setOpacity(shape, 1);
                shape.fillTransparencySettings.blendingSettings.opacity = item.color.a * 100;
                if (item.stroke && item.strokeWidth > 0) shape.strokeTransparencySettings.blendingSettings.opacity = item.stroke.a * 100;
                if (item.radius > 0) {
                    try {
                        shape.topLeftCornerOption = CornerOptions.ROUNDED_CORNER; shape.topRightCornerOption = CornerOptions.ROUNDED_CORNER;
                        shape.bottomLeftCornerOption = CornerOptions.ROUNDED_CORNER; shape.bottomRightCornerOption = CornerOptions.ROUNDED_CORNER;
                        shape.topLeftCornerRadius = item.radius; shape.topRightCornerRadius = item.radius;
                        shape.bottomLeftCornerRadius = item.radius; shape.bottomRightCornerRadius = item.radius;
                    } catch (ignoredCorners) { warn("A rounded corner could not be reproduced for “" + item.name + "”."); }
                }
                return shape;
            }
            function addText(doc, page, layer, item) {
                var frame = page.textFrames.add();
                frame.itemLayer = layer;
                frame.name = item.name;
                frame.geometricBounds = pageBounds(page, item);
                frame.contents = changedNewlines(item.text);
                try { frame.textFramePreferences.insetSpacing = 0; frame.textFramePreferences.ignoreWrap = true; frame.textFramePreferences.verticalJustification = VerticalJustification.TOP_ALIGN; } catch (ignoredFramePreferences) {}
                setOpacity(frame, item.color.a);
                var text = frame.parentStory.texts[0];
                var font = findFont(item.fontName);
                var styles = ensureStyles(doc, item, font);
                try { text.appliedParagraphStyle = styles.paragraphStyle; text.applyCharacterStyle(styles.characterStyle, true); } catch (ignoredStyles) {}
                if (font) text.appliedFont = font;
                text.pointSize = item.fontSize;
                text.leading = item.lineHeight;
                text.tracking = item.trackingThousandths;
                text.fillColor = getColor(doc, item.color);
                text.justification = justification(item.alignment);
                try { text.spaceAfter = item.paragraphSpacing; text.firstLineIndent = item.firstLineIndent; text.underline = item.underline; text.strikeThru = item.strikethrough; } catch (ignoredTextProperties) {}
                try { frame.insertLabel("FontShelfItem", item.section + (item.warnings.length ? " | " + item.warnings.join(" | ") : "")); } catch (ignoredLabel) {}
                return frame;
            }
            function resizePage(page, width, height) {
                try { page.resize(CoordinateSpaces.INNER_COORDINATES, AnchorPoint.TOP_LEFT_ANCHOR, ResizeMethods.REPLACING_CURRENT_DIMENSIONS_WITH, [width, height]); }
                catch (resizeError) { throw new Error("Could not size page “" + page.name + "” to " + width + " × " + height + " pt: " + resizeError.message); }
            }
            function addMetadata(doc) {
                try { doc.insertLabel("FontShelfManifestV1", metadataJSON); } catch (labelError) { warn("The complete Typefield manifest could not be added as a document label."); }
                var layer = doc.layers.add({ name: "Typefield Export Metadata" });
                var page = doc.pages[0], bounds = page.bounds;
                var frame = page.textFrames.add();
                frame.itemLayer = layer;
                frame.name = "Typefield Manifest v1";
                frame.geometricBounds = [bounds[0] + 4, bounds[1] + 4, Math.min(bounds[2] - 4, bounds[0] + 504), Math.min(bounds[3] - 4, bounds[1] + 504)];
                frame.contents = metadataJSON;
                layer.visible = false;
            }

            var outputFile = chooseOutput();
            if (!outputFile) return;
            var doc = null;
            try {
                doc = app.documents.add();
                doc.documentPreferences.facingPages = false;
                doc.viewPreferences.horizontalMeasurementUnits = MeasurementUnits.POINTS;
                doc.viewPreferences.verticalMeasurementUnits = MeasurementUnits.POINTS;
                doc.viewPreferences.rulerOrigin = RulerOrigin.PAGE_ORIGIN;
                for (var canvasIndex = 0; canvasIndex < manifest.canvases.length; canvasIndex++) {
                    var canvas = manifest.canvases[canvasIndex];
                    var page = canvasIndex === 0 ? doc.pages[0] : doc.pages.add(LocationOptions.AT_END);
                    resizePage(page, canvas.width, canvas.height);
                    try { page.insertLabel("FontShelfCanvas", canvas.name); } catch (ignoredPageLabel) {}
                    var layer = doc.layers.add({ name: (canvasIndex + 1) + ". " + canvas.name });
                    var bounds = page.bounds;
                    var background = page.rectangles.add();
                    background.itemLayer = layer;
                    background.name = "Canvas background";
                    background.geometricBounds = bounds;
                    background.fillColor = getColor(doc, canvas.paper);
                    background.strokeColor = doc.swatches.itemByName("None"); background.strokeWeight = 0;
                    setOpacity(background, canvas.paper.a);
                    for (var itemIndex = 0; itemIndex < canvas.items.length; itemIndex++) {
                        var item = canvas.items[itemIndex];
                        if (item.kind === "text") addText(doc, page, layer, item);
                        else addShape(doc, page, layer, item);
                    }
                }
                addMetadata(doc);
                doc.save(outputFile);
                alert(warningSummary(outputFile));
            } catch (error) {
                alert("Typefield could not build the InDesign document.\\n\\n" + error.message + "\\n\\nNo existing document was modified.");
            }
        })();
        """
    }

    /// Fast, deterministic coverage for payload escaping and both script templates.
    /// Adobe DOM behavior still requires a live Illustrator/InDesign smoke test.
    static func selfTest() {
        do {
            var direction = TypeDirection(name: "Canvas \"one\"\n\u{2028}")
            direction.ink = "123456"
            var display = direction.style(.display)
            display.fontName = "TestPS\"; throw new Error('injected')"
            display.axes[0x77676874] = 642
            display.features["liga"] = 0
            display.tracking = 1.25
            display.alignment = .center
            display.underline = true
            direction.styles[TypeRole.display.rawValue] = display
            for target in AdobeTypeSystemTarget.allCases {
                let first = try script(directions: [direction], title: "Type/System:*?", target: target)
                let second = try script(directions: [direction], title: "Type/System:*?", target: target)
                precondition(first == second, "Adobe builder output must be deterministic")
                precondition(first.hasPrefix("#target \(target.rawValue)"))
                precondition(first.contains("Typefield Export Metadata"))
                precondition(first.contains("characterStyle") && first.contains("paragraphStyle"))
                precondition(first.contains("Variable axes") && first.contains("OpenType features"))
                precondition(first.contains(target == .illustrator ? "doc.saveAs(outputFile" : "doc.save(outputFile"))
                if target == .illustrator {
                    precondition(first.contains("Shapes with different fill and stroke opacities use the stroke opacity for both"),
                                 "Illustrator's one-opacity limitation must be disclosed in export metadata")
                }
                if target == .indesign {
                    precondition(first.contains("shape.fillTransparencySettings.blendingSettings.opacity = item.color.a * 100") &&
                                 first.contains("shape.strokeTransparencySettings.blendingSettings.opacity = item.stroke.a * 100") &&
                                 first.contains("shape.strokeAlignment = StrokeAlignment.CENTER_ALIGNMENT"),
                                 "InDesign shapes must preserve independently editable fill and centered stroke appearance")
                }
                precondition(suggestedScriptFilename(title: "Type/System:*?", target: target).hasSuffix(".jsx"))
                let context = JSContext()!
                context.evaluateScript("""
                var alerts = []; function alert(value) { alerts.push(String(value)); }
                var Folder = { desktop: { fsName: '/tmp' } };
                function File(path) { this.fsName = path; this.name = String(path).split('/').pop(); this.saveDlg = function () { return null; }; }
                File.saveDialog = function () { return null; };
                """)
                let body = first.split(separator: "\n", omittingEmptySubsequences: false).dropFirst().joined(separator: "\n")
                context.evaluateScript(body)
                precondition(context.exception == nil, "Generated Adobe script must parse as JavaScript: \(String(describing: context.exception))")
                precondition(context.evaluateScript("alerts.length")!.toInt32() == 0, "Cancelled export must stay quiet")
            }
            precondition(safeBaseName("../CON") == "CON" || safeBaseName("../CON") == "Typefield-Type-System")
            precondition(safeBaseName("///") == "Typefield-Type-System")
            AdobeTypeSystemReturnBridge.selfTest()
        } catch {
            preconditionFailure("Adobe type-system exporter self-test failed: \(error)")
        }
    }
}

enum AdobeReturnScope: String, CaseIterable, Identifiable {
    case prompt
    case selection
    case document

    var id: String { rawValue }
}

/// Stable interchange written by the Adobe return scripts. It deliberately
/// represents text frames and simple shapes rather than proprietary documents.
struct AdobeReturnColor: Codable, Equatable {
    var r: Double
    var g: Double
    var b: Double
    var a: Double
}

struct AdobeReturnLayer: Codable, Equatable {
    var kind: String
    var name: String
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var color: AdobeReturnColor
    var radius: Double?
    var stroke: AdobeReturnColor?
    var strokeWidth: Double?
    var text: String?
    var fontName: String?
    var fontFamily: String?
    var fontStyle: String?
    var fontSize: Double?
    var lineHeight: Double?
    var trackingPoints: Double?
    var trackingThousandths: Double?
    var alignment: String?
    var paragraphSpacing: Double?
    var wordSpacing: Double?
    var firstLineIndent: Double?
    var underline: Bool?
    var strikethrough: Bool?
    var kerning: Bool?
    var axes: [String: Double]?
    var features: [String: Int]?
    var warnings: [String]?
}

struct AdobeReturnCanvas: Codable, Equatable {
    var name: String
    var width: Double
    var height: Double
    var paper: AdobeReturnColor
    var layers: [AdobeReturnLayer]
    var warnings: [String]?
}

struct AdobeReturnDocument: Codable, Equatable {
    var format: String
    var version: Int
    var sourceApplication: String
    var name: String
    var canvases: [AdobeReturnCanvas]
    var warnings: [String]?
}

enum AdobeTypeSystemReturnBridge {
    enum ImportError: LocalizedError {
        case tooLarge
        case unsupportedFormat
        case emptyDocument
        case invalidCanvas(String)
        case invalidLayer(String)

        var errorDescription: String? {
            switch self {
            case .tooLarge:
                return "The Adobe return file is larger than Typefield’s 20 MB safety limit."
            case .unsupportedFormat:
                return "Choose a version 1 Typefield Adobe return JSON file. Native .ai and .indd files are not imported directly."
            case .emptyDocument:
                return "The Adobe return file does not contain any canvases or pages."
            case .invalidCanvas(let name):
                return "The Adobe canvas \(name) has invalid bounds or too many layers."
            case .invalidLayer(let name):
                return "The Adobe layer \(name) contains invalid geometry, color, or typography."
            }
        }
    }

    static func suggestedScriptFilename(target: AdobeTypeSystemTarget) -> String {
        "Typefield-Return-from-" + target.displayName + ".jsx"
    }

    static func script(target: AdobeTypeSystemTarget, scope: AdobeReturnScope = .prompt) -> String {
        switch target {
        case .illustrator:
            return illustratorReturnScript(scope: scope)
        case .indesign:
            return indesignReturnScript(scope: scope)
        }
    }

    static func data(target: AdobeTypeSystemTarget, scope: AdobeReturnScope = .prompt) -> Data {
        Data(script(target: target, scope: scope).utf8)
    }

    static func decode(_ data: Data) throws -> AdobeReturnDocument {
        guard data.count <= 20_000_000 else { throw ImportError.tooLarge }
        let document = try JSONDecoder().decode(AdobeReturnDocument.self, from: data)
        guard document.format == "fontshelf-adobe-return", document.version == 1, ["Illustrator", "InDesign"].contains(document.sourceApplication) else { throw ImportError.unsupportedFormat }
        guard !document.canvases.isEmpty, document.canvases.count <= 100 else { throw ImportError.emptyDocument }
        return document
    }

    static func board(data: Data, fonts: [Face]) throws -> TypeBoard {
        try board(document: decode(data), installedFontNames: Set(fonts.map(\.name)))
    }

    static func board(document: AdobeReturnDocument, installedFontNames: Set<String>? = nil) throws -> TypeBoard {
        guard document.format == "fontshelf-adobe-return", document.version == 1, ["Illustrator", "InDesign"].contains(document.sourceApplication) else { throw ImportError.unsupportedFormat }
        guard !document.canvases.isEmpty, document.canvases.count <= 100 else { throw ImportError.emptyDocument }
        var directions: [TypeDirection] = []
        var totalLayers = 0
        var totalTextBytes = 0
        for (canvasIndex, canvas) in document.canvases.enumerated() {
            guard valid(canvas.width, range: 1...10_000), valid(canvas.height, range: 1...100_000), canvas.layers.count <= 5_000, valid(canvas.paper) else { throw ImportError.invalidCanvas(canvas.name) }
            totalLayers += canvas.layers.count
            var importedLayers: [ImportedLayer] = []
            var warnings = Set((document.warnings ?? []) + (canvas.warnings ?? []))
            warnings.insert("Imported from \(document.sourceApplication). Adobe effects, clipping paths, rotations, columns, linked frames, and mixed inline styles are not reconstructed.")
            for (layerIndex, layer) in canvas.layers.enumerated() {
                let numeric = [layer.x, layer.y, layer.width, layer.height, layer.radius ?? 0]
                guard ["text", "shape"].contains(layer.kind), numeric.allSatisfy(\.isFinite), abs(layer.x) <= 100_000, abs(layer.y) <= 100_000, valid(layer.width, range: 0.01...100_000), valid(layer.height, range: 0.01...100_000), valid(layer.color), valid(layer.radius ?? 0, range: 0...10_000),
                      (layer.stroke.map(valid) ?? true), (layer.strokeWidth.map { valid($0, range: 0...1_000) && ($0 == 0 || layer.stroke != nil) } ?? true),
                      (layer.kind == "shape" || (layer.stroke == nil && layer.strokeWidth == nil)) else { throw ImportError.invalidLayer(layer.name) }
                let color = NSColor(srgbRed: layer.color.r, green: layer.color.g, blue: layer.color.b, alpha: 1)
                var imported = ImportedLayer(
                    name: layer.name.isEmpty ? "Layer \(layerIndex + 1)" : layer.name,
                    x: layer.x, y: layer.y, width: layer.width, height: layer.height,
                    color: color.rgbHex, opacity: layer.color.a, radius: layer.radius ?? 0
                )
                if layer.kind == "shape", let stroke = layer.stroke, let width = layer.strokeWidth, width > 0 {
                    imported.strokeColor = NSColor(srgbRed: stroke.r, green: stroke.g, blue: stroke.b, alpha: 1).rgbHex
                    imported.strokeOpacity = stroke.a
                    imported.strokeWidth = width
                }
                (layer.warnings ?? []).forEach { warnings.insert($0) }
                if layer.kind == "text" {
                    guard let text = layer.text, TypeDirection.acceptsCanvasText(text), let fontSize = layer.fontSize, valid(fontSize, range: 1...1_000) else { throw ImportError.invalidLayer(layer.name) }
                    totalTextBytes += text.utf8.count
                    let fontName = [layer.fontName, layer.fontFamily].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty } ?? "Helvetica"
                    let tracking = layer.trackingPoints ?? ((layer.trackingThousandths ?? 0) * fontSize / 1_000)
                    let lineHeight = layer.lineHeight ?? fontSize * 1.35
                    guard valid(tracking, range: -100...100), valid(lineHeight, range: 1...2_000), valid(layer.paragraphSpacing ?? 0, range: -1_000...1_000), valid(layer.wordSpacing ?? 0, range: -1_000...1_000), valid(layer.firstLineIndent ?? 0, range: -1_000...1_000) else { throw ImportError.invalidLayer(layer.name) }
                    var style = TypeStyle(fontName: fontName, size: fontSize, tracking: tracking, text: text)
                    style.lineHeight = lineHeight
                    style.leading = min(2.5, max(1, lineHeight / fontSize))
                    style.paragraphSpacing = layer.paragraphSpacing ?? 0
                    style.wordSpacing = layer.wordSpacing ?? 0
                    style.indent = layer.firstLineIndent ?? 0
                    style.alignment = alignment(layer.alignment)
                    style.underline = layer.underline ?? false
                    style.strikethrough = layer.strikethrough ?? false
                    if let kerning = layer.kerning { style.setKerning(kerning) }
                    for (tag, value) in layer.axes ?? [:] where validTag(tag) && value.isFinite { style.axes[tagID(tag)] = value }
                    style.features = (layer.features ?? [:]).filter { validTag($0.key) }
                    imported.style = style
                    if let installedFontNames, !installedFontNames.contains(fontName) { warnings.insert("Font “\(fontName)” is unavailable in Typefield; verify the fallback for \(imported.name).") }
                }
                importedLayers.append(imported)
            }
            guard totalLayers <= 50_000, totalTextBytes <= 5_000_000 else { throw ImportError.tooLarge }
            let layout = ImportedLayout(width: canvas.width, height: canvas.height, layers: importedLayers)
            guard layout.isValid else { throw ImportError.invalidCanvas(canvas.name) }
            var direction = TypeDirection(name: canvas.name.isEmpty ? "Adobe canvas \(canvasIndex + 1)" : canvas.name)
            direction.canvas = .imported
            direction.width = canvas.width
            direction.paper = NSColor(srgbRed: canvas.paper.r, green: canvas.paper.g, blue: canvas.paper.b, alpha: 1).rgbHex
            direction.importedLayout = layout
            direction.importedSource = document.sourceApplication == "InDesign" ? .indesign : .illustrator
            direction.importWarnings = warnings.sorted()
            directions.append(direction)
        }
        let title = document.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return TypeBoard(name: title.isEmpty ? "Adobe typeboard" : title, directions: directions, selectedDirection: directions.first?.id)
    }

    private static func valid(_ value: Double, range: ClosedRange<Double>) -> Bool { value.isFinite && range.contains(value) }
    private static func valid(_ color: AdobeReturnColor) -> Bool { [color.r, color.g, color.b, color.a].allSatisfy { $0.isFinite && (0...1).contains($0) } }
    private static func validTag(_ value: String) -> Bool { value.utf8.count == 4 && value.utf8.allSatisfy { (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) } }
    private static func tagID(_ value: String) -> Int { value.utf8.reduce(0) { ($0 << 8) | Int($1) } }
    private static func alignment(_ value: String?) -> TextAlignmentOption {
        switch value?.lowercased() {
        case "center": return .center
        case "right": return .right
        case "justified", "justify": return .justified
        default: return .left
        }
    }

    private static func returnPrelude(target: AdobeTypeSystemTarget, scope: AdobeReturnScope) -> String {
        """
        // Typefield Adobe return bridge v1. Exports editable text-frame and simple-shape data only.
        // It never reads or copies font binaries.
        (function () {
            var requestedScope = "\(scope.rawValue)";
            var bridgeWarnings = [
                "Adobe effects, clipping paths, rotations, columns, linked frames, and mixed inline styles are not reconstructed.",
                "Variable axes and arbitrary OpenType feature tags are unavailable through a consistent Adobe scripting API and may require review."
            ];
            function warn(message) {
                for (var i = 0; i < bridgeWarnings.length; i++) if (bridgeWarnings[i] === message) return;
                bridgeWarnings.push(message);
            }
            function quote(value) {
                var text = String(value), result = "\\\"";
                for (var i = 0; i < text.length; i++) {
                    var code = text.charCodeAt(i), character = text.charAt(i);
                    if (character === "\\\"") result += "\\\\\\\"";
                    else if (character === "\\\\") result += "\\\\\\\\";
                    else if (character === "\\b") result += "\\\\b";
                    else if (character === "\\f") result += "\\\\f";
                    else if (character === "\\n") result += "\\\\n";
                    else if (character === "\\r") result += "\\\\r";
                    else if (character === "\\t") result += "\\\\t";
                    else if (code < 32 || code === 0x2028 || code === 0x2029) result += "\\\\u" + ("0000" + code.toString(16)).slice(-4);
                    else result += character;
                }
                return result + "\\\"";
            }
            function stringify(value) {
                if (value === null) return "null";
                var type = typeof value;
                if (type === "string") return quote(value);
                if (type === "number") return isFinite(value) ? String(value) : "null";
                if (type === "boolean") return value ? "true" : "false";
                var parts = [], i, key;
                if (value instanceof Array) {
                    for (i = 0; i < value.length; i++) parts.push(stringify(value[i]));
                    return "[" + parts.join(",") + "]";
                }
                var keys = [];
                for (key in value) if (value.hasOwnProperty(key) && typeof value[key] !== "undefined") keys.push(key);
                keys.sort();
                for (i = 0; i < keys.length; i++) parts.push(quote(keys[i]) + ":" + stringify(value[keys[i]]));
                return "{" + parts.join(",") + "}";
            }
            function safeNumber(value, fallback) {
                var number = Number(value);
                return isFinite(number) ? number : fallback;
            }
            function normalizedText(value) { return String(value).replace(/\\r\\n|\\r/g, "\\n"); }
            function chooseSelection(appSelection) {
                if (requestedScope === "selection") return true;
                if (requestedScope === "document") return false;
                if (!appSelection || !appSelection.length) return false;
                return confirm("Export the current selection?\\n\\nOK = selection only\\nCancel = entire document");
            }
            function chooseOutput(documentName) {
                var safeName = String(documentName || "Adobe").replace(/[\\\\\\/:*?\"<>|]/g, "-");
                var candidate = new File(Folder.desktop.fsName + "/Typefield-" + safeName + ".json");
                var chosen = candidate.saveDlg ? candidate.saveDlg("Save Typefield Adobe return JSON", "*.json") : File.saveDialog("Save Typefield Adobe return JSON", "*.json");
                if (!chosen) return null;
                return /\\.json$/i.test(chosen.name) ? chosen : new File(chosen.fsName + ".json");
            }
            function writeResult(file, result) {
                file.encoding = "UTF-8"; file.lineFeed = "Unix";
                if (!file.open("w")) throw new Error("Could not open the return file for writing.");
                try { file.write(stringify(result)); } finally { file.close(); }
            }
            if (!app.documents.length) { alert("Typefield: Open a \(target.displayName) document first."); return; }
        """
    }

    private static func illustratorReturnScript(scope: AdobeReturnScope) -> String {
        let prelude = returnPrelude(target: .illustrator, scope: scope)
        return """
        #target illustrator
        \(prelude)
            function colorValue(color, opacity) {
                var result = { r: 0, g: 0, b: 0, a: Math.max(0, Math.min(1, safeNumber(opacity, 100) / 100)) };
                if (!color || color.typename === "NoColor") { result.a = 0; return result; }
                if (color.typename === "RGBColor") { result.r = color.red / 255; result.g = color.green / 255; result.b = color.blue / 255; }
                else if (color.typename === "GrayColor") { result.r = result.g = result.b = color.gray / 100; }
                else if (color.typename === "CMYKColor") {
                    result.r = 1 - Math.min(1, (color.cyan + color.black) / 100);
                    result.g = 1 - Math.min(1, (color.magenta + color.black) / 100);
                    result.b = 1 - Math.min(1, (color.yellow + color.black) / 100);
                    warn("CMYK colors were converted approximately to RGB.");
                } else warn("An unsupported Illustrator color was replaced with black.");
                return result;
            }
            function alignmentValue(value) {
                if (value === Justification.CENTER) return "center";
                if (value === Justification.RIGHT) return "right";
                if (value === Justification.FULLJUSTIFY || value === Justification.FULLJUSTIFYLASTLINELEFT || value === Justification.FULLJUSTIFYLASTLINECENTER || value === Justification.FULLJUSTIFYLASTLINERIGHT) return "justified";
                return "left";
            }
            function flatten(item, result) {
                if (!item) return;
                if (item.typename === "TextRange" && item.parent) { flatten(item.parent, result); return; }
                if (item.typename === "GroupItem") { for (var i = 0; i < item.pageItems.length; i++) flatten(item.pageItems[i], result); return; }
                if (item.typename === "CompoundPathItem") { for (var pathIndex = 0; pathIndex < item.pathItems.length; pathIndex++) flatten(item.pathItems[pathIndex], result); return; }
                if (item.typename === "TextFrame" || item.typename === "PathItem") result.push(item);
                else warn("Unsupported Illustrator item “" + item.typename + "” was skipped.");
            }
            function onArtboard(bounds, artboard) {
                var x = (bounds[0] + bounds[2]) / 2, y = (bounds[1] + bounds[3]) / 2;
                return x >= artboard[0] && x <= artboard[2] && y <= artboard[1] && y >= artboard[3];
            }
            function textLayer(item, artboard) {
                var bounds = item.geometricBounds, range = item.textRange, ca = range.characterAttributes, pa = range.paragraphAttributes;
                var size = safeNumber(ca.size, 12), tracking = safeNumber(ca.tracking, 0), leading = safeNumber(ca.leading, size * 1.2);
                var fontName = "Helvetica", family = "", style = "";
                try { fontName = ca.textFont.name; family = ca.textFont.family; style = ca.textFont.style; } catch (fontError) { warn("A mixed or unavailable Illustrator font was replaced with metadata fallback."); }
                var fill = null; try { fill = ca.fillColor; } catch (ignoredFill) {}
                return {
                    kind: "text", name: item.name || "Text", x: bounds[0] - artboard[0], y: artboard[1] - bounds[1], width: bounds[2] - bounds[0], height: bounds[1] - bounds[3],
                    color: colorValue(fill, item.opacity), radius: 0, text: normalizedText(item.contents), fontName: fontName, fontFamily: family, fontStyle: style,
                    fontSize: size, lineHeight: leading, trackingPoints: tracking / 1000 * size, trackingThousandths: tracking,
                    alignment: alignmentValue(pa.justification), paragraphSpacing: safeNumber(pa.spaceAfter, 0), wordSpacing: 0, firstLineIndent: safeNumber(pa.firstLineIndent, 0),
                    underline: !!ca.underline, strikethrough: !!ca.strikeThrough, kerning: true, axes: {}, features: {}, warnings: ["Mixed inline styles, variable axes, and arbitrary OpenType settings require review after import."]
                };
            }
            function shapeLayer(item, artboard) {
                var bounds = item.geometricBounds, fill = item.filled ? item.fillColor : null;
                return { kind: "shape", name: item.name || "Shape", x: bounds[0] - artboard[0], y: artboard[1] - bounds[1], width: bounds[2] - bounds[0], height: bounds[1] - bounds[3], color: colorValue(fill, item.opacity), radius: 0,
                    stroke: item.stroked ? colorValue(item.strokeColor, item.opacity) : null, strokeWidth: item.stroked ? safeNumber(item.strokeWidth, 0) : 0,
                    warnings: item.closed ? [] : ["An open path was imported as its rectangular bounds."] };
            }

            try {
                var doc = app.activeDocument, selectedOnly = chooseSelection(doc.selection), source = [];
                if (selectedOnly) {
                    if (!doc.selection || !doc.selection.length) { alert("Typefield: Select text frames or simple shapes first."); return; }
                    for (var selectedIndex = 0; selectedIndex < doc.selection.length; selectedIndex++) flatten(doc.selection[selectedIndex], source);
                } else {
                    for (var pageIndex = 0; pageIndex < doc.pageItems.length; pageIndex++) {
                        var pageItem = doc.pageItems[pageIndex];
                        try { if (pageItem.layer && (pageItem.layer.name === "Typefield Export Metadata" || pageItem.layer.name === "FontShelf Export Metadata")) continue; } catch (ignoredLayer) {}
                        try { if (!pageItem.parent || pageItem.parent.typename !== "Layer") continue; } catch (ignoredParent) { continue; }
                        flatten(pageItem, source);
                    }
                }
                var canvases = [];
                for (var artboardIndex = 0; artboardIndex < doc.artboards.length; artboardIndex++) {
                    var artboardObject = doc.artboards[artboardIndex], artboard = artboardObject.artboardRect, layers = [], paper = { r: 1, g: 1, b: 1, a: 1 };
                    for (var itemIndex = 0; itemIndex < source.length; itemIndex++) {
                        var item = source[itemIndex], bounds = item.geometricBounds;
                        if (!onArtboard(bounds, artboard)) continue;
                        if (item.typename === "PathItem" && item.name === "Canvas background") { paper = colorValue(item.fillColor, item.opacity); continue; }
                        layers.push(item.typename === "TextFrame" ? textLayer(item, artboard) : shapeLayer(item, artboard));
                    }
                    if (!selectedOnly || layers.length) canvases.push({ name: artboardObject.name || ("Artboard " + (artboardIndex + 1)), width: artboard[2] - artboard[0], height: artboard[1] - artboard[3], paper: paper, layers: layers, warnings: [] });
                }
                if (!canvases.length) { alert("Typefield: No supported items were found in the selection."); return; }
                var result = { format: "fontshelf-adobe-return", version: 1, sourceApplication: "Illustrator", name: doc.name.replace(/\\.[^.]+$/, ""), warnings: bridgeWarnings, canvases: canvases };
                var output = chooseOutput(result.name); if (!output) return;
                writeResult(output, result);
                alert("Typefield return JSON saved.\\n\\n" + output.fsName + "\\n\\nFonts are referenced by name; no font files were copied.");
            } catch (error) { alert("Typefield could not export this Illustrator document.\\n\\n" + error.message); }
        })();
        """
    }

    private static func indesignReturnScript(scope: AdobeReturnScope) -> String {
        let prelude = returnPrelude(target: .indesign, scope: scope)
        return """
        #target indesign
        \(prelude)
            function colorValue(color, opacity) {
                var result = { r: 0, g: 0, b: 0, a: Math.max(0, Math.min(1, safeNumber(opacity, 100) / 100)) };
                try { if (!color || color.name === "None") { result.a = 0; return result; } } catch (ignoredNone) {}
                try {
                    var values = color.colorValue;
                    if (color.space === ColorSpace.RGB) { result.r = values[0] / 255; result.g = values[1] / 255; result.b = values[2] / 255; }
                    else if (color.space === ColorSpace.CMYK) {
                        result.r = 1 - Math.min(1, (values[0] + values[3]) / 100); result.g = 1 - Math.min(1, (values[1] + values[3]) / 100); result.b = 1 - Math.min(1, (values[2] + values[3]) / 100);
                        warn("CMYK colors were converted approximately to RGB.");
                    } else warn("An unsupported InDesign color was replaced with black.");
                } catch (colorError) { warn("An unsupported InDesign swatch was replaced with black."); }
                return result;
            }
            function opacityValue(item) {
                try { return item.transparencySettings.blendingSettings.opacity; } catch (ignoredOpacity) { return 100; }
            }
            function componentOpacityValue(item, component) {
                var objectOpacity = opacityValue(item);
                try {
                    var settings = component === "stroke" ? item.strokeTransparencySettings : item.fillTransparencySettings;
                    return objectOpacity * Math.max(0, Math.min(100, safeNumber(settings.blendingSettings.opacity, 100))) / 100;
                } catch (ignoredComponent) { return objectOpacity; }
            }
            function alignmentValue(value) {
                if (value === Justification.CENTER_ALIGN) return "center";
                if (value === Justification.RIGHT_ALIGN) return "right";
                if (value === Justification.FULLY_JUSTIFIED || value === Justification.LEFT_JUSTIFIED || value === Justification.CENTER_JUSTIFIED || value === Justification.RIGHT_JUSTIFIED) return "justified";
                return "left";
            }
            function textLayer(item, pageBounds) {
                var bounds = item.geometricBounds, text = item.parentStory.texts[0], size = safeNumber(text.pointSize, 12), tracking = safeNumber(text.tracking, 0), fontName = "Helvetica", family = "", style = "";
                try { fontName = text.appliedFont.postscriptName; family = text.appliedFont.fontFamily; style = text.appliedFont.fontStyleName; } catch (fontError) { warn("A mixed or unavailable InDesign font was replaced with metadata fallback."); }
                return {
                    kind: "text", name: item.name || "Text", x: bounds[1] - pageBounds[1], y: bounds[0] - pageBounds[0], width: bounds[3] - bounds[1], height: bounds[2] - bounds[0],
                    color: colorValue(text.fillColor, opacityValue(item)), radius: 0, text: normalizedText(item.contents), fontName: fontName, fontFamily: family, fontStyle: style,
                    fontSize: size, lineHeight: safeNumber(text.leading, size * 1.2), trackingPoints: tracking / 1000 * size, trackingThousandths: tracking,
                    alignment: alignmentValue(text.justification), paragraphSpacing: safeNumber(text.spaceAfter, 0), wordSpacing: 0, firstLineIndent: safeNumber(text.firstLineIndent, 0),
                    underline: !!text.underline, strikethrough: !!text.strikeThru, kerning: true, axes: {}, features: {}, warnings: ["Mixed inline styles, linked stories, variable axes, and arbitrary OpenType settings require review after import."]
                };
            }
            function shapeLayer(item, pageBounds) {
                var bounds = item.geometricBounds;
                var strokeWidth = safeNumber(item.strokeWeight, 0), hasStroke = strokeWidth > 0;
                try { hasStroke = hasStroke && item.strokeColor.name !== "None"; } catch (ignoredStrokeColor) {}
                return { kind: "shape", name: item.name || "Shape", x: bounds[1] - pageBounds[1], y: bounds[0] - pageBounds[0], width: bounds[3] - bounds[1], height: bounds[2] - bounds[0], color: colorValue(item.fillColor, componentOpacityValue(item, "fill")), radius: 0,
                    stroke: hasStroke ? colorValue(item.strokeColor, componentOpacityValue(item, "stroke")) : null, strokeWidth: hasStroke ? strokeWidth : 0,
                    warnings: item.typename === "Rectangle" ? [] : ["A non-rectangular item was imported as its rectangular bounds."] };
            }
            function supported(item) { return item && (item.typename === "TextFrame" || item.typename === "Rectangle" || item.typename === "Oval" || item.typename === "Polygon"); }

            try {
                var doc = app.activeDocument, selectedOnly = chooseSelection(app.selection), selected = [];
                if (selectedOnly) {
                    if (!app.selection || !app.selection.length) { alert("Typefield: Select text frames or simple shapes first."); return; }
                    for (var selectionIndex = 0; selectionIndex < app.selection.length; selectionIndex++) {
                        if (supported(app.selection[selectionIndex])) selected.push(app.selection[selectionIndex]);
                        else warn("Unsupported InDesign selection “" + app.selection[selectionIndex].typename + "” was skipped.");
                    }
                }
                var canvases = [];
                for (var pageIndex = 0; pageIndex < doc.pages.length; pageIndex++) {
                    var page = doc.pages[pageIndex], pageBounds = page.bounds, source = selectedOnly ? selected : page.allPageItems, layers = [], paper = { r: 1, g: 1, b: 1, a: 1 };
                    for (var itemIndex = 0; itemIndex < source.length; itemIndex++) {
                        var item = source[itemIndex];
                        try { if (item.itemLayer && (item.itemLayer.name === "Typefield Export Metadata" || item.itemLayer.name === "FontShelf Export Metadata")) continue; } catch (ignoredLayer) {}
                        try { if (!item.parentPage || !item.parentPage.isValid || item.parentPage.id !== page.id) continue; } catch (ignoredPage) { continue; }
                        if (!supported(item)) { if (!selectedOnly) warn("Unsupported InDesign item “" + item.typename + "” was skipped."); continue; }
                        if (item.typename === "Rectangle" && item.name === "Canvas background") { paper = colorValue(item.fillColor, componentOpacityValue(item, "fill")); continue; }
                        layers.push(item.typename === "TextFrame" ? textLayer(item, pageBounds) : shapeLayer(item, pageBounds));
                    }
                    if (!selectedOnly || layers.length) canvases.push({ name: page.extractLabel("FontShelfCanvas") || ("Page " + (pageIndex + 1)), width: pageBounds[3] - pageBounds[1], height: pageBounds[2] - pageBounds[0], paper: paper, layers: layers, warnings: [] });
                }
                if (!canvases.length) { alert("Typefield: No supported items were found in the selection."); return; }
                var result = { format: "fontshelf-adobe-return", version: 1, sourceApplication: "InDesign", name: doc.name.replace(/\\.[^.]+$/, ""), warnings: bridgeWarnings, canvases: canvases };
                var output = chooseOutput(result.name); if (!output) return;
                writeResult(output, result);
                alert("Typefield return JSON saved.\\n\\n" + output.fsName + "\\n\\nFonts are referenced by name; no font files were copied.");
            } catch (error) { alert("Typefield could not export this InDesign document.\\n\\n" + error.message); }
        })();
        """
    }

    static func selfTest() {
        do {
            let fixture = """
            {"format":"fontshelf-adobe-return","version":1,"sourceApplication":"Illustrator","name":"Returned typeboard","warnings":["Review effects."],"canvases":[{"name":"Artboard 1","width":640,"height":480,"paper":{"r":1,"g":0.98,"b":0.95,"a":1},"layers":[{"kind":"shape","name":"Card","x":20,"y":20,"width":600,"height":200,"color":{"r":0.2,"g":0.3,"b":0.4,"a":0.5},"radius":12,"stroke":{"r":0.1,"g":0.2,"b":0.3,"a":0.75},"strokeWidth":4},{"kind":"text","name":"Heading","x":40,"y":50,"width":560,"height":80,"color":{"r":0.1,"g":0.1,"b":0.1,"a":1},"text":"Editable heading","fontName":"TestPS","fontSize":48,"lineHeight":52,"trackingThousandths":20,"alignment":"center","paragraphSpacing":4,"firstLineIndent":0,"underline":false,"strikethrough":false,"kerning":true,"axes":{"wght":650},"features":{"liga":1}}]}]}
            """
            let document = try decode(Data(fixture.utf8))
            let board = try board(document: document, installedFontNames: ["TestPS"])
            precondition(board.directions.count == 1 && board.directions[0].canvas == .imported)
            precondition(board.directions[0].importedSource == .illustrator && board.directions[0].canvasDisplayName == "Illustrator layout" && board.directions[0].canvasUnitLabel == "pt")
            precondition(board.directions[0].importedLayout?.layers.count == 2)
            precondition(board.directions[0].importedLayout?.layers[0].strokeWidth == 4 && board.directions[0].importedLayout?.layers[0].strokeColor == "1A334D")
            precondition(board.directions[0].importedLayout?.layers[0].opacity == 0.5 && board.directions[0].importedLayout?.layers[0].strokeOpacity == 0.75,
                         "Adobe return must preserve independent fill and stroke opacity")
            precondition(board.directions[0].importedLayout?.layers[1].style?.fontName == "TestPS")
            precondition(board.directions[0].importedLayout?.layers[1].style?.axes[tagID("wght")] == 650)
            var invalidStroke = document
            invalidStroke.canvases[0].layers[0].strokeWidth = 1_001
            precondition((try? self.board(document: invalidStroke)) == nil, "Adobe return import must reject oversized strokes")
            for target in AdobeTypeSystemTarget.allCases {
                let first = script(target: target, scope: .document)
                precondition(first == script(target: target, scope: .document), "Adobe return script must be deterministic")
                precondition(first.contains("fontshelf-adobe-return") && first.contains("writeResult"))
                if target == .illustrator {
                    precondition(first.contains("pageItem.parent.typename !== \"Layer\""), "Illustrator document export must visit grouped children only through their top-level group")
                    precondition(first.contains("color.typename === \"NoColor\"") && first.contains("result.b = color.gray / 100"), "Illustrator return colors must preserve no-fill and grayscale direction")
                    precondition(!first.contains("result.b = 1 - color.gray / 100"), "Illustrator grayscale must not be inverted")
                } else {
                    precondition(first.contains("color.name === \"None\"") && first.contains("item.parentPage.id !== page.id"), "InDesign return export must preserve no-fill and compare stable page IDs")
                    precondition(first.contains("function componentOpacityValue(item, component)") &&
                                 first.contains("componentOpacityValue(item, \"fill\")") && first.contains("componentOpacityValue(item, \"stroke\")"),
                                 "InDesign return export must read independent fill and stroke opacity")
                    precondition(!first.contains("item.parentPage !== page"), "InDesign DOM objects must not be compared by JavaScript identity")
                }
                let context = JSContext()!
                context.evaluateScript("var alerts = []; function alert(value) { alerts.push(String(value)); } var app = { documents: [] }; var Folder = { desktop: { fsName: '/tmp' } }; function File(path) { this.fsName = path; this.name = path; }")
                let body = first.split(separator: "\n", omittingEmptySubsequences: false).dropFirst().joined(separator: "\n")
                context.evaluateScript(body)
                precondition(context.exception == nil, "Generated Adobe return script must parse as JavaScript: \(String(describing: context.exception))")
                precondition(context.evaluateScript("alerts.length")!.toInt32() == 1)
            }
        } catch {
            preconditionFailure("Adobe return bridge self-test failed: \(error)")
        }
    }
}
