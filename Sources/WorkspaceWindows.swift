import AppKit
import SwiftUI
import UniformTypeIdentifiers

private struct WindowWorkspaceKey: EnvironmentKey { static let defaultValue: WorkspaceMode? = nil }
extension EnvironmentValues {
    var windowWorkspace: WorkspaceMode? {
        get { self[WindowWorkspaceKey.self] }
        set { self[WindowWorkspaceKey.self] = newValue }
    }
}

/// A font drag carries a PostScript name, never a file path or arbitrary text.
enum FontDragPayload {
    static let contentType = UTType(exportedAs: "app.typefield.font-name", conformingTo: .data)
    static let type = NSPasteboard.PasteboardType(contentType.identifier)
    static let prefix = "typefield-font:"
    static func trace(_ message: String) {
        if CommandLine.arguments.contains("--window-qa") { fputs("Window QA: " + message + "\n", stderr) }
    }
    static func provider(_ name: String) -> NSItemProvider {
        trace("Drag font " + name)
        let provider = NSItemProvider(object: (prefix + name) as NSString)
        provider.registerDataRepresentation(forTypeIdentifier: type.rawValue, visibility: .ownProcess) { completion in
            completion(Data(name.utf8), nil)
            return nil
        }
        return provider
    }
    static func read(_ pasteboard: NSPasteboard) -> String? {
        if let data = pasteboard.data(forType: type) {
            guard data.count <= 1024, let name = String(data: data, encoding: .utf8), !name.isEmpty else { return nil }
            return name
        }
        guard let text = pasteboard.string(forType: .string), text.hasPrefix(prefix) else { return nil }
        let name = String(text.dropFirst(prefix.count))
        return !name.isEmpty && name.utf8.count <= 1024 ? name : nil
    }
}

/// There is exactly one live view for each editor. Detaching reparents that view,
/// rather than making a second writer with a stale project snapshot.
final class WorkspaceWindows: NSObject, ObservableObject, NSWindowDelegate {
    let library: Library
    @Published private(set) var detached: Set<WorkspaceMode> = []
    let fontLabSession = FontLabEditorSession()
    private var controllers: [WorkspaceMode: NSViewController] = [:]
    private var hosts: [WorkspaceMode: NSView] = [:]
    private var containers: [WorkspaceMode: NSView] = [:]
    private var editors: [WorkspaceMode: NSWindow] = [:]
    private var browsers: [NSWindow] = []
    init(library: Library) { self.library = library }

