import SwiftUI

/// Reviews local letter suggestions before any project artwork is changed.
struct FontLabStarterAssistView: View {
    let original: FontLabProject
    let onApply: (FontLabProject) -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var proposal: FontLabStarterProposal?
    @State private var scope: LetterScope = .both
    @State private var selected: Set<String> = []
    @State private var focusedCharacter: String?
    @State private var failure = ""

    private enum LetterScope: String, CaseIterable {
        case uppercase = "Uppercase"
        case lowercase = "Lowercase"
        case both = "Both"

        func includes(_ character: String) -> Bool {
            guard character.unicodeScalars.count == 1,
                  let value = character.unicodeScalars.first?.value else { return false }
            let upper = (65...90).contains(value)
            let lower = (97...122).contains(value)
            switch self {
            case .uppercase: return upper
            case .lowercase: return lower
            case .both: return upper || lower
            }
        }
    }

    private var emptyCharacters: [String] {
        original.characters.filter { scope.includes($0) && original.resolvedGlyph($0)?.hasArtwork != true }
    }

    private var availableCharacters: [String] {
        guard let proposal else { return [] }
        return emptyCharacters.filter {
            guard let candidate = proposal.glyphs[$0] else { return false }
            return candidate.hasArtwork && candidate.isValid
        }
    }

    private var unavailableCharacters: [String] {
        let available = Set(availableCharacters)
        return emptyCharacters.filter { !available.contains($0) }
    }

    private var selectedCharacters: [String] {
        availableCharacters.filter { selected.contains($0) }
    }

    private var inspectedCharacter: String? {
        if let focusedCharacter, availableCharacters.contains(focusedCharacter) { return focusedCharacter }
        return availableCharacters.first
    }

    private var activeMasterName: String {
        original.masters?.first(where: { $0.id == original.activeMasterID })?.name ?? "Current design"
    }

    private var adaptedCharacters: [String] {
        guard let proposal else { return [] }
        return availableCharacters.filter { proposal.details[$0]?.confidence == .adapted }
    }

    private var templateCharacters: [String] {
        guard let proposal else { return [] }
        return availableCharacters.filter { proposal.details[$0]?.confidence == .template }
    }

    private var nextReferenceTip: String? {
        guard let proposal else { return nil }
        let opportunities: [(String, [String])] = [
            ("o", ["a", "b", "c", "d", "p", "q"]),
            ("n", ["h", "m", "u"]),
            ("O", ["C", "Q"]),
            ("P", ["R"])
        ]
        let useful = opportunities.compactMap { source, targets -> String? in
            guard original.characters.contains(source), original.resolvedGlyph(source)?.hasArtwork != true,
                  targets.contains(where: { emptyCharacters.contains($0) && proposal.details[$0]?.confidence == .template }) else { return nil }
            return source
        }
        guard !useful.isEmpty else { return nil }
        let names: String
        switch useful.count {
        case 1: names = useful[0]
        case 2: names = useful.joined(separator: " and ")
        default: names = useful.dropLast().joined(separator: ", ") + ", and " + useful.last!
        }
        return "Draw \(names) to unlock more suggestions that reuse your outlines. Reopen this review after drawing them."
    }

    private var proofGlyphs: [String: FontLabGlyph] {
        var glyphs = original.outputProject.glyphs
        guard let proposal else { return glyphs }
        for character in selectedCharacters {
            if let candidate = proposal.glyphs[character] { glyphs[character] = candidate }
        }
        return glyphs
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Suggest missing letters").font(.title2.weight(.semibold))
                Text("Build editable starting points from the letters already in this project. Every suggestion needs a shape and spacing review.")
                    .font(.callout).foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Picker("Letters", selection: $scope) {
                    ForEach(LetterScope.allCases, id: \.self) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 320)
                Spacer()
                Label("Active master: \(activeMasterName)", systemImage: "square.stack.3d.up")
                    .font(.caption).foregroundStyle(.secondary)
                    .help("Suggestions will be added only to the active master.")
            }
            Text("Suggestions are optional and apply only to this master. You can export a partial font using only your drawn glyphs.")
                .font(.caption).foregroundStyle(.secondary)

