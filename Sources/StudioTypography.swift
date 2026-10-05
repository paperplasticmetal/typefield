import SwiftUI
import AppKit

/// Color values remain six-digit RGB in saved typeboards and imported layers.
/// Accept the common short form when someone pastes a CSS color into the inspector.
enum StudioHexColor {
    static func parse(_ input: String) -> String? {
        var value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.unicodeScalars.allSatisfy({ (48...57).contains($0.value) || (65...70).contains($0.value) || (97...102).contains($0.value) }) else { return nil }
        if value.count == 3 { value = value.map { String(repeating: String($0), count: 2) }.joined() }
        guard value.count == 6 else { return nil }
        return value.uppercased()
    }
}

/// The swatch and direct hex entry edit the same saved RGB value. A partial or
/// invalid draft stays local until it can be committed as a complete color.
struct StudioHexColorPicker: View {
    let title: String
    @Binding var hex: String
    @State private var draft = ""
    @State private var invalid = false
    @FocusState private var focused: Bool

    private func refreshDraft() {
        draft = "#" + hex.uppercased()
        invalid = false
    }
    private func commit() {
        guard let normalized = StudioHexColor.parse(draft) else { invalid = true; return }
        invalid = false
        draft = "#" + normalized
        if hex != normalized { hex = normalized }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 7) {
                Text(title).font(.caption)
                Spacer(minLength: 4)
                ColorPicker(title, selection: Binding(
                    get: { Color(nsColor: NSColor(hex: hex)) },
                    set: { hex = NSColor($0).rgbHex }
                ), supportsOpacity: false)
                    .labelsHidden().fixedSize()
                TextField("#RRGGBB", text: $draft)
                    .font(.system(size: 11, design: .monospaced))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 90)
                    .focused($focused)
                    .onSubmit { commit() }
                    .onExitCommand { refreshDraft(); focused = false }
                    .onChange(of: draft) { _ in invalid = false }
                    .accessibilityLabel(title + " hex color")
                    .help("Enter a hex color such as #4F6B91")
            }
            if invalid { Text("Enter #RRGGBB or #RGB").font(.caption2).foregroundStyle(.red) }
        }
        .onAppear { refreshDraft() }
        .onChange(of: hex) { _ in refreshDraft() }
        .onChange(of: focused) { if !$0 { commit() } }
    }
}

struct CanvasTextPosition: Codable, Equatable {
    var x: Double
    var y: Double
    var isValid: Bool { x.isFinite && y.isFinite && abs(x) <= 100000 && abs(y) <= 100000 }
}

enum StudioCanvasAlignment: String, CaseIterable, Identifiable {
    case left = "Align left", center = "Align horizontal centers", right = "Align right"
    case top = "Align top", middle = "Align vertical centers", bottom = "Align bottom"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .left: return "align.horizontal.left"
        case .center: return "align.horizontal.center"
        case .right: return "align.horizontal.right"
        case .top: return "align.vertical.top"
        case .middle: return "align.vertical.center"
        case .bottom: return "align.vertical.bottom"
        }
    }
    func origin(for rect: CGRect, in canvas: CGSize) -> CGPoint {
        var result = rect.origin
        switch self {
        case .left: result.x = 0
        case .center: result.x = (canvas.width - rect.width) / 2
        case .right: result.x = canvas.width - rect.width
        case .top: result.y = 0
        case .middle: result.y = (canvas.height - rect.height) / 2
        case .bottom: result.y = canvas.height - rect.height
        }
        return result
    }
    func savedOrigin(for renderedRect: CGRect, in renderedCanvas: CGSize, scale: Double) -> CGPoint {
        let point = origin(for: renderedRect, in: renderedCanvas)
        return CGPoint(x: point.x / scale, y: point.y / scale)
    }
}

