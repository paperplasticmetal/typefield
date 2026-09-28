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

    static func propose(for project: FontLabProject, reuseCapStems: Bool = true) -> FontLabStarterProposal {
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
        let sources = Dictionary(uniqueKeysWithValues: drawn.compactMap { character -> (String, FontLabGlyph)? in
            guard let glyph = project.resolvedGlyph(character), glyph.hasArtwork else { return nil }
            return (character, compact(glyph))
        })
        let style = FontLabStarterStyle(project: project, sources: sources, weight: weight)
        // Select the construction that best reproduces the supplied controls.
        // Hidden target letters never participate in this calibration.
        func preservesWeight(_ uppercase: Bool) -> Bool {
            let controls = (uppercase ? "HNOX" : "hnop").map(String.init).filter { sources[$0] != nil }
            func score(_ preserve: Bool) -> Double {
                controls.reduce(0) { total, character in
                    guard let generated = template(character, style: style, preserveWeight: preserve),
                          let actual = sources[character] else { return total }
                    return total + similarity(generated, actual)
                }
            }
            return !controls.isEmpty && score(true) > score(false) + 0.01
        }
        let preserveUpperWeight = preservesWeight(true), preserveLowerWeight = preservesWeight(false)
        var glyphs: [String: FontLabGlyph] = [:]
        var details: [String: FontLabStarterDetail] = [:]
        for character in targets {
            if Task.isCancelled { break }
            if project.resolvedGlyph(character)?.hasArtwork == true {
                skipped[character] = "Already drawn; your letter is kept unchanged."
                continue
            }
            var candidate: FontLabGlyph?
            var detail: FontLabStarterDetail?
            let counterpart = character == character.uppercased() ? character.lowercased() : character.uppercased()
            if compatibleCases.contains(character),
               let source = sources[counterpart] {
                candidate = adapted(source, to: character, metrics: project.metrics)
                if candidate != nil {
                    detail = FontLabStarterDetail(sourceCharacters: [counterpart], method: "Scaled outline", explanation: "The drawn \(counterpart) outline was scaled to the \(character == character.uppercased() ? "cap" : "x") height. Review its weight, spacing, and curve balance.", confidence: .adapted)
                }
            }
            if candidate == nil, let derived = sourceDerived(character, sources: sources, style: style, reuseCapStems: reuseCapStems) {
                candidate = derived.glyph
                detail = FontLabStarterDetail(sourceCharacters: derived.sources, method: derived.method,
                                              explanation: derived.explanation, confidence: .adapted)
            }
            if candidate == nil {
                candidate = template(character, style: style, preserveWeight: character == character.uppercased() ? preserveUpperWeight : preserveLowerWeight)
                if candidate != nil {
                    let sources = sampled.isEmpty ? "the project guides" : "the project guides and \(sampled.joined(separator: ", "))"
                    detail = FontLabStarterDetail(sourceCharacters: sampled, method: "Constructed outline", explanation: "A distinct Latin letterform was constructed using proportions, spacing, and stroke weight measured from \(sources). Its contours were not copied from those drawings; refine its curves and spacing.", confidence: .template)
                }
            }
            guard var candidate, let detail else {
                skipped[character] = "Could not construct valid editable geometry for this letter."
                continue
            }
            candidate = compact(candidate)
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
            note: "Starter letters are editable suggestions. Adapted letters reuse your outlines; templates use measured proportions and spacing. A few examples cannot determine every curve or serif. Review each letter before export."
        )
    }

    private static func similarity(_ a: FontLabGlyph, _ b: FontLabGlyph) -> Double {
        func ink(_ glyph: FontLabGlyph) -> CGPath {
            let result = CGMutablePath()
            let transform = CGAffineTransform(a: glyph.resolvedDesignWidth, b: 0, c: 0, d: 1, tx: glyph.leftSideBearing * 1000, ty: 0)
            FontLabVectorMath.paths(in: glyph).filter(\.closed).forEach { result.addPath($0.cgPath, transform: transform) }
            return result
        }
        let a = ink(a), b = ink(b), box = a.boundingBoxOfPath.union(b.boundingBoxOfPath)
        var intersection = 0, union = 0
        for y in 0..<64 { for x in 0..<64 {
            let point = CGPoint(x: box.minX + (Double(x)+0.5)/64*box.width, y: box.minY + (Double(y)+0.5)/64*box.height)
            let aa = a.contains(point), bb = b.contains(point)
            if aa && bb { intersection += 1 }; if aa || bb { union += 1 }
        } }
        return Double(intersection)/Double(max(1, union))
    }

    private static func compact(_ glyph: FontLabGlyph) -> FontLabGlyph {
        for units in [3.0, 2.0] {
            if let fitted = try? FontLabTraceSmoothing.fit(glyph, units: units, refitDenseCurves: true) { return fitted }
        }
        return glyph
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
            for i in 0...501 {
                let inside = i <= 500 && path.contains(CGPoint(x: Double(i) * 2, y: y * 1_000), using: .winding, transform: .identity)
                if inside && start == nil { start = i }
                if !inside, let first = start {
                    let run = Double(i - first) / 500 * glyph.resolvedDesignWidth
                    if (0.006...0.15).contains(run) { widths.append(run) }
                    start = nil
                }
            }
        }
        let sorted = widths.filter(\.isFinite).sorted()
        return min(0.12, max(0.012, sorted.isEmpty ? 0.064 : sorted[sorted.count / 2]))
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

    private static func template(_ character: String, style: FontLabStarterStyle, preserveWeight: Bool = false) -> FontLabGlyph? {
        let baseWidth: Double
        switch character {
        case "M", "W": baseWidth = 0.84
        case "I": baseWidth = 0.34
        case "J": baseWidth = 0.50
        case "m", "w": baseWidth = 0.82
        case "i", "l": baseWidth = 0.29
        case "j": baseWidth = 0.40
        case "f", "r", "t": baseWidth = 0.43
        default: baseWidth = character == character.uppercased() ? 0.65 : 0.57
        }
        let isUpper = character == character.uppercased()
        let width = style.width(baseWidth, character: character)
        // A very short x-height cannot fit a stroke measured from a tall cap.
        // Keep the proposed outline inside the user's guides in that case.
        // The editable box has strict anchor bounds. Heavy strokes and square
        // terminals can push a diagonal or descender just outside that box.
        // Keep the measured style whenever it fits; only taper a troublesome
        // letter enough to produce valid, exportable contours.
        let opticalWeight = ["S", "s"].contains(character) ? style.safeWeight * 0.78 : style.safeWeight
        let caps: [CGLineCap] = style.terminalCap == .round ? [.round] : [.square, .round]
        for cap in caps {
            for fraction in [1.0, 0.90, 0.80, 0.68, 0.55, 0.42] {
                // Narrow, heavy A constructions otherwise overlap above the bar
                // and close the counter. Reserve a useful aperture before stroking.
                let fittedWeight = max(0.008, min(opticalWeight * fraction, character == "A" ? width * 0.24 : .infinity))
                // The source width measures ink, whereas skeleton x values
                // include margins. Solve the construction width before fitting
                // the ink box; otherwise that fit thickens every vertical stem.
                let inset = isUpper ? style.upperInsets : style.lowerInsets
                let targetInkWidth = width * (abs(style.slant) < 0.12 ? 1-inset.0-inset.1 : 1)
                var constructionWidth = width
                var outlines: [FontLabVectorPath]?
                for _ in 0..<(preserveWeight ? 3 : 1) {
                    var shape = FontLabStarterSkeleton(width: constructionWidth, metrics: style.metrics, weight: fittedWeight,
                                                       terminalCap: cap, descenderDepth: style.descenderDepth, plainStem: style.plainStem && style.fixedAdvance == nil)
                    shape.draw(character)
                    guard let candidate = shape.outlines(), !candidate.isEmpty else { outlines = nil; break }
                    outlines = candidate
                    let ink = CGMutablePath(); candidate.forEach { ink.addPath($0.cgPath) }
                    let inkWidth = ink.boundingBoxOfPath.width / 1000 * constructionWidth
                    guard inkWidth > 0 else { break }
                    constructionWidth *= targetInkWidth / inkWidth
                }
                guard var paths = outlines, !paths.isEmpty else { continue }
                // Carry the measured stem lean into constructed letters.
                func lean(_ p: FontLabPoint) -> FontLabPoint {
                    .init(x:p.x + style.slant * (p.y - style.metrics.baseline) / width,y:p.y)
                }
                for p in paths.indices { for n in paths[p].nodes.indices {
                    paths[p].nodes[n].point = lean(paths[p].nodes[n].point)
                    paths[p].nodes[n].incoming = paths[p].nodes[n].incoming.map(lean)
                    paths[p].nodes[n].outgoing = paths[p].nodes[n].outgoing.map(lean)
                } }
                // Skeleton coordinates include construction margins. Those
                // margins must not become extra side bearings: the measured
                // source width is an ink width, so fit the actual ink to it.
                let outline = CGMutablePath()
                paths.forEach { outline.addPath($0.cgPath) }
                let box = outline.boundingBoxOfPath
                let left = abs(style.slant) < 0.12 ? inset.0 : 0
                let right = abs(style.slant) < 0.12 ? inset.1 : 0
                guard box.width > 0 else { continue }
                func align(_ p: FontLabPoint) -> FontLabPoint {
                    .init(x: min(1, max(0, left + (1-left-right) * (p.x * 1000 - box.minX) / box.width)), y: p.y)
                }
                for p in paths.indices { for n in paths[p].nodes.indices {
                    paths[p].nodes[n].point = align(paths[p].nodes[n].point)
                    // Handles may legitimately lie outside the ink box.
                    func handle(_ h: FontLabPoint) -> FontLabPoint { .init(x:left + (1-left-right) * (h.x * 1000 - box.minX) / box.width,y:h.y) }
                    paths[p].nodes[n].incoming = paths[p].nodes[n].incoming.map(handle)
                    paths[p].nodes[n].outgoing = paths[p].nodes[n].outgoing.map(handle)
                } }
                let glyph = FontLabGlyph(character: character, strokes: [FontLabStroke(vectorPaths: paths)],
                                         leftSideBearing: style.bearing(character, left: true),
                                         rightSideBearing: style.bearing(character, left: false),
                                         contourDesignWidth: width)
                if glyph.isValid && glyph.hasArtwork { return glyph }
            }
        }
        return nil
    }
}

