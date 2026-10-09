import AppKit
import SwiftUI

enum TypefieldLanguageChecks {
    static func run() throws {
        func require(_ condition: Bool, _ message: String) throws {
            if !condition { throw NSError(domain: "Typefield.LanguageChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        for (preferred, expected) in [(["fr-CA"], TypefieldLanguage.fr), (["es-MX"], .es), (["de-AT"], .de), (["ja-JP"], .ja), (["hi-IN"], .hi), (["zh-TW"], .traditionalChinese), (["zh-HK"], .traditionalChinese), (["zh-Hans-TW"], .simplifiedChinese), (["zh_Hant_CN"], .traditionalChinese), (["zh-CN"], .simplifiedChinese), (["pt-PT"], .portuguese), (["it-IT"], .it), (["ko-KR"], .ko), (["ar", "fr"], .fr), (["ar"], .en), ([], .en)] {
            try require(TypefieldLanguage.resolve("system", preferred: preferred) == expected, "System matching: \(preferred)")
        }
        try require(TypefieldLanguage.resolve("en", preferred: ["ja"]) == .en, "Explicit English overrides system")
        try require(TypefieldLanguage.resolve("unknown", preferred: ["es"]) == .es, "Invalid preference uses system fallback")
        let suite = "Typefield.LanguageChecks." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("Dark", forKey: "appearance")
        defaults.set("Library", forKey: "previewText")
        let settings = TypefieldLanguageSettings(defaults: defaults, preferred: ["ja"], observeSystem: false)
        try require(settings.selection == "system" && settings.effective == .ja, "Fresh install follows system")
        settings.select("de", preferred: ["ja"])
        let relaunched = TypefieldLanguageSettings(defaults: defaults, preferred: ["ja"], observeSystem: false)
        try require(relaunched.selection == "de" && relaunched.effective == .de, "Selection survives relaunch")
        settings.select("invalid", preferred: ["ja"])
        try require(settings.selection == "de", "Invalid selection ignored")
        settings.select("system", preferred: ["hi-IN"])
        try require(settings.effective == .hi, "Return to system resolves again")
        try require(defaults.string(forKey: "appearance") == "Dark" && defaults.string(forKey: "previewText") == "Library", "Changing language leaves other preferences and specimen content intact")
        let keys = ["Language", "Settings", "Cancel", "Library", "Next", "Quite the\ncharacter.", "Draw a Letter", "Appearance", "Paths", "Import artwork", "System language", "Check for Updates…"]
        var keySet: Set<String>?
        for language in TypefieldLanguage.allCases where language != .system {
            guard let path = TypefieldL10n.resourceBundle.path(forResource: language.rawValue, ofType: "lproj"),
                  let data = try? Data(contentsOf: URL(fileURLWithPath: path).appendingPathComponent("Localizable.strings")),
                  let table = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String] else {
                throw NSError(domain: "Typefield.LanguageChecks", code: 2, userInfo: [NSLocalizedDescriptionKey: "Missing bundled table: \(language.rawValue)"])
            }
            if let keySet { try require(Set(table.keys) == keySet, "Catalog parity: \(language)") }
            else { keySet = Set(table.keys) }
            for key in keys {
                try require(table[key]?.isEmpty == false, "Missing core translation: \(language): \(key)")
                try require(TypefieldL10n.text(key, language: language) == table[key], "AppKit uses selected table: \(language): \(key)")
            }
            try require(TypefieldL10n.text("Untranslated diagnostic", language: language) == "Untranslated diagnostic", "Missing keys fall back safely")
        }
        try require(TypefieldL10n.text("Library", language: .fr) == "Bibliothèque", "French resource sanity")
        try require(TypefieldL10n.text("Settings", language: .ja) == "設定", "Japanese resource sanity")
        print("Language checks passed: resolution, fallback, isolated persistence, preservation and 11 bundled catalogs.")
    }
    /// Real SwiftUI rendering in a GUI session; isolated settings and empty library.
    @MainActor static func snapshots(directory: URL) throws {
        try run()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let fixture = FileManager.default.temporaryDirectory.appendingPathComponent("Typefield-LanguageSnapshots-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: fixture) }
        let library = Library(storageURL: fixture.appendingPathComponent("library.json"))
        let selection = TypefieldSettingsSelection()
        selection.page = .language
        for language in TypefieldLanguage.allCases where language != .system {
            let locale = Locale(identifier: language.rawValue)
            TypefieldLanguageSettings.shared.select(language.rawValue)
            for (step, page) in ["tour", "tour-library", "tour-spaces", "tour-letterforms", "settings"].enumerated() {
                let root: AnyView = page != "settings"
                    ? AnyView(TypefieldTour(dismiss: {}, open: { _ in }, initialStep: step).environment(\.locale, locale))
                    : AnyView(TypefieldSettingsView(library: library, selection: selection).environment(\.locale, locale))
                let size = page != "settings" ? NSSize(width: 840, height: 600) : NSSize(width: 880, height: 680)
                let host = NSHostingView(rootView: root)
                let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.contentView = host
                window.orderFront(nil)
                RunLoop.current.run(until: Date().addingTimeInterval(0.12))
                host.layoutSubtreeIfNeeded()
                guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw CocoaError(.fileWriteUnknown) }
                host.cacheDisplay(in: host.bounds, to: bitmap)
                guard let png = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
                try png.write(to: directory.appendingPathComponent("\(page)-\(language.rawValue).png"))
                window.close()
            }
        }
        print("Rendered all four onboarding steps and language settings in all 11 languages.")
    }

}
