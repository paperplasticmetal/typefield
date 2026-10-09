import AppKit
import SwiftUI

/// A movable Spaces inspector that stays in the same application and editing
/// session as the canvas. Its root view observes shared editor state directly.
final class StudioFloatingInspector: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private var onUserClose: (() -> Void)?
    private var closingProgrammatically = false

    var isVisible: Bool { panel?.isVisible == true }

    func show(content: AnyView, title: String = "Spaces Inspector", relativeTo sourceWindow: NSWindow? = nil, onClose: @escaping () -> Void) {
        onUserClose = onClose
        if let panel {
            panel.makeKeyAndOrderFront(nil)
            return
        }

        let initialSize = NSSize(width: 350, height: 650)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: initialSize),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = title
        panel.minSize = NSSize(width: 290, height: 360)
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior.insert(.fullScreenAuxiliary)
        panel.delegate = self

        let host = NSHostingView(rootView: content.typefieldLocalized())
        host.sizingOptions = []
        panel.contentView = host
        self.panel = panel

        let frameName = "TypefieldSpacesInspector"
        if !panel.setFrameUsingName(frameName) {
            let source = sourceWindow ?? NSApp.mainWindow
            let visible = source?.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            let proposedX = (source?.frame.maxX ?? visible.midX) - initialSize.width - 24
            let proposedY = (source?.frame.maxY ?? visible.maxY) - initialSize.height - 64
            let x = min(max(proposedX, visible.minX + 16), visible.maxX - initialSize.width - 16)
            let y = min(max(proposedY, visible.minY + 16), visible.maxY - initialSize.height - 16)
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
        panel.setFrameAutosaveName(frameName)
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        guard let panel else { return }
        closingProgrammatically = true
        panel.close()
        self.panel = nil
        onUserClose = nil
        closingProgrammatically = false
    }

    func windowWillClose(_ notification: Notification) {
        guard !closingProgrammatically else { return }
        panel = nil
        let callback = onUserClose
        onUserClose = nil
        callback?()
    }

}