private struct FontLabStarterStyle {
    let metrics: FontLabMetrics
    let weight: Double
    let uppercaseWidth: Double
    let lowercaseWidth: Double
    let upperLeftBearing: Double
    let upperRightBearing: Double
    let lowerLeftBearing: Double
    let lowerRightBearing: Double
    let terminalCap: CGLineCap
    let descenderDepth: Double
    let upperInsets: (Double, Double)
    let lowerInsets: (Double, Double)
    let slant: Double
    let fixedAdvance: Double?
    let capStemWidth: Double?
    let capRoundWidth: Double?
    let lowerStemWidth: Double?
    let roundBearings: (Double, Double)?
    let plainStem: Bool

    var safeWeight: Double { min(weight, (metrics.xHeight - metrics.baseline) * 0.65) }

    init(project: FontLabProject, sources: [String: FontLabGlyph], weight: Double) {
        metrics = project.metrics
        self.weight = weight
        capStemWidth = sources["H"]?.resolvedDesignWidth
        capRoundWidth = sources["O"]?.resolvedDesignWidth
        lowerStemWidth = sources["n"]?.resolvedDesignWidth
        roundBearings = sources["O"].map { ($0.leftSideBearing, $0.rightSideBearing) }
        // A plain H stem has no substantial foot flare. Detect from ink, not
        // node count, which varies dramatically between direct and traced art.
        if let h = sources["H"] {
            let ink = CGMutablePath(); FontLabVectorMath.paths(in: h).forEach { ink.addPath($0.cgPath) }
            let box = ink.boundingBoxOfPath
            func firstRun(_ fraction: Double) -> Double {
                var start: Int?
                for x in 0...1000 {
                    let inside = x < 1000 && ink.contains(CGPoint(x: Double(x), y: box.minY + box.height*fraction))
                    if inside && start == nil { start = x }
                    if !inside, let start { return Double(x-start) }
                }
                return 0
            }
            let foot = firstRun(0.025), stem = firstRun(0.25)
            plainStem = stem > 0 && foot > stem*0.75 && foot < stem*1.25
        } else { plainStem = false }
        func median(_ values: [Double]) -> Double? {
            let values = values.filter { $0.isFinite }.sorted()
            return values.isEmpty ? nil : values[values.count / 2]
        }
        let regularCaps = Array("HNOXCDPRSU").map(String.init).compactMap { sources[$0] }
        let regularLower = Array("nopabhduce").map(String.init).compactMap { sources[$0] }
        let caps = regularCaps.isEmpty ? sources.filter { $0.key == $0.key.uppercased() }.map(\.value) : regularCaps
        let lower = regularLower.isEmpty ? sources.filter { $0.key == $0.key.lowercased() }.map(\.value) : regularLower
        let advances = sources.values.map { $0.resolvedDesignWidth + $0.leftSideBearing + $0.rightSideBearing }
        fixedAdvance = !caps.isEmpty && !lower.isEmpty && advances.count >= 3 && (advances.max()! - advances.min()!) < 0.006 ? median(advances) : nil
        let capWidth = median(caps.map(\.resolvedDesignWidth))
        let lowerWidth = median(lower.map(\.resolvedDesignWidth))
        uppercaseWidth = min(2.2, max(0.32, capWidth ?? lowerWidth.map { $0 / 0.88 } ?? 0.65))
        lowercaseWidth = min(2.0, max(0.25, lowerWidth ?? capWidth.map { $0 * 0.88 } ?? 0.57))
        let upperBearings = caps.isEmpty ? lower : caps
        let lowerBearings = lower.isEmpty ? caps : lower
        upperLeftBearing = median(upperBearings.map(\.leftSideBearing)) ?? 0.075
        upperRightBearing = median(upperBearings.map(\.rightSideBearing)) ?? 0.075
        lowerLeftBearing = median(lowerBearings.map(\.leftSideBearing)) ?? 0.075
        lowerRightBearing = median(lowerBearings.map(\.rightSideBearing)) ?? 0.075
        func extent(_ glyph: FontLabGlyph, _ y: Double) -> (Double,Double)? {
            let path=CGMutablePath()
            FontLabVectorMath.paths(in:glyph).forEach { path.addPath($0.cgPath) }
            let samples=(0...500).filter { path.contains(CGPoint(x:Double($0)*2,y:y*1000)) }
            guard let first=samples.first,let last=samples.last else {return nil}
            return (Double(first)/500,Double(last)/500)
        }
        func insets(_ glyph: FontLabGlyph?, top: Double) -> (Double,Double) {
            guard let glyph, let edge=extent(glyph,project.metrics.baseline+(top-project.metrics.baseline)*0.3) else {return (0,0)}
            return (min(0.20,edge.0),min(0.20,1-edge.1))
        }
        upperInsets=insets(sources["H"],top:metrics.capHeight)
        lowerInsets=insets(sources["n"],top:metrics.xHeight)
        var slopes:[Double]=[]
        for (character,top) in [("H",metrics.capHeight),("n",metrics.xHeight),("p",metrics.xHeight)] {
            guard let glyph=sources[character] else {continue}
            let low=metrics.baseline+(top-metrics.baseline)*0.25,high=metrics.baseline+(top-metrics.baseline)*0.65
            if let a=extent(glyph,low),let b=extent(glyph,high) { slopes.append((b.0-a.0)*glyph.resolvedDesignWidth/(high-low)) }
        }
        slant=min(0.65,max(-0.65,median(slopes) ?? 0))
        let stem = ["H", "h", "n", "p"].compactMap { sources[$0] }.first
        if let stem {
            let paths = FontLabVectorMath.paths(in: stem)
            let nodes = paths.flatMap(\.nodes)
            let angular = !nodes.isEmpty && nodes.count <= 40 &&
                Double(nodes.filter { $0.incoming == nil && $0.outgoing == nil }.count) / Double(nodes.count) >= 0.7
            terminalCap = angular ? .square : .round
        } else {
            terminalCap = .round
        }
        let descenders = ["p", "q", "g", "j", "y"].compactMap { sources[$0] }.compactMap { glyph -> Double? in
            let points = glyph.strokes.flatMap { stroke -> [FontLabPoint] in
                stroke.points + (stroke.contours?.flatMap { $0 } ?? []) +
                    (stroke.vectorPaths?.flatMap { $0.nodes.map(\.point) } ?? [])
            }
            return points.map(\.y).min()
        }.filter { $0 < project.metrics.baseline }
        let observed = descenders.map { (project.metrics.baseline - $0) / (project.metrics.capHeight - project.metrics.baseline) }
        descenderDepth = min(0.38, max(0.015, median(observed) ?? min(0.25, max(0.015, (project.metrics.baseline - 0.012) / (project.metrics.capHeight - project.metrics.baseline)))))
    }

