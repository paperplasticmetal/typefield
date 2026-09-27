import SwiftUI

struct FontLabDesignView: View {
    let original: FontLabProject
    let character: String
    let onApply: (FontLabProject, String?) -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var project: FontLabProject
    @State private var tab = "Masters"
    @State private var masterName = "Bold"
    @State private var masterWeight = 700.0
    @State private var source = "A"
    @State private var groupName = ""
    @State private var groupMembers = ""
    @State private var groupSide = FontLabKerningSide.left
    @State private var left = "A"
    @State private var right = "V"
    @State private var kern = -40.0
    @State private var newCharacters = ""
    @State private var message = ""
    init(project: FontLabProject, character: String, onApply: @escaping (FontLabProject, String?) -> Bool) {
        original = project; self.character = character; self.onApply = onApply
        _project = State(initialValue: project)
        _left = State(initialValue: character)
        _right = State(initialValue: project.glyphs["V"] != nil ? "V" : character)
        _source = State(initialValue: project.characters.first { $0 != character && project.glyphs[$0]?.hasArtwork == true } ?? character)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Text("Font design · " + project.name).font(.title2.bold()); Spacer(); Text("Editing " + character).foregroundStyle(.secondary) }
            Picker("Font design", selection: $tab) { ForEach(["Masters", "Components", "Kerning", "Glyph set"], id: \.self) { Text($0) } }.pickerStyle(.segmented).labelsHidden()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if tab == "Masters" { masterControls }
                    if tab == "Components" { componentControls }
                    if tab == "Kerning" { kerningControls }
                    if tab == "Glyph set" { glyphControls }
                }.padding(4).frame(maxWidth: .infinity, alignment: .leading)
            }.frame(maxHeight: .infinity)
            if !message.isEmpty { Text(message).font(.caption).foregroundStyle(.orange) }
            if !project.isValid { Text("Some settings are invalid. Check names, component bounds, group membership and references before applying.").font(.caption).foregroundStyle(.orange) }
            HStack {
                Text("Changes apply together. Cancel keeps the current project.").font(.caption).foregroundStyle(.secondary)
                Spacer(); Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Apply") { apply() }.keyboardShortcut(.defaultAction).disabled(!project.isValid || project == original)
            }
        }.padding(24).frame(width: 800, height: 650)
    }
    private func apply(open character: String? = nil) {
        project.captureActiveMaster()
        if onApply(project, character) { dismiss() }
    }
    private func change(_ action: (inout FontLabProject) -> Void) {
        var candidate = project; action(&candidate)
        guard candidate.isValid else { message = "That change would create an invalid reference, duplicate group membership or an outline outside the design box."; return }
        project = candidate; message = ""
    }
    private var masterControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Keep separate designs for Regular, Bold or other styles. Switching preserves the current outlines, components, metrics and kerning.").foregroundStyle(.secondary)
            Text("Each master exports as a separate static font. Automatic interpolation and variable-font export are not available yet.").font(.caption).foregroundStyle(.secondary)
            if project.masters?.isEmpty != false { Text("Current design · Regular").font(.headline) }
            ForEach(project.masters ?? []) { master in
                HStack {
                    Image(systemName: master.id == project.activeMasterID ? "checkmark.circle.fill" : "circle").foregroundStyle(master.id == project.activeMasterID ? Color.accentColor : .secondary)
                    TextField("Master name", text: Binding(get: { project.masters?.first { $0.id == master.id }?.name ?? "" }, set: { name in
                        if let i = project.masters?.firstIndex(where: { $0.id == master.id }) { project.masters?[i].name = String(name.prefix(80)) }
                    })).textFieldStyle(.roundedBorder)
                    Text("Weight")
                    TextField("400", value: masterWeightBinding(master.id), format: .number.precision(.fractionLength(0)))
                        .textFieldStyle(.roundedBorder).frame(width: 64).help("OpenType weight class from 1 to 1000").accessibilityLabel("Weight class")
                    Text("\(master.id == project.activeMasterID ? project.completedCount : master.glyphs.values.filter(\.hasArtwork).count) drawn").font(.caption).foregroundStyle(.secondary).frame(width: 80)
                    Button(master.id == project.activeMasterID ? "Active" : "Switch") { change { $0.switchMaster(master.id) } }.disabled(master.id == project.activeMasterID)
                }
            }
            Divider()
            HStack {
                TextField("New master name", text: $masterName).textFieldStyle(.roundedBorder)
                Text("Weight")
                TextField("700", value: $masterWeight, format: .number.precision(.fractionLength(0)))
                    .textFieldStyle(.roundedBorder).frame(width: 64).help("OpenType weight class from 1 to 1000")
                Button("Duplicate current as master") {
                    let name = masterName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty else { return }
                    change { $0.addMaster(name: String(name.prefix(80)), weight: min(1000, max(1, masterWeight.rounded()))) }
                }.disabled((project.masters?.count ?? 0) >= 16 || masterName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            preview(project.previewText)
        }
    }
    private func masterWeightBinding(_ id: UUID) -> Binding<Double> {
        Binding(get: { project.masters?.first { $0.id == id }?.weight ?? 400 }, set: { value in
            guard value.isFinite, let index = project.masters?.firstIndex(where: { $0.id == id }) else { return }
            project.masters?[index].weight = min(1000, max(1, value.rounded()))
        })
    }
    private var componentControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Reuse another glyph as a linked component in \(character). Editing the source updates every use in this master. Teal outlines on the canvas are linked components.").foregroundStyle(.secondary)
            HStack {
                Picker("Source glyph", selection: $source) { ForEach(project.characters.filter { $0 != character && project.glyphs[$0]?.hasArtwork == true }, id: \.self) { Text($0).tag($0) } }.frame(maxWidth: 220)
                Button("Insert component") {
                    guard source != character, let base = project.glyphs[source], let target = project.glyphs[character] else { return }
                    let scale = min(1, target.resolvedDesignWidth / base.resolvedDesignWidth)
                    let use = FontLabComponentUse(source: source, y: project.metrics.baseline * (1-scale), scale: scale)
                    change { $0.glyphs[character]?.components = (target.components ?? []) + [use] }
                }.disabled(source == character || project.glyphs[source]?.hasArtwork != true)
                Spacer()
            }
            ForEach(project.glyphs[character]?.components ?? []) { use in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Source " + use.source).font(.headline)
                        Button("Open source") { apply(open: use.source) }.disabled(!project.isValid)
                        Spacer()
                        Button("Decompose") {
                            change { p in
                                guard var glyph = p.glyphs[character] else { return }
                                var isolated = glyph; isolated.strokes = []; isolated.components = [use]
                                var dictionary = p.glyphs; dictionary[character] = isolated
                                guard let resolved = FontLabDesign.resolved(character, in: dictionary) else { return }
                                glyph.strokes += FontLabDesign.detachedStrokes(resolved.strokes); glyph.components?.removeAll { $0.id == use.id }; p.glyphs[character] = glyph
                            }
                        }.help("Replace this reference with editable outlines")
                        Button("Remove") { change { $0.glyphs[character]?.components?.removeAll { $0.id == use.id } } }
                    }
                    HStack(spacing: 12) {
                        StudioTypeNumber(title: "X offset", icon: "arrow.left.and.right", value: componentBinding(use.id, \.x, multiplier: 1000), range: -2000...2000, unit: "units")
                        StudioTypeNumber(title: "Y offset", icon: "arrow.up.and.down", value: componentBinding(use.id, \.y, multiplier: 1000), range: -2000...2000, unit: "units")
                        StudioTypeNumber(title: "Scale", icon: "arrow.up.left.and.arrow.down.right", value: componentBinding(use.id, \.scale, multiplier: 100), range: 5...400, unit: "%")
                    }
                }.padding(12).background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 9))
            }
            preview(character)
            Text("Components stay linked until decomposed. Cycles, excessive nesting and out-of-bounds geometry are rejected.").font(.caption).foregroundStyle(.secondary)
        }
    }
    private func componentBinding(_ id: UUID, _ key: WritableKeyPath<FontLabComponentUse, Double>, multiplier: Double) -> Binding<Double> {
        Binding(get: { (project.glyphs[character]?.components?.first { $0.id == id }?[keyPath: key] ?? 0) * multiplier }, set: { value in
            change { p in if let i = p.glyphs[character]?.components?.firstIndex(where: { $0.id == id }) { p.glyphs[character]?.components?[i][keyPath: key] = value / multiplier } }
        })
    }
    private func endpointName(_ endpoint: String) -> String { project.kerningGroups?.first { "@" + $0.id.uuidString == endpoint }.map { "Group: " + $0.name } ?? endpoint }
    private func endpointPicker(_ title: String, side: FontLabKerningSide, selection: Binding<String>) -> some View {
        Picker(title, selection: selection) {
            ForEach(project.characters, id: \.self) { Text($0).tag($0) }
            ForEach((project.kerningGroups ?? []).filter { $0.side == side }) { Text("Group: " + $0.name).tag("@" + $0.id.uuidString) }
        }
    }
    private var kerningControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Kerning pairs").font(.headline)
            Text("Negative values bring letters closer. Glyph exceptions override group rules. Values use a 1,000-unit em and are included in preview and TrueType export.").font(.caption).foregroundStyle(.secondary)
            HStack {
                endpointPicker("First", side: .left, selection: $left)
                endpointPicker("Second", side: .right, selection: $right)
                StudioTypeNumber(title: "Adjustment", icon: "arrow.left.and.right", value: $kern, range: -500...500, unit: "units").frame(width: 160)
                Button("Set pair") { change { p in
                    var pairs = p.kerningPairs ?? []; pairs.removeAll { $0.left == left && $0.right == right }
                    pairs.append(FontLabKerningPair(left: left, right: right, value: kern.rounded())); p.kerningPairs = pairs
                } }
            }
            preview(pairPreview)
            ForEach(project.kerningPairs ?? []) { pair in
                HStack {
                    Text(endpointName(pair.left) + "  /  " + endpointName(pair.right)); Spacer(); Text("\(Int(pair.value)) units").monospacedDigit()
                    Button("Edit") { left = pair.left; right = pair.right; kern = pair.value }
                    Button("Remove") { change { $0.kerningPairs?.removeAll { $0.id == pair.id } } }
                }.font(.caption)
            }
            Divider(); Text("Kerning groups").font(.headline)
            Text("A glyph can belong to one group on each side of a pair. Assign similar shapes to share a spacing rule.").font(.caption).foregroundStyle(.secondary)
            HStack {
                TextField("Group name", text: $groupName).textFieldStyle(.roundedBorder)
                Picker("Side", selection: $groupSide) { ForEach(FontLabKerningSide.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                TextField("Members, e.g. AVW", text: $groupMembers).textFieldStyle(.roundedBorder)
                Button("Add group") {
                    let members = Array(Set(groupMembers.filter { !$0.isWhitespace }.map(String.init))).sorted()
                    change { $0.kerningGroups = ($0.kerningGroups ?? []) + [FontLabKerningGroup(name: groupName, members: members, side: groupSide)] }
                }.disabled(groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || groupMembers.isEmpty)
            }
            ForEach(project.kerningGroups ?? []) { group in
                HStack {
                    Text(group.name).fontWeight(.medium); Text(group.side.rawValue + ": " + group.members.joined()).foregroundStyle(.secondary); Spacer()
                    Button("Remove") { change { p in
                        p.kerningGroups?.removeAll { $0.id == group.id }
                        let endpoint = "@" + group.id.uuidString; p.kerningPairs?.removeAll { $0.left == endpoint || $0.right == endpoint }
                    } }
                }.font(.caption)
            }
        }
    }
    private var pairPreview: String {
        func sample(_ endpoint: String) -> String { project.kerningGroups?.first { "@" + $0.id.uuidString == endpoint }?.members.first ?? endpoint }
        return String(repeating: sample(left) + sample(right) + " ", count: 4)
    }
    private var glyphControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add characters").font(.headline)
            Text("Add accented letters, marks or symbols to the project. Existing drawings are preserved; new characters start empty in every master.").foregroundStyle(.secondary)
            TextField("Characters, e.g. éàöñç", text: $newCharacters).textFieldStyle(.roundedBorder)
            Button("Add to glyph set") {
                let additions = newCharacters.map(String.init).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                change { p in
                    for c in additions where !p.characters.contains(c) {
                        p.characters.append(c); p.glyphs[c] = FontLabGlyph(character: c)
                        if p.masters != nil { for i in p.masters!.indices { p.masters?[i].glyphs[c] = FontLabGlyph(character: c) } }
                    }
                }
                newCharacters = ""
            }.disabled(newCharacters.isEmpty)
            Text("\(project.characters.count) characters").font(.caption).foregroundStyle(.secondary)
        }
    }
    private func preview(_ text: String) -> some View {
        FontLabPreviewCanvas(text: text, glyphs: project.outputProject.glyphs, metrics: project.metrics, kerningGroups: project.kerningGroups ?? [], kerningPairs: project.kerningPairs ?? [])
            .frame(height: 150).background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10)).clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct FontLabSmoothingView: View {
    let original: FontLabGlyph
    let metrics: FontLabMetrics
    let onApply: (FontLabGlyph) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var tolerance = 5.0
    @State private var candidate: FontLabGlyph?
    @State private var message = ""
    @State private var working = false
    @State private var revision = UUID()
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Simplify outline · " + original.character).font(.title2.bold())
            Text("Fit editable curves while keeping corners and counters. The original stays unchanged until you apply the preview.").foregroundStyle(.secondary)
            HStack {
                Picker("Fit tolerance", selection: $tolerance) { Text("Gentle · 0.5 units").tag(0.5); Text("Balanced · 1 unit").tag(1.0); Text("Loose · 2 units").tag(2.0); Text("Editable · 5 units").tag(5.0) }.disabled(working)
                Button("Preview") { generate() }.disabled(working)
                if working { ProgressView().controlSize(.small) }
            }
            HStack {
                sample("Original", glyph: original)
                sample("Smoothed", glyph: candidate ?? original)
            }
            Text(message).font(.caption).foregroundStyle(.secondary).frame(minHeight: 36)
            HStack { Spacer(); Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction); Button("Apply simplified outline") { if let candidate { onApply(candidate); dismiss() } }.keyboardShortcut(.defaultAction).disabled(candidate == nil || working) }
        }.padding(24).frame(width: 700)
        .onAppear { generate() }.onChange(of: tolerance) { _ in candidate = nil; generate() }
        .onDisappear { revision = UUID() }
    }
    private func sample(_ title: String, glyph: FontLabGlyph) -> some View {
        VStack { Text(title).font(.headline); FontLabPreviewCanvas(text: glyph.character, glyphs: [glyph.character:glyph], metrics: metrics, maximumEm: 220, centered: true).frame(height: 220).background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10)); Text("\(FontLabVectorMath.paths(in: glyph).reduce(0) { $0 + $1.nodes.count }) nodes").font(.caption) }.frame(maxWidth: .infinity)
    }
    private func generate() {
        let id = UUID(); revision = id; working = true; candidate = nil
        let source = original, units = tolerance
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try FontLabTraceSmoothing.fit(source, units: units, refitDenseCurves: true) }
            DispatchQueue.main.async {
                guard revision == id else { return }; working = false
                switch result {
                case .success(let glyph): candidate = glyph; message = "Review the curves before applying. Undo edit restores the original outline."
                case .failure(let error): message = error.localizedDescription
                }
            }
        }
    }
}
