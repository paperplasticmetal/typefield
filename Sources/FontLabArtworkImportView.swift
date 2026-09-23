import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct FontLabArtworkImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    let currentProject: FontLabProject?
    let selectedCharacter: String
    let onImport: (FontLabProject, FontLabProject?) -> Bool

    @State private var source: FontLabArtworkSource?
    @State private var scan: FontLabArtworkScan?
    @State private var options = FontLabArtworkOptions()
    @State private var scannedOptions: FontLabArtworkOptions?
    @State private var selectedRegion: UUID?
    @State private var name = "Imported artwork"
    @State private var order = ""
    @State private var useCurrentProject = false
    @State private var replace = false
    @State private var reviewed = false
    @State private var busy = false
    @State private var failure = ""

    private var included: [FontLabArtworkRegion] { scan?.regions.filter(\.included) ?? [] }
    private var invalidAssignments: Bool {
        let labels = included.map { $0.character.trimmingCharacters(in: .whitespacesAndNewlines) }
        return labels.isEmpty || labels.contains(where: { $0.count != 1 }) || Set(labels).count != labels.count
    }
    private var conflicts: Int { included.filter { currentProject?.glyphs[$0.character]?.hasArtwork == true }.count }
    private var settingsChanged: Bool { scan != nil && scannedOptions != options }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Import your letter artwork").font(.title2.weight(.semibold))
                    Text("Scan a letter or a whole alphabet. Review the labels, then refine the outlines in Letterform Editor.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button(source == nil ? "Choose artwork…" : "Choose another file…") { chooseFile() }.disabled(busy)
            }
            if let source {
                HStack {
                    Text(source.filename).font(.subheadline.weight(.medium)).lineLimit(1)
                    Text("\(source.image.width) × \(source.image.height) px").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    Spacer()
                    Label("On your Mac", systemImage: "lock.shield").font(.caption).foregroundStyle(.secondary)
                }
                scanControls
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("SOURCE & LETTER REGIONS").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            Spacer()
                            Button("Clear regions") { scan?.regions = []; reviewed = false; selectedRegion = nil }.disabled(busy)
                                .font(.caption)
                        }
                        FontLabArtworkRegionCanvas(image: source.image, regions: scan?.regions ?? [], selected: selectedRegion,
                            select: { selectedRegion = $0 }, add: { rect in addRegion(rect) })
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 9))
                            .clipShape(RoundedRectangle(cornerRadius: 9))
                            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.primary.opacity(0.15)))
                            .disabled(busy || scan == nil || settingsChanged)
                        Text("Click a box to select it. Drag on the image to add a region. Remove a bad box, then draw separate boxes for touching letters.")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        HStack {
                            TextField("Letter order, e.g. ABCDEFG…", text: $order)
                                .textFieldStyle(.roundedBorder).onChange(of: order) { if $0.count > 256 { order = String($0.prefix(256)) } }
                            Button("Apply order") { applyOrder() }.disabled(busy || scan?.regions.isEmpty != false)
                        }
                        HStack(spacing: 12) {
                            Button("A–Z") { order = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"; applyOrder() }
                            Button("a–z") { order = "abcdefghijklmnopqrstuvwxyz"; applyOrder() }
                            Button("0–9") { order = "0123456789"; applyOrder() }
                            Spacer()
                            Text("Order: left to right, top to bottom").font(.caption2).foregroundStyle(.secondary)
                        }.buttonStyle(.plain).font(.caption)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("REVIEW \(scan?.regions.count ?? 0) REGIONS").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        ScrollViewReader { proxy in
                            ScrollView {
                                LazyVStack(spacing: 8) {
                                    if let scan {
                                        ForEach(Array(scan.regions.enumerated()), id: \.element.id) { index, region in
                                            regionRow(index: index, region: region, source: source).id(region.id)
                                        }
                                    }
                                }
                            }
                            .onChange(of: selectedRegion) { if let id = $0 { withAnimation { proxy.scrollTo(id, anchor: .center) } } }
                        }
                        Text("Recognition suggests labels only. Check I / l / 1, O / 0, dots, punctuation and counters.")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }.frame(width: 310)
                }.frame(minHeight: 270, maxHeight: .infinity)
                if let notice = scan?.notices.joined(separator: " "), !notice.isEmpty {
                    Text(notice).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    Text("Import into")
                    Picker("Destination", selection: $useCurrentProject) {
                        Text("New project").tag(false)
                        if let currentProject { Text(currentProject.name).tag(true) }
                    }.labelsHidden().frame(maxWidth: 280)
                    if !useCurrentProject { TextField("Project name", text: $name).textFieldStyle(.roundedBorder) }
                    else if conflicts > 0 { Toggle("Replace \(conflicts) existing glyphs", isOn: $replace).toggleStyle(.checkbox) }
                }.font(.subheadline)
                if useCurrentProject && conflicts > 0 && !replace {
                    Text("Existing artwork will be kept; \(conflicts) assigned glyphs will be skipped.").font(.caption).foregroundStyle(.secondary)
                }
                Toggle("I checked the regions, character labels, and traced shapes.", isOn: $reviewed).toggleStyle(.checkbox).font(.caption)
            } else {
                VStack(spacing: 15) {
                    Image(systemName: "doc.viewfinder").font(.system(size: 48)).foregroundStyle(.secondary)
                    Text("Your drawings → editable glyphs").font(.title2)
                    Text("PNG · JPEG · TIFF · HEIC · SVG · Procreate").font(.subheadline)
                    Text("Use clear, separated letters on a plain or transparent background. Sheets may contain multiple rows. Grid mode handles regular worksheets; you can also draw your own letter boxes.")
                        .multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: 500)
                    Text("Procreate files use their embedded flattened preview. Export PNG from Procreate for full resolution. SVG text and effects should be converted to outlines first.")
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 500)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if !failure.isEmpty { Text(failure).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
            HStack {
                if busy { ProgressView().controlSize(.small); Text("Reading artwork and tracing letters…").font(.caption) }
                else if settingsChanged { Text("Settings changed. Rescan before importing.").font(.caption).foregroundStyle(.secondary) }
                else if scan != nil { Text("\(included.count) selected · \(invalidAssignments ? "Review missing or duplicate labels" : "Labels ready")").font(.caption).foregroundStyle(.secondary) }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Import \(included.count) glyphs") { commit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(busy || settingsChanged || invalidAssignments || !reviewed || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(22).frame(width: 1040, height: 780)
        .onChange(of: options) { _ in reviewed = false }
        .onChange(of: useCurrentProject) { _ in reviewed = false; replace = false }
        .onChange(of: replace) { _ in reviewed = false }
        .interactiveDismissDisabled(busy)
    }

    private var scanControls: some View {
        HStack(spacing: 12) {
            Picker("Layout", selection: $options.layout) { ForEach(FontLabArtworkLayout.allCases) { Text($0.rawValue).tag($0) } }.frame(width: 205)
            if options.layout == .grid {
                Stepper("\(options.columns) columns", value: $options.columns, in: 1...32).frame(width: 120)
                Stepper("\(options.rows) rows", value: $options.rows, in: 1...32).frame(width: 100)
            }
            Toggle("Light ink", isOn: $options.lightInk).toggleStyle(.checkbox)
            VStack(alignment: .leading, spacing: 2) {
                Text("Ink threshold \(Int(options.threshold * 100))%").font(.caption)
                Slider(value: $options.threshold, in: 0.05...0.95).frame(width: 120)
            }
            Picker("Specks", selection: $options.minimumArea) {
                Text("Keep detail").tag(1); Text("Remove tiny specks").tag(5); Text("Clean scan").tag(20); Text("Heavy cleanup").tag(80)
            }.frame(width: 180)
            Spacer(minLength: 0)
            Button("Rescan") { rescan() }.disabled(busy)
        }.font(.caption).disabled(busy)
    }

    private func regionRow(index: Int, region: FontLabArtworkRegion, source: FontLabArtworkSource) -> some View {
        HStack(spacing: 8) {
            Toggle("Include region \(index + 1)", isOn: Binding(get: { region.included }, set: { value in mutate(region.id) { $0.included = value } }))
                .labelsHidden().toggleStyle(.checkbox)
            FontLabArtworkShapePreview(contours: region.contours, aspectRatio: region.rect.width / region.rect.height)
                .frame(width: 66, height: 68).background(.white, in: RoundedRectangle(cornerRadius: 5))
                .onTapGesture { selectedRegion = region.id }
                .accessibilityLabel("Traced region \(index + 1)")
            VStack(alignment: .leading, spacing: 3) {
                Text("Region \(index + 1)").font(.caption2).foregroundStyle(.secondary)
                TextField("Letter", text: Binding(get: { region.character }, set: { value in mutate(region.id) { $0.character = String(value.prefix(1)); $0.confidence = 1 } }))
                    .textFieldStyle(.roundedBorder).frame(width: 64).accessibilityLabel("Character for region \(index + 1)")
                Text(region.character.isEmpty ? "Assign a letter" : region.confidence < 0.75 ? "Check label" : "Review shape")
                    .font(.caption2).foregroundStyle(region.confidence < 0.75 ? .orange : .secondary)
            }
            Spacer(minLength: 0)
            Button { scan?.regions.removeAll { $0.id == region.id }; reviewed = false } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain).help("Remove region \(index + 1)")
        }
        .padding(7).background(selectedRegion == region.id ? Color.accentColor.opacity(0.13) : Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
    }

    private func mutate(_ id: UUID, _ change: (inout FontLabArtworkRegion) -> Void) {
        guard let index = scan?.regions.firstIndex(where: { $0.id == id }) else { return }
        change(&scan!.regions[index]); reviewed = false
    }

    private func chooseFile() {
        let panel = NSOpenPanel(); panel.title = "Import letter artwork"; panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
        panel.allowedContentTypes = FontLabImportFormat.allCases.flatMap { $0.filenameExtensions.compactMap { UTType(filenameExtension: $0) } }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        busy = true; failure = ""; reviewed = false
        let requestedOptions = options
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                Result {
                    let loaded = try FontLabArtworkReader.load(url)
                    return (loaded, Result { try FontLabArtworkEngine.scan(loaded, options: requestedOptions) })
                }
            }.value
            await MainActor.run {
                busy = false
                switch result {
                case let .success((loaded, scanResult)):
                    source = loaded; scan = nil; scannedOptions = nil; selectedRegion = nil
                    name = String(url.deletingPathExtension().lastPathComponent.prefix(200))
                    switch scanResult {
                    case var .success(value):
                        if requestedOptions.layout == .single, !value.regions.isEmpty { value.regions[0].character = selectedCharacter; useCurrentProject = currentProject != nil }
                        scan = value; scannedOptions = requestedOptions; selectedRegion = value.regions.first?.id
                    case let .failure(error): failure = error.localizedDescription
                    }
                case let .failure(error): failure = error.localizedDescription
                }
            }
        }
    }

    private func rescan() {
        guard let source else { return }
        busy = true; failure = ""; reviewed = false
        let requestedOptions = options
        Task {
            let result = await Task.detached(priority: .userInitiated) { Result { try FontLabArtworkEngine.scan(source, options: requestedOptions) } }.value
            await MainActor.run {
                busy = false
                switch result {
                case var .success(value):
                    if requestedOptions.layout == .single, !value.regions.isEmpty { value.regions[0].character = selectedCharacter; useCurrentProject = currentProject != nil }
                    scan = value; scannedOptions = requestedOptions; selectedRegion = value.regions.first?.id
                case let .failure(error): scan = nil; scannedOptions = nil; failure = error.localizedDescription
                }
            }
        }
    }

    private func applyOrder() {
        let letters = order.filter { !$0.isWhitespace }.map(String.init)
        let includedIndices = scan?.regions.indices.filter { scan!.regions[$0].included } ?? []
        guard letters.count == includedIndices.count else { failure = "Enter exactly \(includedIndices.count) characters, one for each included region. Spaces and line breaks are ignored."; return }
        for (index, character) in zip(includedIndices, letters) { scan!.regions[index].character = character; scan!.regions[index].confidence = 1 }
        failure = ""; reviewed = false
    }

    private func addRegion(_ rect: CGRect) {
        guard let mask = scan?.mask, var region = FontLabArtworkEngine.region(rect: rect, mask: mask), (scan?.regions.count ?? 0) < 256 else { return }
        if options.layout == .single { region.character = selectedCharacter }
        scan?.regions.append(region)
        if let value = scan {
            let order = FontLabArtworkEngine.readingOrder(value.regions.map(\.rect))
            scan?.regions.sort { (order.firstIndex(of: $0.rect) ?? 0) < (order.firstIndex(of: $1.rect) ?? 0) }
        }
        selectedRegion = region.id; reviewed = false
    }

    private func commit() {
        guard let scan else { return }
        do {
            let original = useCurrentProject ? currentProject : nil
            let result = try FontLabArtworkEngine.project(from: scan, name: name, existing: original, replace: replace)
            if onImport(result, original) { dismiss() }
            else { failure = "The project changed or could not be saved. Your existing artwork was kept." }
        } catch { failure = error.localizedDescription }
    }
}