    func width(_ base: Double, uppercase: Bool) -> Double {
        if let fixedAdvance {
            return max(0.02, fixedAdvance - leftBearing(uppercase:uppercase) - rightBearing(uppercase:uppercase))
        }
        return min(2.5, max(0.22, base * (uppercase ? uppercaseWidth / 0.65 : lowercaseWidth / 0.57)))
    }
    func width(_ base: Double, character: String) -> Double {
        min(2.5, max(0.02, anatomicalWidth(base, character: character)))
    }
    private func anatomicalWidth(_ base: Double, character: String) -> Double {
        let upper = character == character.uppercased()
        guard fixedAdvance == nil else { return width(base, uppercase: upper) }
        if character == "I", plainStem { return weight }
        if let h = capStemWidth, let o = capRoundWidth {
            switch character {
            case "A", "V", "Y": return max(h * 1.10, o * 0.92)
            case "W": return max(h * 1.55, o * 1.28)
            case "X": return max(h * 1.05, o * 0.90)
            case "M": return h * 1.30
            case "B", "P", "R": return h * 0.95
            case "D", "G": return o * 0.98
            case "E", "F": return h * 0.88
            case "L": return h * 0.80
            case "T": return h * 1.04
            case "U", "N": return h
            case "S": return o * 0.82
            case "I" where plainStem: return weight
            case "J": return h * 0.72
            default: break
            }
        }
        if let n = lowerStemWidth {
            switch character {
            case "h", "k": return n
            case "f", "r", "t": return n * 0.72
            case "i" where plainStem, "l" where plainStem: return weight
            default: break
            }
        }
        return width(base, uppercase: upper)
    }
    func bearing(_ character: String, left: Bool) -> Double {
        let upper = character == character.uppercased()
        let fallback = left ? leftBearing(uppercase: upper) : rightBearing(uppercase: upper)
        guard fixedAdvance == nil, upper, let roundBearings else { return fallback }
        let round = left ? roundBearings.0 : roundBearings.1
        // Diagonals and overhanging top bars need less optical side space.
        if "AVWXYT".contains(character) { return min(fallback, round * 0.15) }
        if "CGOSQ".contains(character) { return round }
        return fallback
    }
    func leftBearing(uppercase: Bool) -> Double { uppercase ? upperLeftBearing : lowerLeftBearing }
    func rightBearing(uppercase: Bool) -> Double { uppercase ? upperRightBearing : lowerRightBearing }
}