            if let proposal {
                Text("\(availableCharacters.count) suggestions available · \(unavailableCharacters.count) without suggestions · \(selectedCharacters.count) selected")
                    .font(.subheadline.monospacedDigit())
                HStack(spacing: 16) {
                    Label("\(adaptedCharacters.count) reuse your outlines", systemImage: "square.on.square")
                    Label("\(templateCharacters.count) are constructed templates", systemImage: "square.dashed")
                }
                .font(.caption).foregroundStyle(.secondary)
                if !proposal.note.isEmpty {
                    Text(proposal.note).font(.caption).foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                HStack(alignment: .top, spacing: 12) {
                    suggestionList(proposal)
                        .frame(width: 290)
                        .frame(maxHeight: .infinity)
                    inspectionPanel(proposal)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                .frame(maxHeight: .infinity)

                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("Word preview with selected suggestions").font(.caption.weight(.semibold))
                        Spacer()
                        Text("Outlined tiles remain missing").font(.caption2).foregroundStyle(.secondary)
                    }
                    FontLabPreviewCanvas(text: original.previewText, glyphs: proofGlyphs, metrics: original.metrics,
                                         kerningGroups: original.kerningGroups ?? [], kerningPairs: original.kerningPairs ?? [],
                                         previewInkHex: original.previewInkHex)
                        .frame(height: 70)
                        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            } else {
                ProgressView("Preparing letter suggestions…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if !failure.isEmpty {
                Text(failure).font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Text("Your existing drawings stay unchanged. Cancel leaves the project untouched.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Apply \(selectedCharacters.count) suggestions") { apply() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selectedCharacters.isEmpty)
            }
        }
        .padding(18)
        .frame(width: 880, height: 620)
        .onAppear(perform: prepare)
        .onChange(of: scope) { _ in
            selected = Set(availableCharacters)
            focusedCharacter = availableCharacters.first
            failure = ""
        }
    }