struct FontLabArtworkShapePreview: View {
    let contours: [[FontLabPoint]]
    let aspectRatio: Double
    var body: some View {
        Canvas { context, size in
            let height = min(size.height - 12, (size.width - 12) / max(0.02, aspectRatio))
            let width = height * aspectRatio, x = (size.width - width) / 2, y = (size.height - height) / 2
            var path = Path()
            for contour in contours {
                guard let first = contour.first else { continue }
                path.move(to: CGPoint(x: x + first.x * width, y: y + (1 - first.y) * height))
                for point in contour.dropFirst() { path.addLine(to: CGPoint(x: x + point.x * width, y: y + (1 - point.y) * height)) }
                path.closeSubpath()
            }
            context.fill(path, with: .color(.black))
        }
    }
}

private struct FontLabArtworkRegionCanvas: NSViewRepresentable {
    let image: CGImage
    let regions: [FontLabArtworkRegion]
    let selected: UUID?
    let select: (UUID) -> Void
    let add: (CGRect) -> Void
    func makeNSView(context: Context) -> FontLabArtworkRegionNSView { FontLabArtworkRegionNSView() }
    func updateNSView(_ view: FontLabArtworkRegionNSView, context: Context) {
        view.image = image; view.regions = regions; view.selected = selected; view.select = select; view.add = add; view.needsDisplay = true
    }
}