private struct FontLabStarterDerivation {
    let glyph: FontLabGlyph
    let sources: [String]
    let method: String
    let explanation: String
}

private extension FontLabStarterAssist {
    static func sourceDerived(_ character: String, sources: [String: FontLabGlyph], style: FontLabStarterStyle, reuseCapStems: Bool) -> FontLabStarterDerivation? {
        if reuseCapStems, ["D", "E", "F", "I", "L"].contains(character), abs(style.slant) < 0.12,
           character != "I" || style.fixedAdvance == nil,
           let source = sources["H"], let glyph = reusingCapStem(source, bowl: sources["O"], character: character, style: style) {
            return .init(glyph: glyph, sources: character == "D" ? ["H", "O"] : ["H"], method: "Reused cap stem",
                         explanation: character == "D" ? "The drawn H supplies the stem and terminals; the O supplies the right-hand curve. Review the joins and spacing." : "The drawn H supplies the stem and its terminals. Any new horizontal arms use its crossbar thickness; review their lengths and ends.")
        }
        let horizontalPairs = ["p":"q", "q":"p", "b":"d", "d":"b"]
        if let sourceCharacter = horizontalPairs[character], let source = sources[sourceCharacter], exportable(source),
           let glyph = transformed(source, to: character, width: source.resolvedDesignWidth,
                                   x: { 1 - $0 }, y: { $0 }, swapBearings: true, reverseWinding: true, horizontalSlant: style.slant) {
            return .init(glyph: glyph, sources: [sourceCharacter], method: "Mirrored outline",
                         explanation: "The drawn \(sourceCharacter) contours were reflected horizontally. The curves and stroke character are retained; check the letter's terminals and spacing.")
        }
        // Reuse a complete stem/bowl join when an ascender/descender partner
        // exists. Adding a generic stem to o discards that characteristic join.
        let stemPartners: [String: [(String, Bool)]] = [
            "b": [("p", false), ("q", true)], "d": [("q", false), ("p", true)],
            "p": [("b", false), ("d", true)], "q": [("d", false), ("b", true)]
        ]
        for (origin, horizontal) in (abs(style.slant) < 0.12 ? stemPartners[character] ?? [] : []) {
            guard let source = sources[origin], exportable(source) else { continue }
            if let glyph = transformed(source, to: character, width: source.resolvedDesignWidth,
                                       x: { horizontal ? 1 - $0 : $0 },
                                       y: { style.metrics.baseline + style.metrics.xHeight - $0 },
                                       swapBearings: horizontal, reverseWinding: !horizontal, verticalSlant: style.slant,
                                       horizontalSlant: horizontal ? style.slant : 0) {
                return .init(glyph: glyph, sources: [origin], method: "Reflected stem and bowl",
                             explanation: "The drawn \(origin) stem, bowl and join were reflected into \(character). Review the reflected curve balance and ascender or descender length.")
            }
        }
        let verticalPairs = ["n":"u", "u":"n"]
        if let sourceCharacter = verticalPairs[character], let source = sources[sourceCharacter], exportable(source) {
            let top = character == character.uppercased() ? style.metrics.capHeight : style.metrics.xHeight
            if let glyph = transformed(source, to: character, width: source.resolvedDesignWidth,
                                       x: { $0 }, y: { style.metrics.baseline + top - $0 },
                                       reverseWinding: true, verticalSlant: style.slant) {
                return .init(glyph: glyph, sources: [sourceCharacter], method: "Mirrored outline",
                             explanation: "The drawn \(sourceCharacter) contours were reflected vertically between the baseline and \(character == character.uppercased() ? "cap" : "x") height. Review joins and optical balance.")
            }
        }

        // A bowl source may come from the other case. Scale that actual outline
        // once, then make the letter-specific change. No proposed glyph is used
        // as an input to another proposal in the same review session.
        func bowl(_ uppercase: Bool) -> (FontLabGlyph, String)? {
            let preferred = uppercase ? "O" : "o", alternate = uppercase ? "o" : "O"
            if let source = sources[preferred], exportable(source) { return (source, preferred) }
            if let source = sources[alternate], exportable(source),
               let scaled = adapted(source, to: preferred, metrics: style.metrics) { return (scaled, alternate) }
            return nil
        }
        if character == "C" || character == "c", let (source, origin) = bowl(character == "C"),
           let glyph = openedBowl(source, to: character) {
            return .init(glyph: glyph, sources: [origin], method: "Reused bowl with aperture",
                         explanation: "The drawn \(origin) curves form this C-shaped bowl. A right-side aperture was cut into a copy; refine the two new terminals.")
        }
        if character == "e", let (source, origin) = bowl(false),
           let outline = closedOutline(source), let box = inkBounds(source) {
            let crossbarY = box.minY + box.height * 0.51
            let thickness = min(style.safeWeight, box.height * 0.18)
            let notch = CGPath(rect: CGRect(x: (box.midX + box.width * 0.05) * 1000,
                                           y: (crossbarY - box.height * 0.21) * 1000,
                                           width: box.width * 1000, height: box.height * 0.21 * 1000), transform: nil)
            let bar = CGPath(rect: CGRect(x: (box.minX + box.width * 0.08) * 1000,
                                         y: crossbarY * 1000, width: box.width * 0.86 * 1000,
                                         height: thickness * 1000), transform: nil)
            let ink = outline.subtracting(notch, using: .winding).union(bar, using: .winding)
            let paths = FontLabVectorPath.from(ink)
            let glyph = FontLabGlyph(character: character, strokes: [FontLabStroke(vectorPaths: paths)],
                                     leftSideBearing: source.leftSideBearing, rightSideBearing: source.rightSideBearing,
                                     contourDesignWidth: source.resolvedDesignWidth)
            if glyph.isValid && glyph.hasArtwork {
                return .init(glyph: glyph, sources: [origin], method: "Reused bowl with crossbar",
                             explanation: "The drawn \(origin) provides the e curves and counter. A crossbar and lower-right opening were added; review the aperture and crossbar angle.")
            }
        }
        if character == "G", sources["C"] == nil, let (source, origin) = bowl(true), let opened = openedBowl(source, to: character),
           let box = inkBounds(opened), let outline = closedOutline(opened) {
            let localWeight = sideStrokeWeight(source, at: box.midY, right: true) ?? style.safeWeight
            let bar = CGPath(rect: CGRect(x: (box.midX + box.width * 0.04) * 1000,
                                         y: (box.midY - localWeight * 0.5) * 1000,
                                         width: box.width * 0.46 * 1000, height: localWeight * 1000), transform: nil)
            let vertical = CGPath(rect: CGRect(x: (box.maxX - localWeight / source.resolvedDesignWidth) * 1000,
                                              y: (box.minY + box.height * 0.22) * 1000,
                                              width: localWeight / source.resolvedDesignWidth * 1000,
                                              height: (box.height * 0.28 + localWeight * 0.5) * 1000), transform: nil)
            let paths = FontLabVectorPath.from(outline.union(bar, using: .winding).union(vertical, using: .winding))
            let glyph = FontLabGlyph(character: character, strokes: [FontLabStroke(vectorPaths: paths)],
                                     leftSideBearing: source.leftSideBearing, rightSideBearing: source.rightSideBearing,
                                     contourDesignWidth: source.resolvedDesignWidth)
            if glyph.isValid && glyph.hasArtwork {
                return .init(glyph: glyph, sources: [origin], method: "Reused bowl with crossbar",
                             explanation: "The drawn \(origin) supplies the G curves. An aperture and crossbar were added; review the spur and terminals.")
            }
        }
        if character == "Q", let (source, origin) = bowl(true),
           let box = inkBounds(source),
           let glyph = appending(source, to: character, style: style,
                                 points: [.init(x: box.minX + box.width * 0.62, y: box.minY + box.height * 0.25),
                                          .init(x: min(0.94, box.maxX + box.width * 0.09),
                                                y: max(style.safeWeight * 0.7 + 0.01, box.minY - box.height * 0.12))]) {
            return .init(glyph: glyph, sources: [origin], method: "Reused outline with feature",
                         explanation: "The drawn \(origin) bowl is retained and an editable diagonal tail was added. Adjust its angle and join to suit your design.")
        }
        if character == "R", let source = sources["P"], exportable(source), let box = inkBounds(source),
           let glyph = appending(source, to: character, style: style,
                                 points: [.init(x: box.midX, y: box.midY),
                                          .init(x: min(0.94, box.maxX), y: max(style.metrics.baseline + style.safeWeight * 0.5, box.minY))]) {
            return .init(glyph: glyph, sources: ["P"], method: "Reused outline with feature",
                         explanation: "The drawn P bowl and stem are retained; an editable leg makes an R. Review the leg's join and angle.")
        }
        if character == "G", let source = sources["C"], exportable(source), let box = inkBounds(source),
           let glyph = appending(source, to: character, style: style,
                                 points: [.init(x: box.midX + box.width * 0.03, y: box.midY),
                                          .init(x: min(0.94, box.maxX - box.width * 0.03), y: box.midY)]) {
            return .init(glyph: glyph, sources: ["C"], method: "Reused outline with feature",
                         explanation: "The drawn C outline is retained and an editable crossbar was added. Check its connection and right terminal.")
        }
        if character == "h", let source = sources["n"], exportable(source), let box = inkBounds(source),
           let ink = closedOutline(source) {
            let probeY = box.minY + box.height * 0.65
            let occupied = (0...1000).filter { ink.contains(CGPoint(x: Double($0), y: probeY * 1000)) }
            let first = occupied.first ?? Int(box.minX * 1000)
            let stemWeight = sideStrokeWeight(source, at: probeY, right: false) ?? style.safeWeight
            let x = Double(first)/1000 + stemWeight/source.resolvedDesignWidth * 0.5
            let top = style.metrics.capHeight - stemWeight * 0.5
            if let glyph = appending(source, to: character, style: style,
                                     points: [.init(x: x, y: probeY),
                                              .init(x: x + style.slant * (top-probeY)/source.resolvedDesignWidth, y: top)],
                                     strokeWidth: stemWeight) {
                return .init(glyph: glyph, sources: ["n"], method: "Reused outline with feature",
                             explanation: "The drawn n arch is retained and its left stem is extended to cap height. Check the join and top terminal.")
            }
        }
        if character == "m", let source = sources["n"], exportable(source),
           var glyph = repeatedN(source, weight: style.safeWeight) {
            if let advance = style.fixedAdvance {
                glyph.contourDesignWidth = max(0.02, advance - glyph.leftSideBearing - glyph.rightSideBearing)
            }
            return .init(glyph: glyph, sources: ["n"], method: "Repeated source outline",
                         explanation: "Two independent copies of the drawn n outline form the m arches, fitted to a shared advance when the references are monospaced. Edit the middle join and side bearings as needed.")
        }

        if ["a", "b", "d", "p", "q"].contains(character), let (source, origin) = bowl(false),
           let box = inkBounds(source) {
            let right = ["a", "d", "q"].contains(character)
            // The bowl may have been scaled from the other case. Its local
            // side stroke is then the right reference for a joined stem; the
            // cap/control-letter weight can be visibly heavier than that bowl.
            let sideWeight = sideStrokeWeight(source, at: box.midY, right: right)
            let featureWeight = max(0.006, min(style.safeWeight, (sideWeight ?? style.safeWeight) * 0.88))
            let x = right
                ? box.maxX - featureWeight / max(source.resolvedDesignWidth, 0.1) * 0.5
                : box.minX + featureWeight / max(source.resolvedDesignWidth, 0.1) * 0.5
            let top = ["b", "d"].contains(character) ? style.metrics.capHeight : style.metrics.xHeight
            let bottom = ["p", "q"].contains(character)
                ? max(featureWeight * 0.5 + 0.012, style.metrics.baseline - style.descenderDepth * (style.metrics.capHeight - style.metrics.baseline))
                : style.metrics.baseline
            if let glyph = appending(source, to: character, style: style,
                                     points: [.init(x: x, y: bottom + featureWeight * 0.5),
                                              .init(x: x, y: top - featureWeight * 0.5)],
                                     strokeWidth: featureWeight) {
                return .init(glyph: glyph, sources: [origin], method: "Reused bowl with stem",
                             explanation: "The drawn \(origin) bowl is retained and an editable \(["p", "q"].contains(character) ? "descender" : ["b", "d"].contains(character) ? "ascender" : "stem") was added. Refine the join and spacing.")
            }
        }
        return nil
    }

