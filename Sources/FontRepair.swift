import SwiftUI
import AppKit
import CoreText
import UniformTypeIdentifiers

enum FontHealthSeverity: Int, Comparable {
    case info, warning, error
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    var icon: String { self == .error ? "xmark.octagon.fill" : self == .warning ? "exclamationmark.triangle.fill" : "info.circle.fill" }
    var color: Color { self == .error ? .red : self == .warning ? .orange : .secondary }
}

enum FontRepairAction: String, CaseIterable, Identifiable, Hashable {
    case removeInvalidNames, removeDuplicateNames, normalizeLegacySubfamily, normalizeVersion, rebuildChecksums, removeDigitalSignature
    var id: String { rawValue }
    var title: String {
        switch self {
        case .removeInvalidNames: return "Remove empty or invalid name records"
        case .removeDuplicateNames: return "Remove exact duplicate name records"
        case .normalizeLegacySubfamily: return "Normalize the legacy subfamily"
        case .normalizeVersion: return "Normalize the version name"
        case .rebuildChecksums: return "Rebuild table checksums"
        case .removeDigitalSignature: return "Remove the invalidated digital signature"
        }
    }
    var explanation: String {
        switch self {
        case .removeInvalidNames: return "Drops only records with no usable text or storage outside the name table. Other naming and license records stay intact."
        case .removeDuplicateNames: return "Keeps the first byte-identical record for each platform, language and name ID. Conflicting records are left for manual review."
        case .normalizeLegacySubfamily: return "Uses Regular, Italic, Bold or Bold Italic for legacy name ID 2 while preserving the descriptive style in typographic name ID 17."
        case .normalizeVersion: return "Formats name ID 5 as “Version 1.000” using the number already present in the font."
        case .rebuildChecksums: return "Recalculates the SFNT directory, table checksums and head checksum adjustment without changing outlines."
        case .removeDigitalSignature: return "A binary repair invalidates the DSIG table, so the stale signature is removed from the repaired copy."
        }
    }
}

struct FontHealthIssue: Identifiable, Hashable {
    let id: String
    let severity: FontHealthSeverity
    let title: String
    let detail: String
    let fix: FontRepairAction?
    init(_ severity: FontHealthSeverity, _ title: String, _ detail: String, fix: FontRepairAction? = nil) {
        self.severity = severity; self.title = title; self.detail = detail; self.fix = fix; id = title + "|" + detail
    }
}

struct FontNameSnapshot {
    var family = "—", subfamily = "—", full = "—", postScript = "—", version = "—"
}

struct FontInspection: Identifiable {
    var id: String { url.path }
    let url: URL
    let format: String
    let byteCount: Int
    let names: FontNameSnapshot
    let issues: [FontHealthIssue]
    let canRepair: Bool
    var recommendedFixes: Set<FontRepairAction> { Set(issues.compactMap(\.fix)) }
    var worst: FontHealthSeverity { issues.map(\.severity).max() ?? .info }
    var needsReview: Bool { issues.contains { $0.severity >= .warning } }
}

enum FontRepairError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case .invalid(let message) = self { return message }; return nil }
}

enum FontRepairEngine {
    struct Table { let tag: String; let storedChecksum: UInt32; let offset: Int; let length: Int; let data: Data }
    struct NameRecord: Hashable {
        let platform: UInt16, encoding: UInt16, language: UInt16, nameID: UInt16
        var raw: Data
        var text: String? { FontRepairEngine.decode(raw, platform: platform) }
        var identity: String { "\(platform)|\(encoding)|\(language)|\(nameID)" }
    }
    struct Parsed {
        let scaler: UInt32
        let tables: [Table]
        let nameFormat: UInt16?
        let names: [NameRecord]
        let invalidNameRecords: Bool
        let expectedLegacySubfamily: String
    }

    static func isUserFont(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        let userFonts = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Fonts").standardizedFileURL.path + "/"
        return path.hasPrefix(userFonts) || path.hasPrefix("/Library/Fonts/")
    }

