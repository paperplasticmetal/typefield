import AppKit

/// Opt-in live QA data. Call only for the temporary --window-qa Library.
/// No installed font is registered, and no existing project is imported.
enum WorkspaceStressFixtures {
    static func populate(_ library: Library) throws {
        var spaces: [DesignSpace] = []
        let kinds: [CanvasKind] = [.website, .editorial, .poster, .product]
        for spaceIndex in 0..<2 {
            var space = DesignSpace(name: "Performance QA \(spaceIndex + 1)")
            space.boards = [1, 8, 32].map { count in
                var board = TypeBoard(name: "\(count) canvases")
                board.directions = (0..<count).map { index in
                    var canvas = TypeDirection(name: "Canvas \(index + 1)", fonts: ["Helvetica", "Times-Roman"])
                    canvas.canvas = kinds[index % kinds.count]
                    canvas.width = 960
                    if spaceIndex == 0 {
                        canvas.boardPosition = CanvasBoardPosition(x: 24 + Double(index % 4) * 1_024,
                                                                   y: 52 + Double(index / 4) * 1_800)
                    }
                    return canvas
                }
                board.selectedDirection = board.directions[0].id
                return board
            }
            spaces.append(space)
        }
        library.studio.state.spaces = spaces
        library.studio.focusedSpace = spaces[0].id
        library.studio.focusedBoard = spaces[0].boards[2].id
        guard library.studio.save() else { throw failure(library.studio.error) }

        let projects = [24, 600, 10_000].map { count in
            var project = FontLabProject(name: "Performance QA \(count) anchors")
            let nodes = (0..<count).map { index -> FontLabVectorNode in
                let angle = Double(index) * 2 * Double.pi / Double(count)
                let radius = 0.32 + 0.03 * sin(3 * angle)
                return .init(point: .init(x: 0.5 + radius * cos(angle), y: 0.5 + radius * sin(angle)))
            }
            let glyph = FontLabGlyph(character: "A", strokes: [FontLabStroke(vectorPaths: [
                FontLabVectorPath(nodes: nodes, closed: true)
            ])], contourDesignWidth: 0.62)
            project.glyphs["A"] = glyph
            project.previewText = "A A A"
            return project
        }
        for project in projects {
            guard library.fontLab.addGeneratedProject(project) != nil else { throw failure(library.fontLab.error) }
        }
        guard library.fontLab.save() else { throw failure(library.fontLab.error) }
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "Typefield.WorkspaceStressFixtures", code: 1,
                userInfo: [NSLocalizedDescriptionKey: message])
    }
}
