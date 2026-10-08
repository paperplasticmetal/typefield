import SwiftUI
import AppKit

/// The tool rail chooses one panel; object controls never repeat in the canvas strip.
extension TypeBoardEditor {
    var inspector: some View {
        VStack(spacing: 0) {
            HStack {
                Text(inspectorTab == "Arrangement" ? "Layers" : inspectorTab).font(.subheadline.weight(.semibold))
                Spacer()
                if inspectorTab == "Properties" {
                    Menu { selectionMenu } label: { Image(systemName: "ellipsis") }
                        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                        .accessibilityLabel("Selection actions")
                }
            }.padding(.horizontal, 14).frame(height: 42)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if inspectorTab == "Properties" { objectInspector }
                    else if inspectorTab == "Arrangement" { layoutSections }
                    else if inspectorTab == "Canvas" { canvasInspector }
                    else {
                        if selectedObjects.count > 1 || importedNonTextSelected || selectedArtworkIndex != nil {
                            Text("Select a text box to edit its typography.").font(.callout).foregroundStyle(.secondary)
                            Button("Object properties") { inspectorTab = "Properties" }.buttonStyle(.borderless)
                        } else {
                            typographyInspector
                            if !selectedObjects.isEmpty { Divider(); effectsInspector }
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(14)
            }
        }.background(Color(nsColor: .controlBackgroundColor))
        .accessibilityIdentifier("spaces-context-inspector")
    }
    var selectionMenu: some View {
        Group {
            objectActions
            Divider()
            Button("Select all") { objectCommand("selectAll") }
            Button("Deselect") { selectObjects([]) }
            Divider()
            Button("Group selection (⌘G)") { groupObjects() }.frame(width: 32).disabled(selectedObjects.count < 2)
            Button("Ungroup (⇧⌘G)") { ungroupObjects() }.disabled(!(direction.objectGroups ?? []).contains { !$0.members.isDisjoint(with: selectedObjects) })
            Button("Reset transforms") {
                for id in selectedObjects { board.directions[directionIndex].objectTransforms?.removeValue(forKey: id) }
                save("Reset Content Transforms")
            }.disabled(selectedObjects.isEmpty)
        }
    }
    var objectInspector: some View {
        VStack(alignment: .leading, spacing: 14) {
            if selectedObjects.isEmpty {
                Label("Select an object", systemImage: "cursorarrow").font(.callout.weight(.medium))
                Text("Click text or a shape to inspect it. Use Marquee to select several objects.").font(.caption).foregroundStyle(.secondary)
            } else {
                HStack {
                    Text(selectedObjects.count == 1 ? (selectedImportedShape?.name ?? selectedArtwork?.name ?? (selectedTextID == nil ? "Object" : "Text box")) : "\(selectedObjects.count) objects")
                        .font(.caption.weight(.medium)).lineLimit(1)
                    Spacer()
                    StudioInspectorIcon(title: "Group selection (⌘G)", icon: "square.3.layers.3d") { groupObjects() }.disabled(selectedObjects.count < 2)
                    StudioInspectorIcon(title: "Ungroup (⇧⌘G)", icon: "square.3.layers.3d.slash") { ungroupObjects() }.frame(width: 32)
                        .disabled(!(direction.objectGroups ?? []).contains { !$0.members.isDisjoint(with: selectedObjects) })
                }
                canvasAlignmentPanel
                symmetryControls
                if selectedImportedShape != nil { Divider(); selectedShapeAppearance }
                if selectedArtworkIndex != nil { Divider(); selectedArtworkAppearance }
                if selectedObjects.count == 1 && CanvasPlanCache.plan(for: direction).elements.contains(where: { selectedObjects.contains($0.objectID) && $0.text != nil }) {
                    Button { inspectorTab = "Typography" } label: { Label("Typography", systemImage: "textformat") }.buttonStyle(.borderless)
                }
                Divider()
                effectsInspector
            }
        }
    }
    var canvasInspector: some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField("Canvas name", text: Binding(get: { board.canvasName(direction) }, set: { board.directions[directionIndex].name = $0; save() })).textFieldStyle(.roundedBorder)
            let size = CanvasPlanCache.plan(for: direction).artboardSize
            Text("\(Int(size.width)) × \(Int(size.height)) \(direction.canvasUnitLabel)").font(.caption).monospacedDigit().foregroundStyle(.secondary)
            colorPicker("Background", key: \.paper)
            if direction.canvas != .imported { colorPicker("Accent", key: \.accent) }
            Divider()
            Text("Notes").font(.caption.weight(.medium))
            TextEditor(text: directionBinding(\.notes)).frame(height: 100)
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.secondary.opacity(0.2)))
            if let warnings = direction.importWarnings, !warnings.isEmpty {
                DisclosureGroup("Import notes (\(warnings.count))") {
                    Text(warnings.joined(separator: "\n")).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }.font(.caption)
            }
        }
    }
    var selectedEffects: [CanvasObjectEffects] {
        CanvasPlanCache.plan(for: direction).elements.filter { selectedObjects.contains($0.objectID) }.map(\.effects)
    }
    func updateEffects<T>(_ key: WritableKeyPath<CanvasObjectEffects, T>, value: T, ids: Set<String>, canvasID: UUID) {
        guard !library.studio.readBlocked, let index = board.directions.firstIndex(where: { $0.id == canvasID }) else { return }
        let source = board.directions[index]
        let updated = CanvasObjectEffects.applying(to: source, ids: ids, key: key, displayedValue: value)
        guard updated != source else { return }
        board.directions[index] = updated
        save("Change Object Effects")
    }
    func effectBinding<T: Equatable>(_ key: WritableKeyPath<CanvasObjectEffects, T>) -> Binding<T> {
        let ids = selectedObjects, canvasID = direction.id
        let initial = (selectedEffects.first ?? CanvasObjectEffects())[keyPath: key]
        return Binding(get: { initial }, set: { value in
            // Native controls can emit their initial value when gaining focus.
            guard value != initial else { return }
            updateEffects(key, value: value, ids: ids, canvasID: canvasID)
        })
    }
    var effectsInspector: some View {
        let ids = selectedObjects, canvasID = direction.id
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Effects").font(.caption.weight(.semibold))
                Spacer()
                if let first = selectedEffects.first, selectedEffects.contains(where: { $0 != first }) {
                    Text("Mixed").font(.caption2).foregroundStyle(.secondary).help("Controls show the first object. Changing a value applies that value to each selected object.")
                }
                Button {
                    guard let index = board.directions.firstIndex(where: { $0.id == canvasID }), !library.studio.readBlocked else { return }
                    var overrides = board.directions[index].objectEffects ?? [:]
                    for id in ids { overrides[id] = CanvasObjectEffects() }
                    board.directions[index].objectEffects = overrides; save("Reset Object Effects")
                } label: { Image(systemName: "arrow.counterclockwise") }
                .buttonStyle(.borderless).help("Reset effects on the selection").accessibilityLabel("Reset object effects")
            }
            effectNumber("Blur", key: \.blurRadius, range: 0...40)
            Divider()
            Toggle("Shadow", isOn: effectBinding(\.shadowEnabled)).toggleStyle(.switch).controlSize(.mini).font(.caption)
            if selectedEffects.contains(where: \.shadowEnabled) {
                StudioHexColorPicker(title: "Color", hex: effectBinding(\.shadowColor))
                effectNumber("Opacity", key: \.shadowOpacity, range: 0...1, multiplier: 100, unit: "%")
                effectNumber("Softness", key: \.shadowRadius, range: 0...40)
                HStack(spacing: 10) {
                    effectOffset("X", key: \.shadowX)
                    effectOffset("Y", key: \.shadowY)
                }
            }
        }.disabled(selectedObjects.isEmpty || library.studio.readBlocked)
        .id(canvasID.uuidString + ids.sorted().joined(separator: "|"))
        .accessibilityIdentifier("spaces-object-effects")
    }
    func effectNumber(_ title: String, key: WritableKeyPath<CanvasObjectEffects, Double>, range: ClosedRange<Double>, multiplier: Double = 1, unit: String = "px") -> some View {
        let binding = effectBinding(key)
        let ids = selectedObjects, canvasID = direction.id
        let values = selectedEffects.map { $0[keyPath: key] * multiplier }
        let mixed = values.dropFirst().contains { $0 != values.first }
        let value = Binding<Double>(get: { binding.wrappedValue * multiplier }, set: { input in
            guard input.isFinite else { return }
            binding.wrappedValue = min(range.upperBound, max(range.lowerBound, input / multiplier))
        })
        return HStack(spacing: 7) {
            Text(title).frame(width: 50, alignment: .leading)
            Slider(value: value, in: (range.lowerBound * multiplier)...(range.upperBound * multiplier), onEditingChanged: { editing in if !editing { library.studio.endUndoCoalescing() } }).labelsHidden().accessibilityLabel(title)
            StudioEffectNumberField(title: title + " value", value: mixed ? nil : values.first) { input in
                updateEffects(key, value: min(range.upperBound, max(range.lowerBound, input / multiplier)), ids: ids, canvasID: canvasID)
            }.frame(width: 52)
            Text(unit).foregroundStyle(.secondary).frame(width: 15, alignment: .leading)
        }.font(.caption)
    }
    func effectOffset(_ title: String, key: WritableKeyPath<CanvasObjectEffects, Double>) -> some View {
        let ids = selectedObjects, canvasID = direction.id
        let values = selectedEffects.map { $0[keyPath: key] }
        let mixed = values.dropFirst().contains { $0 != values.first }
        return HStack(spacing: 5) {
            Text(title).foregroundStyle(.secondary)
            StudioEffectNumberField(title: "Shadow " + title + " offset", value: mixed ? nil : values.first) { input in
                updateEffects(key, value: min(200, max(-200, input)), ids: ids, canvasID: canvasID)
            }
        }.font(.caption)
    }
}

/// A mixed value is blank until deliberately edited. Focusing or dismissing
/// this field cannot homogenize a group's effects, unlike a live value binding.
struct StudioEffectNumberField: View {
    let title: String
    let value: Double?
    let onCommit: (Double) -> Void
    @State private var draft = ""
    @State private var baseline = ""
    @FocusState private var focused: Bool
    private func refresh() {
        draft = value.map { $0.formatted(.number.grouping(.never).precision(.fractionLength(0...1))) } ?? ""
        baseline = draft
    }
    private func commit() {
        guard draft != baseline else { return }
        let formatter = NumberFormatter(); formatter.numberStyle = .decimal
        guard let number = formatter.number(from: draft), number.doubleValue.isFinite else { refresh(); return }
        baseline = draft
        onCommit(number.doubleValue)
    }
    var body: some View {
        TextField(value == nil ? "Mixed" : title, text: $draft)
            .textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing).focused($focused)
            .accessibilityLabel(title).onSubmit { commit() }
            .onAppear { refresh() }
            .onChange(of: value) { _ in if !focused { refresh() } }
            .onChange(of: focused) { if !$0 { commit() } }
            .onExitCommand { refresh(); focused = false }
    }
}