    /// Work in physical coordinates so extracting a narrow stem never stretches
    /// its weight or serif. Only the supplied H is inspected.
    static func reusingCapStem(_ source: FontLabGlyph, bowl: FontLabGlyph?, character: String, style: FontLabStarterStyle) -> FontLabGlyph? {
        guard let outline = closedOutline(source) else { return nil }
        var physical = CGAffineTransform(scaleX: source.resolvedDesignWidth, y: 1)
        guard let ink = outline.copy(using: &physical) else { return nil }
        let box = ink.boundingBoxOfPath
        guard box.height > 100, box.width > 40 else { return nil }
        func runs(_ fraction: Double) -> [(Double, Double)] {
            var result: [(Double, Double)] = [], start: Double?
            for i in 0...600 {
                let x = box.minX + box.width * Double(i) / 600
                let inside = i < 600 && ink.contains(CGPoint(x: x, y: box.minY + box.height * fraction))
                if inside && start == nil { start = x }
                if !inside, let first = start { result.append((first, x)); start = nil }
            }
            return result
        }
        let low = runs(0.25), high = runs(0.75), foot = runs(0.025)
        guard low.count == 2, high.count == 2, foot.count == 2,
              foot[0].1-foot[0].0 >= (low[0].1-low[0].0)*0.75 else { return nil }
        let stemRight = (low[0].1 + high[0].1) / 2
        let gapX = (max(low[0].1, high[0].1) + min(low[1].0, high[1].0)) / 2
        guard gapX > stemRight, abs(low[0].1-high[0].1) < box.width * 0.04 else { return nil }
        let rows = (20...80).filter { ink.contains(CGPoint(x: gapX, y: box.minY + box.height * Double($0)/100)) }
        guard let first = rows.first, let last = rows.last, rows.count == last-first+1,
              rows.count >= 2, rows.count <= 25 else { return nil }
        func edge(_ a: Double, _ b: Double, entering: Bool) -> Double {
            var low = a, high = b
            for _ in 0..<24 {
                let middle = (low+high)/2
                if ink.contains(CGPoint(x: gapX, y: middle)) == entering { high = middle }
                else { low = middle }
            }
            return (low+high)/2
        }
        let barBottom = edge(box.minY+box.height*Double(first-1)/100, box.minY+box.height*Double(first)/100, entering: true)
        let barTop = edge(box.minY+box.height*Double(last)/100, box.minY+box.height*Double(last+1)/100, entering: false)
        let clip = CGPath(rect: CGRect(x: box.minX-1, y: box.minY-1, width: gapX-box.minX+1, height: box.height+2), transform: nil)
        let removal = CGPath(rect: CGRect(x: stemRight, y: barBottom-0.05, width: gapX-stemRight+1, height: barTop-barBottom+0.1), transform: nil)
        var result = ink.intersection(clip, using: .winding).subtracting(removal, using: .winding)
        let stemBox = result.boundingBoxOfPath
        guard stemBox.width > 0, stemBox.width < box.width * 0.48 else { return nil }
        if character == "D" {
            guard let bowl, let rawBowl = closedOutline(bowl) else { return nil }
            var physicalBowl = CGAffineTransform(scaleX: bowl.resolvedDesignWidth, y: 1)
            guard let round = rawBowl.copy(using: &physicalBowl) else { return nil }
            let roundBox = round.boundingBoxOfPath
            guard roundBox.width > 20, roundBox.height > 100 else { return nil }
            let width = style.plainStem && style.fixedAdvance == nil ? roundBox.width*0.85 : style.width(0.65, character: character)*roundBox.width/bowl.resolvedDesignWidth
            let sx = width/roundBox.width, sy = box.height/roundBox.height
            var transform = CGAffineTransform(a: sx, b: 0, c: 0, d: sy,
                                               tx: stemBox.minX+width-roundBox.maxX*sx, ty: box.minY-roundBox.minY*sy)
            let half = CGPath(rect: CGRect(x: roundBox.midX, y: roundBox.minY-1, width: roundBox.width, height: roundBox.height+2), transform: nil)
            guard let arc = round.intersection(half, using: .winding).copy(using: &transform) else { return nil }
            let samples = Set((0...1000).filter { round.contains(CGPoint(x: roundBox.midX, y: roundBox.minY+roundBox.height*Double($0)/1000)) })
            let lowerEnd = (1..<500).first { !samples.contains($0) } ?? 0
            let upperStart = (501..<1000).first { samples.contains($0) } ?? 1000
            let bottom = roundBox.height*Double(lowerEnd)/1000*sy
            let top = roundBox.height*Double(1000-upperStart)/1000*sy
            guard bottom > 2, top > 2, bottom < box.height*0.25, top < box.height*0.25 else { return nil }
            let left = (low[0].0+low[0].1)/2, right = roundBox.midX*sx+transform.tx
            guard right > left else { return nil }
            result = result.union(arc, using: .winding)
                .union(CGPath(rect: CGRect(x: left, y: box.minY, width: right-left+0.1, height: bottom), transform: nil), using: .winding)
                .union(CGPath(rect: CGRect(x: left, y: box.maxY-top, width: right-left+0.1, height: top), transform: nil), using: .winding)
        } else if character != "I" {
            let width = style.width(0.65, character: character)*box.width/source.resolvedDesignWidth
            let thickness = barTop-barBottom
            let left = (low[0].0+low[0].1)/2
            let right = stemBox.minX + width
            func arm(_ y: Double, _ length: Double) -> CGPath {
                CGPath(rect: CGRect(x: left, y: y, width: (right-left)*length, height: thickness), transform: nil)
            }
            if character == "E" || character == "F" {
                result = result.union(arm(box.maxY-thickness, 1), using: .winding)
                result = result.union(arm(barBottom, 0.80), using: .winding)
            }
            if character == "E" || character == "L" {
                result = result.union(arm(box.minY, 1), using: .winding)
            }
        }
        let bounds = result.boundingBoxOfPath
        guard bounds.width > 0 else { return nil }
        var normalized = CGAffineTransform(a: 1000/bounds.width, b: 0, c: 0, d: 1, tx: -bounds.minX*1000/bounds.width, ty: 0)
        guard let path = result.copy(using: &normalized) else { return nil }
        let paths = FontLabVectorPath.from(path)
        let bearing: Double
        if let advance = style.fixedAdvance { bearing = max(0, (advance-bounds.width/1000)/2) }
        else { bearing = source.leftSideBearing + max(0, bounds.minX/1000) }
        // Clamping a reboxed bearing would silently translate the copied ink
        // or shrink a monospaced advance. Keep the original construction instead.
        guard bearing <= 0.4 else { return nil }
        let glyph = FontLabGlyph(character: character, strokes: [FontLabStroke(vectorPaths: paths)],
                                 leftSideBearing: bearing, rightSideBearing: bearing,
                                 contourDesignWidth: bounds.width/1000)
        return glyph.isValid && glyph.hasArtwork ? glyph : nil
    }

