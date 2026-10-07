import SwiftUI

private struct TypefieldShortcut: Identifiable {
    let action: String
    let keys: String
    var id: String { action }
}

private struct TypefieldShortcutGroup: Identifiable {
    let title: String
    let symbol: String
    let shortcuts: [TypefieldShortcut]
    var id: String { title }
}

/// The reference lives in Help rather than repeating shortcut hints throughout
/// the canvas and inspector controls.
struct TypefieldShortcutReference: View {
    let dismiss: () -> Void
    var embedded = false
    @State private var search = ""

    private let groups: [TypefieldShortcutGroup] = [
        .init(title: "Workspaces", symbol: "square.grid.2x2", shortcuts: [
            .init(action: "Open Library", keys: "⌘1"),
            .init(action: "Open Spaces", keys: "⌘2"),
            .init(action: "Open Letterform Editor", keys: "⌘3"),
            .init(action: "Show or hide sidebar", keys: "⌃⌘S")
        ]),
        .init(title: "Library", symbol: "textformat", shortcuts: [
            .init(action: "Find fonts", keys: "⌘F"),
            .init(action: "List view", keys: "⇧⌘L"),
            .init(action: "Grid view", keys: "⇧⌘G"),
            .init(action: "Larger or smaller preview", keys: "⌘+ / ⌘−"),
            .init(action: "Reset preview size", keys: "⌘0")
        ]),
        .init(title: "Spaces", symbol: "square.stack.3d.up", shortcuts: [
            .init(action: "Previous or next canvas", keys: "⌥⌘← / ⌥⌘→"),
            .init(action: "Fit canvas width", keys: "⌘0"),
            .init(action: "Show or hide inspector", keys: "⌥⌘I"),
            .init(action: "Typography or Arrangement controls", keys: "⌥⌘T / ⌥⌘A"),
            .init(action: "Full / slim / hidden / floating inspector", keys: "⌥⌘1 / 2 / 3 / 4"),
            .init(action: "Enter or leave canvas focus", keys: "⌘."),
            .init(action: "Select previous or next canvas object while focused", keys: "← / → / ↑ / ↓"),
            .init(action: "Reorder selected canvas section or layer", keys: "⌘⌥↑ / ⌘⌥↓"),
            .init(action: "Move selected imported layer (Shift moves 10 units)", keys: "⌥arrow / ⇧⌥arrow"),
            .init(action: "Edit selected canvas text", keys: "Return"),
            .init(action: "Swap A/B canvases", keys: "⌘\\")
        ]),
        .init(title: "Letterform Editor", symbol: "pencil.and.outline", shortcuts: [
            .init(action: "Previous or next glyph", keys: "⌘[ / ⌘]"),
            .init(action: "Vector or Sketch view", keys: "⇧⌘1 / ⇧⌘2"),
            .init(action: "Vector tools: Select / Pen / Rectangle / Ellipse / Hand", keys: "V / P / R / O / H"),
            .init(action: "Sketch tools: Pen / Eraser / Reshape", keys: "P / E / V"),
            .init(action: "Nudge selected vector points", keys: "← / → / ↑ / ↓"),
            .init(action: "Select previous or next contour or node", keys: "⌥← / ⌥→"),
            .init(action: "Extend contour or node selection", keys: "⇧⌥← / ⇧⌥→"),
            .init(action: "Duplicate selected vector paths", keys: "⌘D"),
            .init(action: "Fit vector canvas", keys: "⌘0"),
            .init(action: "Undo or redo the current glyph's artwork and spacing", keys: "⌘Z / ⇧⌘Z")
        ]),
        .init(title: "Common", symbol: "keyboard", shortcuts: [
            .init(action: "Undo or redo text or the active workspace", keys: "⌘Z / ⇧⌘Z"),
            .init(action: "Cut / Copy / Paste text", keys: "⌘X / ⌘C / ⌘V"),
            .init(action: "New font browser window", keys: "⌘N"),
            .init(action: "New collection", keys: "⇧⌘N"),
            .init(action: "Full screen for the active window", keys: "⌃⌘F"),
            .init(action: "Close window (dock a popped-out editor)", keys: "⌘W"),
            .init(action: "Open Settings", keys: "⌘,")
        ])
    ]

    private var visibleGroups: [TypefieldShortcutGroup] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return groups }
        return groups.compactMap { group in
            if group.title.localizedCaseInsensitiveContains(query) { return group }
            let matching = group.shortcuts.filter { $0.action.localizedCaseInsensitiveContains(query) || $0.keys.localizedCaseInsensitiveContains(query) }
            return matching.isEmpty ? nil : .init(title: group.title, symbol: group.symbol, shortcuts: matching)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 15) {
                Image(systemName: "keyboard")
                    .font(.system(size: 25, weight: .light))
                    .foregroundStyle(ShelfPalette.indiaYellow)
                    .frame(width: 52, height: 52)
                    .background(ShelfPalette.indiaYellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 13))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Keyboard Shortcuts").font(.system(size: 25, weight: .semibold, design: .rounded))
                    Text("Commands follow the active workspace. Letterform tool keys work while its drawing canvas has focus.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
            }
            TextField("Search commands", text: $search)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Search keyboard shortcuts")
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    ForEach(visibleGroups) { group in
                        VStack(alignment: .leading, spacing: 7) {
                            Label(group.title, systemImage: group.symbol)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(ShelfPalette.indiaYellow)
                                .padding(.bottom, 3)
                            ForEach(group.shortcuts) { shortcut in
                                HStack(alignment: .firstTextBaseline, spacing: 14) {
                                    Text(shortcut.action).font(.system(size: 13))
                                    Spacer(minLength: 12)
                                    Text(shortcut.keys)
                                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.trailing)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if visibleGroups.isEmpty {
                        Text("No matching commands")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 28)
                    }
                }
                .padding(.trailing, 10)
            }
            if !embedded { HStack {
                Text("Also available from Help at any time.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Done", action: dismiss).buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            } }
        }
        .padding(embedded ? 0 : 26)
        .frame(width: embedded ? nil : 650, height: embedded ? nil : 580)
        .accessibilityIdentifier("typefield-keyboard-shortcuts")
    }
}
