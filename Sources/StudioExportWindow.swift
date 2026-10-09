import SwiftUI
import AppKit

enum StudioSummaryOutput: String, CaseIterable {
    case text = "Plain text (.txt)"
    case markdown = "Markdown (.md)"
    case pdf = "Type system PDF"
    case illustrator = "Illustrator builder (.jsx)"
    case indesign = "InDesign builder (.jsx)"
    var supportsDetail: Bool { self == .text || self == .markdown }
}
struct StudioExportConfiguration {
    var kind: StudioExportKind
    var canvasIDs: Set<UUID>
    var summaryOutput: StudioSummaryOutput
    var detail: TypographySummaryDetail
    var format: StudioTransferReport.Format {
        switch kind {
        case .summary:
            switch summaryOutput {
            case .text, .markdown: return .typographySummary
            case .pdf: return .typeSystemPDF
            case .illustrator, .indesign: return .adobeBuilder
            }
        case .web: return .typographySummary
        case .handoff: return .developerHandoff
        case .preview: return .previewPDF
        case .figma: return .figma
        }
    }
}

struct StudioExportScopeView: View {
    let board: TypeBoard
    let shown: Set<UUID>
    let current: UUID
    let availableFonts: Set<String>
    let onContinue: (StudioExportConfiguration) -> Void
    @State private var kind: StudioExportKind
    @State private var scope = StudioExportScope.shown
    @State private var selected: Set<UUID>
    @State private var output = StudioSummaryOutput.text
    @State private var detail = TypographySummaryDetail.roles
    @State private var previewTab = "Canvases"
    @State private var copied = false
    @Environment(\.dismiss) private var dismiss
    init(kind: StudioExportKind, board: TypeBoard, shown: Set<UUID>, current: UUID, availableFonts: Set<String>, onContinue: @escaping (StudioExportConfiguration) -> Void) {
        self.board = board; self.shown = shown; self.current = current; self.availableFonts = availableFonts; self.onContinue = onContinue
        _kind = State(initialValue: kind); _selected = State(initialValue: shown)
    }
    private var ids: Set<UUID> { scope.ids(board: board, shown: shown, current: current, selected: selected) }
    private var directions: [TypeDirection] { board.directions.filter { ids.contains($0.id) } }
    private var configuration: StudioExportConfiguration { StudioExportConfiguration(kind: kind, canvasIDs: ids, summaryOutput: output, detail: detail) }
    private var report: StudioTransferReport { StudioTransferReport(format: configuration.format, scope: board.name, directions: directions, availableFonts: availableFonts) }
    private var summary: TypographySummaryDocument { TypographySummaryDocument(summaries: directions.map { CanvasTypographySummary(canvas: board.canvasName($0), direction: $0) }) }
    private var selectionCount: String { "\(ids.count) of \(board.directions.count) canvases" }
    private func selection(_ id: UUID) -> Binding<Bool> {
        Binding(get: { ids.contains(id) }, set: { included in
            selected = ids
            scope = .selected
            if included { selected.insert(id) } else { selected.remove(id) }
        })
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "square.and.arrow.up").font(.title2).foregroundStyle(Color.accentColor)
                    .frame(width: 44, height: 44).background(Color.accentColor.opacity(0.09), in: RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Export typeboard").font(.title2.weight(.semibold))
                    Text(board.name).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
            }.padding(24)
            Divider()
            HStack(alignment: .top, spacing: 0) {
                settings.frame(width: 245).padding(24)
                Divider()
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Picker("Preview", selection: $previewTab) { Text("Canvases").tag("Canvases"); Text("Typography").tag("Typography") }
                            .pickerStyle(.segmented).labelsHidden()
                        Text(selectionCount).font(.caption).foregroundStyle(.secondary).fixedSize()
                    }
                    if previewTab == "Canvases" { canvasList }
                    else { StudioTypographyPreview(summaries: summary.summaries, detail: detail) }
                    StudioExportReview(report: report, showsFormatNote: kind != .web)
                }.padding(20).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }.frame(height: 450)
            Divider()
            HStack(spacing: 12) {
                if kind == .summary {
                    Button(localizedKey(copied ? "Copied" : "Copy summary")) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(summary.text(detail, markdown: output == .markdown), forType: .string)
                        copied = true
                    }.disabled(ids.isEmpty)
                }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(localizedKey(kind == .web ? "Open report" : "Export…")) { onContinue(configuration) }
                    .keyboardShortcut(.defaultAction).disabled(ids.isEmpty || report.blockingReason != nil)
            }.controlSize(.large).padding(.horizontal, 24).padding(.vertical, 16)
        }.frame(width: 800)
        .onChange(of: kind) { _ in copied = false }
        .onChange(of: ids) { _ in copied = false }
        .onChange(of: detail) { _ in copied = false }
        .onChange(of: output) { _ in copied = false }
    }
    private var settings: some View {
        VStack(alignment: .leading, spacing: 20) {
            setting("Export") {
                Picker("Export format", selection: $kind) { ForEach(StudioExportKind.allCases) { Text(localizedKey($0.rawValue)).tag($0) } }.labelsHidden()
            }
            setting("Include") {
                Picker("Canvas scope", selection: $scope) { ForEach(StudioExportScope.allCases, id: \.self) { Text(localizedKey($0.rawValue)).tag($0) } }.labelsHidden()
            }
            if kind == .summary {
                Divider()
                setting("File format") {
                    Picker("Summary file format", selection: $output) { ForEach(StudioSummaryOutput.allCases, id: \.self) { Text(localizedKey($0.rawValue)).tag($0) } }.labelsHidden()
                }
                if output.supportsDetail {
                    setting("Include in summary") {
                        Picker("Summary detail", selection: $detail) { ForEach(TypographySummaryDetail.allCases) { Text(localizedKey($0.rawValue)).tag($0) } }.labelsHidden()
                    }
                }
            }
            Spacer(minLength: 0)
            Label(kind == .web ? "Choose licensed web assets in the report." : "Choose the destination after Export.", systemImage: kind == .web ? "network" : "folder")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.frame(maxHeight: .infinity)
    }
    private func setting<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) { Text(title).font(.subheadline.weight(.medium)); content().frame(maxWidth: .infinity) }
    }
    private var canvasList: some View {
        ScrollView {
            LazyVStack(spacing: 1) {
                ForEach(board.directions) { canvas in
                    HStack(spacing: 12) {
                        Toggle("Include " + board.canvasName(canvas), isOn: selection(canvas.id)).toggleStyle(.checkbox).labelsHidden()
                        Image(systemName: "rectangle.portrait").font(.title2).foregroundStyle(.secondary)
                            .frame(width: 36, height: 42).background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 5))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(board.canvasName(canvas)).font(.subheadline.weight(.medium)).lineLimit(1)
                            let size = CanvasPlanCache.plan(for: canvas).artboardSize
                            Text("\(Int(size.width)) × \(Int(size.height)) · " + canvas.canvasDisplayName).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }.padding(10).background(ids.contains(canvas.id) ? Color.accentColor.opacity(0.07) : Color.clear)
                }
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.primary.opacity(0.1)))
    }
}