    static func exportable(_ glyph: FontLabGlyph) -> Bool {
        glyph.hasArtwork && glyph.isValid &&
            !glyph.strokes.contains { $0.vectorPaths?.contains(where: { !$0.closed }) == true }
    }

    static func transformed(_ source: FontLabGlyph, to character: String, width: Double,
                            x: (Double) -> Double, y: (Double) -> Double,
                            swapBearings: Bool = false, reverseWinding: Bool = false, verticalSlant: Double = 0, horizontalSlant: Double = 0) -> FontLabGlyph? {
        let centerY = inkBounds(source)?.midY ?? 0.5
        func map(_ value: FontLabPoint) -> FontLabPoint {
            var point = value; point.x = x(value.x); point.y = y(value.y)
            // Reflect the vertical structure in deskewed space, then restore
            // the source lean. A direct y reflection reverses italic stems.
            point.x += verticalSlant * (point.y - value.y) / width
            // Horizontal reflection also reverses the lean. Reflect in a
            // deskewed frame centered on the source ink, then restore it.
            point.x += 2 * horizontalSlant * (value.y - centerY) / width
            return point
        }
        var strokes = FontLabDesign.detachedStrokes(source.strokes)
        for index in strokes.indices {
            strokes[index].points = strokes[index].points.map(map)
            strokes[index].contours = strokes[index].contours?.map { contour in
                let transformed = contour.map(map)
                return reverseWinding ? Array(transformed.reversed()) : transformed
            }
            if var paths = strokes[index].vectorPaths {
                for p in paths.indices { for n in paths[p].nodes.indices {
                    paths[p].nodes[n].point = map(paths[p].nodes[n].point)
                    paths[p].nodes[n].incoming = paths[p].nodes[n].incoming.map(map)
                    paths[p].nodes[n].outgoing = paths[p].nodes[n].outgoing.map(map)
                } }
                if reverseWinding { for p in paths.indices where paths[p].closed { paths[p].reverse() } }
                strokes[index].vectorPaths = paths
            }
        }
        // Deskewing can extend a reflected outline beyond its original x
        // box. Rebox without clipping or stretching its physical geometry.
        let vector = strokes.flatMap { $0.vectorPaths ?? [] }
        let anchorX = vector.flatMap(\.nodes).map { $0.point.x } + strokes.flatMap { $0.contours?.flatMap { $0.map(\.x) } ?? [] }
        let minX = min(0, anchorX.min() ?? 0), maxX = max(1, anchorX.max() ?? 1), span = maxX-minX
        if minX < 0 || maxX > 1 {
            func rebox(_ p: FontLabPoint) -> FontLabPoint { .init(x: min(1,max(0,(p.x-minX)/span)), y: p.y) }
            func handle(_ p: FontLabPoint) -> FontLabPoint { .init(x: (p.x-minX)/span, y: p.y) }
            for i in strokes.indices {
                strokes[i].contours = strokes[i].contours?.map { $0.map(rebox) }
                if var paths = strokes[i].vectorPaths {
                    for p in paths.indices { for n in paths[p].nodes.indices {
                        paths[p].nodes[n].point = rebox(paths[p].nodes[n].point)
                        paths[p].nodes[n].incoming = paths[p].nodes[n].incoming.map(handle)
                        paths[p].nodes[n].outgoing = paths[p].nodes[n].outgoing.map(handle)
                    } }
                    strokes[i].vectorPaths = paths
                }
            }
        }
        let glyph = FontLabGlyph(character: character, strokes: strokes,
                                 leftSideBearing: swapBearings ? source.rightSideBearing : source.leftSideBearing,
                                 rightSideBearing: swapBearings ? source.leftSideBearing : source.rightSideBearing,
                                 contourDesignWidth: width * span)
        return glyph.isValid && glyph.hasArtwork ? glyph : nil
    }

