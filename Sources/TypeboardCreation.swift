import SwiftUI

struct TypeboardSeedDraft: Identifiable {
    let id = UUID()
    let fonts: [String]
    let source: String
    let spaceID: UUID?
    let suggested: [String: String]

    init(fonts: [String], source: String, spaceID: UUID? = nil) {
        var seen = Set<String>()
        self.fonts = fonts.filter { !$0.isEmpty && seen.insert($0).inserted }
        self.source = source
        self.spaceID = spaceID
        var roles: [String: String] = [:]
        if !self.fonts.isEmpty {
            for role in TypeRole.allCases {
                roles[role.rawValue] = self.fonts[TypeDirection.seededFontIndex(for: role, count: self.fonts.count)]
            }
        }
        suggested = roles
    }
}
struct TypeboardRoleMapper: View {
    @ObservedObject var library: Library
    let draft: TypeboardSeedDraft
    @State private var roles: [String: String]
    @Environment(\.dismiss) private var dismiss

    init(library: Library, draft: TypeboardSeedDraft) {
        self.library = library
        self.draft = draft
        _roles = State(initialValue: draft.suggested)
    }

    var destination: String {
        let id = draft.spaceID ?? library.studio.focusedSpace
        return library.studio.state.spaces.first { $0.id == id }?.displayName ?? library.studio.state.spaces.first?.displayName ?? "My projects"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Set up type roles").font(.title2)
                    Text("Choose a starting font for each role. This only initializes the first canvas; every role stays editable in Spaces.").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { library.typeboardDraft = nil; dismiss() }.keyboardShortcut(.cancelAction)
            }

            HStack {
                Label(draft.source, systemImage: "textformat")
                Spacer()
                Text("\(draft.fonts.count) \(draft.fonts.count == 1 ? "font" : "fonts") · “\(destination)”").foregroundStyle(.secondary)
            }.font(.caption)

            ScrollView {
                VStack(spacing: 10) {
                    ForEach(TypeRole.allCases) { role in
                        HStack(spacing: 14) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(role.rawValue).font(.headline)
                                Text(role.sample).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }.frame(width: 210, alignment: .leading)
                            ShelfDropdown(title: role.rawValue, selection: Binding(get: {
                                roles[role.rawValue] ?? draft.fonts[0]
                            }, set: { roles[role.rawValue] = $0 }), options: draft.fonts.map { name in
                                let face = library.allFaces.first { $0.name == name }
                                return ((face.map { "\($0.originalFamily) · \($0.style)" } ?? name), name)
                            }).frame(width: 300)
                            Text(role.sample).font(.custom(roles[role.rawValue] ?? draft.fonts[0], size: min(28, role.size))).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                        }.padding(12).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
                    }
                }
            }.frame(minHeight: 390, maxHeight: 520)

            HStack {
                Button("Reset suggestions") { roles = draft.suggested }
                Spacer()
                Button("Create typeboard") {
                    library.createTypeboard(from: draft, roles: roles)
                    dismiss()
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 860)
    }
}
