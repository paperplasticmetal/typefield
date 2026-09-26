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
        let sources = Dictionary(uniqueKeysWithValues: drawn.compactMap { character -> (String, FontLabGlyph)? in
            guard let glyph = project.resolvedGlyph(character), glyph.hasArtwork else { return nil }
            return (character, glyph)
        })
        let style = FontLabStarterStyle(project: project, sources: sources, weight: weight)
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
               let source = sources[counterpart] {
                candidate = adapted(source, to: character, metrics: project.metrics)
                if candidate != nil {
                    detail = FontLabStarterDetail(sourceCharacters: [counterpart], method: "Scaled outline", explanation: "The drawn \(counterpart) outline was scaled to the \(character == character.uppercased() ? "cap" : "x") height. Review its weight, spacing, and curve balance.", confidence: .adapted)
                }
            }
            if candidate == nil, let derived = sourceDerived(character, sources: sources, style: style) {
                candidate = derived.glyph
                detail = FontLabStarterDetail(sourceCharacters: derived.sources, method: derived.method,
                                              explanation: derived.explanation, confidence: .adapted)
            }
            if candidate == nil {
                candidate = template(character, style: style)
                if candidate != nil {
                    let sources = sampled.isEmpty ? "the project guides" : "the project guides and \(sampled.joined(separator: ", "))"
                    detail = FontLabStarterDetail(sourceCharacters: sampled, method: "Constructed outline", explanation: "A distinct Latin letterform was constructed using proportions, spacing, and stroke weight measured from \(sources). Its contours were not copied from those drawings; refine its curves and spacing.", confidence: .template)
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
            note: "Starter letters are editable suggestions. Adapted letters reuse your outlines; templates use measured proportions and spacing. A few examples cannot determine every curve or serif. Review each letter before export."
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

    private static func template(_ character: String, style: FontLabStarterStyle) -> FontLabGlyph? {
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
        let width = style.width(baseWidth, uppercase: isUpper)
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
                let fittedWeight = max(0.008, opticalWeight * fraction)
                var shape = FontLabStarterSkeleton(width: width, metrics: style.metrics, weight: fittedWeight,
                                                   terminalCap: cap, descenderDepth: style.descenderDepth)
                shape.draw(character)
                guard let paths = shape.outlines(), !paths.isEmpty else { continue }
                let glyph = FontLabGlyph(character: character, strokes: [FontLabStroke(vectorPaths: paths)],
                                         leftSideBearing: style.leftBearing(uppercase: isUpper),
                                         rightSideBearing: style.rightBearing(uppercase: isUpper),
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

    var safeWeight: Double { min(weight, (metrics.xHeight - metrics.baseline) * 0.65) }

    init(project: FontLabProject, sources: [String: FontLabGlyph], weight: Double) {
        metrics = project.metrics
        self.weight = weight
        func median(_ values: [Double]) -> Double? {
            let values = values.filter { $0.isFinite }.sorted()
            return values.isEmpty ? nil : values[values.count / 2]
        }
        let regularCaps = Array("HNOXCDPRSU").map(String.init).compactMap { sources[$0] }
        let regularLower = Array("nopabhduce").map(String.init).compactMap { sources[$0] }
        let caps = regularCaps.isEmpty ? sources.filter { $0.key == $0.key.uppercased() }.map(\.value) : regularCaps
        let lower = regularLower.isEmpty ? sources.filter { $0.key == $0.key.lowercased() }.map(\.value) : regularLower
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
        min(2.5, max(0.22, base * (uppercase ? uppercaseWidth / 0.65 : lowercaseWidth / 0.57)))
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
    static func sourceDerived(_ character: String, sources: [String: FontLabGlyph], style: FontLabStarterStyle) -> FontLabStarterDerivation? {
        let horizontalPairs = ["p":"q", "q":"p", "b":"d", "d":"b"]
        if let sourceCharacter = horizontalPairs[character], let source = sources[sourceCharacter], exportable(source),
           let glyph = transformed(source, to: character, width: source.resolvedDesignWidth,
                                   x: { 1 - $0 }, y: { $0 }, swapBearings: true, reverseWinding: true) {
            return .init(glyph: glyph, sources: [sourceCharacter], method: "Mirrored outline",
                         explanation: "The drawn \(sourceCharacter) contours were reflected horizontally. The curves and stroke character are retained; check the letter's terminals and spacing.")
        }
        let verticalPairs = ["n":"u", "u":"n"]
        if let sourceCharacter = verticalPairs[character], let source = sources[sourceCharacter], exportable(source) {
            let top = character == character.uppercased() ? style.metrics.capHeight : style.metrics.xHeight
            if let glyph = transformed(source, to: character, width: source.resolvedDesignWidth,
                                       x: { $0 }, y: { style.metrics.baseline + top - $0 },
                                       reverseWinding: true) {
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
        if character == "h", let source = sources["n"], exportable(source), let box = inkBounds(source) {
            let x = box.minX + style.safeWeight / max(source.resolvedDesignWidth, 0.1) * 0.5
            if let glyph = appending(source, to: character, style: style,
                                     points: [.init(x: x, y: box.maxY - style.safeWeight * 0.3),
                                              .init(x: x, y: style.metrics.capHeight - style.safeWeight * 0.5)]) {
                return .init(glyph: glyph, sources: ["n"], method: "Reused outline with feature",
                             explanation: "The drawn n arch is retained and its left stem is extended to cap height. Check the join and top terminal.")
            }
        }
        if character == "m", let source = sources["n"], exportable(source),
           let glyph = repeatedN(source, weight: style.safeWeight) {
            return .init(glyph: glyph, sources: ["n"], method: "Repeated source outline",
                         explanation: "Two independent copies of the drawn n outline form the m arches. Edit the middle join and side bearings as needed.")
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

    static func exportable(_ glyph: FontLabGlyph) -> Bool {
        glyph.hasArtwork && glyph.isValid &&
            !glyph.strokes.contains { $0.vectorPaths?.contains(where: { !$0.closed }) == true }
    }

    static func transformed(_ source: FontLabGlyph, to character: String, width: Double,
                            x: (Double) -> Double, y: (Double) -> Double,
                            swapBearings: Bool = false, reverseWinding: Bool = false) -> FontLabGlyph? {
        func map(_ value: FontLabPoint) -> FontLabPoint {
            var point = value; point.x = x(value.x); point.y = y(value.y); return point
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
        let glyph = FontLabGlyph(character: character, strokes: strokes,
                                 leftSideBearing: swapBearings ? source.rightSideBearing : source.leftSideBearing,
                                 rightSideBearing: swapBearings ? source.leftSideBearing : source.rightSideBearing,
                                 contourDesignWidth: width)
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
        for i in 0...500 {
            let inside = outline.contains(CGPoint(x: Double(i) * 2, y: y * 1_000),
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
        let paths = !converted.isEmpty && converted.allSatisfy({ $0.closed && $0.isValid })
            ? converted : (filledStrip(points: points, glyphWidth: width, strokeWidth: addedWidth).map { [$0] } ?? [])
        guard !paths.isEmpty && paths.allSatisfy({ $0.closed && $0.isValid }) else { return nil }
        var strokes = FontLabDesign.detachedStrokes(source.strokes)
        strokes.append(FontLabStroke(vectorPaths: paths))
        let glyph = FontLabGlyph(character: character, strokes: strokes,
                                 leftSideBearing: source.leftSideBearing, rightSideBearing: source.rightSideBearing,
                                 contourDesignWidth: width)
        return glyph.isValid && glyph.hasArtwork ? glyph : nil
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