struct StudioExportReview: View {
    let report: StudioTransferReport
    var showsFormatNote = true
    @State private var detailsExpanded = false
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 18) {
                Label("\(report.referencedFonts.count) fonts", systemImage: "textformat")
                if !report.missingFonts.isEmpty { Label("\(report.missingFonts.count) unavailable", systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
                if report.omittedArtworkCount > 0 { Label("\(report.omittedArtworkCount) images omitted", systemImage: "photo").foregroundStyle(.orange) }
            }.font(.caption)
            if let reason = report.blockingReason {
                Text(reason).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            if let note = report.effectsOmissionNote {
                Label(note, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            if showsFormatNote { Text(report.format.limitation).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            if !report.missingFonts.isEmpty {
                DisclosureGroup("Unavailable fonts", isExpanded: $detailsExpanded) {
                    ScrollView { Text(report.missingFonts.joined(separator: ", ")).font(.caption).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 65)
                    Text("Previews use fallback fonts.").font(.caption).foregroundStyle(.secondary)
                }.font(.caption)
            }
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
    }
}

struct StudioTypographyPreview: View {
    let summaries: [CanvasTypographySummary]
    let detail: TypographySummaryDetail
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if summaries.isEmpty { Text("Select a canvas to preview its typography.").foregroundStyle(.secondary).padding(12) }
                ForEach(Array(summaries.enumerated()), id: \.offset) { _, summary in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(summary.canvas).font(.subheadline.weight(.semibold))
                        if detail == .fonts {
                            ForEach(summary.fonts, id: \.self) { font in Text(font).font(.subheadline).textSelection(.enabled) }
                        } else {
                            ForEach(summary.entries, id: \.self) { entry in
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack { Text(entry.role).font(.caption).foregroundStyle(.secondary); Spacer(); Text(entry.font).font(.subheadline).textSelection(.enabled) }
                                    if detail == .full {
                                        HStack(spacing: 14) { metric("Size", entry.size); metric("Leading", entry.lineHeight); metric("Tracking", entry.tracking) }
                                        if !entry.axes.isEmpty { Text("Axes: " + entry.axes).font(.caption).foregroundStyle(.secondary) }
                                        if !entry.features.isEmpty { Text("Features: " + entry.features).font(.caption).foregroundStyle(.secondary) }
                                    }
                                }.padding(.vertical, 5)
                                Divider()
                            }
                        }
                    }
                }
            }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.primary.opacity(0.1)))
    }
    private func metric(_ title: String, _ value: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) { Text(title).foregroundStyle(.secondary); Text(DeveloperHandoff.number(value) + " px").monospacedDigit() }.font(.caption)
    }
}
