import SwiftUI
import AppKit

/// A deliberately local generator UI. It exposes the real vector operations
/// performed by FontLabRemixEngine instead of presenting them as cloud AI.
struct FontLabRemixSheet: View {
    @Environment(\.dismiss) private var dismiss

    let faces: [Face]
    let onCreate: (FontLabRemixResult) -> Bool

    @State private var primaryName: String
    @State private var secondaryName: String
    @State private var projectName: String
    @State private var mode = FontLabRemixMode.blend
    @State private var preset = FontLabStarterPreset.clean
    @State private var blendAmount = 0.5
    @State private var rightsConfirmed = false
    @State private var isGenerating = false
    @State private var failure = ""
    @State private var autoName = ""
    @State private var preview: FontLabRemixResult?
    @State private var previewBusy = true
    @State private var previewRecipe: FontLabRemixRecipe?
    @State private var previewFailure = ""

    init(faces: [Face], suggestedNames: [String], onCreate: @escaping (FontLabRemixResult) -> Bool) {
        self.faces = faces.sorted {
            if $0.originalFamily == $1.originalFamily {
                return $0.style.localizedStandardCompare($1.style) == .orderedAscending
            }
            return $0.originalFamily.localizedStandardCompare($1.originalFamily) == .orderedAscending
        }
        self.onCreate = onCreate

        let available = Set(faces.map(\.name))
        var choices = suggestedNames.filter { available.contains($0) }
        for familiar in ["Helvetica", "TimesNewRomanPSMT", "Times-Roman", "Georgia"] where available.contains(familiar) && !choices.contains(familiar) {
            choices.append(familiar)
        }
        for face in self.faces where !choices.contains(face.name) && choices.count < 2 {
            choices.append(face.name)
        }
        let first = choices.first ?? ""
        let second = choices.dropFirst().first ?? first
        _primaryName = State(initialValue: first)
        _secondaryName = State(initialValue: second)

        let firstFamily = faces.first(where: { $0.name == first })?.originalFamily ?? "Font"
        let secondFamily = faces.first(where: { $0.name == second })?.originalFamily ?? "Remix"
        _projectName = State(initialValue: String("\(firstFamily) × \(secondFamily)".prefix(200)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Generate an editable font starter").font(.title2.weight(.semibold))
                    Text("Remix two installed faces, then redraw or refine any character in Font Lab.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Label("Local generator", systemImage: "lock.shield")
                    .font(.caption.weight(.medium)).foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Project name").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Button("Use source names") { projectName = suggestedProjectName; autoName = suggestedProjectName }
                        .buttonStyle(.plain).font(.caption).disabled(projectName == suggestedProjectName)
                }
                TextField("Font name", text: $projectName).textFieldStyle(.roundedBorder)
                    .onChange(of: projectName) { value in
                        if value.count > 200 { projectName = String(value.prefix(200)) }
                    }
            }

            HStack(alignment: .center, spacing: 12) {
                FontLabFacePicker(title: "Source A", faces: faces, selection: $primaryName)
                Button {
                    let previous = primaryName
                    primaryName = secondaryName
                    secondaryName = previous
                } label: {
                    Image(systemName: "arrow.left.arrow.right")
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.plain).shelfGlass(radius: 10)
                .help("Swap source fonts")
                FontLabFacePicker(title: "Source B", faces: faces, selection: $secondaryName)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Method").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Text(mode.explanation).font(.caption).foregroundStyle(.secondary)
                }
                Picker("Remix method", selection: $mode) {
                    ForEach(FontLabRemixMode.allCases) { option in Text(option.title).tag(option) }
                }
                .pickerStyle(.segmented).labelsHidden()

                HStack(spacing: 10) {
                    Text("A").font(.caption.weight(.semibold))
                    Slider(value: $blendAmount, in: 0...1)
                    Text("B").font(.caption.weight(.semibold))
                    Text("\(Int((blendAmount * 100).rounded()))% B")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 48, alignment: .trailing)
                }
                .disabled(primaryName == secondaryName)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Starting style").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Picker("Starting style", selection: $preset) {
                    ForEach(FontLabStarterPreset.allCases) { option in Text(option.title).tag(option) }
                }
                .pickerStyle(.segmented).labelsHidden()
            }

            Text(preset.explanation).font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 12) {
                FontLabSourcePreview(label: "A", face: selectedFace(primaryName))
                FontLabSourcePreview(label: "B", face: selectedFace(secondaryName))
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("Generated preview").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    if previewBusy { ProgressView().controlSize(.small); Text("Updating…").font(.caption) }
                }
                if let preview {
                    FontLabPreviewCanvas(text: "Hamburgefontsiv 08&", glyphs: preview.project.glyphs, metrics: preview.project.metrics)
                        .frame(height: 94).opacity(previewBusy ? 0.4 : 1)
                    if let sourceB = preview.provenance.sourceBCharacters {
                        let sourceA = preview.project.characters.filter { preview.project.glyphs[$0]?.strokes.isEmpty == false && !sourceB.contains($0) }
                        Text("A: " + sourceA.joined(separator: " ") + "     B: " + sourceB.joined(separator: " "))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    if !preview.preservedCharacters.isEmpty {
                        Text("\(preview.preservedCharacters.count) of \(preview.project.completedCount) preview glyphs keep source \(preview.provenance.blendAmount < 0.5 ? "A" : "B")’s shape with combined proportions: " + preview.preservedCharacters.joined(separator: " "))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                } else {
                    Text(previewFailure.isEmpty ? "Building your preview…" : previewFailure)
                        .font(.caption).foregroundStyle(.secondary).frame(height: 94)
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                Label("Private by design", systemImage: "checkmark.shield")
                    .font(.subheadline.weight(.semibold))
                Text("Generated on your Mac. Review both source font licenses before installing or sharing a derivative font.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Toggle("I have permission to modify both source fonts for this project.", isOn: $rightsConfirmed)
                    .toggleStyle(.checkbox)
                    .font(.caption.weight(.medium))
                    .padding(.top, 3)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 11, style: .continuous))

            if !failure.isEmpty {
                Text(failure).font(.caption).foregroundStyle(.orange).textSelection(.enabled)
            }

            HStack {
                Text(isGenerating ? "Combining the starter character set…" : "Use Reshape to edit outline points, or draw over any glyph.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }.disabled(isGenerating)
                Button("Create starter") { generate() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isGenerating || !canGenerate)
            }
        }
        .padding(24)
        .frame(width: 800, height: 820)
        .disabled(isGenerating)
        .onAppear { autoName = suggestedProjectName }
        .onChange(of: primaryName) { _ in updateSuggestedName() }
        .onChange(of: secondaryName) { _ in updateSuggestedName() }
        .task(id: recipe) { await refreshPreview() }
        .interactiveDismissDisabled(isGenerating)
    }

    private var canGenerate: Bool {
        !primaryName.isEmpty && !secondaryName.isEmpty &&
            !projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && projectName.count <= 200 &&
            rightsConfirmed && !previewBusy && preview != nil && previewRecipe == recipe
    }

    private func selectedFace(_ name: String) -> Face? { faces.first { $0.name == name } }

    private var suggestedProjectName: String {
        String("\(selectedFace(primaryName)?.originalFamily ?? "Font") × \(selectedFace(secondaryName)?.originalFamily ?? "Remix")".prefix(200))
    }

    private func updateSuggestedName() {
        if projectName == autoName || projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            projectName = suggestedProjectName
        }
        autoName = suggestedProjectName
    }

    private var recipe: FontLabRemixRecipe {
        FontLabRemixRecipe(primaryPostScriptName: primaryName, secondaryPostScriptName: secondaryName,
            blendAmount: primaryName == secondaryName ? 0 : blendAmount, mode: mode, preset: preset)
    }

    @MainActor private func refreshPreview() async {
        previewBusy = true
        previewFailure = ""
        let requestedRecipe = recipe
        do { try await Task.sleep(nanoseconds: 220_000_000) } catch { return }
        let generated = await Task.detached(priority: .userInitiated) {
            Result { try FontLabRemixEngine.generate(recipe: requestedRecipe,
                characters: Array("Hamburgefontsiv08&").map(String.init)) }
        }.value
        guard !Task.isCancelled else { return }
        previewBusy = false
        switch generated {
        case let .success(result): preview = result; previewRecipe = requestedRecipe
        case let .failure(error): preview = nil; previewRecipe = nil; previewFailure = error.localizedDescription
        }
    }

    private func generate() {
        let recipe = self.recipe
        let requestedName = projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        isGenerating = true
        failure = ""
        DispatchQueue.global(qos: .userInitiated).async {
            let generated = Result {
                try FontLabRemixEngine.generate(recipe: recipe, projectName: requestedName)
            }
            DispatchQueue.main.async {
                isGenerating = false
                switch generated {
                case let .success(result):
                    if onCreate(result) { dismiss() }
                    else { failure = "FontShelf could not add the generated project. The existing Font Lab data was not replaced." }
                case let .failure(error):
                    failure = error.localizedDescription
                }
            }
        }
    }
}

