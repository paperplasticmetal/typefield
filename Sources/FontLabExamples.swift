import SwiftUI
import AppKit

/// Original artwork shared by the in-app practice gallery and import checks.
enum FontLabExamples {
    static let handwritingSVG = """
    <svg xmlns="http://www.w3.org/2000/svg" width="700" height="240" viewBox="0 0 700 240">
    <g fill="none" stroke="black" stroke-width="13" stroke-linecap="round" stroke-linejoin="round">
    <path d="M30 173 Q35 130 45 91 M39 128 C67 67 105 80 92 128 L82 174"/>
    <path d="M196 89 C142 64 132 171 168 177 C211 188 234 83 196 89 Z"/>
    <path d="M270 218 L302 91 M294 124 C331 66 363 99 342 150 Q324 186 286 168"/>
    <path d="M413 172 L438 91"/>
    <path d="M557 88 L531 180 Q524 215 499 207"/>
    </g><g fill="black"><ellipse cx="455" cy="54" rx="8" ry="9"/><ellipse cx="565" cy="51" rx="9" ry="8"/></g></svg>
    """
    static let bubbleSVG = """
    <svg xmlns="http://www.w3.org/2000/svg" width="450" height="250" viewBox="0 0 450 250">
    <g fill="black" fill-rule="evenodd">
    <path d="M37 217 C10 198 15 63 36 34 C65 9 160 16 177 58 C191 85 174 111 159 119 C205 134 199 198 169 216 C135 241 60 235 37 217 Z M69 61 C88 47 133 52 132 78 C131 99 89 101 67 94 Z M64 146 C98 127 145 144 143 171 C140 196 87 200 63 184 Z"/>
    <path d="M312 24 C225 25 216 214 298 228 C389 244 438 45 348 25 Q329 19 312 24 Z M309 76 C347 54 370 91 357 140 C345 187 306 194 283 166 C263 141 278 91 309 76 Z"/>
    </g></svg>
    """

    static let roundedASVG = """
    <svg xmlns="http://www.w3.org/2000/svg" width="240" height="260" viewBox="0 0 120 130">
    <path d="M15 115 L60 15 L105 115 M32 78 H88" fill="none" stroke="black" stroke-width="12" stroke-linecap="round" stroke-linejoin="round"/>
    </svg>
    """
    static let titles = ["Handwriting: slant and detached dots", "Bubble letters: irregular counters", "Rounded A: simplify a dense trace"]
    static func make(_ index: Int, fitCurves: Bool = true) throws -> FontLabProject {
        let entries = [(handwritingSVG, "nopij"), (bubbleSVG, "BO"), (roundedASVG, "A")]
        let (svg, letters) = entries[index]
        let image = try FontLabArtworkReader.svgImage(Data(svg.utf8))
        let source = FontLabArtworkSource(image: image, filename: "Typefield practice artwork.svg", format: .svg, notices: [])
        var scan = try FontLabArtworkEngine.scan(source, options: FontLabArtworkOptions(), recognize: false)
        guard scan.regions.count == letters.count else { throw FontLabArtworkError.message("The example could not be separated into letters.") }
        for (i, letter) in letters.enumerated() { scan.regions[i].character = String(letter) }
        return try FontLabArtworkEngine.project(from: scan, name: "Practice: " + titles[index], fitCurves: fitCurves)
    }
}

struct FontLabExamplesView: View {
    let onOpen: (FontLabProject) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var choice = 0
    @State private var source: FontLabProject?
    @State private var rawCount = 0
    @State private var working = false
    @State private var error = ""
    @State private var revision = UUID()
    private var drawn: String { source?.characters.filter { source?.glyphs[$0]?.hasArtwork == true }.joined() ?? "" }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Letterform examples").font(.title2.bold())
            Text("Practice importing and editing original handwriting, bubble letters, and a rounded A. These synthetic examples open as separate projects.").foregroundStyle(.secondary)
            Picker("Example", selection: $choice) {
                ForEach(0..<FontLabExamples.titles.count, id: \.self) { Text(FontLabExamples.titles[$0]).tag($0) }
            }.disabled(working)
            if working { ProgressView("Importing practice artwork…").frame(height: 240) }
            else if let source {
                Text("Imported artwork: \(rawCount) trace points → \(source.glyphs.values.reduce(0) { $0 + FontLabVectorMath.paths(in: $1).flatMap(\.nodes).count }) editable anchors").font(.headline)
                FontLabPreviewCanvas(text: drawn, glyphs: source.glyphs, metrics: source.metrics, maximumEm: 170, centered: true).frame(height: 240)
            }
            if !error.isEmpty { Text(error).foregroundStyle(.red) }
            HStack {
                Text("Open a separate practice project to inspect nodes, change curves and undo edits.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Open editable example") {
                    guard var project = source else { return }
                    project.previewText = drawn
                    onOpen(project); dismiss()
                }.disabled(source == nil || working)
            }
        }.padding(24).frame(width: 820)
        .onAppear { generate() }.onChange(of: choice) { _ in generate() }
        .onDisappear { revision = UUID() }
    }
    private func generate() {
        let id = UUID(), index = choice
        revision = id; working = true; source = nil; error = ""
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { () throws -> (FontLabProject, Int) in
                let raw = try FontLabExamples.make(index, fitCurves: false)
                let project = try FontLabExamples.make(index)
                return (project, raw.glyphs.values.reduce(0) { $0 + FontLabVectorMath.paths(in: $1).flatMap(\.nodes).count })
            }
            DispatchQueue.main.async {
                guard revision == id else { return }; working = false
                switch result {
                case .success(let value): source = value.0; rawCount = value.1
                case .failure(let failure): error = failure.localizedDescription
                }
            }
        }
    }
}
