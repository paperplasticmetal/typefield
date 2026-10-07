import AppKit
import SwiftUI

enum FontLabShortcutAction: Equatable {
    case previousGlyph
    case nextGlyph
    case vectorEditor
    case sketchEditor
    case copyContours
    case pasteContours
    case selectAllContours

    var isVectorCommand: Bool { self == .copyContours || self == .pasteContours || self == .selectAllContours }

    static func resolve(key: String?, keyCode: UInt16? = nil, modifiers: NSEvent.ModifierFlags) -> Self? {
        let relevant = modifiers.intersection([.command, .option, .control, .shift])
        // Shifted number keys can arrive as punctuation in some keyboard layouts.
        if relevant == [.command, .shift] {
            if keyCode == 18 { return .vectorEditor }
            if keyCode == 19 { return .sketchEditor }
        }
        switch (key?.lowercased(), relevant) {
        case ("[", .command): return .previousGlyph
        case ("]", .command): return .nextGlyph
        case ("1", [.command, .shift]): return .vectorEditor
        case ("2", [.command, .shift]): return .sketchEditor
        case ("c", .command): return .copyContours
        case ("v", .command): return .pasteContours
        case ("a", .command): return .selectAllContours
        default: return nil
        }
    }
}

/// Keeps Letterform Editor commands local to its window. The event is left alone
/// while a text field is active, so project names and preview text edit normally.
struct FontLabShortcutBridge: NSViewRepresentable {
    let characters: [String]
    let selectedCharacter: String
    let canSketch: Bool
    let onSelectCharacter: (String) -> Void
    let onSelectMode: (Bool) -> Void
    let onVectorCommand: (FontLabShortcutAction) -> Bool

    func makeNSView(context: Context) -> FontLabShortcutAnchor { FontLabShortcutAnchor(frame: .zero) }

    func updateNSView(_ view: FontLabShortcutAnchor, context: Context) {
        view.onShortcut = { event in
            guard !characters.isEmpty,
                  let action = FontLabShortcutAction.resolve(
                    key: event.charactersIgnoringModifiers,
                    keyCode: event.keyCode,
                    modifiers: event.modifierFlags
                  ) else { return false }
            switch action {
            case .previousGlyph, .nextGlyph:
                guard let index = characters.firstIndex(of: selectedCharacter) else { return true }
                let next = index + (action == .previousGlyph ? -1 : 1)
                if characters.indices.contains(next) { onSelectCharacter(characters[next]) }
            case .vectorEditor:
                onSelectMode(true)
            case .sketchEditor:
                if canSketch { onSelectMode(false) }
            case .copyContours, .pasteContours, .selectAllContours:
                // The focused canvas finishes any gesture before its native
                // key equivalent. Only fill the workspace-focus gap here.
                guard !(event.window?.firstResponder is FontLabVectorNSView) else { return false }
                return onVectorCommand(action)
            }
            return true
        }
    }
}

final class FontLabShortcutAnchor: NSView {
    var onShortcut: ((NSEvent) -> Bool)?
    private var monitor: Any?

    static func allowsWorkspaceShortcuts(matchingWindow: Bool, isKeyWindow: Bool, hasSheet: Bool,
                                         hasModalWindow: Bool, firstResponder: NSResponder?) -> Bool {
        matchingWindow && isKeyWindow && !hasSheet && !hasModalWindow &&
        !(firstResponder is NSTextView) && !(firstResponder is NSTextField)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        guard let window else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak window] event in
            guard let self, let window,
                  Self.allowsWorkspaceShortcuts(matchingWindow: event.window === window, isKeyWindow: window.isKeyWindow,
                                                hasSheet: window.attachedSheet != nil, hasModalWindow: NSApp.modalWindow != nil,
                                                firstResponder: window.firstResponder) else { return event }
            return self.onShortcut?(event) == true ? nil : event
        }
    }

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }
}
