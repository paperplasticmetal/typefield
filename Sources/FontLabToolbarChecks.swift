import AppKit
import SwiftUI

/// Exercise the toolbar's real hosted controls as well as its canvas shortcuts.
/// The windows stay hidden and the glyphs never enter a saved project.
enum FontLabToolbarChecks {
    private struct ToolCase {
        let id: String
        let key: String
        let code: UInt16
        let tool: FontLabVectorTool
        let objects: Bool?
    }

    private static let tools: [ToolCase] = [
        .init(id: "select", key: "v", code: 9, tool: .select, objects: true),
        .init(id: "nodes", key: "a", code: 0, tool: .select, objects: false),
        .init(id: "pen", key: "p", code: 35, tool: .pen, objects: nil),
        .init(id: "line", key: "l", code: 37, tool: .line, objects: nil),
        .init(id: "rectangle", key: "r", code: 15, tool: .rectangle, objects: nil),
        .init(id: "ellipse", key: "o", code: 31, tool: .ellipse, objects: nil),
        .init(id: "hand", key: "h", code: 4, tool: .hand, objects: nil)
    ]

    private static func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw FontLabStore.SelfTestError.failed(message) }
    }

    private static func matches(_ item: ToolCase, editor: FontLabVectorEditor) -> Bool {
        editor.tool == item.tool && (item.objects.map { editor.objectSelection == $0 } ?? true)
    }

    static func run() throws {
        try check(Thread.isMainThread, "Toolbar checks must run on the AppKit main thread")
        try toolCommands()
        // SwiftUI builds its accessibility nodes lazily. Request that tree for
        // this process only, then restore the previous state after the checks.
        // This does not enable VoiceOver or change a system preference.
        let accessibility = try HostedAccessibility()
        defer { accessibility.restore() }
        for (width, compact) in [(1100.0, false), (440.0, true)] {
            try hostedTools(width: width, compact: compact)
        }
        print("PASS: vector toolbar targets, shortcut discovery, Select/Nodes parity, focus and stable hosted layout")
    }

    private static func toolCommands() throws {
        let glyph = FontLabVectorChecks.fixture()
        let editor = FontLabVectorEditor(glyph: glyph, metrics: FontLabMetrics())
        let canvas = FontLabVectorNSView(editor: editor)
        canvas.frame = CGRect(x: 0, y: 0, width: 640, height: 640)
        var commits = 0, focusRequests = 0
        editor.onCommit = { _ in commits += 1 }
        editor.onFocusCanvasRequested = { focusRequests += 1 }
        editor.selection = [editor.paths[1].nodes[0].id]
        editor.objectSelection = false
        editor.activateTool(.select)
        try check(editor.objectSelection && editor.selection == Set(editor.paths.flatMap(\.nodes).map(\.id)) && focusRequests == 1,
                  "Select must expand a touched counter to its complete object and request canvas focus once")
        let wholeObject = editor.selection
        editor.activateTool(.select, objects: false)
        try check(!editor.objectSelection && editor.selection == wholeObject && focusRequests == 2,
                  "Nodes must retain the selected points while returning to direct editing")

        for item in tools {
            // Start in a different mode and with a stale hint, so an ignored
            // shortcut cannot accidentally satisfy the selected-state check.
            editor.tool = item.tool == .hand ? .pen : .hand
            if let objects = item.objects { editor.objectSelection = !objects }
            editor.message = "Previous tool hint"
            let beforeFocus = focusRequests
            canvas.keyDown(with: key(item.key, code: item.code))
            try check(matches(item, editor: editor) && editor.message.isEmpty && focusRequests == beforeFocus + 1,
                      "Canvas \(item.key.uppercased()) must activate the same tool as its toolbar button and focus once")
            try check(editor.glyph == glyph && commits == 0,
                      "Changing vector tools must not alter artwork or add undo entries")
            try check(FontLabShortcutAction.resolve(key: item.key, modifiers: []) == nil,
                      "Single-letter tool keys must remain canvas-local rather than intercepting workspace text")
        }

        let open = FontLabVectorPath(nodes: [.init(point: .init(x: 0.2, y: 0.2)), .init(point: .init(x: 0.7, y: 0.7))])
        let constructionGlyph = FontLabGlyph(character: "A", strokes: [.init(vectorPaths: [open])], contourDesignWidth: 0.62)
        let construction = FontLabVectorEditor(glyph: constructionGlyph, metrics: FontLabMetrics())
        for item in tools {
            construction.tool = .pen; construction.activePath = open.id
            construction.activateTool(item.tool, objects: item.objects)
            try check(construction.activePath == nil && construction.glyph == constructionGlyph,
                      "Explicit tool activation must finish previous construction without modifying its saved path")
        }

        for responder in [NSTextView(), NSTextField()] as [NSResponder] {
            try check(!FontLabShortcutAnchor.allowsWorkspaceShortcuts(matchingWindow: true, isKeyWindow: true,
                hasSheet: false, hasModalWindow: false, firstResponder: responder),
                "Proof and inspector text must retain normal keyboard input after the toolbar update")
        }
    }

    private static func hostedTools(width: Double, compact: Bool) throws {
        let size = CGSize(width: width, height: 820)
        let glyph = FontLabVectorChecks.fixture()
        let metrics = FontLabMetrics()
        let editor = FontLabVectorEditor(glyph: glyph, metrics: metrics)
        var commits = 0
        let root = FontLabVectorEditorView(glyph: glyph, metrics: metrics, retainedEditor: editor,
            compact: compact, onChange: { _ in commits += 1 }, onUndo: {}, onRedo: {})
            .frame(width: size.width, height: size.height)
        let hosting = NSHostingView(rootView: root)
        hosting.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        defer { window.contentView = nil; window.close() }
        flushLayout(hosting)
        guard let canvas = nativeCanvas(in: hosting) else {
            throw FontLabStore.SelfTestError.failed("Hosted toolbar did not create its canvas at width \(width)")
        }
        let beforeCanvas = canvas.convert(canvas.bounds, to: hosting)
        let beforeDesign = canvas.designRect
        let hostScreenFrame = window.convertToScreen(hosting.convert(hosting.bounds, to: nil))
        var originalFrames: [String: CGRect] = [:]
        for item in tools {
            let button = try toolButton(item.id, in: hosting)
            let frame = button.accessibilityFrame()
            try check(frame.width >= 43.5 && frame.height >= 43.5,
                      "\(item.id) must expose the full 44×44 tool target at width \(width)")
            try check(hostScreenFrame.insetBy(dx: -0.5, dy: -0.5).contains(frame),
                      "\(item.id) must remain fully inside the hosted editor at width \(width)")
            let help = (button.accessibilityLabel() ?? "") + " " + (button.accessibilityHelp() ?? "")
            try check(help.contains("(\(item.key.uppercased()))"),
                      "\(item.id) must reveal its actual keyboard shortcut in accessible help")
            originalFrames[item.id] = frame
        }
        for first in tools.indices { for second in tools.indices where second > first {
            try check(!originalFrames[tools[first].id]!.intersects(originalFrames[tools[second].id]!),
                      "Tool targets must not overlap at width \(width)")
        } }

        for item in tools {
            // A toolbar press must restore keyboard control even if a text
            // responder was previously active in the same editor window.
            let text = NSTextView(frame: .zero)
            hosting.addSubview(text)
            _ = window.makeFirstResponder(text)
            try check(window.firstResponder === text, "Toolbar focus fixture could not focus its text responder")
            let button = try toolButton(item.id, in: hosting)
            try check(button.accessibilityPerformPress(), "The real hosted \(item.id) control must accept a press")
            flushLayout(hosting)
            text.removeFromSuperview()
            try check(matches(item, editor: editor) && window.firstResponder === canvas,
                      "Pressing \(item.id) must activate its tool and return keyboard focus to the canvas")
            try check(editor.glyph == glyph && commits == 0,
                      "Toolbar presses must not change the glyph or create history")
            try check(nativeCanvas(in: hosting) === canvas && sameRect(canvas.convert(canvas.bounds, to: hosting), beforeCanvas) &&
                      sameRect(canvas.designRect, beforeDesign),
                      "Switching to \(item.id) must not move or resize the canvas at width \(width)")
            for retained in tools {
                let retainedButton = try toolButton(retained.id, in: hosting)
                let frame = retainedButton.accessibilityFrame()
                try check(sameRect(frame, originalFrames[retained.id]!),
                          "Selected labels must not shift another tool's click target at width \(width)")
                try check((retainedButton.accessibilityValue() as? String) == (retained.id == item.id ? "Selected" : "Not selected"),
                          "The toolbar must expose exactly the active tool as selected, including distinct Select and Nodes states")
            }
        }
    }

    // SwiftUI.AccessibilityNode implements the public accessibility selectors
    // and minimal element protocol, but not NSAccessibilityProtocol. Requiring
    // the full protocol silently drops the actual hosted buttons from traversal.
    private struct AccessibleControl {
        let object: NSObject
        let element: NSAccessibilityElementProtocol

        func accessibilityFrame() -> CGRect { element.accessibilityFrame() }
        func accessibilityLabel() -> String? { (object as AnyObject).accessibilityLabel?() }
        func accessibilityHelp() -> String? { (object as AnyObject).accessibilityHelp?() }
        func accessibilityValue() -> Any? {
            let selector = NSSelectorFromString("accessibilityValue")
            guard object.responds(to: selector) else { return nil }
            return object.perform(selector)?.takeUnretainedValue()
        }
        func accessibilityPerformPress() -> Bool { (object as AnyObject).accessibilityPerformPress?() == true }
    }

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
                throw FontLabStore.SelfTestError.failed("AppKit cannot materialize the hosted accessibility tree")
            }
            // AppKit exposes no modern typed property for this process-local
            // accessibility request. Invoke its public informal-protocol
            // selectors with their exact Objective-C signatures; in particular,
            // the void setter must not be invoked as an object-returning perform.
            let getter = unsafeBitCast(getterImplementation, to: Getter.self)
            let setter = unsafeBitCast(setterImplementation, to: Setter.self)
            self.application = application
            self.setter = setter
            previous = getter(application, getterSelector, attribute)?.takeUnretainedValue()
            setter(application, setterSelector, NSNumber(value: true), attribute)
        }

        func restore() {
            setter(application, setterSelector, previous ?? NSNumber(value: false), attribute)
        }
    }

    private static func toolButton(_ id: String, in hosting: NSView) throws -> AccessibleControl {
        var seen = Set<ObjectIdentifier>()
        var pending: [Any] = [hosting]
        let identifier = "font-lab-tool-" + id
        while let value = pending.popLast() {
            guard let object = value as? NSObject, seen.insert(ObjectIdentifier(object)).inserted else { continue }
            if let element = object as? NSAccessibilityElementProtocol, element.accessibilityIdentifier?() == identifier {
                return AccessibleControl(object: object, element: element)
            }
            if let children = (object as AnyObject).accessibilityChildren?() {
                pending.append(contentsOf: children)
            }
            if let view = object as? NSView { pending.append(contentsOf: view.subviews) }
        }
        throw FontLabStore.SelfTestError.failed("Hosted toolbar is missing accessible control \(identifier)")
    }

    private static func nativeCanvas(in view: NSView) -> FontLabVectorNSView? {
        if let canvas = view as? FontLabVectorNSView { return canvas }
        for child in view.subviews { if let canvas = nativeCanvas(in: child) { return canvas } }
        return nil
    }

    private static func key(_ characters: String, code: UInt16) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
            context: nil, characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)!
    }

    private static func sameRect(_ first: CGRect, _ second: CGRect) -> Bool {
        abs(first.minX - second.minX) <= 0.5 && abs(first.minY - second.minY) <= 0.5 &&
        abs(first.width - second.width) <= 0.5 && abs(first.height - second.height) <= 0.5
    }

    private static func flushLayout(_ hosting: NSView) {
        for _ in 0..<8 {
            hosting.needsLayout = true
            hosting.layoutSubtreeIfNeeded()
            _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        hosting.layoutSubtreeIfNeeded()
    }
}