    static func inspect(_ url: URL) -> FontInspection {
        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values.isRegularFile == true else { throw FontRepairError.invalid("This is not a regular font file.") }
            guard (values.fileSize ?? 0) <= 256_000_000 else { throw FontRepairError.invalid("The file is larger than the 256 MB inspection limit.") }
            return inspect(data: try Data(contentsOf: url, options: .mappedIfSafe), url: url)
        } catch {
            return FontInspection(url: url, format: url.pathExtension.uppercased(), byteCount: 0, names: FontNameSnapshot(), issues: [FontHealthIssue(.error, "Could not read font", error.localizedDescription)], canRepair: false)
        }
    }

    static func inspect(data: Data, url: URL) -> FontInspection {
        var issues: [FontHealthIssue] = []
        guard let parsed = parse(data, issues: &issues) else {
            return FontInspection(url: url, format: formatName(data), byteCount: data.count, names: FontNameSnapshot(), issues: issues, canRepair: false)
        }
        let snapshot = nameSnapshot(parsed.names)
        if parsed.tables.contains(where: { $0.tag == "DSIG" }), let repairSeverity = issues.filter({ $0.fix != nil }).map(\.severity).max() {
            issues.append(FontHealthIssue(repairSeverity >= .warning ? .warning : .info, "Repair invalidates the digital signature", "The existing DSIG cannot describe a modified binary and must be removed from the repaired copy.", fix: .removeDigitalSignature))
        }
        let format = formatName(data)
        let canRepair = parsed.nameFormat == 0 && !issues.contains { $0.severity == .error && $0.fix == nil }
        return FontInspection(url: url, format: format, byteCount: data.count, names: snapshot, issues: issues, canRepair: canRepair)
    }

    static func parse(_ data: Data, issues: inout [FontHealthIssue]) -> Parsed? {
        guard data.count >= 12, let scaler = data.fsUInt32(0) else { issues.append(FontHealthIssue(.error, "Truncated font header", "The file does not contain a complete SFNT header.")); return nil }
        if scaler == 0x74746366 { issues.append(FontHealthIssue(.info, "Font collection is read-only", "TTC and OTC collections can be inspected by Core Text, but Typefield does not rewrite a shared multi-font container.")); return nil }
        guard [0x00010000, 0x4F54544F, 0x74727565, 0x74797031].contains(scaler) else { issues.append(FontHealthIssue(.error, "Unsupported font container", "Repair currently supports individual TrueType and OpenType SFNT files, not WOFF, WOFF2, dfont or unknown containers.")); return nil }
        guard let countValue = data.fsUInt16(4) else { return nil }
        let count = Int(countValue), directoryEnd = 12 + count * 16
        guard count > 0, count <= 4096, directoryEnd <= data.count else { issues.append(FontHealthIssue(.error, "Invalid table directory", "The declared table count extends outside the file.")); return nil }
        var tables: [Table] = [], tags = Set<String>(), ranges: [(String, Range<Int>)] = []
        for index in 0..<count {
            let base = 12 + index * 16
            guard let tag = data.fsTag(base), let checksum = data.fsUInt32(base + 4), let offsetValue = data.fsUInt32(base + 8), let lengthValue = data.fsUInt32(base + 12) else { return nil }
            let offset = Int(offsetValue), length = Int(lengthValue)
            guard offset >= directoryEnd, length >= 0, offset <= data.count, length <= data.count - offset else { issues.append(FontHealthIssue(.error, "Table outside file", "The \(tag) table points beyond the available font data.")); return nil }
            if !tags.insert(tag).inserted { issues.append(FontHealthIssue(.error, "Duplicate table tag", "The table directory contains more than one \(tag) entry.")) }
            let tableData = data.subdata(in: offset..<(offset + length))
            tables.append(Table(tag: tag, storedChecksum: checksum, offset: offset, length: length, data: tableData)); ranges.append((tag, offset..<(offset + length)))
            let calculated = checksumForTable(tag, tableData)
            if calculated != checksum { issues.append(FontHealthIssue(.warning, "Incorrect \(tag) checksum", "Stored 0x\(hex(checksum)); calculated 0x\(hex(calculated)).", fix: .rebuildChecksums)) }
        }
        let sortedRanges = ranges.sorted { $0.1.lowerBound < $1.1.lowerBound }
        for pair in zip(sortedRanges, sortedRanges.dropFirst()) where pair.0.1.upperBound > pair.1.1.lowerBound {
            issues.append(FontHealthIssue(.error, "Overlapping tables", "The \(pair.0.0) and \(pair.1.0) tables occupy overlapping bytes."))
        }
        for required in ["head", "name", "cmap", "maxp"] where !tags.contains(required) { issues.append(FontHealthIssue(.error, "Missing \(required) table", "This required OpenType table is absent.")) }
        var nameFormat: UInt16?, nameRecords: [NameRecord] = [], invalidNames = false
        if let table = tables.first(where: { $0.tag == "name" }) {
            let result = parseName(table.data, issues: &issues)
            nameFormat = result.format; nameRecords = result.records; invalidNames = result.invalid
        }
        let expected = expectedSubfamily(tables)
        validateNames(nameRecords, format: nameFormat, expectedSubfamily: expected, issues: &issues)
        return Parsed(scaler: scaler, tables: tables, nameFormat: nameFormat, names: nameRecords, invalidNameRecords: invalidNames, expectedLegacySubfamily: expected)
    }

    static func parseName(_ data: Data, issues: inout [FontHealthIssue]) -> (format: UInt16?, records: [NameRecord], invalid: Bool) {
        guard data.count >= 6, let format = data.fsUInt16(0), let countValue = data.fsUInt16(2), let stringsValue = data.fsUInt16(4) else { issues.append(FontHealthIssue(.error, "Truncated name table", "The name table header is incomplete.")); return (nil, [], true) }
        let count = Int(countValue), strings = Int(stringsValue), recordsEnd = 6 + count * 12
        guard count <= 32768, recordsEnd <= data.count, strings >= recordsEnd, strings <= data.count else { issues.append(FontHealthIssue(.error, "Invalid name table layout", "Name records or string storage point outside the table.")); return (format, [], true) }
        if format > 1 { issues.append(FontHealthIssue(.warning, "Unknown name table format", "Format \(format) can be inspected conservatively but is not rewritten.")) }
        if format == 1 { issues.append(FontHealthIssue(.info, "Language-tagged name table", "Format 1 language tags are preserved read-only; export repair is disabled for this font.")) }
        var records: [NameRecord] = [], invalid = false
        for index in 0..<count {
            let base = 6 + index * 12
            guard let platform = data.fsUInt16(base), let encoding = data.fsUInt16(base + 2), let language = data.fsUInt16(base + 4), let nameID = data.fsUInt16(base + 6), let lengthValue = data.fsUInt16(base + 8), let offsetValue = data.fsUInt16(base + 10) else { invalid = true; continue }
            let start = strings + Int(offsetValue), length = Int(lengthValue)
            guard start >= strings, start <= data.count, length <= data.count - start else { invalid = true; continue }
            records.append(NameRecord(platform: platform, encoding: encoding, language: language, nameID: nameID, raw: data.subdata(in: start..<(start + length))))
        }
        if invalid { issues.append(FontHealthIssue(.error, "Invalid name record storage", "One or more name records point outside the string storage and can be removed during repair.", fix: .removeInvalidNames)) }
        return (format, records, invalid)
    }

    static func validateNames(_ records: [NameRecord], format: UInt16?, expectedSubfamily: String, issues: inout [FontHealthIssue]) {
        guard format != nil else { return }
        let empty = records.filter { $0.raw.isEmpty || ($0.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? false) }
        if !empty.isEmpty { issues.append(FontHealthIssue(.error, "Empty name records", "\(empty.count) name \(empty.count == 1 ? "record has" : "records have") no usable text. Empty strings commonly break validators and installers.", fix: .removeInvalidNames)) }
        var seen: [String: Set<Data>] = [:], exactDuplicates = 0, conflicts = 0
        for record in records { if seen[record.identity, default: []].contains(record.raw) { exactDuplicates += 1 }; seen[record.identity, default: []].insert(record.raw) }
        for values in seen.values where values.count > 1 { conflicts += 1 }
        if exactDuplicates > 0 { issues.append(FontHealthIssue(.warning, "Duplicate name records", "\(exactDuplicates) byte-identical duplicate \(exactDuplicates == 1 ? "record" : "records") can be removed safely.", fix: .removeDuplicateNames)) }
        if conflicts > 0 { issues.append(FontHealthIssue(.warning, "Conflicting localized names", "\(conflicts) platform/language/name ID \(conflicts == 1 ? "combination contains" : "combinations contain") different strings. Review these manually; Typefield will not guess which one is correct.")) }
        let present = Set(records.filter { !($0.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) }.map(\.nameID))
        for required: UInt16 in [1, 2, 4, 6] where !present.contains(required) { issues.append(FontHealthIssue(.error, "Missing name ID \(required)", "A required family, subfamily, full-name or PostScript-name record is absent. Typefield will not invent identity data.")) }
        if records.contains(where: { $0.nameID == 17 && !($0.text?.isEmpty ?? true) }) {
            let legacy = Set(records.filter { $0.nameID == 2 }.compactMap(\.text))
            let allowed = Set(["Regular", "Italic", "Bold", "Bold Italic"])
            if legacy.contains(where: { !allowed.contains($0) }) { issues.append(FontHealthIssue(.info, "Optional legacy subfamily compatibility", "Name ID 2 can be normalized to \(expectedSubfamily) for older RIBBI-only software. The descriptive style remains in name ID 17; this is not corruption by itself.", fix: .normalizeLegacySubfamily)) }
        }
        let versions = records.filter { $0.nameID == 5 }.compactMap(\.text)
        if versions.contains(where: { !$0.hasPrefix("Version ") }) { issues.append(FontHealthIssue(.info, "Optional version-name normalization", "Name ID 5 can be normalized to begin with “Version ” followed by a numeric version. This is not corruption by itself.", fix: .normalizeVersion)) }
        for postScript in records.filter({ $0.nameID == 6 }).compactMap(\.text) {
            let forbidden = CharacterSet(charactersIn: " [](){}<>/%")
            if postScript.unicodeScalars.contains(where: { $0.value < 33 || $0.value > 126 || forbidden.contains($0) }) { issues.append(FontHealthIssue(.error, "Invalid PostScript name", "“\(postScript)” contains a forbidden character. Changing font identity is not automated; edit this record in a dedicated font editor.")) }
        }
    }

    static func repairedData(for url: URL, actions: Set<FontRepairAction>, validateWithCoreText: Bool = true) throws -> Data {
        guard !actions.isEmpty else { throw FontRepairError.invalid("Select at least one proposed fix.") }
        let source = try Data(contentsOf: url, options: .mappedIfSafe)
        var issues: [FontHealthIssue] = []
        guard let parsed = parse(source, issues: &issues) else { throw FontRepairError.invalid("This font cannot be rebuilt safely.") }
        guard parsed.nameFormat == 0 else { throw FontRepairError.invalid("Only format 0 name tables can currently be rebuilt. No file was changed.") }
        if parsed.invalidNameRecords && !actions.contains(.removeInvalidNames) { throw FontRepairError.invalid("Select the invalid-name-record repair before rebuilding this name table.") }
        if parsed.tables.contains(where: { $0.tag == "DSIG" }) && !actions.contains(.removeDigitalSignature) { throw FontRepairError.invalid("Select removal of the invalidated digital signature before repairing this signed font.") }
        let nameActions: Set<FontRepairAction> = [.removeInvalidNames, .removeDuplicateNames, .normalizeLegacySubfamily, .normalizeVersion]
        var tableValues = parsed.tables.filter { $0.tag != "DSIG" || !actions.contains(.removeDigitalSignature) }.map { ($0.tag, $0.data) }
        if !actions.isDisjoint(with: nameActions) {
            var records = parsed.names
            if actions.contains(.removeInvalidNames) { records.removeAll { $0.raw.isEmpty || ($0.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? false) } }
            if actions.contains(.removeDuplicateNames) {
                var seen = Set<String>(); records = records.filter { seen.insert($0.identity + "|" + $0.raw.base64EncodedString()).inserted }
            }
            if actions.contains(.normalizeLegacySubfamily) { records = records.map { record in var value = record; if value.nameID == 2, let encoded = encode(parsed.expectedLegacySubfamily, platform: value.platform) { value.raw = encoded }; return value } }
            if actions.contains(.normalizeVersion) { records = records.map { record in var value = record; if value.nameID == 5, let encoded = encode(normalizedVersion(value.text ?? ""), platform: value.platform) { value.raw = encoded }; return value } }
            let nameSize = 6 + records.count * 12 + records.reduce(0) { $0 + $1.raw.count }
            guard records.count <= Int(UInt16.max), nameSize <= Int(UInt16.max), records.allSatisfy({ $0.raw.count <= Int(UInt16.max) }) else { throw FontRepairError.invalid("The repaired name table would exceed the format 0 size limit. No file was changed.") }
            let rebuiltName = buildName(records)
            guard let index = tableValues.firstIndex(where: { $0.0 == "name" }) else { throw FontRepairError.invalid("The font has no name table to repair.") }
            tableValues[index].1 = rebuiltName
        }
        let output = buildSFNT(scaler: parsed.scaler, tables: tableValues)
        var outputIssues: [FontHealthIssue] = []
        guard parse(output, issues: &outputIssues) != nil else { throw FontRepairError.invalid("The repaired copy failed Typefield's structural validation.") }
        if validateWithCoreText {
            let descriptors = CTFontManagerCreateFontDescriptorsFromData(output as CFData) as? [CTFontDescriptor] ?? []
            guard !descriptors.isEmpty else { throw FontRepairError.invalid("Core Text rejected the repaired copy. No file was written.") }
        }
        return output
    }

    static func buildName(_ records: [NameRecord]) -> Data {
        let headerSize = 6 + records.count * 12
        var output = Data(); output.fsAppendUInt16(0); output.fsAppendUInt16(UInt16(records.count)); output.fsAppendUInt16(UInt16(headerSize))
        var strings = Data(), offsets: [Int] = []
        for record in records { offsets.append(strings.count); strings.append(record.raw) }
        for (index, record) in records.enumerated() {
            output.fsAppendUInt16(record.platform); output.fsAppendUInt16(record.encoding); output.fsAppendUInt16(record.language); output.fsAppendUInt16(record.nameID)
            output.fsAppendUInt16(UInt16(record.raw.count)); output.fsAppendUInt16(UInt16(offsets[index]))
        }
        output.append(strings); return output
    }

    static func buildSFNT(scaler: UInt32, tables: [(String, Data)]) -> Data {
        let clean = tables.filter { $0.0.utf8.count == 4 }
        let count = clean.count, maxPower = count > 0 ? 1 << Int(floor(log2(Double(count)))) : 0
        let searchRange = maxPower * 16, entrySelector = maxPower > 0 ? Int(log2(Double(maxPower))) : 0, rangeShift = count * 16 - searchRange
        struct Prepared { let tag: String; let data: Data; let checksum: UInt32; let offset: Int }
        var cursor = 12 + count * 16, prepared: [Prepared] = []
        for (tag, original) in clean {
            cursor = (cursor + 3) & ~3
            var value = original
            if tag == "head", value.count >= 12 { value.fsSetUInt32(8, 0) }
            prepared.append(Prepared(tag: tag, data: value, checksum: checksumForTable(tag, value), offset: cursor)); cursor += (value.count + 3) & ~3
        }
        var output = Data(); output.fsAppendUInt32(scaler); output.fsAppendUInt16(UInt16(count)); output.fsAppendUInt16(UInt16(searchRange)); output.fsAppendUInt16(UInt16(entrySelector)); output.fsAppendUInt16(UInt16(rangeShift))
        for table in prepared { output.append(contentsOf: table.tag.utf8); output.fsAppendUInt32(table.checksum); output.fsAppendUInt32(UInt32(table.offset)); output.fsAppendUInt32(UInt32(table.data.count)) }
        for table in prepared { while output.count < table.offset { output.append(0) }; output.append(table.data); while output.count % 4 != 0 { output.append(0) } }
        if let head = prepared.first(where: { $0.tag == "head" }), head.data.count >= 12 {
            let adjustment = UInt32(truncatingIfNeeded: UInt64(0xB1B0AFBA) &- UInt64(checksum(output)))
            output.fsSetUInt32(head.offset + 8, adjustment)
        }
        return output
    }

    static func checksumForTable(_ tag: String, _ data: Data) -> UInt32 { var value = data; if tag == "head", value.count >= 12 { value.fsSetUInt32(8, 0) }; return checksum(value) }
    static func checksum(_ data: Data) -> UInt32 {
        var total: UInt32 = 0, index = 0
        while index < data.count { var word: UInt32 = 0; for byte in 0..<4 { word <<= 8; if index + byte < data.count { word |= UInt32(data[data.startIndex + index + byte]) } }; total = total &+ word; index += 4 }
        return total
    }
    static func formatName(_ data: Data) -> String { guard let signature = data.fsUInt32(0) else { return "Unknown" }; switch signature { case 0x00010000, 0x74727565: return "TrueType"; case 0x4F54544F: return "OpenType/CFF"; case 0x74746366: return "Font collection"; case 0x774F4646: return "WOFF"; case 0x774F4632: return "WOFF2"; default: return "Unknown" } }
    static func hex(_ value: UInt32) -> String { String(format: "%08X", value) }
    static func decode(_ data: Data, platform: UInt16) -> String? { platform == 0 || platform == 3 ? String(data: data, encoding: .utf16BigEndian) : platform == 1 ? String(data: data, encoding: .macOSRoman) : String(data: data, encoding: .utf8) }
    static func encode(_ string: String, platform: UInt16) -> Data? { string.data(using: platform == 0 || platform == 3 ? .utf16BigEndian : platform == 1 ? .macOSRoman : .utf8) }
    static func nameSnapshot(_ records: [NameRecord]) -> FontNameSnapshot {
        func preferred(_ id: UInt16) -> String {
            records.filter { $0.nameID == id }.sorted { score($0) > score($1) }.compactMap(\.text).first { !$0.isEmpty } ?? "—"
        }
        return FontNameSnapshot(family: preferred(1), subfamily: preferred(2), full: preferred(4), postScript: preferred(6), version: preferred(5))
    }
    static func score(_ record: NameRecord) -> Int { (record.platform == 3 ? 30 : record.platform == 0 ? 20 : 10) + (record.language == 0x0409 || record.language == 0 ? 5 : 0) }
    static func expectedSubfamily(_ tables: [Table]) -> String {
        let macStyle = tables.first(where: { $0.tag == "head" })?.data.fsUInt16(44) ?? 0
        let selection = tables.first(where: { $0.tag == "OS/2" })?.data.fsUInt16(62) ?? 0
        let bold = macStyle & 1 != 0 || selection & 0x20 != 0, italic = macStyle & 2 != 0 || selection & 1 != 0
        return bold && italic ? "Bold Italic" : bold ? "Bold" : italic ? "Italic" : "Regular"
    }
    static func normalizedVersion(_ value: String) -> String {
        let match = value.range(of: #"\d+(?:\.\d+)?"#, options: .regularExpression).map { String(value[$0]) }
        return "Version " + String(format: "%.3f", Double(match ?? "1") ?? 1)
    }
}

