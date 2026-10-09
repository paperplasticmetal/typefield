import AppKit
import SwiftUI

/// Exercise the actual workspace layout without opening a user project or
/// changing its panel preferences. These checks do not require drawing hardware.
enum FontLabWorkspaceControlsChecks {
    private static func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw FontLabStore.SelfTestError.failed(message) }
    }

    static func run() throws {
        try check(Thread.isMainThread, "Workspace controls checks must run on the AppKit main thread")
        let accessibility = try HostedAccessibility()
        defer { accessibility.restore() }
        try hostedWorkspace()
        try sketchEntry()
        print("PASS: Letterform metrics visibility in wide/compact/Focus layouts, header action targets, retained host state and drawing-device sketch entry")
    }

    private static func hostedWorkspace() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Typefield-workspace-controls-" + UUID().uuidString)
        let suite = "Typefield.WorkspaceControlsChecks." + UUID().uuidString
        guard let defaults = UserDefaults(suiteName: suite) else {
            throw FontLabStore.SelfTestError.failed("Could not create isolated workspace preferences")
        }
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: folder)
        }
        defaults.set(false, forKey: "fontLabProofStripExpanded")
        defaults.set(220.0, forKey: "fontLabCharacterBrowserWidth")
        let bridge = FontLabEditMenuBridge.shared
        let menuState = (bridge.projectID, bridge.character, bridge.canUndo, bridge.canRedo)
        defer { bridge.update(projectID: menuState.0, character: menuState.1, canUndo: menuState.2, canRedo: menuState.3) }

        let library = Library(storageURL: folder.appendingPathComponent("library.json"))
        var project = FontLabProject(name: "Workspace controls fixture", characters: ["O", "B"])
        let glyph = FontLabVectorChecks.fixture()
        project.glyphs["O"] = glyph
        project.previewText = "OB"
        try check(library.fontLab.addGeneratedProject(project) != nil && library.fontLab.save(),
                  "Workspace controls fixture must save only to its temporary project")
        let savedState = library.fontLab.state
        let session = FontLabEditorSession()
        session.selectedCharacter = "O"
        let root = FontLabView(library: library, sidebarCollapsed: .constant(true), session: session)
            .defaultAppStorage(defaults)
            .environment(\.locale, Locale(identifier: "en"))
        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = []
        hosting.frame = CGRect(x: 0, y: 0, width: 1600, height: 1100)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        let detached = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        detached.isReleasedWhenClosed = false
        window.contentView = hosting
        defer {
            window.contentView = nil; detached.contentView = nil
            window.close(); detached.close()
        }
        flushLayout(hosting)
        guard let initialCanvas = nativeCanvas(in: hosting) else {
            throw FontLabStore.SelfTestError.failed("Hosted Letterform workspace did not create a vector canvas")
        }
        let editor = initialCanvas.editor
        let selected = Set([editor.paths[0].nodes[0].id])
        editor.objectSelection = false
        editor.selection = selected
        editor.zoom = 1.17
        editor.pan = CGPoint(x: 11, y: -7)
        session.editHistory.record(glyph)
        let undo = session.editHistory.undoEntries
        let redo = session.editHistory.redoEntries

        func retainedState(_ context: String) throws {
            try check(nativeCanvas(in: hosting)?.editor === editor && editor.selection == selected &&
                      editor.zoom == 1.17 && editor.pan == CGPoint(x: 11, y: -7),
                      "\(context) must retain the editor, selected node, zoom and pan")
            try check(library.fontLab.state == savedState && editor.glyph == glyph &&
                      session.editHistory.undoEntries == undo && session.editHistory.redoEntries == redo,
                      "\(context) must not change artwork, metrics or undo/redo history")
        }

        for (width, focused) in [(1600.0, false), (980.0, false), (1600.0, true), (980.0, true), (1600.0, false)] {
            session.focusEditor = focused
            window.setContentSize(CGSize(width: width, height: 1100))
            hosting.frame = CGRect(x: 0, y: 0, width: width, height: 1100)
            let context = "width \(Int(width)), Focus \(focused)"
            for visible in [true, false, true] {
                // This is the same retained property bound by the real View
                // menu and the compact disclosure. The wide case failed before
                // the inspector also consumed this property.
                session.showMetrics = visible
                flushLayout(hosting)
                try metricsContent(visible: visible, in: hosting, window: window, context: context)
                try headerActions(in: hosting, window: window, context: context)
                try retainedState("Metrics toggle at \(context)")
            }
        }

        // WorkspaceWindows moves the existing host and enables Focus on pop-out.
        // Reproduce that lifecycle here with hidden windows and isolated defaults;
        // the separate window self-test covers its actual detach/dock commands.
        session.focusEditor = true
        session.showMetrics = false
        flushLayout(hosting)
        let canvasBeforeMove = nativeCanvas(in: hosting)
        window.contentView = nil
        detached.contentView = hosting
        flushLayout(hosting)
        try check(!session.showMetrics,
                  "A hidden metrics preference must survive moving the retained host to another window")
        try metricsContent(visible: false, in: hosting, window: detached, context: "moved Focus editor")
        session.showMetrics = true
        flushLayout(hosting)
        try metricsContent(visible: true, in: hosting, window: detached, context: "moved Focus editor")
        detached.contentView = nil
        window.contentView = hosting
        flushLayout(hosting)
        try check(nativeCanvas(in: hosting) === canvasBeforeMove && session.showMetrics,
                  "Returning the host must retain the same canvas and visible metrics")
        try metricsContent(visible: true, in: hosting, window: window, context: "returned Focus editor")
        try retainedState("Host reparenting")
    }

    private static func sketchEntry() throws {
        let session = FontLabEditorSession()
        session.drawingTool = .eraser
        session.nibStyle = .marker
        session.usesTabletPressure = false
        session.strokeWidth = 0.047
        session.smoothing = .strong
        let glyph = FontLabVectorChecks.fixture()
        session.editHistory.record(glyph)
        let editor = session.vector(for: "sketch-entry", glyph: glyph, metrics: FontLabMetrics())
        let node = editor.paths[0].nodes[0].id
        editor.selection = [node]
        var linked = FontLabGlyph(character: "B")
        linked.components = [FontLabComponentUse(source: "O")]
        try check(!session.startSketching(glyph: linked) && session.vectorEditing && session.drawingTool == .eraser &&
                  session.nibStyle == .marker && !session.usesTabletPressure,
                  "Drawing-device setup must not enter Sketch or change tools for a linked component glyph")
        try check(session.startSketching(glyph: glyph) && !session.vectorEditing && session.drawingTool == .pen &&
                  session.nibStyle == .round && session.usesTabletPressure,
                  "Start sketching must select the editable pen with round pressure-sensitive input")
        try check(session.strokeWidth == 0.047 && session.smoothing == .strong && editor.glyph == glyph &&
                  editor.selection == [node] && session.editHistory.undoEntries == [glyph.character: [glyph]] &&
                  session.editHistory.redoEntries == [glyph.character: []],
                  "Entering Sketch must preserve artwork, vector selection, existing brush width/smoothing and history")
    }

    private static func metricsContent(visible: Bool, in hosting: NSView, window: NSWindow, context: String) throws {
        // The disclosure propagates its own identifier onto expanded contents.
        // Inspect the actual editable controls instead. This Vector-only fixture
        // has no sliders outside Metrics and keeps the word proof collapsed.
        let exposed = controls(in: hosting)
        let sliders = uniqueFrames(exposed.filter { $0.role == .slider })
        let guides = uniqueFrames(exposed.filter {
            $0.role == .button && $0.label == "Guide" && $0.help == "Learn what each type metric controls"
        })
        try check(sliders.count == (visible ? 5 : 0) && guides.count == (visible ? 1 : 0),
                  "Metrics must expose exactly five sliders and one Guide when visible, and neither when hidden at \(context); visible \(visible), sliders \(sliders.count), guides \(guides.count)")
        if visible {
            let screenBounds = window.convertToScreen(hosting.convert(hosting.bounds, to: nil)).insetBy(dx: -0.5, dy: -0.5)
            try check((sliders + guides).allSatisfy { $0.width > 0 && $0.height > 0 && screenBounds.contains($0) },
                      "The visible metric controls must have usable on-screen frames at \(context)")
        }
    }

    private static func uniqueFrames(_ controls: [AccessibleControl]) -> [CGRect] {
        var frames: [CGRect] = []
        for control in controls {
            let frame = control.element.accessibilityFrame()
            if !frames.contains(frame) { frames.append(frame) }
        }
        return frames
    }

    private static func headerActions(in hosting: NSView, window: NSWindow, context: String) throws {
        let actions = [
            (identifier: "font-lab-import", label: "Import", help: "Import a letter, alphabet sheet, SVG or Procreate artwork"),
            (identifier: "font-lab-drawing-devices", label: "iPad & tablet", help: "Draw with Apple Pencil through Sidecar or a connected pen tablet")
        ]
        let screenBounds = window.convertToScreen(hosting.convert(hosting.bounds, to: nil)).insetBy(dx: -0.5, dy: -0.5)
        var frames: [CGRect] = []
        let exposed = controls(in: hosting)
        for expected in actions {
            // SwiftUI propagates the workspace container's identifier onto its
            // direct header actions. Real accessibility clients still receive
            // distinct button roles, names and help. Query that public contract
            // rather than requiring the child modifier's ID to survive grouping.
            guard let action = exposed.first(where: {
                $0.role == .button && $0.label == expected.label && $0.help == expected.help
            }) else {
                throw FontLabStore.SelfTestError.failed("Missing direct header action \(expected.identifier) at \(context)")
            }
            let frame = action.element.accessibilityFrame()
            try check(frame.width >= 35.5 && frame.height >= 35.5 && screenBounds.contains(frame),
                      "\(expected.identifier) must expose a full visible 36-point target at \(context)")
            frames.append(frame)
        }
        try check(!frames[0].intersects(frames[1]), "Import and device actions must not overlap at \(context)")
    }

    // Follow only the exposed accessibility tree. Traversing native subviews as
    // well would count controls retained behind a collapsed disclosure. SwiftUI
    // nodes implement the minimal element protocol, not NSAccessibilityProtocol.
    private struct AccessibleControl {
        let object: NSObject
        let element: NSAccessibilityElementProtocol
        var label: String? { (object as AnyObject).accessibilityLabel?() }
        var help: String? { (object as AnyObject).accessibilityHelp?() }
        var role: NSAccessibility.Role? { (object as AnyObject).accessibilityRole?() }
    }

    private static func controls(in hosting: NSView) -> [AccessibleControl] {
        var seen = Set<ObjectIdentifier>()
        var pending: [Any] = [hosting]
        var result: [AccessibleControl] = []
        while let value = pending.popLast() {
            guard let object = value as? NSObject, seen.insert(ObjectIdentifier(object)).inserted else { continue }
            if let element = object as? NSAccessibilityElementProtocol {
                result.append(AccessibleControl(object: object, element: element))
            }
            if let children = (object as AnyObject).accessibilityChildren?() { pending.append(contentsOf: children) }
        }
        return result
    }

    private static func nativeCanvas(in view: NSView) -> FontLabVectorNSView? {
        if let canvas = view as? FontLabVectorNSView { return canvas }
        for child in view.subviews { if let canvas = nativeCanvas(in: child) { return canvas } }
        return nil
    }

    private static func flushLayout(_ hosting: NSView) {
        for _ in 0..<8 {
            hosting.needsLayout = true
            hosting.layoutSubtreeIfNeeded()
            _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        hosting.layoutSubtreeIfNeeded()
    }

    /// Request only this process's lazy SwiftUI accessibility tree, restoring the
    /// previous state afterwards. This never enables VoiceOver system-wide.
    private struct HostedAccessibility {
        private typealias Getter = @convention(c) (AnyObject, Selector, NSString) -> Unmanaged<AnyObject>?
        private typealias Setter = @convention(c) (AnyObject, Selector, AnyObject?, NSString) -> Void
        private let application: NSApplication
        private let attribute = "AXEnhancedUserInterface" as NSString
        private let setterSelector = NSSelectorFromString("accessibilitySetValue:forAttribute:")
        private let setter: Setter
        private let previous: AnyObject?

        init() throws {
            let application = NSApplication.shared
            let getterSelector = NSSelectorFromString("accessibilityAttributeValue:")
            guard application.responds(to: getterSelector), application.responds(to: setterSelector),
                  let getterImplementation = application.method(for: getterSelector),
                  let setterImplementation = application.method(for: setterSelector) else {
                throw FontLabStore.SelfTestError.failed("AppKit cannot materialize the workspace accessibility tree")
            }
            let getter = unsafeBitCast(getterImplementation, to: Getter.self)
            let setter = unsafeBitCast(setterImplementation, to: Setter.self)
            self.application = application
            self.setter = setter
            previous = getter(application, getterSelector, attribute)?.takeUnretainedValue()
            setter(application, setterSelector, NSNumber(value: true), attribute)
        }

        func restore() { setter(application, setterSelector, previous ?? NSNumber(value: false), attribute) }
    }
}
