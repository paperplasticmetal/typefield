import AppKit

enum FontLabStarterConfidence: String, Equatable {
    case adapted
    case template

    var title: String {
        switch self {
        case .adapted: return "Adapted from your drawing"
        case .template: return "Provisional template"
        }
    }
}

struct FontLabStarterDetail: Equatable {
    let sourceCharacters: [String]
    let method: String
    let explanation: String
    let confidence: FontLabStarterConfidence
}

struct FontLabStarterProposal: Equatable {
    let glyphs: [String: FontLabGlyph]
    let details: [String: FontLabStarterDetail]
    let skipped: [String: String]
    let note: String
}

/// A local, deterministic starting point for the basic Latin alphabet. These
/// shapes are independent editable outlines; accepting one never links it to,
/// replaces, or changes a person's drawing. A handful of control letters can
/// establish weight and proportions, but cannot establish every design choice.
enum FontLabStarterAssist {
    private static let alphabet = Set(Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz").map(String.init))
    private static let compatibleCases = Set(Array("COSVWXZcosvwxz").map(String.init))
    private static let controlOrder = Array("HONXhonxp").map(String.init)

    static func hasLatinArtwork(in project: FontLabProject) -> Bool {
        project.characters.contains { alphabet.contains($0) && project.resolvedGlyph($0)?.hasArtwork == true }
    }

    static func propose(for project: FontLabProject) -> FontLabStarterProposal {
        let targets = project.characters.filter { alphabet.contains($0) }
        var skipped: [String: String] = [:]
        guard project.isValid else {
            for character in targets { skipped[character] = "Repair this project before preparing starter letters." }
            return FontLabStarterProposal(glyphs: [:], details: [:], skipped: skipped, note: "Starter letters require a valid project.")
        }
        let drawn = targets.filter { project.resolvedGlyph($0)?.hasArtwork == true }
        guard !drawn.isEmpty else {
            for character in targets { skipped[character] = "Draw at least one Latin letter first." }
            return FontLabStarterProposal(glyphs: [:], details: [:], skipped: skipped, note: "Draw a few letters first. H, O, N, and X give the clearest starting proportions.")
        }
        let controls = controlOrder.filter { drawn.contains($0) }
        let sampled = controls + Array(drawn.filter { !controls.contains($0) }.prefix(4))
        // Curves and diagonals look wider at a horizontal probe than a true
        // stem. Prefer vertical-stem controls when the user has drawn them.
        let stemControls = Set(["H", "h", "n", "p", "N"])
        let stemSamples = sampled.filter { stemControls.contains($0) }
        let weight = measuredWeight(in: project, characters: stemSamples.isEmpty ? sampled : stemSamples)
        var glyphs: [String: FontLabGlyph] = [:]
        var details: [String: FontLabStarterDetail] = [:]
        for character in targets {
            if project.resolvedGlyph(character)?.hasArtwork == true {
                skipped[character] = "Already drawn; your letter is kept unchanged."
                continue
            }
            var candidate: FontLabGlyph?
            var detail: FontLabStarterDetail?
            let counterpart = character == character.uppercased() ? character.lowercased() : character.uppercased()
            if compatibleCases.contains(character),
               let source = project.resolvedGlyph(counterpart), source.hasArtwork {
                candidate = adapted(source, to: character, metrics: project.metrics)
                if candidate != nil {
                    detail = FontLabStarterDetail(sourceCharacters: [counterpart], method: "Scaled outline", explanation: "The drawn \(counterpart) outline was scaled to the \(character == character.uppercased() ? "cap" : "x") height. Review its weight, spacing, and curve balance.", confidence: .adapted)
                }
            }
            if candidate == nil {
                candidate = template(character, metrics: project.metrics, weight: weight)
                if candidate != nil {
                    let sources = sampled.isEmpty ? "the project guides" : "the project guides and \(sampled.joined(separator: ", "))"
                    detail = FontLabStarterDetail(sourceCharacters: sampled, method: "Constructed outline", explanation: "A distinct Latin letterform was constructed from \(sources). This is a starting shape, not a prediction of your intended design; refine its curves and spacing.", confidence: .template)
                }
            }
            guard var candidate, let detail else {
                skipped[character] = "Could not construct valid editable geometry for this letter."
                continue
            }
            candidate.starterOrigin = detail.confidence == .adapted
                ? "Starter adaptation from \(detail.sourceCharacters.joined(separator: ", "))"
                : "Starter template informed by \(detail.sourceCharacters.joined(separator: ", "))"
            guard candidate.isValid, candidate.hasArtwork else {
                skipped[character] = "Generated geometry did not pass project validation."
                continue
            }
            glyphs[character] = candidate
            details[character] = detail
        }
        return FontLabStarterProposal(
            glyphs: glyphs, details: details, skipped: skipped,
            note: "Starter letters are editable suggestions. Templates use your guides and an estimated stroke weight; a few examples cannot determine every curve, serif, or spacing choice. Review each letter before export."
        )
    }

    /// Prefer an actual closed outline for weight measurement. The sample is
    /// taken near the upper part of H/O/N (or their lowercase equivalents),
    /// where a crossbar is unlikely to confuse a vertical-stem measurement.
    private static func measuredWeight(in project: FontLabProject, characters: [String]) -> Double {
        var widths: [Double] = []
        for character in characters {
            guard let glyph = project.resolvedGlyph(character) else { continue }
            let sampleTop = character == character.uppercased() ? project.metrics.capHeight : project.metrics.xHeight
            let y = project.metrics.baseline + (sampleTop - project.metrics.baseline) * 0.82
            let path = CGMutablePath()
            for stroke in glyph.strokes {
                if let vector = stroke.vectorPaths {
                    for shape in vector where shape.closed { path.addPath(shape.cgPath) }
                } else if let contours = stroke.contours {
                    for contour in contours {
                        path.addLines(between: contour.map { CGPoint(x: $0.x * 1_000, y: $0.y * 1_000) })
                        path.closeSubpath()
                    }
                } else if !stroke.points.isEmpty {
                    widths.append(stroke.width * glyph.resolvedDesignWidth)
                }
            }
            var start: Int? = nil
            for i in 0...500 {
                let inside = path.contains(CGPoint(x: Double(i) * 2, y: y * 1_000), using: .winding, transform: .identity)
                if inside && start == nil { start = i }
                if !inside, let first = start {
                    let run = Double(i - first) / 500 * glyph.resolvedDesignWidth
                    if (0.018...0.15).contains(run) { widths.append(run) }
                    start = nil
                }
            }
        }
        let sorted = widths.filter(\.isFinite).sorted()
        return min(0.12, max(0.035, sorted.isEmpty ? 0.064 : sorted[sorted.count / 2]))
    }

    private static func adapted(_ source: FontLabGlyph, to character: String, metrics: FontLabMetrics) -> FontLabGlyph? {
        let sourceIsUpper = source.character == source.character.uppercased()
        let targetIsUpper = character == character.uppercased()
        let sourceTop = sourceIsUpper ? metrics.capHeight : metrics.xHeight
        let targetTop = targetIsUpper ? metrics.capHeight : metrics.xHeight
        let scale = (targetTop - metrics.baseline) / (sourceTop - metrics.baseline)
        let targetWidth = min(1.1, max(0.24, source.resolvedDesignWidth * (targetIsUpper ? 1.08 : 0.92)))
        func transform(_ value: FontLabPoint) -> FontLabPoint {
            var point = value
            point.y = metrics.baseline + (point.y - metrics.baseline) * scale
            return point
        }
        var strokes = FontLabDesign.detachedStrokes(source.strokes)
        for index in strokes.indices {
            strokes[index].points = strokes[index].points.map(transform)
            strokes[index].contours = strokes[index].contours?.map { $0.map(transform) }
            if var paths = strokes[index].vectorPaths {
                for p in paths.indices { for n in paths[p].nodes.indices {
                    paths[p].nodes[n].point = transform(paths[p].nodes[n].point)
                    paths[p].nodes[n].incoming = paths[p].nodes[n].incoming.map(transform)
                    paths[p].nodes[n].outgoing = paths[p].nodes[n].outgoing.map(transform)
                } }
                strokes[index].vectorPaths = paths
            }
            if !strokes[index].points.isEmpty { strokes[index].width *= min(1, scale) }
        }
        let glyph = FontLabGlyph(character: character, strokes: strokes,
                                 leftSideBearing: source.leftSideBearing, rightSideBearing: source.rightSideBearing,
                                 contourDesignWidth: targetWidth)
        return glyph.isValid ? glyph : nil
    }

    private static func template(_ character: String, metrics: FontLabMetrics, weight: Double) -> FontLabGlyph? {
        let width: Double
        switch character {
        case "M", "W": width = 0.84
        case "I": width = 0.34
        case "J": width = 0.50
        case "m", "w": width = 0.82
        case "i", "l": width = 0.29
        case "j": width = 0.40
        case "f", "r", "t": width = 0.43
        default: width = character == character.uppercased() ? 0.65 : 0.57
        }
        // A very short x-height cannot fit a stroke measured from a tall cap.
        // Keep the proposed outline inside the user's guides in that case.
        let safeWeight = min(weight, (metrics.xHeight - metrics.baseline) * 0.65)
        var shape = FontLabStarterSkeleton(width: width, metrics: metrics, weight: safeWeight)
        shape.draw(character)
        guard let paths = shape.outlines(), !paths.isEmpty else { return nil }
        let glyph = FontLabGlyph(character: character, strokes: [FontLabStroke(vectorPaths: paths)],
                                 leftSideBearing: 0.075, rightSideBearing: 0.075,
                                 contourDesignWidth: width)
        return glyph.isValid ? glyph : nil
    }
}

/// Skeleton coordinates are letter-local: x runs 0...1, y runs from the
/// baseline (0) to cap height (1). Lowercase x-height is computed from the
/// project's guides. The centerlines are stroked in physical em coordinates
/// so wide and narrow letters keep the same apparent stroke weight.
private struct FontLabStarterSkeleton {
    let width: Double
    let metrics: FontLabMetrics
    let weight: Double
    private let centerlines = CGMutablePath()
    private let solids = CGMutablePath()
    private var capSpan: Double { metrics.capHeight - metrics.baseline }
    // point(y:) places the baseline and cap centerlines half a stroke in from
    // the guides. Solve for the lowercase centerline whose *outer* edge reaches
    // x-height, otherwise lowercase bowls overshoot the guide.
    private var h: Double { (metrics.xHeight - metrics.baseline - weight) / (capSpan - weight) }
    private var d: Double { min(0.25, max(0.015, (metrics.baseline - 0.012) / capSpan)) }