private final class FontLabArtworkRegionNSView: NSView {
    var image: CGImage?
    var regions: [FontLabArtworkRegion] = []
    var selected: UUID?
    var select: ((UUID) -> Void)?
    var add: ((CGRect) -> Void)?
    var dragStart: CGPoint?
    var dragEnd: CGPoint?
    override var isFlipped: Bool { true }
    private var imageRect: CGRect {
        guard let image else { return .zero }
        let scale = min((bounds.width - 16) / Double(image.width), (bounds.height - 16) / Double(image.height))
        return CGRect(x: (bounds.width - Double(image.width) * scale) / 2, y: (bounds.height - Double(image.height) * scale) / 2,
            width: Double(image.width) * scale, height: Double(image.height) * scale)
    }
    private func displayedRect(_ rect: CGRect) -> CGRect {
        guard let image else { return .zero }
        let target = imageRect
        return CGRect(x: target.minX + rect.minX / Double(image.width) * target.width, y: target.minY + rect.minY / Double(image.height) * target.height,
            width: rect.width / Double(image.width) * target.width, height: rect.height / Double(image.height) * target.height)
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill(); bounds.fill()
        guard let image else { return }
        for row in 0...Int(imageRect.height / 16) {
            for column in 0...Int(imageRect.width / 16) where (row + column) % 2 == 0 {
                NSColor(calibratedWhite: 0.87, alpha: 1).setFill()
                CGRect(x: imageRect.minX + Double(column * 16), y: imageRect.minY + Double(row * 16), width: 16, height: 16).intersection(imageRect).fill()
            }
        }
        NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height)).draw(in: imageRect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        for (index, region) in regions.enumerated() {
            let rect = displayedRect(region.rect)
            let color = region.included ? (region.id == selected ? NSColor.systemOrange : NSColor.systemBlue) : NSColor.gray
            color.setStroke(); let path = NSBezierPath(rect: rect.insetBy(dx: -2, dy: -2)); path.lineWidth = region.id == selected ? 2.5 : 1; path.stroke()
            ("\(index + 1) \(region.character)" as NSString).draw(at: NSPoint(x: rect.minX, y: max(0, rect.minY - 16)), withAttributes: [.font: NSFont.systemFont(ofSize: 11, weight: .semibold), .foregroundColor: color, .backgroundColor: NSColor.white])
        }
        if let a = dragStart, let b = dragEnd {
            NSColor.systemOrange.setStroke(); NSBezierPath(rect: CGRect(x: min(a.x,b.x), y: min(a.y,b.y), width: abs(b.x-a.x), height: abs(b.y-a.y))).stroke()
        }
    }
    override func mouseDown(with event: NSEvent) { dragStart = convert(event.locationInWindow, from: nil); dragEnd = nil }
    override func mouseDragged(with event: NSEvent) { dragEnd = convert(event.locationInWindow, from: nil); needsDisplay = true }
    override func mouseUp(with event: NSEvent) {
        defer { dragStart = nil; dragEnd = nil; needsDisplay = true }
        guard let start = dragStart, let image else { return }
        let end = convert(event.locationInWindow, from: nil)
        if hypot(end.x-start.x, end.y-start.y) < 5 {
            if let region = regions.first(where: { displayedRect($0.rect).insetBy(dx: -3, dy: -3).contains(end) }) { select?(region.id) }
            return
        }
        let rect = CGRect(x: min(start.x,end.x), y: min(start.y,end.y), width: abs(start.x-end.x), height: abs(start.y-end.y)).intersection(imageRect)
        guard !rect.isNull, rect.width > 2, rect.height > 2 else { return }
        add?(CGRect(x: (rect.minX-imageRect.minX)/imageRect.width*Double(image.width), y: (rect.minY-imageRect.minY)/imageRect.height*Double(image.height), width: rect.width/imageRect.width*Double(image.width), height: rect.height/imageRect.height*Double(image.height)))
    }
}
