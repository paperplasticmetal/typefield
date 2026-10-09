import AppKit
import SwiftUI

/// Resize in window coordinates: the handle itself moves with the panel.
/// The caller keeps previews in memory and saves the preference on release.
struct FontLabPanelResizeHandle: NSViewRepresentable {
    enum Axis { case horizontal, vertical }
    let axis: Axis
    let value: Double
    let limits: ClosedRange<Double>
    let defaultValue: Double
    let label: String
    let identifier: String
    let onPreview: (Double) -> Void
    let onCommit: (Double) -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> FontLabPanelResizeNSView { FontLabPanelResizeNSView() }
    func updateNSView(_ view: FontLabPanelResizeNSView, context: Context) {
        view.axis = axis
        view.value = value
        view.limits = limits
        view.defaultValue = defaultValue
        view.onPreview = onPreview
        view.onCommit = onCommit
        view.onCancel = onCancel
        view.setAccessibilityLabel(TypefieldL10n.text(label))
        view.setAccessibilityIdentifier(identifier)
        view.toolTip = TypefieldL10n.text("Drag to resize. Double-click to reset. Arrow keys adjust; Escape cancels.")
        view.needsDisplay = true
    }
}

final class FontLabPanelResizeNSView: NSView {
    var axis = FontLabPanelResizeHandle.Axis.horizontal
    var value = 0.0
    var limits = 0.0...1.0
    var defaultValue = 0.0
    var onPreview: (Double) -> Void = { _ in }
    var onCommit: (Double) -> Void = { _ in }
    var onCancel: () -> Void = {}
    private var lastPosition: Double?
    private var didResize = false
    private weak var previousResponder: NSResponder?
    private var hovered = false
    private var tracking: NSTrackingArea?
    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area); tracking = area
    }
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: axis == .horizontal ? .resizeLeftRight : .resizeUpDown)
    }
    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }

    private func position(_ event: NSEvent) -> Double {
        axis == .horizontal ? event.locationInWindow.x : -event.locationInWindow.y
    }
    private func clamped(_ proposed: Double) -> Double { min(max(proposed, limits.lowerBound), limits.upperBound) }
    override func mouseDown(with event: NSEvent) {
        guard limits.lowerBound < limits.upperBound else { return }
        didResize = false
        previousResponder = window?.firstResponder
        window?.makeFirstResponder(self)
        if event.clickCount == 2 {
            value = clamped(defaultValue); onCommit(value); restoreFocus(); return
        }
        lastPosition = position(event)
    }
    override func mouseDragged(with event: NSEvent) {
        guard let lastPosition else { return }
        let current = position(event)
        // Incremental deltas let the pointer immediately reverse at a limit.
        let next = clamped(value + current - lastPosition)
        self.lastPosition = current
        guard next != value else { return }
        value = next; didResize = true
        onPreview(value); needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        guard lastPosition != nil else { return }
        if lastPosition != position(event) { mouseDragged(with: event) }
        finish(); restoreFocus()
    }
    private func finish() {
        guard lastPosition != nil else { return }
        let shouldCommit = didResize
        lastPosition = nil; didResize = false
        if shouldCommit { onCommit(clamped(value)) }
    }
    private func restoreFocus() {
        if let previousResponder { window?.makeFirstResponder(previousResponder) }
        previousResponder = nil
    }
    override func cancelOperation(_ sender: Any?) {
        guard lastPosition != nil else { return }
        lastPosition = nil; didResize = false; onCancel(); restoreFocus()
    }
    override func resignFirstResponder() -> Bool { finish(); return super.resignFirstResponder() }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil, lastPosition != nil { lastPosition = nil; didResize = false; onCancel() }
        super.viewWillMove(toWindow: newWindow)
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { cancelOperation(nil); return }
        let increment: Bool
        switch (axis, event.keyCode) {
        case (.horizontal, 124), (.vertical, 125): increment = true
        case (.horizontal, 123), (.vertical, 126): increment = false
        default: super.keyDown(with: event); return
        }
        adjust(increment ? 24 : -24)
    }
    private func adjust(_ amount: Double) {
        // Accessibility/keyboard adjustments are a separate discrete action.
        // Finish a pointer transaction first so its later mouseUp is ignored.
        finish()
        value = clamped(value + amount); onCommit(value); needsDisplay = true
    }
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .splitter }
    override func accessibilityValue() -> Any? { "\(Int(value.rounded())) points" }
    override func accessibilityPerformIncrement() -> Bool { adjust(24); return true }
    override func accessibilityPerformDecrement() -> Bool { adjust(-24); return true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.labelColor.withAlphaComponent(hovered || lastPosition != nil ? 0.08 : 0.025).setFill()
        bounds.fill()
        NSColor.secondaryLabelColor.withAlphaComponent(hovered ? 0.9 : 0.5).setFill()
        let grip = axis == .horizontal
            ? NSRect(x: bounds.midX - 1.5, y: max(12, min(bounds.midY - 19, 220)), width: 3, height: 38)
            : NSRect(x: bounds.midX - 21, y: bounds.midY - 1.5, width: 42, height: 3)
        NSBezierPath(roundedRect: grip, xRadius: 1.5, yRadius: 1.5).fill()
    }
}