    private func point(_ x: Double, _ y: Double) -> CGPoint {
        let half = weight / 2
        let actualY = y >= 0
            ? metrics.baseline + half + (capSpan - weight) * y
            : metrics.baseline + half + capSpan * y
        return CGPoint(x: x * width * 1_000, y: actualY * 1_000)
    }
    private func move(_ x: Double, _ y: Double) { centerlines.move(to: point(x, y)) }
    private func line(_ x: Double, _ y: Double) { centerlines.addLine(to: point(x, y)) }
    private func curve(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ x: Double, _ y: Double) {
        centerlines.addCurve(to: point(x, y), control1: point(x1, y1), control2: point(x2, y2))
    }
    private func close() { centerlines.closeSubpath() }
    private func stroke(_ points: [(Double, Double)]) {
        guard let first = points.first else { return }
        move(first.0, first.1)
        for p in points.dropFirst() { line(p.0, p.1) }
    }
    private func oval(_ left: Double, _ bottom: Double, _ right: Double, _ top: Double) {
        let a = point(left, bottom), b = point(right, top)
        centerlines.addEllipse(in: CGRect(x: a.x, y: a.y, width: b.x - a.x, height: b.y - a.y))
    }
    private func dot(_ x: Double, _ y: Double) {
        let p = point(x, y), radius = weight * 600
        solids.addEllipse(in: CGRect(x: p.x-radius, y: p.y-radius, width: radius*2, height: radius*2))
    }
    func outlines() -> [FontLabVectorPath]? {
        let stroked = centerlines.copy(strokingWithWidth: weight * 1_000, lineCap: .round, lineJoin: .round, miterLimit: 4)
        let combined = CGMutablePath(); combined.addPath(stroked); combined.addPath(solids)
        let normalized = CGMutablePath(); normalized.addPath(combined, transform: CGAffineTransform(scaleX: 1 / width, y: 1))
        let paths = FontLabVectorPath.from(normalized)
        guard !paths.isEmpty, paths.allSatisfy(\.isValid), paths.allSatisfy(\.closed),
              paths.reduce(0, { $0 + $1.nodes.count }) <= 30_000 else { return nil }
        return paths
    }

