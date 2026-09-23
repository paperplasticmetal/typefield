import SwiftUI
import AppKit
import CoreText
import UniformTypeIdentifiers

enum WorkspaceSidebarPreference {
    static let key = "workspaceSidebarCollapsed"
    static func collapsed(in defaults: UserDefaults = .standard) -> Bool { defaults.bool(forKey: key) }
    static func setCollapsed(_ value: Bool, in defaults: UserDefaults = .standard) { defaults.set(value, forKey: key) }
}
enum WorkspaceSidebarLayout {
    static let width = 232.0
    static let outerPadding = 12.0
    // Keep the collapsed affordance comfortably above Apple's 44-point
    // minimum target instead of reducing it to a small floating chevron.
    static let revealWidth = 52.0
    static let revealHeight = 64.0
    static func reservedWidth(collapsed: Bool) -> Double { collapsed ? 0 : width + outerPadding * 2 }
}
enum WorkspaceHeaderLayout {
    static let horizontalPadding = 20.0
    static let verticalPadding = 14.0
    static let titleSize = 22.0
    static let titleHeight = 30.0
    static let rowHeight = 40.0
}
struct WorkspaceSwitcher: View {
    @ObservedObject var library: Library
    var body: some View {
        VStack(spacing: 3) {
            ForEach(WorkspaceMode.allCases) { workspace in
                Button { library.workspace = workspace } label: {
                    Label(workspace.rawValue, systemImage: workspace == .library ? "textformat" : workspace == .spaces ? "square.stack.3d.up" : "pencil.and.outline")
                        .font(.system(size: 12, weight: library.workspace == workspace ? .semibold : .regular))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(library.workspace == workspace ? ShelfPalette.indiaYellow.opacity(0.16) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .accessibilityValue(library.workspace == workspace ? "Selected" : "")
                .help(workspace == .library ? "Browse and organize fonts" : workspace == .spaces ? "Explore typeboards and layouts" : "Draw and refine your own letters")
            }
        }.accessibilityIdentifier("workspace-switcher")
    }
}
struct WorkspaceSidebarHeader: View {
    @ObservedObject var library: Library
    @Binding var collapsed: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 30, height: 30).accessibilityHidden(true).accessibilityIdentifier("workspace-brand-mark")
                Text("Typefield").font(.headline).accessibilityIdentifier("workspace-brand-name")
                Spacer()
                Button {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { collapsed = true }
                } label: { Image(systemName: "sidebar.left") }
                    .buttonStyle(.plain).padding(7).contentShape(Rectangle())
                    .help("Hide sidebar").accessibilityLabel("Hide sidebar").accessibilityIdentifier("workspace-sidebar-hide")
            }
            WorkspaceSwitcher(library: library)
        }.padding(.horizontal, 12).padding(.top, 14).padding(.bottom, 12)
    }
}
struct WorkspaceSidebarShell<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        content.frame(width: WorkspaceSidebarLayout.width).environment(\.shelfInsideGlass, true).modifier(ShelfSidebarGlass()).padding(WorkspaceSidebarLayout.outerPadding).accessibilityIdentifier("workspace-sidebar")
    }
}
struct WorkspaceSidebarRevealButton: View {
    @Binding var collapsed: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var hovered = false
    var body: some View {
        Button {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { collapsed = false }
        } label: {
            VStack(spacing: 9) {
                Image(systemName: "sidebar.left").font(.system(size: 17, weight: .medium))
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold))
            }
            .frame(width: WorkspaceSidebarLayout.revealWidth, height: WorkspaceSidebarLayout.revealHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(ShelfPalette.ink)
        .background(
            reduceTransparency
                ? Color(nsColor: .controlBackgroundColor)
                : Color(nsColor: .windowBackgroundColor).opacity(hovered ? 0.96 : 0.82),
            in: WorkspaceSidebarEdgeShape()
        )
        .overlay(WorkspaceSidebarEdgeShape().stroke(Color.primary.opacity(hovered ? 0.24 : 0.13), lineWidth: 1))
        .shadow(color: .black.opacity(hovered ? 0.16 : 0.09), radius: hovered ? 8 : 5, x: 2, y: 2)
        .scaleEffect(hovered && !reduceMotion ? 1.025 : 1, anchor: .leading)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: hovered)
        .onHover { hovered = $0 }
        .help("Show sidebar (Control-Command-S)")
        .accessibilityLabel("Show sidebar")
        .accessibilityHint("Restores Library, Spaces, and Letterform Editor navigation. You can also press Control-Command-S.")
        .accessibilityIdentifier("workspace-sidebar-show")
    }
}

/// A pull-out tab whose square leading edge stays visually attached to the
/// window while its exposed edge has friendly rounded corners.
private struct WorkspaceSidebarEdgeShape: Shape {
    func path(in rect: CGRect) -> Path {
        let radius = min(15, rect.width, rect.height / 2)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + radius),
            control: CGPoint(x: rect.maxX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - radius, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
struct StudioView: View {
    @ObservedObject var library: Library
    @ObservedObject var store: StudioStore
    @Binding var sidebarCollapsed: Bool
    @State private var spaceID: UUID?
    @State private var boardID: UUID?
    @State private var newName = ""
    @State private var showNewSpace = false
    @State private var confirmDelete = false
    @State private var deletingBoard: (space: UUID, board: TypeBoard)?
    var space: DesignSpace? { store.state.spaces.first { $0.id == spaceID } ?? store.state.spaces.first }
    var board: TypeBoard? { space?.boards.first { $0.id == boardID } ?? space?.boards.first }
    var body: some View {
        HStack(spacing: 0) {
        if !sidebarCollapsed { WorkspaceSidebarShell { navigation }.transition(.move(edge: .leading).combined(with: .opacity)) }
        VStack(spacing: 0) {
            if !store.error.isEmpty { Text(store.error).foregroundStyle(.orange).textSelection(.enabled).padding(.horizontal, 20) }
            if let space {
                HStack(spacing: 12) {
                    ShelfEditableName(name: space.displayName, onRename: { setSpaceName(space.id, $0) })
                        .font(.system(size: WorkspaceHeaderLayout.titleSize, weight: .semibold))
                        .frame(minHeight: WorkspaceHeaderLayout.titleHeight)
                    Spacer()
                    Button("New typeboard") {
                        let fonts = library.compared.map { library.chosenFace($0).name }
                        if fonts.isEmpty { boardID = store.addBoard(space: space.id) }
                        else { library.pairSelection(fonts, source: "Shortlist", spaceID: space.id) }
                    }.disabled(store.readBlocked)
                    Menu {
                        Button("Rename space…") { renameSpace(space) }
                        Button("Import Figma typeboard…") { importFigma() }.disabled(store.readBlocked)
                        Button("Import Adobe return JSON…") { importAdobe() }.disabled(store.readBlocked)
                        Menu("Export Adobe return bridge") {
                            Button("Illustrator (.jsx)…") { exportAdobeReturnBridge(.illustrator) }
                            Button("InDesign (.jsx)…") { exportAdobeReturnBridge(.indesign) }
                        }
                        Button("Create font collection…") { createCollection(from: space) }.disabled(space.boards.isEmpty)
                        Button("Developer handoff…") { exportHandoff(space) }.disabled(space.boards.isEmpty)
                        Button("Export space…") { exportSpace(space) }
                        Button("Import space…") { importSpace() }.disabled(store.readBlocked)
                        Divider()
                        Button("Delete space…", role: .destructive) { confirmDelete = true }
                    } label: { Image(systemName: "ellipsis") }.shelfIconMenu().help("Space actions").accessibilityLabel("Space actions")
                }
                .frame(minHeight: WorkspaceHeaderLayout.rowHeight)
                .padding(.horizontal, WorkspaceHeaderLayout.horizontalPadding)
                .padding(.vertical, WorkspaceHeaderLayout.verticalPadding)
                .padding(.leading, sidebarCollapsed ? WorkspaceSidebarLayout.revealWidth + 8 : 0)
                .fixedSize(horizontal: false, vertical: true)
                Divider()
                if let board {
                    TypeBoardEditor(library: library, savedBoard: board, projectName: space.displayName, projectBoards: space.boards, onSave: { store.update(space: space.id, board: $0, action: $1) }, onDelete: {
                        store.removeBoard(space: space.id, id: board.id); boardID = store.focusedBoard
                    }).id(board.id)
                } else {
                    VStack(spacing: 14) { Image(systemName: "rectangle.3.group").font(.system(size: 38)); Text("No typeboards").font(.title2); Button("Create typeboard") { boardID = store.addBoard(space: space.id) }.disabled(store.readBlocked) }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "rectangle.3.group").font(.system(size: 42)).foregroundStyle(.secondary)
                    Text("Create a space").font(.title2)
                    Text("A space holds your project's typeboards. Each typeboard can contain several canvases to explore and compare.").foregroundStyle(.secondary)
                    HStack { Button("New space") { showNewSpace = true }; Button("Import space…") { importSpace() } }.disabled(store.readBlocked)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }.accessibilityIdentifier("spaces-workspace") }
        .onAppear { if let id = store.focusedSpace { spaceID = id }; if let id = store.focusedBoard { boardID = id } }
        .onChange(of: store.focusedSpace) { id in spaceID = id; boardID = store.focusedBoard }
        .onChange(of: store.focusedBoard) { id in spaceID = store.focusedSpace; boardID = id }
        .alert("New space", isPresented: $showNewSpace) {
            TextField("Project or client name", text: $newName)
            Button("Create") {
                let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                if let created = store.addSpace(name) {
                    spaceID = created
                    let fonts = library.compared.map { library.chosenFace($0).name }
                    if fonts.isEmpty { boardID = store.addBoard(space: created) }
                    else { DispatchQueue.main.async { library.pairSelection(fonts, source: "Shortlist", spaceID: created) } }
                }
                newName = ""
            }
            Button("Cancel", role: .cancel) { newName = "" }
        }
        .alert("Delete this space and its typeboards?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) { if let space { store.state.spaces.removeAll { $0.id == space.id }; store.focusedSpace = nil; store.focusedBoard = nil; store.save(); spaceID = nil; boardID = nil } }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Delete “\(deletingBoard?.board.name ?? "typeboard")”?", isPresented: Binding(get: { deletingBoard != nil }, set: { if !$0 { deletingBoard = nil } })) {
            Button("Delete", role: .destructive) { if let target = deletingBoard { store.removeBoard(space: target.space, id: target.board.id); if boardID == target.board.id { boardID = store.focusedBoard } }; deletingBoard = nil }
            Button("Cancel", role: .cancel) { deletingBoard = nil }
        } message: { Text("Its canvases will be removed from this space. You can undo this with ⌘Z.") }
    }
    var navigation: some View {
        VStack(alignment: .leading, spacing: 6) {
            WorkspaceSidebarHeader(library: library, collapsed: $sidebarCollapsed)
            VStack(alignment: .leading, spacing: 14) {
                HStack { Text("SPACES").font(.caption).foregroundStyle(.secondary); Spacer(); Button { showNewSpace = true } label: { Image(systemName: "plus") }.help("New space").disabled(store.readBlocked) }
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                    ForEach(store.state.spaces) { item in
                        HStack(spacing: 8) {
                            Button { selectSpace(item.id) } label: { Image(systemName: "rectangle.3.group") }.buttonStyle(.plain).accessibilityLabel("Open " + item.displayName)
                            ShelfEditableName(name: item.displayName, selected: space?.id == item.id, onSelect: { selectSpace(item.id) }, onRename: { setSpaceName(item.id, $0) })
                        }.fontWeight(.medium).padding(10).background(space?.id == item.id ? Color.accentColor.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 8)).contextMenu { Button("Rename space…") { renameSpace(item) } }
                        ForEach(item.boards) { child in
                            StudioBoardRow(name: child.name, selected: board?.id == child.id, onSelect: { spaceID = item.id; boardID = child.id; store.focusedSpace = item.id; store.focusedBoard = child.id; store.save() }, onRename: {
                                if let name = ShelfRename.prompt("Rename typeboard", current: child.name) { var renamed = child; renamed.name = name; store.update(space: item.id, board: renamed, action: "Rename Typeboard") }
                            }, onRenameInline: { name in var renamed = child; renamed.name = name; store.update(space: item.id, board: renamed, action: "Rename Typeboard"); return true }, onDelete: { deletingBoard = (item.id, child) })
                        }
                    }
                    }
                }
                Menu("Import…") {
                    Button("Space…") { importSpace() }.disabled(store.readBlocked)
                    Button("Figma typeboard JSON…") { importFigma() }.disabled(store.readBlocked)
                    Button("Using a native .fig file…") { figFileHelp() }
                    Divider()
                    Button("Adobe return JSON…") { importAdobe() }.disabled(store.readBlocked)
                    Menu("Export Adobe return bridge") {
                        Button("Illustrator (.jsx)…") { exportAdobeReturnBridge(.illustrator) }
                        Button("InDesign (.jsx)…") { exportAdobeReturnBridge(.indesign) }
                    }
                }.menuStyle(.borderlessButton).fixedSize().padding(.bottom, 12)
            }.padding(.horizontal, 12)
        }
    }
    func renameSpace(_ target: DesignSpace) {
        if let name = ShelfRename.prompt("Rename space", current: target.displayName) { _ = setSpaceName(target.id, name) }
    }
    func selectSpace(_ id: UUID) { spaceID = id; boardID = nil; store.focusedSpace = id; store.focusedBoard = nil; store.save() }
    func setSpaceName(_ id: UUID, _ name: String) -> Bool { guard let index = store.state.spaces.firstIndex(where: { $0.id == id }) else { return false }; store.state.spaces[index].name = name; store.save(); return true }
    func exportHandoff(_ space: DesignSpace) {
        do { if let folder = try DeveloperHandoff.selectFolder(title: space.displayName, boards: space.boards, catalog: library.families) { store.error = ""; NSWorkspace.shared.activateFileViewerSelecting([folder]) } }
        catch { store.error = "Handoff export failed: " + error.localizedDescription }
    }
    func createCollection(from space: DesignSpace) {
        let fontNames = StudioFontCollection.fontNames(in: space.boards)
        let families = library.familyNames(forPostScriptNames: fontNames)
        let unavailable = fontNames.subtracting(Set(library.allFaces.map(\.name))).count
        guard !families.isEmpty else { library.message = "This project does not use any fonts currently available in the Library."; return }
        guard let name = ShelfCollectionPrompt.prompt(suggestedName: space.displayName + " fonts", source: "the “" + space.displayName + "” project", count: families.count, unavailable: unavailable, validate: { library.saved.collections[$0] == nil ? nil : "A collection with this name already exists." }) else { return }
        switch library.createCollection(name, postScriptNames: fontNames) {
        case .created(let created, let count): library.message = "Created “\(created)” with \(count) font \(count == 1 ? "family" : "families"). It is ready in Library and in typeboard font filters."
        case .duplicateName: library.message = "A collection with that name already exists."
        case .noAvailableFonts: library.message = "None of the project's fonts are currently available in the Library."
        case .invalidName: library.message = "Enter a collection name."
        case .saveFailed: break
        }
    }
    func exportSpace(_ space: DesignSpace) {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "\(space.name).fontshelf.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try JSONEncoder().encode(space).write(to: url, options: .atomic) } catch { store.error = error.localizedDescription }
    }
    func importSpace() {
        guard !store.readBlocked else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            var space = try JSONDecoder().decode(DesignSpace.self, from: Data(contentsOf: url))
            guard space.boards.allSatisfy(\.isValid) else { throw CocoaError(.fileReadCorruptFile) }
            space.id = UUID()
            for i in space.boards.indices { space.boards[i].id = UUID(); space.boards[i].directions = space.boards[i].directions.map { $0.copy(name: $0.name) }; space.boards[i].selectedDirection = nil }
            store.state.spaces.append(space); store.focusedSpace = space.id; store.focusedBoard = nil; store.save(); spaceID = space.id; boardID = nil
        } catch { store.error = "Space could not be imported: " + error.localizedDescription }
    }
    func importFigma() {
        guard !store.readBlocked else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]
        panel.message = "In the Typefield Figma bridge, export selected frames to Typefield, then choose that JSON file. Native .fig files are not supported."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 20_000_000 else { throw CocoaError(.fileReadTooLarge) }
            let imported = try FigmaLayoutImporter.board(data: Data(contentsOf: url), fonts: library.allFaces)
            guard let target = space?.id ?? store.addSpace("Figma imports") else { return }
            guard let index = store.state.spaces.firstIndex(where: { $0.id == target }) else { return }
            store.state.spaces[index].boards.append(imported); store.focusedSpace = target; store.focusedBoard = imported.id; store.save(); spaceID = target; boardID = imported.id
        } catch { store.error = "Figma layout could not be imported: " + error.localizedDescription }
    }
    func importAdobe() {
        guard !store.readBlocked else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]
        panel.message = "Run Typefield's return bridge inside Illustrator or InDesign, save its JSON, then choose that file here. Native .ai and .indd files are not decoded directly."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 20_000_000 else { throw AdobeTypeSystemReturnBridge.ImportError.tooLarge }
            let imported = try AdobeTypeSystemReturnBridge.board(data: Data(contentsOf: url), fonts: library.allFaces)
            guard let target = space?.id ?? store.addSpace("Adobe imports") else { return }
            guard let index = store.state.spaces.firstIndex(where: { $0.id == target }) else { return }
            store.state.spaces[index].boards.append(imported)
            store.focusedSpace = target; store.focusedBoard = imported.id; store.save(); spaceID = target; boardID = imported.id
        } catch {
            store.error = "Adobe layout could not be imported: " + error.localizedDescription
        }
    }
    func exportAdobeReturnBridge(_ target: AdobeTypeSystemTarget) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: target.scriptExtension) ?? .plainText]
        panel.nameFieldStringValue = AdobeTypeSystemReturnBridge.suggestedScriptFilename(target: target)
        panel.message = "Run this bridge inside Adobe " + target.displayName + ". It exports the selection or document as JSON that Typefield can import."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try AdobeTypeSystemReturnBridge.data(target: target, scope: .prompt).write(to: url, options: .atomic)
            store.error = ""
        } catch {
            store.error = "Adobe return bridge could not be exported: " + error.localizedDescription
        }
    }
    func figFileHelp() {
        let alert = NSAlert(); alert.messageText = "Bring a .fig file into Typefield"
        alert.informativeText = "Direct .fig decoding is not available yet. Import your .fig file in Figma's file browser, run the Typefield Layout Importer plugin, select the frames you want and choose Export selected frames. Then import the saved JSON here.\n\nThis keeps supported text and shapes editable; review the bridge's notes for unsupported content."
        alert.addButton(withTitle: "OK"); alert.runModal()
    }
}