    func mode(for window: NSWindow?) -> WorkspaceMode? {
        editors.first { $0.value === window }?.key
    }
    func isBrowser(_ window: NSWindow?) -> Bool { browsers.contains { $0 === window } }
    func host(_ mode: WorkspaceMode) -> NSView {
        if let host = hosts[mode] { return host }
        let controller = NSHostingController(rootView: EditorWindowRoot(library: library, windows: self, fontLabSession: fontLabSession, mode: mode).typefieldLocalized())
        let container = NSView()
        controller.view.frame = container.bounds
        controller.view.autoresizingMask = [.width, .height]
        container.addSubview(controller.view)
        controllers[mode] = controller
        hosts[mode] = container
        return container
    }
    func mount(_ mode: WorkspaceMode, in container: NSView) {
        containers[mode] = container
        guard !detached.contains(mode) else { return }
        attach(host(mode), to: container)
    }
    private func attach(_ view: NSView, to container: NSView) {
        guard view.superview !== container else { return }
        view.removeFromSuperview()
        view.frame = container.bounds
        view.autoresizingMask = [.width, .height]
        container.addSubview(view)
    }
    func detach(_ mode: WorkspaceMode, at point: NSPoint? = nil) {
        guard mode != .library else { openBrowser(); return }
        if let window = editors[mode] { window.makeKeyAndOrderFront(nil); return }
        if mode == .fontLab { fontLabSession.focusEditor = true }
        let view = host(mode)
        guard view.window?.attachedSheet == nil else { return }
        view.window?.makeFirstResponder(nil)
        let window = makeWindow(title: "Typefield: " + mode.rawValue, size: NSSize(width: 1240, height: 850), minimum: NSSize(width: 980, height: 660))
        editors[mode] = window
        detached.insert(mode)
        view.removeFromSuperview()
        window.contentView = view
        if let point { window.setFrameTopLeftPoint(point) }
        window.makeKeyAndOrderFront(nil)
    }
    func dock(_ mode: WorkspaceMode) {
        guard let window = editors[mode], window.attachedSheet == nil else { return }
        window.makeFirstResponder(nil)
        window.contentView = NSView()
        editors.removeValue(forKey: mode)
        window.close()
        detached.remove(mode)
        library.workspace = mode
        if let container = containers[mode] { attach(host(mode), to: container) }
        (NSApp.delegate as? AppDelegate)?.window.makeKeyAndOrderFront(nil)
    }
    func openBrowser(scope: String = "All Fonts") {
        let window = makeWindow(title: "Typefield: Font Browser", size: NSSize(width: 520, height: 720), minimum: NSSize(width: 360, height: 360))
        let host = NSHostingView(rootView: FontBrowserWindow(library: library, initialScope: scope).typefieldLocalized())
        host.sizingOptions = []
        window.contentView = host
        browsers.append(window)
        window.makeKeyAndOrderFront(nil)
    }
    private func makeWindow(title: String, size: NSSize, minimum: NSSize) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = title
        window.minSize = minimum
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.fullScreenPrimary]
        window.tabbingMode = .disallowed
        window.delegate = self
        window.center()
        if let source = NSApp.keyWindow { window.cascadeTopLeft(from: NSPoint(x: source.frame.minX + 28, y: source.frame.maxY - 28)) }
        return window
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if let mode = mode(for: sender) { dock(mode); return false }
        return true
    }
    func windowWillClose(_ notification: Notification) {
        browsers.removeAll { $0 === notification.object as? NSWindow }
    }
}

struct WorkspaceMount: NSViewRepresentable {
    let windows: WorkspaceWindows
    let mode: WorkspaceMode
    func makeNSView(context: Context) -> NSView { let view = NSView(); windows.mount(mode, in: view); return view }
    func updateNSView(_ view: NSView, context: Context) { windows.mount(mode, in: view) }
}

