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
                let background = luminance(TypefieldPalette.color(dark ? palette.night : palette.paper))
                try require((max(foreground, background) + 0.05) / (min(foreground, background) + 0.05) >= 4.5, "Palette text contrast: \(palette.title)")
            }
        }
        // A fused crossbar becomes one component (H); an overly fine glyph can vanish.
        for size in [16, 32, 64, 128] {
            guard let bitmap = TypefieldIcon.image(palette: .neutral, dark: false, size: size).representations.first as? NSBitmapImageRep else { throw CocoaError(.fileReadCorruptFile) }
            try require(bitmap.pixelsWide == size && bitmap.pixelsHigh == size, "Icon raster dimensions")
            var ink: Set<Int> = []
            for y in 0..<size { for x in 0..<size {
                if let pixel = bitmap.colorAt(x: x, y: y), pixel.alphaComponent > 0.7, luminance(pixel) < 0.25 { ink.insert(y * size + x) }
            } }
            var components = 0
            while let first = ink.first {
                components += 1
                ink.remove(first)
                var queue = [first]
                while let point = queue.popLast() {
                    let x = point % size, y = point / size
                    for (nx, ny) in [(x-1,y),(x+1,y),(x,y-1),(x,y+1)] where nx >= 0 && nx < size && ny >= 0 && ny < size {
                        let next = ny * size + nx
                        if ink.remove(next) != nil { queue.append(next) }
                    }
                }
            }
            try require(components == 2, "t and f must stay distinct at \(size) pixels (got \(components))")
        }
        try require(TypefieldPalette.resolve("unknown") == .neutral, "Unknown palette fallback")
        try require(TypefieldIcon.isDark(mode: "Dark", appearance: NSAppearance(named: .aqua)!), "Explicit dark icon")
        try require(!TypefieldIcon.isDark(mode: "Light", appearance: NSAppearance(named: .darkAqua)!), "Explicit light icon")
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
        print("Settings checks passed: six palette contrasts, separate tf silhouettes at 16/32/64/128 pixels, appearance modes, folder-save rollback.")
    }
}