    static func inkBounds(_ glyph: FontLabGlyph) -> CGRect? {
        if let outline = closedOutline(glyph) {
            let bounds = outline.boundingBoxOfPath
            let box = CGRect(x: bounds.minX / 1_000, y: bounds.minY / 1_000,
                             width: bounds.width / 1_000, height: bounds.height / 1_000)
            if box.width > 0.02 && box.height > 0.02 { return box }
        }
        let points = glyph.strokes.flatMap { stroke -> [FontLabPoint] in
            stroke.points + (stroke.contours?.flatMap { $0 } ?? []) +
                (stroke.vectorPaths?.flatMap { path in path.nodes.map(\.point) } ?? [])
        }
        guard !points.isEmpty else { return nil }
        let box = FontLabVectorMath.bounds(points)
        return box.width > 0.02 && box.height > 0.02 ? box : nil
    }

    static func closedOutline(_ glyph: FontLabGlyph) -> CGPath? {
        guard exportable(glyph), glyph.strokes.allSatisfy({ $0.points.isEmpty }) else { return nil }
        let paths = FontLabVectorMath.paths(in: glyph)
        guard !paths.isEmpty && paths.allSatisfy(\.closed) else { return nil }
        let combined = CGMutablePath()
        for path in paths { combined.addPath(path.cgPath) }
        return combined
    }

    static func sideStrokeWeight(_ glyph: FontLabGlyph, at y: Double, right: Bool) -> Double? {
        guard let outline = closedOutline(glyph) else { return nil }
        var runs: [Double] = []
        var start: Int?
        for i in 0...501 {
            let inside = i <= 500 && outline.contains(CGPoint(x: Double(i) * 2, y: y * 1_000),
                                          using: .winding, transform: .identity)
            if inside && start == nil { start = i }
            if !inside, let first = start {
                runs.append(Double(i - first) / 500 * glyph.resolvedDesignWidth)
                start = nil
            }
        }
        guard let value = right ? runs.last : runs.first, (0.006...0.18).contains(value) else { return nil }
        return value
    }

    static func openedBowl(_ source: FontLabGlyph, to character: String) -> FontLabGlyph? {
        guard let outline = closedOutline(source) else { return nil }
        let box = outline.boundingBoxOfPath
        guard box.width > 150 && box.height > 150 else { return nil }
        let start = box.midX + box.width * 0.03
        let notch = CGPath(rect: CGRect(x: start, y: box.minY + box.height * 0.35,
                                      width: box.maxX - start + 100, height: box.height * 0.30), transform: nil)
        let opened = outline.subtracting(notch, using: .winding)
        let paths = FontLabVectorPath.from(opened)
        guard !paths.isEmpty && paths.allSatisfy({ $0.closed && $0.isValid }) else { return nil }
        let glyph = FontLabGlyph(character: character, strokes: [FontLabStroke(vectorPaths: paths)],
                                 leftSideBearing: source.leftSideBearing, rightSideBearing: source.rightSideBearing,
                                 contourDesignWidth: source.resolvedDesignWidth)
        return glyph.isValid && glyph.hasArtwork ? glyph : nil
    }

