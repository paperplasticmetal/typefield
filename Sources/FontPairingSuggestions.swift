import SwiftUI
import AppKit

/// A local, explainable pairing browser for a font already assigned in Spaces.
/// Choosing a result is intentionally delegated so the caller can decide
/// whether to apply it immediately, add it as a candidate, or update a draft.
struct FontPairingSuggestionsSheet: View {
    @ObservedObject var library: Library
    let reference: Face
    let intendedRole: TypeRole
    let onChoose: (Face) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var mode: FontPairingMode
    @State private var previewText: String
    @State private var suggestions: [FontPairingResult] = []
    @State private var loadingSuggestions = true

    init(library: Library, reference: Face, intendedRole: TypeRole, initialMode: FontPairingMode = .balanced, preview: String? = nil, onChoose: @escaping (Face) -> Void) {
        self.library = library
        self.reference = reference
        self.intendedRole = intendedRole
        self.onChoose = onChoose
        _mode = State(initialValue: initialMode)
        let suppliedPreview = preview?.trimmingCharacters(in: .whitespacesAndNewlines)
        let initialPreview = suppliedPreview.flatMap { $0.isEmpty ? nil : $0 } ?? intendedRole.sample
        _previewText = State(initialValue: initialPreview)
    }

    private var effectivePreview: String {
        let value = previewText.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? intendedRole.sample : value
    }

    private var modeDescription: String {
        switch mode {
        case .safe: return "Subtle separation, with compatible proportions and coverage doing most of the work."
        case .balanced: return "A clear change in voice while preserving rhythm, readability, and language support."
        case .expressive: return "Stronger shifts in category, weight, width, or stroke contrast—with compatibility guardrails."
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            controls(resultCount: suggestions.count)
            Divider()
            resultsList(suggestions)
        }
        .frame(width: 940, height: min(780, (NSScreen.main?.visibleFrame.height ?? 900) - 100))
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { refreshSuggestions() }
        .onChange(of: mode) { _ in refreshSuggestions() }
        .onChange(of: library.families.count) { _ in refreshSuggestions() }
        .onExitCommand { dismiss() }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 9) {
                    Text("Pair a font").font(.title2)
                    Text(intendedRole.rawValue)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(ShelfPalette.indiaYellow.opacity(0.16), in: Capsule())
                        .foregroundStyle(ShelfPalette.ink)
                }
                Text("Starting from \(reference.originalFamily) · \(reference.style)").font(.headline)
                Text("Suggestions use only fonts in your local Typefield catalog. Scores order this list; they are not match percentages or a substitute for trying the pair in context.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 24)
            Label("On this Mac", systemImage: "internaldrive")
                .font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Color.primary.opacity(0.045), in: Capsule())
            Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
        }
        .padding(22)
    }

    private func controls(resultCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .center, spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Pairing direction").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Picker("Pairing direction", selection: $mode) {
                        ForEach(FontPairingMode.allCases) { option in Text(option.rawValue).tag(option) }
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 360)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text(mode.rawValue).font(.headline)
                    Text(modeDescription).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer()
                Text("\(resultCount) suggestions").font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                Text("Preview").font(.caption).foregroundStyle(.secondary)
                TextField("Preview text", text: $previewText).textFieldStyle(.roundedBorder)
                Button("Use role sample") { previewText = intendedRole.sample }.disabled(previewText == intendedRole.sample)
            }
        }
        .padding(.horizontal, 22).padding(.vertical, 16)
        .background(Color.primary.opacity(0.018))
    }

    @ViewBuilder private func resultsList(_ suggestions: [FontPairingResult]) -> some View {
        if (library.loading || loadingSuggestions) && suggestions.isEmpty {
            VStack(spacing: 12) {
                ProgressView()
                Text("Loading the local font catalog…").foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if suggestions.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: intendedRole == .mono ? "chevron.left.forwardslash.chevron.right" : "textformat")
                    .font(.system(size: 34)).foregroundStyle(.secondary)
                Text("No local pairing candidates").font(.title3)
                Text(intendedRole == .mono ? "Typefield could not find another monospaced family in the current catalog." : "Typefield could not find another eligible family in the current catalog.")
                    .foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button("Done") { dismiss() }
            }
            .padding(40).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, result in
                        FontPairingSuggestionCard(reference: reference, result: result, category: library.category(result.family), preview: effectivePreview, rank: index + 1) {
                            onChoose(result.face)
                            dismiss()
                        }
                    }
                }
                .padding(20)
            }
        }
    }

    private func refreshSuggestions() {
        loadingSuggestions = true
        suggestions = library.pairingSuggestions(for: reference, intendedRole: intendedRole, mode: mode, limit: 16)
        loadingSuggestions = false
    }
}