/// Lists are explicit text edits, so their markers survive every existing export
/// and inline editing path without a second, hidden representation of the text.
enum StudioListFormat: String, CaseIterable, Identifiable {
    case none = "No list", bullets = "Bullets", numbered = "Numbered list"
    var id: String { rawValue }
    var icon: String { switch self { case .none: return "text.alignleft"; case .bullets: return "list.bullet"; case .numbered: return "list.number" } }
    static let marker = try! NSRegularExpression(pattern: #"^(\s*)(?:[•◦▪]\s+|[0-9]+[.)]\s+)"#)
    func applying(to text: String) -> String {
        var number = 0
        return text.components(separatedBy: "\n").map { line in
            guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { number = 0; return line }
            let clean = Self.marker.stringByReplacingMatches(in: line, range: NSRange(line.startIndex..., in: line), withTemplate: "$1")
            let indentation = String(clean.prefix { $0 == " " || $0 == "\t" })
            let content = String(clean.dropFirst(indentation.count))
            number += 1
            switch self {
            case .none: return clean
            case .bullets: return indentation + "• " + content
            case .numbered: return indentation + "\(number). " + content
            }
        }.joined(separator: "\n")
    }
}

/// A compact field supports direct values, keyboard arrows, steppers and presets.
/// Values commit on Return/focus loss; stepping commits one deliberate increment.
struct StudioTypeNumber: View {
    let title: String
    let icon: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var unit = "px"
    var step = 1.0
    var presets: [Double] = []
    var autoAction: (() -> Void)? = nil
    @State private var draft = ""
    @FocusState private var focused: Bool
    private func formatted(_ number: Double) -> String { number.formatted(.number.precision(.fractionLength(0...2))) }
    private func commit() {
        let formatter = NumberFormatter(); formatter.numberStyle = .decimal
        if let parsed = formatter.number(from: draft)?.doubleValue, parsed.isFinite {
            let next = min(range.upperBound, max(range.lowerBound, parsed))
            if next != value { value = next }
            draft = formatted(next)
        } else { draft = formatted(value) }
    }
    private func increment(_ amount: Double) {
        if focused { commit() }
        value = min(range.upperBound, max(range.lowerBound, value + amount))
        draft = formatted(value)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 0)
                if let autoAction {
                    Button("Auto", action: autoAction)
                        .font(.caption2).buttonStyle(.borderless)
                        .help("Use automatic leading")
                        .accessibilityLabel("Use automatic leading")
                }
                if !presets.isEmpty {
                    Menu { ForEach(presets.filter { range.contains($0) }, id: \.self) { amount in
                        Button(formatted(amount) + " " + unit) { value = amount; draft = formatted(amount) }
                    } } label: { Image(systemName: "ellipsis").font(.caption2).frame(width: 18, height: 16) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .help(title + " presets").accessibilityLabel(title + " presets")
                }
            }
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 12)).frame(width: 16).foregroundStyle(.secondary).accessibilityHidden(true)
                TextField(title, text: $draft).textFieldStyle(.plain).focused($focused)
                    .monospacedDigit().onSubmit { commit() }
                    .onExitCommand { draft = formatted(value); focused = false }
                    .onMoveCommand { direction in
                        if direction == .up { increment(step) }
                        if direction == .down { increment(-step) }
                    }
                    .accessibilityLabel(title + " in " + unit)
                Text(unit).font(.caption2).foregroundStyle(.secondary)
                Stepper(title, onIncrement: { increment(step) }, onDecrement: { increment(-step) })
                    .labelsHidden().controlSize(.small).fixedSize()
            }.padding(.horizontal, 7).frame(height: 28)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(focused ? Color.accentColor : Color.primary.opacity(0.16), lineWidth: 1))
        }
        .onAppear { draft = formatted(value) }
        .onChange(of: value) { _ in draft = formatted(value) }
        .onChange(of: focused) { if !$0 { commit() } }
    }
}

struct StudioInspectorIcon: View {
    let title: String
    let icon: String
    var selected = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 14)).frame(maxWidth: .infinity).frame(height: 30)
                .foregroundStyle(selected ? Color.accentColor : Color.primary)
                .background(selected ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).help(title).accessibilityLabel(title).accessibilityValue(selected ? "Selected" : "")
    }
}