private struct FontLabFacePicker: View {
    let title: String
    let faces: [Face]
    @Binding var selection: String
    @State private var presented = false
    @State private var query = ""

    private var selected: Face? { faces.first { $0.name == selection } }
    private var filteredFaces: [Face] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return faces }
        return faces.filter {
            $0.originalFamily.localizedCaseInsensitiveContains(needle) ||
                $0.style.localizedCaseInsensitiveContains(needle) ||
                $0.name.localizedCaseInsensitiveContains(needle)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Button { presented = true } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(selected?.originalFamily ?? "Choose a font").font(.subheadline.weight(.semibold)).lineLimit(1)
                        Text(selected.map { "\($0.style) · \($0.name)" } ?? "Search installed faces")
                            .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 6)
                    Text("Ag").font(.custom(selected?.name ?? "Helvetica", size: 25))
                    Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(.secondary)
                }
                .padding(11)
                .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Color.primary.opacity(0.11)))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .popover(isPresented: $presented, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("Search family, style, or PostScript name", text: $query)
                        .textFieldStyle(.roundedBorder)
                    HStack {
                        Text("\(filteredFaces.count) available \(filteredFaces.count == 1 ? "face" : "faces")")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        if !query.isEmpty { Button("Clear") { query = "" }.buttonStyle(.plain).font(.caption) }
                    }
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(filteredFaces) { face in
                                Button {
                                    selection = face.name
                                    presented = false
                                } label: {
                                    HStack(spacing: 10) {
                                        Text("Ag").font(.custom(face.name, size: 21)).frame(width: 38)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(face.originalFamily).font(.subheadline.weight(face.name == selection ? .semibold : .regular))
                                            Text("\(face.style) · \(face.name)").font(.caption2).foregroundStyle(.secondary)
                                        }
                                        .lineLimit(1)
                                        Spacer()
                                        if face.name == selection { Image(systemName: "checkmark").foregroundStyle(ShelfPalette.ink) }
                                    }
                                    .padding(.horizontal, 8).padding(.vertical, 7)
                                    .background(face.name == selection ? Color.primary.opacity(0.08) : Color.clear,
                                                in: RoundedRectangle(cornerRadius: 7))
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("\(face.originalFamily), \(face.style), \(face.name)")
                            }
                        }
                    }
                }
                .padding(14).frame(width: 410, height: 440)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct FontLabSourcePreview: View {
    let label: String
    let face: Face?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Source \(label) preview").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text("Hamburgefontsiv 0123")
                .font(.custom(face?.name ?? "Helvetica", size: 25))
                .lineLimit(1).minimumScaleFactor(0.55)
        }
        .padding(12).frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Color.primary.opacity(0.1)))
    }
}
