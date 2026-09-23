import SwiftUI

/// Editor state shared by the canvas and a detached inspector window.
/// Keeping the selections here lets either window update the other immediately.
final class StudioEditorSession: ObservableObject {
    @Published var board: TypeBoard
    @Published var role: TypeRole = .display
    @Published var selectedTextID: String?
    @Published var selectedSection: String?
    @Published var inspectorTab = "Typography"
    @Published var fontSearch = ""
    @Published var fontCollection = "All fonts"
    @Published var fontCategory = "All categories"
    @Published var showFontPicker = false

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
