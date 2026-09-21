import SwiftUI
import AppKit
import CoreText

enum CanvasKind: String, Codable, CaseIterable { case website = "Website", product = "Product UI", editorial = "Editorial", poster = "Poster", specimen = "Type system", custom = "Custom layout", imported = "Figma layout" }
enum ImportedLayoutSource: String, Codable {
    case figma
    case illustrator
    case indesign

    var displayName: String {
        switch self {
        case .figma: return "Figma layout"
        case .illustrator: return "Illustrator layout"
        case .indesign: return "InDesign layout"
        }
    }
    var unitLabel: String { self == .figma ? "px" : "pt" }
}
enum TypeRole: String, Codable, CaseIterable, Identifiable {
    case display = "Display", heading = "Heading", subheading = "Subheading", body = "Body", label = "UI label", caption = "Caption", mono = "Monospace"
    var id: String { rawValue }
    var size: Double { switch self { case .display: return 64; case .heading: return 36; case .subheading: return 24; case .body: return 18; case .label: return 14; case .caption: return 12; case .mono: return 14 } }
    var sample: String { switch self { case .display: return "A new perspective."; case .heading: return "Designed for everyday life"; case .subheading: return "Details make the difference"; case .body: return "Good design begins with a clear idea. Explore a collection of considered objects, useful tools, and stories about the way we live."; case .label: return "Explore collection"; case .caption: return "STUDIO JOURNAL · SEPTEMBER 2026"; case .mono: return "0123456789  /  Aa Bb Cc  /  { type: true }" } }
}
struct TypeStyle: Codable, Equatable {
    var fontName: String
    var size: Double
    var leading: Double = 1.35
    var tracking: Double = 0
    var axes: [Int: Double] = [:]
    var features: [String: Int] = [:]
    var text: String
    var alignment: TextAlignmentOption?
    var kerning: Bool?
    var lineHeight: Double?
    var paragraphSpacing: Double?
    var wordSpacing: Double?
    var indent: Double?
    var casing: TextCaseOption?
    var underline: Bool?
    var strikethrough: Bool?
    var kerningOverride: Bool? {
        if let kerning { return kerning }
        if let legacy = features["kern"] { return legacy != 0 }
        return nil
    }
    var effectiveKerning: Bool { kerningOverride ?? true }
    var featuresWithoutKerning: [String: Int] { features.filter { $0.key != "kern" } }
    var canonicalFeatures: [String: Int] {
        var values = featuresWithoutKerning
        if let kerningOverride { values["kern"] = kerningOverride ? 1 : 0 }
        return values
    }
    mutating func setKerning(_ enabled: Bool) {
        kerning = enabled
        features.removeValue(forKey: "kern")
    }
    var font: CTFont { OpenType.font(name: fontName, size: size, axes: axes, features: canonicalFeatures) }
    func attributed(_ source: String? = nil, color: NSColor) -> NSAttributedString {
        let raw = source ?? text
        let value = casing == .upper ? raw.uppercased() : casing == .lower ? raw.lowercased() : raw
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = (alignment ?? .left).native
        paragraph.minimumLineHeight = lineHeight ?? size * leading
        paragraph.maximumLineHeight = paragraph.minimumLineHeight
        paragraph.paragraphSpacing = paragraphSpacing ?? 0
        paragraph.firstLineHeadIndent = indent ?? 0
        paragraph.lineBreakMode = .byWordWrapping
        var attributes: [NSAttributedString.Key: Any] = [.font: font as NSFont, .foregroundColor: color, .paragraphStyle: paragraph]
        if tracking != 0 || !effectiveKerning { attributes[.kern] = tracking }
        if underline == true { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        if strikethrough == true { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        let result = NSMutableAttributedString(string: value, attributes: attributes)
        if let spacing = wordSpacing, spacing != 0 {
            let string = value as NSString
            for i in 0..<string.length where string.character(at: i) == 32 { result.addAttribute(.kern, value: tracking + spacing, range: NSRange(location: i, length: 1)) }
        }
        return result
    }
}
enum TextAlignmentOption: String, Codable, CaseIterable { case left = "Left", center = "Center", right = "Right", justified = "Justified"
    var native: NSTextAlignment { switch self { case .left: return .left; case .center: return .center; case .right: return .right; case .justified: return .justified } }
}
enum TextCaseOption: String, Codable, CaseIterable { case original = "Original", upper = "UPPERCASE", lower = "lowercase" }
struct LayoutBlock: Codable, Identifiable, Equatable { var id = UUID().uuidString; var role: TypeRole }
struct TypeDirection: Codable, Identifiable, Equatable {
    static let maximumTextBytes = 200_000
    var id = UUID()
    var name = "Direction A"
    var canvas: CanvasKind = .website
    var width: Double = 960
    var ink = "222222"
    var paper = "F5F2EA"
    var accent = "C59937"
    var styles: [String: TypeStyle] = [:]
    var notes = ""
    var blocks: [TypeRole]?
    var addedBlocks: [LayoutBlock]?
    var sectionOrder: [String]?
    var hiddenSections: Set<String>?
    var importedLayout: ImportedLayout?
    /// Optional so projects created before source tracking still decode. A
    /// missing value denotes the original Figma import flow.
    var importedSource: ImportedLayoutSource?
    var importWarnings: [String]?
    var textOverrides: [String: String]?
    var canvasDisplayName: String { canvas == .imported ? (importedSource ?? .figma).displayName : canvas.rawValue }
    var canvasUnitLabel: String { canvas == .imported ? (importedSource ?? .figma).unitLabel : "px" }
    static func seededFontIndex(for role: TypeRole, count: Int) -> Int {
        guard count > 1 else { return 0 }
        switch role {
        case .display: return 0
        case .heading: return count == 2 ? 0 : min(1, count - 1)
        case .subheading: return count == 2 ? 0 : min(count >= 5 ? 2 : 1, count - 1)
        case .body: return min(count >= 5 ? 3 : 2, count - 1)
        case .label, .caption: return min(count >= 6 ? 4 : (count >= 3 ? 2 : 1), count - 1)
        case .mono: return count - 1
        }
    }
    init(name: String = "Canvas 1", fonts: [String] = [], roleFonts: [String: String] = [:]) {
        self.name = name
        for role in TypeRole.allCases {
            let fallback = role == .mono ? "Menlo-Regular" : role == .display || role == .heading ? "Georgia" : "Helvetica"
            let index = Self.seededFontIndex(for: role, count: fonts.count)
            styles[role.rawValue] = TypeStyle(fontName: roleFonts[role.rawValue] ?? (fonts.isEmpty ? fallback : fonts[index]), size: role.size, text: role.sample)
        }
    }
    func style(_ role: TypeRole) -> TypeStyle { styles[role.rawValue] ?? TypeStyle(fontName: "Helvetica", size: role.size, text: role.sample) }
    mutating func setCanvasText(_ text: String, textID: String) {
        var overrides = textOverrides ?? [:]
        overrides[textID] = text
        textOverrides = overrides
    }
    static func acceptsCanvasText(_ text: String) -> Bool { text.utf8.count <= maximumTextBytes }
    @discardableResult mutating func setImportedText(_ text: String, layerID: String) -> Bool {
        guard let index = importedLayout?.layers.firstIndex(where: { $0.id == layerID }), var style = importedLayout?.layers[index].style else { return false }
        style.text = text
        importedLayout?.layers[index].style = style
        return true
    }
    func copy(name: String? = nil) -> TypeDirection { var value = self; value.id = UUID(); value.name = name ?? self.name + " copy"; return value }
    mutating func reorder(_ source: String, target: String, before: Bool, visible: [String]) {
        guard source != target, visible.contains(source), visible.contains(target) else { return }
        var order = visible.filter { $0 != source }
        guard let index = order.firstIndex(of: target) else { return }
        order.insert(source, at: index + (before ? 0 : 1)); sectionOrder = order
    }
    @discardableResult mutating func insert(_ role: TypeRole, target: String?, before: Bool, visible: [String]) -> String {
        let block = LayoutBlock(role: role)
        addedBlocks = (addedBlocks ?? []) + [block]
        let sectionID = canvas.rawValue + ":" + block.id
        var order = visible
        if let target, let index = order.firstIndex(of: target) { order.insert(sectionID, at: index + (before ? 0 : 1)) }
        else { order.append(sectionID) }
        sectionOrder = order
        return sectionID
    }
}
struct ImportedLayer: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var name: String
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var color: String
    var opacity: Double = 1
    var radius: Double = 0
    var style: TypeStyle?
    var rect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}
struct ImportedLayout: Codable, Equatable {
    var width: Double
    var height: Double
    var layers: [ImportedLayer]
    /// Use the first text layer only for the initial inspector state. A
    /// selected shape must not redirect edits to an unrelated text layer.
    func textLayerIndex(selectedID: String?) -> Int? {
        if let selectedID { return layers.firstIndex { $0.id == selectedID && $0.style != nil } }
        return layers.firstIndex { $0.style != nil }
    }
    var isValid: Bool {
        width.isFinite && height.isFinite && (1...10000).contains(width) && (1...100000).contains(height) && layers.count <= 5000 && Set(layers.map(\.id)).count == layers.count && layers.allSatisfy { layer in
            [layer.x, layer.y, layer.width, layer.height, layer.opacity, layer.radius].allSatisfy(\.isFinite) && abs(layer.x) <= 100000 && abs(layer.y) <= 100000 && (0.01...100000).contains(layer.width) && (0.01...100000).contains(layer.height) && (0...1).contains(layer.opacity) && (0...10000).contains(layer.radius) && (layer.style.map { $0.size.isFinite && (1...1000).contains($0.size) && TypeDirection.acceptsCanvasText($0.text) && $0.tracking.isFinite && abs($0.tracking) <= 100 && ($0.lineHeight.map { $0.isFinite && (1...2000).contains($0) } ?? true) && $0.axes.values.allSatisfy(\.isFinite) && [$0.paragraphSpacing, $0.indent, $0.wordSpacing].allSatisfy { $0.map { $0.isFinite && abs($0) <= 1000 } ?? true } } ?? true)
        }
    }
}
struct TypeBoard: Codable, Identifiable, Equatable {
    var id = UUID()
    var name = "Untitled typeboard"
    var directions = [TypeDirection()]
    var selectedDirection: UUID?
    var candidates: [String] = []
    var checkpoints: [DirectionCheckpoint]?
    func canvasName(_ canvas: TypeDirection) -> String {
        if canvas.name.range(of: #"^Direction [A-Z]( copy)*$"#, options: .regularExpression) != nil { return "Canvas \((directions.firstIndex { $0.id == canvas.id } ?? 0) + 1)" }
        return canvas.name
    }
    var nextCanvasName: String { var number = directions.count + 1; while directions.contains(where: { canvasName($0) == "Canvas \(number)" }) { number += 1 }; return "Canvas \(number)" }
    var isValid: Bool { !directions.isEmpty && directions.allSatisfy(\.isValid) && (checkpoints ?? []).allSatisfy { $0.direction.isValid } }
}
struct DirectionCheckpoint: Codable, Identifiable, Equatable {
    var id = UUID()
    var date = Date()
    var direction: TypeDirection
}
struct DesignSpace: Codable, Identifiable {
    var id = UUID()
    var name = "Untitled space"
    var boards: [TypeBoard] = []
    var displayName: String { name == "Pairing Studio" ? "My projects" : name }
}
struct StudioState: Codable {
    var version = 1
    var spaces: [DesignSpace] = []
    var selectedSpace: UUID?
    var selectedBoard: UUID?
}
final class StudioStore: ObservableObject {
    @Published var focusedSpace: UUID?
    @Published var focusedBoard: UUID?
    @Published var state = StudioState()
    @Published var error = ""
    @Published var savedAt: Date?
    let url: URL
    let undoManager = UndoManager()
    private var lastEdit: (board: UUID, action: String, date: Date)?
    private(set) var readBlocked = false
    init(url: URL) {
        self.url = url
        undoManager.levelsOfUndo = 100
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let loaded = try JSONDecoder().decode(StudioState.self, from: Data(contentsOf: url))
            guard loaded.version == 1, loaded.spaces.allSatisfy({ $0.boards.allSatisfy(\.isValid) }) else { throw NSError(domain: "FontShelf", code: 1, userInfo: [NSLocalizedDescriptionKey: "The workspace has invalid data or requires a newer FontShelf version."]) }
            state = loaded
            focusedSpace = loaded.selectedSpace; focusedBoard = loaded.selectedBoard
        } catch { readBlocked = true; self.error = "Spaces could not be opened. The saved file has been preserved. " + error.localizedDescription }
    }
    @discardableResult func save() -> Bool {
        guard !readBlocked else { return false }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let focusedSpace, let space = state.spaces.first(where: { $0.id == focusedSpace }) {
                if let focusedBoard, !space.boards.contains(where: { $0.id == focusedBoard }) { self.focusedBoard = nil }
            } else {
                focusedSpace = nil
                focusedBoard = nil
            }
            state.selectedSpace = focusedSpace; state.selectedBoard = focusedBoard
            let data = try JSONEncoder().encode(state)
            try LibraryBackupTools.preserve(url)
            if FileManager.default.fileExists(atPath: url.path) {
                try Data(contentsOf: url).write(to: url.appendingPathExtension("backup"), options: .atomic)
            }
            try data.write(to: url, options: .atomic); savedAt = Date(); error = ""; return true
        } catch { self.error = "Spaces could not be saved: " + error.localizedDescription; return false }
    }
    func addSpace(_ name: String) -> UUID? {
        guard !readBlocked else { return nil }
        let space = DesignSpace(name: name.isEmpty ? "Untitled space" : name)
        state.spaces.append(space); focusedSpace = space.id; focusedBoard = nil; save(); return space.id
    }
    func addBoard(space: UUID, fonts: [String] = [], roleFonts: [String: String] = [:]) -> UUID? {
        guard !readBlocked else { return nil }
        guard let i = state.spaces.firstIndex(where: { $0.id == space }) else { return nil }
        var number = state.spaces[i].boards.count + 1
        while state.spaces[i].boards.contains(where: { $0.name == "Typeboard \(number)" }) { number += 1 }
        let board = TypeBoard(name: "Typeboard \(number)", directions: [TypeDirection(fonts: fonts, roleFonts: roleFonts)], candidates: fonts)
        state.spaces[i].boards.append(board); focusedSpace = space; focusedBoard = board.id; save(); return board.id
    }
    func update(space: UUID, board: TypeBoard, action: String = "Edit Typeboard") {
        guard let i = state.spaces.firstIndex(where: { $0.id == space }), let j = state.spaces[i].boards.firstIndex(where: { $0.id == board.id }) else { return }
        let previous = state.spaces[i].boards[j]
        guard previous != board else { return }
        // Direction navigation isn't a document edit and shouldn't fill the undo stack.
        var content = previous; content.selectedDirection = board.selectedDirection
        if content != board {
            let replaying = undoManager.isUndoing || undoManager.isRedoing
            let coalesced = !replaying && !undoManager.canRedo && undoManager.canUndo && action.hasPrefix("Change ") && action != "Change Font" && lastEdit?.board == board.id && lastEdit?.action == action && Date().timeIntervalSince(lastEdit!.date) < 0.8
            if !coalesced {
                if !replaying { undoManager.beginUndoGrouping() }
                undoManager.registerUndo(withTarget: self) { store in
                    store.update(space: space, board: previous, action: action)
                    store.focusedSpace = space; store.focusedBoard = previous.id; store.save()
                }
                undoManager.setActionName(action)
                if !replaying { undoManager.endUndoGrouping() }
            }
            lastEdit = replaying ? nil : (board.id, action, Date())
        } else {
            lastEdit = nil
        }
        state.spaces[i].boards[j] = board; save()
    }
    func endUndoCoalescing() { lastEdit = nil }
    func removeBoard(space: UUID, id: UUID) {
        guard let i = state.spaces.firstIndex(where: { $0.id == space }), let j = state.spaces[i].boards.firstIndex(where: { $0.id == id }) else { return }
        let board = state.spaces[i].boards[j]
        let replaying = undoManager.isUndoing || undoManager.isRedoing
        if !replaying { undoManager.beginUndoGrouping() }
        undoManager.registerUndo(withTarget: self) { $0.restoreBoard(space: space, board: board, index: j) }
        undoManager.setActionName("Delete Typeboard")
        if !replaying { undoManager.endUndoGrouping() }
        lastEdit = nil; state.spaces[i].boards.remove(at: j)
        if focusedBoard == id { focusedBoard = state.spaces[i].boards.first?.id }
        save()
    }
    private func restoreBoard(space: UUID, board: TypeBoard, index: Int) {
        guard let i = state.spaces.firstIndex(where: { $0.id == space }), !state.spaces[i].boards.contains(where: { $0.id == board.id }) else { return }
        undoManager.registerUndo(withTarget: self) { $0.removeBoard(space: space, id: board.id) }
        undoManager.setActionName("Delete Typeboard")
        state.spaces[i].boards.insert(board, at: min(index, state.spaces[i].boards.count))
        focusedSpace = space; focusedBoard = board.id; lastEdit = nil; save()
    }
}

struct TagQuery: Equatable {
    var included: Set<String> = []
    var excluded: Set<String> = []
    var matchAll = true
    var active: Bool { !included.isEmpty || !excluded.isEmpty }
    static func contains(_ parent: String, in tags: Set<String>) -> Bool { tags.contains { $0 == parent || $0.hasPrefix(parent + "/") } }
    func matches(_ tags: Set<String>) -> Bool {
        let include = included.isEmpty || (matchAll ? included.allSatisfy { Self.contains($0, in: tags) } : included.contains { Self.contains($0, in: tags) })
        return include && !excluded.contains { Self.contains($0, in: tags) }
    }
    static func hierarchy(_ tags: Set<String>) -> [String] {
        var result = tags
        for tag in tags { let parts = tag.split(separator: "/"); for count in 1..<max(1, parts.count) { result.insert(parts.prefix(count).joined(separator: "/")) } }
        return result.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}