extension TypeBoardEditor {
    var selectedFace: Face? { library.allFaces.first { $0.name == style.fontName } }
    var characterPanel: some View {
        let selectedFace = self.selectedFace
        let familyFaces = selectedFace.map { selected in
            library.allFaces.filter { $0.originalFamily == selected.originalFamily }
        } ?? []
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Button { showFontPicker = true } label: {
                    HStack(spacing: 6) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Font family").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            Text(selectedFace?.originalFamily ?? style.fontName).font(.system(size: 13, weight: .medium)).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.down").font(.caption2).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 9).frame(height: 36)
                    .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 7))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .help("Choose font family")
                .accessibilityLabel("Font family: " + (selectedFace?.originalFamily ?? style.fontName))
                .popover(isPresented: $editorSession.showFontPicker) { fontPicker }
                ShelfPopup(
                    title: "Font style",
                    selection: Binding(get: { style.fontName }, set: { chooseFont($0) }),
                    options: familyFaces.isEmpty ? [("Unavailable", style.fontName)] : familyFaces.map { ($0.style, $0.name) }
                )
                .frame(width: 96, height: 24)
                .padding(.horizontal, 7).frame(height: 36)
                .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.primary.opacity(0.08)))
                .disabled(familyFaces.count < 2)
                .help("Choose a style from the current font family")
                .accessibilityLabel("Font style: " + (selectedFace?.style ?? style.fontName))
            }
            HStack(alignment: .top, spacing: 8) {
                StudioTypeNumber(title: "Size", icon: "textformat.size", value: styleBinding(\.size), range: direction.canvas == .imported ? 1...1000 : 8...160, unit: direction.canvasUnitLabel, presets: [8,10,12,14,16,18,24,30,36,48,60,72,96,120,144])
                StudioTypeNumber(
                    title: style.lineHeight == nil ? "Leading (auto)" : "Leading",
                    icon: "arrow.up.and.down.text.horizontal",
                    value: Binding(get: { style.lineHeight ?? style.size * style.leading }, set: { var s = style; s.lineHeight = $0; setStyle(s); save("Change Leading") }),
                    range: direction.canvas == .imported ? 1...2000 : 8...400,
                    unit: direction.canvasUnitLabel,
                    presets: [12,16,20,24,28,32,36,40,48,60,72,96],
                    autoAction: style.lineHeight == nil ? nil : { var s = style; s.lineHeight = nil; setStyle(s); save("Auto Leading") }
                )
            }
            DisclosureGroup("Character details") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Text(style.lineHeight == nil ? "Auto leading: \(Int(style.leading * 100))%" : "Custom leading")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Kerning").font(.caption).foregroundStyle(.secondary)
                            Picker("Kerning", selection: kerningBinding) { Text("Metrics").tag(true); Text("Off").tag(false) }
                                .labelsHidden().frame(maxWidth: .infinity, alignment: .leading).frame(height: 28)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        StudioTypeNumber(title: "Tracking", icon: "arrow.left.and.right.text.vertical", value: styleBinding(\.tracking), range: direction.canvas == .imported ? -100...100 : -3...12, unit: direction.canvasUnitLabel, step: 0.1, presets: [-3,-2,-1,0,0.5,1,2,3,4,6,8,12])
                    }
                    Text("Case & decoration").font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 5) {
                        StudioInspectorIcon(title: "Original case", icon: "textformat", selected: style.casing == nil || style.casing == .original) { var s = style; s.casing = .original; setStyle(s); save("Change Case") }
                        StudioInspectorIcon(title: "Uppercase", icon: "textformat.abc", selected: style.casing == .upper) { var s = style; s.casing = .upper; setStyle(s); save("Change Case") }
                        StudioInspectorIcon(title: "Lowercase", icon: "textformat.alt", selected: style.casing == .lower) { var s = style; s.casing = .lower; setStyle(s); save("Change Case") }
                        StudioInspectorIcon(title: "Underline", icon: "underline", selected: style.underline == true) { var s = style; s.underline = !(s.underline ?? false); setStyle(s); save("Toggle Underline") }
                        StudioInspectorIcon(title: "Strikethrough", icon: "strikethrough", selected: style.strikethrough == true) { var s = style; s.strikethrough = !(s.strikethrough ?? false); setStyle(s); save("Toggle Strikethrough") }
                    }
                }.padding(.top, 6)
            }
            .font(.system(size: 12, weight: .medium))
        }
    }
    var paragraphPanel: some View {
        DisclosureGroup("Paragraph") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Text alignment").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 5) {
                    ForEach(TextAlignmentOption.allCases, id: \.self) { alignment in
                        StudioInspectorIcon(title: alignment.rawValue + " align paragraphs", icon: alignment == .justified ? "text.justify" : "text.align" + alignment.rawValue.lowercased(), selected: (style.alignment ?? .left) == alignment) {
                            var s = style; s.alignment = alignment; setStyle(s); save("Align Paragraphs")
                        }
                    }
                }
                HStack(alignment: .top, spacing: 8) {
                    StudioTypeNumber(title: "Space after", icon: "paragraphsign", value: optionalStyleBinding(\.paragraphSpacing, default: 0), range: 0...200, unit: direction.canvasUnitLabel, presets: [0,4,8,12,16,24,32])
                    StudioTypeNumber(title: "First indent", icon: "increase.indent", value: optionalStyleBinding(\.indent, default: 0), range: 0...200, unit: direction.canvasUnitLabel, presets: [0,8,16,24,32,48])
                }
                StudioTypeNumber(title: "Additional word spacing", icon: "text.word.spacing", value: optionalStyleBinding(\.wordSpacing, default: 0), range: -3...40, unit: direction.canvasUnitLabel, step: 0.5)
                Divider()
                Text("Lists").font(.caption).foregroundStyle(.secondary)
                listPanel
            }.padding(.top, 6)
        }.font(.system(size: 12, weight: .medium))
    }
    var listPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                ForEach(StudioListFormat.allCases) { format in
                    StudioInspectorIcon(title: format.rawValue, icon: format.icon) {
                        let text = format.applying(to: style.text)
                        guard TypeDirection.acceptsCanvasText(text), text != style.text else { return }
                        var s = style; s.text = text; setStyle(s); save("Format List")
                    }
                }
            }
            Text("Applies to nonempty paragraphs. Markers remain editable text.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }
    var alignmentElement: CanvasElement? {
        let plan = CanvasPlanCache.plan(for: direction)
        if direction.canvas == .imported {
            let id = selectedSection ?? importedLayerIndex.flatMap { direction.importedLayout?.layers[$0].id }
            return plan.elements.first { $0.sectionID == id }
        }
        return selectedText
    }
    var canvasAlignmentPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Align to canvas").font(.system(size: 12, weight: .semibold))
            HStack(spacing: 4) {
                ForEach(StudioCanvasAlignment.allCases) { alignment in
                    StudioInspectorIcon(title: alignment.rawValue + " to canvas", icon: alignment.icon) { alignElement(alignment) }
                }
            }.disabled(alignmentElement == nil)
            Text(alignmentElement == nil ? "Select text on the canvas to align its frame." : "Moves the selected frame; paragraph alignment controls the text inside it.")
                .font(.caption2).foregroundStyle(.secondary)
            if direction.canvas != .imported, let id = selectedTextID, direction.textPositions?[id] != nil {
                Button("Reset frame position") { board.directions[directionIndex].textPositions?.removeValue(forKey: id); save("Reset Text Position") }.font(.caption)
            }
        }
    }
    func alignElement(_ alignment: StudioCanvasAlignment) {
        guard let element = alignmentElement else { return }
        let plan = CanvasPlanCache.plan(for: direction)
        // The plan is uniformly scaled for presentation and export. Saved layer
        // positions remain in the original canvas coordinate system.
        let scale = direction.canvasScale ?? 1
        let size = direction.canvas == .imported
            ? CGSize(width: direction.width * scale, height: (direction.importedLayout?.height ?? plan.size.height / scale) * scale)
            : plan.size
        let origin = alignment.savedOrigin(for: element.rect, in: size, scale: scale)
        if direction.canvas == .imported {
            guard let index = direction.importedLayout?.layers.firstIndex(where: { $0.id == element.sectionID }) else { return }
            board.directions[directionIndex].importedLayout?.layers[index].x = origin.x
            board.directions[directionIndex].importedLayout?.layers[index].y = origin.y
        } else if let id = element.textID {
            var positions = direction.textPositions ?? [:]
            positions[id] = CanvasTextPosition(x: origin.x, y: origin.y)
            board.directions[directionIndex].textPositions = positions
        } else { return }
        save(alignment.rawValue)
    }
}
