// Research-only, read-only width dataset export. No outlines or raster masks
// are written. Compile with swiftc; pass a temporary JSON destination.
import AppKit
import CoreText
import CryptoKit

let characters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz").map(String.init)
let references = Array("HOnop").map(String.init)
let targets = characters.filter { !references.contains($0) }
let excludedLineages = ["helvetica", "times", "courier", "menlo", "avenir", "chalkboard", "noteworthy", "markerfelt", "snellroundhand", "georgia", "verdana", "trebuchet", "baskerville", "cochin", "americantypewriter", "comicsans", "bradleyhand", "zapfino"]
guard CommandLine.arguments.count == 2 else {
    fputs("Usage: width-export /tmp/typefield-width-training.json\n", stderr); exit(1)
}
func font(_ name: String) -> CTFont { CTFontCreateWithName(name as CFString, 1000, nil) }
func license(_ f: CTFont) -> String {
    [kCTFontLicenseNameKey, kCTFontLicenseURLNameKey].compactMap { CTFontCopyName(f, $0) as String? }.joined(separator: " ").lowercased()
}
func paths(_ f: CTFont) -> [CGPath]? {
    let cap = CTFontGetCapHeight(f)
    guard cap > 100 else { return nil }
    var result: [CGPath] = []
    for character in characters {
        var code = character.utf16.first!, glyph = CGGlyph()
        guard CTFontGetGlyphsForCharacters(f, &code, &glyph, 1), glyph != 0,
              let raw = CTFontCreatePathForGlyph(f, glyph, nil) else { return nil }
        let bounds = raw.boundingBoxOfPath, scale = 600/cap
        // Match the original width experiment's supported training frame.
        // Overflow faces are not silently clipped into training examples.
        guard bounds.width > 1, bounds.height > 1, bounds.width*scale < 1350,
              bounds.maxY*scale+220 < 1000, bounds.minY*scale+220 > 0 else { return nil }
        var transform = CGAffineTransform(a: scale, b: 0, c: 0, d: scale,
                                           tx: max(0, -bounds.minX*scale), ty: 220)
        guard let transformed = raw.copy(using: &transform) else { return nil }
        result.append(transformed)
    }
    return result
}
func digest(_ paths: [CGPath]) -> String {
    var raster = Data()
    for path in paths {
        var bytes = [UInt8](repeating: 0, count: 92*72)
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: 92, height: 72,
                                    bitsPerComponent: 8, bytesPerRow: 92,
                                    space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
            context.setShouldAntialias(false)
            context.scaleBy(x: 92/1400.0, y: 72/1000.0)
            context.setFillColor(gray: 1, alpha: 1)
            context.addPath(path); context.fillPath()
        }
        raster.append(contentsOf: bytes)
    }
    return SHA256.hash(data: raster).map { String(format: "%02x", $0) }.joined()
}
func priority(_ name: String) -> Int {
    let value = name.lowercased()
    return value.hasSuffix("regular") ? 0 : value.hasSuffix("bold") ? 1 : value.hasSuffix("italic") ? 2 : value.hasSuffix("light") ? 3 : 4
}
var families: [String: [String]] = [:]
for name in (CTFontManagerCopyAvailablePostScriptNames() as? [String] ?? []).sorted() {
    let face = font(name), metadata = license(face)
    guard metadata.contains("open font license") || metadata.contains("openfontlicense.org") || metadata.contains("scripts.sil.org/ofl") else { continue }
    let family = CTFontCopyFamilyName(face) as String
    let key = family.lowercased().filter(\.isLetter)
    guard !excludedLineages.contains(where: { key.hasPrefix($0) }) else { continue }
    families[family, default: []].append(name)
}
let selected = families.keys.sorted().flatMap { family in
    families[family]!.sorted { (priority($0), $0) < (priority($1), $1) }.prefix(6)
}
var records: [[String: Any]] = [], seen = Set<String>(), unsupported = 0
for name in selected {
    let face = font(name)
    guard CTFontCopyPostScriptName(face) as String == name, let outlines = paths(face) else { unsupported += 1; continue }
    let hash = digest(outlines)
    guard seen.insert(hash).inserted else { continue }
    let boxes = Dictionary(uniqueKeysWithValues: zip(characters, outlines.map(\.boundingBoxOfPath)))
    let h = boxes["H"]!, o = boxes["O"]!, n = boxes["n"]!, lowerO = boxes["o"]!, p = boxes["p"]!
    let features = [log(o.width/h.width), log(n.width/h.width), log(lowerO.width/n.width), log(p.width/n.width),
                    log(h.width/h.height), log(n.height/h.height), log(p.height/n.height), log(o.height/h.height)]
    let widths = targets.map { character in log(boxes[character]!.width/(character == character.uppercased() ? h.width : n.width)) }
    records.append(["name": name, "family": CTFontCopyFamilyName(face) as String,
                    "features": features, "logWidthRatios": widths, "alphabetMaskSHA256": hash])
}
guard !records.isEmpty else { fputs("No eligible open-license training faces were available.\n", stderr); exit(1) }
let object: [String: Any] = ["schemaVersion": 1, "references": references, "targets": targets,
                            "excludedLineages": excludedLineages, "records": records]
try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]).write(to: URL(fileURLWithPath: CommandLine.arguments[1]), options: .atomic)
print("Width training export: \(records.count) distinct faces, \(Set(records.compactMap { $0["family"] as? String }).count) families; \(unsupported) unsupported faces excluded. No outlines or masks written.")
