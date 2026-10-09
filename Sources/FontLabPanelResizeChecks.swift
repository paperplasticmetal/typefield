import AppKit

/// Native divider transactions use disposable windows and in-memory preferences.
/// Moving the handle during a preview models SwiftUI laying out the resized panel.
enum FontLabPanelResizeChecks {
    private final class FocusTarget: NSView {
        override var acceptsFirstResponder: Bool { true }
    }

    private final class Harness {
        let window: NSWindow
        let root: NSView
        let focus = FocusTarget(frame: NSRect(x: 20, y: 20, width: 40, height: 40))
        let otherFocus = FocusTarget(frame: NSRect(x: 80, y: 20, width: 40, height: 40))
        let handle = FontLabPanelResizeNSView(frame: NSRect(x: 200, y: 80, width: 12, height: 400))
        var saved: Double
        var previews: [Double] = []
        var commits: [Double] = []
        var cancellations = 0
        var didCommit: (() -> Void)?

        init(axis: FontLabPanelResizeHandle.Axis = .horizontal, value: Double = 200,
             limits: ClosedRange<Double> = 100...400, defaultValue: Double = 240) {
            saved = value
            root = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 700))
            window = NSWindow(contentRect: root.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = root
            root.addSubview(focus); root.addSubview(otherFocus); root.addSubview(handle)
            handle.axis = axis; handle.value = value; handle.limits = limits; handle.defaultValue = defaultValue
            handle.onPreview = { [weak self] value in
                guard let self else { return }
                previews.append(value)
                // The representable receives this displayed value on layout.
                handle.value = value
                if handle.axis == .horizontal { handle.frame.origin.x = value }
                else { handle.frame.origin.y = 600 - value }
            }
            handle.onCommit = { [weak self] value in
                guard let self else { return }
                commits.append(value); saved = value; handle.value = value
                didCommit?()
            }
            handle.onCancel = { [weak self] in
                guard let self else { return }
                cancellations += 1; handle.value = saved
            }
            window.makeFirstResponder(focus)
        }

