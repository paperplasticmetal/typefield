import SwiftUI
import AppKit
import CoreText
import UniformTypeIdentifiers

struct GlyphEntry: Identifiable {
    var id: Int { Int(glyph) }
    let glyph: CGGlyph
    let scalar: Unicode.Scalar?
    let glyphName: String
    var code: String { scalar.map { String(format: "U+%04X", $0.value) } ?? "GID \(glyph)" }
    var title: String { scalar?.properties.name ?? glyphName }
    var group: String {
        guard let scalar else { return "Unmapped" }
        switch scalar.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter: return "Letters"
        case .decimalNumber, .letterNumber, .otherNumber: return "Numbers"
        case .nonspacingMark, .spacingMark, .enclosingMark: return "Marks"
        case .connectorPunctuation, .dashPunctuation, .openPunctuation, .closePunctuation, .initialPunctuation, .finalPunctuation, .otherPunctuation: return "Punctuation"
        default: return "Symbols / other"
        }
    }
    func matches(_ query: String) -> Bool {
        query.isEmpty || code.localizedCaseInsensitiveContains(query) || title.localizedCaseInsensitiveContains(query) || glyphName.localizedCaseInsensitiveContains(query) || scalar.map { String($0) == query } == true
    }
}
enum GlyphCatalog {
    static func entries(font: CTFont, isCancelled: () -> Bool = { Task.isCancelled }) -> [GlyphEntry] {
        guard !isCancelled() else { return [] }
        let coverage = CTFontCopyCharacterSet(font) as CharacterSet
        var mapped: [CGGlyph: Unicode.Scalar] = [:]
        for plane in UInt8(0)...16 where coverage.hasMember(inPlane: plane) {
            for value in (UInt32(plane) << 16)...min(0x10FFFF, (UInt32(plane) << 16) + 65535) {
                if value % 1024 == 0 && isCancelled() { return [] }
                guard let scalar = Unicode.Scalar(value), coverage.contains(scalar) else { continue }
                let units = Array(String(scalar).utf16)
                var glyphs = [CGGlyph](repeating: 0, count: units.count)
                _ = CTFontGetGlyphsForCharacters(font, units, &glyphs, units.count)
                if let glyph = glyphs.first, glyph != 0, mapped[glyph] == nil { mapped[glyph] = scalar }
            }
        }
        var result: [GlyphEntry] = []
        for value in 1..<max(1, CTFontGetGlyphCount(font)) {
            if value % 1024 == 1 && isCancelled() { return [] }
            let glyph = CGGlyph(value)
            result.append(GlyphEntry(glyph: glyph, scalar: mapped[glyph], glyphName: CTFontCopyNameForGlyph(font, glyph) as String? ?? "glyph\(value)"))
        }
        guard !isCancelled() else { return [] }
        return result.sorted { ($0.scalar?.value ?? UInt32.max, $0.glyph) < ($1.scalar?.value ?? UInt32.max, $1.glyph) }
    }
    static func svg(font: CTFont, glyph: CGGlyph) -> String? {
        guard let path = CTFontCreatePathForGlyph(font, glyph, nil), !path.isEmpty else { return nil }
        let bounds = path.boundingBoxOfPath, pad = 4.0
        var pieces: [String] = []
        func point(_ p: CGPoint) -> String { String(format: "%.3f %.3f", p.x - bounds.minX + pad, bounds.maxY - p.y + pad) }
        path.applyWithBlock { ptr in
            let e = ptr.pointee
            switch e.type {
            case .moveToPoint: pieces.append("M" + point(e.points[0]))
            case .addLineToPoint: pieces.append("L" + point(e.points[0]))
            case .addQuadCurveToPoint: pieces.append("Q" + point(e.points[0]) + " " + point(e.points[1]))
            case .addCurveToPoint: pieces.append("C" + point(e.points[0]) + " " + point(e.points[1]) + " " + point(e.points[2]))
            case .closeSubpath: pieces.append("Z")
            @unknown default: break
            }
        }
        return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 \(bounds.width + pad * 2) \(bounds.height + pad * 2)\"><path fill=\"currentColor\" d=\"\(pieces.joined(separator: " "))\"/></svg>"
    }
}
struct GlyphBrowser: View {
    let face: Face
    let axes: [Int: Double]
    @State private var entries: [GlyphEntry] = []
    @State private var query = ""
    @State private var group = "All glyphs"
    @State private var selected: Int?
    @State private var metrics = false
    @State private var outlines = false
    @State private var loading = true
    @State private var status = ""
    var filtered: [GlyphEntry] {
        let search = query.trimmingCharacters(in: .whitespaces)
        return entries.filter { (group == "All glyphs" || $0.group == group) && $0.matches(search) }
    }
    var current: GlyphEntry? { entries.first { $0.id == selected } }
    var font: CTFont { OpenType.font(name: face.name, size: 100, axes: axes) }
    var body: some View {
        let visibleEntries = filtered
        let previewFont = font
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                TextField("Character, Unicode name, U+code, or glyph name", text: $query).textFieldStyle(.roundedBorder)
                ShelfDropdown(title: "Group", selection: $group, options: ["All glyphs", "Letters", "Numbers", "Marks", "Punctuation", "Symbols / other", "Unmapped"].map { ($0, $0) }).frame(width: 210)
                Text("\(visibleEntries.count)").monospacedDigit().foregroundStyle(.secondary)
            }
            if loading { ProgressView("Reading glyphs…").frame(maxWidth: .infinity, maxHeight: .infinity) }
            else {
                HStack(alignment: .top, spacing: 20) {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 78))], spacing: 8) {
                            ForEach(visibleEntries) { entry in
                                Button { selected = entry.id } label: {
                                    VStack(spacing: 4) { GlyphPreview(font: previewFont, glyph: entry.glyph, metrics: false, outlines: false).frame(height: 62); Text(entry.code).font(.system(size: 9, design: .monospaced)).lineLimit(1) }.padding(6).background(selected == entry.id ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 7))
                                }.buttonStyle(.plain).help(entry.title).accessibilityLabel(entry.title + " " + entry.code)
                                .onDrag { provider(entry) }
                            }
                        }
                        if visibleEntries.isEmpty { Text("No matching glyphs").foregroundStyle(.secondary).padding(30) }
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        if let entry = current {
                            GlyphPreview(font: previewFont, glyph: entry.glyph, metrics: metrics, outlines: outlines).frame(width: 230, height: 220).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
                            Text(entry.title).font(.headline).textSelection(.enabled)
                            Text(entry.code + ": " + entry.glyphName).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                            Toggle("Metrics", isOn: $metrics).toggleStyle(.checkbox)
                            Toggle("Outline", isOn: $outlines).toggleStyle(.checkbox)
                            if metrics { Text("Baseline, x-height, cap height").font(.caption).foregroundStyle(.secondary) }
                            Button("Copy character") { if let scalar = entry.scalar { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(String(scalar), forType: .string); status = "Character copied" } }.disabled(entry.scalar == nil)
                            Button("Export SVG…") { export(entry) }.disabled(CTFontCreatePathForGlyph(previewFont, entry.glyph, nil)?.isEmpty != false)
                            Text("Drag a glyph to export its vector outline.").font(.caption).foregroundStyle(.secondary)
                        } else { Text("Select a glyph").foregroundStyle(.secondary) }
                        Text(status).font(.caption).foregroundStyle(.secondary)
                    }.frame(width: 230)
                }
            }
        }.padding(18)
        .task(id: face.name) {
            loading = true; selected = nil
            let name = face.name
            let worker = Task.detached(priority: .userInitiated) { GlyphCatalog.entries(font: CTFontCreateWithName(name as CFString, 100, nil)) }
            let result = await withTaskCancellationHandler(operation: { await worker.value }, onCancel: { worker.cancel() })
            guard !Task.isCancelled else { return }
            entries = result; selected = result.first?.id; loading = false
        }
    }
    func provider(_ entry: GlyphEntry) -> NSItemProvider {
        let provider = NSItemProvider()
        if let svg = GlyphCatalog.svg(font: font, glyph: entry.glyph) {
            provider.suggestedName = "glyph-\(entry.glyph).svg"
            provider.registerDataRepresentation(forTypeIdentifier: UTType.svg.identifier, visibility: .all) { completion in completion(Data(svg.utf8), nil); return nil }
        }
        if let scalar = entry.scalar { provider.registerObject(String(scalar) as NSString, visibility: .all) }
        return provider
    }
    func export(_ entry: GlyphEntry) {
        guard let svg = GlyphCatalog.svg(font: font, glyph: entry.glyph) else { return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [.svg]; panel.nameFieldStringValue = "\(face.name)-\(entry.glyph).svg"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try svg.write(to: url, atomically: true, encoding: .utf8); status = "SVG exported" } catch { status = error.localizedDescription }
    }
}
final class GlyphNativeView: NSView {
    var font = CTFontCreateWithName("Helvetica" as CFString, 100, nil)
    var glyph: CGGlyph = 0
    var metrics = false
    var outlines = false
    /// Parent selection/search updates should not repaint every visible glyph.
    @discardableResult func update(font: CTFont, glyph: CGGlyph, metrics: Bool, outlines: Bool) -> Bool {
        guard !CFEqual(self.font, font) || self.glyph != glyph ||
                self.metrics != metrics || self.outlines != outlines else { return false }
        self.font = font
        self.glyph = glyph
        self.metrics = metrics
        self.outlines = outlines
        needsDisplay = true
        return true
    }
    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let rect = CTFontGetBoundingRectsForGlyphs(font, .default, [glyph], nil, 1)
        let scale = min((bounds.width - 22) / max(100, rect.width), (bounds.height - 24) / max(110, rect.height))
        context.saveGState(); defer { context.restoreGState() }
        context.clip(to: bounds)
        context.translateBy(x: (bounds.width - rect.width * scale) / 2 - rect.minX * scale, y: (bounds.height - rect.height * scale) / 2 - rect.minY * scale)
        context.scaleBy(x: scale, y: scale)
        if metrics {
            context.setStrokeColor(NSColor.systemCyan.withAlphaComponent(0.65).cgColor); context.setLineWidth(0.6 / scale)
            for y in [0, CTFontGetXHeight(font), CTFontGetCapHeight(font)] { context.move(to: CGPoint(x: -200, y: y)); context.addLine(to: CGPoint(x: 300, y: y)); context.strokePath() }
        }
        context.setFillColor(NSColor.labelColor.cgColor); context.setStrokeColor(NSColor.labelColor.cgColor)
        if outlines, let path = CTFontCreatePathForGlyph(font, glyph, nil) { context.addPath(path); context.setLineWidth(0.8 / scale); context.strokePath() }
        else { var g = glyph, position = CGPoint.zero; CTFontDrawGlyphs(font, &g, &position, 1, context) }
    }
}
struct GlyphPreview: NSViewRepresentable {
    let font: CTFont
    let glyph: CGGlyph
    let metrics: Bool
    let outlines: Bool
    func makeNSView(context: Context) -> GlyphNativeView { GlyphNativeView() }
    func updateNSView(_ view: GlyphNativeView, context: Context) { view.update(font: font, glyph: glyph, metrics: metrics, outlines: outlines) }
}

