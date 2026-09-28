// Research-only font-prior benchmark. Never called by the application.
// Compile: swiftc -O -module-cache-path /tmp/typefield-study-cache scripts/starter-research/reference-retrieval.swift -o /tmp/typefield-reference-study
// Run: /tmp/typefield-reference-study
// Installed fonts are read only; no font data or project data is written.
// Known target family lineages are excluded before donor ranking. Close Latin
// clones in unrelated families can still exist, so this is not a novel-font test.
// Only H O n o p participate in fitting. Hidden letters are scored afterwards.
import AppKit
import CoreText

let testNames = [
  "Helvetica", "Times-Roman", "Courier", "Menlo-Regular", "Avenir-Book", "ChalkboardSE-Regular",
  "Noteworthy-Light", "MarkerFelt-Wide", "SnellRoundhand",
]
let seeds = Array("HOnop").map(String.init)
let letters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz").map(String.init)
let baseline = 220.0
func font(_ name: String) -> CTFont { CTFontCreateWithName(name as CFString, 1000, nil) }
for name in testNames {
  guard CTFontCopyPostScriptName(font(name)) as String == name else {
    fputs("Required benchmark font unavailable: \(name)\n", stderr)
    exit(1)
  }
}
let excluded = Set(testNames.map { CTFontCopyFamilyName(font($0)) as String })
let lineages = [
  "helvetica", "times", "courier", "menlo", "avenir", "chalkboard", "noteworthy", "markerfelt",
  "snellroundhand",
]
func excludedLineage(_ name: String) -> Bool {
  let key = name.lowercased().filter { $0.isLetter }
  return lineages.contains { key.hasPrefix($0) }
}
struct Shape {
  let path: CGPath
  let width: Double
  let left: Double
  let right: Double
}
func shape(_ f: CTFont, _ c: String, _ xScale: Double = 1, _ lowerScale: Double = 1) -> Shape? {
  var char = c.utf16.first!
  var g = CGGlyph()
  guard CTFontGetGlyphsForCharacters(f, &char, &g, 1), g != 0,
    let raw = CTFontCreatePathForGlyph(f, g, nil)
  else { return nil }
  let b = raw.boundingBoxOfPath
  let cap = Double(CTFontGetCapHeight(f))
  guard cap > 0, b.width > 1 else { return nil }
  let sy = 600 / cap * (c == c.uppercased() ? 1 : lowerScale)
  let sx = 600 / cap * xScale
  var advance = CGSize.zero
  _ = CTFontGetAdvancesForGlyphs(f, .horizontal, &g, &advance, 1)
  let left = max(0, b.minX * sx)
  let right = max(0, (advance.width - b.maxX) * sx)
  var tr = CGAffineTransform(a: sx, b: 0, c: 0, d: sy, tx: left - b.minX * sx, ty: baseline)
  guard let p = raw.copy(using: &tr) else { return nil }
  return Shape(path: p, width: b.width * sx, left: left, right: right)
}
func adjusted(_ path: CGPath, _ lean: Double, _ weight: Double) -> CGPath {
  var t = CGAffineTransform(a: 1, b: 0, c: lean, d: 1, tx: -lean * baseline, ty: 0)
  let p = path.copy(using: &t)!
  if abs(weight) < 0.01 { return p }
  let border = p.copy(
    strokingWithWidth: abs(weight) * 2, lineCap: .round, lineJoin: .round, miterLimit: 4)
  return weight > 0 ? p.union(border, using: .winding) : p.subtracting(border, using: .winding)
}
func mask(_ p: CGPath, _ resolution: Int = 96) -> [UInt8] {
  var bytes = [UInt8](repeating: 0, count: resolution * resolution)
  bytes.withUnsafeMutableBytes { buffer in
    let ctx = CGContext(
      data: buffer.baseAddress, width: resolution, height: resolution, bitsPerComponent: 8,
      bytesPerRow: resolution, space: CGColorSpaceCreateDeviceGray(),
      bitmapInfo: CGImageAlphaInfo.none.rawValue)!
    ctx.setShouldAntialias(false)
    ctx.scaleBy(x: Double(resolution) / 1400, y: Double(resolution) / 1000)
    ctx.setFillColor(gray: 1, alpha: 1)
    ctx.addPath(p)
    ctx.fillPath()
  }
  return bytes
}
// Match the shipped audit's fixed coordinate sampling exactly for final scores.
func auditMask(_ p: CGPath) -> [UInt8] {
  (0..<72).flatMap { y in
    (0..<92).map { x in
      p.contains(CGPoint(x: (Double(x) + 0.5) / 92 * 1400, y: (Double(y) + 0.5) / 72 * 1000))
        ? UInt8(255) : UInt8(0)
    }
  }
}
func iou(_ a: [UInt8], _ b: [UInt8]) -> Double {
  var u = 0
  var i = 0
  for n in a.indices {
    if a[n] > 0 || b[n] > 0 { u += 1 }
    if a[n] > 0 && b[n] > 0 { i += 1 }
  }
  return Double(i) / Double(max(1, u))
}
func median(_ v: [Double]) -> Double {
  let s = v.sorted()
  return s[s.count / 2]
}
let all = (CTFontManagerCopyAvailablePostScriptNames() as? [String] ?? []).sorted().filter {
  !excludedLineage(CTFontCopyFamilyName(font($0)) as String) && !$0.hasPrefix(".")
}
struct Donor {
  let name: String
  let font: CTFont
  let shapes: [String: Shape]
}
let donors = all.compactMap { name -> Donor? in
  let f = font(name)
  var shapes: [String: Shape] = [:]
  for c in seeds {
    guard let s = shape(f, c) else { return nil }
    shapes[c] = s
  }
  return Donor(name: name, font: f, shapes: shapes)
}
print("EXCLUDED FAMILIES \(excluded.sorted()); DONORS \(donors.count)")
var overall: [Double] = []
for name in testNames {
  let target = font(name)
  let truth = Dictionary(uniqueKeysWithValues: seeds.map { ($0, shape(target, $0)!) })
  let masks = truth.mapValues { mask($0.path) }
  let advances = seeds.map { truth[$0]!.width + truth[$0]!.left + truth[$0]!.right }
  let fixedAdvance = (advances.max()! - advances.min()!) / median(advances) < 0.02
  var best: [(Double, Donor, Double, Double, Double)] = []
  for d in donors {
    let upper = median(["H", "O"].map { truth[$0]!.width / d.shapes[$0]!.width })
    let lower = median(["n", "o", "p"].map { truth[$0]!.width / d.shapes[$0]!.width })
    let lowerY =
      Double(CTFontGetXHeight(target) / CTFontGetCapHeight(target))
      / (Double(CTFontGetXHeight(d.font) / CTFontGetCapHeight(d.font)))
    guard (0.5...2).contains(upper), (0.5...2).contains(lower), (0.5...2).contains(lowerY) else {
      continue
    }
    let score =
      seeds.reduce(0.0) {
        $0
          + iou(
            mask(shape(d.font, $1, $1 == $1.uppercased() ? upper : lower, lowerY)!.path), masks[$1]!
          )
      } / Double(seeds.count)
    let da = seeds.map {
      let v = d.shapes[$0]!
      return v.width + v.left + v.right
    }
    let donorFixed = (da.max()! - da.min()!) / median(da) < 0.02
    best.append((score - (fixedAdvance != donorFixed ? 0.15 : 0), d, upper, lower, lowerY))
  }
  best.sort { $0.0 > $1.0 }
  var refined: [(Double, Donor, Double, Double, Double, Double, Double)] = []
  for b in best.prefix(24) {
    var bestScore = b.0
    var bestLean = 0.0
    var bestWeight = 0.0
    let da = seeds.map {
      let v = b.1.shapes[$0]!
      return v.width + v.left + v.right
    }
    let donorFixed = (da.max()! - da.min()!) / median(da) < 0.02
    let shapes = Dictionary(
      uniqueKeysWithValues: seeds.map {
        ($0, shape(b.1.font, $0, $0 == $0.uppercased() ? b.2 : b.3, b.4)!.path)
      })
    for lean in [-0.3, -0.2, -0.1, 0, 0.1, 0.2, 0.3] {
      for weight in [-8.0, -4.0, 0, 4, 8] {
        let score =
          seeds.reduce(0.0) { $0 + iou(mask(adjusted(shapes[$1]!, lean, weight)), masks[$1]!) }
          / Double(seeds.count) - (fixedAdvance != donorFixed ? 0.15 : 0)
        if score > bestScore {
          bestScore = score
          bestLean = lean
          bestWeight = weight
        }
      }
    }
    refined.append((bestScore, b.1, b.2, b.3, b.4, bestLean, bestWeight))
  }
  refined.sort { $0.0 > $1.0 }
  for (rank, b) in refined.prefix(3).enumerated() {
    var scores: [Double] = []
    for c in letters where !seeds.contains(c) {
      guard let actual = shape(target, c),
        let guess = shape(b.1.font, c, c == c.uppercased() ? b.2 : b.3, b.4)
      else {
        scores.append(0)
        continue
      }
      scores.append(iou(auditMask(actual.path), auditMask(adjusted(guess.path, b.5, b.6))))
    }
    if rank == 0 { overall.append(scores.reduce(0, +) / Double(scores.count)) }
    print(
      "RESULT \(name) rank\(rank+1) donor=\(b.1.name) reference=\(b.0) lean=\(b.5) weight=\(b.6) holdout=\(scores.reduce(0,+)/Double(scores.count))"
    )
  }
  fflush(stdout)
}

print("OVERALL \(overall.count) faces: \(overall.reduce(0,+)/Double(max(1,overall.count)))")
