import SwiftUI

/// Editor state shared by the canvas and a detached inspector window.
/// Keeping the selections here lets either window update the other immediately.
final class StudioEditorSession: ObservableObject {
    @Published var interactionTool = CanvasInteractionTool.auto
    @Published var selectedObjects: Set<String> = []
    @Published var arrangementExpanded = true
    @Published var selectionRevealToken = 0
    @Published var board: TypeBoard
    @Published var role: TypeRole = .display
    @Published var selectedTextID: String?
    @Published var selectedSection: String?
    @Published var inspectorTab = "Typography"
    @Published var fontSearch = ""
    @Published var fontCollection = "All fonts"
    @Published var fontCategory = "All categories"
    @Published var showFontPicker = false

    func selectObjects(_ ids: Set<String>, in direction: TypeDirection) {
        let plan = CanvasPlanCache.plan(for: direction)
        selectedObjects = ids.intersection(Set(plan.elements.map(\.objectID)))
        let elements = plan.elements.filter { selectedObjects.contains($0.objectID) }
        let sections = Set(elements.map(\.sectionID))
        selectedSection = sections.count == 1 ? sections.first : nil
        selectedTextID = elements.count == 1 ? elements.first?.textID : nil
        if elements.count == 1, let role = elements.first?.role { self.role = role }
    }

    init(board: TypeBoard) {
        self.board = board
    }
}

/// Observes both inputs so the separate NSHostingView refreshes when an edit,
/// selection, or installed-font change originates in the main editor window.
struct StudioFloatingInspectorHost: View {
    @ObservedObject var session: StudioEditorSession
    @ObservedObject var library: Library
    let content: () -> AnyView

    var body: some View {
        content()
    }
}