        func close() { window.close() }
        func event(_ type: NSEvent.EventType, x: Double = 100, y: Double = 400, clicks: Int = 1) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: NSPoint(x: x, y: y), modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: clicks, pressure: 1)!
        }
        func down(x: Double = 100, y: Double = 400, clicks: Int = 1) {
            handle.mouseDown(with: event(.leftMouseDown, x: x, y: y, clicks: clicks))
        }
        func drag(x: Double = 100, y: Double = 400) {
            handle.mouseDragged(with: event(.leftMouseDragged, x: x, y: y))
        }
        func up(x: Double = 100, y: Double = 400) {
            handle.mouseUp(with: event(.leftMouseUp, x: x, y: y))
        }
        func key(_ code: UInt16) {
            handle.keyDown(with: NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "",
                isARepeat: false, keyCode: code)!)
        }
    }

    private static func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw FontLabStore.SelfTestError.failed(message) }
    }

    static func run() throws {
        try check(Thread.isMainThread, "Panel resize checks must run on the AppKit main thread")
        try windowCoordinateTracking()
        try limitsAndReversal()
        try cancellationAndFocus()
        try discreteActions()
        try panelBounds()
        print("PASS: native panel resize coordinates, limits, release, cancellation, focus, reset and accessible adjustment")
    }

    private static func windowCoordinateTracking() throws {
        let horizontal = Harness()
        defer { horizontal.close() }
        horizontal.down()
        try check(horizontal.window.firstResponder === horizontal.handle,
                  "Pressing a divider must focus it so Escape and arrow keys work")
        horizontal.drag(x: 120)
        try check(horizontal.previews == [220] && horizontal.saved == 200 && horizontal.commits.isEmpty,
                  "Dragging must preview the panel size without persisting a preference")
        horizontal.drag(x: 120)
        try check(horizontal.handle.value == 220,
                  "A stationary pointer must not drift when layout moves the divider beneath it")
        horizontal.handle.frame.origin = NSPoint(x: 550, y: 160)
        horizontal.drag(x: 135)
        horizontal.drag(x: 135)
        try check(horizontal.handle.value == 235,
                  "Resize deltas must use window coordinates even after the divider changes position")
        horizontal.up(x: 142)
        try check(horizontal.saved == 242 && horizontal.commits == [242],
                  "Mouse-up must include its final pointer position and persist exactly one resize")
        try check(horizontal.window.firstResponder === horizontal.focus,
                  "Releasing a divider must restore the canvas or control that previously had focus")
        horizontal.up(x: 190); horizontal.drag(x: 200)
        try check(horizontal.commits == [242] && horizontal.handle.value == 242,
                  "Late drag or release events must not restart a completed resize")

        let vertical = Harness(axis: .vertical, value: 300, limits: 100...500)
        defer { vertical.close() }
        vertical.down(y: 400); vertical.drag(y: 375); vertical.drag(y: 375)
        try check(vertical.handle.value == 325 && vertical.saved == 300,
                  "Dragging a horizontal divider down must grow its top panel without local-coordinate feedback")
        vertical.drag(y: 385); vertical.up(y: 390)
        try check(vertical.commits == [310], "Dragging a horizontal divider upward must shrink the top panel")

        let quick = Harness()
        defer { quick.close() }
        quick.down(x: 100); quick.up(x: 127)
        try check(quick.commits == [227],
                  "A release that arrives without an intermediate drag event must still honor the pointer movement")
        let click = Harness()
        defer { click.close() }
        click.down(); click.up()
        try check(click.previews.isEmpty && click.commits.isEmpty && click.saved == 200
                  && click.window.firstResponder === click.focus,
                  "A stationary divider click must preserve the stored preference and restore focus without saving")

        let constrained = Harness(value: 194, limits: 184...194)
        defer { constrained.close() }
        constrained.saved = 420
        constrained.down(); constrained.up()
        try check(constrained.saved == 420 && constrained.handle.value == 194 && constrained.commits.isEmpty
                  && constrained.previews.isEmpty && constrained.window.firstResponder === constrained.focus,
                  "Clicking a temporarily clamped divider must retain the wider stored preference")
        constrained.down(); constrained.drag(); constrained.up()
        try check(constrained.saved == 420 && constrained.handle.value == 194 && constrained.commits.isEmpty
                  && constrained.previews.isEmpty,
                  "A drag event with no movement must not overwrite a wider stored panel preference")
        constrained.down(); constrained.drag(x: 140); constrained.up(x: 140)
        try check(constrained.saved == 420 && constrained.handle.value == 194 && constrained.commits.isEmpty
                  && constrained.previews.isEmpty,
                  "Dragging outward at a visible limit without resizing must preserve the stored preference")
        constrained.down(); constrained.drag(x: 140); constrained.drag(x: 135); constrained.up(x: 135)
        try check(constrained.saved == 189 && constrained.commits == [189],
                  "Reversing from a clamped edge must immediately resize and save the user's new width")
    }

    private static func limitsAndReversal() throws {
        let fixture = Harness(value: 280, limits: 100...300)
        defer { fixture.close() }
        fixture.down(); fixture.drag(x: 160)
        try check(fixture.handle.value == 300, "Resize previews must clamp at the maximum width")
        fixture.drag(x: 159)
        try check(fixture.handle.value == 299,
                  "Reversing at the maximum must respond immediately without retracing overshoot")
        fixture.drag(x: -100); fixture.drag(x: -99)
        try check(fixture.handle.value == 101,
                  "Reversing at the minimum must respond immediately without retracing overshoot")
        // A window resize updates both the limits and the displayed preference.
        fixture.handle.limits = 120...250; fixture.handle.value = 120
        fixture.drag(x: -79)
        try check(fixture.handle.value == 140,
                  "A resize must continue from the latest displayed size when layout changes its limits")
        fixture.handle.limits = 100...130
        fixture.up(x: -79)
        try check(fixture.commits == [130],
                  "Release must clamp to the current limits even when the pointer has not moved")

        let disabled = Harness(value: 200, limits: 200...200)
        defer { disabled.close() }
        disabled.down(); disabled.drag(x: 180); disabled.up(x: 180)
        try check(disabled.previews.isEmpty && disabled.commits.isEmpty && disabled.window.firstResponder === disabled.focus,
                  "A divider with no available resize range must not take focus or begin a drag")
    }

    private static func cancellationAndFocus() throws {
        let cancelled = Harness()
        defer { cancelled.close() }
        cancelled.down(); cancelled.drag(x: 140); cancelled.key(53)
        cancelled.up(x: 180)
        try check(cancelled.saved == 200 && cancelled.handle.value == 200 && cancelled.commits.isEmpty && cancelled.cancellations == 1,
                  "Escape must discard the preview once and prevent a later mouse-up from saving it")
        try check(cancelled.window.firstResponder === cancelled.focus,
                  "Escape must restore the previous responder after cancelling a resize")

        let detached = Harness()
        defer { detached.close() }
        detached.down(); detached.drag(x: 125); detached.handle.removeFromSuperview()
        detached.up(x: 160)
        try check(detached.saved == 200 && detached.commits.isEmpty && detached.cancellations == 1,
                  "Removing a divider mid-drag must cancel its temporary size instead of persisting it")

        let focus = Harness()
        defer { focus.close() }
        focus.down(); focus.drag(x: 135)
        focus.window.makeFirstResponder(focus.otherFocus)
        try check(focus.commits == [235], "Focus loss must commit the current preview exactly once")
        focus.up(x: 180)
        try check(focus.commits == [235] && focus.window.firstResponder === focus.otherFocus,
                  "A stale release after focus loss must not commit again or steal the new responder's focus")

        let reentrant = Harness()
        defer { reentrant.close() }
        reentrant.didCommit = { [weak reentrant] in reentrant?.handle.cancelOperation(nil) }
        reentrant.down(); reentrant.drag(x: 115); reentrant.up(x: 120)
        try check(reentrant.commits == [220] && reentrant.cancellations == 0,
                  "A commit callback must observe a finished transaction and cannot cancel or duplicate it")
    }

    private static func discreteActions() throws {
        let reset = Harness(value: 310, defaultValue: 240)
        defer { reset.close() }
        reset.down(clicks: 2); reset.up()
        try check(reset.commits == [240] && reset.previews.isEmpty && reset.window.firstResponder === reset.focus,
                  "Double-click must reset once and return keyboard focus without beginning a drag")
        reset.handle.limits = 100...220
        reset.down(clicks: 2)
        try check(reset.commits == [240, 220], "Double-click reset must respect the current panel limits")

        let keyboard = Harness()
        defer { keyboard.close() }
        keyboard.key(124); keyboard.key(123)
        try check(keyboard.commits == [224, 200] && keyboard.previews.isEmpty,
                  "Horizontal divider arrow keys must save discrete 24-point adjustments")
        keyboard.handle.axis = .vertical
        keyboard.key(125); keyboard.key(126)
        try check(keyboard.commits == [224, 200, 224, 200],
                  "Vertical divider Down and Up keys must grow and shrink the panel respectively")
        keyboard.handle.limits = 190...210
        try check(keyboard.handle.accessibilityPerformIncrement() && keyboard.handle.accessibilityPerformDecrement(),
                  "The divider must support native accessibility increment and decrement actions")
        try check(Array(keyboard.commits.suffix(2)) == [210, 190] && keyboard.handle.accessibilityRole() == .splitter
                  && keyboard.handle.accessibilityValue() as? String == "190 points",
                  "Accessible adjustments must obey the limits and expose the current size as a splitter")

        let interrupted = Harness()
        defer { interrupted.close() }
        interrupted.down(); interrupted.drag(x: 130); interrupted.key(124)
        interrupted.up(x: 190)
        try check(interrupted.commits == [230, 254],
                  "A keyboard adjustment during a drag must finish that resize, save the discrete action, and ignore stale release")
        interrupted.down(); interrupted.drag(x: 105)
        _ = interrupted.handle.accessibilityPerformDecrement()
        interrupted.up(x: 190)
        try check(Array(interrupted.commits.suffix(2)) == [259, 235] && interrupted.commits.count == 4,
                  "An accessibility adjustment during a drag must finish it before the separate adjustment")
    }

    private static func panelBounds() throws {
        for (width, lower, upper) in [(724.0, 184.0, 194.0), (980, 184, 420), (1200, 184, 420),
                                      (700, 170, 170), (682, 152, 152), (530, 152, 152), (0, 152, 152)] {
            let limits = FontLabCharacterPanelLayout.limits(workspaceWidth: width)
            try check(limits.lowerBound == lower && limits.upperBound == upper,
                      "Character panel limits must reserve the canvas at workspace width \(width)")
        }
        for width in stride(from: 0.0, through: 2000.0, by: 4.0) {
            let limits = FontLabCharacterPanelLayout.limits(workspaceWidth: width)
            try check(limits.lowerBound >= 0 && limits.lowerBound <= limits.upperBound
                      && limits.upperBound <= FontLabCharacterPanelLayout.maximumWidth,
                      "Character panel limits must remain ordered, nonnegative and capped")
            for stored in [-100.0, 184, 270, 420, 2000] {
                let visible = min(max(stored, limits.lowerBound), limits.upperBound)
                try check(limits.contains(visible) && (width < 682 || visible + 530 <= width),
                          "A stored character width must clamp to the visible workspace without overrunning the reserved editor")
            }
        }
    }
}
