import SwiftUI
import AppKit
import CoreText
import JavaScriptCore

// These are coverage probes, not claims of full language or shaping support.
enum WritingSystem: String, CaseIterable, Hashable {
    case devanagari = "Devanagari / Hindi", japanese = "Japanese", simplified = "Chinese · Simplified", traditional = "Chinese · Traditional", korean = "Korean", arabic = "Arabic", hebrew = "Hebrew", bengali = "Bengali", gujarati = "Gujarati", tamil = "Tamil", telugu = "Telugu", thai = "Thai", greek = "Greek", cyrillic = "Cyrillic", latin = "Latin"
    var probe: String {
        switch self {
        case .devanagari: return "अआइईउएकखगचजतनमरहािुे"
        case .japanese: return "あいうえおかきくけこアイウエオカキクケコ日本語"
        case .simplified: return "汉语国书车门风东学这"
        case .traditional: return "漢語國書車門風東學這"
        case .korean: return "가나다라마바사아자차카타파하한글"
        case .arabic: return "ابتثجحخدذرزسشصضطظعغفقكلمنهوي"
        case .hebrew: return "אבגדהוזחטיכלמנסעפצקרשת"
        case .bengali: return "অআইউএকখগচজতনমরহ"
        case .gujarati: return "અઆઇઉએકખગચજતનમરહ"
        case .tamil: return "அஆஇஉஎகசஞதநமயரவ"
        case .telugu: return "అఆఇఉఎకఖగచజతనమరహ"
        case .thai: return "กขคงจฉชดตถทนบปผมยรลวสห"
        case .greek: return "ΑΒΓΔΕΖΗΘαβγδεζηθ"
        case .cyrillic: return "АБВГДЕЖЗабвгдежз"
        case .latin: return "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
        }
    }
    var sample: String {
        switch self {
        case .devanagari: return "नमस्ते दुनिया — हिन्दी अक्षर और शब्द"
        case .japanese: return "日本語の文字 — ひらがな カタカナ"
        case .simplified: return "简体中文 — 字体与文字设计"
        case .traditional: return "繁體中文 — 字體與文字設計"
        case .korean: return "한글 글꼴과 문자 디자인"
        case .arabic: return "اللغة العربية — حروف وكلمات"
        case .hebrew: return "אותיות ומילים בעברית"
        case .bengali: return "বাংলা অক্ষর এবং শব্দ"
        case .gujarati: return "ગુજરાતી અક્ષરો અને શબ્દો"
        case .tamil: return "தமிழ் எழுத்துக்கள்"
        case .telugu: return "తెలుగు అక్షరాలు"
        case .thai: return "ตัวอักษรภาษาไทย"
        case .greek: return "Ελληνικά γράμματα και λέξεις"
        case .cyrillic: return "Кириллица — буквы и слова"
        case .latin: return "The quick brown fox jumps over the lazy dog."
        }
    }
    var mark: String { String(probe.prefix(1)) }
    func supported(by coverage: CharacterSet) -> Bool { probe.unicodeScalars.allSatisfy { coverage.contains($0) } }
}
enum FontCoverage {
    static func missing(_ text: String, in coverage: CharacterSet) -> [Unicode.Scalar] {
        var seen = Set<UInt32>()
        return text.unicodeScalars.filter { scalar in
            // Formatting controls aren't independently rendered glyphs.
            let format = scalar.properties.generalCategory == .format
            return !CharacterSet.whitespacesAndNewlines.contains(scalar) && !format && !coverage.contains(scalar) && seen.insert(scalar.value).inserted
        }
    }
}
struct CoverageView: View {
    let text: String
    let coverage: CharacterSet
    var body: some View {
        let missing = FontCoverage.missing(text, in: coverage)
        VStack(alignment: .leading, spacing: 5) {
            Label(missing.isEmpty ? "Preview characters present" : "\(missing.count) missing preview characters", systemImage: missing.isEmpty ? "checkmark.circle" : "exclamationmark.triangle").foregroundStyle(missing.isEmpty ? Color.secondary : Color.orange)
            if !missing.isEmpty {
                Text(missing.prefix(32).map { "\(String($0)) U+\(String(format: "%04X", $0.value))" }.joined(separator: " · ")).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
            }
            Text("Checks character coverage only. Shaping, ligatures, and regional forms can differ.").font(.caption).foregroundStyle(.secondary)
        }
    }
}
struct CompareView: View {
    @ObservedObject var library: Library
    @State var preview: String
    @State var size: Double
    @State var styles: [String: String] = [:]
    @Environment(\.dismiss) var dismiss
    var body: some View {
        VStack(spacing: 16) {
            HStack { Text("Shortlist").font(.title2); Spacer(); Text("\(library.compared.count) \(library.compared.count == 1 ? "family" : "families")").foregroundStyle(.secondary); Button("Done") { dismiss() }.keyboardShortcut(.cancelAction) }
            HStack { TextField("Preview text", text: $preview); Slider(value: $size, in: 16...160).frame(width: 140); Text("\(Int(size)) pt").frame(width: 45) }
            ScrollView {
                VStack(spacing: 18) {
                    ForEach(library.compared) { family in
                        let face = family.faces.first { $0.name == styles[family.name] } ?? library.chosenFace(family)
                        let text = preview == "{family}" ? family.name : preview
                        VStack(alignment: .leading, spacing: 10) {
                            HStack { Text(family.name).font(.headline); Spacer(); ShelfDropdown(title: "Style", selection: Binding(get: { face.name }, set: { styles[family.name] = $0 }), options: family.faces.map { ($0.style, $0.name) }).frame(width: 230); Button { library.compare(family) } label: { Image(systemName: "xmark") }.help("Remove from comparison") }
                            // Wrapping allows comparing the same complete sentence at a shared size.
                            Text(text).font(.custom(face.name, size: size)).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                            CoverageView(text: text, coverage: face.coverage)
                        }.padding(16).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
                    }
                    if library.compared.isEmpty { Text("Add families with the + button on a font preview.").foregroundStyle(.secondary).padding(30) }
                }
            }
        }.padding(24).frame(width: 900, height: min(780, (NSScreen.main?.visibleFrame.height ?? 900) - 100))
    }
}
enum AdobeTarget: String, CaseIterable {
    case illustrator = "Illustrator", photoshop = "Photoshop", indesign = "InDesign"
    var directive: String { rawValue.lowercased() }
}
enum AdobeBridge {
    static func quoted(_ value: String) -> String {
        let data = try! JSONEncoder().encode(value)
        return String(data: data, encoding: .utf8)!.replacingOccurrences(of: "\u{2028}", with: "\\u2028").replacingOccurrences(of: "\u{2029}", with: "\\u2029")
    }
    static func script(font: String, target: AdobeTarget) -> String {
        let operation: String
        switch target {
        case .illustrator:
            operation = """
            var font = app.textFonts.getByName(fontName);
            var selection = app.activeDocument.selection;
            var targets = [];
            if (selection && selection.typename === "TextRange") targets.push(selection);
            else if (selection) for (var i = 0; i < selection.length; i++) {
                if (selection[i].typename === "TextFrame") targets.push(selection[i].textRange);
            }
            if (!targets.length) throw new Error("Select text or text frames first.");
            for (var j = 0; j < targets.length; j++) targets[j].characterAttributes.textFont = font;
            """
        case .photoshop:
            operation = """
            var font = app.fonts.getByName(fontName);
            var layer = app.activeDocument.activeLayer;
            if (layer.kind !== LayerKind.TEXT) throw new Error("Select a text layer first.");
            layer.textItem.font = font.postScriptName;
            """
        case .indesign:
            operation = """
            var font = null;
            for (var i = 0; i < app.fonts.length; i++) {
                if (app.fonts[i].postscriptName === fontName) { font = app.fonts[i]; break; }
            }
            if (!font) throw new Error("This font is not available in InDesign.");
            var targets = [];
            for (var j = 0; j < app.selection.length; j++) {
                var item = app.selection[j];
                try { if (item.texts && item.texts.length) targets.push(item.texts[0]); } catch (ignored) {}
            }
            if (!targets.length) throw new Error("Select text or text frames first.");
            app.doScript(function () {
                for (var k = 0; k < targets.length; k++) targets[k].appliedFont = font;
            }, ScriptLanguage.JAVASCRIPT, undefined, UndoModes.ENTIRE_SCRIPT, "FontShelf: Apply font");
            """
        }
        return """
        #target \(target.directive)
        // FontShelf: applies one font style to the current selection; does not save the document.
        // Photoshop applies to the entire active text layer. Custom variable axes are not transferred.
        (function () {
            try {
                var fontName = \(quoted(font));
                if (!app.documents.length) throw new Error("Open a document first.");
                \(operation)
            } catch (error) { alert("FontShelf: " + error.message); }
        })();
        """
    }
    static func export(face: Face, target: AdobeTarget) {
        let panel = NSSavePanel()
        panel.title = "Export \(target.rawValue) script"
        panel.nameFieldStringValue = "FontShelf-\(target.rawValue)-\(face.name.replacingOccurrences(of: "/", with: "-" )).jsx"
        panel.message = target == .photoshop ? "Run through File → Scripts → Browse in Photoshop. Applies to the entire active text layer." : target == .illustrator ? "Run through File → Scripts → Other Script in Illustrator. Applies to selected text or text frames." : "Run from InDesign’s Scripts panel. Applies to selected text or text frames."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try script(font: face.name, target: target).write(to: url, atomically: true, encoding: .utf8) }
        catch { let alert = NSAlert(); alert.messageText = "Could not export script"; alert.informativeText = error.localizedDescription; alert.runModal() }
    }
    static func selfTest() {
        // Execute the actual exported code against minimal Adobe DOM fixtures.
        // Real application compatibility is separately documented, not inferred from these fixtures.
        for target in AdobeTarget.allCases {
            let context = JSContext()!
            context.evaluateScript("""
            var alerts = []; function alert(s) { alerts.push(s); }
            var LayerKind = {TEXT: 1}; var ScriptLanguage = {JAVASCRIPT: 1}; var UndoModes = {ENTIRE_SCRIPT: 1};
            var font = {name: 'TestPS', postScriptName: 'TestPS', postscriptName: 'TestPS'};
            var range = {characterAttributes: {}, appliedFont: null};
            var layer = {kind: 1, textItem: {font: null}};
            var fonts = [font]; fonts.getByName = function(n) { if (n !== 'TestPS') throw new Error('Missing font'); return font; };
            var doc = {selection: [{typename: 'TextFrame', textRange: range}], activeLayer: layer};
            var app = {documents: [doc], activeDocument: doc, textFonts: fonts, fonts: fonts, selection: [{texts: [range]}], doScript: function(f) { f(); }};
            """)
            let body = script(font: "TestPS", target: target).split(separator: "\n").dropFirst().joined(separator: "\n")
            context.evaluateScript(body)
            precondition(context.exception == nil, "Adobe script parse/runtime failure")
            precondition(context.evaluateScript("alerts.length")!.toInt32() == 0)
            let check = target == .illustrator ? "range.characterAttributes.textFont === font" : target == .photoshop ? "layer.textItem.font === 'TestPS'" : "range.appliedFont === font"
            precondition(context.evaluateScript(check)!.toBool(), "Adobe font assignment failed")
            context.evaluateScript("app.documents = []; alerts = [];")
            context.evaluateScript(body)
            precondition(context.evaluateScript("alerts.length")!.toInt32() == 1, "Missing-document guard failed")
            let hostile = script(font: "Name\";throw new Error('injected');\u{2028}\\", target: target).split(separator: "\n").dropFirst().joined(separator: "\n")
            context.evaluateScript(hostile)
            precondition(context.exception == nil, "Font-name escaping failed")
        }
    }
}