private extension Data {
    func fsUInt16(_ offset: Int) -> UInt16? { guard offset >= 0, offset + 2 <= count else { return nil }; return UInt16(self[startIndex + offset]) << 8 | UInt16(self[startIndex + offset + 1]) }
    func fsUInt32(_ offset: Int) -> UInt32? { guard let high = fsUInt16(offset), let low = fsUInt16(offset + 2) else { return nil }; return UInt32(high) << 16 | UInt32(low) }
    func fsTag(_ offset: Int) -> String? { guard offset >= 0, offset + 4 <= count else { return nil }; return String(bytes: self[(startIndex + offset)..<(startIndex + offset + 4)], encoding: .ascii) }
    mutating func fsAppendUInt16(_ value: UInt16) { append(UInt8(value >> 8)); append(UInt8(value & 0xFF)) }
    mutating func fsAppendUInt32(_ value: UInt32) { fsAppendUInt16(UInt16(value >> 16)); fsAppendUInt16(UInt16(value & 0xFFFF)) }
    mutating func fsSetUInt32(_ offset: Int, _ value: UInt32) { guard offset >= 0, offset + 4 <= count else { return }; self[startIndex + offset] = UInt8(value >> 24); self[startIndex + offset + 1] = UInt8((value >> 16) & 0xFF); self[startIndex + offset + 2] = UInt8((value >> 8) & 0xFF); self[startIndex + offset + 3] = UInt8(value & 0xFF) }
}

