import SwiftUI
import AppKit
import CoreText

struct PreviewColorsView: View {
    @AppStorage("customPreviewColors") var enabled = false
    @AppStorage("previewInkHex") var inkHex = "EEEEEE"
    @AppStorage("previewPaperHex") var paperHex = "202020"
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Preview colors").font(.headline)
            Toggle("Use custom colors", isOn: $enabled)
            ColorPicker("Text", selection: Binding(get: { Color(nsColor: NSColor(hex: inkHex)) }, set: { inkHex = NSColor($0).rgbHex; enabled = true }), supportsOpacity: false)
            ColorPicker("Background", selection: Binding(get: { Color(nsColor: NSColor(hex: paperHex)) }, set: { paperHex = NSColor($0).rgbHex; enabled = true }), supportsOpacity: false)
            HStack { Button("Black on white") { inkHex = "111111"; paperHex = "FFFFFF"; enabled = true }; Button("Reset") { enabled = false; inkHex = "EEEEEE"; paperHex = "202020" } }
        }.padding(22).frame(width: 280)
    }
}
struct BodyColumns: NSViewRepresentable {
    let text: String
    let font: CTFont
    let columns: Int
    let width: Double
    let lineHeight: Double
    let tracking: Double
    let alignment: NSTextAlignment
    let ink: NSColor
    let paper: NSColor
    func makeNSView(context: Context) -> BodyColumnsNativeView { BodyColumnsNativeView() }
    func updateNSView(_ view: BodyColumnsNativeView, context: Context) {
        view.update(text: text, font: font, columns: columns, width: width,
                    lineHeight: lineHeight, tracking: tracking, alignment: alignment,
                    ink: ink, paper: paper)
    }
}

/// Retains TextKit's layout and selection while surrounding inspector controls update.
final class BodyColumnsNativeView: NSView {
    private struct Configuration {
        let text: String
        let font: CTFont
        let columns: Int
        let width: Double
        let lineHeight: Double
        let tracking: Double
        let alignment: NSTextAlignment
        let ink: NSColor
        let paper: NSColor

