import SwiftUI
import AppKit

enum StudioExportKind: String, CaseIterable, Identifiable {
    case summary = "Typography summary"
    case web = "Web-font performance"
    case handoff = "Developer handoff"
    case preview = "Preview PDF"
    case figma = "Editable Figma layout"
    var id: Self { self }
}

enum StudioExportScope: String, CaseIterable {
    case shown = "Shown canvases"
    case all = "All canvases"
    case current = "Current canvas"
    case selected = "Choose canvases"
    func ids(board: TypeBoard, shown: Set<UUID>, current: UUID, selected: Set<UUID>) -> Set<UUID> {
        let available = Set(board.directions.map(\.id))
        switch self {
        case .shown: return shown.intersection(available)
        case .all: return available
        case .current: return available.intersection([current])
        case .selected: return selected.intersection(available)
        }
    }
    static func board(_ source: TypeBoard, including ids: Set<UUID>) -> TypeBoard {
        var result = source
        result.directions = source.directions.filter { ids.contains($0.id) }
        if !result.directions.contains(where: { $0.id == result.selectedDirection }) {
            result.selectedDirection = result.directions.first?.id
        }
        // Checkpoint snapshots are unrelated to the chosen export scope.
        result.checkpoints = nil
        return result
    }
}

/// One visual page per selected canvas, preserving board order and each page's dimensions.
enum CanvasPreviewPDF {
    static func data(directions: [TypeDirection]) throws -> Data {
        guard let first = directions.first else { throw failure("Select at least one canvas.") }
        let result = NSMutableData()
        guard let consumer = CGDataConsumer(data: result as CFMutableData) else { throw failure("Could not create the PDF destination.") }
        var defaultBox = CGRect(origin: .zero, size: CanvasPlanCache.plan(for: first).size)
        guard let context = CGContext(consumer: consumer, mediaBox: &defaultBox, nil) else { throw failure("Could not create the PDF document.") }
        for direction in directions {
            let view = CanvasNativeView(plan: CanvasPlanCache.plan(for: direction))
            let data = view.dataWithPDF(inside: view.bounds)
            guard let provider = CGDataProvider(data: data as CFData), let document = CGPDFDocument(provider), let page = document.page(at: 1) else { throw failure("Could not render a canvas page.") }
            var box = page.getBoxRect(.mediaBox)
            context.beginPDFPage([kCGPDFContextMediaBox: NSData(bytes: &box, length: MemoryLayout<CGRect>.size)] as CFDictionary)
            context.drawPDFPage(page)
            context.endPDFPage()
        }
        context.closePDF()
        return result as Data
    }
    private static func failure(_ message: String) -> NSError { NSError(domain: "Typefield.PreviewPDF", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}
