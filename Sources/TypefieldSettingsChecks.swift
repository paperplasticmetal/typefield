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
        for palette in TypefieldPalette.allCases {
            for dark in [false, true] {
                let foreground = luminance(palette.accent(dark: dark))
                let workspaceBackground = luminance(ShelfPalette.workspaceColor(dark: dark))
                try require((max(foreground, workspaceBackground) + 0.05) / (min(foreground, workspaceBackground) + 0.05) >= 4.5, "Accent contrast on neutral workspace: \(palette.title)")
            }
        }
        try require(ShelfPalette.workspaceColor(dark: false).isEqual(TypefieldPalette.color("F6F7F9")), "Light workspace uses Porcelain surface")
        try require(ShelfPalette.workspaceColor(dark: true).isEqual(TypefieldPalette.color("171A20")), "Dark workspace uses Porcelain surface")
        // The high-contrast serif strokes must survive rasterization at small Dock sizes.
        for size in [16, 32, 64, 128] {
            guard let bitmap = TypefieldIcon.image(palette: .neutral, dark: false, size: size).representations.first as? NSBitmapImageRep else { throw CocoaError(.fileReadCorruptFile) }
            try require(bitmap.pixelsWide == size && bitmap.pixelsHigh == size, "Icon raster dimensions")
            var visibleInk = 0
            for y in 0..<size { for x in 0..<size {
                if let pixel = bitmap.colorAt(x: x, y: y), pixel.alphaComponent > 0.7, luminance(pixel) < 0.25 { visibleInk += 1 }
            } }
            try require(visibleInk > size * size / 20, "Serif icon remains visible at \(size) pixels")
        }
        for size in [32, 64, 128] {
            var rendered = Set<Data>()
            for design in TypefieldPalette.allCases {
                for dark in [false, true] {
                    guard let bitmap = TypefieldIcon.image(palette: design, dark: dark, size: size).representations.first as? NSBitmapImageRep,
                          bitmap.pixelsWide == size, bitmap.pixelsHigh == size,
                          let png = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileReadCorruptFile) }
                    rendered.insert(png)
                }
            }
            try require(rendered.count == TypefieldPalette.allCases.count * 2, "Icon designs and light/dark variants remain distinct at \(size) pixels")
        }
        try require(TypefieldPalette.resolve("unknown") == .neutral, "Unknown palette fallback")
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
        print("Settings checks passed: six accent contrasts, distinct icon designs at 32/64/128 pixels, serif icon at 16 pixels, appearance modes, folder-save rollback.")
    }
}
