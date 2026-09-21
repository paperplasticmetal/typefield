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
    @State private var preset = FontLabStarterPreset.soft
    @State private var blendAmount = 0.5
    @State private var rightsConfirmed = false
    @State private var isGenerating = false
    @State private var failure = ""

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
        for familiar in ["Helvetica", "Times-Roman"] where available.contains(familiar) && !choices.contains(familiar) {
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
        VStack(alignment: .leading, spacing: 18) {
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
                Text("PROJECT NAME").font(.system(size: 10, weight: .semibold)).tracking(0.8).foregroundStyle(.secondary)
                TextField("Font name", text: $projectName).textFieldStyle(.roundedBorder)
                    .onChange(of: projectName) { value in
                        if value.count > 200 { projectName = String(value.prefix(200)) }
                    }
            }

            HStack(alignment: .center, spacing: 12) {
                FontLabFacePicker(title: "SOURCE A", faces: faces, selection: $primaryName)
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
                FontLabFacePicker(title: "SOURCE B", faces: faces, selection: $secondaryName)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("METHOD").font(.system(size: 10, weight: .semibold)).tracking(0.8).foregroundStyle(.secondary)
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
                    Text("\(Int((blendAmount * 100).rounded()))%")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 38, alignment: .trailing)
                }
                .disabled(primaryName == secondaryName)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("STARTING STYLE").font(.system(size: 10, weight: .semibold)).tracking(0.8).foregroundStyle(.secondary)
                Picker("Starting style", selection: $preset) {
                    ForEach(FontLabStarterPreset.allCases) { option in Text(option.title).tag(option) }
                }
                .pickerStyle(.segmented).labelsHidden()
            }

            HStack(spacing: 12) {
                FontLabSourcePreview(label: "A", face: selectedFace(primaryName))
                FontLabSourcePreview(label: "B", face: selectedFace(secondaryName))
            }

            VStack(alignment: .leading, spacing: 5) {
                Label("Private by design", systemImage: "checkmark.shield")
                    .font(.subheadline.weight(.semibold))
                Text("This version uses deterministic outline sampling and geometric presets—not a cloud AI model. It copies no source font binaries, but the result is derivative artwork: review both source licenses before installing or sharing it.")
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
                Text(isGenerating ? "Sampling and combining the starter character set…" : "The generated glyphs remain ordinary editable Font Lab strokes.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }.disabled(isGenerating)
                Button("Create starter") { generate() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isGenerating || !canGenerate)
            }
        }
        .padding(24)
        .frame(width: 760, height: 720)
        .interactiveDismissDisabled(isGenerating)
    }

    private var canGenerate: Bool {
        !primaryName.isEmpty && !secondaryName.isEmpty &&
            !projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && projectName.count <= 200 &&
            rightsConfirmed
    }

    private func selectedFace(_ name: String) -> Face? { faces.first { $0.name == name } }

    private func generate() {
        let recipe = FontLabRemixRecipe(
            primaryPostScriptName: primaryName,
            secondaryPostScriptName: secondaryName,
            blendAmount: primaryName == secondaryName ? 0 : blendAmount,
            mode: mode,
            preset: preset
        )
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
            Text(title).font(.system(size: 10, weight: .semibold)).tracking(0.8).foregroundStyle(.secondary)
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
                    List(filteredFaces) { face in
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
                                Spacer()
                                if face.name == selection { Image(systemName: "checkmark").foregroundStyle(ShelfPalette.ink) }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.inset)
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
            Text("SOURCE \(label) PREVIEW").font(.system(size: 9, weight: .semibold)).tracking(0.7).foregroundStyle(.secondary)
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