        func sameTextAttributes(as other: Configuration) -> Bool {
            CFEqual(font, other.font) && lineHeight == other.lineHeight &&
                tracking == other.tracking && alignment == other.alignment && ink.isEqual(other.ink)
        }
    }
    private let storage = NSTextStorage()
    private let textLayout = NSLayoutManager()
    private var textViews: [NSTextView] = []
    private var configuration: Configuration?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        storage.addLayoutManager(textLayout)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @discardableResult
    func update(text: String, font: CTFont, columns: Int, width: Double,
                lineHeight: Double, tracking: Double, alignment: NSTextAlignment,
                ink: NSColor, paper: NSColor) -> Bool {
        let next = Configuration(text: text, font: font, columns: max(1, columns), width: width,
                                 lineHeight: lineHeight, tracking: tracking, alignment: alignment,
                                 ink: ink, paper: paper)
        let previous = configuration
        // Swift String equality folds canonical Unicode equivalents. Retain the
        // exact input for copy/selection, including composed vs decomposed text.
        let textChanged = previous.map { !$0.text.utf8.elementsEqual(text.utf8) } ?? true
        let attributesChanged = previous.map { !next.sameTextAttributes(as: $0) } ?? true
        let columnsChanged = previous?.columns != next.columns
        let widthChanged = previous?.width != width
        let paperChanged = previous.map { !paper.isEqual($0.paper) } ?? true
        guard textChanged || attributesChanged || columnsChanged || widthChanged || paperChanged else { return false }
        configuration = next

        if textChanged || attributesChanged {
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineHeightMultiple = lineHeight
            paragraph.paragraphSpacing = 14
            paragraph.alignment = alignment
            storage.beginEditing()
            if textChanged { storage.replaceCharacters(in: NSRange(location: 0, length: storage.length), with: text) }
            storage.setAttributes([.font: font as NSFont, .foregroundColor: ink,
                                   .paragraphStyle: paragraph, .kern: tracking],
                                  range: NSRange(location: 0, length: storage.length))
            storage.endEditing()
        }
        if columnsChanged {
            // Keep the selected text when changing the number of columns. A new
            // body string deliberately starts with a fresh insertion point.
            let selection = textChanged ? NSRange(location: 0, length: 0) : textViews.first?.selectedRange()
            for textView in textViews { textView.removeFromSuperview() }
            textViews.removeAll()
            while !textLayout.textContainers.isEmpty { textLayout.removeTextContainer(at: 0) }
            for _ in 0..<next.columns {
                let container = NSTextContainer(size: NSSize(width: 1, height: 520))
                container.lineFragmentPadding = 0
                textLayout.addTextContainer(container)
                let textView = NSTextView(frame: .zero, textContainer: container)
                textView.isEditable = false
                textView.isSelectable = true
                textView.drawsBackground = true
                textView.backgroundColor = paper
                textView.textContainerInset = .zero
                textView.isVerticallyResizable = false
                textView.isHorizontallyResizable = false
                textViews.append(textView)
                addSubview(textView)
            }
            if let selection { textViews.first?.setSelectedRange(selection) }
        }
        if columnsChanged || widthChanged {
            let gap = 24.0
            let columnWidth = max(1, (width - gap * Double(next.columns - 1)) / Double(next.columns))
            for (index, textView) in textViews.enumerated() {
                textView.frame = NSRect(x: Double(index) * (columnWidth + gap), y: 0,
                                        width: columnWidth, height: 520)
                textView.textContainer?.containerSize = NSSize(width: columnWidth, height: 520)
            }
        }
        if paperChanged { for textView in textViews { textView.backgroundColor = paper } }
        if textChanged { textViews.first?.setSelectedRange(NSRange(location: 0, length: 0)) }
        return true
    }
}
struct LayoutWorkspace: View {
    let face: Face
    let axes: [Int: Double]
    let features: [String: Int]
    @State var headline = "Headline"
    @State var copy = String(repeating: "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed non risus. Suspendisse lectus tortor, dignissim sit amet, adipiscing nec, ultricies sed, dolor. Cras elementum ultrices diam. Maecenas ligula massa, varius a, semper congue, euismod non, mi.\n\n", count: 5)
    @State var bodySize = 18.0
    @State var headingSize = 44.0
    @State var width = 740.0
    @State var lineHeight = 1.3
    @State var tracking = 0.0
    @State var columns = 2
    @State var alignment = "Left"
    @State var editCopy = false
    @AppStorage("customPreviewColors") var customColors = false
    @AppStorage("previewInkHex") var inkHex = "EEEEEE"
    @AppStorage("previewPaperHex") var paperHex = "202020"
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack { TextField("Headline", text: $headline); Button(editCopy ? "Hide text editor" : "Edit body text") { editCopy.toggle() } }
                if editCopy { TextEditor(text: $copy).font(.body).frame(height: 130).overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.secondary.opacity(0.3))) }
                HStack {
                    Stepper("Body \(Int(bodySize)) pt", value: $bodySize, in: 8...72).frame(width: 160)
                    Stepper("Heading \(Int(headingSize)) pt", value: $headingSize, in: 16...100).frame(width: 180)
                    ShelfDropdown(title: "Columns", selection: $columns, options: (1...3).map { (String($0), $0) }).frame(width: 130)
                    ShelfDropdown(title: "Align", selection: $alignment, options: ["Left", "Center", "Right", "Justified"].map { ($0, $0) }).frame(width: 160)
                }
                HStack { Text("Width"); Slider(value: $width, in: 360...920, step: 10); Text("\(Int(width)) pt").monospacedDigit(); Text("Leading"); Slider(value: $lineHeight, in: 1...2).frame(width: 95); Text(String(format: "%.2f", lineHeight)); Text("Tracking"); Slider(value: $tracking, in: -1...6).frame(width: 90); Text(String(format: "%.1f", tracking)) }
                Text("Text flows across columns. Overflow beyond the fixed 520 pt page is clipped; reduce size or edit the text.").font(.caption).foregroundStyle(.secondary)
                ScrollView(.horizontal) {
                    VStack(alignment: .leading, spacing: 18) {
                        FontPreview(text: headline, name: face.name, size: headingSize, variations: axes, features: features).frame(width: width, height: headingSize * 1.5)
                        BodyColumns(text: copy, font: OpenType.font(name: face.name, size: bodySize, axes: axes, features: features), columns: columns, width: width, lineHeight: lineHeight, tracking: tracking, alignment: alignment == "Center" ? .center : alignment == "Right" ? .right : alignment == "Justified" ? .justified : .left, ink: customColors ? NSColor(hex: inkHex) : .labelColor, paper: customColors ? NSColor(hex: paperHex) : .textBackgroundColor).frame(width: width, height: 520)
                    }.padding(22).background(customColors ? Color(nsColor: NSColor(hex: paperHex)) : Color(nsColor: .textBackgroundColor))
                }
            }.padding(18)
        }
    }
}
struct OpenTypeInspector: View {
    let face: Face
    @Binding var features: [String: Int]
    @Binding var text: String
    let axes: [Int: Double]
    @State var query = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { TextField("Search feature tags", text: $query); Button("Feature sample") { text = "office affine fi fl ffi 0123456789 1/2 3/4 HAMBURGEFONTS abcdefgh" }; Button("Reset features") { features = [:] } }
            FontPreview(text: text, name: face.name, size: 38, variations: axes, features: features).frame(height: 75)
            Text("Default uses the font’s own settings. Features can depend on script, language, or specific characters.").font(.caption).foregroundStyle(.secondary)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(face.facts.features.filter { query.isEmpty || $0.localizedCaseInsensitiveContains(query) || OpenType.label($0).localizedCaseInsensitiveContains(query) }, id: \.self) { tag in
                        HStack { Text(tag).font(.system(.body, design: .monospaced)).frame(width: 55, alignment: .leading); Text(OpenType.label(tag)); Spacer(); ShelfDropdown(title: "Value", selection: Binding(get: { features[tag] ?? -1 }, set: { if $0 < 0 { features.removeValue(forKey: tag) } else { features[tag] = $0 } }), options: [("Default", -1), ("Off", 0), ("On", 1)] + (2...9).map { ("Alternate \($0)", $0) }, showsTitle: false).frame(width: 145) }.padding(8).background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 5))
                    }
                    if face.facts.features.isEmpty { Text("No GSUB/GPOS feature tags found. This font may use Apple Advanced Typography features.").foregroundStyle(.secondary) }
                    DisclosureGroup("Core Text feature metadata") {
                        Text(coreTextMetadata).font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    }.padding(.top, 12)
                }
            }
        }.padding(18)
    }
    var coreTextMetadata: String {
        let font = CTFontCreateWithName(face.name as CFString, 24, nil)
        let types = CTFontCopyFeatures(font) as? [[String: Any]] ?? []
        return types.map { type in
            let name = type[kCTFontFeatureTypeNameKey as String] as? String ?? "Feature"
            let selectors = type[kCTFontFeatureTypeSelectorsKey as String] as? [[String: Any]] ?? []
            return name + ": " + selectors.compactMap { $0[kCTFontFeatureSelectorNameKey as String] as? String }.joined(separator: ", ")
        }.joined(separator: "\n")
    }
}
struct FontContextView: View {
    let face: Face
    @ObservedObject var library: Library
    @State private var noteDraft = ""
    @State private var noteFaceName = ""
    @State private var noteStatus = ""
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                let font = CTFontCreateWithName(face.name as CFString, 1000, nil)
                Text(face.name).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                Text("Original family: \(face.originalFamily), \(face.style)")
                Text("\(face.facts.glyphCount) glyphs, weight \(face.facts.weight), \(CTFontGetUnitsPerEm(font)) units/em")
                Text("At 1000 pt: ascent \(Int(CTFontGetAscent(font))), descent \(Int(CTFontGetDescent(font))), x-height \(Int(CTFontGetXHeight(font))), cap height \(Int(CTFontGetCapHeight(font)))").font(.caption)
                ForEach(metadata(font), id: \.0) { label, value in VStack(alignment: .leading, spacing: 3) { Text(label).font(.caption).foregroundStyle(.secondary); Text(value).textSelection(.enabled) } }
                if let url = face.url {
                    Text(url.path).font(.caption).textSelection(.enabled)
                    let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                    Text("\(url.pathExtension.uppercased()), \(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)), \(scopeLabel(url))").font(.caption)
                    HStack { Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }; Button("Copy path") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(url.path, forType: .string) } }
                }
                Text("Script coverage").font(.headline)
                Text(face.writingSystems.sorted { $0.displayName < $1.displayName }.map(\.displayName).joined(separator: ", "))
                Text("Notes").font(.headline)
                TextEditor(text: $noteDraft).frame(height: 100).overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.2)))
                    .accessibilityLabel("Notes for \(face.name)")
                if !noteStatus.isEmpty { Text(noteStatus).font(.caption).foregroundStyle(noteStatus.hasPrefix("Notes saved") ? Color.secondary : Color.red).textSelection(.enabled) }
            }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { loadNote(for: face.name) }
        .onChange(of: noteDraft) { _ in if noteStatus.hasPrefix("Notes saved") { noteStatus = "" } }
        .onChange(of: face.name) { newName in saveNote(); loadNote(for: newName) }
        .onDisappear { saveNote() }
        .task(id: noteDraft) {
            try? await Task.sleep(nanoseconds: 650_000_000)
            if !Task.isCancelled { await MainActor.run { saveNote() } }
        }
    }
    private func loadNote(for name: String) {
        noteFaceName = name
        noteDraft = library.pro.notes[name] ?? ""
        noteStatus = ""
    }
    private func saveNote() {
        let name = noteFaceName
        guard !name.isEmpty, noteDraft != (library.pro.notes[name] ?? "") else { return }
        let draft = noteDraft
        if library.updatePro({ $0.notes[name] = draft }) {
            noteStatus = "Notes saved for \(name) in Library."
        } else {
            noteDraft = library.pro.notes[name] ?? ""
            noteStatus = "Notes were not saved. Previous text restored. " + library.message
        }
    }
    func metadata(_ font: CTFont) -> [(String, String)] {
        [("Version", kCTFontVersionNameKey), ("Designer", kCTFontDesignerNameKey), ("Manufacturer", kCTFontManufacturerNameKey), ("Description", kCTFontDescriptionNameKey), ("Copyright", kCTFontCopyrightNameKey), ("Trademark", kCTFontTrademarkNameKey), ("License", kCTFontLicenseNameKey), ("License URL", kCTFontLicenseURLNameKey)].compactMap { label, key in
            guard let value = CTFontCopyName(font, key) as String?, !value.isEmpty else { return nil }; return (label, value)
        }
    }
    func scopeLabel(_ url: URL) -> String { switch CTFontManagerGetScopeForURL(url as CFURL) { case .process: return "Typefield only"; case .session: return "Current login session"; case .persistent: return "Installed"; default: return "System or unregistered" } }
}
struct FontSwitchView: View {
    let face: Face
    @ObservedObject var activation = ActivationManager.shared
    @State var target: AdobeTarget = .illustrator
    @State var status = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Adobe scripts").font(.title2)
            ShelfDropdown(title: "Target application", selection: $target, options: AdobeTarget.allCases.map { ($0.rawValue, $0) }).frame(width: 310)
            Text(face.name).font(.system(.body, design: .monospaced))
            Button("Export Adobe script…") { AdobeBridge.export(face: face, target: target) }
            Text("Run the exported script in the selected Adobe app with text selected. The font must already be available there. Photoshop changes the entire active text layer. Custom variable-axis values are not transferred.").font(.caption).foregroundStyle(.secondary)
            Text(status).textSelection(.enabled).foregroundStyle(.secondary)
            if let url = face.url {
                Divider()
                Text("Temporary activation").font(.headline)
                Text(activation.owns(url) ? "Temporarily activated by Typefield" : "Not temporarily activated by Typefield")
                Button(activation.owns(url) ? "Deactivate temporary font" : "Activate temporarily") {
                    do { if activation.owns(url) { try activation.deactivate(url); status = "Temporary activation cleared." } else { status = try activation.activate(url) } } catch { status = error.localizedDescription }
                }
                Text("Cleared on normal quit or logout.").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }.padding(22)
    }
}
struct SimilarFontsView: View {
    @ObservedObject var library: Library
    let family: Family
    let reference: Face
    let preview: String
    @Environment(\.dismiss) private var dismiss
    var results: [FontSimilarityResult] { library.similarFamilies(to: reference, limit: 16) }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Similar in my library").font(.title3)
                    Text("Ranked only from fonts already on this Mac using category, width, weight, x-height, proportions, PANOSE metadata, script coverage, and your visual labels. Results are ordered—not fake match percentages.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if reference.facts.widthClass < 5 { Label("Narrow", systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right").font(.caption) }
                if reference.facts.panoseIndicatesHighContrast { Label("High contrast (metadata)", systemImage: "circle.lefthalf.filled").font(.caption) }
            }
            HStack(spacing: 8) {
                Text("Your visual labels").font(.caption).foregroundStyle(.secondary)
                visualLabel("Soft", tag: "visual/soft")
                visualLabel("Geometric", tag: "visual/geometric")
                visualLabel("Editorial", tag: "visual/editorial")
                Text("Labels are searchable tags and influence local similarity where appropriate.").font(.caption2).foregroundStyle(.secondary)
            }
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(results) { result in
                        HStack(alignment: .top, spacing: 14) {
                            VStack(alignment: .leading, spacing: 7) {
                                HStack { Text(result.family.name).font(.headline); Text(", " + result.face.style).foregroundStyle(.secondary); Spacer(); Text(library.category(result.family).rawValue).font(.caption).foregroundStyle(.secondary) }
                                FontPreview(text: preview, name: result.face.name, size: 29, wraps: true).frame(minHeight: 44).allowsHitTesting(false)
                                Text(result.reasons.isEmpty ? "Closest available local metrics" : result.reasons.joined(separator: "; ")).font(.caption).foregroundStyle(.secondary)
                            }
                            VStack(alignment: .trailing, spacing: 7) {
                                Button("Inspect") { open(result.family) }
                                Button(library.comparison.contains(result.family.name) ? "Shortlisted" : "Shortlist") { library.compare(result.family) }
                                Button("New typeboard") { dismiss(); DispatchQueue.main.async { library.pairSelection([reference.name, result.face.name], source: "Pairing suggestion") } }
                            }.fixedSize()
                        }.padding(14).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
                    }
                    if results.isEmpty { Text("No other local families are available to compare.").foregroundStyle(.secondary).padding(30).frame(maxWidth: .infinity) }
                }
            }
        }.padding(18)
    }
    func visualLabel(_ label: String, tag: String) -> some View {
        let active = family.faces.contains { library.pro.tags[$0.name]?.contains(tag) == true }
        return Button { setTag(tag, enabled: !active) } label: { HStack(spacing: 4) { if active { Image(systemName: "checkmark") }; Text(label) } }.buttonStyle(.bordered).tint(active ? .accentColor : nil)
    }
    func setTag(_ tag: String, enabled: Bool) {
        let previous = library.pro.tags
        for face in family.faces { if enabled { library.pro.tags[face.name, default: []].insert(tag) } else { library.pro.tags[face.name]?.remove(tag); if library.pro.tags[face.name]?.isEmpty == true { library.pro.tags.removeValue(forKey: face.name) } } }
        if !library.savePro() { library.pro.tags = previous }
    }
    func open(_ family: Family) { dismiss(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { library.detail = family } }
}