struct FontHealthView: View {
    @ObservedObject var library: Library
    @State private var inspections: [FontInspection] = []
    @State private var selectedPath: String?
    @State private var selectedFixes: Set<FontRepairAction> = []
    @State private var scanning = false
    @State private var userFontsOnly = true
    @State private var showClean = false
    @State private var query = ""
    @State private var status = "Choose Scan Library or inspect one font file."
    var visible: [FontInspection] {
        inspections.filter { item in
            (showClean || item.needsReview) && (query.isEmpty || item.url.lastPathComponent.localizedCaseInsensitiveContains(query) || item.names.family.localizedCaseInsensitiveContains(query) || item.names.postScript.localizedCaseInsensitiveContains(query))
        }
    }
    var selected: FontInspection? { inspections.first { $0.url.path == selectedPath } }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Font health & repair").font(.title2).fontWeight(.semibold)
                    Text("Inspect structure and naming, review each proposed fix, then export a repaired copy or repair a writable user font with a backup.").foregroundStyle(.secondary)
                }
                Spacer()
                if scanning { ProgressView().controlSize(.small) }
                Button("Scan Library") { scanLibrary() }.disabled(scanning)
                Button("Inspect file…") { inspectFile() }.disabled(scanning)
            }
            HStack {
                TextField("Search results", text: $query).textFieldStyle(.roundedBorder).frame(maxWidth: 320)
                Toggle("User fonts only", isOn: $userFontsOnly).toggleStyle(.checkbox)
                Toggle("Show clean files", isOn: $showClean).toggleStyle(.checkbox)
                Spacer()
                Text(summary).font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            HSplitView {
                ScrollView {
                    LazyVStack(spacing: 5) {
                        if visible.isEmpty { Text(scanning ? "Inspecting font files…" : inspections.isEmpty ? "No files inspected yet." : "No files match these filters.").foregroundStyle(.secondary).padding(30) }
                        ForEach(visible) { item in resultRow(item) }
                    }.padding(.trailing, 8)
                }.frame(minWidth: 260, idealWidth: 310, maxWidth: 380)
                Group {
                    if let item = selected { detail(item) }
                    else { VStack(spacing: 10) { Image(systemName: "stethoscope").font(.system(size: 34)).foregroundStyle(.secondary); Text("Select an inspected font").font(.headline); Text("Typefield does not modify files during inspection.").foregroundStyle(.secondary) }.frame(maxWidth: .infinity, maxHeight: .infinity) }
                }.frame(minWidth: 450, maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            HStack { Image(systemName: "lock.shield"); Text("Original files are never overwritten without a separate confirmation. In-place repair is unavailable for system fonts and read-only files."); Spacer(); Text(status).lineLimit(2) }.font(.caption).foregroundStyle(.secondary)
        }.padding(10).onAppear { consumeRequestedFile() }
    }
    var summary: String {
        let affected = inspections.filter(\.needsReview).count
        return inspections.isEmpty ? "" : "\(affected) need review · \(inspections.count) inspected"
    }
    func resultRow(_ item: FontInspection) -> some View {
        Button { select(item) } label: {
            HStack(spacing: 10) {
                Image(systemName: item.needsReview ? item.worst.icon : "checkmark.circle.fill").foregroundStyle(item.needsReview ? item.worst.color : Color.green)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.names.family == "—" ? item.url.deletingPathExtension().lastPathComponent : item.names.family).fontWeight(.medium).lineLimit(1)
                    Text(item.url.lastPathComponent + " · " + (item.needsReview ? "\(item.issues.filter { $0.severity >= .warning }.count) finding\(item.issues.filter { $0.severity >= .warning }.count == 1 ? "" : "s")" : item.issues.isEmpty ? "Clean" : "No problems · \(item.issues.count) compatibility note\(item.issues.count == 1 ? "" : "s")")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                if !item.canRepair && !item.issues.isEmpty { Image(systemName: "eye").help("Inspection only") }
            }.padding(9).frame(maxWidth: .infinity, alignment: .leading).background(selectedPath == item.url.path ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 7))
        }.buttonStyle(.plain)
    }
    func detail(_ item: FontInspection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) { Text(item.url.lastPathComponent).font(.headline); Text(item.format + " · " + ByteCountFormatter.string(fromByteCount: Int64(item.byteCount), countStyle: .file)).font(.caption).foregroundStyle(.secondary) }
                Spacer(); Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
            }
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 5) {
                nameRow("Family", item.names.family); nameRow("Subfamily", item.names.subfamily); nameRow("Full name", item.names.full); nameRow("PostScript", item.names.postScript); nameRow("Version", item.names.version)
            }.font(.caption)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if !item.needsReview { Label(item.issues.isEmpty ? "No structural or naming problems found by the current checks." : "No corruption found. Optional compatibility notes appear below.", systemImage: "checkmark.seal.fill").foregroundStyle(.green).padding(.vertical, 10) }
                    ForEach(item.issues) { issue in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: issue.severity.icon).foregroundStyle(issue.severity.color).frame(width: 18)
                            VStack(alignment: .leading, spacing: 3) { Text(issue.title).fontWeight(.medium); Text(issue.detail).font(.caption).foregroundStyle(.secondary) }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if !item.recommendedFixes.isEmpty {
                        Divider(); Text("PROPOSED FIXES").font(.caption).foregroundStyle(.secondary)
                        ForEach(FontRepairAction.allCases.filter { item.recommendedFixes.contains($0) }) { action in
                            Toggle(isOn: Binding(get: { selectedFixes.contains(action) }, set: { if $0 { selectedFixes.insert(action) } else { selectedFixes.remove(action) } })) {
                                VStack(alignment: .leading, spacing: 3) { Text(action.title); Text(action.explanation).font(.caption).foregroundStyle(.secondary) }
                            }.toggleStyle(.checkbox)
                        }
                    }
                }.padding(.trailing, 10)
            }
            HStack {
                Button("Export repaired copy…") { exportCopy(item) }.disabled(!item.canRepair || selectedFixes.isEmpty)
                Button("Repair original…") { repairOriginal(item) }.disabled(!canRepairOriginal(item) || selectedFixes.isEmpty)
                Spacer()
                if !item.canRepair && !item.issues.isEmpty { Text("Inspection only").font(.caption).foregroundStyle(.secondary) }
            }
        }.padding(.leading, 18)
    }
    func nameRow(_ label: String, _ value: String) -> some View { GridRow { Text(label).foregroundStyle(.secondary).frame(width: 70, alignment: .trailing); Text(value).textSelection(.enabled).lineLimit(1) } }
    func select(_ item: FontInspection) { selectedPath = item.url.path; selectedFixes = Set(item.issues.filter { $0.severity >= .warning }.compactMap(\.fix)) }
    func scanLibrary() {
        let watched = library.resolvedFolders + library.saved.folders
        let paths = Set(library.allFaces.compactMap(\.url).filter { url in !userFontsOnly || FontRepairEngine.isUserFont(url) || watched.contains { FontFolderSnapshot.contains(url.path, root: $0) } }.map { $0.standardizedFileURL.path })
        let urls = paths.sorted().map(URL.init(fileURLWithPath:))
        scanning = true; status = "Inspecting \(urls.count) font files…"
        DispatchQueue.global(qos: .userInitiated).async {
            let values = urls.map(FontRepairEngine.inspect)
            DispatchQueue.main.async { inspections = values; scanning = false; status = "Inspection complete"; if let first = values.first(where: \.needsReview) ?? (showClean ? values.first : nil) { select(first) } else { selectedPath = nil; selectedFixes = [] } }
        }
    }
    func inspectFile() {
        let panel = NSOpenPanel(); panel.canChooseFiles = true; panel.canChooseDirectories = false; panel.allowsMultipleSelection = true
        panel.allowedContentTypes = ["ttf", "otf", "ttc", "otc", "dfont", "woff", "woff2"].compactMap { UTType(filenameExtension: $0) }
        panel.message = "Choose font files to inspect. Inspection is read-only."
        guard panel.runModal() == .OK else { return }
        let values = panel.urls.map(FontRepairEngine.inspect)
        for value in values { if let index = inspections.firstIndex(where: { $0.url.standardizedFileURL == value.url.standardizedFileURL }) { inspections[index] = value } else { inspections.append(value) } }
        if let first = values.first { select(first) }; status = "Inspected \(values.count) selected file\(values.count == 1 ? "" : "s")"
    }
    func consumeRequestedFile() {
        guard let url = library.repairURL else { return }
        library.repairURL = nil; let item = FontRepairEngine.inspect(url)
        inspections.removeAll { $0.url.standardizedFileURL == item.url.standardizedFileURL }; inspections.insert(item, at: 0); select(item); status = "Inspected " + item.url.lastPathComponent
    }
    func exportCopy(_ item: FontInspection) {
        let panel = NSSavePanel(), ext = item.url.pathExtension
        panel.allowedContentTypes = [UTType(filenameExtension: ext) ?? .data]
        panel.nameFieldStringValue = item.url.deletingPathExtension().lastPathComponent + "-repaired." + ext
        panel.directoryURL = item.url.deletingLastPathComponent(); panel.message = "Typefield writes a new repaired copy and leaves the original untouched."
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        guard destination.standardizedFileURL != item.url.standardizedFileURL else { status = "Choose a different filename; Export never overwrites the original"; return }
        do { let data = try FontRepairEngine.repairedData(for: item.url, actions: selectedFixes); try data.write(to: destination, options: .atomic); status = "Repaired copy saved as " + destination.lastPathComponent; NSWorkspace.shared.activateFileViewerSelecting([destination]) }
        catch { status = "Repair failed: " + error.localizedDescription }
    }
    func canRepairOriginal(_ item: FontInspection) -> Bool {
        let watched = (library.resolvedFolders + library.saved.folders).contains { FontFolderSnapshot.contains(item.url.path, root: $0) }
        return item.canRepair && (FontRepairEngine.isUserFont(item.url) || watched) && FileManager.default.isWritableFile(atPath: item.url.path)
    }
    func repairOriginal(_ item: FontInspection) {
        let alert = NSAlert(); alert.messageText = "Repair the original font file?"
        alert.informativeText = "Typefield will first create a .fontshelf-backup beside the original, then atomically replace the original with the reviewed repair. This can affect every app using this font."
        alert.alertStyle = .warning; alert.addButton(withTitle: "Repair & Keep Backup"); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            let repaired = try FontRepairEngine.repairedData(for: item.url, actions: selectedFixes)
            let backup = uniqueBackupURL(item.url)
            try FileManager.default.copyItem(at: item.url, to: backup)
            do { try repaired.write(to: item.url, options: .atomic) }
            catch { try? FileManager.default.removeItem(at: backup); throw error }
            let refreshed = FontRepairEngine.inspect(item.url)
            if let index = inspections.firstIndex(where: { $0.id == item.id }) { inspections[index] = refreshed }; select(refreshed)
            library.reload(register: true); status = "Original repaired; backup saved as " + backup.lastPathComponent
        } catch { status = "Original was not repaired: " + error.localizedDescription }
    }
    func uniqueBackupURL(_ url: URL) -> URL {
        let folder = url.deletingLastPathComponent(), base = url.lastPathComponent + ".fontshelf-backup"
        var candidate = folder.appendingPathComponent(base), number = 2
        while FileManager.default.fileExists(atPath: candidate.path) { candidate = folder.appendingPathComponent(base + "-\(number)"); number += 1 }
        return candidate
    }
}