    static func appending(_ source: FontLabGlyph, to character: String, style: FontLabStarterStyle,
                          points: [FontLabPoint], strokeWidth: Double? = nil) -> FontLabGlyph? {
        guard exportable(source), points.count >= 2 else { return nil }
        let width = source.resolvedDesignWidth
        let addedWidth = strokeWidth ?? style.safeWeight
        let trace = CGMutablePath()
        trace.move(to: CGPoint(x: points[0].x * width * 1_000, y: points[0].y * 1_000))
        for point in points.dropFirst() { trace.addLine(to: CGPoint(x: point.x * width * 1_000, y: point.y * 1_000)) }
        let filled = trace.copy(strokingWithWidth: addedWidth * 1_000, lineCap: style.terminalCap,
                                lineJoin: style.terminalCap == .square ? .miter : .round, miterLimit: 4)
        let normalized = CGMutablePath()
        normalized.addPath(filled, transform: CGAffineTransform(scaleX: 1 / width, y: 1))
        let converted = FontLabVectorPath.from(normalized)
        let paths = converted.isEmpty ? (filledStrip(points: points, glyphWidth: width, strokeWidth: addedWidth).map { [$0] } ?? []) : converted
        guard !paths.isEmpty && paths.allSatisfy(\.closed) else { return nil }
        var strokes = FontLabDesign.detachedStrokes(source.strokes)
        strokes.append(FontLabStroke(vectorPaths: paths))
        let glyph = FontLabGlyph(character: character, strokes: strokes,
                                 leftSideBearing: source.leftSideBearing, rightSideBearing: source.rightSideBearing,
                                 contourDesignWidth: width)
        return transformed(glyph, to: character, width: width, x: { $0 }, y: { $0 })
    }

    /// A four-anchor outline is a safe fallback for a straight feature when
    /// Core Graphics emits a cap curve with out-of-box anchors. It retains the
    /// source contours and uses the measured physical stroke width.
    static func filledStrip(points: [FontLabPoint], glyphWidth: Double, strokeWidth: Double) -> FontLabVectorPath? {
        guard points.count == 2 else { return nil }
        let a = points[0], b = points[1]
        let dx = (b.x - a.x) * glyphWidth, dy = b.y - a.y
        let length = hypot(dx, dy)
        guard length > 0.01 else { return nil }
        let nx = -dy / length * strokeWidth * 0.5
        let ny = dx / length * strokeWidth * 0.5
        let corners = [
            FontLabPoint(x: a.x + nx / glyphWidth, y: a.y + ny),
            FontLabPoint(x: b.x + nx / glyphWidth, y: b.y + ny),
            FontLabPoint(x: b.x - nx / glyphWidth, y: b.y - ny),
            FontLabPoint(x: a.x - nx / glyphWidth, y: a.y - ny)
        ]
        let path = FontLabVectorPath(nodes: corners.map { FontLabVectorNode(point: $0) }, closed: true)
        return path.isValid ? path : nil
    }

    static func repeatedN(_ source: FontLabGlyph, weight: Double) -> FontLabGlyph? {
        guard let box = inkBounds(source), source.resolvedDesignWidth <= 1.65 else { return nil }
        let halfStem = weight / (2 * source.resolvedDesignWidth)
        let leftStemCenter = box.minX + halfStem
        let rightStemCenter = box.maxX - halfStem
        let separation = min(0.85, max(0.25, rightStemCenter - leftStemCenter)) * source.resolvedDesignWidth
        let width = source.resolvedDesignWidth + separation
        guard width <= 3 else { return nil }
        let first = transformed(source, to: "m", width: width,
                                x: { $0 * source.resolvedDesignWidth / width }, y: { $0 })
        let second = transformed(source, to: "m", width: width,
                                 x: { ($0 * source.resolvedDesignWidth + separation) / width }, y: { $0 })
        guard let first, let second else { return nil }
        let glyph = FontLabGlyph(character: "m", strokes: first.strokes + second.strokes,
                                 leftSideBearing: source.leftSideBearing, rightSideBearing: source.rightSideBearing,
                                 contourDesignWidth: width)
        return glyph.isValid && glyph.hasArtwork ? glyph : nil
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
    let terminalCap: CGLineCap
    let descenderDepth: Double
    var plainStem = false
    private let centerlines = CGMutablePath()
    private let solids = CGMutablePath()
    private var capSpan: Double { metrics.capHeight - metrics.baseline }
    // point(y:) places the baseline and cap centerlines half a stroke in from
    // the guides. Solve for the lowercase centerline whose *outer* edge reaches
    // x-height, otherwise lowercase bowls overshoot the guide.
    private var h: Double { (metrics.xHeight - metrics.baseline - weight) / (capSpan - weight) }
    private var d: Double { min(descenderDepth, max(0.015, (metrics.baseline - 0.012) / capSpan)) }

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
        let stroked = centerlines.copy(strokingWithWidth: weight * 1_000, lineCap: terminalCap,
                                       lineJoin: terminalCap == .square ? .miter : .round, miterLimit: 4)
        let combined = CGMutablePath(); combined.addPath(stroked); combined.addPath(solids)
        let normalized = CGMutablePath(); normalized.addPath(combined.normalized(using: .winding), transform: CGAffineTransform(scaleX: 1 / width, y: 1))
        let paths = FontLabVectorPath.from(normalized)
        // Construction margins are not the final glyph box. Wide caps and
        // diagonal joins can extend past x=0/1 before template() fits the ink.
        // Rejecting them here silently retried at a much thinner weight.
        guard !paths.isEmpty, paths.allSatisfy({ path in
            path.closed && path.nodes.count >= 3 && path.nodes.allSatisfy { node in
                node.point.x.isFinite && node.point.y.isFinite && (0...1).contains(node.point.y) &&
                [node.incoming, node.outgoing].compactMap { $0 }.allSatisfy { $0.x.isFinite && $0.y.isFinite }
            }
        }),
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
            stroke([(0.50,0),(0.50,1)])
            if !plainStem { stroke([(0.22,1),(0.78,1)]); stroke([(0.22,0),(0.78,0)]) }
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
            stroke([(0.50,0),(0.50,h)]); dot(0.50,min(0.97,h+0.22))
        case "j":
            move(0.68,h); line(0.68,-d*0.58)
            curve(0.68,-d*1.04,0.36,-d*1.10,0.18,-d*0.84); dot(0.68,min(0.97,h+0.22))
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
