import AppKit
import SwiftUI

/// Real SwiftUI measurement of the shared header, with native geometry probes.
/// Fixtures never read or write a saved library or project.
enum WorkspaceHeaderChecks {
    private final class Fixture: ObservableObject {
        @Published var name = "A long project name with editable text"
        @Published var search = "font search"
        var markers: [String: NSView] = [:]
    }

    private struct Marker: NSViewRepresentable {
        let id: String
        let fixture: Fixture
        func makeNSView(context: Context) -> NSView {
            let view = NSView()
            fixture.markers[id] = view
            return view
        }
        func updateNSView(_ view: NSView, context: Context) {}
    }

    private struct FixtureHeader: View {
        @ObservedObject var fixture: Fixture
        let collapsed: Bool
        var body: some View {
            VStack(spacing: 0) {
                WorkspaceHeader(sidebarCollapsed: collapsed) {
                    TextField("Project name", text: $fixture.name)
                        .textFieldStyle(.plain).lineLimit(1)
                        .frame(minWidth: 160, maxWidth: .infinity)
                        .background(Marker(id: "identity", fixture: fixture))
                } actions: {
                    action("Rediscover", symbol: "shuffle", id: "rediscover")
                    action("New typeboard", symbol: "text.badge.plus", id: "new")
                    action("Advanced filters", symbol: "line.3.horizontal.decrease.circle", id: "filters", iconOnly: true)
                    action("Preview colors", symbol: "paintpalette", id: "colors", iconOnly: true)
                    Menu { Button("Rename typeboard…") {} } label: {
                        WorkspaceHeaderActionLabel("Board", systemImage: "rectangle.3.group", showsMenuIndicator: true)
                    }
                    .workspaceHeaderMenu()
                    .background(Marker(id: "board", fixture: fixture))
                    Menu { Button("Export…") {} } label: {
                        WorkspaceHeaderActionLabel("Export", systemImage: "square.and.arrow.up", showsMenuIndicator: true)
                    }
                    .workspaceHeaderMenu()
                    .background(Marker(id: "export", fixture: fixture))
                    TextField("Search fonts", text: $fixture.search)
                        .textFieldStyle(.plain).frame(width: 170, height: 36)
                        .padding(.horizontal, 10)
                        .background(Marker(id: "search", fixture: fixture))
                }
                Spacer(minLength: 0)
            }
        }
        private func action(_ title: LocalizedStringKey, symbol: String, id: String, iconOnly: Bool = false) -> some View {
            Button {} label: { WorkspaceHeaderActionLabel(title, systemImage: symbol, iconOnly: iconOnly) }
                .buttonStyle(.plain)
                .background(Marker(id: id, fixture: fixture))
        }
    }

    static func run() throws {
        func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
            if !condition() { throw NSError(domain: "Typefield.WorkspaceHeaderChecks", code: 1,
                userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        try require(Thread.isMainThread, "Header checks require the AppKit main thread")
        let actionIDs = ["rediscover", "new", "filters", "colors", "board", "export", "search"]
        for language in ["en", "de", "hi", "ja"] {
            for collapsed in [false, true] {
                let fixture = Fixture()
                let hosting = NSHostingView(rootView: FixtureHeader(fixture: fixture, collapsed: collapsed)
                    .environment(\.locale, Locale(identifier: language)))
                hosting.sizingOptions = []
                let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1440, height: 320),
                    styleMask: [.borderless], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.contentView = hosting
                defer { fixture.markers.removeAll(); window.contentView = nil; window.close() }
                flush(hosting)
                let originals = fixture.markers.mapValues(ObjectIdentifier.init)
                let nativeFields = textFields(in: hosting)
                guard let nameField = nativeFields.first(where: { $0.stringValue == fixture.name }) else {
                    throw NSError(domain: "Typefield.WorkspaceHeaderChecks", code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "Header fixture did not materialize its real name field"])
                }
                try require(window.makeFirstResponder(nameField), "Header fixture must focus its name field")
                let initialResponder = window.firstResponder
                let fieldIDs = Set(nativeFields.map(ObjectIdentifier.init))
                var wideTitleY: CGFloat?
                for width: CGFloat in [1440, 724, 440, 1440] {
                    window.setContentSize(CGSize(width: width, height: 320))
                    flush(hosting)
                    try require(fixture.markers.count == actionIDs.count + 1,
                                "Header must retain every visible action at \(width)/\(language)")
                    try require(fixture.markers.mapValues(ObjectIdentifier.init) == originals &&
                                Set(textFields(in: hosting).map(ObjectIdentifier.init)) == fieldIDs,
                                "Header resize must preserve each control and native text field")
                    try require(window.firstResponder === initialResponder && nameField.currentEditor() != nil,
                                "Header wrapping must preserve the active name editor")
                    try require(fixture.name == "A long project name with editable text" && fixture.search == "font search",
                                "Layout changes must preserve draft and search contents")
                    var frames: [String: CGRect] = [:]
                    for id in ["identity"] + actionIDs {
                        guard let marker = fixture.markers[id] else { continue }
                        let frame = marker.convert(marker.bounds, to: hosting)
                        frames[id] = frame
                        try require(hosting.bounds.insetBy(dx: -0.5, dy: -0.5).contains(frame),
                                    "Header \(id) must remain inside its viewport at \(width)/\(language)")
                        try require(frame.minX >= WorkspaceHeaderLayout.horizontalPadding + (collapsed ? WorkspaceSidebarLayout.revealWidth + 8 : 0) - 0.5,
                                    "Header controls must leave room for the sidebar reveal target")
                        if id != "identity" {
                            try require(frame.height >= WorkspaceHeaderLayout.actionHeight - 0.5,
                                        "Header action \(id) needs its full36point target")
                        }
                    }
                    let ids = ["identity"] + actionIDs
                    for first in ids.indices { for second in ids.indices where second > first {
                        guard let a = frames[ids[first]], let b = frames[ids[second]] else { continue }
                        let overlap = a.intersection(b)
                        try require(overlap.isNull || overlap.width * overlap.height < 0.5,
                                    "Header \(ids[first]) and \(ids[second]) overlap at \(width)/\(language)")
                    } }
                    if width == 1440, let title = frames["identity"] {
                        if let wideTitleY { try require(abs(title.midY - wideTitleY) < 0.5, "Returning wide must restore the shared header alignment") }
                        else { wideTitleY = title.midY }
                        try require(actionIDs.allSatisfy { abs((frames[$0]?.midY ?? 0) - title.midY) < 0.5 },
                                    "Wide headers must align identity and actions on one row")
                    }
                    if width == 440 {
                        let actionRows = Set(actionIDs.compactMap { frames[$0].map { Int($0.midY.rounded()) } })
                        try require(actionRows.count > 1, "Narrow header must wrap actions rather than hide them")
                    }
                }
            }
        }
        print("PASS: shared workspace header real layout, visible actions, translated narrow wrapping and native text focus retention")
    }

    private static func flush(_ view: NSView) {
        view.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        view.layoutSubtreeIfNeeded()
    }

    private static func textFields(in view: NSView) -> [NSTextField] {
        (view as? NSTextField).map { [$0] } ?? view.subviews.flatMap(textFields)
    }
}