enum FontRepairChecks {
    static func run(catalog: [Family]) throws {
        func verify(_ condition: @autoclosure () -> Bool, _ message: String) throws { if !condition() { throw FontRepairError.invalid("Font repair check failed: " + message) } }
        func record(_ id: UInt16, _ text: String) -> FontRepairEngine.NameRecord { FontRepairEngine.NameRecord(platform: 3, encoding: 1, language: 0x0409, nameID: id, raw: FontRepairEngine.encode(text, platform: 3)!) }
        var records = [record(1, "BudNull"), record(2, "Medium"), record(4, "BudNull Medium"), record(6, "BudNullMedium"), record(5, "1.0"), record(7, ""), record(16, "BudNull"), record(17, "Medium")]
        records.append(record(4, "BudNull Medium"))
        var head = Data(repeating: 0, count: 54); head.fsSetUInt32(12, 0x5F0F3CF5)
        var os2 = Data(repeating: 0, count: 64); os2[62] = 0; os2[63] = 0x40
        let fixture = FontRepairEngine.buildSFNT(scaler: 0x00010000, tables: [("head", head), ("name", FontRepairEngine.buildName(records)), ("cmap", Data(repeating: 0, count: 4)), ("maxp", Data(repeating: 0, count: 6)), ("OS/2", os2)])
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Typefield-repair-check-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("BudNull.ttf"); try fixture.write(to: source)
        let before = FontRepairEngine.inspect(source)
        try verify(before.canRepair, "Fixture should be repairable")
        try verify(before.recommendedFixes.contains(.removeInvalidNames) && before.recommendedFixes.contains(.removeDuplicateNames) && before.recommendedFixes.contains(.normalizeLegacySubfamily) && before.recommendedFixes.contains(.normalizeVersion), "Expected name-table proposals")
        let repaired = try FontRepairEngine.repairedData(for: source, actions: before.recommendedFixes, validateWithCoreText: false)
        try verify(FontRepairEngine.checksum(repaired) == 0xB1B0AFBA, "Whole-font checksum adjustment")
        let output = root.appendingPathComponent("BudNull-repaired.ttf"); try repaired.write(to: output)
        let after = FontRepairEngine.inspect(output)
        try verify(after.names.subfamily == "Regular" && after.names.version == "Version 1.000", "Repaired naming preview")
        try verify(!after.issues.contains { [.removeInvalidNames, .removeDuplicateNames, .normalizeLegacySubfamily, .normalizeVersion, .rebuildChecksums].contains($0.fix) }, "Selected findings should be resolved")
        var validatedRealFont = false
        for url in Array(Set(catalog.flatMap(\.faces).compactMap(\.url).filter { ["ttf", "otf"].contains($0.pathExtension.lowercased()) })).prefix(100) {
            let inspection = FontRepairEngine.inspect(url)
            guard inspection.canRepair else { continue }
            var actions: Set<FontRepairAction> = [.rebuildChecksums]
            if inspection.issues.contains(where: { $0.fix == .removeDigitalSignature }) { actions.insert(.removeDigitalSignature) }
            do { _ = try FontRepairEngine.repairedData(for: url, actions: actions); validatedRealFont = true; break } catch { continue }
        }
        try verify(validatedRealFont, "A rebuilt local font should pass Core Text validation")
        print("PASS: font structure/name inspection, conservative proposals, repaired-copy rebuild, checksums and Core Text validation.")
    }
}
