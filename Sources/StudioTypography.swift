import SwiftUI
import AppKit

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
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 13)).frame(width: 19).foregroundStyle(.secondary).accessibilityHidden(true)
                TextField(title, text: $draft).textFieldStyle(.plain).focused($focused)
                    .monospacedDigit().onSubmit { commit() }
                    .onExitCommand { draft = formatted(value); focused = false }
                    .onMoveCommand { direction in
                        if direction == .up { increment(step) }
                        if direction == .down { increment(-step) }
                    }
                    .accessibilityLabel(title + " in " + unit)
                Text(unit).font(.caption2).foregroundStyle(.secondary)
                Stepper(title, onIncrement: { increment(step) }, onDecrement: { increment(-step) }).labelsHidden().fixedSize()
                if !presets.isEmpty {
                    Menu { ForEach(presets.filter { range.contains($0) }, id: \.self) { amount in
                        Button(formatted(amount) + " " + unit) { value = amount; draft = formatted(amount) }
                    } } label: { Image(systemName: "chevron.down").font(.caption2) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help(title + " presets").accessibilityLabel(title + " presets")
                }
            }.padding(.horizontal, 7).frame(height: 32)
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
            Image(systemName: icon).font(.system(size: 16)).frame(maxWidth: .infinity).frame(height: 32)
                .foregroundStyle(selected ? Color.accentColor : Color.primary)
                .background(selected ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).help(title).accessibilityLabel(title).accessibilityValue(selected ? "Selected" : "")
    }
}