    mutating func draw(_ character: String) {
        switch character {
        case "A":
            stroke([(0.14,0),(0.50,1),(0.86,0)]); stroke([(0.28,0.40),(0.72,0.40)])
        case "B":
            stroke([(0.18,0),(0.18,1),(0.55,1)])
            move(0.55,1); curve(0.94,1,0.94,0.55,0.53,0.51); line(0.18,0.51)
            move(0.53,0.51); curve(0.99,0.51,0.97,0,0.51,0); line(0.18,0)
        case "C":
            move(0.85,0.86); curve(0.17,1.25,0.08,0.82,0.14,0.50); curve(0.08,0.15,0.19,-0.19,0.85,0.14)
        case "D":
            stroke([(0.18,0),(0.18,1),(0.48,1)])
            move(0.48,1); curve(1.02,1,1.03,0,0.48,0); line(0.18,0)
        case "E":
            stroke([(0.83,1),(0.18,1),(0.18,0),(0.83,0)]); stroke([(0.18,0.51),(0.70,0.51)])
        case "F":
            stroke([(0.18,0),(0.18,1),(0.83,1)]); stroke([(0.18,0.51),(0.70,0.51)])
        case "G":
            move(0.86,0.85); curve(0.15,1.25,0.08,0.80,0.14,0.50); curve(0.08,0.14,0.25,-0.18,0.83,0.13)
            stroke([(0.83,0.13),(0.83,0.49),(0.58,0.49)])
        case "H":
            stroke([(0.18,0),(0.18,1)]); stroke([(0.82,0),(0.82,1)]); stroke([(0.18,0.50),(0.82,0.50)])
        case "I":
            stroke([(0.50,0),(0.50,1)]); stroke([(0.22,1),(0.78,1)]); stroke([(0.22,0),(0.78,0)])
        case "J":
            stroke([(0.78,1),(0.78,0.18)]); move(0.78,0.18); curve(0.76,-0.16,0.21,-0.15,0.16,0.22)
        case "K":
            stroke([(0.18,0),(0.18,1)]); stroke([(0.83,1),(0.18,0.43),(0.84,0)])
        case "L":
            stroke([(0.18,1),(0.18,0),(0.83,0)])
        case "M":
            stroke([(0.12,0),(0.12,1),(0.50,0.41),(0.88,1),(0.88,0)])
        case "N":
            stroke([(0.17,0),(0.17,1),(0.83,0),(0.83,1)])
        case "O": oval(0.14,0,0.86,1)
        case "P":
            stroke([(0.18,0),(0.18,1),(0.55,1)])
            move(0.55,1); curve(0.98,1,0.98,0.48,0.55,0.48); line(0.18,0.48)
        case "Q": oval(0.14,0,0.86,1); stroke([(0.62,0.24),(0.91,-0.10)])
        case "R":
            stroke([(0.18,0),(0.18,1),(0.55,1)])
            move(0.55,1); curve(0.98,1,0.98,0.48,0.55,0.48); line(0.18,0.48)
            stroke([(0.51,0.48),(0.85,0)])
        case "S":
            move(0.83,0.85); curve(0.20,1.21,0.01,0.69,0.51,0.51)
            curve(1.01,0.32,0.82,-0.20,0.17,0.15)
        case "T": stroke([(0.12,1),(0.88,1)]); stroke([(0.50,1),(0.50,0)])
        case "U":
            move(0.17,1); line(0.17,0.31); curve(0.17,-0.11,0.83,-0.11,0.83,0.31); line(0.83,1)
        case "V": stroke([(0.13,1),(0.50,0),(0.87,1)])
        case "W": stroke([(0.10,1),(0.30,0),(0.50,0.63),(0.70,0),(0.90,1)])
        case "X": stroke([(0.15,1),(0.85,0)]); stroke([(0.85,1),(0.15,0)])
        case "Y": stroke([(0.14,1),(0.50,0.51),(0.86,1)]); stroke([(0.50,0.51),(0.50,0)])
        case "Z": stroke([(0.15,1),(0.85,1),(0.15,0),(0.85,0)])
        case "a":
            oval(0.14,0,0.75,h); stroke([(0.75,h),(0.75,0)])
        case "b":
            stroke([(0.18,0),(0.18,1)]); oval(0.18,0,0.86,h)
        case "c":
            move(0.83,h*0.84); curve(0.19,h*1.21,0.08,h*0.77,0.14,h*0.50)
            curve(0.08,h*0.18,0.21,-h*0.20,0.83,h*0.16)
        case "d":
            stroke([(0.82,0),(0.82,1)]); oval(0.14,0,0.82,h)
        case "e":
            move(0.14,h*0.48); line(0.85,h*0.48)
            curve(0.88,h*1.24,0.12,h*1.25,0.14,h*0.48)
            curve(0.13,-h*0.16,0.62,-h*0.19,0.83,h*0.15)
        case "f":
            move(0.43,0); line(0.43,0.77)
            curve(0.43,1.05,0.60,1.08,0.83,0.98)
            stroke([(0.18,h*0.82),(0.76,h*0.82)])
        case "g":
            oval(0.14,0,0.79,h); stroke([(0.79,h),(0.79,-d*0.46)])
            move(0.79,-d*0.46); curve(0.76,-d*1.18,0.33,-d*1.12,0.20,-d*0.70)
        case "h":
            stroke([(0.18,0),(0.18,1),(0.18,h*0.53)])
            move(0.18,h*0.53); curve(0.19,h*1.13,0.82,h*1.13,0.82,h*0.51); line(0.82,0)
        case "i":
            stroke([(0.50,0),(0.50,h*0.78)]); dot(0.50,h*1.23)
        case "j":
            move(0.56,h*0.78); line(0.56,-d*0.58)
            curve(0.55,-d*1.04,0.28,-d*1.16,0.17,-d*0.82); dot(0.56,h*1.23)
        case "k":
            stroke([(0.18,0),(0.18,1)]); stroke([(0.81,h),(0.18,h*0.37),(0.83,0)])
        case "l": stroke([(0.50,0),(0.50,1)])
        case "m":
            stroke([(0.13,0),(0.13,h)])
            move(0.13,h*0.54); curve(0.13,h*1.12,0.49,h*1.12,0.49,h*0.54); line(0.49,0)
            move(0.49,h*0.54); curve(0.49,h*1.12,0.87,h*1.12,0.87,h*0.54); line(0.87,0)
        case "n":
            stroke([(0.18,0),(0.18,h)])
            move(0.18,h*0.55); curve(0.18,h*1.13,0.82,h*1.13,0.82,h*0.55); line(0.82,0)
        case "o": oval(0.14,0,0.86,h)
        case "p":
            stroke([(0.18,-d),(0.18,h)]); oval(0.18,0,0.86,h)
        case "q":
            stroke([(0.82,-d),(0.82,h)]); oval(0.14,0,0.82,h)
        case "r":
            stroke([(0.22,0),(0.22,h)]); move(0.22,h*0.52)
            curve(0.26,h*1.06,0.63,h*1.14,0.81,h*0.89)
        case "s":
            move(0.82,h*0.84); curve(0.23,h*1.20,0.02,h*0.61,0.50,h*0.50)
            curve(1.00,h*0.36,0.80,-h*0.18,0.17,h*0.15)
        case "t":
            stroke([(0.50,0),(0.50,0.91)]); stroke([(0.19,h*0.77),(0.81,h*0.77)])
        case "u":
            move(0.17,h); line(0.17,h*0.31); curve(0.17,-h*0.16,0.82,-h*0.15,0.82,h*0.31)
            line(0.82,h); stroke([(0.82,h*0.47),(0.82,0)])
        case "v": stroke([(0.14,h),(0.50,0),(0.86,h)])
        case "w": stroke([(0.10,h),(0.30,0),(0.50,h*0.62),(0.70,0),(0.90,h)])
        case "x": stroke([(0.15,h),(0.85,0)]); stroke([(0.85,h),(0.15,0)])
        case "y":
            stroke([(0.15,h),(0.51,0),(0.85,h)]); stroke([(0.51,0),(0.29,-d)])
        case "z": stroke([(0.16,h),(0.84,h),(0.16,0),(0.84,0)])
        default: break
        }
    }
}