/// A glyph selection changes its surrounding button, not the glyph's pixels.
enum GlyphBrowserChecks {
    static func run() throws {
        func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
            if !condition() { throw NSError(domain: "Typefield.GlyphBrowserCheck", code: 1,
                                             userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        let view = GlyphNativeView(frame: NSRect(x: 0, y: 0, width: 80, height: 80))
        let font = CTFontCreateWithName("Helvetica" as CFString, 100, nil)
        try check(GlyphCatalog.entries(font: font, isCancelled: { true }).isEmpty,
                  "A cancelled glyph scan must not return entries")
        var cancellationChecks = 0
        let interrupted = GlyphCatalog.entries(font: font, isCancelled: {
            cancellationChecks += 1
            return cancellationChecks >= 3
        })
        try check(interrupted.isEmpty && cancellationChecks == 3,
                  "Glyph scanning must poll cancellation during enumeration and discard partial results")
        view.update(font: font, glyph: 36, metrics: false, outlines: false)
        // A detached NSView does not track AppKit's dirty regions. Check the
        // redraw decision directly without opening a test window on the desktop.
        for _ in 0..<100 {
            try check(!view.update(font: CTFontCreateCopyWithAttributes(font, 100, nil, nil),
                                   glyph: 36, metrics: false, outlines: false),
                      "Equivalent glyph updates must not trigger repaint")
        }
        try check(view.update(font: font, glyph: 37, metrics: false, outlines: false) && view.glyph == 37,
                  "Changing the glyph must repaint")
        try check(view.update(font: font, glyph: 37, metrics: true, outlines: false) && view.metrics,
                  "Toggling metrics must repaint")
        try check(view.update(font: font, glyph: 37, metrics: true, outlines: true) && view.outlines,
                  "Toggling outlines must repaint")
        let larger = CTFontCreateCopyWithAttributes(font, 120, nil, nil)
        try check(view.update(font: larger, glyph: 37, metrics: true, outlines: true) && CTFontGetSize(view.font) == 120,
                  "Changing the font must repaint")
        print("PASS: glyph previews skip unchanged redraws and invalidate changed rendering inputs.")
    }
}