struct StudioBoardRow: View {
    let name: String
    let selected: Bool
    let onSelect: () -> Void
    let onRename: () -> Void
    let onRenameInline: (String) -> Bool
    let onDelete: () -> Void
    var body: some View {
        HStack(spacing: 6) {
            Button(action: onSelect) { Image(systemName: "rectangle.on.rectangle") }.buttonStyle(.plain).accessibilityLabel("Open " + name)
            ShelfEditableName(name: name, selected: selected, onSelect: onSelect, onRename: onRenameInline)
            Button(action: onDelete) { Image(systemName: "trash").frame(width: 28, height: 28).contentShape(Rectangle()) }.buttonStyle(.borderless).help("Delete " + name).accessibilityLabel("Delete " + name)
        }.font(.caption).padding(.leading, 16).padding(6).foregroundStyle(selected ? ShelfPalette.ink : Color.secondary)
            .background(selected ? Color.primary.opacity(0.05) : .clear, in: RoundedRectangle(cornerRadius: 6)).contentShape(Rectangle())
            .contextMenu { Button("Rename typeboard…", action: onRename); Button("Delete typeboard…", role: .destructive, action: onDelete) }
    }
}

enum CanvasVisibility {
    static func selecting(_ next: UUID, from current: UUID, shown: Set<UUID>) -> Set<UUID> { shown.union([current, next]) }
    static func solo(_ id: UUID) -> Set<UUID> { [id] }
    static func prune(_ shown: Set<UUID>, valid: Set<UUID>, selected: UUID?) -> Set<UUID> { shown.intersection(valid).union(selected.map { [$0] } ?? []) }
}

enum CanvasDragPayload {
    enum Source: Equatable { case section(String), role(TypeRole) }
    static func parse(_ value: String, directionID: UUID, sectionIDs: Set<String>, acceptsRoles: Bool) -> Source? {
        let prefix = directionID.uuidString + "|"
        guard value.hasPrefix(prefix) else { return nil }
        let payload = String(value.dropFirst(prefix.count))
        if payload.hasPrefix("role|") {
            guard acceptsRoles, let role = TypeRole(rawValue: String(payload.dropFirst(5))) else { return nil }
            return .role(role)
        }
        let id = payload.hasPrefix("section|") ? String(payload.dropFirst(8)) : payload
        return sectionIDs.contains(id) ? .section(id) : nil
    }
}

extension TypeDirection {
    var isValid: Bool {
        width.isFinite && (canvas == .imported ? (1...10000).contains(width) : (320...1600).contains(width)) && (importedLayout?.isValid ?? (canvas != .imported)) && (textOverrides.map { $0.count <= 5000 && $0.values.allSatisfy(Self.acceptsCanvasText) } ?? true) && (textPositions.map { $0.count <= 5000 && $0.values.allSatisfy(\.isValid) } ?? true) && TypeRole.allCases.allSatisfy { role in
            guard let s = styles[role.rawValue] else { return false }
            return s.size.isFinite && (8...160).contains(s.size) && s.leading.isFinite && (1...2.5).contains(s.leading) && s.tracking.isFinite && (-3...12).contains(s.tracking) && s.axes.values.allSatisfy(\.isFinite) && (s.lineHeight.map { $0.isFinite && (8...400).contains($0) } ?? true) && [s.paragraphSpacing, s.indent].allSatisfy { $0.map { $0.isFinite && (0...200).contains($0) } ?? true } && (s.wordSpacing.map { $0.isFinite && (-3...40).contains($0) } ?? true)
        }
    }
}