private struct FontPairingSuggestionCard: View {
    let reference: Face
    let result: FontPairingResult
    let category: Category
    let preview: String
    let rank: Int
    let choose: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var showingDetails = false

    private var score: Int { Int(result.score.rounded()) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 7) {
                        Text(result.family.name).font(.headline)
                        Text("· " + result.face.style).foregroundStyle(.secondary)
                    }
                    Text("Suggested for \(result.intendedRole.rawValue) · \(category.rawValue)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text("#\(rank)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                PairingScoreBadge(score: score, mode: result.mode, assessment: result.assessment)
                Button("Choose for \(result.intendedRole.rawValue)", action: choose)
                    .buttonStyle(.borderedProminent)
            }

            VStack(spacing: 0) {
                pairingRow(label: "Current", face: reference, size: 22)
                Divider().padding(.leading, 86)
                pairingRow(label: result.intendedRole.rawValue, face: result.face, size: min(38, max(26, result.intendedRole.size * 0.65)))
            }
            .background(colorScheme == .dark ? Color.white.opacity(0.025) : Color.black.opacity(0.018), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.07)))

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "lightbulb").foregroundStyle(ShelfPalette.indiaYellow)
                Text(result.reasons.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button(showingDetails ? "Hide scoring" : "How it scored") { showingDetails.toggle() }
                    .buttonStyle(.borderless).font(.caption)
            }

            if showingDetails {
                HStack(spacing: 18) {
                    PairingMetric(label: "Compatibility", value: result.assessment.compatibility)
                    PairingMetric(label: "Role fit", value: result.assessment.roleFitness)
                    PairingMetric(label: "Contrast", value: result.assessment.contrast)
                    Spacer()
                    Text("Relative signals for this request—not percentages.").font(.caption2).foregroundStyle(.secondary)
                }
                .padding(11)
                .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(16)
        .background(colorScheme == .dark ? Color.white.opacity(0.025) : Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.08)))
        .accessibilityElement(children: .contain)
    }

    private func pairingRow(label: String, face: Face, size: Double) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                Text(face.originalFamily).font(.caption).lineLimit(1)
            }.frame(width: 72, alignment: .leading)
            FontPreview(text: preview, name: face.name, size: size, wraps: true)
                .frame(minHeight: max(38, size * 1.35)).allowsHitTesting(false)
        }
        .padding(.horizontal, 13).padding(.vertical, 9)
    }
}

private struct PairingScoreBadge: View {
    let score: Int
    let mode: FontPairingMode
    let assessment: FontPairingAssessment

    var body: some View {
        VStack(spacing: 1) {
            Text("\(score)").font(.headline.monospacedDigit())
            Text("Score").font(.system(size: 10, weight: .medium))
        }
        .frame(width: 52, height: 42)
        .background(ShelfPalette.indiaYellow.opacity(0.14), in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(ShelfPalette.indiaYellow.opacity(0.35)))
        .help("Relative \(mode.rawValue.lowercased())-mode score. Compatibility \(metric(assessment.compatibility)), role fit \(metric(assessment.roleFitness)), contrast \(metric(assessment.contrast)).")
        .accessibilityLabel("Pairing score \(score)")
    }

    private func metric(_ value: Double) -> String { String(Int((value * 100).rounded())) }
}

private struct PairingMetric: View {
    let label: String
    let value: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.caption2).foregroundStyle(.secondary)
                Text("\(Int((value * 100).rounded()))").font(.caption2.monospacedDigit())
            }
            ProgressView(value: value, total: 1).frame(width: 105)
        }
    }
}