    private func suggestionList(_ proposal: FontLabStarterProposal) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Review letters").font(.caption.weight(.semibold))
                Spacer()
                Menu("Select") {
                    Button("All suggestions") { selected = Set(availableCharacters) }
                    Button("Only reused outlines") { selected = Set(adaptedCharacters) }
                        .disabled(adaptedCharacters.isEmpty)
                    Button("None") { selected.removeAll() }
                }
                .disabled(availableCharacters.isEmpty)
            }
            .font(.caption)

            ScrollView {
                LazyVStack(spacing: 7) {
                    ForEach(availableCharacters, id: \.self) { character in
                        let detail = proposal.details[character]
                        let adapted = detail?.confidence == .adapted
                        let lineage = adapted
                            ? "Reuses \(detail?.sourceCharacters.joined(separator: ", ") ?? "your") \(detail?.sourceCharacters.count == 1 ? "outline" : "outlines")"
                            : "Constructed template"
                        HStack(spacing: 8) {
                            Toggle("Include \(character)", isOn: Binding(
                                get: { selected.contains(character) },
                                set: { include in
                                    if include { selected.insert(character) }
                                    else { selected.remove(character) }
                                }
                            ))
                            .labelsHidden().toggleStyle(.checkbox)
                            Button { focusedCharacter = character } label: {
                                HStack(spacing: 9) {
                                    Text(character).font(.system(size: 21, design: .serif))
                                        .frame(width: 30)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Suggested \(character)").font(.subheadline)
                                        Label(lineage, systemImage: adapted ? "square.on.square" : "square.dashed")
                                            .font(.caption2)
                                            .foregroundStyle(adapted ? Color.accentColor : Color.orange)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    Image(systemName: focusedCharacter == character ? "chevron.right.circle.fill" : "chevron.right")
                                        .foregroundStyle(.secondary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Review suggested \(character), \(lineage)")
                        }
                        .padding(8)
                        .background(focusedCharacter == character ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.035),
                                    in: RoundedRectangle(cornerRadius: 9))
                    }
                    if availableCharacters.isEmpty {
                        VStack(alignment: .leading, spacing: 7) {
                            Text(emptyCharacters.isEmpty ? "Every letter in this set already has artwork." : "No suggestions are ready for this set yet.")
                                .font(.subheadline.weight(.medium))
                            if !emptyCharacters.isEmpty {
                                Text("Try drawing H and O for capitals, or x, n, o, and p for lowercase proportions and spacing.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading).padding(10)
                    }
                    if !unavailableCharacters.isEmpty {
                        DisclosureGroup("Why \(unavailableCharacters.count) letters remain empty") {
                            VStack(alignment: .leading, spacing: 5) {
                                ForEach(unavailableCharacters, id: \.self) { character in
                                    Text("\(character): \(proposal.skipped[character] ?? "No reliable suggestion from the current drawings.")")
                                        .font(.caption).fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .padding(.top, 6)
                        }
                        .font(.caption)
                        .padding(8)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func inspectionPanel(_ proposal: FontLabStarterProposal) -> some View {
        if let character = inspectedCharacter, let glyph = proposal.glyphs[character] {
            let detail = proposal.details[character]
            let adapted = detail?.confidence == .adapted
            let sources = detail?.sourceCharacters ?? []
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Suggested \(character)").font(.headline)
                        Spacer()
                        Label(detail?.confidence.title ?? "Review carefully",
                              systemImage: adapted ? "square.on.square" : "square.dashed")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(adapted ? Color.accentColor : Color.orange)
                    }
                    if let detail {
                        Text(detail.method).font(.subheadline.weight(.medium))
                        Text(detail.explanation).font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack(alignment: .top, spacing: 10) {
                        if !sources.isEmpty {
                            previewCard(adapted ? "Your source: \(sources.prefix(3).joined(separator: " "))" : "Style references: \(sources.prefix(3).joined(separator: " "))",
                                        text: sources.prefix(3).joined(),
                                        glyphs: original.outputProject.glyphs)
                        }
                        previewCard(adapted ? "Adapted suggestion: \(character)" : "Constructed suggestion: \(character)",
                                    text: character, glyphs: [character: glyph])
                    }
                    if adapted, !sources.isEmpty {
                        Text("This suggestion reuses some or all of your source outline and may add constructed parts. Compare the copied contours with your original.")
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if !sources.isEmpty {
                        Text("These drawings inform the suggested proportions and style. Their contours are not copied into \(character).")
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let nextReferenceTip {
                        Label(nextReferenceTip, systemImage: "lightbulb")
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text("The outline remains editable after Apply. Compare its curves, counters, width, and side bearings with your drawings.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Start with a few reference letters").font(.headline)
                Text("Suggestions appear here after Typefield finds reusable shapes in this project's drawings. You can keep drawing and export the letters you already have.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func previewCard(_ title: String, text: String, glyphs: [String: FontLabGlyph]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            FontLabPreviewCanvas(text: text, glyphs: glyphs, metrics: original.metrics,
                                 maximumEm: 110, centered: true, previewInkHex: original.previewInkHex)
                .frame(height: 104)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
                .clipShape(RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.primary.opacity(0.1)))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func prepare() {
        guard proposal == nil else { return }
        let generated = FontLabStarterAssist.propose(for: original)
        proposal = generated
        selected = Set(original.characters.filter {
            original.resolvedGlyph($0)?.hasArtwork != true && generated.glyphs[$0]?.hasArtwork == true
        })
        focusedCharacter = original.characters.first { generated.glyphs[$0]?.hasArtwork == true }
    }

    private func apply() {
        guard let proposal, !selectedCharacters.isEmpty else { return }
        var updated = original
        for character in selectedCharacters {
            guard original.characters.contains(character),
                  original.resolvedGlyph(character)?.hasArtwork != true,
                  let candidate = proposal.glyphs[character], candidate.isValid, candidate.hasArtwork else {
                failure = "A selected suggestion is no longer valid. Close and reopen the review."
                return
            }
            updated.glyphs[character] = candidate
        }
        updated.captureActiveMaster()
        guard updated.isValid else {
            failure = "These suggestions do not form a valid project. No artwork was changed."
            return
        }
        guard onApply(updated) else {
            failure = "Suggestions could not be applied. The project may have changed or saving may be unavailable. Close and reopen the review."
            return
        }
        dismiss()
    }
}