struct TypeBoardEditor: View {
    @ObservedObject var library: Library
    @State var board: TypeBoard
    let savedBoard: TypeBoard
    let projectName: String
    let projectBoards: [TypeBoard]
    let onSave: (TypeBoard, String) -> Void
    let onDelete: () -> Void
    init(library: Library, savedBoard: TypeBoard, projectName: String, projectBoards: [TypeBoard], onSave: @escaping (TypeBoard, String) -> Void, onDelete: @escaping () -> Void) {
        self.library = library; self.savedBoard = savedBoard; self.projectName = projectName; self.projectBoards = projectBoards; self.onSave = onSave; self.onDelete = onDelete
        _board = State(initialValue: savedBoard)
        let initialCanvasIDs = Set([savedBoard.selectedDirection ?? savedBoard.directions.first?.id].compactMap { $0 })
        _shownCanvasIDs = State(initialValue: initialCanvasIDs)
        _summaryCanvasIDs = State(initialValue: Set(savedBoard.directions.map(\.id)))
    }
    @State var role = TypeRole.display
    @State private var fontSearch = ""
    @State private var fontCollection = "All fonts"
    @State private var fontCategory = "All categories"
    @State private var shownCanvasIDs: Set<UUID>
    @State var selectedTextID: String?
    @State private var zoom = 0.0
    @State private var showDelete = false
    @State private var status = ""
    @State var showFontPicker = false
    @State private var showPairingSuggestions = false
    @State private var pairingTargetRole = TypeRole.body
    @State private var showFontSummary = false
    @State private var showWebFontAudit = false
    @State private var fontSummaryDetail = TypographySummaryDetail.roles
    @State private var summaryCanvasIDs: Set<UUID>
    @State private var draggedSection: String?
    @State var selectedSection: String?
    @State private var abID: UUID?
    @State private var inspectorTab = "Typography"
    @State private var discoveryNonce: UInt64 = 0
    @FocusState private var fontSearchFocused: Bool
    var directionIndex: Int { board.directions.firstIndex { $0.id == board.selectedDirection } ?? 0 }
    var direction: TypeDirection { board.directions[directionIndex] }
    var visibleDirections: [TypeDirection] { board.directions.filter { shownCanvasIDs.contains($0.id) || $0.id == direction.id } }
    var showingAllCanvases: Bool { !board.directions.isEmpty && Set(board.directions.map(\.id)).isSubset(of: shownCanvasIDs) }
    var importedLayerIndex: Int? { guard direction.canvas == .imported else { return nil }; return direction.importedLayout?.textLayerIndex(selectedID: selectedSection) }
    var importedNonTextSelected: Bool { direction.canvas == .imported && importedLayerIndex == nil }
    var selectedText: CanvasElement? { guard let selectedTextID else { return nil }; return CanvasPlanCache.plan(for: direction).elements.first { $0.textID == selectedTextID } }
    var style: TypeStyle { if let index = importedLayerIndex, let style = direction.importedLayout?.layers[index].style { return style }; return selectedText?.style ?? direction.style(role) }
    var selectedSummaryDirections: [TypeDirection] { board.directions.filter { summaryCanvasIDs.contains($0.id) } }
    var fontSummary: TypographySummaryDocument { TypographySummaryDocument(summaries: selectedSummaryDirections.map { CanvasTypographySummary(canvas: board.canvasName($0), direction: $0) }) }
    var visibleFontCount: Int { TypographySummaryDocument(summaries: visibleDirections.map { CanvasTypographySummary(canvas: board.canvasName($0), direction: $0) }).fonts.count }
    var editingTitle: String { if let index = importedLayerIndex { return direction.importedLayout?.layers[index].name ?? "Text layer" }; return role.rawValue }
    func setStyle(_ style: TypeStyle) {
        if direction.canvas == .imported && importedLayerIndex == nil { return }
        if let index = importedLayerIndex { board.directions[directionIndex].importedLayout?.layers[index].style = style }
        else if let selectedTextID, let selectedText {
            var shared = style; shared.text = direction.style(role).text
            board.directions[directionIndex].styles[role.rawValue] = shared
            if style.text != selectedText.style?.text { board.directions[directionIndex].setCanvasText(style.text, textID: selectedTextID) }
        } else { board.directions[directionIndex].styles[role.rawValue] = style }
    }
    var faces: [Face] { StudioFontFilter.faces(library: library, collection: fontCollection, category: fontCategory, search: fontSearch) }
    var missingFonts: [String] { Set(direction.canvas == .imported ? direction.importedLayout?.layers.compactMap { $0.style?.fontName } ?? [] : direction.styles.values.map(\.fontName)).subtracting(Set(library.allFaces.map(\.name))).sorted() }
    func save(_ action: String = "Edit Typeboard") { onSave(board, action) }
    func directionBinding<T>(_ key: WritableKeyPath<TypeDirection, T>) -> Binding<T> { Binding(get: { direction[keyPath: key] }, set: { board.directions[directionIndex][keyPath: key] = $0; save() }) }
    func styleBinding<T>(_ key: WritableKeyPath<TypeStyle, T>) -> Binding<T> { Binding(get: { style[keyPath: key] }, set: { var updated = style; updated[keyPath: key] = $0; setStyle(updated); save(key == \TypeStyle.size ? "Change Size" : key == \TypeStyle.tracking ? "Change Letter Spacing" : key == \TypeStyle.text ? "Change Sample Text" : "Edit Typography") }) }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ShelfEditableName(name: board.name, onRename: { name in board.name = name; save("Rename Typeboard"); return true }).font(.headline).frame(minWidth: 110)
                Spacer(minLength: 12)
                Menu("Add canvas") {
                    Button("Blank canvas") { let canvas = TypeDirection(name: board.nextCanvasName); board.directions.append(canvas); board.selectedDirection = canvas.id; summaryCanvasIDs.insert(canvas.id); save("Add Canvas") }
                    Button("Duplicate current canvas") { let copy = direction.copy(name: board.nextCanvasName); board.directions.append(copy); board.selectedDirection = copy.id; summaryCanvasIDs.insert(copy.id); save("Duplicate Canvas") }
                }.fixedSize()
                Button { openFontSummary() } label: { Label("\(visibleFontCount) fonts used", systemImage: "textformat") }.fixedSize().popover(isPresented: $showFontSummary) { fontSummaryPopover }
                Menu("Export") {
                    Button("Typography summary…") { openFontSummary() }
                    Button("Web-font performance…") { showWebFontAudit = true }
                    Button("Developer handoff…") {
                        do { if let folder = try DeveloperHandoff.selectFolder(title: board.name, boards: [board], catalog: library.families) { status = "Developer handoff exported. Open index.html for the specimen; README explains font setup."; NSWorkspace.shared.activateFileViewerSelecting([folder]) } }
                        catch { status = "Handoff export failed: " + error.localizedDescription }
                    }
                    Divider()
                    Button("Preview PDF…") { exportPDF() }
                    Button("Editable Figma layout…") { exportFigma() }
                }.fixedSize()
                Menu {
                    Button("Save checkpoint") { var values = board.checkpoints ?? []; values.append(DirectionCheckpoint(direction: direction)); board.checkpoints = Array(values.suffix(50)); save(); status = "Checkpoint saved" }
                    Menu("Restore checkpoint as canvas") {
                        ForEach((board.checkpoints ?? []).reversed()) { checkpoint in Button(checkpoint.direction.name + " · " + checkpoint.date.formatted(date: .abbreviated, time: .shortened)) { let copy = checkpoint.direction.copy(name: checkpoint.direction.name + " restored"); board.directions.append(copy); board.selectedDirection = copy.id; summaryCanvasIDs.insert(copy.id); save() } }
                    }.disabled((board.checkpoints ?? []).isEmpty)
                    Button("Add shortlist as candidates") { board.candidates = Array(Set(board.candidates + library.compared.map { library.chosenFace($0).name })).sorted(); save() }
                    Menu("Create font collection") {
                        Button("From this canvas…") { createCollection(.canvas) }
                        Button("From this typeboard…") { createCollection(.typeboard) }
                        Button("From this project…") { createCollection(.project) }
                    }
                    Divider()
                    Button("Delete canvas", role: .destructive) { let id = direction.id; board.directions.removeAll { $0.id == id }; shownCanvasIDs.remove(id); summaryCanvasIDs.remove(id); board.selectedDirection = board.directions.first?.id; if let selected = board.selectedDirection { shownCanvasIDs.insert(selected); if summaryCanvasIDs.isEmpty { summaryCanvasIDs.insert(selected) } }; abID = nil; save("Delete Canvas") }.disabled(board.directions.count < 2)
                    Button("Delete typeboard…", role: .destructive) { showDelete = true }
                } label: { Image(systemName: "ellipsis") }.shelfIconMenu().help("Typeboard actions").accessibilityLabel("Typeboard actions")
            }.padding(14).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) { ForEach(board.directions) { canvas in
                        Button { selectCanvas(canvas.id) } label: { HStack(spacing: 5) { if shownCanvasIDs.contains(canvas.id) || canvas.id == direction.id { Image(systemName: "eye.fill").font(.caption2) }; Text(board.canvasName(canvas)).lineLimit(1) }.padding(.horizontal, 12).padding(.vertical, 7).background(canvas.id == direction.id ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 7)) }.buttonStyle(.plain).help("Edit and show " + board.canvasName(canvas))
                    } }
                }
                Button(showingAllCanvases ? "Only current" : "Show all") { if showingAllCanvases { showOnlyCurrent() } else { shownCanvasIDs = Set(board.directions.map(\.id)); abID = nil } }.disabled(board.directions.count < 2).fixedSize()
            }.frame(height: 36).padding(.horizontal, 14).padding(.bottom, 10)
            HStack {
                ShelfDropdown(title: "Format", selection: directionBinding(\.canvas), options: CanvasKind.allCases.filter { $0 != .imported || direction.importedLayout != nil }.map { ($0 == .imported ? direction.canvasDisplayName : $0.rawValue, $0) }).frame(minWidth: 115, idealWidth: 180, maxWidth: 210)
                if direction.canvas == .imported { Text("\(Int(direction.width)) \(direction.canvasUnitLabel)").font(.caption).foregroundStyle(.secondary) }
                else { ShelfDropdown(title: "Width", selection: directionBinding(\.width), options: [("Mobile · 390", 390.0), ("Tablet · 768", 768.0), ("Desktop · 1200", 1200.0), ("Canvas · 960", 960.0)], showsTitle: false).frame(width: 132) }
                Spacer()
                Menu {
                    Button("Only " + board.canvasName(direction)) { showOnlyCurrent() }.disabled(visibleDirections.count == 1 && abID == nil)
                    Button("Show every canvas") { shownCanvasIDs = Set(board.directions.map(\.id)); abID = nil }.disabled(showingAllCanvases)
                    Divider()
                    ForEach(board.directions) { candidate in
                        Button((shownCanvasIDs.contains(candidate.id) || candidate.id == direction.id ? "✓ " : "") + board.canvasName(candidate)) {
                            guard candidate.id != direction.id else { return }
                            if shownCanvasIDs.contains(candidate.id) { shownCanvasIDs.remove(candidate.id) } else { shownCanvasIDs.insert(candidate.id) }
                            abID = nil
                        }.disabled(candidate.id == direction.id)
                    }
                    Divider()
                    Menu("Quick A/B") {
                        let candidates = board.directions.filter { $0.id != direction.id && $0.canvas == direction.canvas && $0.width == direction.width }
                        if candidates.isEmpty { Text("Duplicate a canvas to start"); Text("Use the same format and width") }
                        ForEach(candidates) { candidate in Button(board.canvasName(candidate)) { abID = candidate.id; shownCanvasIDs = [direction.id] } }
                    }.disabled(board.directions.count < 2)
                } label: { Label(abID != nil ? "A/B" : "Shown · \(visibleDirections.count)", systemImage: "rectangle.split.2x1") }.fixedSize().help("Choose exactly which canvases are visible")
                if abID != nil { Button { swapAB() } label: { Image(systemName: "arrow.left.arrow.right") }.keyboardShortcut("\\", modifiers: [.command]).help("Swap A/B (⌘\\)").accessibilityLabel("Swap A/B") }
                Menu(zoom == 0 ? "Fit" : "\(Int(zoom * 100))%") { Button("Fit all visible canvases") { zoom = 0 }; ForEach([0.25, 0.5, 0.75, 1.0, 1.5, 2.0, 3.0], id: \.self) { value in Button("\(Int(value * 100))%") { zoom = value } } }.fixedSize().help("Pinch to zoom, or hold ⌘ while scrolling with a mouse. Scroll normally to pan.")
            }.padding(.horizontal, 14).padding(.bottom, 12).fixedSize(horizontal: false, vertical: true)
            Divider()
            HSplitView {
                inspector.frame(minWidth: 300, idealWidth: 330, maxWidth: 500).background(StudioSplitPosition())
                VStack(alignment: .leading, spacing: 0) {
                    if library.loading { ProgressView(library.families.isEmpty ? "Loading font library…" : "Checking watched font folders…").controlSize(.small).padding(10) }
                    else if !missingFonts.isEmpty { Label("Unavailable fonts: " + missingFonts.joined(separator: ", ") + ". Preview uses fallback.", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange).padding(12) }
                    GeometryReader { geometry in
                    let visible = visibleDirections
                    let scale = zoom == 0 ? min(1, max(0.1, (geometry.size.width - 48 - Double(visible.count - 1) * 24) / visible.reduce(0) { $0 + $1.width })) : zoom
                    ScrollView([.horizontal, .vertical]) {
                        HStack(alignment: .top, spacing: 24) {
                            ForEach(visible) { item in canvas(item, scale: scale) }
                        }.padding(24).frame(minWidth: geometry.size.width, minHeight: geometry.size.height, alignment: .topLeading)
                    }.background(Color.black.opacity(0.09)).background(CanvasZoomInput { factor in zoom = CanvasZoomInput.clamped((zoom == 0 ? scale : zoom) * factor) })
                    }
                    HStack { Text(!library.studio.error.isEmpty ? "Changes could not be saved" : status.isEmpty ? "Saved" : status).lineLimit(2); Spacer(); if let partner = board.directions.first(where: { $0.id == abID }) { Text("A/B · " + partner.name).lineLimit(1) }; Text("\(Int(direction.width)) \(direction.canvasUnitLabel) · " + (zoom == 0 ? "Fit" : "\(Int(zoom * 100))%" )).monospacedDigit() }.font(.caption).foregroundStyle(.secondary).padding(10)
                }.frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
            }
        }.alert("Delete this typeboard?", isPresented: $showDelete) { Button("Delete", role: .destructive, action: onDelete); Button("Cancel", role: .cancel) {} }
        .sheet(isPresented: $showWebFontAudit) { WebFontAuditView(board: board, library: library, initialCanvasIDs: summaryCanvasIDs) }
        .sheet(isPresented: $showPairingSuggestions) {
            if let reference = library.allFaces.first(where: { $0.name == style.fontName }) {
                FontPairingSuggestionsSheet(library: library, reference: reference, intendedRole: pairingTargetRole, preview: direction.style(pairingTargetRole).text) { face in
                    applyPairingSuggestion(face, to: pairingTargetRole, reference: reference)
                }
            }
        }
        .onChange(of: savedBoard) { value in if value != board { board = value; shownCanvasIDs = CanvasVisibility.prune(shownCanvasIDs, valid: Set(value.directions.map(\.id)), selected: value.selectedDirection ?? value.directions.first?.id) } }
        .onChange(of: role) { _ in library.studio.endUndoCoalescing() }
        .onChange(of: selectedSection) { _ in library.studio.endUndoCoalescing() }
        .onChange(of: selectedTextID) { _ in library.studio.endUndoCoalescing() }
        .onChange(of: direction.id) { id in shownCanvasIDs.insert(id); selectedSection = nil; selectedTextID = nil; draggedSection = nil; if let other = board.directions.first(where: { $0.id == abID }), other.canvas != direction.canvas || other.width != direction.width { abID = nil } }
        .onChange(of: direction.canvas) { _ in abID = nil; selectedSection = nil; selectedTextID = nil }
        .onChange(of: direction.width) { _ in abID = nil }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("TypefieldMenu"))) { event in if event.object as? String == "find" { inspectorTab = "Typography"; DispatchQueue.main.async { showFontPicker = true } } }
    }
    func selectCanvas(_ id: UUID) { shownCanvasIDs = CanvasVisibility.selecting(id, from: direction.id, shown: shownCanvasIDs); board.selectedDirection = id; abID = nil; save() }
    func showOnlyCurrent() { shownCanvasIDs = CanvasVisibility.solo(direction.id); abID = nil }
    func hideCanvas(_ id: UUID) { guard id != direction.id else { return }; shownCanvasIDs.remove(id) }
    func swapAB() { guard let id = abID, board.directions.contains(where: { $0.id == id && $0.canvas == direction.canvas && $0.width == direction.width }) else { return }; abID = direction.id; board.selectedDirection = id; shownCanvasIDs = [id]; save() }
    func moveSection(_ source: String, _ target: String, _ before: Bool) {
        let plan = CanvasPlanCache.plan(for: direction)
        if direction.canvas == .imported, var layout = direction.importedLayout, source != target, let index = layout.layers.firstIndex(where: { $0.id == source }) {
            let layer = layout.layers.remove(at: index)
            if let destination = layout.layers.firstIndex(where: { $0.id == target }) { layout.layers.insert(layer, at: destination + (before ? 0 : 1)); board.directions[directionIndex].importedLayout = layout; selectedSection = source; save("Reorder Layers") }; return
        }
        board.directions[directionIndex].reorder(source, target: target, before: before, visible: plan.sections.map(\.id)); selectedSection = source; save("Reorder Sections")
    }
    func selectRole(_ item: TypeRole) {
        role = item; fontSearch = ""; inspectorTab = "Typography"
        if let element = CanvasPlanCache.plan(for: direction).elements.first(where: { $0.role == item && $0.text != nil }) { selectedSection = element.sectionID; selectedTextID = element.textID }
        else { selectedSection = nil; selectedTextID = nil }
    }
    func addRole(_ item: TypeRole, target: String?, before: Bool) {
        if direction.canvas == .imported {
            let layer = ImportedLayer(name: item.rawValue, x: 24, y: 24, width: max(1, direction.width - 48), height: item.size * 2, color: direction.ink, style: direction.style(item))
            board.directions[directionIndex].importedLayout?.layers.append(layer); selectedSection = layer.id; selectedTextID = nil; save("Add Text Layer"); return
        }
        let current = CanvasPlanCache.plan(for: direction).sections.map(\.id)
        let id = board.directions[directionIndex].insert(item, target: target, before: before, visible: current)
        selectedSection = id; selectedTextID = nil; role = item; inspectorTab = "Typography"; save("Add \(item.rawValue)")
    }
    func moveLayer(_ id: String, _ dx: Double, _ dy: Double) {
        guard let index = direction.importedLayout?.layers.firstIndex(where: { $0.id == id }) else { return }
        board.directions[directionIndex].importedLayout!.layers[index].x = min(100000, max(0, direction.importedLayout!.layers[index].x + dx))
        board.directions[directionIndex].importedLayout!.layers[index].y = min(100000, max(0, direction.importedLayout!.layers[index].y + dy))
        save("Move Layer")
    }
    func canvas(_ direction: TypeDirection, scale: Double) -> some View {
        let zoom = scale
        let plan = CanvasPlanCache.plan(for: direction)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button { selectCanvas(direction.id) } label: { HStack { Text(board.canvasName(direction)); if direction.id == self.direction.id { Text("Editing").foregroundStyle(Color.accentColor) } else { Text("Click to edit").foregroundStyle(.secondary) } }.contentShape(Rectangle()) }.font(.caption).buttonStyle(.plain)
                Spacer()
                if direction.id != self.direction.id { Button { hideCanvas(direction.id) } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.borderless).foregroundStyle(.secondary).help("Hide " + board.canvasName(direction)).accessibilityLabel("Hide " + board.canvasName(direction)) }
                else if visibleDirections.count > 1 { Button("Only this") { showOnlyCurrent() }.buttonStyle(.borderless).font(.caption).help("Hide the other canvases") }
            }.frame(width: plan.size.width * zoom)
            CanvasPreview(plan: plan, zoom: zoom, directionID: direction.id == self.direction.id ? direction.id : nil, selectedSection: direction.id == self.direction.id ? selectedSection : nil, selectedTextID: direction.id == self.direction.id ? selectedTextID : nil, onSelect: { id in selectedSection = id; selectedTextID = nil; inspectorTab = "Arrangement" }, onMove: moveSection, onAddRole: direction.id == self.direction.id ? addRole : nil, onTranslate: direction.canvas == .imported ? moveLayer : nil, onTextSelect: { element in selectText(element) }, onTextEdit: direction.id == self.direction.id ? { element, text in editText(element, text, directionID: direction.id) } : nil)
                .frame(width: plan.size.width * zoom, height: plan.size.height * zoom).shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        }
    }
    func selectText(_ element: CanvasElement) {
        selectedSection = element.sectionID
        selectedTextID = element.textID
        if let item = element.role { role = item }
        inspectorTab = "Typography"
    }
    func editText(_ element: CanvasElement, _ text: String, directionID: UUID) {
        guard let index = board.directions.firstIndex(where: { $0.id == directionID }) else { return }
        guard TypeDirection.acceptsCanvasText(text) else { status = "Canvas text must be smaller than 200 KB"; return }
        if board.directions[index].canvas == .imported {
            guard board.directions[index].setImportedText(text, layerID: element.sectionID) else { return }
        } else {
            guard let textID = element.textID, element.role != nil else { return }
            board.directions[index].setCanvasText(text, textID: textID)
        }
        save("Edit Canvas Text")
    }
    var inspector: some View {
        let plan = CanvasPlanCache.plan(for: direction)
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                TextField("Canvas name", text: Binding(get: { board.canvasName(direction) }, set: { board.directions[directionIndex].name = $0; save() })).textFieldStyle(.roundedBorder)
                Picker("Inspector", selection: $inspectorTab) { Text("Typography").tag("Typography"); Text("Arrangement").tag("Arrangement") }.pickerStyle(.segmented).labelsHidden()
                if inspectorTab == "Arrangement" { layoutSections }
                else {
                if direction.canvas == .imported {
                    Text("IMPORTED TEXT LAYERS").font(.caption).foregroundStyle(.secondary)
                    ShelfDropdown(title: "Layer", selection: Binding(get: { importedLayerIndex.flatMap { direction.importedLayout?.layers[$0].id } ?? "" }, set: { selectedSection = $0 }), options: (direction.importedLayout?.layers.filter { $0.style != nil } ?? []).map { ($0.name, $0.id) }, showsTitle: false)
                    Text("Edit each text layer independently. Drag layers on the canvas to position them.").font(.caption).foregroundStyle(.secondary)
                } else {
                DisclosureGroup("Type roles · " + role.rawValue) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 5) {
                ForEach(TypeRole.allCases) { item in
                    let count = plan.elements.filter { $0.role == item && $0.text != nil }.count
                    Button { selectRole(item) } label: {
                        HStack { Text(item.rawValue).font(.caption).fontWeight(.medium); Spacer(); Text(count == 0 ? "Add" : "\(count)× · \(Int(direction.style(item).size))").font(.caption).monospacedDigit().foregroundStyle(.secondary) }.padding(9).background(role == item ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 7)).contentShape(Rectangle())
                    }.buttonStyle(.plain).onDrag { NSItemProvider(object: (direction.id.uuidString + "|role|" + item.rawValue) as NSString) }.help(count == 0 ? "Drag onto the canvas to add this role" : "Click to locate this role; drag to add another")
                }
                Text("Double-click text on the canvas to edit it in place. Press ⌘Return to finish or Escape to cancel.").font(.caption).foregroundStyle(.secondary)
                }
                Text("Click a role to select its first use on the canvas. Drag any role onto the canvas to add its saved sample text.").font(.caption2).foregroundStyle(.secondary)
                }
                }
                Divider()
                if importedNonTextSelected {
                    Text("Select a text layer to edit typography.").font(.caption).foregroundStyle(.secondary)
                } else {
                Text(editingTitle).font(.headline)
                if selectedTextID != nil && direction.canvas != .imported { Text("Editing the selected text. Font and spacing changes apply to its shared type role.").font(.caption).foregroundStyle(.secondary) }
                characterPanel
                if direction.canvas != .imported {
                    Menu {
                        ForEach(TypeRole.allCases.filter { $0 != role }) { target in
                            Button("Suggest for " + target.rawValue) {
                                pairingTargetRole = target
                                showPairingSuggestions = true
                            }
                        }
                    } label: { Label("Pair this font with another role…", systemImage: "sparkles") }
                        .disabled(library.allFaces.first(where: { $0.name == style.fontName }) == nil)
                        .help("Rank compatible fonts from your local library and explain each suggestion")
                }
                paragraphPanel
                listPanel
                Divider()
                canvasAlignmentPanel
                DisclosureGroup("Variable font axes") { axesEditor }
                if let face = library.allFaces.first(where: { $0.name == style.fontName }) {
                    let features = face.facts.features.filter { $0 != "kern" }
                    if !features.isEmpty {
                    DisclosureGroup("OpenType features") {
                        ForEach(features, id: \.self) { tag in
                            ShelfDropdown(title: tag, selection: Binding(get: { style.features[tag] ?? -1 }, set: { var s = style; if $0 < 0 { s.features.removeValue(forKey: tag) } else { s.features[tag] = $0 }; setStyle(s); save() }), options: [("Default", -1), ("Off", 0), ("On", 1)] + (2...9).map { ("Alternate \($0)", $0) })
                        }
                    }
                    }
                }
                Text(selectedTextID == nil ? "Sample text" : "Selected text").font(.caption).foregroundStyle(.secondary)
                TextEditor(text: styleBinding(\.text)).frame(height: 100).overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.secondary.opacity(0.25)))
                DisclosureGroup("Proofing") {
                    let ink = importedLayerIndex.flatMap { direction.importedLayout?.layers[$0].color } ?? direction.ink
                    if let ratio = SpacesProofing.contrastRatio(ink: ink, paper: direction.paper) {
                        Text(String(format: "Ink/canvas contrast: %.2f:1", ratio))
                        if ratio < 4.5 { Label("Below the 4.5:1 small-text reference", systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
                    }
                    Text("Longest entered line: \(SpacesProofing.longestLine(style.text)) characters")
                    if direction.canvas == .imported { Text("Contrast uses saved layer ink and canvas color; overlapping artwork may change the result.") }
                    else { Text("Wrapping and rendered line length depend on the frame and font.") }
                }.font(.caption).foregroundStyle(.secondary)
                }
                }
                Divider()
                if inspectorTab == "Arrangement" || importedNonTextSelected { canvasAlignmentPanel; Divider() }
                if let warnings = direction.importWarnings, !warnings.isEmpty { DisclosureGroup("Import notes (\(warnings.count))") { Text(warnings.joined(separator: "\n")).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) } }
                if !importedNonTextSelected { colorPicker("Text", key: \.ink) }; colorPicker("Background", key: \.paper); if direction.canvas != .imported { colorPicker("Accent", key: \.accent) }
                Text("Canvas notes").font(.caption).foregroundStyle(.secondary)
                TextEditor(text: directionBinding(\.notes)).frame(height: 75)
            }.padding(14)
        }
    }
    func optionalStyleBinding<T>(_ key: WritableKeyPath<TypeStyle, T?>, default fallback: T) -> Binding<T> { Binding(get: { style[keyPath: key] ?? fallback }, set: { var s = style; s[keyPath: key] = $0; setStyle(s); save() }) }
    var kerningBinding: Binding<Bool> { Binding(get: { style.effectiveKerning }, set: { var s = style; s.setKerning($0); setStyle(s); save() }) }
    var fontPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { Text("Choose font · " + editingTitle).font(.headline); Spacer(); Button("Done") { showFontPicker = false } }
            TextField("Search fonts, styles or #tags", text: $fontSearch).textFieldStyle(.roundedBorder).focused($fontSearchFocused)
            HStack(spacing: 12) {
                ShelfDropdown(title: "Collection", selection: $fontCollection, options: [("All fonts", "All fonts"), ("Favorites", "Favorites")] + library.saved.collections.keys.sorted().map { ($0, "collection:" + $0) })
                ShelfDropdown(title: "Category", selection: $fontCategory, options: ["All categories"] .map { ($0, $0) } + Category.allCases.map { ($0.rawValue, $0.rawValue) })
            }
            HStack { Text("\(faces.count) styles").font(.caption).foregroundStyle(.secondary); Spacer(); if fontCollection != "All fonts" || fontCategory != "All categories" || !fontSearch.isEmpty { Button("Clear filters") { fontCollection = "All fonts"; fontCategory = "All categories"; fontSearch = "" }.font(.caption) } }
            Button { chooseDiscoveryFont() } label: { Label("Try a local font I haven’t used recently", systemImage: "shuffle") }.buttonStyle(.borderless).disabled(faces.isEmpty)
            if !board.candidates.isEmpty {
                Menu("Pairing candidates (\(board.candidates.count))") {
                    ForEach(board.candidates, id: \.self) { name in Button(name) { chooseFont(name) } }
                }
            }
            if library.loading && faces.isEmpty { ProgressView("Loading font library…").frame(maxWidth: .infinity, maxHeight: .infinity) }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if faces.isEmpty { Text("No fonts match these filters. Choose another collection or category, or clear the filters.").foregroundStyle(.secondary).padding(20).frame(maxWidth: .infinity) }
                    ForEach(faces) { face in
                        Button { chooseFont(face.name) } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack { Text(face.originalFamily + " · " + face.style).font(.caption); Spacer(); if style.fontName == face.name { Image(systemName: "checkmark") } }
                                FontPreview(text: style.text.isEmpty ? "Aa Bb Cc 0123456789" : String(style.text.prefix(90)), name: face.name, size: 27, wraps: true).frame(minHeight: 38).allowsHitTesting(false)
                            }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(style.fontName == face.name ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 8))
                        }.buttonStyle(.plain)
                    }
                }
            }.frame(maxHeight: .infinity)
        }.padding(18).frame(width: 580, height: 540).background(Color(nsColor: .windowBackgroundColor)).onAppear { fontSearchFocused = true }.onExitCommand { showFontPicker = false }
    }
    var layoutSections: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { Text("ARRANGEMENT").font(.caption).foregroundStyle(.secondary); Spacer(); Menu { ForEach(TypeRole.allCases) { item in Button(item.rawValue) {
                addRole(item, target: CanvasPlanCache.plan(for: direction).sections.last?.id, before: false)
            } }; if !(direction.hiddenSections ?? []).isEmpty { Button("Restore removed sections") { board.directions[directionIndex].hiddenSections = nil; save() } } } label: { Image(systemName: "plus") }.shelfIconMenu().help("Add section").accessibilityLabel("Add section") }
            let plan = CanvasPlanCache.plan(for: direction)
            GeometryReader { geometry in
                ZStack(alignment: .topTrailing) {
                    CanvasPreview(plan: CanvasPlan(arrangement: plan.sections, width: geometry.size.width), directionID: direction.id, selectedSection: selectedSection, onSelect: { selectedSection = $0 }, onMove: moveSection)
                    VStack(spacing: 0) {
                        ForEach(plan.sections) { section in
                            Button { var hidden = direction.hiddenSections ?? []; hidden.insert(section.id); board.directions[directionIndex].hiddenSections = hidden; save("Remove Section") } label: { Image(systemName: "minus").frame(width: 28, height: 42) }.buttonStyle(.borderless).help("Remove " + section.title).accessibilityLabel("Remove " + section.title)
                        }
                    }
                }
            }.frame(height: Double(plan.sections.count) * 42)
            Text(direction.canvas == .imported ? "Drag here to change layer stacking order; drag on the canvas to move a layer." : "Drag sections here or on the canvas.").font(.caption2).foregroundStyle(.secondary)
        }
    }
    func chooseFont(_ name: String) { let changed = style.fontName != name; var s = style; s.fontName = name; s.axes = library.pro.axes[name] ?? [:]; s.features = library.pro.features[name] ?? [:]; setStyle(s); save("Change Font"); if changed && library.studio.error.isEmpty { _ = library.recordFontUse(name) } }
    func applyPairingSuggestion(_ face: Face, to target: TypeRole, reference: Face) {
        var paired = direction.style(target)
        paired.fontName = face.name
        paired.axes = library.pro.axes[face.name] ?? [:]
        paired.features = library.pro.features[face.name] ?? [:]
        board.directions[directionIndex].styles[target.rawValue] = paired
        board.candidates = Array(Set(board.candidates + [reference.name, face.name])).sorted()
        role = target; selectedSection = nil; selectedTextID = nil
        save("Apply Pairing Suggestion")
        if library.studio.error.isEmpty { _ = library.recordFontUse(face.name) }
        status = "Paired " + reference.originalFamily + " with " + face.originalFamily + " for " + target.rawValue
    }
    func chooseDiscoveryFont() {
        let allowed = Set(faces.map(\.name))
        let eligible = library.families.filter { !$0.faces.allSatisfy { !allowed.contains($0.name) } }
        discoveryNonce &+= 1
        let preferred = library.discoveryCandidates(in: eligible, includeSystemFonts: false, seed: discoveryNonce, limit: 1).first ?? library.discoveryCandidates(in: eligible, includeSystemFonts: true, seed: discoveryNonce, limit: 1).first
        if let preferred { chooseFont(preferred.face.name); fontSearch = ""; status = "Trying \(preferred.family.name) · \(preferred.face.style) from your local library" }
    }
    func openFontSummary() {
        showFontSummary = true
    }
    var fontSummaryPopover: some View {
        let summary = fontSummary
        return VStack(alignment: .leading, spacing: 14) {
            HStack { VStack(alignment: .leading, spacing: 3) { Text("Typography summary").font(.headline); Text("\(selectedSummaryDirections.count) of \(board.directions.count) canvases · \(summary.fonts.count) fonts").font(.caption).foregroundStyle(.secondary) }; Spacer(); Button("Done") { showFontSummary = false }.keyboardShortcut(.cancelAction) }
            VStack(alignment: .leading, spacing: 7) {
                Text("Canvases to include").font(.caption).foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(board.directions) { canvas in
                            Toggle(board.canvasName(canvas), isOn: Binding(get: { summaryCanvasIDs.contains(canvas.id) }, set: { included in
                                if included { summaryCanvasIDs.insert(canvas.id) }
                                else if summaryCanvasIDs.count > 1 { summaryCanvasIDs.remove(canvas.id) }
                            })).toggleStyle(.checkbox).disabled(summaryCanvasIDs.count == 1 && summaryCanvasIDs.contains(canvas.id))
                        }
                    }
                }
            }
            Picker("Detail", selection: $fontSummaryDetail) { ForEach(TypographySummaryDetail.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented).labelsHidden()
            ScrollView { Text(summary.text(fontSummaryDetail)).font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(12) }.background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8)).frame(minHeight: 180, maxHeight: 320)
            HStack {
                Button("Copy") { let pasteboard = NSPasteboard.general; pasteboard.clearContents(); pasteboard.setString(summary.text(fontSummaryDetail), forType: .string); status = "Typography summary copied" }
                Button("Web cost…") { showFontSummary = false; DispatchQueue.main.async { showWebFontAudit = true } }
                Spacer()
                Menu { Button("From this canvas…") { createCollection(.canvas) }; Button("From this typeboard…") { createCollection(.typeboard) }; Button("From this project…") { createCollection(.project) } } label: { Label("Collection", systemImage: "folder.badge.plus") }.fixedSize()
                Menu("Export") {
                    Button("Plain text…") { exportFontSummary(markdown: false) }
                    Button("Markdown…") { exportFontSummary(markdown: true) }
                    Divider()
                    Button("Type system PDF…") { exportTypeSystemPDF() }
                    Divider()
                    Button("Illustrator builder (.jsx)…") { exportAdobeTypeSystem(.illustrator) }
                    Button("InDesign builder (.jsx)…") { exportAdobeTypeSystem(.indesign) }
                }.fixedSize()
            }
            Text("Each selected canvas contributes its visible text styles. Type system PDF creates one specimen page per canvas. Adobe builders create editable native documents when you run the saved script inside Illustrator or InDesign; fonts are referenced, never bundled.").font(.caption).foregroundStyle(.secondary)
        }.padding(18).frame(width: 540)
    }
    enum CollectionScope { case canvas, typeboard, project }
    func createCollection(_ scope: CollectionScope) {
        let names: Set<String>, source: String, suggested: String
        switch scope {
        case .canvas:
            names = StudioFontCollection.fontNames(in: direction); source = "“" + board.canvasName(direction) + "”"; suggested = board.name + " — " + board.canvasName(direction)
        case .typeboard:
            names = StudioFontCollection.fontNames(in: board); source = "the “" + board.name + "” typeboard"; suggested = board.name + " fonts"
        case .project:
            let currentBoards = projectBoards.map { $0.id == board.id ? board : $0 }
            names = StudioFontCollection.fontNames(in: currentBoards); source = "the “" + projectName + "” project"; suggested = projectName + " fonts"
        }
        let families = library.familyNames(forPostScriptNames: names)
        let unavailable = names.subtracting(Set(library.allFaces.map(\.name))).count
        guard !families.isEmpty else { status = "No fonts in this scope are currently available in the Library"; return }
        guard let name = ShelfCollectionPrompt.prompt(suggestedName: suggested, source: source, count: families.count, unavailable: unavailable, validate: { library.saved.collections[$0] == nil ? nil : "A collection with this name already exists." }) else { return }
        switch library.createCollection(name, postScriptNames: names) {
        case .created(let created, let count): status = "Created “\(created)” with \(count) font \(count == 1 ? "family" : "families"); available in Library and font filters"
        case .duplicateName: status = "A collection with that name already exists"
        case .noAvailableFonts: status = "No fonts in this scope are currently available in the Library"
        case .invalidName: status = "Enter a collection name"
        case .saveFailed: status = library.message
        }
    }
    func exportFontSummary(markdown: Bool) {
        let panel = NSSavePanel(), suffix = markdown ? "md" : "txt"
        panel.allowedContentTypes = [UTType(filenameExtension: suffix) ?? .plainText]
        let scope = selectedSummaryDirections.count == 1 ? board.canvasName(selectedSummaryDirections[0]) : "\(selectedSummaryDirections.count) canvases"
        panel.nameFieldStringValue = board.name + " — " + scope + " typography." + suffix
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try fontSummary.text(fontSummaryDetail, markdown: markdown).write(to: url, atomically: true, encoding: .utf8); status = "Typography summary exported" }
        catch { status = "Typography summary export failed: " + error.localizedDescription }
    }
    func exportTypeSystemPDF() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.pdf]; panel.nameFieldStringValue = board.name + " — type systems.pdf"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try TypeSystemPDFExporter.data(directions: selectedSummaryDirections).write(to: url, options: .atomic)
            status = "Type system PDF exported with \(selectedSummaryDirections.count) canvas \(selectedSummaryDirections.count == 1 ? "page" : "pages")"
        } catch { status = "Type system PDF export failed: " + error.localizedDescription }
    }
    func exportAdobeTypeSystem(_ target: AdobeTypeSystemTarget) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: target.scriptExtension) ?? .plainText]
        panel.nameFieldStringValue = AdobeTypeSystemExporter.suggestedScriptFilename(title: board.name, target: target)
        panel.message = "Run this builder inside Adobe " + target.displayName + ". It creates a new editable ." + target.documentExtension + " document and asks where to save it."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try AdobeTypeSystemExporter.data(directions: selectedSummaryDirections, title: board.name, target: target).write(to: url, options: .atomic)
            status = "Adobe " + target.displayName + " builder exported — run the .jsx file inside " + target.displayName + " to create the native document"
        } catch {
            status = "Adobe " + target.displayName + " export failed: " + error.localizedDescription
        }
    }
    func numeric(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 4) { HStack { Text(title); Spacer(); TextField(title, value: Binding(get: { value.wrappedValue }, set: { if $0.isFinite { value.wrappedValue = min(range.upperBound, max(range.lowerBound, $0)) } }), format: .number.precision(.fractionLength(0...2))).multilineTextAlignment(.trailing).textFieldStyle(.roundedBorder).frame(width: 65).onSubmit { NSApp.keyWindow?.makeFirstResponder(nil) }; Text(unit).foregroundStyle(.secondary) }.font(.caption); Slider(value: value, in: range) }
    }
    var axesEditor: some View {
        let axes = CTFontCopyVariationAxes(CTFontCreateWithName(style.fontName as CFString, 24, nil)) as? [[String: Any]] ?? []
        return ForEach(Array(axes.enumerated()), id: \.offset) { _, axis in
            if let id = axis[kCTFontVariationAxisIdentifierKey as String] as? Int, let low = axis[kCTFontVariationAxisMinimumValueKey as String] as? Double, let high = axis[kCTFontVariationAxisMaximumValueKey as String] as? Double, let initial = axis[kCTFontVariationAxisDefaultValueKey as String] as? Double, high > low {
                numeric(axis[kCTFontVariationAxisNameKey as String] as? String ?? "Axis", value: Binding(get: { style.axes[id] ?? initial }, set: { var s = style; s.axes[id] = $0; setStyle(s); save() }), range: low...high, unit: "")
            }
        }
    }
    func colorPicker(_ title: String, key: WritableKeyPath<TypeDirection, String>) -> some View {
        HStack {
            Text(title)
            Spacer()
            ColorPicker(title, selection: Binding(get: { Color(nsColor: NSColor(hex: key == \TypeDirection.ink ? importedLayerIndex.flatMap { direction.importedLayout?.layers[$0].color } ?? direction.ink : direction[keyPath: key])) }, set: { if key == \TypeDirection.ink && importedNonTextSelected { return }; if key == \TypeDirection.ink, let index = importedLayerIndex { board.directions[directionIndex].importedLayout?.layers[index].color = NSColor($0).rgbHex } else { board.directions[directionIndex][keyPath: key] = NSColor($0).rgbHex }; save() }), supportsOpacity: false).labelsHidden().fixedSize()
        }
    }
    func exportPDF() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.pdf]; panel.nameFieldStringValue = board.name + " — " + direction.name + ".pdf"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { let plan = CanvasPlanCache.plan(for: direction); let view = CanvasNativeView(plan: plan); try view.dataWithPDF(inside: view.bounds).write(to: url, options: .atomic); status = "PDF exported" } catch { status = "Export failed: " + error.localizedDescription }
    }
    func exportFigma() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
        panel.message = "Choose where to save the editable Figma layout and local importer. No fonts are bundled."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { let folder = try FigmaLayoutExporter.write(board: board, parent: url); status = "Figma package exported. See README in the package for import steps."; NSWorkspace.shared.activateFileViewerSelecting([folder]) } catch { status = "Figma export failed: " + error.localizedDescription }
    }
}

