import SwiftUI
import AppKit
import CoreText
import UniformTypeIdentifiers

enum WorkspaceSidebarPreference {
    static let key = "workspaceSidebarCollapsed"
    static func collapsed(in defaults: UserDefaults = .standard) -> Bool { defaults.bool(forKey: key) }
    static func setCollapsed(_ value: Bool, in defaults: UserDefaults = .standard) { defaults.set(value, forKey: key) }
}
enum StudioInspectorMode: String, CaseIterable {
    case expanded, slim, hidden, floating

    var title: String {
        switch self {
        case .expanded: return "Full inspector"
        case .slim: return "Slim tools"
        case .hidden: return "Hide inspector"
        case .floating: return "Float inspector"
        }
    }
    var symbol: String {
        switch self {
        case .expanded: return "sidebar.left"
        case .slim: return "rectangle.righthalf.inset.filled"
        case .hidden: return "rectangle"
        case .floating: return "macwindow.on.rectangle"
        }
    }
}
enum StudioInspectorPreference {
    static let key = "spacesInspectorMode"
    static func mode(in defaults: UserDefaults = .standard) -> StudioInspectorMode {
        let saved = StudioInspectorMode(rawValue: defaults.string(forKey: key) ?? "") ?? .expanded
        return saved == .floating ? .expanded : saved
    }
    static func setMode(_ mode: StudioInspectorMode, in defaults: UserDefaults = .standard) {
        if mode != .floating { defaults.set(mode.rawValue, forKey: key) }
    }
}
enum StudioInspectorLayout {
    static let slimWidth = 52.0
    static let fullIdealWidth = 310.0
    static let fullMinimumWidth = 280.0
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
enum StudioTransferDialog {
    static func confirm(_ report: StudioTransferReport) -> Bool {
        let alert = NSAlert()
        alert.messageText = report.blockingReason == nil ? "Export " + report.format.title + "?" : "Export is unavailable"
        alert.informativeText = report.detail
        alert.alertStyle = report.blockingReason == nil ? .informational : .warning
        alert.addButton(withTitle: report.blockingReason == nil ? "Continue to Export" : "OK")
        if report.blockingReason == nil { alert.addButton(withTitle: "Cancel") }
        return alert.runModal() == .alertFirstButtonReturn && report.blockingReason == nil
    }
    static func showImport(_ report: StudioImportReport, name: String) {
        let alert = NSAlert()
        alert.messageText = "Imported “" + name + "”"
        alert.informativeText = report.detail
        alert.alertStyle = report.warnings.isEmpty && report.missingFonts.isEmpty ? .informational : .warning
        alert.addButton(withTitle: "Done")
        alert.runModal()
    }
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
                TypefieldIconPreview(size: 30).accessibilityHidden(true).accessibilityIdentifier("workspace-brand-mark")
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
        .shelfElevation(.floating)
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
    @Binding var focusCanvas: Bool
    @State private var spaceID: UUID?
    @State private var boardID: UUID?
    @State private var newName = ""
    @State private var showNewSpace = false
    @State private var confirmDelete = false
    @State private var deletingBoard: (space: UUID, board: TypeBoard)?
    @State private var operationStatus = ""
    @State private var lastDeletedSpace: (id: UUID, name: String, boards: Int)?
    var space: DesignSpace? { store.state.spaces.first { $0.id == spaceID } ?? store.state.spaces.first }
    var board: TypeBoard? { space?.boards.first { $0.id == boardID } ?? space?.boards.first }
    var body: some View {
        HStack(spacing: 0) {
        if !sidebarCollapsed && !focusCanvas { WorkspaceSidebarShell { navigation }.transition(.move(edge: .leading).combined(with: .opacity)) }
        VStack(spacing: 0) {
            if !store.error.isEmpty { Text(store.error).foregroundStyle(.orange).textSelection(.enabled).padding(.horizontal, 20) }
            if store.error.isEmpty && !operationStatus.isEmpty {
                HStack {
                    Text(operationStatus).lineLimit(2)
                    Spacer()
                    if store.undoManager.canUndo && store.undoManager.undoActionName == "Delete Space" {
                        Button("Undo") {
                            store.undoManager.undo()
                            spaceID = store.focusedSpace; boardID = store.focusedBoard
                            operationStatus = store.focusedSpace == nil ? "Space could not be restored" : "Space restored"
                        }
                    }
                }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 20).padding(.vertical, 4)
            }
            if let space {
                if !focusCanvas { HStack(spacing: 12) {
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
                        Button("Developer handoff · this space (\(space.boards.count) typeboards)…") { exportHandoff(space) }.disabled(space.boards.isEmpty)
                        Button("Export Space JSON · “\(space.displayName)”…") { exportSpace(space) }
                        Button("Import space…") { importSpace() }.disabled(store.readBlocked)
                        Divider()
                        Button("Delete space…", role: .destructive) { confirmDelete = true }
                    } label: { Image(systemName: "ellipsis") }.shelfIconMenu().help("Space actions").accessibilityLabel("Space actions")
                }
                .frame(minHeight: WorkspaceHeaderLayout.rowHeight)
                .padding(.horizontal, WorkspaceHeaderLayout.horizontalPadding)
                .padding(.vertical, WorkspaceHeaderLayout.verticalPadding)
                .padding(.leading, sidebarCollapsed ? WorkspaceSidebarLayout.revealWidth + 8 : 0)
                .fixedSize(horizontal: false, vertical: true) }
                if !focusCanvas { Divider() }
                if let board {
                    TypeBoardEditor(library: library, savedBoard: board, projectName: space.displayName, projectBoards: space.boards, focusCanvas: $focusCanvas, sidebarCollapsed: $sidebarCollapsed, onSave: { edited, action in
                        _ = store.update(space: space.id, board: edited, action: action)
                        return store.state.spaces.first(where: { $0.id == space.id })?.boards.first(where: { $0.id == edited.id }) ?? board
                    }, onDelete: {
                        if store.removeBoard(space: space.id, id: board.id) { boardID = store.focusedBoard }
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
        .onChange(of: store.focusedSpace) { id in
            spaceID = id; boardID = store.focusedBoard
            if let deleted = lastDeletedSpace {
                if id == deleted.id { operationStatus = "Restored “\(deleted.name)” and \(deleted.boards) \(deleted.boards == 1 ? "typeboard" : "typeboards")" }
                else if id == nil && !store.state.spaces.contains(where: { $0.id == deleted.id }) {
                    operationStatus = "Deleted “\(deleted.name)” and \(deleted.boards) \(deleted.boards == 1 ? "typeboard" : "typeboards")."
                }
            }
        }
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
        .alert("Delete “\(space?.displayName ?? "space")”?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) {
                if let target = space, store.removeSpace(target.id) {
                    spaceID = nil; boardID = nil
                    lastDeletedSpace = (target.id, target.displayName, target.boards.count)
                    operationStatus = "Deleted “\(target.displayName)” and \(target.boards.count) \(target.boards.count == 1 ? "typeboard" : "typeboards")."
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This removes all \(space?.boards.count ?? 0) typeboards in the space. You can restore the space with Undo (⌘Z).") }
        .alert("Delete “\(deletingBoard?.board.name ?? "typeboard")”?", isPresented: Binding(get: { deletingBoard != nil }, set: { if !$0 { deletingBoard = nil } })) {
            Button("Delete", role: .destructive) { if let target = deletingBoard, store.removeBoard(space: target.space, id: target.board.id), boardID == target.board.id { boardID = store.focusedBoard }; deletingBoard = nil }
            Button("Cancel", role: .cancel) { deletingBoard = nil }
        } message: { Text("Its canvases will be removed from this space. You can undo this with ⌘Z.") }
    }
    var navigation: some View {
        VStack(alignment: .leading, spacing: 6) {
            WorkspaceSidebarHeader(library: library, collapsed: $sidebarCollapsed)
            VStack(alignment: .leading, spacing: 14) {
                HStack { Text("Spaces").font(.caption.weight(.semibold)).foregroundStyle(.secondary); Spacer(); Button { showNewSpace = true } label: { Image(systemName: "plus") }.help("New space").disabled(store.readBlocked) }
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                    ForEach(store.state.spaces) { item in
                        HStack(spacing: 8) {
                            Button { selectSpace(item.id) } label: { Image(systemName: "rectangle.3.group") }.buttonStyle(.plain).accessibilityLabel("Open " + item.displayName)
                            ShelfEditableName(name: item.displayName, selected: space?.id == item.id, onSelect: { selectSpace(item.id) }, onRename: { setSpaceName(item.id, $0) })
                        }.fontWeight(.medium).padding(10)
                            .background(space?.id == item.id ? Color.accentColor.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(space?.id == item.id ? Color.accentColor.opacity(0.75) : .clear, lineWidth: 1))
                            .contextMenu { Button("Rename space…") { renameSpace(item) } }
                        ForEach(item.boards) { child in
                            StudioBoardRow(name: child.name, selected: board?.id == child.id, onSelect: { if store.select(space: item.id, board: child.id) { spaceID = item.id; boardID = child.id } }, onRename: {
                                if let name = ShelfRename.prompt("Rename typeboard", current: child.name) { var renamed = child; renamed.name = name; store.update(space: item.id, board: renamed, action: "Rename Typeboard") }
                            }, onRenameInline: { name in var renamed = child; renamed.name = name; return store.update(space: item.id, board: renamed, action: "Rename Typeboard") }, onDelete: { deletingBoard = (item.id, child) })
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
    func selectSpace(_ id: UUID) { if store.select(space: id) { spaceID = id; boardID = nil } }
    func setSpaceName(_ id: UUID, _ name: String) -> Bool { store.renameSpace(id, to: name) }
    func transferReport(_ format: StudioTransferReport.Format, space: DesignSpace) -> StudioTransferReport {
        let canvasCount = space.boards.reduce(0) { $0 + $1.directions.count }
        return StudioTransferReport(format: format,
                                    scope: "Space “\(space.displayName)” · \(space.boards.count) typeboards · \(canvasCount) canvases",
                                    directions: space.boards.flatMap(\.directions),
                                    availableFonts: Set(library.allFaces.map(\.name)))
    }
    func exportHandoff(_ space: DesignSpace) {
        guard StudioTransferDialog.confirm(transferReport(.developerHandoff, space: space)) else { return }
        do { if let folder = try DeveloperHandoff.selectFolder(title: space.displayName, boards: space.boards, catalog: library.families) { store.error = ""; operationStatus = "Exported developer handoff for “\(space.displayName)”"; NSWorkspace.shared.activateFileViewerSelecting([folder]) } }
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
        guard StudioTransferDialog.confirm(transferReport(.spaceJSON, space: space)) else { return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "\(space.name).typefield.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try JSONEncoder().encode(space).write(to: url, options: .atomic); operationStatus = "Exported “\(space.displayName)” Space JSON" } catch { store.error = error.localizedDescription }
    }
    func importSpace() {
        guard !store.readBlocked else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            var space = try JSONDecoder().decode(DesignSpace.self, from: TypefieldInputFile.read(url, maximumBytes: 256_000_000))
            guard space.boards.allSatisfy(\.isValid) else { throw CocoaError(.fileReadCorruptFile) }
            space.id = UUID()
            for i in space.boards.indices { space.boards[i].id = UUID(); space.boards[i].directions = space.boards[i].directions.map { $0.copy(name: $0.name) }; space.boards[i].selectedDirection = nil }
            if store.importSpace(space) {
                spaceID = space.id; boardID = nil
                operationStatus = "Imported “\(space.displayName)” from Space JSON"
                StudioTransferDialog.showImport(StudioImportReport(source: "Space JSON", boards: space.boards, availableFonts: Set(library.allFaces.map(\.name))), name: space.displayName)
            }
        } catch { store.error = "Space could not be imported: " + error.localizedDescription }
    }
    func importFigma() {
        guard !store.readBlocked else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]
        panel.message = "In the Typefield Figma bridge, export selected frames to Typefield, then choose that JSON file. Native .fig files are not supported."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let imported = try FigmaLayoutImporter.board(data: TypefieldInputFile.read(url, maximumBytes: 20_000_000), fonts: library.allFaces)
            if store.importBoard(imported, into: space?.id, defaultSpaceName: "Figma imports") {
                spaceID = store.focusedSpace; boardID = imported.id
                operationStatus = "Imported “\(imported.name)” from Figma"
                StudioTransferDialog.showImport(StudioImportReport(source: "Figma", boards: [imported], availableFonts: Set(library.allFaces.map(\.name))), name: imported.name)
            }
        } catch { store.error = "Figma layout could not be imported: " + error.localizedDescription }
    }
    func importAdobe() {
        guard !store.readBlocked else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]
        panel.message = "Run Typefield's return bridge inside Illustrator or InDesign, save its JSON, then choose that file here. Native .ai and .indd files are not decoded directly."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let imported = try AdobeTypeSystemReturnBridge.board(data: TypefieldInputFile.read(url, maximumBytes: 20_000_000), fonts: library.allFaces)
            if store.importBoard(imported, into: space?.id, defaultSpaceName: "Adobe imports") {
                spaceID = store.focusedSpace; boardID = imported.id
                operationStatus = "Imported “\(imported.name)” from Adobe"
                StudioTransferDialog.showImport(StudioImportReport(source: "Adobe return JSON", boards: [imported], availableFonts: Set(library.allFaces.map(\.name))), name: imported.name)
            }
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

enum CanvasFrameCorner: CaseIterable, Hashable {
    case topLeft, topRight, bottomLeft, bottomRight
    var left: Bool { self == .topLeft || self == .bottomLeft }
    var top: Bool { self == .topLeft || self == .topRight }
}
enum CanvasFrameEdge: String, CaseIterable, Hashable {
    case left, right, top, bottom
    var horizontal: Bool { self == .left || self == .right }
    var leading: Bool { self == .left || self == .top }
}

enum CanvasBoardLayout {
    struct TextContentBounds {
        var minX: Double
        var minY: Double
        var width: Double
        var height: Double
    }
    struct ResizeResult {
        var scale: Double
        var width: Double
        var importedWidth: Double?
        var height: Double?
        var position: CanvasBoardPosition
        var warning: String?
    }
    static func positions(for canvases: [TypeDirection]) -> [UUID: CanvasBoardPosition] {
        var result: [UUID: CanvasBoardPosition] = [:]
        var nextX = 24.0
        for canvas in canvases {
            let position = canvas.boardPosition ?? CanvasBoardPosition(x: nextX, y: 52)
            result[canvas.id] = position
            nextX = max(nextX, position.x + CanvasPlanCache.plan(for: canvas).size.width + 32)
        }
        return result
    }
    static func visibleOffset(for visible: [TypeDirection], positions: [UUID: CanvasBoardPosition]) -> CGSize {
        let left = visible.compactMap { positions[$0.id]?.x }.min() ?? 24
        let top = visible.compactMap { positions[$0.id]?.y }.min() ?? 52
        return CGSize(width: 24 - left, height: 52 - top)
    }
    static func moved(from position: CanvasBoardPosition, by translation: CGSize, zoom: Double) -> CanvasBoardPosition {
        CanvasBoardPosition(x: min(100_000, max(0, position.x + translation.width / max(0.01, zoom))),
                            y: min(100_000, max(0, position.y + translation.height / max(0.01, zoom))))
    }
    static func frameControlsAreActive(canvasID: UUID, selectedDirectionID: UUID?, frameCanvasID: UUID?) -> Bool {
        selectedDirectionID == canvasID || frameCanvasID == canvasID
    }
    static func resized(canvas: TypeDirection, artboardSize: CGSize, position: CanvasBoardPosition,
                        corner: CanvasFrameCorner, by translation: CGSize, zoom: Double) -> ResizeResult {
        let originalScale = canvas.canvasScale ?? 1
        let baseWidth = artboardSize.width / originalScale
        let baseHeight = artboardSize.height / originalScale
        let horizontal = (corner.left ? -translation.width : translation.width) / max(1, baseWidth * zoom)
        let vertical = (corner.top ? -translation.height : translation.height) / max(1, baseHeight * zoom)
        let change = abs(horizontal) >= abs(vertical) ? horizontal : vertical
        let scale = min(canvas.maximumCanvasScale, max(canvas.minimumCanvasScale, originalScale + change))
        let x = corner.left ? position.x + (originalScale - scale) * baseWidth : position.x
        let y = corner.top ? position.y + (originalScale - scale) * baseHeight : position.y
        var fitted = canvas
        fitted.canvasScale = scale
        let plan = CanvasPlan(direction: fitted)
        let bounds = textContentBounds(in: plan)
        let width = artboardSize.width * scale / originalScale
        let height = artboardSize.height * scale / originalScale
        if bounds.minX < 0 || bounds.minY < 0 || bounds.width > width + 0.5 || bounds.height > height + 0.5 || width > 10_000 || height > 10_000 {
            return ResizeResult(scale: originalScale, width: canvas.width, importedWidth: canvas.canvasWidth, height: canvas.canvasHeight,
                                position: position, warning: "Canvas resize was canceled because the text does not fit within the export-safe artboard limits.")
        }
        return ResizeResult(scale: scale, width: canvas.width, importedWidth: canvas.canvasWidth, height: canvas.canvasHeight,
                            position: CanvasBoardPosition(x: min(100_000, max(0, x)), y: min(100_000, max(0, y))), warning: nil)
    }
    static func resized(canvas: TypeDirection, artboardSize: CGSize, position: CanvasBoardPosition,
                        edge: CanvasFrameEdge, by translation: CGSize, zoom: Double) -> ResizeResult {
        let scale = canvas.canvasScale ?? 1
        let baseHeight = canvas.canvasHeight ?? artboardSize.height / scale
        let delta = edge.horizontal
            ? (edge.leading ? -translation.width : translation.width) / max(0.01, zoom * scale)
            : (edge.leading ? -translation.height : translation.height) / max(0.01, zoom * scale)
        let currentWidth = canvas.canvas == .imported ? (canvas.canvasWidth ?? (artboardSize.width / scale)) : canvas.width
        var width = edge.horizontal && canvas.canvas != .imported ? min(1_600, max(320, canvas.width + delta)) : canvas.width
        var importedWidth = canvas.canvas == .imported ? min(10_000, max(1, currentWidth + (edge.horizontal ? delta : 0))) : canvas.canvasWidth
        // Horizontal edge drags must preserve the rendered starting height.
        // Save it explicitly so responsive reflow cannot shrink the orthogonal
        // dimension; only the later text-fit check may grow it.
        var height: Double? = edge.horizontal ? baseHeight : min(canvas.maximumCanvasHeight, max(canvas.minimumCanvasHeight, baseHeight + delta))
        var candidate = canvas
        candidate.width = width
        candidate.canvasWidth = importedWidth
        candidate.canvasHeight = height
        var warning: String?
        if edge.horizontal {
            // Rebuild after changing width so responsive layouts, wraps, and
            // explicitly positioned text all contribute to the safe bounds.
            for _ in 0..<5 {
                candidate.width = width
                candidate.canvasWidth = importedWidth
                let required = textContentBounds(in: CanvasPlan(direction: candidate)).width
                if canvas.canvas == .imported {
                    if required > 10_000 {
                        importedWidth = canvas.canvasWidth
                        warning = "Canvas width cannot be reduced without clipping text; resize was canceled."
                        break
                    }
                    let next = min(10_000, max(importedWidth ?? currentWidth, required))
                    if abs(next - (importedWidth ?? currentWidth)) < 0.5 { break }
                    importedWidth = next
                } else {
                    if required > 1_600 {
                        width = canvas.width
                        warning = "Canvas width cannot be reduced without clipping text; resize was canceled."
                        break
                    }
                    let next = min(1_600, max(width, required))
                    if abs(next - width) < 0.5 { break }
                    width = next
                }
            }
        }
        candidate.width = width
        candidate.canvasWidth = importedWidth
        if let requestedHeight = height {
            let required = textContentBounds(in: CanvasPlan(direction: candidate)).height
            if required > canvas.maximumCanvasHeight {
                height = canvas.canvasHeight ?? baseHeight
                warning = "Canvas height cannot be reduced without clipping text; resize was canceled."
            } else { height = min(canvas.maximumCanvasHeight, max(requestedHeight, required)) }
        }
        let appliedDelta = edge.horizontal
            ? (canvas.canvas == .imported ? (importedWidth ?? currentWidth) - currentWidth : width - canvas.width)
            : (height ?? baseHeight) - baseHeight
        let x = edge == .left ? position.x - appliedDelta : position.x
        let y = edge == .top ? position.y - appliedDelta : position.y
        let fittedDirection = {
            var value = canvas
            value.width = width; value.canvasWidth = importedWidth; value.canvasHeight = height
            return value
        }()
        let fittedPlan = CanvasPlan(direction: fittedDirection)
        let bounds = textContentBounds(in: fittedPlan)
        // A vertical gesture holds the rendered width, which can exceed the
        // stored template width when an unbreakable text run needs more room.
        // Imported legacy plans likewise use their already-expanded width.
        let targetWidth = edge.horizontal
            ? (canvas.canvas == .imported ? (importedWidth ?? currentWidth) : width) * scale
            : fittedPlan.artboardSize.width
        let targetHeight = (height ?? (fittedPlan.artboardSize.height / scale)) * scale
        if bounds.minX < 0 || bounds.minY < 0 || bounds.width > targetWidth + 0.5 || bounds.height > targetHeight + 0.5 || targetWidth > 10_000 || targetHeight > 10_000 {
            width = canvas.width; importedWidth = canvas.canvasWidth; height = canvas.canvasHeight
            warning = "Canvas resize was canceled because the text does not fit within the export-safe artboard limits."
            return ResizeResult(scale: scale, width: width, importedWidth: importedWidth, height: height, position: position, warning: warning)
        }
        return ResizeResult(scale: scale, width: width, importedWidth: importedWidth, height: height,
                            position: CanvasBoardPosition(x: min(100_000, max(0, x)), y: min(100_000, max(0, y))), warning: warning)
    }
    static func textContentBounds(in plan: CanvasPlan, padding: Double = 12) -> TextContentBounds {
        var maxX = 0.0, maxY = 0.0
        var minX = 0.0, minY = 0.0
        for element in plan.elements where element.text != nil {
            maxX = max(maxX, Double(element.rect.maxX))
            maxY = max(maxY, Double(element.rect.maxY))
            minX = min(minX, Double(element.rect.minX))
            minY = min(minY, Double(element.rect.minY))
            guard let text = element.text, text.length > 0 else { continue }
            let storage = NSTextStorage(attributedString: text)
            let layout = NSLayoutManager(); layout.usesFontLeading = true
            let container = NSTextContainer(containerSize: CGSize(width: max(1, element.rect.width), height: .greatestFiniteMagnitude))
            container.lineFragmentPadding = 0
            layout.addTextContainer(container); storage.addLayoutManager(layout)
            layout.ensureLayout(for: container)
            let used = layout.usedRect(for: container).offsetBy(dx: element.rect.minX, dy: element.rect.minY)
            maxX = max(maxX, Double(used.maxX))
            maxY = max(maxY, Double(used.maxY))
            minX = min(minX, Double(used.minX))
            minY = min(minY, Double(used.minY))
            maxX = max(maxX, Double(element.rect.minX) + minimumTextFrameWidth(for: element))
        }
        return TextContentBounds(minX: minX, minY: minY, width: ceil(maxX + padding), height: ceil(maxY + padding))
    }
    static func minimumTextFrameWidth(for element: CanvasElement) -> Double {
        guard let text = element.text, text.length > 0 else { return Double(element.rect.width) }
        let source = text.string as NSString
        let tokenMatcher = try? NSRegularExpression(pattern: #"\S+"#)
        var required = Double(element.rect.width)
        var paragraphEnd = 0
        var tokenWidths: [NSAttributedString: Double] = [:]
        tokenMatcher?.enumerateMatches(in: text.string, range: NSRange(location: 0, length: source.length)) { match, _, _ in
            guard let range = match?.range, range.length > 0 else { return }
            let token = text.attributedSubstring(from: range)
            let tokenWidth: Double
            if let cached = tokenWidths[token] { tokenWidth = cached }
            else {
                tokenWidth = CTLineGetTypographicBounds(CTLineCreateWithAttributedString(token as CFAttributedString),nil,nil,nil)
                if tokenWidths.count < 512 { tokenWidths[token] = tokenWidth }
            }
            // Each paragraph is scanned once, rather than once per word.
            // The first regex match in a paragraph is its first nonblank token.
            let isFirstToken = range.location >= paragraphEnd
            if isFirstToken { paragraphEnd = NSMaxRange(source.paragraphRange(for: NSRange(location:range.location,length:0))) }
            let paragraphStyle = token.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
            let indent = isFirstToken ? max(0, paragraphStyle?.firstLineHeadIndent ?? 0) : 0
            required = max(required, tokenWidth + Double(indent))
        }
        return ceil(required)
    }
}

private struct CanvasFrameInteraction {
    enum Mode {
        case move, resizeCorner(CanvasFrameCorner), resizeEdge(CanvasFrameEdge)
        var isResize: Bool { if case .move = self { return false }; return true }
    }
    var id: UUID
    var mode: Mode
    var translation: CGSize
}

private struct CanvasFrameDisplay {
    var direction: TypeDirection
    var position: CanvasBoardPosition
}
private struct CanvasSoloViewport {
    var id: UUID
    var offset: CGSize
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
        width.isFinite && (canvas == .imported ? (1...10000).contains(width) : (320...1600).contains(width)) && (canvasWidth.map { canvas == .imported && $0.isFinite && (1...10000).contains($0) } ?? true) && (canvasHeight.map { $0.isFinite && (minimumCanvasHeight...maximumCanvasHeight).contains($0) } ?? true) && (boardPosition?.isValid ?? true) && (canvasScale.map { $0.isFinite && $0 >= minimumCanvasScale && $0 <= maximumCanvasScale } ?? true) && (importedLayout?.isValid ?? (canvas != .imported)) && artworkLayersAreValid && (textOverrides.map { $0.count <= 5000 && $0.values.allSatisfy(Self.acceptsCanvasText) } ?? true) && (textPositions.map { $0.count <= 5000 && $0.values.allSatisfy(\.isValid) } ?? true) && TypeRole.allCases.allSatisfy { role in
            guard let s = styles[role.rawValue] else { return false }
            return s.size.isFinite && (8...160).contains(s.size) && s.leading.isFinite && (1...2.5).contains(s.leading) && s.tracking.isFinite && (-3...12).contains(s.tracking) && s.axes.values.allSatisfy(\.isFinite) && (s.lineHeight.map { $0.isFinite && (8...400).contains($0) } ?? true) && [s.paragraphSpacing, s.indent].allSatisfy { $0.map { $0.isFinite && (0...200).contains($0) } ?? true } && (s.wordSpacing.map { $0.isFinite && (-3...40).contains($0) } ?? true)
        }
    }
}

struct TypeBoardEditor: View {
    @ObservedObject var library: Library
    @Environment(\.colorSchemeContrast) private var contrast
    @StateObject var editorSession: StudioEditorSession
    let savedBoard: TypeBoard
    let projectName: String
    let projectBoards: [TypeBoard]
    @Binding var focusCanvas: Bool
    @Binding var sidebarCollapsed: Bool
    let onSave: (TypeBoard, String) -> TypeBoard
    let onDelete: () -> Void
    init(library: Library, savedBoard: TypeBoard, projectName: String, projectBoards: [TypeBoard], focusCanvas: Binding<Bool>, sidebarCollapsed: Binding<Bool>, onSave: @escaping (TypeBoard, String) -> TypeBoard, onDelete: @escaping () -> Void) {
        self.library = library; self.savedBoard = savedBoard; self.projectName = projectName; self.projectBoards = projectBoards; self._focusCanvas = focusCanvas; self._sidebarCollapsed = sidebarCollapsed; self.onSave = onSave; self.onDelete = onDelete
        _editorSession = StateObject(wrappedValue: StudioEditorSession(board: savedBoard))
        _inspectorMode = State(initialValue: StudioInspectorPreference.mode())
        let initialCanvasIDs = Set([savedBoard.selectedDirection ?? savedBoard.directions.first?.id].compactMap { $0 })
        _shownCanvasIDs = State(initialValue: initialCanvasIDs)
        _summaryCanvasIDs = State(initialValue: initialCanvasIDs)
    }
    @State private var shownCanvasIDs: Set<UUID>
    @State private var zoom = 0.0
    @State private var showDelete = false
    @State private var artworkImportError: String?
    @State private var status = ""
    @State private var showPairingSuggestions = false
    @State private var pairingTargetRole = TypeRole.body
    @State private var showFontSummary = false
    @State private var showWebFontAudit = false
    @State private var fontSummaryDetail = TypographySummaryDetail.roles
    @State private var summaryCanvasIDs: Set<UUID>
    @State private var draggedSection: String?
    @State private var frameCanvasID: UUID?
    @State private var frameInteraction: CanvasFrameInteraction?
    @State private var interactionZoom: Double?
    @State private var soloViewport: CanvasSoloViewport?
    @State private var abID: UUID?
    @State private var inspectorMode: StudioInspectorMode
    @State private var showRailInspector = false
    @State private var floatingInspector = StudioFloatingInspector()
    @State private var sidebarBeforeFocus = false
    @State private var inspectorBeforeFocus = StudioInspectorMode.expanded
    @State private var inspectorBeforeFloating = StudioInspectorMode.expanded
    @State private var discoveryNonce: UInt64 = 0
    @FocusState private var fontSearchFocused: Bool
    var board: TypeBoard { get { editorSession.board } nonmutating set { editorSession.board = newValue } }
    var role: TypeRole { get { editorSession.role } nonmutating set { editorSession.role = newValue } }
    var fontSearch: String { get { editorSession.fontSearch } nonmutating set { editorSession.fontSearch = newValue } }
    var fontCollection: String { get { editorSession.fontCollection } nonmutating set { editorSession.fontCollection = newValue } }
    var fontCategory: String { get { editorSession.fontCategory } nonmutating set { editorSession.fontCategory = newValue } }
    var selectedTextID: String? { get { editorSession.selectedTextID } nonmutating set { editorSession.selectedTextID = newValue } }
    var selectedSection: String? { get { editorSession.selectedSection } nonmutating set { editorSession.selectedSection = newValue } }
    var inspectorTab: String { get { editorSession.inspectorTab } nonmutating set { editorSession.inspectorTab = newValue } }
    var showFontPicker: Bool { get { editorSession.showFontPicker } nonmutating set { editorSession.showFontPicker = newValue } }
    var directionIndex: Int { board.directions.firstIndex { $0.id == board.selectedDirection } ?? 0 }
    var direction: TypeDirection { board.directions[directionIndex] }
    var visibleDirections: [TypeDirection] { board.directions.filter { shownCanvasIDs.contains($0.id) || $0.id == direction.id } }
    var showingAllCanvases: Bool { !board.directions.isEmpty && Set(board.directions.map(\.id)).isSubset(of: shownCanvasIDs) }
    var importedLayerIndex: Int? { guard direction.canvas == .imported else { return nil }; return direction.importedLayout?.textLayerIndex(selectedID: selectedSection) }
    var importedNonTextSelected: Bool { direction.canvas == .imported && importedLayerIndex == nil }
    var selectedImportedShapeIndex: Int? {
        guard direction.canvas == .imported, let selectedSection else { return nil }
        return direction.importedLayout?.layers.firstIndex { $0.id == selectedSection && $0.style == nil && $0.artworkData == nil }
    }
    var selectedImportedShape: ImportedLayer? { selectedImportedShapeIndex.flatMap { direction.importedLayout?.layers[$0] } }
    var selectedArtworkIndex: Int? {
        guard let selectedSection else { return nil }
        return direction.artworkLayers?.firstIndex { $0.id == selectedSection && $0.artworkData != nil }
    }
    var selectedArtwork: ImportedLayer? { selectedArtworkIndex.flatMap { direction.artworkLayers?[$0] } }
    var selectedText: CanvasElement? { guard let selectedTextID else { return nil }; return CanvasPlanCache.plan(for: direction).elements.first { $0.textID == selectedTextID } }
    var style: TypeStyle {
        if let index = importedLayerIndex, let style = direction.importedLayout?.layers[index].style { return style }
        var base = direction.style(role)
        if let selectedTextID { base.text = direction.textOverrides?[selectedTextID] ?? selectedText?.style?.text ?? base.text }
        return base
    }
    var selectedSummaryDirections: [TypeDirection] { board.directions.filter { summaryCanvasIDs.contains($0.id) } }
    var fontSummary: TypographySummaryDocument { TypographySummaryDocument(summaries: selectedSummaryDirections.map { CanvasTypographySummary(canvas: board.canvasName($0), direction: $0) }) }
    var visibleFontCount: Int { TypographySummaryDocument(summaries: visibleDirections.map { CanvasTypographySummary(canvas: board.canvasName($0), direction: $0) }).fonts.count }
    func confirmExport(_ format: StudioTransferReport.Format, directions: [TypeDirection], scope: String) -> Bool {
        StudioTransferDialog.confirm(StudioTransferReport(format: format, scope: scope, directions: directions,
                                                          availableFonts: Set(library.allFaces.map(\.name))))
    }
    var editingTitle: String { if let index = importedLayerIndex { return direction.importedLayout?.layers[index].name ?? "Text layer" }; return role.rawValue }
    var editingScopeLabel: String {
        if let shape = selectedImportedShape { return "Editing object: “\(shape.name)” · affects 1 shape" }
        if let artwork = selectedArtwork { return "Editing object: “\(artwork.name)” · affects 1 image" }
        if direction.canvas == .imported {
            if importedLayerIndex != nil { return "Editing layer: “\(editingTitle)” · affects 1 text object" }
            return "Select an imported text layer or object"
        }
        let count = StudioRoleScope.affectedTextCount(role: role, direction: direction)
        return "Editing role: \(role.rawValue) · affects \(count) text \(count == 1 ? "object" : "objects")"
    }
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
    @discardableResult func save(_ action: String = "Edit Typeboard") -> Bool {
        let proposed = board
        let persisted = onSave(proposed, action)
        guard persisted == proposed else { board = persisted; return false }
        return true
    }
    func updateSelectedShape(_ action: String, _ change: (inout ImportedLayer) -> Void) {
        guard let index = selectedImportedShapeIndex, var layout = board.directions[directionIndex].importedLayout else { return }
        change(&layout.layers[index])
        board.directions[directionIndex].importedLayout = layout
        save(action)
    }
    func updateSelectedArtwork(_ action: String, _ change: (inout ImportedLayer) -> Void) {
        guard let index = selectedArtworkIndex else { return }
        change(&board.directions[directionIndex].artworkLayers![index])
        save(action)
    }
    func directionBinding<T>(_ key: WritableKeyPath<TypeDirection, T>) -> Binding<T> { Binding(get: { direction[keyPath: key] }, set: { board.directions[directionIndex][keyPath: key] = $0; save() }) }
    func styleBinding<T>(_ key: WritableKeyPath<TypeStyle, T>) -> Binding<T> { Binding(get: { style[keyPath: key] }, set: { var updated = style; updated[keyPath: key] = $0; setStyle(updated); save(key == \TypeStyle.size ? "Change Size" : key == \TypeStyle.tracking ? "Change Letter Spacing" : key == \TypeStyle.text ? "Change Sample Text" : "Edit Typography") }) }
    func typeboardToolbar(compact: Bool) -> some View {
        HStack(spacing: compact ? 7 : 12) {
                ShelfEditableName(name: board.name, onRename: { name in board.name = name; return save("Rename Typeboard") })
                    .font(.headline).lineLimit(1).frame(minWidth: compact ? 90 : 110, maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: compact ? 4 : 12)
                Menu {
                    Button("Blank canvas") { let canvas = TypeDirection(name: board.nextCanvasName); board.directions.append(canvas); board.selectedDirection = canvas.id; summaryCanvasIDs.insert(canvas.id); save("Add Canvas") }
                    Button("Duplicate current canvas") { let copy = direction.copy(name: board.nextCanvasName); board.directions.append(copy); board.selectedDirection = copy.id; summaryCanvasIDs.insert(copy.id); save("Duplicate Canvas") }
                } label: { Image(systemName: "plus") }.shelfIconMenu().help("Add a canvas").accessibilityLabel("Add a canvas")
                Button { chooseArtwork() } label: {
                    if compact { Image(systemName: "photo.on.rectangle") }
                    else { Label("Artwork…", systemImage: "photo.on.rectangle") }
                }
                    .fixedSize().help("Import SVG, PNG, JPEG, TIFF, HEIC, BMP, or GIF artwork onto this canvas. You can also drop a file directly onto a canvas.")
                    .accessibilityLabel("Import artwork onto this canvas")
                Button { openFontSummary() } label: {
                    if compact { Label("\(visibleFontCount)", systemImage: "textformat") }
                    else { Label("\(visibleFontCount) fonts · \(visibleDirections.count) shown", systemImage: "textformat") }
                }
                    .fixedSize().accessibilityLabel("Typography summary: \(visibleFontCount) fonts across \(visibleDirections.count) shown canvases")
                    .popover(isPresented: $showFontSummary) { fontSummaryPopover }
                Menu("Export") {
                    Button("Typography summary · shown canvases…") { openFontSummary() }
                    Button("Web-font performance · shown canvases…") { summaryCanvasIDs = Set(visibleDirections.map(\.id)); showWebFontAudit = true }
                    Button("Developer handoff · this typeboard (\(board.directions.count) canvases)…") { exportDeveloperHandoff() }
                    Divider()
                    Button("Preview PDF · \(board.canvasName(direction))…") { exportPDF() }
                    Button("Editable Figma layout · this typeboard (\(board.directions.count) canvases)…") { exportFigma() }
                }.fixedSize()
                Menu {
                    Button("Save checkpoint") { saveCheckpoint() }
                    Text("\((board.checkpoints ?? []).count) of \(StudioCheckpointSave.maximumCount) checkpoints saved")
                    Text("After 50, the oldest is replaced")
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
            }.padding(.horizontal, 12).padding(.vertical, 8).fixedSize(horizontal: false, vertical: true)
    }
    var body: some View {
        VStack(spacing: 0) {
            if !focusCanvas {
            ViewThatFits(in: .horizontal) {
                typeboardToolbar(compact: false)
                typeboardToolbar(compact: true)
            }
            HStack(spacing: 8) {
                inspectorLayoutMenu
                Divider().frame(height: 20)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) { ForEach(board.directions) { canvas in
                        Button { selectCanvas(canvas.id) } label: {
                            HStack(spacing: 6) {
                                if shownCanvasIDs.contains(canvas.id) || canvas.id == direction.id { Circle().fill(Color.accentColor).frame(width: 5, height: 5) }
                                Text(board.canvasName(canvas)).lineLimit(1)
                            }
                            .font(.subheadline)
                            .padding(.horizontal, 9).padding(.vertical, 5)
                            .background(canvas.id == direction.id ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 7))
                            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(canvas.id == direction.id ? Color.accentColor : Color.primary.opacity(contrast == .increased ? 0.35 : 0.08), lineWidth: canvas.id == direction.id && contrast == .increased ? 1.5 : 1))
                        }.buttonStyle(.plain).help("Edit and show " + board.canvasName(canvas))
                            .accessibilityValue(canvas.id == direction.id ? "Editing" : shownCanvasIDs.contains(canvas.id) ? "Shown" : "Hidden")
                    } }
                }
                Divider().frame(height: 20)
                Menu {
                    Menu("Format") {
                        ForEach(CanvasKind.allCases.filter { $0 != .imported || direction.importedLayout != nil }, id: \.self) { kind in
                            Button(kind == .imported ? direction.canvasDisplayName : kind.rawValue) { directionBinding(\.canvas).wrappedValue = kind }
                        }
                    }
                    if direction.canvas != .imported {
                        Menu("Width") {
                            Button("Mobile · 390") { directionBinding(\.width).wrappedValue = 390 }
                            Button("Tablet · 768") { directionBinding(\.width).wrappedValue = 768 }
                            Button("Desktop · 1200") { directionBinding(\.width).wrappedValue = 1200 }
                            Button("Canvas · 960") { directionBinding(\.width).wrappedValue = 960 }
                        }
                    }
                } label: {
                    Label(direction.canvasDisplayName + " · \(Int(direction.width)) \(direction.canvasUnitLabel)", systemImage: "rectangle.dashed")
                        .lineLimit(1)
                }.fixedSize().help("Change canvas format or width")
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
                        let candidates = board.directions.filter { $0.id != direction.id && $0.canvas == direction.canvas && $0.width == direction.width && $0.canvasWidth == direction.canvasWidth && $0.canvasHeight == direction.canvasHeight && $0.canvasScale == direction.canvasScale }
                        if candidates.isEmpty { Text("Duplicate a canvas to start"); Text("Use the same format, width, and scale") }
                        ForEach(candidates) { candidate in Button(board.canvasName(candidate)) { abID = candidate.id; shownCanvasIDs = [direction.id] } }
                    }.disabled(board.directions.count < 2)
                } label: { Label(abID != nil ? "A/B" : "\(visibleDirections.count) shown", systemImage: "eye") }.fixedSize().help("Choose exactly which canvases are visible")
                if abID != nil { Button { swapAB() } label: { Image(systemName: "arrow.left.arrow.right") }.keyboardShortcut("\\", modifiers: [.command]).help("Swap A/B (⌘\\)").accessibilityLabel("Swap A/B") }
                Menu(zoom == 0 ? "Fit width" : "\(Int(zoom * 100))%") { Button("Fit width of visible canvases") { zoom = 0 }; ForEach([0.25, 0.5, 0.75, 1.0, 1.5, 2.0, 3.0], id: \.self) { value in Button("\(Int(value * 100))%") { zoom = value } } }.fixedSize().help("Pinch to zoom, or hold ⌘ while scrolling with a mouse. Scroll normally to pan.")
            }.padding(.horizontal, 12).padding(.bottom, 7).fixedSize(horizontal: false, vertical: true)
            Divider()
            }
            if inspectorMode == .expanded && !focusCanvas {
                HSplitView {
                    inspector.frame(minWidth: StudioInspectorLayout.fullMinimumWidth, idealWidth: StudioInspectorLayout.fullIdealWidth, maxWidth: 500).background(StudioSplitPosition())
                    canvasWorkspace
                }
            } else if inspectorMode == .slim && !focusCanvas {
                HStack(spacing: 0) { slimInspector; Divider(); canvasWorkspace }
            } else {
                canvasWorkspace
            }
        }.alert("Delete this typeboard?", isPresented: $showDelete) { Button("Delete", role: .destructive, action: onDelete); Button("Cancel", role: .cancel) {} }
        .alert("Artwork could not be imported", isPresented: Binding(get: { artworkImportError != nil }, set: { if !$0 { artworkImportError = nil } })) {
            Button("OK") { artworkImportError = nil }
        } message: { Text(artworkImportError ?? "") }
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
        .onChange(of: shownCanvasIDs) { _ in soloViewport = nil }
        .onChange(of: inspectorMode) { mode in
            if mode == .floating {
                let host = StudioFloatingInspectorHost(session: editorSession, library: library) { AnyView(floatingInspectorContent) }
                floatingInspector.show(content: AnyView(host), title: "Typefield · Inspector", relativeTo: NSApp.mainWindow) {
                    inspectorMode = inspectorBeforeFloating
                }
            } else { floatingInspector.close() }
        }
        .onChange(of: direction.id) { id in shownCanvasIDs.insert(id); if !(direction.artworkLayers ?? []).contains(where: { $0.id == selectedSection }) { selectedSection = nil }; selectedTextID = nil; draggedSection = nil; if frameCanvasID != id { frameCanvasID = nil }; if let other = board.directions.first(where: { $0.id == abID }), other.canvas != direction.canvas || other.width != direction.width || other.canvasWidth != direction.canvasWidth || other.canvasHeight != direction.canvasHeight || other.canvasScale != direction.canvasScale { abID = nil } }
        .onChange(of: direction.canvas) { _ in abID = nil; selectedSection = nil; selectedTextID = nil }
        .onChange(of: direction.width) { _ in abID = nil }
        .onDisappear { floatingInspector.close(); if focusCanvas { sidebarCollapsed = sidebarBeforeFocus; focusCanvas = false } }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("TypefieldCanvasFocus"))) { _ in
            if focusCanvas { leaveCanvasFocus(); sidebarCollapsed = false }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("TypefieldMenu"))) { event in
            guard let command = event.object as? String else { return }
            switch command {
            case "find":
                inspectorTab = "Typography"
                if inspectorMode == .hidden { setInspectorMode(.expanded) }
                DispatchQueue.main.async { showFontPicker = true }
            case "studio.previousCanvas": selectAdjacentCanvas(-1)
            case "studio.nextCanvas": selectAdjacentCanvas(1)
            case "studio.canvas.fit": zoom = 0
            case "studio.inspector.full": setInspectorMode(.expanded)
            case "studio.inspector.slim": setInspectorMode(.slim)
            case "studio.inspector.hidden": setInspectorMode(.hidden)
            case "studio.inspector.floating": setInspectorMode(.floating)
            case "studio.inspector.toggle": setInspectorMode(inspectorMode == .hidden ? .expanded : .hidden)
            case "studio.inspector.typography": showInspectorTab("Typography")
            case "studio.inspector.arrangement": showInspectorTab("Arrangement")
            case "studio.canvasFocus":
                if focusCanvas { leaveCanvasFocus() } else { enterCanvasFocus() }
            default: break
            }
        }
    }
    var canvasWorkspace: some View {
        VStack(alignment: .leading, spacing: 0) {
                    if library.loading { ProgressView(library.families.isEmpty ? "Loading font library…" : "Checking watched font folders…").controlSize(.small).padding(10) }
                    else if !missingFonts.isEmpty { Label("Unavailable fonts: " + missingFonts.joined(separator: ", ") + ". Preview uses fallback.", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange).padding(12) }
                    GeometryReader { geometry in
                    let visible = visibleDirections
                    let positions = CanvasBoardLayout.positions(for: board.directions)
                    let calculatedOffset = CanvasBoardLayout.visibleOffset(for: visible, positions: positions)
                    let visibleOffset = visible.count == 1 && soloViewport?.id == visible.first?.id ? soloViewport!.offset : calculatedOffset
                    let committedWidth = visible.count == 1 ? (CanvasPlanCache.plan(for: visible[0]).size.width + 48) : visible.reduce(48.0) { current, item in
                        max(current, (positions[item.id]?.x ?? 24) + visibleOffset.width + CanvasPlanCache.plan(for: item).size.width + 24)
                    }
                    // Leave space for the vertical scroller and the right-hand resize handle.
                    let fittingWidth = max(1, geometry.size.width - 32)
                    let scale = interactionZoom ?? (zoom == 0 ? min(1, max(0.1, fittingWidth / max(1, committedWidth))) : zoom)
                    let extent = canvasWorkspaceExtent(visible, positions: positions, visibleOffset: visibleOffset, zoom: scale)
                    ScrollView([.horizontal, .vertical]) {
                        ZStack(alignment: .topLeading) {
                            ForEach(visible) { item in
                                let display = displayedCanvas(item, positions: positions, zoom: scale)
                                canvas(item, displayed: display.direction, scale: scale)
                                    .offset(x: (display.position.x + visibleOffset.width) * scale,
                                            y: (display.position.y + visibleOffset.height) * scale)
                            }
                        }
                        .frame(width: max(fittingWidth, extent.width * scale),
                               height: max(geometry.size.height, extent.height * scale), alignment: .topLeading)
                    }.background(Color.primary.opacity(0.07)).background(CanvasZoomInput { factor in zoom = CanvasZoomInput.clamped((zoom == 0 ? scale : zoom) * factor) })
                    }
                    if !focusCanvas { HStack { Text(!library.studio.error.isEmpty ? "Changes could not be saved" : status.isEmpty ? "Saved" : status).lineLimit(2); Spacer(); if let partner = board.directions.first(where: { $0.id == abID }) { Text("A/B · " + partner.name).lineLimit(1) }; Text("\(Int(CanvasPlanCache.plan(for: direction).artboardSize.width)) × \(Int(CanvasPlanCache.plan(for: direction).artboardSize.height)) \(direction.canvasUnitLabel) · " + (zoom == 0 ? "Fit width" : "\(Int(zoom * 100))%" )).monospacedDigit() }.font(.caption).foregroundStyle(.secondary).padding(7) }
        }.frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topTrailing) { if focusCanvas { focusControls.padding(12) } }
    }
    var floatingInspectorContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Inspector").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Button("Slim tools") { setInspectorMode(.slim) }.font(.caption).buttonStyle(.borderless)
                Button { setInspectorMode(.expanded) } label: { Label("Dock", systemImage: "sidebar.left") }
                    .font(.caption).buttonStyle(.borderless).help("Dock the full inspector beside the canvas")
            }.padding(.horizontal, 12).padding(.vertical, 7)
            Divider()
            inspector
        }
    }
    var inspectorLayoutMenu: some View {
        Menu {
            ForEach(StudioInspectorMode.allCases, id: \.self) { mode in
                Button { setInspectorMode(mode) } label: {
                    Label((inspectorMode == mode ? "✓ " : "") + mode.title, systemImage: mode.symbol)
                }
            }
            Divider()
            Button { enterCanvasFocus() } label: { Label("Focus canvas", systemImage: "arrow.up.left.and.arrow.down.right") }
            Divider()
            Button("Toggle inspector") { setInspectorMode(inspectorMode == .hidden ? .expanded : .hidden) }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: inspectorMode.symbol).font(.system(size: 13))
                Text("Inspector")
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 8).frame(height: 28)
            .background(Color.accentColor.opacity(0.09), in: RoundedRectangle(cornerRadius: 7))
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .help("Inspector layout: " + inspectorMode.title + ". Choose full, slim, hidden, floating, or canvas focus.")
        .accessibilityLabel("Inspector layout: " + inspectorMode.title)
        .accessibilityIdentifier("spaces-inspector-layout")
    }
    var slimInspector: some View {
        VStack(spacing: 5) {
            railButton("Typography", symbol: "textformat", selected: inspectorTab == "Typography") {
                inspectorTab = "Typography"; showRailInspector = true
            }
            railButton("Arrangement", symbol: "square.3.layers.3d", selected: inspectorTab == "Arrangement") {
                inspectorTab = "Arrangement"; showRailInspector = true
            }
            Spacer(minLength: 8)
            railButton("Float inspector", symbol: StudioInspectorMode.floating.symbol) { setInspectorMode(.floating) }
            railButton("Full inspector", symbol: StudioInspectorMode.expanded.symbol) { setInspectorMode(.expanded) }
            railButton("Hide inspector", symbol: "chevron.left") { setInspectorMode(.hidden) }
        }
        .padding(.vertical, 8)
        .frame(width: StudioInspectorLayout.slimWidth)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
        .popover(isPresented: $showRailInspector, arrowEdge: .trailing) {
            inspector.frame(width: 320, height: 560)
        }
        .accessibilityIdentifier("spaces-inspector-rail")
    }
    func railButton(_ title: String, symbol: String, selected: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 16, weight: .medium))
                .frame(width: 44, height: 44)
                .foregroundStyle(selected ? Color.accentColor : Color.primary)
                .background(selected ? Color.accentColor.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).help(title).accessibilityLabel(title)
    }
    var focusControls: some View {
        HStack(spacing: 6) {
            Menu {
                ForEach(board.directions) { item in
                    Button(board.canvasName(item)) { selectCanvas(item.id) }
                }
            } label: { Label(board.canvasName(direction), systemImage: "rectangle.on.rectangle") }
                .fixedSize().help("Choose canvas")
            Button { leaveCanvasFocus() } label: { Label("Exit focus", systemImage: "arrow.down.right.and.arrow.up.left") }
                .help("Restore the Spaces toolbar and sidebar")
                .accessibilityIdentifier("spaces-exit-focus")
        }
        .font(.caption)
        .padding(7)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9))
        .shelfElevation(.floating)
    }
    func setInspectorMode(_ mode: StudioInspectorMode) {
        if focusCanvas { leaveCanvasFocus(restoreInspector: false) }
        showRailInspector = false
        if mode == .floating && inspectorMode != .floating { inspectorBeforeFloating = inspectorMode }
        inspectorMode = mode
        StudioInspectorPreference.setMode(mode)
    }
    func enterCanvasFocus() {
        guard !focusCanvas else { return }
        sidebarBeforeFocus = sidebarCollapsed
        inspectorBeforeFocus = inspectorMode == .floating ? inspectorBeforeFloating : inspectorMode
        showRailInspector = false
        inspectorMode = .hidden
        sidebarCollapsed = true
        focusCanvas = true
    }
    func leaveCanvasFocus(restoreInspector: Bool = true) {
        guard focusCanvas else { return }
        focusCanvas = false
        sidebarCollapsed = sidebarBeforeFocus
        if restoreInspector { inspectorMode = inspectorBeforeFocus }
    }
    private func displayedCanvas(_ item: TypeDirection, positions: [UUID: CanvasBoardPosition], zoom: Double) -> CanvasFrameDisplay {
        let position = positions[item.id] ?? CanvasBoardPosition(x: 24, y: 52)
        guard let interaction = frameInteraction, interaction.id == item.id else {
            return CanvasFrameDisplay(direction: item, position: position)
        }
        switch interaction.mode {
        case .move:
            return CanvasFrameDisplay(direction: item, position: CanvasBoardLayout.moved(from: position, by: interaction.translation, zoom: zoom))
        case .resizeCorner(let corner):
            let result = CanvasBoardLayout.resized(canvas: item, artboardSize: CanvasPlanCache.plan(for: item).artboardSize,
                                                   position: position, corner: corner, by: interaction.translation, zoom: zoom)
            var rendered = item
            rendered.canvasScale = result.scale
            return CanvasFrameDisplay(direction: rendered, position: result.position)
        case .resizeEdge(let edge):
            let result = CanvasBoardLayout.resized(canvas: item, artboardSize: CanvasPlanCache.plan(for: item).artboardSize,
                                                   position: position, edge: edge, by: interaction.translation, zoom: zoom)
            var rendered = item
            rendered.width = result.width
            rendered.canvasWidth = result.importedWidth
            rendered.canvasHeight = result.height
            return CanvasFrameDisplay(direction: rendered, position: result.position)
        }
    }
    private func canvasWorkspaceExtent(_ visible: [TypeDirection], positions: [UUID: CanvasBoardPosition], visibleOffset: CGSize, zoom: Double) -> CGSize {
        visible.reduce(CGSize(width: 48, height: 120)) { extent, item in
            let display = displayedCanvas(item, positions: positions, zoom: zoom)
            let size = CanvasPlanCache.plan(for: display.direction).size
            return CGSize(width: max(extent.width, display.position.x + visibleOffset.width + size.width + 24),
                          height: max(extent.height, display.position.y + visibleOffset.height + size.height + 58))
        }
    }
    private func beginFrameInteraction(_ id: UUID, mode: CanvasFrameInteraction.Mode, translation: CGSize, zoom: Double) {
        if interactionZoom == nil { interactionZoom = zoom }
        frameCanvasID = id
        frameInteraction = CanvasFrameInteraction(id: id, mode: mode, translation: translation)
    }
    private func finishFrameInteraction(_ id: UUID, mode: CanvasFrameInteraction.Mode, translation: CGSize, zoom: Double) {
        defer { frameInteraction = nil; interactionZoom = nil }
        guard let index = board.directions.firstIndex(where: { $0.id == id }) else { return }
        let wasSelected = board.selectedDirection == id
        let startingDirections = board.directions
        var resizeWarning: String?
        frameCanvasID = id
        let dragged = hypot(translation.width, translation.height) > 2
        if dragged {
            let positions = CanvasBoardLayout.positions(for: board.directions)
            if visibleDirections.count == 1 { soloViewport = CanvasSoloViewport(id: id, offset: CanvasBoardLayout.visibleOffset(for: visibleDirections, positions: positions)) }
            let original = board.directions[index]
            // Freeze the initial row before moving one canvas so its neighbors
            // do not shift when an older board first gains explicit positions.
            for candidate in board.directions.indices where board.directions[candidate].boardPosition == nil {
                board.directions[candidate].boardPosition = positions[board.directions[candidate].id]
            }
            let start = positions[id] ?? CanvasBoardPosition(x: 24, y: 52)
            switch mode {
            case .move:
                board.directions[index].boardPosition = CanvasBoardLayout.moved(from: start, by: translation, zoom: zoom)
            case .resizeCorner(let corner):
                let result = CanvasBoardLayout.resized(canvas: original, artboardSize: CanvasPlanCache.plan(for: original).artboardSize,
                                                       position: start, corner: corner, by: translation, zoom: zoom)
                board.directions[index].boardPosition = result.position
                board.directions[index].canvasScale = result.scale
                resizeWarning = result.warning
            case .resizeEdge(let edge):
                let result = CanvasBoardLayout.resized(canvas: original, artboardSize: CanvasPlanCache.plan(for: original).artboardSize,
                                                       position: start, edge: edge, by: translation, zoom: zoom)
                board.directions[index].boardPosition = result.position
                board.directions[index].width = result.width
                board.directions[index].canvasWidth = result.importedWidth
                board.directions[index].canvasHeight = result.height
                resizeWarning = result.warning
            }
            if resizeWarning != nil { board.directions = startingDirections }
        }
        shownCanvasIDs.insert(id)
        board.selectedDirection = id
        abID = nil
        if let resizeWarning { status = resizeWarning }
        if (dragged && board.directions != startingDirections) || !wasSelected {
            save(dragged ? (mode.isResize ? "Resize Canvas" : "Move Canvas") : "Select Canvas")
        }
    }
    func selectCanvas(_ id: UUID) { frameCanvasID = nil; shownCanvasIDs = CanvasVisibility.selecting(id, from: direction.id, shown: shownCanvasIDs); board.selectedDirection = id; abID = nil; save() }
    func selectAdjacentCanvas(_ offset: Int) {
        guard board.directions.count > 1 else { return }
        let count = board.directions.count
        let next = (directionIndex + offset + count) % count
        selectCanvas(board.directions[next].id)
    }
    func showInspectorTab(_ tab: String) {
        if focusCanvas { leaveCanvasFocus() }
        inspectorTab = tab
        if inspectorMode == .hidden { setInspectorMode(.expanded) }
        else if inspectorMode == .slim { showRailInspector = true }
    }
    func showOnlyCurrent() { shownCanvasIDs = CanvasVisibility.solo(direction.id); abID = nil }
    func hideCanvas(_ id: UUID) { guard id != direction.id else { return }; shownCanvasIDs.remove(id) }
    func swapAB() { guard let id = abID, board.directions.contains(where: { $0.id == id && $0.canvas == direction.canvas && $0.width == direction.width && $0.canvasWidth == direction.canvasWidth && $0.canvasHeight == direction.canvasHeight && $0.canvasScale == direction.canvasScale }) else { return }; abID = direction.id; board.selectedDirection = id; shownCanvasIDs = [id]; save() }
    func moveSection(_ source: String, _ target: String, _ before: Bool) {
        let plan = CanvasPlanCache.plan(for: direction)
        if let layers = direction.artworkLayers, let index = layers.firstIndex(where: { $0.id == source }) {
            guard source != target, layers.contains(where: { $0.id == target }) else { return }
            var reordered = layers
            let artwork = reordered.remove(at: index)
            guard let destination = reordered.firstIndex(where: { $0.id == target }) else { return }
            reordered.insert(artwork, at: destination + (before ? 0 : 1))
            board.directions[directionIndex].artworkLayers = reordered
            selectedSection = source
            save("Reorder Artwork")
            return
        }
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
        if let index = direction.artworkLayers?.firstIndex(where: { $0.id == id }) {
            let scale = direction.canvasScale ?? 1
            let artboard = CanvasPlanCache.plan(for: direction).artboardSize
            let layer = direction.artworkLayers![index]
            board.directions[directionIndex].artworkLayers![index].x = min(max(0, artboard.width / scale - layer.width), max(0, layer.x + dx / scale))
            board.directions[directionIndex].artworkLayers![index].y = min(max(0, artboard.height / scale - layer.height), max(0, layer.y + dy / scale))
            save("Move Artwork")
            return
        }
        guard let index = direction.importedLayout?.layers.firstIndex(where: { $0.id == id }) else { return }
        let scale = direction.canvasScale ?? 1
        board.directions[directionIndex].importedLayout!.layers[index].x = min(100000, max(0, direction.importedLayout!.layers[index].x + dx / scale))
        board.directions[directionIndex].importedLayout!.layers[index].y = min(100000, max(0, direction.importedLayout!.layers[index].y + dy / scale))
        save("Move Layer")
    }
    func chooseArtwork() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = SpacesArtworkImport.supportedExtensions.sorted().compactMap { UTType(filenameExtension: $0) }
        panel.message = "Choose artwork for the current canvas, or drag an image from Finder onto any canvas."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let size = CanvasPlanCache.plan(for: direction).artboardSize
        importArtwork(url, onto: direction.id, at: CGPoint(x: size.width / 2, y: size.height / 2))
    }
    func importArtwork(_ url: URL, onto canvasID: UUID, at point: CGPoint) {
        guard let index = board.directions.firstIndex(where: { $0.id == canvasID }) else { return }
        do {
            var layer = try SpacesArtworkImport.load(url)
            let canvas = board.directions[index]
            let scale = max(0.01, canvas.canvasScale ?? 1)
            let artboard = CanvasPlanCache.plan(for: canvas).artboardSize
            let width = artboard.width / scale, height = artboard.height / scale
            let fit = min(1, width * 0.8 / layer.width, height * 0.8 / layer.height)
            layer.width *= fit; layer.height *= fit
            layer.x = min(max(0, point.x / scale - layer.width / 2), max(0, width - layer.width))
            layer.y = min(max(0, point.y / scale - layer.height / 2), max(0, height - layer.height))
            board.directions[index].artworkLayers = (canvas.artworkLayers ?? []) + [layer]
            board.selectedDirection = canvasID
            shownCanvasIDs.insert(canvasID)
            selectedSection = layer.id; selectedTextID = nil; frameCanvasID = nil; inspectorTab = "Arrangement"
            guard save("Import Artwork") else {
                artworkImportError = library.studio.error.isEmpty ? "This canvas could not save the image layer." : library.studio.error
                return
            }
            status = url.pathExtension.lowercased() == "svg"
                ? "Imported \(layer.name). SVG was rendered to an embedded image for Spaces."
                : "Imported \(layer.name) as an image layer"
        } catch {
            artworkImportError = error.localizedDescription
        }
    }
    func canvas(_ direction: TypeDirection, displayed: TypeDirection, scale: Double) -> some View {
        let zoom = scale
        let plan = CanvasPlanCache.plan(for: displayed)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Button { selectCanvas(direction.id) } label: {
                    HStack(spacing: 4) {
                        if direction.id == self.direction.id { Circle().fill(Color.accentColor).frame(width:5,height:5) }
                        Text(board.canvasName(direction)).lineLimit(1).truncationMode(.tail)
                    }.frame(maxWidth:.infinity,alignment:.leading).contentShape(Rectangle())
                }.font(.caption).buttonStyle(.plain)
                 .help(board.canvasName(direction) + (direction.id == self.direction.id ? " · Editing" : " · Click to edit"))
                 .accessibilityLabel(board.canvasName(direction) + (direction.id == self.direction.id ? ", Editing" : ", Click to edit"))
                if plan.artboardSize.width * zoom >= 280 {
                    Text("\(Int(plan.artboardSize.width)) × \(Int(plan.artboardSize.height))").font(.caption2).monospacedDigit().foregroundStyle(.secondary).fixedSize()
                }
                if plan.artboardSize.width * zoom >= 160 {
                    if direction.id != self.direction.id { Button { hideCanvas(direction.id) } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.borderless).foregroundStyle(.secondary).help("Hide " + board.canvasName(direction)).accessibilityLabel("Hide " + board.canvasName(direction)) }
                    else if visibleDirections.count > 1 { Button("Only this") { showOnlyCurrent() }.buttonStyle(.borderless).font(.caption).fixedSize().help("Hide the other canvases") }
                }
            }.frame(width: max(1,plan.artboardSize.width * zoom), height:24).clipped()
            CanvasPreview(plan: plan, zoom: zoom, directionID: direction.id == self.direction.id ? direction.id : nil, selectedSection: direction.id == self.direction.id ? selectedSection : nil, selectedTextID: direction.id == self.direction.id ? selectedTextID : nil, onSelect: { id in frameCanvasID = nil; selectedSection = id; selectedTextID = nil; inspectorTab = "Arrangement" }, onMove: moveSection, onAddRole: direction.id == self.direction.id ? addRole : nil, onTranslate: direction.id == self.direction.id && direction.canvas == .imported ? moveLayer : nil, onArtworkTranslate: direction.id == self.direction.id ? moveLayer : nil, onImportArtwork: { url, point in importArtwork(url, onto: direction.id, at: point) }, onTextSelect: { element in frameCanvasID = nil; selectText(element) }, onTextEdit: direction.id == self.direction.id ? { element, text in editText(element, text, directionID: direction.id) } : nil)
                .frame(width: plan.size.width * zoom, height: plan.size.height * zoom)
                .overlay(alignment: .topLeading) {
                    canvasFrameControls(direction, size: CGSize(width: plan.artboardSize.width * zoom, height: plan.artboardSize.height * zoom), zoom: zoom)
                }
                .shelfElevation(.canvas)
        }
    }
    private func canvasFrameControls(_ canvas: TypeDirection, size: CGSize, zoom: Double) -> some View {
        let active = CanvasBoardLayout.frameControlsAreActive(canvasID: canvas.id,
                                                               selectedDirectionID: board.selectedDirection,
                                                               frameCanvasID: frameCanvasID)
        let width = max(1, size.width), height = max(1, size.height)
        return ZStack {
            Rectangle()
                .strokeBorder(active ? Color.accentColor.opacity(0.85) : Color.primary.opacity(0.28), lineWidth: active ? 2 : 1)
                .allowsHitTesting(false)
            VStack(spacing: 0) {
                canvasMoveEdge(canvas.id, zoom: zoom).frame(height: 10)
                Spacer(minLength: 0)
                canvasMoveEdge(canvas.id, zoom: zoom).frame(height: 10)
            }
            HStack(spacing: 0) {
                canvasMoveEdge(canvas.id, zoom: zoom).frame(width: 10)
                Spacer(minLength: 0)
                canvasMoveEdge(canvas.id, zoom: zoom).frame(width: 10)
            }
            if active {
                ForEach(CanvasFrameCorner.allCases, id: \.self) { corner in
                    canvasResizeHandle(canvas.id, corner: corner, zoom: zoom)
                        .position(x: corner.left ? 0 : width, y: corner.top ? 0 : height)
                }
                ForEach(CanvasFrameEdge.allCases, id: \.self) { edge in
                    canvasResizeEdgeHandle(canvas.id, edge: edge, zoom: zoom)
                        .position(x: edge == .left ? 0 : edge == .right ? width : width / 2,
                                  y: edge == .top ? 0 : edge == .bottom ? height : height / 2)
                }
            }
        }
        .frame(width: width, height: height)
        .accessibilityLabel("Canvas frame for " + board.canvasName(canvas))
    }
    private func canvasMoveEdge(_ id: UUID, zoom: Double) -> some View {
        Rectangle().fill(Color.clear).contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { beginFrameInteraction(id, mode: .move, translation: $0.translation, zoom: zoom) }
                .onEnded { finishFrameInteraction(id, mode: .move, translation: $0.translation, zoom: zoom) })
            .help("Drag this canvas edge to arrange it")
    }
    private func canvasResizeHandle(_ id: UUID, corner: CanvasFrameCorner, zoom: Double) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(Color(nsColor: .windowBackgroundColor))
            .overlay { RoundedRectangle(cornerRadius: 2).strokeBorder(Color.accentColor, lineWidth: 1.5) }
            .frame(width: 12, height: 12)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { beginFrameInteraction(id, mode: .resizeCorner(corner), translation: $0.translation, zoom: zoom) }
                .onEnded { finishFrameInteraction(id, mode: .resizeCorner(corner), translation: $0.translation, zoom: zoom) })
            .help("Drag to resize the canvas and its contents proportionally")
            .accessibilityElement()
            .accessibilityLabel("Resize canvas from \(corner.left ? "left" : "right") \(corner.top ? "top" : "bottom") corner")
            .accessibilityHint("Drag to resize the canvas and its contents proportionally. Use increment and decrement to resize by 10 points.")
            .accessibilityAdjustableAction { direction in
                let delta = direction == .increment ? 10.0 : -10.0
                finishFrameInteraction(id, mode: .resizeCorner(corner), translation: CGSize(width: corner.left ? -delta : delta, height: corner.top ? -delta : delta), zoom: zoom)
            }
            .onHover { if $0 { NSCursor.resizeLeftRight.set() } else { NSCursor.arrow.set() } }
    }
    private func canvasResizeEdgeHandle(_ id: UUID, edge: CanvasFrameEdge, zoom: Double) -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Color(nsColor: .windowBackgroundColor))
            .overlay { RoundedRectangle(cornerRadius: 3).strokeBorder(Color.accentColor, lineWidth: 1.5) }
            .frame(width: 12, height: 12)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { beginFrameInteraction(id, mode: .resizeEdge(edge), translation: $0.translation, zoom: zoom) }
                .onEnded { finishFrameInteraction(id, mode: .resizeEdge(edge), translation: $0.translation, zoom: zoom) })
            .help(edge.horizontal ? "Drag to resize canvas width. Text stays inside the artboard." : "Drag to resize canvas height. Text stays inside the artboard.")
            .accessibilityElement()
            .accessibilityLabel("Resize canvas from \(edge.rawValue) edge")
            .accessibilityHint("Changes only the artboard dimension while keeping text inside the canvas. Use increment and decrement to resize by 10 points.")
            .accessibilityAdjustableAction { direction in
                let delta = direction == .increment ? 10.0 : -10.0
                let signed = edge.leading ? -delta : delta
                finishFrameInteraction(id, mode: .resizeEdge(edge), translation: edge.horizontal ? CGSize(width: signed, height: 0) : CGSize(width: 0, height: signed), zoom: zoom)
            }
            .onHover { if $0 { (edge.horizontal ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).set() } else { NSCursor.arrow.set() } }
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
        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text("Canvas").font(.caption).foregroundStyle(.secondary)
                    TextField("Canvas name", text: Binding(get: { board.canvasName(direction) }, set: { board.directions[directionIndex].name = $0; save() }))
                        .textFieldStyle(.roundedBorder)
                }
                Picker("Inspector", selection: $editorSession.inspectorTab) { Text("Typography").tag("Typography"); Text("Arrangement").tag("Arrangement") }.pickerStyle(.segmented).labelsHidden()
                VStack(alignment: .leading, spacing: 3) {
                    Text(editingScopeLabel).font(.caption.weight(.semibold))
                    if direction.canvas != .imported {
                        Text("Font, size and spacing change every use of this role. Text color changes canvas text; selected text content changes only that object.")
                            .font(.caption2).foregroundStyle(.secondary)
                    } else if importedLayerIndex != nil {
                        Text("Typography, color and text content change only this imported layer.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(9)
                    .background(Color.accentColor.opacity(0.09), in: RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.accentColor.opacity(contrast == .increased ? 0.8 : 0.2)))
                    .accessibilityIdentifier("spaces-editing-scope")
                if let warnings = direction.importWarnings, !warnings.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Import result · \(warnings.count) \(warnings.count == 1 ? "note" : "notes")", systemImage: "exclamationmark.triangle")
                            .font(.caption.weight(.semibold)).foregroundStyle(.orange)
                        Text(warnings[0]).font(.caption).foregroundStyle(.secondary)
                        if warnings.count > 1 {
                            DisclosureGroup("Show all import notes") {
                                Text(warnings.joined(separator: "\n")).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                            }.font(.caption)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(9)
                        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
                }
                if selectedImportedShapeIndex != nil { selectedShapeAppearance; Divider() }
                if selectedArtworkIndex != nil { selectedArtworkAppearance; Divider() }
                if inspectorTab == "Arrangement" { layoutSections }
                else {
                if direction.canvas == .imported {
                    Text("Imported text layers").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ShelfDropdown(title: "Layer", selection: Binding(get: { importedLayerIndex.flatMap { direction.importedLayout?.layers[$0].id } ?? "" }, set: { selectedSection = $0 }), options: (direction.importedLayout?.layers.filter { $0.style != nil } ?? []).map { ($0.name, $0.id) }, showsTitle: false)
                    Text("Edit each text layer independently. Drag layers on the canvas to position them.").font(.caption).foregroundStyle(.secondary)
                } else {
                HStack(spacing: 8) {
                    Text("Type role").font(.caption).foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Menu {
                        ForEach(TypeRole.allCases) { item in Button(item.rawValue) { selectRole(item) } }
                    } label: {
                        HStack(spacing: 5) { Text(role.rawValue).fontWeight(.medium); Image(systemName: "chevron.up.chevron.down").font(.caption2) }
                    }.fixedSize().accessibilityLabel("Type role: " + role.rawValue)
                }
                DisclosureGroup("Browse and add roles") {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 5) {
                ForEach(TypeRole.allCases) { item in
                    let count = StudioRoleScope.affectedTextCount(role: item, direction: direction)
                    Button { if count == 0 { addRole(item, target: nil, before: false) } else { selectRole(item) } } label: {
                        HStack { Text(item.rawValue).font(.caption).fontWeight(.medium); Spacer(); Text(count == 0 ? "Add" : "\(count)× · \(Int(direction.style(item).size))").font(.caption).monospacedDigit().foregroundStyle(.secondary) }.padding(9).background(role == item ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 7)).contentShape(Rectangle())
                    }.buttonStyle(.plain).onDrag { NSItemProvider(object: (direction.id.uuidString + "|role|" + item.rawValue) as NSString) }
                        .help(count == 0 ? "Click to add this role at the end of the canvas, or drag to place it" : "Click to locate this role; drag to add another")
                        .accessibilityLabel(count == 0 ? "Add \(item.rawValue) to canvas" : "Select \(item.rawValue), \(count) text objects")
                }
                Text("Double-click text on the canvas to edit it in place. Press ⌘Return to finish or Escape to cancel.").font(.caption).foregroundStyle(.secondary)
                }
                Text("Click Add to place a missing role at the end. Click an existing role to select it; drag a role to choose its position.").font(.caption2).foregroundStyle(.secondary)
                }
                }
                Divider()
                if importedNonTextSelected || selectedArtworkIndex != nil {
                    if selectedImportedShapeIndex == nil && selectedArtworkIndex == nil { Text("Select a text layer to edit typography.").font(.caption).foregroundStyle(.secondary) }
                } else {
                if direction.canvas == .imported { Text(editingTitle).font(.headline) }
                characterPanel
                colorPicker("Text", key: \.ink)
                DisclosureGroup("Type") {
                    VStack(alignment: .leading, spacing: 10) {
                        paragraphPanel
                        if direction.canvas != .imported {
                            Menu {
                                ForEach(TypeRole.allCases.filter { $0 != role }) { target in
                                    Button("Suggest for " + target.rawValue) {
                                        pairingTargetRole = target
                                        showPairingSuggestions = true
                                    }
                                }
                            } label: { Label("Find a font pairing…", systemImage: "sparkles") }
                                .disabled(selectedFace == nil)
                                .help("Rank compatible fonts from your local library and explain each suggestion")
                        }
                        if selectedFace?.facts.variable == true {
                            Text("Variable font axes").font(.caption).fontWeight(.semibold)
                            axesEditor
                        }
                        if let face = selectedFace {
                            let features = face.facts.features.filter { $0 != "kern" }
                            if !features.isEmpty {
                                Text("OpenType features").font(.caption).fontWeight(.semibold)
                                ForEach(features, id: \.self) { tag in
                                    ShelfDropdown(title: tag, selection: Binding(get: { style.features[tag] ?? -1 }, set: { var s = style; if $0 < 0 { s.features.removeValue(forKey: tag) } else { s.features[tag] = $0 }; setStyle(s); save() }), options: [("Default", -1), ("Off", 0), ("On", 1)] + (2...9).map { ("Alternate \($0)", $0) })
                                }
                            }
                        }
                    }.padding(.top, 8)
                }
                DisclosureGroup("Object") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(selectedTextID == nil ? "Sample text" : "Selected text").font(.caption).fontWeight(.semibold)
                        TextEditor(text: styleBinding(\.text)).frame(height: 100)
                            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.secondary.opacity(0.25)))
                        Divider()
                        Text("Proofing").font(.caption).fontWeight(.semibold)
                        let proofPlan = CanvasPlanCache.plan(for: direction)
                        let proofElement = proofPlan.elements.first { element in
                            guard element.text != nil else { return false }
                            if direction.canvas == .imported { return element.sectionID == selectedSection }
                            return selectedTextID != nil ? element.textID == selectedTextID : element.role == role
                        }
                        if let proofElement {
                            let intersectsArtwork = proofPlan.elements.contains { $0.image != nil && $0.rect.intersects(proofElement.rect) }
                            if intersectsArtwork {
                                Text("Image artwork overlaps this text frame; contrast needs visual review.").font(.caption).foregroundStyle(.secondary)
                            } else if let contrast = CanvasProofing.contrast(for: proofElement, in: proofPlan) {
                                Text(String(format: "Lowest sampled text/background contrast: %.2f:1", contrast.minimum)).font(.caption).foregroundStyle(.secondary)
                                if contrast.minimum < 4.5 { Label("Below the 4.5:1 small-text reference", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange) }
                                if contrast.overlaid { Text("Later shapes overlap this text frame; inspect the final composition.").font(.caption).foregroundStyle(.secondary) }
                            }
                            if let lines = CanvasProofing.renderedLines(for: proofElement) {
                                Text("Longest rendered line: \(lines.longestCharacters) characters across \(lines.count) \(lines.count == 1 ? "line" : "lines")").font(.caption).foregroundStyle(.secondary)
                            }
                            Text("Contrast samples the saved colors under the text frame; actual glyphs and overlapping artwork may differ.").font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text("Longest entered line: \(SpacesProofing.longestLine(style.text)) characters").font(.caption).foregroundStyle(.secondary)
                            Text("Select text on the canvas to see rendered line and background measurements.").font(.caption).foregroundStyle(.secondary)
                        }
                        Divider()
                        canvasAlignmentPanel
                    }
                    .padding(.top, 8)
                }
                }
                }
                Divider()
                if inspectorTab == "Arrangement" { DisclosureGroup("Object") { canvasAlignmentPanel.padding(.top, 8) } }
                DisclosureGroup("Canvas") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Colors").font(.caption).fontWeight(.semibold)
                        if inspectorTab == "Arrangement" && !importedNonTextSelected { colorPicker("Text", key: \.ink) }
                        colorPicker("Background", key: \.paper)
                        if direction.canvas != .imported { colorPicker("Accent", key: \.accent) }
                        Divider()
                        Text("Canvas notes").font(.caption).fontWeight(.semibold)
                        TextEditor(text: directionBinding(\.notes)).frame(height: 75)
                    }.padding(.top, 8)
                }
            }.padding(14)
        }
    }
    func optionalStyleBinding<T>(_ key: WritableKeyPath<TypeStyle, T?>, default fallback: T) -> Binding<T> { Binding(get: { style[keyPath: key] ?? fallback }, set: { var s = style; s[keyPath: key] = $0; setStyle(s); save() }) }
    var kerningBinding: Binding<Bool> { Binding(get: { style.effectiveKerning }, set: { var s = style; s.setKerning($0); setStyle(s); save() }) }
    var fontPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { Text("Choose font · " + editingTitle).font(.headline); Spacer(); Button("Done") { showFontPicker = false } }
            TextField("Search fonts, styles or #tags", text: $editorSession.fontSearch).textFieldStyle(.roundedBorder).focused($fontSearchFocused)
            HStack(spacing: 12) {
                ShelfDropdown(title: "Collection", selection: $editorSession.fontCollection, options: [("All fonts", "All fonts"), ("Favorites", "Favorites")] + library.saved.collections.keys.sorted().map { ($0, "collection:" + $0) })
                ShelfDropdown(title: "Category", selection: $editorSession.fontCategory, options: ["All categories"] .map { ($0, $0) } + Category.allCases.map { ($0.rawValue, $0.rawValue) })
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
            HStack { Text("Arrangement").font(.caption.weight(.semibold)).foregroundStyle(.secondary); Spacer(); Menu { ForEach(TypeRole.allCases) { item in Button(item.rawValue) {
                addRole(item, target: CanvasPlanCache.plan(for: direction).sections.last?.id, before: false)
            } }; if !(direction.hiddenSections ?? []).isEmpty { Button("Restore removed sections") { board.directions[directionIndex].hiddenSections = nil; save() } } } label: { Image(systemName: "plus") }.shelfIconMenu().help("Add section").accessibilityLabel("Add section") }
            let plan = CanvasPlanCache.plan(for: direction)
            GeometryReader { geometry in
                ZStack(alignment: .topTrailing) {
                    CanvasPreview(plan: CanvasPlan(arrangement: plan.sections, width: geometry.size.width), directionID: direction.id, selectedSection: selectedSection, onSelect: { selectedSection = $0; selectedTextID = nil }, onMove: moveSection)
                    VStack(spacing: 0) {
                        ForEach(plan.sections) { section in
                            Button { var hidden = direction.hiddenSections ?? []; hidden.insert(section.id); board.directions[directionIndex].hiddenSections = hidden; save("Remove Section") } label: { Image(systemName: "minus").frame(width: 28, height: 42) }.buttonStyle(.borderless).help("Remove " + section.title).accessibilityLabel("Remove " + section.title)
                        }
                    }
                }
            }.frame(height: Double(plan.sections.count) * 42)
            Text(direction.canvas == .imported ? "Drag to reorder or move layers. On a focused canvas, use arrows to select, ⌘⌥↑/↓ to reorder, or ⌥arrow to nudge." : "Drag to reorder sections. On a focused canvas, use arrows to select and ⌘⌥↑/↓ to reorder.").font(.caption2).foregroundStyle(.secondary)
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
        summaryCanvasIDs = Set(visibleDirections.map(\.id))
        showFontSummary = true
    }
    func saveCheckpoint() {
        let outcome = StudioCheckpointSave.save(direction: direction, board: board) { onSave($0, "Save Checkpoint") }
        board = outcome.board
        if outcome.saved {
            status = "Checkpoint saved · \((board.checkpoints ?? []).count) of \(StudioCheckpointSave.maximumCount) kept"
        } else {
            status = library.studio.error.isEmpty ? "Checkpoint could not be saved" : "Checkpoint could not be saved: " + library.studio.error
        }
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
                Menu("Export selected canvases") {
                    Button("Plain text · \(selectedSummaryDirections.count) selected…") { exportFontSummary(markdown: false) }
                    Button("Markdown · \(selectedSummaryDirections.count) selected…") { exportFontSummary(markdown: true) }
                    Divider()
                    Button("Type system PDF · \(selectedSummaryDirections.count) selected…") { exportTypeSystemPDF() }
                    Divider()
                    Button("Illustrator builder · \(selectedSummaryDirections.count) selected (.jsx)…") { exportAdobeTypeSystem(.illustrator) }
                    Button("InDesign builder · \(selectedSummaryDirections.count) selected (.jsx)…") { exportAdobeTypeSystem(.indesign) }
                }.fixedSize()
            }
            Text("Each selected canvas contributes its visible text styles. Type system PDF creates one specimen page per canvas; imported Figma and Adobe canvases are not supported yet. Use Preview PDF for their visual layout. Adobe builders create editable native documents when you run the saved script inside Illustrator or InDesign; fonts are referenced, never bundled.").font(.caption).foregroundStyle(.secondary)
        }.padding(18).frame(width: 540)
    }
    enum CollectionScope { case canvas, typeboard, project }
    var summaryExportScope: String {
        let selected = selectedSummaryDirections
        if selected.count == 1, let canvas = selected.first { return "Canvas “\(board.canvasName(canvas))” in typeboard “\(board.name)”" }
        return "\(selected.count) of \(board.directions.count) selected canvases in typeboard “\(board.name)”"
    }
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
        guard confirmExport(.typographySummary, directions: selectedSummaryDirections, scope: summaryExportScope) else { return }
        let panel = NSSavePanel(), suffix = markdown ? "md" : "txt"
        panel.allowedContentTypes = [UTType(filenameExtension: suffix) ?? .plainText]
        let scope = selectedSummaryDirections.count == 1 ? board.canvasName(selectedSummaryDirections[0]) : "\(selectedSummaryDirections.count) canvases"
        panel.nameFieldStringValue = board.name + " — " + scope + " typography." + suffix
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try fontSummary.text(fontSummaryDetail, markdown: markdown).write(to: url, atomically: true, encoding: .utf8); status = "Typography summary exported · \(selectedSummaryDirections.count) selected canvases" }
        catch { status = "Typography summary export failed: " + error.localizedDescription }
    }
    func exportTypeSystemPDF() {
        guard confirmExport(.typeSystemPDF, directions: selectedSummaryDirections, scope: summaryExportScope) else { return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [.pdf]; panel.nameFieldStringValue = board.name + " — type systems.pdf"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try TypeSystemPDFExporter.data(directions: selectedSummaryDirections).write(to: url, options: .atomic)
            status = "Type system PDF exported with \(selectedSummaryDirections.count) canvas \(selectedSummaryDirections.count == 1 ? "page" : "pages")"
        } catch { status = "Type system PDF export failed: " + error.localizedDescription }
    }
    func exportAdobeTypeSystem(_ target: AdobeTypeSystemTarget) {
        guard confirmExport(.adobeBuilder, directions: selectedSummaryDirections, scope: summaryExportScope) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: target.scriptExtension) ?? .plainText]
        panel.nameFieldStringValue = AdobeTypeSystemExporter.suggestedScriptFilename(title: board.name, target: target)
        let omittedArtwork = StudioTransferReport(format: .adobeBuilder, scope: summaryExportScope,
                                                   directions: selectedSummaryDirections,
                                                   availableFonts: Set(library.allFaces.map(\.name))).omittedArtworkCount
        panel.message = "Run this builder inside Adobe " + target.displayName + ". It creates a new editable ." + target.documentExtension + " document and asks where to save it." + (omittedArtwork > 0 ? " \(omittedArtwork) image layers are omitted; use Preview PDF for a visual handoff." : "")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try AdobeTypeSystemExporter.data(directions: selectedSummaryDirections, title: board.name, target: target).write(to: url, options: .atomic)
            status = "Adobe " + target.displayName + " builder exported · \(selectedSummaryDirections.count) selected canvases. Run the .jsx file inside " + target.displayName + "." + (omittedArtwork > 0 ? " \(omittedArtwork) image layers omitted." : "")
        } catch {
            status = "Adobe " + target.displayName + " export failed: " + error.localizedDescription
        }
    }
    func numeric(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 4) { HStack { Text(title); Spacer(); TextField(title, value: Binding(get: { value.wrappedValue }, set: { if $0.isFinite { value.wrappedValue = min(range.upperBound, max(range.lowerBound, $0)) } }), format: .number.precision(.fractionLength(0...2))).multilineTextAlignment(.trailing).textFieldStyle(.roundedBorder).frame(width: 65).onSubmit { NSApp.keyWindow?.makeFirstResponder(nil) }; Text(unit).foregroundStyle(.secondary) }.font(.caption); Slider(value: value, in: range) }
    }
    var selectedShapeFill: Binding<String> {
        Binding(get: { selectedImportedShape?.color ?? "000000" }, set: { hex in
            updateSelectedShape("Change Shape Fill") { $0.color = hex }
        })
    }
    var selectedShapeStroke: Binding<String> {
        Binding(get: { selectedImportedShape?.strokeColor ?? "222222" }, set: { hex in
            updateSelectedShape("Change Shape Stroke") {
                $0.strokeColor = hex
                if ($0.strokeWidth ?? 0) == 0 { $0.strokeWidth = 1 }
            }
        })
    }
    var selectedShapeStrokeWidth: Binding<Double> {
        Binding(get: { selectedImportedShape?.visibleStrokeWidth ?? 0 }, set: { value in
            guard value.isFinite else { return }
            updateSelectedShape("Change Shape Stroke Width") {
                $0.strokeWidth = min(1_000, max(0, value))
                if $0.strokeWidth! > 0 && $0.strokeColor == nil { $0.strokeColor = "222222" }
            }
        })
    }
    var selectedShapeStrokeOpacity: Binding<Double> {
        Binding(get: { (selectedImportedShape?.strokeOpacity ?? 1) * 100 }, set: { value in
            guard value.isFinite else { return }
            updateSelectedShape("Change Shape Stroke Opacity") { $0.strokeOpacity = min(1, max(0, value / 100)) }
        })
    }
    var selectedShapeOpacity: Binding<Double> {
        Binding(get: { (selectedImportedShape?.opacity ?? 1) * 100 }, set: { value in
            guard value.isFinite else { return }
            updateSelectedShape("Change Shape Opacity") { $0.opacity = min(1, max(0, value / 100)) }
        })
    }
    var selectedShapeRadiusLimit: Double {
        guard let shape = selectedImportedShape else { return 10 }
        return min(10_000, max(max(10, min(shape.width, shape.height) / 2), shape.radius))
    }
    var selectedShapeRadius: Binding<Double> {
        Binding(get: { selectedImportedShape?.radius ?? 0 }, set: { value in
            guard value.isFinite else { return }
            let limit = selectedShapeRadiusLimit
            updateSelectedShape("Change Shape Corners") { $0.radius = min(limit, max(0, value)) }
        })
    }
    var selectedShapeAppearance: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Text("Selected shape").font(.headline)
                Spacer(minLength: 4)
                Text(selectedImportedShape?.name ?? "Shape").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Text("Appearance changes apply only to this shape.").font(.caption).foregroundStyle(.secondary)
            StudioHexColorPicker(title: "Fill", hex: selectedShapeFill)
            StudioHexColorPicker(title: "Stroke", hex: selectedShapeStroke)
            HStack(spacing: 7) {
                Text("Stroke width")
                Spacer(minLength: 4)
                TextField("Stroke width", value: selectedShapeStrokeWidth, format: .number.precision(.fractionLength(0...2)))
                    .multilineTextAlignment(.trailing).textFieldStyle(.roundedBorder).frame(width: 70)
                Text(direction.canvasUnitLabel).foregroundStyle(.secondary)
            }.font(.caption)
            if (selectedImportedShape?.visibleStrokeWidth ?? 0) > 0 {
                HStack(spacing: 7) {
                    Text("Stroke opacity")
                    Slider(value: selectedShapeStrokeOpacity, in: 0...100) { Text("Stroke opacity") }.labelsHidden()
                    TextField("Stroke opacity", value: selectedShapeStrokeOpacity, format: .number.precision(.fractionLength(0...1)))
                        .multilineTextAlignment(.trailing).textFieldStyle(.roundedBorder).frame(width: 52)
                    Text("%").foregroundStyle(.secondary)
                }.font(.caption)
            }
            HStack(spacing: 7) {
                Text("Fill opacity")
                Slider(value: selectedShapeOpacity, in: 0...100) { Text("Fill opacity") }.labelsHidden()
                TextField("Fill opacity", value: selectedShapeOpacity, format: .number.precision(.fractionLength(0...1)))
                    .multilineTextAlignment(.trailing).textFieldStyle(.roundedBorder).frame(width: 52)
                Text("%").foregroundStyle(.secondary)
            }.font(.caption)
            HStack(spacing: 7) {
                Text("Corners")
                Slider(value: selectedShapeRadius, in: 0...selectedShapeRadiusLimit) { Text("Corner radius") }.labelsHidden()
                TextField("Corner radius", value: selectedShapeRadius, format: .number.precision(.fractionLength(0...1)))
                    .multilineTextAlignment(.trailing).textFieldStyle(.roundedBorder).frame(width: 52)
            }.font(.caption)
        }
    }
    var selectedArtworkAppearance: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("Selected artwork").font(.headline)
                Spacer(minLength: 4)
                Text(selectedArtwork?.name ?? "Image").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Text("Drag the image on the canvas to position it. Its source is embedded in this project.")
                .font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 7) {
                Text("Width")
                Spacer(minLength: 4)
                TextField("Width", value: Binding(get: { selectedArtwork?.width ?? 1 }, set: { value in
                    guard value.isFinite, value > 0 else { return }
                    updateSelectedArtwork("Resize Artwork") { layer in
                        let next = min(10_000, max(1, value))
                        layer.height = min(10_000, max(1, layer.height * next / max(1, layer.width)))
                        layer.width = next
                    }
                }), format: .number.precision(.fractionLength(0...1)))
                    .multilineTextAlignment(.trailing).textFieldStyle(.roundedBorder).frame(width: 80)
                Text(direction.canvasUnitLabel).foregroundStyle(.secondary)
            }.font(.caption)
            HStack(spacing: 7) {
                Text("Opacity")
                Slider(value: Binding(get: { (selectedArtwork?.opacity ?? 1) * 100 }, set: { value in
                    updateSelectedArtwork("Change Artwork Opacity") { $0.opacity = min(1, max(0, value / 100)) }
                }), in: 0...100) { Text("Artwork opacity") }.labelsHidden()
                Text("\(Int((selectedArtwork?.opacity ?? 1) * 100))%").monospacedDigit().foregroundStyle(.secondary)
            }.font(.caption)
            Toggle("Place above canvas content", isOn: Binding(get: { selectedArtwork?.artworkInFront ?? false }, set: { value in
                updateSelectedArtwork("Arrange Artwork") { $0.artworkInFront = value }
            })).toggleStyle(.checkbox).font(.caption)
            Button("Remove artwork", role: .destructive) {
                guard let index = selectedArtworkIndex else { return }
                board.directions[directionIndex].artworkLayers?.remove(at: index)
                selectedSection = nil
                save("Remove Artwork")
            }.font(.caption)
        }
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
        StudioHexColorPicker(title: title, hex: Binding(
            get: { key == \TypeDirection.ink ? importedLayerIndex.flatMap { direction.importedLayout?.layers[$0].color } ?? direction.ink : direction[keyPath: key] },
            set: { hex in
                if key == \TypeDirection.ink && importedNonTextSelected { return }
                if key == \TypeDirection.ink, let index = importedLayerIndex {
                    board.directions[directionIndex].importedLayout?.layers[index].color = hex
                } else {
                    board.directions[directionIndex][keyPath: key] = hex
                }
                save("Change " + title + " Color")
            }
        ))
    }
    func exportDeveloperHandoff() {
        guard confirmExport(.developerHandoff, directions: board.directions,
                            scope: "Typeboard “\(board.name)” · all \(board.directions.count) canvases") else { return }
        do {
            if let folder = try DeveloperHandoff.selectFolder(title: board.name, boards: [board], catalog: library.families) {
                status = "Developer handoff exported · all \(board.directions.count) canvases. Open index.html for the specimen."
                NSWorkspace.shared.activateFileViewerSelecting([folder])
            }
        } catch { status = "Handoff export failed: " + error.localizedDescription }
    }
    func exportPDF() {
        guard confirmExport(.previewPDF, directions: [direction],
                            scope: "Canvas “\(board.canvasName(direction))” in typeboard “\(board.name)”") else { return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [.pdf]; panel.nameFieldStringValue = board.name + " — " + direction.name + ".pdf"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { let plan = CanvasPlanCache.plan(for: direction); let view = CanvasNativeView(plan: plan); try view.dataWithPDF(inside: view.bounds).write(to: url, options: .atomic); status = "Preview PDF exported · “\(board.canvasName(direction))”" } catch { status = "Export failed: " + error.localizedDescription }
    }
    func exportFigma() {
        guard confirmExport(.figma, directions: board.directions,
                            scope: "Typeboard “\(board.name)” · all \(board.directions.count) canvases") else { return }
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
        let omittedArtwork = StudioTransferReport(format: .figma, scope: board.name, directions: board.directions,
                                                   availableFonts: Set(library.allFaces.map(\.name))).omittedArtworkCount
        panel.message = "Choose where to save the editable Figma layout and local importer. No fonts are bundled." + (omittedArtwork > 0 ? " \(omittedArtwork) image layers are omitted; use Preview PDF for a visual handoff." : "")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { let folder = try FigmaLayoutExporter.write(board: board, parent: url); status = "Figma package exported · all \(board.directions.count) canvases. See README for import steps." + (omittedArtwork > 0 ? " \(omittedArtwork) image layers omitted." : ""); NSWorkspace.shared.activateFileViewerSelecting([folder]) } catch { status = "Figma export failed: " + error.localizedDescription }
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
                        split.setPosition(min(500, max(StudioInspectorLayout.fullMinimumWidth, saved == 0 ? StudioInspectorLayout.fullIdealWidth : saved)), ofDividerAt: 0)
                        self.observation = NotificationCenter.default.addObserver(forName: NSSplitView.didResizeSubviewsNotification, object: split, queue: .main) { [weak split] _ in
                            if let width = split?.subviews.first?.frame.width, width >= StudioInspectorLayout.fullMinimumWidth { UserDefaults.standard.set(min(500, width), forKey: "studioInspectorWidth") }
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
    var image: NSImage?
    var imageOpacity: Double = 1
    var artworkInFront = false
    var radius: Double = 0
    var strokeColor: NSColor?
    var strokeWidth: Double = 0
    var sectionID = ""
    var style: TypeStyle?
    var role: TypeRole?
    var textID: String?
    var textKind: CanvasTextKind = .text
}
struct CanvasSection: Identifiable { var id: String; var title: String; var rect: CGRect }
enum CanvasPlanCache {
    private struct Entry { let direction: TypeDirection; let plan: CanvasPlan; let textLength: Int; var used: UInt64 }
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
        if plan.elements.count <= 1_000 && textLength <= 1_000_000 { entries[direction.id] = Entry(direction: direction, plan: plan, textLength:textLength, used: used) }
        while entries.count > 16 || entries.values.reduce(0, { $0+$1.textLength }) > 2_000_000 {
            guard let oldest = entries.min(by: { $0.value.used < $1.value.used })?.key else { break }
            entries.removeValue(forKey: oldest)
        }
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
    static func editorialSample(_ text: String, repetitions: Int) -> String {
        // Repeat short sample copy to fill a template, but never multiply a
        // user's long article. Keep the original text intact in every column.
        let count = max(1, min(repetitions, 2_000 / max(1, text.utf16.count + 2)))
        return Array(repeating: text, count: count).joined(separator: "\n\n")
    }
    var elements: [CanvasElement] = []
    var sections: [CanvasSection] = []
    var size: CGSize = .zero
    var artboardSize: CGSize = .zero
    var paper: NSColor
    var ink: NSColor
    var accessibilityText = "Typography canvas"
    var contentScale = 1.0
    mutating func updateAccessibilityText() {
        var result = ""
        for value in elements.compactMap({ $0.text?.string }) where result.count < 4_000 {
            result += (result.isEmpty ? "" : ". ") + String(value.prefix(4_000 - result.count))
        }
        if !result.isEmpty { accessibilityText = result }
    }
    init(arrangement: [CanvasSection], width: Double) {
        paper = .clear; ink = .labelColor; size = CGSize(width: width, height: Double(arrangement.count) * 42)
        artboardSize = size
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
            artboardSize = size
            for layer in d.importedLayout?.layers ?? [] where !(d.hiddenSections ?? []).contains(layer.id) {
                let color = NSColor(hex: layer.color).withAlphaComponent(layer.opacity)
                var rect = layer.rect
                if let data = layer.artworkData, let image = NSImage(data: data) {
                    elements.append(CanvasElement(rect: rect, image: image, imageOpacity: layer.opacity, artworkInFront: layer.artworkInFront ?? false, sectionID: layer.id))
                } else if let style = layer.style {
                    let text = style.attributed(color: color)
                    rect.size.height = max(rect.height, ceil(text.boundingRect(with: CGSize(width: max(1, rect.width), height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading]).height) + 4)
                    elements.append(CanvasElement(rect: rect, text: text, sectionID: layer.id, style: style))
                } else {
                    let stroke = layer.strokeColor.map { NSColor(hex: $0).withAlphaComponent(layer.strokeOpacity ?? 1) }
                    elements.append(CanvasElement(rect: rect, color: color, radius: layer.radius,
                                                  strokeColor: stroke, strokeWidth: layer.visibleStrokeWidth, sectionID: layer.id))
                }
                sections.append(CanvasSection(id: layer.id, title: layer.name, rect: rect))
                size.width = max(size.width, rect.maxX)
                size.height = max(size.height, rect.maxY)
            }
            appendArtworkLayers(d.artworkLayers ?? [], hidden: d.hiddenSections ?? [])
            artboardSize = size
            applyCanvasScale(d.canvasScale ?? 1)
            expandTextFramesForUnbreakableContent()
            applyArtboardBounds(width: d.width, importedWidth: d.canvasWidth, height: d.canvasHeight,
                                preserveImportedOverflow: d.canvasWidth == nil && d.canvasHeight == nil)
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
            let logoH = text(.label, "Studio 01", x: margin, at: navY, width: usable * 0.35)
            let navH = text(.caption, "Work · About · Journal · Contact", x: margin + usable * 0.48, at: navY, width: usable * 0.52)
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
            for (i, value) in ["Est. 2018", "Independent", "Worldwide"].enumerated() { _ = text(.caption, value, x: margin + Double(i) * proofWidth, at: proofY, width: proofWidth) }
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
            y = bottom; rule(); section("footer", "Website footer"); _ = text(.heading, "Stay curious."); _ = text(.caption, "Newsletter · Instagram · Terms · © 2026")
        case .product:
            section("app-bar", "Application chrome")
            let barY = y
            elements.append(CanvasElement(rect: CGRect(x: margin, y: barY, width: usable, height: 62), color: ink.withAlphaComponent(0.055), radius: 10))
            _ = text(.label, "Acme Workspace", x: margin + 18, at: barY + 19, width: usable * 0.35)
            _ = text(.caption, "⌘ K  Search   Arian ▾", x: margin + usable * 0.58, at: barY + 20, width: usable * 0.38)
            y = barY + 86
            section("dashboard", "Dashboard header")
            _ = text(.caption, "Overview · This week"); _ = text(.heading, "Good morning, Arian"); _ = text(.body, "Track active projects, decisions, and the work that needs your attention.")
            section("metrics", "Metric cards")
            let columns = w >= 700 ? 3 : 1, gap = 14.0, cw = (usable - Double(columns - 1) * gap) / Double(columns)
            for start in stride(from: 0, to: 3, by: columns) {
                let rowY = y; var bottom = y
                for i in start..<min(start + columns, 3) {
                    let x = margin + Double(i - start) * (cw + gap), insertion = elements.count
                    let captionH = text(.caption, ["Active projects", "Awaiting review", "On-time rate"][i], x: x + 18, at: rowY + 16, width: cw - 36)
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
            _ = text(.caption, "Project", x: margin + 16, at: tableY + 13, width: usable * 0.44)
            _ = text(.caption, "Status", x: margin + usable * 0.58, at: tableY + 13, width: usable * 0.2)
            y = tableY + 42
            for (i, item) in ["Website exploration", "Mobile interface", "Brand guidelines", "Product launch"].enumerated() {
                let row = y
                _ = text(.label, item, x: margin + 16, at: row + 16, width: usable * 0.48)
                _ = text(.caption, i == 1 ? "Needs review" : "In progress", x: margin + usable * 0.58, at: row + 17, width: usable * 0.28)
                y = row + 56; elements.append(CanvasElement(rect: CGRect(x: margin, y: y - 1, width: usable, height: 1), color: ink.withAlphaComponent(0.1)))
            }
            y += 22; section("command", "Command input")
            let commandY = y; elements.append(CanvasElement(rect: CGRect(x: margin, y: commandY, width: usable, height: 58), color: accent.withAlphaComponent(0.13), radius: 9)); _ = text(.mono, "Ask your workspace…                         ⌘ ↵", x: margin + 18, at: commandY + 17, width: usable - 36); y = commandY + 82
        case .editorial:
            section("masthead", "Magazine masthead")
            let mastY = y; _ = text(.caption, "Vol. 12 · Culture & design", x: margin, at: mastY, width: usable * 0.5); _ = text(.label, "The Field Notes", x: margin + usable * 0.62, at: mastY, width: usable * 0.38); y = mastY + 38; rule()
            section("cover-story", "Cover story")
            _ = text(.display, "The quiet ideas reshaping everyday life"); _ = text(.subheading, "A conversation about objects, attention, and what it means to make things that last.")
            let bylineY = y; _ = text(.caption, "Words · Maya Chen", x: margin, at: bylineY, width: usable * 0.45); _ = text(.caption, "Photography · Luis Ortega", x: margin + usable * 0.52, at: bylineY, width: usable * 0.48); y = bylineY + 42
            section("image", "Lead image")
            let imageHeight = w >= 700 ? usable * 0.52 : 240
            elements.append(CanvasElement(rect: CGRect(x: margin, y: y, width: usable, height: imageHeight), color: accent.withAlphaComponent(0.22), radius: 2))
            elements.append(CanvasElement(rect: CGRect(x: margin + usable * 0.64, y: y + imageHeight * 0.13, width: usable * 0.22, height: imageHeight * 0.7), color: ink.withAlphaComponent(0.12), radius: 2)); y += imageHeight + 18
            _ = text(.caption, "Fig. 01 — Morning light in the workshop."); y += 18
            section("article", "Article and pull quote")
            if w >= 700 {
                let articleY = y, columnGap = 28.0, bodyWidth = usable * 0.29
                let first = text(.body, Self.editorialSample(d.style(.body).text, repetitions: 4), x: margin, at: articleY, width: bodyWidth)
                let quote = text(.heading, "“The useful things are often the most poetic.”", x: margin + bodyWidth + columnGap, at: articleY + 28, width: usable * 0.34)
                let second = text(.body, Self.editorialSample(d.style(.body).text, repetitions: 4), x: margin + usable - bodyWidth, at: articleY, width: bodyWidth)
                y = articleY + max(first, quote + 28, second) + 36
            } else { _ = text(.heading, "“The useful things are often the most poetic.”"); _ = text(.body, Self.editorialSample(d.style(.body).text, repetitions: 5)) }
            rule(); section("folio", "Editorial folio"); let folioY = y; _ = text(.caption, "The Field Notes", x: margin, at: folioY, width: usable * 0.5); _ = text(.mono, "024", x: margin + usable * 0.8, at: folioY, width: usable * 0.2); y = folioY + 38
        case .poster:
            section("poster-code", "Poster index")
            let indexY = y; _ = text(.mono, "Poster 07", x: margin, at: indexY, width: usable * 0.4); _ = text(.caption, "Design · Music · Conversation", x: margin + usable * 0.48, at: indexY, width: usable * 0.52); y = indexY + 60
            section("poster-field", "Graphic field")
            let fieldY = y, fieldHeight = max(300, usable * 0.62)
            elements.append(CanvasElement(rect: CGRect(x: margin, y: fieldY, width: usable, height: fieldHeight), color: accent, radius: 0))
            elements.append(CanvasElement(rect: CGRect(x: margin + usable * 0.54, y: fieldY + fieldHeight * 0.08, width: usable * 0.34, height: usable * 0.34), color: paper.withAlphaComponent(0.9), radius: usable * 0.17))
            _ = text(.display, "Form / Sound", x: margin + 28, at: fieldY + 30, width: usable * 0.62, color: paper)
            _ = text(.mono, "08—10\nOct 2026", x: margin + 30, at: fieldY + fieldHeight * 0.68, width: usable * 0.34, color: paper)
            _ = text(.label, "Hall 04 / Los Angeles", x: margin + usable * 0.54, at: fieldY + fieldHeight * 0.78, width: usable * 0.38, color: paper)
            y = fieldY + fieldHeight + 42
            section("poster-details", "Event details")
            let detailY = y; _ = text(.heading, "Three nights of new work.", x: margin, at: detailY, width: usable * 0.55); _ = text(.body, "Exhibitions, live performance, workshops, and conversations with independent makers.", x: margin + usable * 0.62, at: detailY, width: usable * 0.38); y = detailY + 150
            rule(); section("poster-footer", "Poster footer"); let footerY = y; _ = text(.caption, "Tickets · Program · Access", x: margin, at: footerY, width: usable * 0.58); _ = text(.mono, "F/S 2026", x: margin + usable * 0.72, at: footerY, width: usable * 0.28); y = footerY + 44
        case .specimen:
            for role in TypeRole.allCases { section(role.rawValue, role.rawValue); _ = text(.caption, role.rawValue + " · " + d.style(role).fontName + " · \(Int(d.style(role).size)) px"); _ = text(role); rule() }
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
        artboardSize = size
        for i in elements.indices {
            if let id = elements[i].textID, let position = d.textPositions?[id], position.isValid {
                let fittedWidth = min(elements[i].rect.width, max(1, d.width))
                let fittedX = min(max(0, position.x), max(0, d.width - fittedWidth))
                let fittedY = min(max(0, position.y), max(0, 10_000 / max(0.01, d.canvasScale ?? 1) - elements[i].rect.height))
                elements[i].rect.origin = CGPoint(x: fittedX, y: fittedY)
                elements[i].rect.size.width = fittedWidth
            }
        }
        appendArtworkLayers(d.artworkLayers ?? [], hidden: d.hiddenSections ?? [])
        applyCanvasScale(d.canvasScale ?? 1)
        expandTextFramesForUnbreakableContent()
        applyArtboardBounds(width: d.width, importedWidth: d.canvasWidth, height: d.canvasHeight,
                            preserveImportedOverflow: d.canvas == .imported && d.canvasWidth == nil && d.canvasHeight == nil)
        updateAccessibilityText()
    }
    private mutating func appendArtworkLayers(_ layers: [ImportedLayer], hidden: Set<String>) {
        var behind: [CanvasElement] = []
        for layer in layers where !hidden.contains(layer.id) {
            guard let data = layer.artworkData, let image = NSImage(data: data) else { continue }
            let rect = layer.rect
            let element = CanvasElement(rect: rect, image: image, imageOpacity: layer.opacity,
                                        artworkInFront: layer.artworkInFront ?? false, sectionID: layer.id)
            if element.artworkInFront { elements.append(element) } else { behind.append(element) }
            sections.append(CanvasSection(id: layer.id, title: layer.name, rect: rect))
            size.width = max(size.width, rect.maxX)
            size.height = max(size.height, rect.maxY)
        }
        elements.insert(contentsOf: behind, at: 0)
    }
    private mutating func applyCanvasScale(_ factor: Double) {
        guard factor != 1 else { return }
        contentScale = factor
        func scaled(_ rect: CGRect) -> CGRect {
            CGRect(x: rect.minX * factor, y: rect.minY * factor, width: rect.width * factor, height: rect.height * factor)
        }
        size = CGSize(width: size.width * factor, height: size.height * factor)
        artboardSize = CGSize(width: artboardSize.width * factor, height: artboardSize.height * factor)
        for index in sections.indices { sections[index].rect = scaled(sections[index].rect) }
        for index in elements.indices {
            elements[index].rect = scaled(elements[index].rect)
            elements[index].radius *= factor
            elements[index].strokeWidth *= factor
            if let style = elements[index].style { elements[index].style = style.scaledForCanvas(factor) }
            if let text = elements[index].text {
                let scaledText = NSMutableAttributedString(attributedString: text)
                text.enumerateAttributes(in: NSRange(location: 0, length: text.length), options: []) { attributes, range, _ in
                    if let font = attributes[.font] as? NSFont {
                        scaledText.addAttribute(.font, value: NSFont(descriptor: font.fontDescriptor, size: font.pointSize * factor) ?? font, range: range)
                    }
                    if let kern = attributes[.kern] as? NSNumber { scaledText.addAttribute(.kern, value: kern.doubleValue * factor, range: range) }
                    if let paragraph = attributes[.paragraphStyle] as? NSParagraphStyle, let copy = paragraph.mutableCopy() as? NSMutableParagraphStyle {
                        copy.minimumLineHeight *= factor
                        copy.maximumLineHeight *= factor
                        copy.paragraphSpacing *= factor
                        copy.firstLineHeadIndent *= factor
                        scaledText.addAttribute(.paragraphStyle, value: copy, range: range)
                    }
                }
                elements[index].text = scaledText
            }
        }
    }
    private mutating func expandTextFramesForUnbreakableContent() {
        for index in elements.indices where elements[index].text != nil {
            let minimumWidth = CanvasBoardLayout.minimumTextFrameWidth(for: elements[index])
            if minimumWidth > Double(elements[index].rect.width) {
                elements[index].rect.size.width = minimumWidth
            }
        }
    }
    private mutating func applyArtboardBounds(width: Double, importedWidth: Double?, height: Double?, preserveImportedOverflow: Bool) {
        let scale = contentScale
        let requestedWidth = importedWidth.map { $0 * scale } ?? (preserveImportedOverflow ? artboardSize.width : width * scale)
        let requestedHeight = (height.map { max(1, $0) } ?? artboardSize.height / max(0.01, scale)) * scale
        let textBounds = CanvasBoardLayout.textContentBounds(in: self)
        let finalWidth = max(requestedWidth, Double(textBounds.width))
        let finalHeight = max(requestedHeight, Double(textBounds.height))
        let boundedWidth = preserveImportedOverflow ? finalWidth : min(10_000, finalWidth)
        let boundedHeight = preserveImportedOverflow ? finalHeight : min(10_000, finalHeight)
        artboardSize = CGSize(width: boundedWidth, height: boundedHeight)
        size = artboardSize
    }
}

enum CanvasProofing {
    struct RenderedLines { let count: Int; let longestCharacters: Int }
    struct Contrast { let minimum: Double; let overlaid: Bool }

    static func renderedLines(for element: CanvasElement) -> RenderedLines? {
        guard let text = element.text else { return nil }
        guard text.length > 0 else { return RenderedLines(count: 1, longestCharacters: 0) }
        let storage = NSTextStorage(attributedString: text)
        let manager = NSLayoutManager(); manager.usesFontLeading = true
        let container = NSTextContainer(containerSize: CGSize(width: max(1, element.rect.width), height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        manager.addTextContainer(container); storage.addLayoutManager(manager)
        manager.ensureLayout(for: container)
        var count = 0, longest = 0
        manager.enumerateLineFragments(forGlyphRange: manager.glyphRange(for: container)) { _, _, _, glyphRange, _ in
            let range = manager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
            let line = (text.string as NSString).substring(with: range).trimmingCharacters(in: .newlines)
            longest = max(longest, line.count)
            count += 1
        }
        return RenderedLines(count: max(1, count), longestCharacters: longest)
    }

    private struct RGB {
        var red: Double; var green: Double; var blue: Double; var alpha: Double
        init?(_ color: NSColor) {
            guard let value = color.usingColorSpace(.sRGB) else { return nil }
            red = value.redComponent; green = value.greenComponent; blue = value.blueComponent; alpha = value.alphaComponent
        }
        static let white = RGB(red: 1, green: 1, blue: 1, alpha: 1)
        private init(red: Double, green: Double, blue: Double, alpha: Double) {
            self.red = red; self.green = green; self.blue = blue; self.alpha = alpha
        }
        func over(_ below: RGB) -> RGB {
            let coverage = alpha + below.alpha * (1 - alpha)
            guard coverage > 0 else { return .white }
            return RGB(red: (red * alpha + below.red * below.alpha * (1 - alpha)) / coverage,
                       green: (green * alpha + below.green * below.alpha * (1 - alpha)) / coverage,
                       blue: (blue * alpha + below.blue * below.alpha * (1 - alpha)) / coverage,
                       alpha: coverage)
        }
        var luminance: Double {
            func linear(_ component: Double) -> Double { component <= 0.04045 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4) }
            return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
        }
    }

    static func contrast(for element: CanvasElement, in plan: CanvasPlan) -> Contrast? {
        guard let text = element.text, text.length > 0,
              let inkColor = text.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor,
              let ink = RGB(inkColor), let paper = RGB(plan.paper),
              let index = plan.elements.firstIndex(where: { $0.sectionID == element.sectionID && $0.textID == element.textID && $0.rect == element.rect && $0.text?.string == text.string }) else { return nil }
        let frame = plan.textBounds(for: element)
        guard !frame.isNull, frame.width > 0, frame.height > 0 else { return nil }
        var minimum = Double.infinity
        for row in 0..<3 {
            for column in 0..<5 {
                let point = CGPoint(x: frame.minX + frame.width * (Double(column) + 0.5) / 5,
                                    y: frame.minY + frame.height * (Double(row) + 0.5) / 3)
                var background = paper.over(.white)
                for item in plan.elements[..<index] where item.rect.contains(point) {
                    if let color = item.color, let fill = RGB(color) { background = fill.over(background) }
                }
                let foreground = ink.over(background)
                let high = max(foreground.luminance, background.luminance)
                let low = min(foreground.luminance, background.luminance)
                minimum = min(minimum, (high + 0.05) / (low + 0.05))
            }
        }
        let overlaid = plan.elements.dropFirst(index + 1).contains { ($0.color != nil || $0.image != nil) && $0.rect.intersects(frame) }
        return Contrast(minimum: minimum, overlaid: overlaid)
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
private enum CanvasAccessibleTarget: Hashable {
    case section(String)
    case text(String)
    case layer(String)
}
private final class CanvasAccessibilityItem: NSAccessibilityElement {
    var onPress: (() -> Bool)?
    var actionCapabilities = -1
    override func accessibilityPerformPress() -> Bool { onPress?() ?? false }
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
    var onArtworkTranslate: ((String, Double, Double) -> Void)?
    var onImportArtwork: ((URL, CGPoint) -> Void)?
    var onTextSelect: ((CanvasElement) -> Void)?
    var onTextEdit: ((CanvasElement, String) -> Void)?
    private var insertionY: Double?
    private var artworkDropHover = false
    private var translation = NSPoint.zero
    private weak var inlineEditor: CanvasInlineTextView?
    private var editingElement: CanvasElement?
    private var activeTextEdit: ((CanvasElement, String) -> Void)?
    private var accessibleItems: [CanvasAccessibleTarget: CanvasAccessibilityItem] = [:]
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { directionID != nil }
    override func becomeFirstResponder() -> Bool { let accepted = super.becomeFirstResponder(); if accepted { needsDisplay = true }; return accepted }
    override func resignFirstResponder() -> Bool { let accepted = super.resignFirstResponder(); if accepted { needsDisplay = true }; return accepted }
    init(plan: CanvasPlan) { self.plan = plan; super.init(frame: CGRect(origin: .zero, size: plan.size)); registerForDraggedTypes([.string, .fileURL]) }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    override func resetCursorRects() { if directionID != nil { addCursorRect(bounds, cursor: .openHand) } }
    private var navigationTargets: [CanvasAccessibleTarget] {
        if plan.sections.isEmpty { return [] }
        if plan.elements.contains(where: { $0.textID != nil }) {
            let texts = Dictionary(grouping: plan.elements.compactMap { element -> (String, String)? in
                element.textID.map { (element.sectionID, $0) }
            }, by: { $0.0 })
            return plan.sections.flatMap { section -> [CanvasAccessibleTarget] in
                let base: CanvasAccessibleTarget = plan.elements.contains { $0.sectionID == section.id && $0.image != nil } ? .layer(section.id) : .section(section.id)
                return [base] + (texts[section.id] ?? []).map { .text($0.1) }
            }
        }
        if plan.elements.count == plan.sections.count && plan.elements.contains(where: { $0.style != nil || $0.color != nil || $0.image != nil }) {
            return plan.sections.map { .layer($0.id) }
        }
        return plan.sections.map { .section($0.id) }
    }
    private var currentTarget: CanvasAccessibleTarget? {
        guard let selectedSection else { return nil }
        if let selectedTextID { return .text(selectedTextID) }
        return navigationTargets.contains(.layer(selectedSection)) ? .layer(selectedSection) : .section(selectedSection)
    }
    private func element(for target: CanvasAccessibleTarget) -> CanvasElement? {
        switch target {
        case .text(let id): return plan.elements.first { $0.textID == id }
        case .layer(let id): return plan.elements.first { $0.sectionID == id }
        case .section: return nil
        }
    }
    @discardableResult private func activate(_ target: CanvasAccessibleTarget) -> Bool {
        guard directionID != nil else { return false }
        switch target {
        case .section(let id):
            guard plan.sections.contains(where: { $0.id == id }) else { return false }
            selectedSection = id; selectedTextID = nil; onSelect?(id)
        case .text(let id):
            guard let text = plan.elements.first(where: { $0.textID == id }) else { return false }
            selectedSection = text.sectionID; selectedTextID = id; onTextSelect?(text)
        case .layer(let id):
            guard let layer = plan.elements.first(where: { $0.sectionID == id }) else { return false }
            selectedSection = id; selectedTextID = nil
            if layer.text != nil { onTextSelect?(layer) } else { onSelect?(id) }
        }
        window?.makeFirstResponder(self)
        needsDisplay = true
        updateAccessibilityItems()
        return true
    }
    @discardableResult private func edit(_ target: CanvasAccessibleTarget) -> Bool {
        guard onTextEdit != nil, let text = element(for: target), text.text != nil, activate(target) else { return false }
        beginEditing(text)
        return true
    }
    @discardableResult private func reorder(_ target: CanvasAccessibleTarget, offset: Int) -> Bool {
        guard directionID != nil, onMove != nil else { return false }
        let id: String
        switch target { case .section(let value), .layer(let value): id = value
        case .text(let value): guard let element = element(for: .text(value)) else { return false }; id = element.sectionID }
        guard let index = plan.sections.firstIndex(where: { $0.id == id }), plan.sections.indices.contains(index + offset) else { return false }
        onMove?(id, plan.sections[index + offset].id, offset < 0)
        return true
    }
    @discardableResult private func nudge(_ target: CanvasAccessibleTarget, dx: Double, dy: Double) -> Bool {
        guard directionID != nil else { return false }
        let id: String
        switch target { case .layer(let value), .section(let value): id = value
        case .text(let value): guard let element = element(for: .text(value)) else { return false }; id = element.sectionID }
        guard plan.sections.contains(where: { $0.id == id }) else { return false }
        if plan.elements.contains(where: { $0.sectionID == id && $0.image != nil }) {
            guard let onArtworkTranslate else { return false }
            onArtworkTranslate(id, dx, dy)
        } else {
            guard let onTranslate else { return false }
            onTranslate(id, dx, dy)
        }
        return true
    }
    private func selectAdjacent(_ offset: Int) -> Bool {
        let targets = navigationTargets
        guard !targets.isEmpty else { return false }
        let index = currentTarget.flatMap { targets.firstIndex(of: $0) }
        let next = index.map { min(max(0, $0 + offset), targets.count - 1) } ?? (offset > 0 ? 0 : targets.count - 1)
        return activate(targets[next])
    }
    override func keyDown(with event: NSEvent) {
        guard directionID != nil else { super.keyDown(with: event); return }
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask).intersection([.command, .option, .shift, .control])
        let offset: Int? = event.keyCode == 126 || event.keyCode == 123 ? -1 : event.keyCode == 125 || event.keyCode == 124 ? 1 : nil
        if let offset, modifiers == [.command, .option], let currentTarget, reorder(currentTarget, offset: offset) { return }
        if modifiers == [.option] || modifiers == [.option, .shift] {
            let step = modifiers.contains(.shift) ? 10.0 : 1.0
            let dx = event.keyCode == 123 ? -step : event.keyCode == 124 ? step : 0
            let dy = event.keyCode == 126 ? -step : event.keyCode == 125 ? step : 0
            if (dx != 0 || dy != 0), let currentTarget, nudge(currentTarget, dx: dx, dy: dy) { return }
        }
        if let offset, modifiers.isEmpty, selectAdjacent(offset) { return }
        if (event.keyCode == 36 || event.keyCode == 76), modifiers.isEmpty, let currentTarget, edit(currentTarget) { return }
        super.keyDown(with: event)
    }
    func updateAccessibilityItems() {
        let targets = navigationTargets
        let active = directionID != nil
        let selected = currentTarget
        let sections = Dictionary(uniqueKeysWithValues: plan.sections.enumerated().map { ($0.element.id, ($0.offset, $0.element)) })
        let texts = Dictionary(uniqueKeysWithValues: plan.elements.compactMap { element -> (String, CanvasElement)? in element.textID.map { ($0, element) } })
        var layers: [String: CanvasElement] = [:]
        if targets.contains(where: { if case .layer = $0 { return true }; return false }) {
            for element in plan.elements { layers[element.sectionID] = element }
        }
        var ordered: [CanvasAccessibilityItem] = []
        for target in targets {
            let item = accessibleItems[target] ?? CanvasAccessibilityItem()
            item.setAccessibilityParent(self)
            item.setAccessibilityRole(active ? .button : .staticText)
            item.setAccessibilityEnabled(true)
            item.setAccessibilitySelected(active && selected == target)
            let frame: CGRect
            let label: String
            var editable = false
            switch target {
            case .section(let id):
                guard let (index, section) = sections[id] else { continue }
                frame = section.rect
                label = "Section \(index + 1) of \(plan.sections.count): \(section.title)"
                item.setAccessibilityIdentifier("spaces-section-" + id)
            case .text(let id):
                guard let element = texts[id] else { continue }
                frame = element.rect
                let content = element.text?.string.replacingOccurrences(of: "\n", with: " ") ?? ""
                label = "\(element.role?.rawValue ?? "Text") text at x \(Int(frame.minX)), y \(Int(frame.minY)): \(String(content.prefix(160)))"
                item.setAccessibilityValue(element.text.map { String($0.string.prefix(4_000)) })
                item.setAccessibilityIdentifier("spaces-text-" + id)
                editable = element.text != nil
            case .layer(let id):
                guard let (index, section) = sections[id], let element = layers[id] else { continue }
                frame = section.rect
                label = "\(element.text == nil ? "Artwork" : "Text") layer \(index + 1) of \(plan.sections.count): \(section.title), x \(Int(frame.minX)), y \(Int(frame.minY))"
                if let text = element.text { item.setAccessibilityValue(String(text.string.prefix(4_000))) }
                item.setAccessibilityIdentifier("spaces-layer-" + id)
                editable = element.text != nil
            }
            item.setAccessibilityLabel(label)
            item.setAccessibilityFrameInParentSpace(frame.applying(CGAffineTransform(scaleX: zoom, y: zoom)))
            item.setAccessibilityHelp(active ? "Press to select. Use custom actions to edit or move this object. Keyboard: arrows select; Command-Option-Up or Down reorders; Option-arrow nudges imported layers." : "Preview canvas. Select this canvas to edit its objects.")
            if item.onPress == nil { item.onPress = { [weak self] in self?.activate(target) ?? false } }
            let movable = element(for: target)?.image != nil ? onArtworkTranslate != nil : onTranslate != nil
            let capabilities = active ? (editable && onTextEdit != nil ? 1 : 0) | (onMove != nil ? 2 : 0) | (movable ? 4 : 0) : 0
            if item.actionCapabilities != capabilities {
                var actions: [NSAccessibilityCustomAction] = []
                if capabilities & 1 != 0 {
                    actions.append(NSAccessibilityCustomAction(name: "Edit text") { [weak self] in self?.edit(target) ?? false })
                }
                if capabilities & 2 != 0 {
                    actions.append(NSAccessibilityCustomAction(name: "Move up in arrangement") { [weak self] in self?.reorder(target, offset: -1) ?? false })
                    actions.append(NSAccessibilityCustomAction(name: "Move down in arrangement") { [weak self] in self?.reorder(target, offset: 1) ?? false })
                }
                if capabilities & 4 != 0 {
                    actions.append(NSAccessibilityCustomAction(name: "Nudge left") { [weak self] in self?.nudge(target, dx: -1, dy: 0) ?? false })
                    actions.append(NSAccessibilityCustomAction(name: "Nudge right") { [weak self] in self?.nudge(target, dx: 1, dy: 0) ?? false })
                    actions.append(NSAccessibilityCustomAction(name: "Nudge up") { [weak self] in self?.nudge(target, dx: 0, dy: -1) ?? false })
                    actions.append(NSAccessibilityCustomAction(name: "Nudge down") { [weak self] in self?.nudge(target, dx: 0, dy: 1) ?? false })
                }
                item.setAccessibilityCustomActions(actions)
                item.actionCapabilities = capabilities
            }
            accessibleItems[target] = item
            ordered.append(item)
        }
        let valid = Set(targets)
        accessibleItems = accessibleItems.filter { valid.contains($0.key) }
        setAccessibilityChildren(ordered + (inlineEditor.map { [$0] } ?? []))
        setAccessibilityRole(.group)
        setAccessibilityLabel("Typography canvas, \(plan.sections.count) sections")
        setAccessibilityHelp("Use arrow keys to select objects. Press Return to edit text, Command-Option-Up or Down to reorder, and Option-arrow keys to move imported layers.")
    }
    func section(at point: NSPoint) -> CanvasSection? {
        let local = NSPoint(x: point.x / max(0.01, zoom), y: point.y / max(0.01, zoom))
        if let artwork = plan.elements.last(where: { $0.image != nil && $0.artworkInFront && $0.rect.contains(local) }),
           let section = plan.sections.first(where: { $0.id == artwork.sectionID }) { return section }
        if let text = plan.text(at: local), let section = plan.sections.first(where: { $0.id == text.sectionID }) { return section }
        if let artwork = plan.elements.last(where: { $0.image != nil && $0.rect.contains(local) }),
           let section = plan.sections.first(where: { $0.id == artwork.sectionID }) { return section }
        return plan.sections.last { $0.rect.contains(local) }
    }
    override func mouseDown(with event: NSEvent) {
        guard directionID != nil, let window else { return }
        window.makeFirstResponder(self)
        let origin = convert(event.locationInWindow, from: nil)
        guard let item = section(at: origin) else { return }
        selectedSection = item.id; needsDisplay = true
        let artwork = plan.elements.contains { $0.sectionID == item.id && $0.image != nil }
        let translate = artwork ? onArtworkTranslate : onTranslate
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
                if !moved, !artwork, let text = plan.text(at: local) {
                    onTextSelect?(text)
                    if event.clickCount >= 2, onTextEdit != nil { beginEditing(text) }
                }
                else { onSelect?(item.id) }
                if moved, bounds.contains(point) { if let translate { translate(item.id, (point.x - origin.x) / zoom, (point.y - origin.y) / zoom) } else if let target { onMove?(item.id, target.id, point.y / zoom < target.rect.midY) } }
                return
            }
            if moved {
                _ = autoscroll(with: next)
                if translate != nil { translation = NSPoint(x: (point.x - origin.x) / zoom, y: (point.y - origin.y) / zoom) }
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
        editor.backgroundColor = plan.paper
        editor.textColor = Self.editorTextColor(attributed, fallback: plan.ink)
        editor.font = (element.style?.font as NSFont?).map { NSFont(descriptor: $0.fontDescriptor, size: max(11, $0.pointSize * zoom)) ?? $0 } ?? .systemFont(ofSize: max(11, 14 * zoom))
        editor.alignment = element.style?.alignment?.native ?? .left
        editor.textContainerInset = NSSize(width: 4, height: 3)
        editor.isVerticallyResizable = false
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = []
        editor.wantsLayer = true
        editor.layer?.borderColor = ShelfPalette.nativeAccent.cgColor
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
        updateAccessibilityItems()
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
        updateAccessibilityItems()
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
    private func artworkURL(_ sender: NSDraggingInfo) -> URL? {
        guard onImportArtwork != nil,
              let objects = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]),
              objects.count == 1, let url = objects.first as? URL, url.isFileURL,
              SpacesArtworkImport.supportedExtensions.contains(url.pathExtension.lowercased()) else { return nil }
        return url
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { draggingUpdated(sender) }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        if artworkURL(sender) != nil {
            artworkDropHover = true; insertionY = nil; needsDisplay = true
            return .copy
        }
        artworkDropHover = false
        guard source(sender) != nil else { return [] }
        let point = convert(sender.draggingLocation, from: nil)
        guard let target = dropTarget(at: point) else { insertionY = nil; needsDisplay = true; return [] }
        insertionY = point.y / zoom < target.rect.midY ? target.rect.minY : target.rect.maxY; needsDisplay = true
        if case .role = source(sender) { return .copy }; return .move
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { insertionY = nil; artworkDropHover = false; needsDisplay = true }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { artworkURL(sender) != nil || source(sender) != nil }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer { insertionY = nil; artworkDropHover = false; needsDisplay = true }
        if let url = artworkURL(sender) {
            let point = convert(sender.draggingLocation, from: nil)
            onImportArtwork?(url, CGPoint(x: point.x / max(0.01, zoom), y: point.y / max(0.01, zoom)))
            return true
        }
        guard let source = source(sender) else { return false }
        let point = convert(sender.draggingLocation, from: nil)
        guard let target = dropTarget(at: point) else { return false }
        let before = point.y / zoom < target.rect.midY
        switch source { case .section(let id): onMove?(id, target.id, before); case .role(let role): onAddRole?(role, target.id, before) }
        return true
    }
    override func draw(_ dirtyRect: NSRect) {
        plan.paper.setFill()
        NSRect(origin: .zero, size: CGSize(width: plan.artboardSize.width * zoom, height: plan.artboardSize.height * zoom)).fill()
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current?.cgContext.scaleBy(x: zoom, y: zoom)
        NSBezierPath(rect: NSRect(origin: .zero, size: plan.artboardSize)).addClip()
        for element in plan.elements {
            if let image = element.image {
                image.draw(in: element.rect, from: .zero, operation: .sourceOver,
                           fraction: CGFloat(element.imageOpacity), respectFlipped: true, hints: nil)
            }
            if element.color != nil || element.strokeColor != nil {
                let shape = NSBezierPath(roundedRect: element.rect, xRadius: element.radius, yRadius: element.radius)
                if let color = element.color { color.setFill(); shape.fill() }
                if let stroke = element.strokeColor, element.strokeWidth > 0 {
                    stroke.setStroke(); shape.lineWidth = element.strokeWidth; shape.stroke()
                }
            }
            element.text?.draw(with: element.rect, options: [.usesLineFragmentOrigin, .usesFontLeading])
        }
        if directionID != nil, let textID = selectedTextID, let selected = plan.elements.first(where: { $0.textID == textID }) {
            let source = plan.textBounds(for: selected).offsetBy(dx: translation.x, dy: translation.y)
            let requestedInset = 1 / max(0.1, zoom)
            let insetX = min(requestedInset, max(0, source.width / 2 - 0.5))
            let insetY = min(requestedInset, max(0, source.height / 2 - 0.5))
            ShelfPalette.nativeAccent.withAlphaComponent(0.85).setStroke(); let border = NSBezierPath(roundedRect: source.insetBy(dx: insetX, dy: insetY), xRadius: 3 / zoom, yRadius: 3 / zoom); border.lineWidth = 2 / zoom; border.stroke()
        } else if directionID != nil, let selected = plan.sections.first(where: { $0.id == selectedSection }) {
            ShelfPalette.nativeAccent.withAlphaComponent(0.7).setStroke(); let border = NSBezierPath(rect: selected.rect.offsetBy(dx: translation.x, dy: translation.y).insetBy(dx: 1 / zoom, dy: 0)); border.lineWidth = 1 / zoom; border.stroke()
        }
        if let insertionY { ShelfPalette.nativeAccent.setFill(); NSRect(x: 0, y: insertionY, width: plan.size.width, height: 3 / zoom).fill() }
        if artworkDropHover {
            ShelfPalette.nativeAccent.withAlphaComponent(0.8).setStroke()
            let outline = NSBezierPath(rect: NSRect(origin: .zero, size: plan.artboardSize).insetBy(dx: 2 / zoom, dy: 2 / zoom))
            outline.lineWidth = 3 / zoom; outline.stroke()
        }
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
    var onArtworkTranslate: ((String, Double, Double) -> Void)?
    var onImportArtwork: ((URL, CGPoint) -> Void)?
    var onTextSelect: ((CanvasElement) -> Void)?
    var onTextEdit: ((CanvasElement, String) -> Void)?
    final class Coordinator {}
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> CanvasNativeView { CanvasNativeView(plan: plan) }
    func updateNSView(_ view: CanvasNativeView, context: Context) { view.plan = plan; view.zoom = zoom; view.directionID = directionID; view.selectedSection = selectedSection; view.selectedTextID = selectedTextID; view.onSelect = onSelect; view.onMove = onMove; view.onAddRole = onAddRole; view.onTranslate = onTranslate; view.onArtworkTranslate = onArtworkTranslate; view.onImportArtwork = onImportArtwork; view.onTextSelect = onTextSelect; view.onTextEdit = onTextEdit; view.frame.size = CGSize(width: plan.size.width * zoom, height: plan.size.height * zoom); view.synchronizeInlineEditor(); view.setAccessibilityElement(true); view.updateAccessibilityItems(); view.needsDisplay = true }
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
    enum ExportError: LocalizedError {
        case importedCanvas

        var errorDescription: String? {
            switch self {
            case .importedCanvas:
                return "Type system PDF does not support imported Figma or Adobe canvases yet. Use Preview PDF to export the selected imported canvas."
            }
        }
    }
    static func specimenDirection(from source: TypeDirection) -> TypeDirection {
        var direction = source
        direction.canvas = .specimen
        direction.width = min(1200, max(768, source.width))
        direction.blocks = nil
        direction.addedBlocks = nil
        direction.sectionOrder = nil
        direction.hiddenSections = nil
        direction.importedLayout = nil
        direction.canvasWidth = nil
        direction.canvasHeight = nil
        direction.importedSource = nil
        direction.importWarnings = nil
        direction.textOverrides = nil
        return direction
    }
    static func data(directions: [TypeDirection]) throws -> Data {
        guard !directions.isEmpty else { throw NSError(domain: "Typefield", code: 1, userInfo: [NSLocalizedDescriptionKey: "Select at least one canvas."]) }
        guard !directions.contains(where: { $0.canvas == .imported }) else { throw ExportError.importedCanvas }
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
