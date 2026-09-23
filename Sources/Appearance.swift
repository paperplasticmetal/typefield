import SwiftUI
import AppKit

enum ShelfPalette {
    static var selected: TypefieldPalette { .resolve(UserDefaults.standard.string(forKey: "typefield.palette") ?? "neutral") }
    static var indiaYellow: Color { ink }
    static var nativeAccent: NSColor {
        selected.accent(dark: NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
    }
    static var ink: Color {
        let palette = selected
        return Color(nsColor: NSColor(name: nil) { appearance in
            palette.accent(dark: appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
        })
    }
    static func workspaceColor(dark: Bool) -> NSColor {
        TypefieldPalette.color(dark ? TypefieldPalette.neutral.night : TypefieldPalette.neutral.paper)
    }
    static var canvas: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            workspaceColor(dark: appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
        })
    }
}

private struct InsideGlassKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var shelfInsideGlass: Bool {
        get { self[InsideGlassKey.self] }
        set { self[InsideGlassKey.self] = newValue }
    }
}
struct ShelfGlass: ViewModifier {
    var radius: CGFloat
    @Environment(\.shelfInsideGlass) private var insideGlass
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ViewBuilder func body(content: Content) -> some View {
        if insideGlass {
            content
        } else if reduceTransparency {
            content.background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: radius))
                .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(Color.primary.opacity(0.2)))
        } else if #available(macOS 26, *) {
            content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: radius))
        } else {
            content.background(.regularMaterial, in: RoundedRectangle(cornerRadius: radius))
                .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(Color.primary.opacity(0.09)))
        }
    }
}
struct ShelfCardSurface: ViewModifier {
    var selected: Bool
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        content.padding(20)
            .background(scheme == .dark ? Color.white.opacity(hovered ? 0.055 : 0.025) : Color.white.opacity(0.8), in: shape)
            .clipShape(shape)
            .overlay(shape.strokeBorder(selected ? ShelfPalette.ink : hovered ? ShelfPalette.ink.opacity(contrast == .increased ? 0.5 : 0.25) : Color.primary.opacity(contrast == .increased ? 0.45 : 0.07), lineWidth: selected ? 1.5 : 1))
            .shadow(color: .black.opacity(scheme == .dark ? 0.07 : 0.025), radius: 5, y: 2)
            .onHover { hovered = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: hovered)
    }
}
extension View {
    func shelfGlass(radius: CGFloat = 18) -> some View { modifier(ShelfGlass(radius: radius)) }
    // Let AppKit measure the complete menu control; an undersized outer frame lets
    // its native indicator draw into the next button on newer macOS versions.
    func shelfIconMenu() -> some View { menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().padding(.horizontal, 6).frame(minWidth: 30, minHeight: 28) }
}

// All popup controls resolve their native text and menu appearance from the
// SwiftUI theme, including sheets, instead of retaining the system's old colors.
struct ShelfDropdown<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [(String, Value)]
    var showsTitle = true
    var body: some View {
        HStack(spacing: 6) {
            if showsTitle { Text(title).font(.caption).foregroundStyle(.secondary) }
            ShelfPopup(title: title, selection: $selection, options: options)
                .frame(minWidth: 65).frame(height: 26)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .shelfGlass(radius: 10)
        }
    }
}
struct ShelfPopup<Value: Hashable>: NSViewRepresentable {
    let title: String
    @Binding var selection: Value
    let options: [(String, Value)]
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var enabled
    func makeCoordinator() -> Coordinator { Coordinator(selection: $selection) }
    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.isBordered = false
        button.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        button.target = context.coordinator
        button.action = #selector(Coordinator.changed(_:))
        button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return button
    }
    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.selection = $selection
        context.coordinator.values = options.map { $0.1 }
        let titles = options.map { $0.0 }
        if button.itemTitles != titles { button.removeAllItems(); button.addItems(withTitles: titles) }
        button.setAccessibilityLabel(title)
        button.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        button.contentTintColor = .labelColor
        button.isEnabled = enabled
        button.selectItem(at: options.firstIndex { $0.1 == selection } ?? -1)
        button.needsDisplay = true
    }
    final class Coordinator: NSObject {
        var selection: Binding<Value>
        var values: [Value] = []
        init(selection: Binding<Value>) { self.selection = selection }
        @objc func changed(_ sender: NSPopUpButton) {
            let index = sender.indexOfSelectedItem
            if values.indices.contains(index) { selection.wrappedValue = values[index] }
        }
    }
}

struct ShelfSidebarGlass: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ViewBuilder func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        } else if #available(macOS 26, *) {
            content.glassEffect(.clear, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        } else {
            content.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }
}

struct SidebarSection<Content: View>: View {
    let title: String
    @AppStorage private var expanded: Bool
    let content: Content
    let onAdd: (() -> Void)?
    init(title: String, key: String, onAdd: (() -> Void)? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.onAdd = onAdd
        self._expanded = AppStorage(wrappedValue: true, key)
        self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
            Button { expanded.toggle() } label: {
                HStack {
                    Text(title).font(.caption.weight(.semibold))
                    Spacer()
                    Image(systemName: expanded ? "chevron.down" : "chevron.right").font(.system(size: 10, weight: .semibold))
                }.foregroundStyle(.secondary).contentShape(Rectangle())
            }.buttonStyle(.plain)
                .accessibilityValue(expanded ? "Expanded" : "Collapsed")
            if let onAdd {
                Button(action: onAdd) { Image(systemName: "plus").font(.system(size: 11, weight: .semibold)).frame(width: 20, height: 20) }
                    .buttonStyle(.plain).help("New collection").accessibilityLabel("New collection")
            }
            }.padding(.horizontal, 14)
            if expanded { content }
        }.padding(.top, 20)
    }
}