/// Preserve the designer's inspector width across boards, without replacing native split-view behavior.
struct StudioSplitPosition: NSViewRepresentable {
    final class Anchor: NSView {
        private var observation: NSObjectProtocol?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.observation == nil else { return }
                var ancestor = self.superview
                while let view = ancestor {
                    if let split = view as? NSSplitView {
                        let saved = UserDefaults.standard.double(forKey: "studioInspectorWidth")
                        split.setPosition(min(500, max(240, saved == 0 ? 310 : saved)), ofDividerAt: 0)
                        self.observation = NotificationCenter.default.addObserver(forName: NSSplitView.didResizeSubviewsNotification, object: split, queue: .main) { [weak split] _ in
                            if let width = split?.subviews.first?.frame.width, width >= 240 { UserDefaults.standard.set(min(500, width), forKey: "studioInspectorWidth") }
                        }
                        return
                    }
                    ancestor = view.superview
                }
            }
        }
        deinit { if let observation { NotificationCenter.default.removeObserver(observation) } }
    }
    func makeNSView(context: Context) -> Anchor { Anchor() }
    func updateNSView(_ view: Anchor, context: Context) {}
}

enum CanvasTextKind { case text, buttonLabel }
struct CanvasElement {
    var rect: CGRect
    var text: NSAttributedString?
    var color: NSColor?
    var radius: Double = 0
    var sectionID = ""
    var style: TypeStyle?
    var role: TypeRole?
    var textID: String?
    var textKind: CanvasTextKind = .text
}
struct CanvasSection: Identifiable { var id: String; var title: String; var rect: CGRect }
enum CanvasPlanCache {
    private struct Entry { let direction: TypeDirection; let plan: CanvasPlan; var used: UInt64 }
    private static let lock = NSLock()
    private static var entries: [UUID: Entry] = [:]
    private static var clock: UInt64 = 0
    static func plan(for direction: TypeDirection) -> CanvasPlan {
        lock.lock()
        clock &+= 1
        let used = clock
        if var entry = entries[direction.id], entry.direction == direction {
            entry.used = used
            entries[direction.id] = entry
            lock.unlock()
            return entry.plan
        }
        lock.unlock()
        let plan = CanvasPlan(direction: direction)
        lock.lock()
        let textLength = plan.elements.reduce(0) { $0 + ($1.text?.length ?? 0) }
        if plan.elements.count <= 1_000 && textLength <= 200_000 { entries[direction.id] = Entry(direction: direction, plan: plan, used: used) }
        if entries.count > 16, let oldest = entries.min(by: { $0.value.used < $1.value.used })?.key { entries.removeValue(forKey: oldest) }
        lock.unlock()
        return plan
    }
    static func removeAll() {
        lock.lock()
        entries.removeAll(keepingCapacity: true)
        lock.unlock()
    }
}
struct CanvasPlan {
    var elements: [CanvasElement] = []
    var sections: [CanvasSection] = []
    var size: CGSize = .zero
    var paper: NSColor
    var ink: NSColor
    var accessibilityText = "Typography canvas"
    mutating func updateAccessibilityText() {
        var result = ""
        for value in elements.compactMap({ $0.text?.string }) where result.count < 4_000 {
            result += (result.isEmpty ? "" : ". ") + String(value.prefix(4_000 - result.count))
        }
        if !result.isEmpty { accessibilityText = result }
    }
    init(arrangement: [CanvasSection], width: Double) {
        paper = .clear; ink = .labelColor; size = CGSize(width: width, height: Double(arrangement.count) * 42)
        for (index, section) in arrangement.enumerated() {
            let y = Double(index) * 42
            sections.append(CanvasSection(id: section.id, title: section.title, rect: CGRect(x: 0, y: y, width: width, height: 42)))
            let text = NSAttributedString(string: "≡   " + section.title, attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.labelColor])
            elements.append(CanvasElement(rect: CGRect(x: 10, y: y + 13, width: max(1, width - 42), height: 20), text: text, sectionID: section.id))
        }
        updateAccessibilityText()
    }
    init(direction d: TypeDirection) {
        paper = NSColor(hex: d.paper)
        ink = NSColor(hex: d.ink)
        if d.canvas == .imported {
            size = CGSize(width: d.width, height: d.importedLayout?.height ?? 480)
            for layer in d.importedLayout?.layers ?? [] where !(d.hiddenSections ?? []).contains(layer.id) {
                let color = NSColor(hex: layer.color).withAlphaComponent(layer.opacity)
                var rect = layer.rect
                if let style = layer.style {
                    let text = style.attributed(color: color)
                    rect.size.height = max(rect.height, ceil(text.boundingRect(with: CGSize(width: max(1, rect.width), height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading]).height) + 4)
                    elements.append(CanvasElement(rect: rect, text: text, sectionID: layer.id, style: style))
                } else { elements.append(CanvasElement(rect: rect, color: color, radius: layer.radius, sectionID: layer.id)) }
                sections.append(CanvasSection(id: layer.id, title: layer.name, rect: rect))
                size.height = max(size.height, rect.maxY)
            }
            updateAccessibilityText()
            return
        }
        let w = min(1600, max(320, d.width)), margin = w < 500 ? 24.0 : 56.0, usable = w - margin * 2
        let ink = self.ink, accent = NSColor(hex: d.accent)
        var y = margin
        var currentID = "", currentTitle = "", sectionStart = margin, elementStart = 0
        var textCounts: [TypeRole: Int] = [:]
        func finishSection() {
            guard !currentID.isEmpty else { return }
            for i in elementStart..<elements.count { elements[i].sectionID = currentID }
            sections.append(CanvasSection(id: currentID, title: currentTitle, rect: CGRect(x: 0, y: sectionStart, width: w, height: max(24, y - sectionStart))))
        }
        func section(_ id: String, _ title: String) {
            finishSection(); currentID = d.canvas.rawValue + ":" + id; currentTitle = title; sectionStart = y; elementStart = elements.count; textCounts = [:]
        }
        func text(_ role: TypeRole, _ override: String? = nil, x: Double? = nil, at: Double? = nil, width: Double? = nil, color: NSColor? = nil) -> Double {
            let occurrence = textCounts[role, default: 0]; textCounts[role] = occurrence + 1
            let textID = currentID + "|" + role.rawValue + "|" + String(occurrence)
            var style = d.style(role); style.text = d.textOverrides?[textID] ?? override ?? style.text
            let value = style.attributed(color: color ?? ink)
            let available = max(1, width ?? usable)
            let height = ceil(value.boundingRect(with: NSSize(width: available, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading]).height) + 4
            elements.append(CanvasElement(rect: CGRect(x: x ?? margin, y: at ?? y, width: available, height: height), text: value, style: style, role: role, textID: textID))
            if at == nil { y += height + 18 }
            return height
        }
        func rule() { elements.append(CanvasElement(rect: CGRect(x: margin, y: y, width: usable, height: 1), color: ink.withAlphaComponent(0.18))); y += 26 }
        func button(_ label: String? = nil, x: Double? = nil, width: Double? = nil) { let bx = x ?? margin, bw = width ?? usable, start = y, textIndex = elements.count; let h = text(.label, label, x: bx + 18, at: start + 13, width: bw - 36); elements[textIndex].textKind = .buttonLabel; elements.insert(CanvasElement(rect: CGRect(x: bx, y: start, width: bw, height: h + 26), color: accent, radius: 7), at: textIndex); y = start + h + 50 }
        switch d.canvas {
        case .imported: break
        case .custom:
            for (index, role) in (d.blocks ?? TypeRole.allCases).enumerated() { section("block-\(index)", role.rawValue); _ = text(role) }
        case .website:
            section("navigation", "Website navigation")
            let navY = y
            let logoH = text(.label, "STUDIO / 01", x: margin, at: navY, width: usable * 0.35)
            let navH = text(.caption, "WORK   ABOUT   JOURNAL   CONTACT", x: margin + usable * 0.48, at: navY, width: usable * 0.52)
            y = navY + max(logoH, navH) + 22; rule()
            section("hero", "Split hero")
            if w >= 700 {
                let top = y, copyWidth = usable * 0.49, imageX = margin + usable * 0.57, imageWidth = usable * 0.43
                let displayH = text(.display, x: margin, at: top, width: copyWidth)
                let bodyH = text(.body, x: margin, at: top + displayH + 22, width: copyWidth * 0.88)
                y = top + displayH + bodyH + 48; button("Explore the collection", x: margin, width: min(230, copyWidth))
                let imageHeight = max(300, y - top + 54)
                elements.insert(CanvasElement(rect: CGRect(x: imageX, y: top, width: imageWidth, height: imageHeight), color: accent.withAlphaComponent(0.2), radius: 3), at: elementStart)
                elements.append(CanvasElement(rect: CGRect(x: imageX + imageWidth * 0.55, y: top + imageHeight * 0.12, width: imageWidth * 0.28, height: imageHeight * 0.65), color: accent.withAlphaComponent(0.38), radius: imageWidth * 0.14))
                y = max(y, top + imageHeight + 34)
            } else {
                _ = text(.display); _ = text(.body); button("Explore the collection", width: min(240, usable)); elements.append(CanvasElement(rect: CGRect(x: margin, y: y, width: usable, height: 220), color: accent.withAlphaComponent(0.2), radius: 3)); y += 250
            }
            section("proof", "Trust strip")
            let proofY = y, proofWidth = usable / 3
            for (i, value) in ["EST. 2018", "INDEPENDENT", "WORLDWIDE"].enumerated() { _ = text(.caption, value, x: margin + Double(i) * proofWidth, at: proofY, width: proofWidth) }
            y = proofY + 38; rule()
            section("features", "Feature stories")
            let cards = w >= 768 ? 3 : 1, gap = 24.0, cw = (usable - Double(cards - 1) * gap) / Double(cards), top = y
            var bottom = y
            for i in 0..<cards {
                let x = margin + Double(i) * (cw + gap), imageHeight = cw * (i == 1 ? 0.9 : 0.62)
                elements.append(CanvasElement(rect: CGRect(x: x, y: top, width: cw, height: imageHeight), color: accent.withAlphaComponent(0.11 + Double(i) * 0.055), radius: 4))
                let h = text(.subheading, ["Objects with purpose", "A slower process", "Inside the studio"][i], x: x, at: top + imageHeight + 16, width: cw)
                let b = text(.body, x: x, at: top + imageHeight + h + 26, width: cw)
                bottom = max(bottom, top + imageHeight + h + b + 42)
            }
            y = bottom; rule(); section("footer", "Website footer"); _ = text(.heading, "Stay curious."); _ = text(.caption, "NEWSLETTER     INSTAGRAM     TERMS     © 2026")
        case .product:
            section("app-bar", "Application chrome")
            let barY = y
            elements.append(CanvasElement(rect: CGRect(x: margin, y: barY, width: usable, height: 62), color: ink.withAlphaComponent(0.055), radius: 10))
            _ = text(.label, "ACME WORKSPACE", x: margin + 18, at: barY + 19, width: usable * 0.35)
            _ = text(.caption, "⌘ K  SEARCH        ARIAN ▾", x: margin + usable * 0.58, at: barY + 20, width: usable * 0.38)
            y = barY + 86
            section("dashboard", "Dashboard header")
            _ = text(.caption, "OVERVIEW / THIS WEEK"); _ = text(.heading, "Good morning, Arian"); _ = text(.body, "Track active projects, decisions, and the work that needs your attention.")
            section("metrics", "Metric cards")
            let columns = w >= 700 ? 3 : 1, gap = 14.0, cw = (usable - Double(columns - 1) * gap) / Double(columns)
            for start in stride(from: 0, to: 3, by: columns) {
                let rowY = y; var bottom = y
                for i in start..<min(start + columns, 3) {
                    let x = margin + Double(i - start) * (cw + gap), insertion = elements.count
                    let captionH = text(.caption, ["ACTIVE PROJECTS", "AWAITING REVIEW", "ON-TIME RATE"][i], x: x + 18, at: rowY + 16, width: cw - 36)
                    let numberH = text(.heading, ["24", "08", "96%" ][i], x: x + 18, at: rowY + captionH + 26, width: cw - 36)
                    let height = captionH + numberH + 48
                    elements.insert(CanvasElement(rect: CGRect(x: x, y: rowY, width: cw, height: height), color: accent.withAlphaComponent(i == 1 ? 0.2 : 0.09), radius: 10), at: insertion)
                    bottom = max(bottom, rowY + height)
                }
                y = bottom + 18
            }
            section("table", "Project table")
            let tableY = y
            elements.append(CanvasElement(rect: CGRect(x: margin, y: tableY, width: usable, height: 42), color: ink.withAlphaComponent(0.06), radius: 6))
            _ = text(.caption, "PROJECT", x: margin + 16, at: tableY + 13, width: usable * 0.44)
            _ = text(.caption, "STATUS", x: margin + usable * 0.58, at: tableY + 13, width: usable * 0.2)
            y = tableY + 42
            for (i, item) in ["Website exploration", "Mobile interface", "Brand guidelines", "Product launch"].enumerated() {
                let row = y
                _ = text(.label, item, x: margin + 16, at: row + 16, width: usable * 0.48)
                _ = text(.caption, i == 1 ? "NEEDS REVIEW" : "IN PROGRESS", x: margin + usable * 0.58, at: row + 17, width: usable * 0.28)
                y = row + 56; elements.append(CanvasElement(rect: CGRect(x: margin, y: y - 1, width: usable, height: 1), color: ink.withAlphaComponent(0.1)))
            }
            y += 22; section("command", "Command input")
            let commandY = y; elements.append(CanvasElement(rect: CGRect(x: margin, y: commandY, width: usable, height: 58), color: accent.withAlphaComponent(0.13), radius: 9)); _ = text(.mono, "Ask your workspace…                         ⌘ ↵", x: margin + 18, at: commandY + 17, width: usable - 36); y = commandY + 82
        case .editorial:
            section("masthead", "Magazine masthead")
            let mastY = y; _ = text(.caption, "VOL. 12   /   CULTURE & DESIGN", x: margin, at: mastY, width: usable * 0.5); _ = text(.label, "THE FIELD NOTES", x: margin + usable * 0.62, at: mastY, width: usable * 0.38); y = mastY + 38; rule()
            section("cover-story", "Cover story")
            _ = text(.display, "The quiet ideas reshaping everyday life"); _ = text(.subheading, "A conversation about objects, attention, and what it means to make things that last.")
            let bylineY = y; _ = text(.caption, "WORDS  MAYA CHEN", x: margin, at: bylineY, width: usable * 0.45); _ = text(.caption, "PHOTOGRAPHY  LUIS ORTEGA", x: margin + usable * 0.52, at: bylineY, width: usable * 0.48); y = bylineY + 42
            section("image", "Lead image")
            let imageHeight = w >= 700 ? usable * 0.52 : 240
            elements.append(CanvasElement(rect: CGRect(x: margin, y: y, width: usable, height: imageHeight), color: accent.withAlphaComponent(0.22), radius: 2))
            elements.append(CanvasElement(rect: CGRect(x: margin + usable * 0.64, y: y + imageHeight * 0.13, width: usable * 0.22, height: imageHeight * 0.7), color: ink.withAlphaComponent(0.12), radius: 2)); y += imageHeight + 18
            _ = text(.caption, "FIG. 01 — Morning light in the workshop."); y += 18
            section("article", "Article and pull quote")
            if w >= 700 {
                let articleY = y, columnGap = 28.0, bodyWidth = usable * 0.29
                let first = text(.body, Array(repeating: d.style(.body).text, count: 4).joined(separator: "\n\n"), x: margin, at: articleY, width: bodyWidth)
                let quote = text(.heading, "“The useful things are often the most poetic.”", x: margin + bodyWidth + columnGap, at: articleY + 28, width: usable * 0.34)
                let second = text(.body, Array(repeating: d.style(.body).text, count: 4).joined(separator: "\n\n"), x: margin + usable - bodyWidth, at: articleY, width: bodyWidth)
                y = articleY + max(first, quote + 28, second) + 36
            } else { _ = text(.heading, "“The useful things are often the most poetic.”"); _ = text(.body, Array(repeating: d.style(.body).text, count: 5).joined(separator: "\n\n")) }
            rule(); section("folio", "Editorial folio"); let folioY = y; _ = text(.caption, "THE FIELD NOTES", x: margin, at: folioY, width: usable * 0.5); _ = text(.mono, "024", x: margin + usable * 0.8, at: folioY, width: usable * 0.2); y = folioY + 38
        case .poster:
            section("poster-code", "Poster index")
            let indexY = y; _ = text(.mono, "POSTER / 07", x: margin, at: indexY, width: usable * 0.4); _ = text(.caption, "DESIGN / MUSIC / CONVERSATION", x: margin + usable * 0.48, at: indexY, width: usable * 0.52); y = indexY + 60
            section("poster-field", "Graphic field")
            let fieldY = y, fieldHeight = max(300, usable * 0.62)
            elements.append(CanvasElement(rect: CGRect(x: margin, y: fieldY, width: usable, height: fieldHeight), color: accent, radius: 0))
            elements.append(CanvasElement(rect: CGRect(x: margin + usable * 0.54, y: fieldY + fieldHeight * 0.08, width: usable * 0.34, height: usable * 0.34), color: paper.withAlphaComponent(0.9), radius: usable * 0.17))
            _ = text(.display, "FORM / SOUND", x: margin + 28, at: fieldY + 30, width: usable * 0.62, color: paper)
            _ = text(.mono, "08—10\nOCT 2026", x: margin + 30, at: fieldY + fieldHeight * 0.68, width: usable * 0.34, color: paper)
            _ = text(.label, "HALL 04 / LOS ANGELES", x: margin + usable * 0.54, at: fieldY + fieldHeight * 0.78, width: usable * 0.38, color: paper)
            y = fieldY + fieldHeight + 42
            section("poster-details", "Event details")
            let detailY = y; _ = text(.heading, "Three nights of new work.", x: margin, at: detailY, width: usable * 0.55); _ = text(.body, "Exhibitions, live performance, workshops, and conversations with independent makers.", x: margin + usable * 0.62, at: detailY, width: usable * 0.38); y = detailY + 150
            rule(); section("poster-footer", "Poster footer"); let footerY = y; _ = text(.caption, "TICKETS / PROGRAM / ACCESS", x: margin, at: footerY, width: usable * 0.58); _ = text(.mono, "F/S 2026", x: margin + usable * 0.72, at: footerY, width: usable * 0.28); y = footerY + 44
        case .specimen:
            for role in TypeRole.allCases { section(role.rawValue, role.rawValue); _ = text(.caption, role.rawValue.uppercased() + " · " + d.style(role).fontName + " · \(Int(d.style(role).size)) PX"); _ = text(role); rule() }
        }
        for block in d.addedBlocks ?? [] { section(block.id, block.role.rawValue); _ = text(block.role) }
        finishSection()
        let original = elements, sourceSections = sections
        let available = sourceSections.map(\.id).filter { !(d.hiddenSections ?? []).contains($0) }
        var ordered: [String] = []
        for id in (d.sectionOrder ?? []) + available where available.contains(id) && !ordered.contains(id) { ordered.append(id) }
        elements = []; sections = []; y = margin
        for id in ordered {
            guard var part = sourceSections.first(where: { $0.id == id }) else { continue }
            let offset = y - part.rect.minY
            for var element in original where element.sectionID == id { element.rect.origin.y += offset; elements.append(element) }
            part.rect.origin.y = y; sections.append(part); y += part.rect.height
        }
        size = CGSize(width: w, height: max(480, y + margin))
        for i in elements.indices {
            if let id = elements[i].textID, let position = d.textPositions?[id], position.isValid {
                elements[i].rect.origin = CGPoint(x: position.x, y: position.y)
            }
        }
        updateAccessibilityText()
    }
}
final class CanvasInlineTextView: NSTextView {
    var commit: (() -> Void)?
    var cancel: (() -> Void)?
    private var completionScheduled = false
    private func schedule(_ action: (() -> Void)?) {
        guard !completionScheduled, let action else { return }
        completionScheduled = true
        DispatchQueue.main.async(execute: action)
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { schedule(cancel); return }
        if event.keyCode == 36 && event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command) { schedule(commit); return }
        super.keyDown(with: event)
    }
    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        if accepted { schedule(commit) }
        return accepted
    }
}
final class CanvasNativeView: NSView {
    var plan: CanvasPlan
    var zoom = 1.0
    var directionID: UUID?
    var selectedSection: String?
    var selectedTextID: String?
    var onSelect: ((String) -> Void)?
    var onMove: ((String, String, Bool) -> Void)?
    var onAddRole: ((TypeRole, String?, Bool) -> Void)?
    var onTranslate: ((String, Double, Double) -> Void)?
    var onTextSelect: ((CanvasElement) -> Void)?
    var onTextEdit: ((CanvasElement, String) -> Void)?
    private var insertionY: Double?
    private var translation = NSPoint.zero
    private weak var inlineEditor: CanvasInlineTextView?
    private var editingElement: CanvasElement?
    private var activeTextEdit: ((CanvasElement, String) -> Void)?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    init(plan: CanvasPlan) { self.plan = plan; super.init(frame: CGRect(origin: .zero, size: plan.size)); registerForDraggedTypes([.string]) }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    override func resetCursorRects() { if directionID != nil { addCursorRect(bounds, cursor: .openHand) } }
    func section(at point: NSPoint) -> CanvasSection? {
        let local = NSPoint(x: point.x / max(0.01, zoom), y: point.y / max(0.01, zoom))
        if let text = plan.text(at: local), let section = plan.sections.first(where: { $0.id == text.sectionID }) { return section }
        return plan.sections.last { $0.rect.contains(local) }
    }
    override func mouseDown(with event: NSEvent) {
        guard directionID != nil, let window else { return }
        window.makeFirstResponder(self)
        let origin = convert(event.locationInWindow, from: nil)
        guard let item = section(at: origin) else { return }
        selectedSection = item.id; needsDisplay = true
        var moved = false
        // Keep selection changes out of SwiftUI until tracking ends: changing the inspector
        // during mouseDown can rebuild the hosted canvas before AppKit delivers the drag.
        defer { insertionY = nil; translation = .zero; needsDisplay = true }
        while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp, .keyDown], until: .distantFuture, inMode: .eventTracking, dequeue: true) {
            if next.type == .keyDown { if next.keyCode == 53 { return }; continue }
            let point = convert(next.locationInWindow, from: nil)
            moved = moved || hypot(point.x - origin.x, point.y - origin.y) > 4
            let target = dropTarget(at: point)
            if next.type == .leftMouseUp {
                let local = NSPoint(x: origin.x / zoom, y: origin.y / zoom)
                if !moved, let text = plan.text(at: local) {
                    onTextSelect?(text)
                    if event.clickCount >= 2, onTextEdit != nil { beginEditing(text) }
                }
                else { onSelect?(item.id) }
                if moved, bounds.contains(point) { if let onTranslate { onTranslate(item.id, (point.x - origin.x) / zoom, (point.y - origin.y) / zoom) } else if let target { onMove?(item.id, target.id, point.y / zoom < target.rect.midY) } }
                return
            }
            if moved {
                _ = autoscroll(with: next)
                if onTranslate != nil { translation = NSPoint(x: (point.x - origin.x) / zoom, y: (point.y - origin.y) / zoom) }
                else { insertionY = target.map { point.y / zoom < $0.rect.midY ? $0.rect.minY : $0.rect.maxY } }
                needsDisplay = true; displayIfNeeded()
            }
        }
    }
    private func beginEditing(_ element: CanvasElement) {
        finishEditing(commit: true)
        guard let window, let attributed = element.text else { return }
        let editor = CanvasInlineTextView(frame: editorFrame(for: element))
        editor.string = element.style?.text ?? attributed.string
        editor.isRichText = false
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.allowsUndo = true
        editor.drawsBackground = true
        editor.backgroundColor = plan.paper.blended(withFraction: 0.06, of: .controlAccentColor) ?? plan.paper
        editor.textColor = Self.editorTextColor(attributed, fallback: plan.ink)
        editor.font = (element.style?.font as NSFont?).map { NSFont(descriptor: $0.fontDescriptor, size: max(11, $0.pointSize * zoom)) ?? $0 } ?? .systemFont(ofSize: max(11, 14 * zoom))
        editor.alignment = element.style?.alignment?.native ?? .left
        editor.textContainerInset = NSSize(width: 4, height: 3)
        editor.isVerticallyResizable = false
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = []
        editor.wantsLayer = true
        editor.layer?.borderColor = NSColor.controlAccentColor.cgColor
        editor.layer?.borderWidth = 2
        editor.layer?.cornerRadius = 4
        editingElement = element
        activeTextEdit = onTextEdit
        inlineEditor = editor
        editor.commit = { [weak self] in self?.finishEditing(commit: true) }
        editor.cancel = { [weak self] in self?.finishEditing(commit: false) }
        addSubview(editor)
        window.makeFirstResponder(editor)
        editor.selectAll(nil)
    }
    static func editorTextColor(_ attributed: NSAttributedString, fallback: NSColor) -> NSColor {
        guard attributed.length > 0 else { return fallback }
        return attributed.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor ?? fallback
    }
    static func editorFrame(textRect: NSRect, alignment: TextAlignmentOption, zoom: Double, bounds: NSRect) -> NSRect {
        let tight = NSRect(x: textRect.minX * zoom - 3, y: textRect.minY * zoom - 3, width: textRect.width * zoom + 6, height: textRect.height * zoom + 6)
        let width = min(bounds.width, max(90, tight.width)), height = min(bounds.height, max(32, tight.height))
        let extra = width - tight.width
        let proposedX: Double
        switch alignment {
        case .left, .justified: proposedX = tight.minX
        case .center: proposedX = tight.minX - extra / 2
        case .right: proposedX = tight.minX - extra
        }
        let x = min(max(bounds.minX, proposedX), bounds.maxX - width)
        let y = min(max(bounds.minY, tight.minY), bounds.maxY - height)
        return NSRect(x: x, y: y, width: width, height: height)
    }
    private func editorFrame(for element: CanvasElement) -> NSRect {
        let textRect = plan.textBounds(for: element)
        return Self.editorFrame(textRect: textRect, alignment: element.style?.alignment ?? .left, zoom: zoom, bounds: bounds)
    }
    private func finishEditing(commit shouldCommit: Bool) {
        guard let editor = inlineEditor, let element = editingElement else { return }
        let value = editor.string
        let edit = activeTextEdit
        editor.commit = nil
        editor.cancel = nil
        inlineEditor = nil
        editingElement = nil
        activeTextEdit = nil
        if window?.firstResponder === editor { window?.makeFirstResponder(self) }
        editor.removeFromSuperview()
        if shouldCommit { edit?(element, value) }
    }
    func endInlineEditing(commit: Bool) { finishEditing(commit: commit) }
    func synchronizeInlineEditor() {
        guard let editor = inlineEditor, let editingElement else { return }
        let current = plan.elements.first { candidate in
            if let textID = editingElement.textID { return candidate.textID == textID }
            return candidate.sectionID == editingElement.sectionID && candidate.text != nil
        }
        guard let current else { finishEditing(commit: false); return }
        editor.frame = editorFrame(for: current)
    }
    private func dropTarget(at point: NSPoint) -> CanvasSection? {
        if let hit = section(at: point) { return hit }
        return point.y / max(0.01, zoom) < (plan.sections.first?.rect.minY ?? 0) ? plan.sections.first : plan.sections.last
    }
    private func source(_ sender: NSDraggingInfo) -> CanvasDragPayload.Source? {
        guard let directionID, let value = sender.draggingPasteboard.string(forType: .string) else { return nil }
        return CanvasDragPayload.parse(value, directionID: directionID, sectionIDs: Set(plan.sections.map(\.id)), acceptsRoles: onAddRole != nil)
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { draggingUpdated(sender) }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard source(sender) != nil else { return [] }
        let point = convert(sender.draggingLocation, from: nil)
        guard let target = dropTarget(at: point) else { insertionY = nil; needsDisplay = true; return [] }
        insertionY = point.y / zoom < target.rect.midY ? target.rect.minY : target.rect.maxY; needsDisplay = true
        if case .role = source(sender) { return .copy }; return .move
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { insertionY = nil; needsDisplay = true }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { source(sender) != nil }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer { insertionY = nil; needsDisplay = true }
        guard let source = source(sender) else { return false }
        let point = convert(sender.draggingLocation, from: nil)
        guard let target = dropTarget(at: point) else { return false }
        let before = point.y / zoom < target.rect.midY
        switch source { case .section(let id): onMove?(id, target.id, before); case .role(let role): onAddRole?(role, target.id, before) }
        return true
    }
    override func draw(_ dirtyRect: NSRect) {
        plan.paper.setFill(); bounds.fill()
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current?.cgContext.scaleBy(x: zoom, y: zoom)
        for element in plan.elements {
            if let color = element.color { color.setFill(); NSBezierPath(roundedRect: element.rect, xRadius: element.radius, yRadius: element.radius).fill() }
            element.text?.draw(with: element.rect, options: [.usesLineFragmentOrigin, .usesFontLeading])
        }
        if directionID != nil, let textID = selectedTextID, let selected = plan.elements.first(where: { $0.textID == textID }) {
            let source = plan.textBounds(for: selected).offsetBy(dx: translation.x, dy: translation.y)
            let requestedInset = 1 / max(0.1, zoom)
            let insetX = min(requestedInset, max(0, source.width / 2 - 0.5))
            let insetY = min(requestedInset, max(0, source.height / 2 - 0.5))
            NSColor.controlAccentColor.withAlphaComponent(0.85).setStroke(); let border = NSBezierPath(roundedRect: source.insetBy(dx: insetX, dy: insetY), xRadius: 3 / zoom, yRadius: 3 / zoom); border.lineWidth = 2 / zoom; border.stroke()
        } else if directionID != nil, let selected = plan.sections.first(where: { $0.id == selectedSection }) {
            NSColor.controlAccentColor.withAlphaComponent(0.7).setStroke(); let border = NSBezierPath(rect: selected.rect.offsetBy(dx: translation.x, dy: translation.y).insetBy(dx: 1 / zoom, dy: 0)); border.lineWidth = 1 / zoom; border.stroke()
        }
        if let insertionY { NSColor.controlAccentColor.setFill(); NSRect(x: 0, y: insertionY, width: plan.size.width, height: 3 / zoom).fill() }
    }
}
struct CanvasPreview: NSViewRepresentable {
    let plan: CanvasPlan
    var zoom = 1.0
    var directionID: UUID?
    var selectedSection: String?
    var selectedTextID: String?
    var onSelect: ((String) -> Void)?
    var onMove: ((String, String, Bool) -> Void)?
    var onAddRole: ((TypeRole, String?, Bool) -> Void)?
    var onTranslate: ((String, Double, Double) -> Void)?
    var onTextSelect: ((CanvasElement) -> Void)?
    var onTextEdit: ((CanvasElement, String) -> Void)?
    final class Coordinator { var accessibilityText = "" }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> CanvasNativeView { CanvasNativeView(plan: plan) }
    func updateNSView(_ view: CanvasNativeView, context: Context) { view.plan = plan; view.zoom = zoom; view.directionID = directionID; view.selectedSection = selectedSection; view.selectedTextID = selectedTextID; view.onSelect = onSelect; view.onMove = onMove; view.onAddRole = onAddRole; view.onTranslate = onTranslate; view.onTextSelect = onTextSelect; view.onTextEdit = onTextEdit; view.frame.size = CGSize(width: plan.size.width * zoom, height: plan.size.height * zoom); view.synchronizeInlineEditor(); view.setAccessibilityElement(true); if context.coordinator.accessibilityText != plan.accessibilityText { context.coordinator.accessibilityText = plan.accessibilityText; view.setAccessibilityLabel(plan.accessibilityText) }; view.needsDisplay = true }
    static func dismantleNSView(_ view: CanvasNativeView, coordinator: Coordinator) { DispatchQueue.main.async { view.endInlineEditing(commit: true) } }
}

