import Foundation

enum StudioNavigationChecks {
    private static func check(_ condition: @autoclosure () throws -> Bool, _ message: String, line: Int = #line) throws {
        guard try condition() else {
            throw NSError(domain: "Typefield.NavigationCheck", code: line,
                          userInfo: [NSLocalizedDescriptionKey: "\(message) (StudioNavigationChecks.swift:\(line))"])
        }
    }
    private static func bytes(_ state: StudioState) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        return try encoder.encode(state)
    }
    private static func seed(_ store: StudioStore) throws {
        store.state.spaces = (0..<2).map { index in
            DesignSpace(name: "Space \(index)", boards: (0..<3).map { board in
                let directions = [TypeDirection(name: "First"), TypeDirection(name: "Second")]
                return TypeBoard(name: "Board \(board)", directions: directions, selectedDirection: directions[0].id)
            })
        }
        store.focusedSpace = store.state.spaces[0].id
        store.focusedBoard = store.state.spaces[0].boards[0].id
        store.undoManager.groupsByEvent = false
        try check(store.save() && store.save(), "Could not seed disposable navigation fixture")
    }
    private static func fixture(_ root: URL, _ name: String) throws -> StudioStore {
        let store = StudioStore(url: root.appendingPathComponent(name).appendingPathComponent("spaces.json"))
        try seed(store)
        return store
    }
    private static func chooseSecondBoard(_ store: StudioStore) -> Bool {
        store.select(space: store.state.spaces[0].id, board: store.state.spaces[0].boards[1].id)
    }
    static func run() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("Typefield-navigation-check-" + UUID().uuidString)
        defer { try? fm.removeItem(at: root) }
        do {
            let store = try fixture(root, "reopen")
            let document = try Data(contentsOf: store.url), backup = try Data(contentsOf: store.url.appendingPathExtension("backup"))
            try check(chooseSecondBoard(store), "Board navigation failed")
            for spaceIndex in store.state.spaces.indices {
                for boardIndex in store.state.spaces[spaceIndex].boards.indices {
                    var board = store.state.spaces[spaceIndex].boards[boardIndex]
                    board.selectedDirection = boardIndex == 2 ? nil : board.directions[1].id
                    try check(store.update(space: store.state.spaces[spaceIndex].id, board: board), "Canvas navigation failed")
                }
            }
            let reopened = StudioStore(url: store.url)
            try check(try bytes(reopened.state) == bytes(store.state), "Every board's selected canvas and focused board must survive reopen")
            try check(try Data(contentsOf: store.url) == document && Data(contentsOf: store.url.appendingPathExtension("backup")) == backup,
                      "Navigation must not rewrite the document or its content backup")
            try check(!store.undoManager.canUndo && store.error.isEmpty, "Navigation must not create undo actions")
            try check(store.select(space: store.state.spaces[0].id, board: nil), "Clearing board focus failed")
            try check(StudioStore(url: store.url).focusedBoard == nil, "Cleared board focus must survive reopen")
            var board = store.state.spaces[0].boards[0]; board.name = "Content edit after navigation"
            try check(store.update(space: store.state.spaces[0].id, board: board), "Content save following navigation failed")
            try check(try bytes(StudioStore(url: store.url).state) == bytes(store.state), "A full save must supersede the old navigation file")
            store.undoManager.undo(); store.undoManager.redo()
            try check(StudioStore(url: store.url).state.spaces[0].boards[0].name == board.name, "Navigation must not disrupt undo/redo persistence")
            try check(store.removeBoard(space: store.state.spaces[0].id, id: board.id), "Board deletion failed")
            try check(try bytes(StudioStore(url: store.url).state) == bytes(store.state), "Old navigation must not revive a deleted board")
        }
        do {
            let store = try fixture(root, "failure")
            var board = store.state.spaces[0].boards[0]
            let originalName = board.name
            board.name = "First edit"
            try check(store.update(space: store.state.spaces[0].id, board: board, action: "Change Name"), "Could not seed coalescing edit")
            let previous = try bytes(store.state), date = store.savedAt, focus = store.focusedBoard
            try fm.createDirectory(at: store.navigationURL, withIntermediateDirectories: false)
            try check(!chooseSecondBoard(store), "An obstructed navigation write must fail")
            try check(try bytes(store.state) == previous && store.savedAt == date && store.focusedBoard == focus && !store.error.isEmpty,
                      "Failed navigation must restore state, focus and save time")
            try fm.removeItem(at: store.navigationURL)
            board.name = "Second edit"
            try check(store.update(space: store.state.spaces[0].id, board: board, action: "Change Name"), "Coalesced edit after navigation failure failed")
            store.undoManager.undo()
            try check(store.state.spaces[0].boards[0].name == originalName, "Failed navigation must not end edit coalescing")
            try check(chooseSecondBoard(store), "Navigation must succeed when the obstruction is removed")
            try check(store.error.isEmpty && StudioStore(url: store.url).focusedBoard == store.focusedBoard, "Retried navigation did not persist")
        }
        do {
            let store = try fixture(root, "dirty")
            store.state.spaces[0].boards[0].name = "Direct external edit"
            let parent = store.url.deletingLastPathComponent(), held = root.appendingPathComponent("dirty-held")
            try fm.moveItem(at: parent, to: held)
            try Data("Obstruction".utf8).write(to: parent)
            try check(!chooseSecondBoard(store), "Dirty selection must fail when the full document cannot be saved")
            try fm.removeItem(at: parent); try fm.moveItem(at: held, to: parent)
            try check(chooseSecondBoard(store), "Dirty selection retry failed")
            try check(StudioStore(url: store.url).state.spaces[0].boards[0].name == "Direct external edit",
                      "A failed selection must not mark unsaved content clean or lose it on retry")
        }
        do {
            let store = try fixture(root, "replacement")
            try check(chooseSecondBoard(store), "Could not seed stale navigation")
            var replacement = store.state
            replacement.spaces[0].name = "Externally replaced"
            replacement.selectedBoard = replacement.spaces[0].boards[2].id
            let data = try bytes(replacement)
            try data.write(to: store.url, options: .atomic)
            try check(!store.select(space: store.state.spaces[1].id, board: nil), "A stale live window must not write navigation for a replaced document")
            try check(try Data(contentsOf: store.url) == data, "Stale navigation changed the replacement document")
            let reopened = StudioStore(url: store.url)
            try check(reopened.focusedBoard == replacement.selectedBoard && reopened.state.spaces[0].name == "Externally replaced",
                      "Old navigation must not override a replacement with the same IDs")
            try check(chooseSecondBoard(reopened), "The replacement must accept new navigation after reopening")
        }
        for kind in ["corrupt", "future", "oversize", "too-many-boards", "invalid-canvas", "partial", "directory", "symlink", "dangling-symlink"] {
            let store = try fixture(root, kind)
            try check(chooseSecondBoard(store), "Could not seed navigation preservation case")
            var object = try JSONSerialization.jsonObject(with: Data(contentsOf: store.navigationURL)) as! [String: Any]
            var expected: Data?
            switch kind {
            case "corrupt": expected = Data("Unrecognized navigation".utf8)
            case "future": object["version"] = 99
            case "oversize": expected = Data(repeating: 32, count: StudioNavigationSnapshot.maximumBytes + 1)
            case "too-many-boards": object["boards"] = Array(repeating: (object["boards"] as! [[String: Any]])[0], count: StudioNavigationSnapshot.maximumBoards + 1)
            case "invalid-canvas":
                var boards = object["boards"] as! [[String: Any]]; boards[0]["canvas"] = UUID().uuidString; object["boards"] = boards
            case "partial": object["boards"] = []
            case "directory", "symlink", "dangling-symlink":
                try fm.removeItem(at: store.navigationURL)
                if kind == "directory" { try fm.createDirectory(at: store.navigationURL, withIntermediateDirectories: false) }
                else {
                    let target = root.appendingPathComponent(kind + "-target")
                    if kind == "symlink" { try Data("Preserve target".utf8).write(to: target) }
                    try fm.createSymbolicLink(at: store.navigationURL, withDestinationURL: target)
                }
            default: break
            }
            if !["directory", "symlink", "dangling-symlink"].contains(kind) {
                if expected == nil { expected = try JSONSerialization.data(withJSONObject: object) }
                try expected!.write(to: store.navigationURL, options: .atomic)
            }
            let reopened = StudioStore(url: store.url)
            try check(!reopened.readBlocked && reopened.focusedBoard == store.state.spaces[0].boards[0].id,
                      "Unusable navigation must leave the original content and focus readable: \(kind)")
            try check(chooseSecondBoard(reopened), "Unusable navigation must fall back to the document save: \(kind)")
            try check(StudioStore(url: store.url).focusedBoard == reopened.focusedBoard, "Fallback navigation must survive reopen: \(kind)")
            if let expected { try check(try Data(contentsOf: store.navigationURL) == expected, "Unusable navigation bytes must be preserved: \(kind)") }
            else if kind == "directory" { try check(try fm.attributesOfItem(atPath: store.navigationURL.path)[.type] as? FileAttributeType == .typeDirectory, "Navigation directory was replaced") }
            else { try check(try fm.destinationOfSymbolicLink(atPath: store.navigationURL.path) == root.appendingPathComponent(kind + "-target").path, "Navigation symbolic link was replaced") }
        }
        print("PASS: Spaces navigation preserves content bytes, exact reopen state, undo, failed-save rollback/retry, dirty edits and external replacements; bounded invalid navigation stays intact.")
    }

    static func backupIntegration() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("Typefield-navigation-backup-check-" + UUID().uuidString)
        defer { try? fm.removeItem(at: root) }
        let library = Library(storageURL: root.appendingPathComponent("library.json"))
        try seed(library.studio)
        try check(library.save() && library.savePro(), "Could not seed backup fixture")
        try check(chooseSecondBoard(library.studio), "Could not seed exported navigation")
        var selected = library.studio.state.spaces[0].boards[1]
        selected.selectedDirection = selected.directions[1].id
        try check(library.studio.update(space: library.studio.state.spaces[0].id, board: selected), "Could not seed exported canvas selection")
        let backup = try LibraryBackupTools.snapshot(library)
        try check(try bytes(backup.spaces) == bytes(library.studio.state), "Portable backup must contain current navigation, including every canvas selection")
        let previous = try bytes(library.studio.state)
        var failed = false
        do {
            try LibraryBackupTools.merge(backup, into: library) { data, url in
                if url.lastPathComponent == "spaces.json" { throw CocoaError(.fileWriteNoPermission) }
                try data.write(to: url, options: .atomic)
            }
        } catch { failed = true }
        try check(failed && (try bytes(library.studio.state)) == previous, "Failed backup import must retain live navigation")
        try check(library.studio.select(space: library.studio.state.spaces[1].id, board: nil), "Navigation following backup rollback must rebind the recovered document")
        try check(try bytes(StudioStore(url: library.studio.url).state) == bytes(library.studio.state), "Navigation following rollback must survive reopen")
        try LibraryBackupTools.merge(backup, into: library)
        try check(library.studio.state.spaces.count == 4, "Successful backup merge lost projects")
        let committed = try Data(contentsOf: library.studio.url)
        try check(chooseSecondBoard(library.studio), "Navigation following committed backup import failed")
        try check(try Data(contentsOf: library.studio.url) == committed, "Successful import must refresh the clean document stamp for navigation")
        try check(try bytes(StudioStore(url: library.studio.url).state) == bytes(library.studio.state), "Navigation following successful import must survive reopen")
        print("PASS: backup export includes current Spaces navigation; committed imports and failed-import rollback both support navigation and exact reopen.")
    }
}