struct WorkspaceEditorSlot: View {
    @ObservedObject var windows: WorkspaceWindows
    let mode: WorkspaceMode
    var body: some View {
        if windows.detached.contains(mode) {
            VStack(spacing: 16) {
                Image(systemName: "macwindow.on.rectangle").font(.largeTitle)
                Text(mode.rawValue + " is in its own window").font(.title2)
                HStack {
                    Button("Show window") { windows.detach(mode) }
                    Button("Bring back here") { windows.dock(mode) }
                    Button("Browse fonts") { windows.library.workspace = .library }
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else { WorkspaceMount(windows: windows, mode: mode) }
    }
}

private struct EditorWindowRoot: View {
    @ObservedObject var library: Library
    @ObservedObject var windows: WorkspaceWindows
    @ObservedObject var fontLabSession: FontLabEditorSession
    let mode: WorkspaceMode
    @AppStorage(WorkspaceSidebarPreference.key) private var collapsed = false
    @State private var focusCanvas = false
    @AppStorage("appearance") private var appearance = "Dark"
    @AppStorage("typefield.palette") private var palette = "neutral"
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var editorToolbar: some View {
        HStack(spacing: 8) {
            Menu("View") {
                if mode == .fontLab {
                    Toggle("Focus editor", isOn: $fontLabSession.focusEditor)
                    Toggle("Show characters", isOn: $fontLabSession.showCharacters)
                        .disabled(!fontLabSession.focusEditor)
                    Toggle("Show metrics & spacing", isOn: $fontLabSession.compactMetricsExpanded)
                    Divider()
                }
                if mode == .spaces {
                    Menu("Inspector") {
                        Button("Tools & inspector") { NotificationCenter.default.post(name: Notification.Name("TypefieldMenu"), object: "studio.inspector.full") }
                        Button("Tools only") { NotificationCenter.default.post(name: Notification.Name("TypefieldMenu"), object: "studio.inspector.slim") }
                        Button("Hide tools & inspector") { NotificationCenter.default.post(name: Notification.Name("TypefieldMenu"), object: "studio.inspector.hidden") }
                        Button("Float inspector") { NotificationCenter.default.post(name: Notification.Name("TypefieldMenu"), object: "studio.inspector.floating") }
                    }
                    Button("Toggle canvas focus") { NotificationCenter.default.post(name: Notification.Name("TypefieldMenu"), object: "studio.canvasFocus") }
                    Divider()
                }
                Button("Open font browser…") { windows.openBrowser() }
                Button(windows.detached.contains(mode) ? "Dock window" : "Pop out editor") {
                    if windows.detached.contains(mode) { windows.dock(mode) } else { windows.detach(mode) }
                }
            }
            .menuStyle(.borderlessButton).fixedSize()
            .help("Editor layout, font browser and window options")
            .accessibilityLabel("Workspace view")
        }
        .accessibilityIdentifier("workspace-editor-controls")
    }

    var body: some View {
        Group {
            ZStack(alignment: .topLeading) {
                if mode == .spaces { StudioView(library: library, store: library.studio, sidebarCollapsed: $collapsed, focusCanvas: $focusCanvas, editorToolbar: AnyView(editorToolbar)) }
                else { FontLabView(library: library, sidebarCollapsed: $collapsed, session: fontLabSession, editorToolbar: AnyView(editorToolbar)) }
                if collapsed && !focusCanvas && !(mode == .fontLab && fontLabSession.focusEditor) { WorkspaceSidebarRevealButton(collapsed: $collapsed).padding(.top, 8) }
            }
        }
        .environment(\.windowWorkspace, mode)
        .background(ShelfPalette.canvas)
        .tint(Color(nsColor: TypefieldPalette.resolve(palette).accent(dark: appearance == "Dark" || (appearance == "System" && scheme == .dark))))
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("TypefieldMenu"))) { event in
            guard (NSApp.delegate as? AppDelegate)?.activeWorkspace == mode, event.object as? String == "toggleSidebar" else { return }
            if mode == .spaces && focusCanvas { NotificationCenter.default.post(name: Notification.Name("TypefieldCanvasFocus"), object: nil) }
            else { withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { collapsed.toggle() } }
        }
    }
}

struct FontBrowserWindow: View {
    @ObservedObject var library: Library
    @State private var scope: String
    @State private var search = ""
    @State private var preview = "Hamburgefontsiv"
    @State private var styles: [String: String] = [:]
    init(library: Library, initialScope: String) { self.library = library; _scope = State(initialValue: initialScope) }
    private var families: [Family] {
        library.families.filter { family in
            let inScope: Bool
            if scope == "Shortlist" { inScope = library.comparison.contains(family.name) }
            else if scope.hasPrefix("folder:") { inScope = family.faces.contains { face in face.url.map { FontFolderSnapshot.contains($0.path, root: String(scope.dropFirst(7))) } ?? false } }
            else { inScope = library.matchesSection(family, scope) }
            return inScope && (search.isEmpty || family.name.localizedCaseInsensitiveContains(search) || family.faces.contains { $0.name.localizedCaseInsensitiveContains(search) })
        }
    }
    var body: some View {
        VStack(spacing: 12) {
            Picker("Fonts", selection: $scope) {
                Text("All fonts").tag("All Fonts")
                Text("Shortlist").tag("Shortlist")
                Text("Favorites").tag("Favorites")
                ForEach(library.saved.collections.keys.sorted(), id: \.self) { Text($0).tag("collection:" + $0) }
                ForEach(library.saved.folders, id: \.self) { Text(URL(fileURLWithPath: $0).lastPathComponent).tag("folder:" + $0) }
            }
            TextField("Find fonts", text: $search).textFieldStyle(.roundedBorder)
            TextField("Preview text", text: $preview).textFieldStyle(.roundedBorder)
            Text("Drag a preview onto text in a Space to change its font.").font(.caption).foregroundStyle(.secondary)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(families) { family in
                        let face = family.faces.first { $0.name == styles[family.name] } ?? library.chosenFace(family)
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(family.name).font(.headline)
                                Spacer()
                                Button { library.compare(family) } label: { Image(systemName: library.comparison.contains(family.name) ? "checkmark.circle.fill" : "plus.circle") }.buttonStyle(.plain).help("Toggle shortlist")
                            }
                            Picker("Style", selection: Binding(get: { face.name }, set: { styles[family.name] = $0 })) {
                                ForEach(family.faces) { Text($0.style).tag($0.name) }
                            }
                            Text(preview.isEmpty ? family.name : preview).font(.custom(face.name, size: 36)).frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle()).onDrag { FontDragPayload.provider(face.name) }
                                .help("Drag this font onto text in a Space")
                        }.padding(12).background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                    }
                    if families.isEmpty { Text("No fonts match this view.").foregroundStyle(.secondary).padding() }
                }
            }
        }.padding(16).background(ShelfPalette.canvas)
    }
}