extension CanvasPlan {
    func textBounds(for element: CanvasElement) -> CGRect {
        guard let text = element.text else { return element.rect }
        let local: CGRect
        if text.length == 0 {
            let width = min(element.rect.width, 12)
            let x: CGFloat
            switch element.style?.alignment ?? .left {
            case .left, .justified: x = 0
            case .center: x = (element.rect.width - width) / 2
            case .right: x = element.rect.width - width
            }
            local = CGRect(x: x, y: 0, width: width, height: min(element.rect.height, 2))
        } else {
            let storage = NSTextStorage(attributedString: text)
            let layout = NSLayoutManager(); layout.usesFontLeading = true
            let container = NSTextContainer(containerSize: CGSize(width: max(1, element.rect.width), height: max(1, element.rect.height)))
            container.lineFragmentPadding = 0
            layout.addTextContainer(container); storage.addLayoutManager(layout); layout.ensureLayout(for: container)
            local = layout.usedRect(for: container)
        }
        let positioned = local.offsetBy(dx: element.rect.minX, dy: element.rect.minY)
        return positioned.insetBy(dx: -5, dy: -3).intersection(element.rect)
    }
    func text(at point: NSPoint) -> CanvasElement? {
        var result: (element: CanvasElement, area: CGFloat, index: Int)?
        for (index, element) in elements.enumerated() where element.text != nil {
            guard element.rect.contains(point) else { continue }
            let bounds = textBounds(for: element)
            guard bounds.contains(point) else { continue }
            let area = bounds.width * bounds.height
            if result == nil || area < result!.area || (area == result!.area && index > result!.index) { result = (element, area, index) }
        }
        return result?.element
    }
}

