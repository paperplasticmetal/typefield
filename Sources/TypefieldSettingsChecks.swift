import AppKit

/// Small-size silhouette and transactional folder settings regressions.
enum TypefieldSettingsChecks {
    static func run() throws {
        func require(_ value: Bool, _ message: String) throws {
            if !value { throw NSError(domain: "Typefield.SettingsChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        func luminance(_ color: NSColor) -> CGFloat {
            let rgb = color.usingColorSpace(.sRGB)!
            func linear(_ value: CGFloat) -> CGFloat { value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4) }
            return 0.2126 * linear(rgb.redComponent) + 0.7152 * linear(rgb.greenComponent) + 0.0722 * linear(rgb.blueComponent)
        }
        func contrast(_ foreground: NSColor, _ background: NSColor) -> CGFloat {
            let values = [luminance(foreground), luminance(background)].sorted()
            return (values[1] + 0.05) / (values[0] + 0.05)
        }
        func blend(_ foreground: NSColor, over background: NSColor, opacity: CGFloat) -> NSColor {
            let front = foreground.usingColorSpace(.sRGB)!
            let back = background.usingColorSpace(.sRGB)!
            return NSColor(srgbRed: front.redComponent * opacity + back.redComponent * (1 - opacity),
                           green: front.greenComponent * opacity + back.greenComponent * (1 - opacity),
                           blue: front.blueComponent * opacity + back.blueComponent * (1 - opacity), alpha: 1)
        }
        for palette in TypefieldPalette.allCases {
            for dark in [false, true] {
                let accent = palette.accent(dark: dark)
                let workspace = ShelfPalette.workspaceColor(dark: dark)
                let card = blend(.white, over: workspace, opacity: dark ? 0.025 : 0.8)
                let selectedRow = blend(accent, over: workspace, opacity: 0.13)
                try require(contrast(accent, workspace) >= 4.5, "Accent contrast on neutral workspace: \(palette.title)")
                try require(contrast(accent, card) >= 4.5, "Accent contrast on Library card: \(palette.title)")
                try require(contrast(accent, selectedRow) >= 4.5, "Selected Settings label contrast: \(palette.title)")
            }
        }
        for dark in [false, true] {
            let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
            var label = NSColor.black
            var control = NSColor.white
            var window = NSColor.white
            appearance.performAsCurrentDrawingAppearance {
                label = NSColor.labelColor.usingColorSpace(.sRGB)!
                control = NSColor.controlBackgroundColor.usingColorSpace(.sRGB)!
                window = NSColor.windowBackgroundColor.usingColorSpace(.sRGB)!
            }
            let workspace = ShelfPalette.workspaceColor(dark: dark)
            let exclusion = ShelfPalette.exclusionColor(dark: dark)
            let exclusionChip = blend(exclusion, over: workspace, opacity: 0.09)
            try require(contrast(exclusion, exclusionChip) >= 4.5, "Excluded search chip text contrast")
            for palette in TypefieldPalette.allCases {
                let accent = palette.accent(dark: dark)
                let opaqueSelectedRow = blend(accent, over: window, opacity: 0.13)
                try require(contrast(accent, opaqueSelectedRow) >= 4.5, "Selected Settings label with Reduce Transparency: \(palette.title)")
            }
            for background in [workspace, control] {
                let renderedLabel = blend(label, over: background, opacity: label.alphaComponent)
                try require(contrast(renderedLabel, background) >= 4.5, "Primary label contrast on workspace and opaque controls")
            }
        }
        try require(ShelfPalette.workspaceColor(dark: false).isEqual(TypefieldPalette.color("F6F7F9")), "Light workspace uses Porcelain surface")
        try require(ShelfPalette.workspaceColor(dark: true).isEqual(TypefieldPalette.color("171A20")), "Dark workspace uses Porcelain surface")
        // Icon colors share the established silhouette, including its small-size optical master.
        try require(TypefieldPalette.allCases.map(\.rawValue) == ["neutral", "amber", "ocean", "forest", "plum", "rose"], "Stored palette IDs remain stable")
        try require(TypefieldPalette.resolve("unknown") == .neutral, "Unknown palette fallback")
        for size in [16, 32, 48, 64, 128] {
            var rendered = Set<Data>()
            var referenceMask: [Bool]?
            for palette in TypefieldPalette.allCases {
                for dark in [false, true] {
                    let image = TypefieldIcon.image(palette: palette, dark: dark, size: size)
                    try require(image === TypefieldIcon.image(palette: palette, dark: dark, size: size), "Icon raster reuses the cache")
                    guard let bitmap = image.representations.first as? NSBitmapImageRep,
                          bitmap.pixelsWide == size, bitmap.pixelsHigh == size,
                          let png = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileReadCorruptFile) }
                    let colors = TypefieldIcon.colors(palette: palette, dark: dark)
                    try require(contrast(colors.ink, colors.paper) >= 4.5, "Icon ink contrast: \(palette.rawValue), dark=\(dark)")
                    let paper = colors.paper.usingColorSpace(.sRGB)!
                    let ink = colors.ink.usingColorSpace(.sRGB)!
                    let paperComponents = [paper.redComponent, paper.greenComponent, paper.blueComponent]
                    let inkComponents = [ink.redComponent, ink.greenComponent, ink.blueComponent]
                    // Use the most separated channel to compare coverage independently of color.
                    let channel = (0..<3).max { abs(inkComponents[$0] - paperComponents[$0]) < abs(inkComponents[$1] - paperComponents[$1]) }!
                    var mask: [Bool] = []
                    for y in 0..<size { for x in 0..<size {
                        guard let pixel = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { throw CocoaError(.fileReadCorruptFile) }
                        let components = [pixel.redComponent, pixel.greenComponent, pixel.blueComponent]
                        let coverage = (components[channel] - paperComponents[channel]) / (inkComponents[channel] - paperComponents[channel])
                        mask.append(pixel.alphaComponent > 0.7 && coverage > 0.55)
                    } }
                    try require(mask.filter { $0 }.count > size * size / 20, "Serif icon remains visible at \(size) pixels: \(palette.rawValue)")
                    if let referenceMask {
                        let differences = zip(mask, referenceMask).filter { $0 != $1 }.count
                        try require(differences <= max(2, size * size / 100), "Color preserves icon silhouette at \(size) pixels: \(palette.rawValue)")
                    } else { referenceMask = mask }
                    try require((bitmap.colorAt(x: 0, y: 0)?.alphaComponent ?? 1) == 0, "Icon retains transparent corner")
                    rendered.insert(png)
                }
            }
            try require(rendered.count == TypefieldPalette.allCases.count * 2, "Icon colors and light/dark variants remain distinct at \(size) pixels")
        }
        try require(TypefieldIcon.isDark(mode: "Dark", appearance: NSAppearance(named: .aqua)!), "Explicit dark icon")
        try require(!TypefieldIcon.isDark(mode: "Light", appearance: NSAppearance(named: .darkAqua)!), "Explicit light icon")
        try require(!TypefieldIcon.isDark(mode: "Automatic", appearance: NSAppearance(named: .aqua)!), "Automatic light icon appearance")
        try require(TypefieldIcon.isDark(mode: "Automatic", appearance: NSAppearance(named: .darkAqua)!), "Automatic icon appearance")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Typefield-settings-checks-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = Library(storageURL: root.appendingPathComponent("library.json"))
        let path = root.appendingPathComponent("Original Fonts").path
        library.saved.folders = [path]
        library.saved.autoActivateFolders = [path]
        library.librarySaveBlocked = true
        try require(!library.stopWatchingFolder(path), "Unreadable library cannot persist stop-watching")
        try require(library.saved.folders == [path] && library.saved.autoActivateFolders == [path], "Failed stop-watching must restore selected folders")
        try require(!library.setFolderActivation(path, enabled: false), "Unreadable library cannot change activation")
        try require(library.saved.autoActivateFolders == [path], "Failed activation edit must restore setting")
        print("Settings checks passed: accent, card, selected-label, and opaque-control contrast; icon color contrast, silhouettes, and cache reuse at 16/32/48/64/128 pixels; appearance modes; folder-save rollback.")
    }
}
