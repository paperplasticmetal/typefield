import Foundation
import AppKit
import CoreText
import CryptoKit

struct ProState: Codable {
    var familyOverrides: [String: String] = [:]
    var mainPreviews: [String: String] = [:]
    var tags: [String: Set<String>] = [:] // PostScript names remain stable across regrouping.
    var axes: [String: [Int: Double]] = [:]
    var features: [String: [String: Int]] = [:]
    var notes: [String: String] = [:]
}
struct FontFacts {
    let weight: Int
    let italic: Bool
    let glyphCount: Int
    let foundry: String
    let features: [String]
    let widthClass: Int
    let xHeightRatio: Double
    let capHeightRatio: Double
    let ascenderRatio: Double
    let descenderRatio: Double
    let averageAdvanceRatio: Double
    let panose: [UInt8]
    let variable: Bool
    let color: Bool
    let bitmap: Bool
    let monospace: Bool
    /// PANOSE contrast is meaningful here only for Latin text families.
    var panoseContrast: Int? {
        guard panose.count == 10, panose[0] == 2, panose[4] >= 2 else { return nil }
        return Int(panose[4])
    }
    var panoseIndicatesHighContrast: Bool { (panoseContrast ?? 0) >= 8 }
    static func read(_ font: CTFont) -> FontFacts {
        var weight = 400
        let table = CTFontCopyTable(font, 0x4f532f32, []) as Data?
        if let table, table.count > 5 { let value = Int(table[4]) * 256 + Int(table[5]); weight = (1...1000).contains(value) ? value : 400 }
        let width = table.flatMap { OpenType.u16($0, 6) } ?? 5
        let panose = table.map { $0.count >= 42 ? Array($0[32..<42]) : [] } ?? []
        let size = max(1, Double(CTFontGetSize(font)))
        let sample = Array("HOnoxam0123".utf16)
        var glyphs = [CGGlyph](repeating: 0, count: sample.count)
        var advances = [CGSize](repeating: .zero, count: sample.count)
        let mapped = CTFontGetGlyphsForCharacters(font, sample, &glyphs, sample.count) && !glyphs.contains(0)
        if mapped { CTFontGetAdvancesForGlyphs(font, .horizontal, glyphs, &advances, glyphs.count) }
        let averageAdvance = mapped ? advances.reduce(0) { $0 + Double($1.width) } / Double(max(1, advances.count)) / size : 0
        // Core Text stores raw table tags in this CFArray, not Objective-C objects.
        var tables = Set<UInt32>()
        if let available = CTFontCopyAvailableTables(font, []) {
            for index in 0..<CFArrayGetCount(available) { tables.insert(UInt32(truncatingIfNeeded: UInt(bitPattern: CFArrayGetValueAtIndex(available, index)))) }
        }
        return FontFacts(weight: weight, italic: CTFontGetSymbolicTraits(font).contains(.traitItalic), glyphCount: CTFontGetGlyphCount(font), foundry: CTFontCopyName(font, kCTFontManufacturerNameKey) as String? ?? "", features: OpenType.tags(font), widthClass: width, xHeightRatio: Double(CTFontGetXHeight(font)) / size, capHeightRatio: Double(CTFontGetCapHeight(font)) / size, ascenderRatio: Double(CTFontGetAscent(font)) / size, descenderRatio: abs(Double(CTFontGetDescent(font))) / size, averageAdvanceRatio: averageAdvance, panose: panose, variable: !(CTFontCopyVariationAxes(font) as? [Any] ?? []).isEmpty, color: !tables.isDisjoint(with: [0x434F4C52, 0x43424454, 0x73626978, 0x53564720]), bitmap: !tables.isDisjoint(with: [0x45424454, 0x43424454, 0x73626978]), monospace: CTFontGetSymbolicTraits(font).contains(.traitMonoSpace))
    }
}
enum OpenType {
    private final class CachedFont: NSObject {
        let value: CTFont
        init(_ value: CTFont) { self.value = value }
    }
    private static let fontCache: NSCache<NSString, CachedFont> = {
        let cache = NSCache<NSString, CachedFont>()
        cache.countLimit = 384
        return cache
    }()
    static func u16(_ data: Data, _ offset: Int) -> Int? {
        guard offset >= 0, offset + 1 < data.count else { return nil }
        return Int(data[offset]) << 8 | Int(data[offset + 1])
    }
    static func tags(in data: Data) -> [String] {
        guard let offset = u16(data, 6), let count = u16(data, offset), count <= (data.count - offset - 2) / 6 else { return [] }
        return (0..<count).compactMap { index in
            let start = offset + 2 + index * 6
            return String(data: data.subdata(in: start..<start+4), encoding: .ascii)
        }
    }
    static func tags(_ font: CTFont) -> [String] {
        var result = Set<String>()
        for table: UInt32 in [0x47535542, 0x47504f53] { // GSUB and GPOS use the same FeatureList header.
            if let data = CTFontCopyTable(font, table, []) as Data? { result.formUnion(tags(in: data)) }
        }
        return result.sorted()
    }
    static let names = ["liga":"Standard ligatures", "dlig":"Discretionary ligatures", "hlig":"Historical ligatures", "calt":"Contextual alternates", "salt":"Stylistic alternates", "smcp":"Small capitals", "c2sc":"Capitals to small capitals", "onum":"Oldstyle figures", "lnum":"Lining figures", "tnum":"Tabular figures", "pnum":"Proportional figures", "frac":"Fractions", "ordn":"Ordinals", "zero":"Slashed zero", "swsh":"Swashes", "kern":"Kerning", "locl":"Localized forms", "case":"Case-sensitive forms", "sups":"Superscript", "subs":"Subscript", "rvrn":"Required variation alternates", "rlig":"Required ligatures", "ccmp":"Glyph composition", "mark":"Mark positioning", "mkmk":"Mark-to-mark positioning", "vert":"Vertical forms", "vkrn":"Vertical kerning"]
    static func label(_ tag: String) -> String { names[tag] ?? (tag.hasPrefix("ss") ? "Stylistic set \(tag.suffix(2))" : tag.hasPrefix("cv") ? "Character variant \(tag.suffix(2))" : "Font-defined feature") }
    static func clearFontCache() {
        fontCache.removeAllObjects()
        PreviewTextMetrics.clearCache()
    }
    static func font(name: String, size: Double, axes: [Int: Double] = [:], features: [String: Int] = [:]) -> CTFont {
        let axisKey = axes.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value.bitPattern)" }.joined(separator: ",")
        let featureKey = features.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ",")
        let key = "\(name)|\(size.bitPattern)|\(axisKey)|\(featureKey)" as NSString
        if let cached = fontCache.object(forKey: key) { return cached.value }
        let base = CTFontCreateWithName(name as CFString, size, nil)
        var attributes: [CFString: Any] = [:]
        if !axes.isEmpty { attributes[kCTFontVariationAttribute] = axes }
        if !features.isEmpty { attributes[kCTFontFeatureSettingsAttribute] = features.map { [kCTFontOpenTypeFeatureTag: $0.key, kCTFontOpenTypeFeatureValue: $0.value] as [CFString: Any] } }
        let font = CTFontCreateCopyWithAttributes(base, size, nil, CTFontDescriptorCreateWithAttributes(attributes as CFDictionary))
        fontCache.setObject(CachedFont(font), forKey: key)
        return font
    }
}
struct AdvancedFilter: Codable, Equatable {
    var foundry = ""
    var feature = ""
    var format = "Any"
    var slant = "Any"
    var minimumWeight = 1.0
    var maximumWeight = 1000.0
    var minimumGlyphs = 0
    var tag = ""
    var activation = "Any"
    var active: Bool { self != AdvancedFilter() }
    func matches(_ face: Face, tags: Set<String>) -> Bool {
        let f = face.facts
        return (foundry.isEmpty || f.foundry.localizedCaseInsensitiveContains(foundry)) &&
            (feature.isEmpty || f.features.contains(feature.trimmingCharacters(in: .whitespaces).lowercased())) &&
            (format == "Any" || face.url?.pathExtension.lowercased() == format.lowercased()) &&
            (slant == "Any" || (slant == "Italic" ? f.italic : !f.italic)) &&
            Double(f.weight) >= minimumWeight && Double(f.weight) <= maximumWeight &&
            f.glyphCount >= minimumGlyphs && (tag.isEmpty || tags.contains(tag)) &&
            (activation == "Any" || (activation == "Temporary" ? face.url.map { ActivationManager.shared.owns($0) } ?? false : face.url.map { CTFontManagerGetScopeForURL($0 as CFURL) == .process } ?? false))
    }
}
struct ActivationRecord: Codable { let path: String; let restoreProcess: Bool }
final class ActivationManager: ObservableObject {
    static let shared = ActivationManager()
    @Published private(set) var records: [ActivationRecord] = []
    let journal: URL
    private var journalUnreadable = false
    init(journal: URL? = nil) {
        self.journal = journal ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("FontShelf/temporary-activations.json")
        if FileManager.default.fileExists(atPath: self.journal.path) {
            do { records = try JSONDecoder().decode([ActivationRecord].self, from: Data(contentsOf: self.journal)) }
            catch { journalUnreadable = true }
        }
    }
    func owns(_ url: URL) -> Bool { records.contains { $0.path == url.path } }
    private func persist() throws {
        try FileManager.default.createDirectory(at: journal.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(records).write(to: journal, options: .atomic)
    }
    func activate(_ url: URL) throws -> String {
        guard !journalUnreadable else { throw NSError(domain: "FontShelf", code: 8, userInfo: [NSLocalizedDescriptionKey: "Temporary activation history is unreadable. It was preserved. Log out to clear session fonts and restore the history from a backup."]) }
        if owns(url) { return "Already temporarily activated." }
        let scope = CTFontManagerGetScopeForURL(url as CFURL)
        guard !url.path.hasPrefix("/System/"), !url.path.hasPrefix("/Library/Apple/"), scope != .persistent, scope != .session else { return "Already available to other apps. No activation changed." }
        let restore = scope == .process
        if restore {
            var processError: Unmanaged<CFError>?
            let removedProcessScope = CTFontManagerUnregisterFontsForURL(url as CFURL, .process, &processError)
            let retainedProcessError = processError?.takeRetainedValue()
            if !removedProcessScope && CTFontManagerGetScopeForURL(url as CFURL) == .process {
                throw retainedProcessError ?? NSError(domain: "FontShelf", code: 10, userInfo: [NSLocalizedDescriptionKey: "The font is still registered for Typefield, so temporary activation was not started."])
            }
        }
        var error: Unmanaged<CFError>?
        guard CTFontManagerRegisterFontsForURL(url as CFURL, .session, &error) else {
            if restore { CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil) }
            throw error?.takeRetainedValue() as Error? ?? NSError(domain: "FontShelf", code: 1, userInfo: [NSLocalizedDescriptionKey: "macOS could not activate this file."])
        }
        records.append(ActivationRecord(path: url.path, restoreProcess: restore))
        do { try persist() } catch {
            let persistenceError = error
            var unregisterError: Unmanaged<CFError>?
            let removedSessionScope = CTFontManagerUnregisterFontsForURL(url as CFURL, .session, &unregisterError)
            let retainedUnregisterError = unregisterError?.takeRetainedValue()
            let confirmedNotRegistered = retainedUnregisterError.map {
                CFEqual(CFErrorGetDomain($0), kCTFontManagerErrorDomain) && CFErrorGetCode($0) == CTFontManagerError.notRegistered.rawValue
            } ?? false
            if (!removedSessionScope && !confirmedNotRegistered) || CTFontManagerGetScopeForURL(url as CFURL) == .session {
                // Keep the in-memory owner and try again so termination cleanup can retry.
                try? persist()
                throw NSError(domain: "FontShelf", code: 13, userInfo: [NSLocalizedDescriptionKey: "The activation history could not be saved, and macOS did not confirm removal of the session font. Its activation record was retained for cleanup.", NSUnderlyingErrorKey: (retainedUnregisterError as Error?) ?? persistenceError])
            }
            records.removeAll { $0.path == url.path }
            if restore { CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil) }
            throw persistenceError
        }
        return "Temporarily available to other apps until Typefield quits or you log out."
    }
    func deactivate(_ url: URL, restore: Bool = true) throws {
        guard let record = records.first(where: { $0.path == url.path }) else { return }
        var error: Unmanaged<CFError>?
        let removedSessionScope = CTFontManagerUnregisterFontsForURL(url as CFURL, .session, &error)
        let unregisterError = error?.takeRetainedValue()
        let confirmedNotRegistered = unregisterError.map {
            CFEqual(CFErrorGetDomain($0), kCTFontManagerErrorDomain) && CFErrorGetCode($0) == CTFontManagerError.notRegistered.rawValue
        } ?? false
        if !removedSessionScope && !confirmedNotRegistered {
            throw unregisterError as Error? ?? NSError(domain: "FontShelf", code: 11, userInfo: [NSLocalizedDescriptionKey: "macOS could not confirm removal of the session registration. Its activation record was kept so it can be retried."])
        }
        if CTFontManagerGetScopeForURL(url as CFURL) == .session {
            throw NSError(domain: "FontShelf", code: 12, userInfo: [NSLocalizedDescriptionKey: "macOS still reports this font as active for the session. Its activation record was kept so it can be retried."])
        }
        let previous = records
        records.removeAll { $0.path == url.path }
        defer { if restore && record.restoreProcess { CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil) } }
        do { try persist() } catch { records = previous; throw error }
    }
    @discardableResult func clear(restore: Bool = true) -> [String] {
        if journalUnreadable { return ["Temporary activation history is unreadable and was preserved. Log out to clear session fonts, then restore the history from a backup."] }
        var errors: [String] = []
        for record in records { do { try deactivate(URL(fileURLWithPath: record.path), restore: restore) } catch { errors.append(error.localizedDescription) } }
        return errors
    }
}
struct DuplicateGroup: Identifiable {
    let id: String
    let title: String
    let paths: [String]
    let exact: Bool
}
enum DuplicateFinder {
    static let extensions: Set<String> = ["ttf", "otf", "ttc", "otc", "dfont", "woff", "woff2"]
    static func hash(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        var hash = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty { hash.update(data: data) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
    static func scan(urls: [URL], folders: [String]) -> (groups: [DuplicateGroup], errors: [String]) {
        var all = Set(urls.map { $0.resolvingSymlinksInPath() })
        var errors: [String] = []
        for folder in folders {
            guard let items = FileManager.default.enumerator(at: URL(fileURLWithPath: folder), includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { url, error in errors.append(url.path + ": " + error.localizedDescription); return true }) else { errors.append("Cannot scan \(folder)"); continue }
            for case let url as URL in items where extensions.contains(url.pathExtension.lowercased()) { all.insert(url.resolvingSymlinksInPath()) }
        }
        var names: [String: Set<String>] = [:], sizes: [Int: [URL]] = [:]
        for url in all {
            do { let count = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0; sizes[count, default: []].append(url) }
            catch { errors.append(url.path + ": " + error.localizedDescription); continue }
            for descriptor in CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor] ?? [] {
                if let name = CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute) as? String { names[name, default: []].insert(url.path) }
            }
        }
        var hashes: [String: [String]] = [:]
        for candidates in sizes.values where candidates.count > 1 {
            for url in candidates { do { hashes[try hash(url), default: []].append(url.path) } catch { errors.append(url.path + ": " + error.localizedDescription) } }
        }
        var groups = hashes.filter { $0.value.count > 1 }.map { DuplicateGroup(id: $0.key, title: "\($0.value.count) identical file copies", paths: $0.value.sorted(), exact: true) }
        groups += names.filter { $0.value.count > 1 }.map { DuplicateGroup(id: "name:" + $0.key, title: $0.key, paths: $0.value.sorted(), exact: false) }
        return (groups.sorted { $0.title < $1.title }, errors)
    }
}
enum FontExporter {
    static func copy(faces: [Face], to destination: URL) -> (copied: [String], errors: [String]) {
        var copied: [String] = [], errors: [String] = []
        let urls = Set(faces.compactMap(\.url)).sorted { $0.path < $1.path }
        for url in urls {
            var target = destination.appendingPathComponent(url.lastPathComponent)
            var suffix = 2
            while FileManager.default.fileExists(atPath: target.path) { target = destination.appendingPathComponent(url.deletingPathExtension().lastPathComponent + "-\(suffix)." + url.pathExtension); suffix += 1 }
            do { try FileManager.default.copyItem(at: url, to: target); copied.append(target.lastPathComponent) }
            catch { errors.append("\(url.lastPathComponent): \(error.localizedDescription)") }
        }
        if faces.contains(where: { $0.url == nil }) { errors.append("Some font styles have no accessible source file.") }
        return (copied, errors)
    }
    static func export(_ faces: [Face]) -> String? {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
        panel.message = "Choose an export destination. Original font files are copied; collection files can contain additional styles."
        guard panel.runModal() == .OK, let base = panel.url else { return nil }
        let folder = base.appendingPathComponent("Typefield Export " + ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-") + "-" + String(UUID().uuidString.prefix(4)))
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let result = copy(faces: faces, to: folder)
            let manifest: [String: Any] = ["files": result.copied, "errors": result.errors, "styles": faces.map { ["postscriptName": $0.name, "family": $0.originalFamily, "style": $0.style] }]
            try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys]).write(to: folder.appendingPathComponent("manifest.json"), options: .atomic)
            NSWorkspace.shared.activateFileViewerSelecting([folder])
            return "Exported \(result.copied.count) files." + (result.errors.isEmpty ? "" : "\n" + result.errors.joined(separator: "\n"))
        } catch { return "Export failed: " + error.localizedDescription }
    }
}
extension NSColor {
    convenience init(hex: String) {
        let value = UInt64(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0
        self.init(srgbRed: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255, alpha: 1)
    }
    var rgbHex: String {
        let c = usingColorSpace(.sRGB) ?? self
        let channels = [c.redComponent, c.greenComponent, c.blueComponent]
            .map { min(255, max(0, Int(($0 * 255).rounded()))) }
        return String(format: "%02X%02X%02X", channels[0], channels[1], channels[2])
    }
}