enum TypeSystemPDFExporter {
    static func specimenDirection(from source: TypeDirection) -> TypeDirection {
        var direction = source
        direction.canvas = .specimen
        direction.width = min(1200, max(768, source.width))
        direction.blocks = nil
        direction.addedBlocks = nil
        direction.sectionOrder = nil
        direction.hiddenSections = nil
        direction.importedLayout = nil
        direction.importedSource = nil
        direction.importWarnings = nil
        direction.textOverrides = nil
        return direction
    }
    static func data(directions: [TypeDirection]) throws -> Data {
        guard !directions.isEmpty else { throw NSError(domain: "Typefield", code: 1, userInfo: [NSLocalizedDescriptionKey: "Select at least one canvas."]) }
        let pages: [(Data, CGRect)] = directions.map { source in
            let plan = CanvasPlan(direction: specimenDirection(from: source))
            let view = CanvasNativeView(plan: plan)
            return (view.dataWithPDF(inside: view.bounds), CGRect(origin: .zero, size: plan.size))
        }
        let result = NSMutableData()
        guard let consumer = CGDataConsumer(data: result as CFMutableData) else { throw NSError(domain: "Typefield", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not create the PDF destination."]) }
        var defaultBox = pages[0].1
        guard let context = CGContext(consumer: consumer, mediaBox: &defaultBox, nil) else { throw NSError(domain: "Typefield", code: 3, userInfo: [NSLocalizedDescriptionKey: "Could not create the PDF document."]) }
        for (data, box) in pages {
            guard let provider = CGDataProvider(data: data as CFData), let document = CGPDFDocument(provider), let page = document.page(at: 1) else { throw NSError(domain: "Typefield", code: 4, userInfo: [NSLocalizedDescriptionKey: "Could not render a type system page."]) }
            var mediaBox = box
            let pageInfo = [kCGPDFContextMediaBox: NSData(bytes: &mediaBox, length: MemoryLayout<CGRect>.size)] as CFDictionary
            context.beginPDFPage(pageInfo)
            context.drawPDFPage(page)
            context.endPDFPage()
        }
        context.closePDF()
        return result as Data
    }
}

enum StudioFontFilter {
    static func faces(library: Library, collection: String, category: String, search: String) -> [Face] {
        let query = FontSearchQuery(search)
        return library.families.filter { family in
            (collection == "All fonts" || library.matchesSection(family, collection)) && (category == "All categories" || library.category(family).rawValue == category)
        }.flatMap(\.faces).filter { face in
            (query.text.isEmpty || face.name.localizedCaseInsensitiveContains(query.text) || face.originalFamily.localizedCaseInsensitiveContains(query.text) || face.style.localizedCaseInsensitiveContains(query.text)) && query.matches(face, tags: library.pro.tags[face.name] ?? [])
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

/// Limit gesture interception to the visible canvas viewport; ordinary scrolling still pans.
struct CanvasZoomInput: NSViewRepresentable {
    var onZoom: (Double) -> Void
    static func clamped(_ value: Double) -> Double { value.isFinite ? min(4, max(0.1, value)) : 1 }
    final class Anchor: NSView {
        var onZoom: ((Double) -> Void)?
        var monitor: Any?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.magnify, .scrollWheel]) { [weak self] event in
                guard let self, !self.isHiddenOrHasHiddenAncestor, event.window === self.window, self.bounds.contains(self.convert(event.locationInWindow, from: nil)) else { return event }
                if event.type == .magnify { self.onZoom?(max(0.1, 1 + event.magnification)); return nil }
                if event.modifierFlags.contains(.command) { self.onZoom?(exp(Double(event.scrollingDeltaY) * 0.01)); return nil }
                return event
            }
        }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
    }
    func makeNSView(context: Context) -> Anchor { let view = Anchor(); view.onZoom = onZoom; return view }
    func updateNSView(_ view: Anchor, context: Context) { view.onZoom = onZoom }
    static func dismantleNSView(_ view: Anchor, coordinator: ()) { if let monitor = view.monitor { NSEvent.removeMonitor(monitor); view.monitor = nil } }
}

struct SectionDragTarget: View {
    let id: String
    let title: String
    let directionID: UUID
    let height: Double
    let selected: Bool
    @Binding var dragging: String?
    let onSelect: () -> Void
    let onMove: (String, String, Bool) -> Void
    var showsLabel = false
    @State private var insertion: Bool?
    @State private var hovered = false
    var body: some View {
        ZStack(alignment: .leading) {
            Rectangle().fill(selected ? Color.accentColor.opacity(0.055) : .clear)
            if showsLabel { HStack { Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary); Text(title).font(.caption); Spacer() }.padding(.horizontal, 8) }
            if hovered && !showsLabel { Text(title).font(.caption2).padding(5).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 4)).padding(4).frame(maxHeight: .infinity, alignment: .top) }
        }
        .contentShape(Rectangle())
        .overlay(Rectangle().stroke(selected || hovered ? Color.accentColor.opacity(0.55) : .clear, lineWidth: 1))
        .overlay(alignment: insertion == false ? .bottom : .top) { if insertion != nil { Rectangle().fill(Color.accentColor).frame(height: 3) } }
        .onHover { hovered = $0 }
        .onTapGesture(perform: onSelect)
        .onDrag { let token = directionID.uuidString + "|section|" + id; dragging = token; return NSItemProvider(object: token as NSString) }
        .onDrop(of: [UTType.plainText], delegate: SectionDropDelegate(target: id, directionID: directionID, height: height, dragging: $dragging, insertion: $insertion, onMove: onMove))
        .accessibilityLabel("Reorder " + title).help("Drag above or below another section")
    }
}
struct SectionDropDelegate: DropDelegate {
    let target: String
    let directionID: UUID
    let height: Double
    @Binding var dragging: String?
    @Binding var insertion: Bool?
    let onMove: (String, String, Bool) -> Void
    func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: [UTType.plainText]) }
    func dropUpdated(info: DropInfo) -> DropProposal? { insertion = info.location.y < height / 2; return DropProposal(operation: .move) }
    func dropExited(info: DropInfo) { insertion = nil }
    func performDrop(info: DropInfo) -> Bool {
        guard let provider = info.itemProviders(for: [UTType.plainText]).first else { return false }
        let before = info.location.y < height / 2
        insertion = nil; dragging = nil
        _ = provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let value = object as? String, value.hasPrefix(directionID.uuidString + "|section|") else { return }
            DispatchQueue.main.async { onMove(String(value.dropFirst(45)), target, before) }
        }
        return true
    }
}