struct FontDiscoveryView: View {
    @ObservedObject var library: Library
    let eligibleFamilies: [Family]
    let preview: String
    @Environment(\.dismiss) private var dismiss
    @State private var currentScope = true
    @State private var includeSystemFonts = false
    @State private var seed: UInt64 = 1
    var results: [FontDiscoveryResult] { library.discoveryCandidates(in: currentScope ? eligibleFamilies : nil, includeSystemFonts: includeSystemFonts, seed: seed, limit: 16) }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) { Text("Rediscover your library").font(.title2); Text("Local fonts you have never explicitly applied come first, followed by the least recently used. Opening or previewing a font never counts as use.").foregroundStyle(.secondary) }
                Spacer(); Button("Another mix") { seed &+= 1 }; Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding(20)
            HStack(spacing: 16) { Toggle("Use current library filters", isOn: $currentScope).toggleStyle(.checkbox); Toggle("Include system fonts", isOn: $includeSystemFonts).toggleStyle(.checkbox); Spacer(); Text("\(results.count) local families").font(.caption).foregroundStyle(.secondary) }.padding(.horizontal, 20).padding(.bottom, 14)
            Divider()
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(results) { result in
                        HStack(alignment: .top, spacing: 16) {
                            VStack(alignment: .leading, spacing: 7) {
                                HStack { Text(result.family.name).font(.headline); Text(", " + result.face.style).foregroundStyle(.secondary); Spacer(); Text(usage(result)).font(.caption).foregroundStyle(.secondary) }
                                FontPreview(text: preview, name: result.face.name, size: 31, wraps: true).frame(minHeight: 46).allowsHitTesting(false)
                                Text(result.currentCanvasCount == 0 ? "Not used in a current canvas" : "Used in \(result.currentCanvasCount) current canvas\(result.currentCanvasCount == 1 ? "" : "es")").font(.caption).foregroundStyle(.secondary)
                            }
                            VStack(alignment: .trailing, spacing: 7) {
                                Button("Inspect") { open(result.family) }
                                Button(library.comparison.contains(result.family.name) ? "Shortlisted" : "Shortlist") { library.compare(result.family) }
                                Button("New typeboard") { dismiss(); DispatchQueue.main.async { library.pairSelection([result.face.name], source: "Discovery suggestion") } }
                            }.fixedSize()
                        }.padding(14).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
                    }
                    if results.isEmpty { Text(currentScope ? "No fonts match the current library filters. Turn off the scope filter to rediscover the full local library." : "No eligible local fonts found.").foregroundStyle(.secondary).padding(40) }
                }.padding(20)
            }
        }.frame(width: 900, height: min(760, (NSScreen.main?.visibleFrame.height ?? 900) - 100))
    }
    func usage(_ result: FontDiscoveryResult) -> String {
        if let date = result.lastAppliedAt { return "Last applied " + date.formatted(date: .abbreviated, time: .omitted) + " (\(result.applicationCount) \(result.applicationCount == 1 ? "time" : "times"))" }
        return "Never explicitly applied"
    }
    func open(_ family: Family) { dismiss(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { library.detail = family } }
}