extension TypeBoardEditor {
    var selectedFace: Face? { library.allFaces.first { $0.name == style.fontName } }
    var familyFaces: [Face] { guard let family = selectedFace?.originalFamily else { return [] }; return library.allFaces.filter { $0.originalFamily == family } }
    func panelHeading(_ title: String) -> some View { Text(title).font(.system(size: 13, weight: .semibold)).frame(maxWidth: .infinity, alignment: .leading) }
    var characterPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            panelHeading("Character")
            Button { showFontPicker = true } label: {
                HStack { Text(selectedFace?.originalFamily ?? style.fontName).lineLimit(1); Spacer(); Image(systemName: "chevron.down") }
                    .padding(9).background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 6)).contentShape(Rectangle())
            }.buttonStyle(.plain).help("Choose font family").accessibilityLabel("Font family: " + (selectedFace?.originalFamily ?? style.fontName))
                .popover(isPresented: $showFontPicker) { fontPicker }
            ShelfDropdown(title: "Style", selection: Binding(get: { style.fontName }, set: { chooseFont($0) }), options: familyFaces.isEmpty ? [(style.fontName, style.fontName)] : familyFaces.map { ($0.style, $0.name) }, showsTitle: false)
                .help("Choose a style from the current font family")
            HStack(alignment: .top, spacing: 10) {
                StudioTypeNumber(title: "Size", icon: "textformat.size", value: styleBinding(\.size), range: direction.canvas == .imported ? 1...1000 : 8...160, unit: direction.canvasUnitLabel, presets: [8,10,12,14,16,18,24,30,36,48,60,72,96,120,144])
                StudioTypeNumber(title: "Leading", icon: "arrow.up.and.down.text.horizontal", value: Binding(get: { style.lineHeight ?? style.size * style.leading }, set: { var s = style; s.lineHeight = $0; setStyle(s); save("Change Leading") }), range: direction.canvas == .imported ? 1...2000 : 8...400, unit: direction.canvasUnitLabel, presets: [12,16,20,24,28,32,36,40,48,60,72,96])
            }
            HStack {
                Text(style.lineHeight == nil ? "Auto leading · \(Int(style.leading * 100))%" : "Custom leading").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Button("Auto") { var s = style; s.lineHeight = nil; setStyle(s); save("Auto Leading") }.font(.caption).buttonStyle(.borderless).help("Follow font size at the saved leading ratio")
            }
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Kerning").font(.caption).foregroundStyle(.secondary)
                    Picker("Kerning", selection: kerningBinding) { Text("Metrics").tag(true); Text("Off").tag(false) }.labelsHidden().frame(height: 32)
                }.frame(maxWidth: .infinity)
                StudioTypeNumber(title: "Tracking", icon: "arrow.left.and.right.text.vertical", value: styleBinding(\.tracking), range: direction.canvas == .imported ? -100...100 : -3...12, unit: direction.canvasUnitLabel, step: 0.1, presets: [-3,-2,-1,0,0.5,1,2,3,4,6,8,12])
            }
            HStack(spacing: 5) {
                StudioInspectorIcon(title: "Original case", icon: "textformat", selected: style.casing == nil || style.casing == .original) { var s = style; s.casing = .original; setStyle(s); save("Change Case") }
                StudioInspectorIcon(title: "Uppercase", icon: "textformat.abc", selected: style.casing == .upper) { var s = style; s.casing = .upper; setStyle(s); save("Change Case") }
                StudioInspectorIcon(title: "Lowercase", icon: "textformat.alt", selected: style.casing == .lower) { var s = style; s.casing = .lower; setStyle(s); save("Change Case") }
                StudioInspectorIcon(title: "Underline", icon: "underline", selected: style.underline == true) { var s = style; s.underline = !(s.underline ?? false); setStyle(s); save("Toggle Underline") }
                StudioInspectorIcon(title: "Strikethrough", icon: "strikethrough", selected: style.strikethrough == true) { var s = style; s.strikethrough = !(s.strikethrough ?? false); setStyle(s); save("Toggle Strikethrough") }
            }
        }
    }
    var paragraphPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider(); panelHeading("Paragraph")
            HStack(spacing: 5) {
                ForEach(TextAlignmentOption.allCases, id: \.self) { alignment in
                    StudioInspectorIcon(title: alignment.rawValue + " align paragraphs", icon: alignment == .justified ? "text.justify" : "text.align" + alignment.rawValue.lowercased(), selected: (style.alignment ?? .left) == alignment) {
                        var s = style; s.alignment = alignment; setStyle(s); save("Align Paragraphs")
                    }
                }
            }
            HStack(alignment: .top, spacing: 10) {
                StudioTypeNumber(title: "Space after", icon: "paragraphsign", value: optionalStyleBinding(\.paragraphSpacing, default: 0), range: 0...200, unit: direction.canvasUnitLabel, presets: [0,4,8,12,16,24,32])
                StudioTypeNumber(title: "First indent", icon: "increase.indent", value: optionalStyleBinding(\.indent, default: 0), range: 0...200, unit: direction.canvasUnitLabel, presets: [0,8,16,24,32,48])
            }
            DisclosureGroup("Word spacing") {
                StudioTypeNumber(title: "Additional word spacing", icon: "text.word.spacing", value: optionalStyleBinding(\.wordSpacing, default: 0), range: -3...40, unit: direction.canvasUnitLabel, step: 0.5).padding(.top, 6)
            }.font(.caption)
        }
    }
    var listPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider(); panelHeading("Bullets and numbering")
            HStack(spacing: 5) {
                ForEach(StudioListFormat.allCases) { format in
                    StudioInspectorIcon(title: format.rawValue, icon: format.icon) {
                        let text = format.applying(to: style.text)
                        guard TypeDirection.acceptsCanvasText(text), text != style.text else { return }
                        var s = style; s.text = text; setStyle(s); save("Format List")
                    }
                }
            }
            Text("Apply to each nonempty paragraph. Markers remain editable text.").font(.caption2).foregroundStyle(.secondary)
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
        VStack(alignment: .leading, spacing: 10) {
            HStack { panelHeading("Align"); Text("To canvas").font(.caption).foregroundStyle(.secondary).fixedSize() }
            HStack(spacing: 4) {
                ForEach(StudioCanvasAlignment.allCases) { alignment in
                    StudioInspectorIcon(title: alignment.rawValue + " to canvas", icon: alignment.icon) { alignElement(alignment) }
                }
            }.disabled(alignmentElement == nil)
            Text(alignmentElement == nil ? "Select text on the canvas to align its frame." : "Moves the selected frame; paragraph alignment controls the text inside it.").font(.caption2).foregroundStyle(.secondary)
            if direction.canvas != .imported, let id = selectedTextID, direction.textPositions?[id] != nil {
                Button("Reset frame position") { board.directions[directionIndex].textPositions?.removeValue(forKey: id); save("Reset Text Position") }.font(.caption)
            }
        }
    }
    func alignElement(_ alignment: StudioCanvasAlignment) {
        guard let element = alignmentElement else { return }
        let plan = CanvasPlanCache.plan(for: direction)
        // Imported canvases may expand their preview around off-canvas objects;
        // alignment always targets the saved artboard, not that expanded preview.
        let size = direction.canvas == .imported ? CGSize(width: direction.width, height: direction.importedLayout?.height ?? plan.size.height) : plan.size
        let origin = alignment.origin(for: element.rect, in: size)
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