/// Uses the same scope as the typography inspector: one template role, or one
/// imported text layer. Text, positions, sizing and other roles are preserved.
enum StudioFontDrop {
    static func applying(_ name: String, to direction: TypeDirection, element: CanvasElement,
                         axes: [Int: Double] = [:], features: [String: Int] = [:]) -> TypeDirection? {
        var result = direction
        if let index = direction.objectLayers?.firstIndex(where: { $0.id == element.sectionID }), var style = direction.objectLayers?[index].style {
            style.fontName = name; style.axes = axes; style.features = features
            result.objectLayers?[index].style = style
        } else if direction.canvas == .imported {
            guard let index = direction.importedLayout?.textLayerIndex(selectedID: element.sectionID),
                  var style = direction.importedLayout?.layers[index].style else { return nil }
            style.fontName = name; style.axes = axes; style.features = features
            result.importedLayout?.layers[index].style = style
        } else {
            guard let role = element.role, element.text != nil else { return nil }
            var style = direction.style(role)
            style.fontName = name; style.axes = axes; style.features = features
            result.styles[role.rawValue] = style
        }
        return result.isValid ? result : nil
    }
}


/// Run separately in a GUI session; all projects use a disposable store.
enum WorkspaceWindowChecks {
    static func run() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Typefield-window-check-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let library = Library(storageURL: folder.appendingPathComponent("library.json"))
        let windows = WorkspaceWindows(library: library)
        for mode in [WorkspaceMode.spaces, .fontLab] {
            let container = NSView(frame: NSRect(x: 0, y: 0, width: 1000, height: 700))
            windows.mount(mode, in: container)
            let host = windows.host(mode)
            precondition(host.superview === container)
            windows.detach(mode)
            let window = host.window!
            precondition(windows.mode(for: window) == mode && window.contentView === host)
            precondition(window.styleMask.contains(.resizable) && window.collectionBehavior.contains(.fullScreenPrimary))
            windows.detach(mode)
            precondition(host.window === window, "Repeated pop-out must not duplicate the editor")
            window.performClose(nil)
            precondition(!windows.detached.contains(mode) && host.superview === container, "Closing must dock the same editor")
            windows.detach(mode)
            windows.dock(mode)
            precondition(windows.host(mode) === host && host.superview === container)
        }
        windows.openBrowser(scope: "Shortlist")
        let first = app.windows.first { windows.isBrowser($0) }!
        windows.openBrowser(scope: "Favorites")
        precondition(app.windows.filter { windows.isBrowser($0) }.count == 2, "Font browser windows must coexist")
        first.performClose(nil)
        precondition(app.windows.filter { windows.isBrowser($0) }.count == 1, "Closing one browser must keep the other")
        for window in app.windows where windows.isBrowser(window) { window.close() }
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("Helvetica", forType: .string)
        precondition(FontDragPayload.read(pasteboard) == nil, "Plain text must not be accepted as a font")
        pasteboard.setData(Data("Helvetica".utf8), forType: FontDragPayload.type)
        precondition(FontDragPayload.read(pasteboard) == "Helvetica")
        pasteboard.setData(Data(repeating: 65, count: 1025), forType: FontDragPayload.type)
        precondition(FontDragPayload.read(pasteboard) == nil)
        print("PASS: editor host identity, detach/redock/close, resizable/fullscreen windows, independent browser lifetime, typed font payload")
    }
}