struct DetailView: View {
    @ObservedObject var library: Library
    let family: Family
    @State var preview: String
    @State var size: Double
    @State var chosen = ""
    @State var tab = "All styles"
    @State var overlayStyles = false
    @State private var exportStatus = ""
    @State private var showLicenseSources = false
    @State private var settingsError = ""
    @Environment(\.dismiss) var dismiss
    var face: Face { family.faces.first { $0.name == chosen } ?? library.chosenFace(family) }
    private func persistPro(_ change: (inout ProState) -> Void) {
        if !library.updatePro(change) { settingsError = library.message }
    }
    private func setMainPreview(_ name: String) {
        persistPro { $0.mainPreviews[family.name] = name }
    }
    private func weight(_ face: Face) -> Double {
        let traits = CTFontCopyTraits(CTFontCreateWithName(face.name as CFString, 24, nil)) as NSDictionary
        return (traits[kCTFontWeightTrait] as? Double ?? 0) + (face.style.lowercased().contains("italic") ? 0.001 : 0)
    }
    var axesBinding: Binding<[Int: Double]> { Binding(get: { library.pro.axes[face.name] ?? [:] }, set: { values in persistPro { $0.axes[face.name] = values } }) }
    var featureBinding: Binding<[String: Int]> { Binding(get: { library.pro.features[face.name] ?? [:] }, set: { values in persistPro { $0.features[face.name] = values } }) }
    var axes: [Axis] {
        let values = CTFontCopyVariationAxes(CTFontCreateWithName(face.name as CFString, 24, nil)) as? [[String: Any]] ?? []
        return values.compactMap { d in
            guard let id = d[kCTFontVariationAxisIdentifierKey as String] as? Int, let min = d[kCTFontVariationAxisMinimumValueKey as String] as? Double, let max = d[kCTFontVariationAxisMaximumValueKey as String] as? Double, let value = d[kCTFontVariationAxisDefaultValueKey as String] as? Double, max > min else { return nil }
            return Axis(id: id, name: d[kCTFontVariationAxisNameKey as String] as? String ?? "Axis", min: min, max: max, defaultValue: value)
        }
    }
    var body: some View {
        VStack(spacing: 14) {
            HStack { Text(family.name).font(.title2); Spacer(); FontActivationButton(face: face) { exportStatus = $0 }; Menu("More") { Button("License sources…") { showLicenseSources = true }; Button("Find similar") { tab = "Similar" } }; Button("Export font…") { if let result = FontExporter.export([face]) { exportStatus = result } }; Button("Done") { dismiss() }.keyboardShortcut(.cancelAction) }
                .alert("Settings not saved", isPresented: Binding(get: { !settingsError.isEmpty }, set: { if !$0 { settingsError = "" } })) {
                    Button("OK") { settingsError = "" }
                } message: { Text(settingsError) }
            if !exportStatus.isEmpty {
                HStack { Text(exportStatus).font(.caption).foregroundStyle(exportStatus.hasPrefix("Export failed:") ? .red : .secondary).textSelection(.enabled); Spacer(); Button("Dismiss") { exportStatus = "" } }
            }
            HStack {
                ShelfDropdown(title: "Style", selection: $chosen, options: family.faces.map { ($0.style, $0.name) }).frame(width: 300)
                Button("Use as main preview") { setMainPreview(face.name) }
                Button("Compare in library") { library.overlayName = face.name; dismiss() }
                Spacer(); Text(library.category(family).rawValue).foregroundStyle(.secondary)
            }
            Picker("Inspector", selection: $tab) { ForEach(["All styles", "Preview", "Similar", "Glyphs", "Waterfall", "Body layout", "OpenType", "Context", "Adobe scripts"], id: \.self) { Text($0) } }.pickerStyle(.segmented).labelsHidden()
            Group {
                switch tab {
                case "Glyphs": GlyphBrowser(face: face, axes: axesBinding.wrappedValue)
                case "Similar": SimilarFontsView(library: library, family: family, reference: face, preview: preview)
                case "Waterfall": WaterfallView(face: face, text: preview, axes: axesBinding.wrappedValue, features: featureBinding.wrappedValue)
                case "All styles":
                    VStack {
                        HStack {
                            Toggle("Overlay comparison", isOn: $overlayStyles).toggleStyle(.checkbox)
                            if overlayStyles { Text("Cyan: \(face.style); orange: each style").foregroundStyle(.secondary) }
                            Spacer()
                        }
                        HStack { TextField("Preview text", text: $preview); Slider(value: $size, in: 16...160).frame(width: 150); Text("\(Int(size)) pt").monospacedDigit().frame(width: 50) }
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 12) {
                                ForEach(family.faces.sorted { weight($0) < weight($1) }) { style in
                                    VStack(alignment: .leading, spacing: 12) {
                                        HStack { Text(style.style).font(.headline); Spacer(); Button("Inspect") { chosen = style.name; tab = "Preview" }; Button("Compare in library") { library.overlayName = style.name; dismiss() }; Button("Use as main preview") { setMainPreview(style.name) } }
                                        if overlayStyles {
                                            OverlayPreview(text: preview, candidate: style.name, reference: face.name, size: size, library: library)
                                        } else {
                                            FontPreview(text: preview, name: style.name, size: size, wraps: true, variations: library.pro.axes[style.name] ?? [:], features: library.pro.features[style.name] ?? [:])
                                        }
                                    }.padding(16).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
                                }
                            }.padding(.vertical, 8)
                        }
                    }
                case "Body layout": LayoutWorkspace(face: face, axes: axesBinding.wrappedValue, features: featureBinding.wrappedValue)
                case "OpenType": OpenTypeInspector(face: face, features: featureBinding, text: $preview, axes: axesBinding.wrappedValue)
                case "Context": FontContextView(face: face, library: library)
                case "Adobe scripts": FontSwitchView(face: face)
                default:
                    ScrollView { VStack(alignment: .leading, spacing: 18) {
                        HStack { TextField("Preview text", text: $preview); Slider(value: $size, in: 16...160).frame(width: 150); Text("\(Int(size)) pt").monospacedDigit().frame(width: 50) }
                        ScrollView(.horizontal) { FontPreview(text: preview, name: face.name, size: size, variations: axesBinding.wrappedValue, features: featureBinding.wrappedValue).frame(width: max(860, Double(preview.count) * size), height: size * 1.6) }.frame(height: size * 1.6 + 12)
                        if !axes.isEmpty {
                            HStack { Text("Variable axes").font(.headline); Spacer(); Button("Reset axes") { axesBinding.wrappedValue = [:] } }
                            ForEach(axes) { axis in HStack { Text(axis.name).frame(width: 120, alignment: .leading); Slider(value: Binding(get: { axesBinding.wrappedValue[axis.id] ?? axis.defaultValue }, set: { axesBinding.wrappedValue[axis.id] = $0 }), in: axis.min...axis.max); Text(String(format: "%.1f", axesBinding.wrappedValue[axis.id] ?? axis.defaultValue)).monospacedDigit().frame(width: 65) } }
                            Button("Copy CSS variation settings") {
                                let values = axes.map { axis -> String in let bytes: [UInt8] = [UInt8((axis.id >> 24) & 255), UInt8((axis.id >> 16) & 255), UInt8((axis.id >> 8) & 255), UInt8(axis.id & 255)]; let tag = String(bytes: bytes, encoding: .ascii) ?? "axis"; return "'\(tag)' \(String(format: "%.2f", axesBinding.wrappedValue[axis.id] ?? axis.defaultValue))" }.joined(separator: ", ")
                                NSPasteboard.general.clearContents(); NSPasteboard.general.setString("font-variation-settings: \(values);", forType: .string)
                            }
                        }
                        CoverageView(text: preview, coverage: face.coverage)
                        FontPreview(text: "ABCDEFGHIJKLMNOPQRSTUVWXYZ abcdefghijklmnopqrstuvwxyz 0123456789", name: face.name, size: 28, variations: axesBinding.wrappedValue, features: featureBinding.wrappedValue).frame(height: 60)
                        Text(face.name).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    }.padding(18) }
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }.typefieldSheet(isPresented: $showLicenseSources) { FontLicenseSourcesView(face: face) }.padding(20).frame(width: 980, height: min(820, (NSScreen.main?.visibleFrame.height ?? 920) - 90)).onAppear { chosen = library.chosenFace(family).name }
    }
}
