import AppKit

enum FontLabPersistenceChecks {
    static func run() throws {
        func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
            if !condition() { throw FontLabStore.SelfTestError.failed(message) }
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Typefield-LetterformPersistence-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = root.appendingPathComponent("font-lab.json")
        let store = FontLabStore(url: destination)
        guard let id = store.addProject(name: "Save retry fixture") else {
            throw FontLabStore.SelfTestError.failed("Could not create the asynchronous-save fixture")
        }
        let baselineData = try Data(contentsOf: destination)
        try FileManager.default.removeItem(at: destination)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
        let stroke = FontLabStroke(points: [.init(x: 0.2, y: 0.3), .init(x: 0.8, y: 0.7)])
        let unsavedGlyph = FontLabGlyph(character: "A", strokes: [stroke])
        store.setGlyph(unsavedGlyph, in: id, save: false)
        store.scheduleSave(after: 0)
        let deadline = Date().addingTimeInterval(5)
        while store.error.isEmpty && Date() < deadline {
            _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        try check(!store.error.isEmpty && store.selectedProject?.glyphs["A"] == unsavedGlyph,
                  "A failed asynchronous save must report the failure and retain unsaved artwork in memory")
        // Dismissing the visible error must not clear the retry state.
        store.error = ""
        try FileManager.default.removeItem(at: destination)
        try baselineData.write(to: destination, options: .atomic)
        store.flushPendingSave()
        try check(store.error.isEmpty && FontLabStore(url: destination).selectedProject?.glyphs["A"] == unsavedGlyph,
                  "Flush must retry a completed failed background save even after its error was dismissed")

        func pointer(_ type: NSEvent.EventType, _ point: CGPoint) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
                              windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        func key(_ characters: String, _ code: UInt16, modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
                            windowNumber: 0, context: nil, characters: characters,
                            charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)!
        }
        func view(_ glyph: FontLabGlyph = FontLabGlyph(character: "A")) -> FontLabDrawingNSView {
            let view = FontLabDrawingNSView(frame: CGRect(x: 0, y: 0, width: 600, height: 600))
            view.replaceGlyph(glyph); view.smoothing = .off
            return view
        }
        func begin(_ view: FontLabDrawingNSView) {
            view.mouseDown(with: pointer(.leftMouseDown, CGPoint(x: 140, y: 180)))
            view.mouseDragged(with: pointer(.leftMouseDragged, CGPoint(x: 310, y: 330)))
        }
        func staleEvents(_ view: FontLabDrawingNSView) {
            view.mouseDragged(with: pointer(.leftMouseDragged, CGPoint(x: 400, y: 450)))
            view.mouseUp(with: pointer(.leftMouseUp, CGPoint(x: 400, y: 450)))
        }
        let escaped = view()
        let empty = escaped.glyph
        var escapeCommits = 0; escaped.onCommit = { _ in escapeCommits += 1 }
        begin(escaped)
        try check(escaped.isDrawing && !escaped.glyph.strokes.isEmpty && escapeCommits == 0,
                  "Sketch preview must remain uncommitted while drawing")
        escaped.keyDown(with: key("\u{1b}", 53)); staleEvents(escaped)
        try check(escaped.glyph == empty && !escaped.isDrawing && escapeCommits == 0,
                  "Escape must restore a sketch exactly and ignore its trailing mouse-up")

        let undo = view()
        var undoCommits: [FontLabGlyph] = []
        undo.onCommit = { undoCommits.append($0) }
        undo.onUndo = { undo.replaceGlyph(empty) }
        undo.onRedo = { if let latest = undoCommits.last { undo.replaceGlyph(latest) } }
        begin(undo); undo.keyDown(with: key("z", 6, modifiers: .command)); staleEvents(undo)
        try check(undo.glyph == empty && undoCommits.count == 1,
                  "Undo during a sketch must first finish exactly one transaction and prevent replay")
        undo.keyDown(with: key("z", 6, modifiers: [.command, .shift]))
        try check(undo.glyph == undoCommits[0] && undoCommits.count == 1,
                  "Redo must restore the complete interrupted stroke without generating another commit")

        for interruption in 0..<4 {
            let drawing = view()
            var commits = 0; drawing.onCommit = { _ in commits += 1 }
            drawing.onSelectTool = { drawing.tool = $0 }
            begin(drawing)
            let preview = drawing.glyph
            switch interruption {
            case 0: _ = drawing.resignFirstResponder()
            case 1: drawing.tool = .eraser
            case 2: drawing.keyDown(with: key("e", 14))
            default: drawing.viewWillMove(toWindow: nil)
            }
            staleEvents(drawing)
            try check(drawing.glyph == preview && !drawing.isDrawing && commits == 1,
                      "Focus, tool, keyboard-tool and detach changes must finish one sketch transaction")
        }

        let replacementView = view()
        var replacementCommits = 0; replacementView.onCommit = { _ in replacementCommits += 1 }
        begin(replacementView)
        var replacement = unsavedGlyph; replacement.character = "B"
        replacementView.replaceGlyph(replacement); staleEvents(replacementView)
        try check(replacementView.glyph == replacement && replacementCommits == 0 && !replacementView.isDrawing,
                  "Replacing a sketch glyph must discard an in-progress preview and ignore stale pointer events")

        let eraser = view(unsavedGlyph)
        eraser.tool = .eraser
        var eraseCommits = 0; eraser.onCommit = { _ in eraseCommits += 1 }
        eraser.mouseDown(with: pointer(.leftMouseDown, CGPoint(x: 134.4, y: 189.6)))
        try check(eraser.glyph.strokes.isEmpty, "Eraser fixture must remove the touched sketch stroke")
        eraser.keyDown(with: key("\u{1b}", 53)); staleEvents(eraser)
        try check(eraser.glyph == unsavedGlyph && eraseCommits == 0,
                  "Escape must undo an in-progress eraser gesture without a history entry")
        let untouched = view(unsavedGlyph)
        untouched.tool = .eraser
        var untouchedCommits = 0; untouched.onCommit = { _ in untouchedCommits += 1 }
        untouched.mouseDown(with: pointer(.leftMouseDown, CGPoint(x: 500, y: 80)))
        untouched.mouseUp(with: pointer(.leftMouseUp, CGPoint(x: 500, y: 80)))
        try check(untouched.glyph == unsavedGlyph && untouchedCommits == 0,
                  "Erasing empty canvas must not produce a phantom undo step")
        print("PASS: Letterform failed-save retry and sketch Escape, Undo/Redo, focus, tool, detach, replacement and eraser lifecycle checks")
    }
}
