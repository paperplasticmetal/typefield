import Foundation

/// How much visual separation a pairing should aim for. Scores are relative
/// ordering values within one request, not match percentages.
enum FontPairingMode: String, Codable, CaseIterable, Identifiable {
    case safe = "Safe"
    case balanced = "Balanced"
    case expressive = "Expressive"

    var id: String { rawValue }

    fileprivate var contrastTarget: Double {
        switch self {
        case .safe: return 0.16
        case .balanced: return 0.34
        case .expressive: return 0.58
        }
    }

    fileprivate var contrastTolerance: Double {
        switch self {
        case .safe: return 0.23
        case .balanced: return 0.28
        case .expressive: return 0.32
        }
    }

    fileprivate var scoreWeights: (compatibility: Double, role: Double, contrast: Double) {
        switch self {
        case .safe: return (0.46, 0.30, 0.24)
        case .balanced: return (0.40, 0.28, 0.32)
        case .expressive: return (0.34, 0.24, 0.42)
        }
    }
}

struct FontPairingAssessment: Equatable {
    /// A deterministic 0...100 ranking score. It is not a probability or a
    /// guarantee that two designs work together in every setting.
    let score: Double
    let compatibility: Double
    let roleFitness: Double
    let contrast: Double
    let reasons: [String]
}

struct FontPairingResult: Identifiable {
    var id: String { family.name }
    let family: Family
    let face: Face
    let intendedRole: TypeRole
    let mode: FontPairingMode
    let assessment: FontPairingAssessment

    var score: Double { assessment.score }
    var reasons: [String] { assessment.reasons }
}

/// Local-only, deterministic font-pair ranking. The engine deliberately aims
/// for controlled contrast while retaining compatible proportions, language
/// coverage, and a useful face for the requested typographic role.
enum FontPairingEngine {
    static let maximumResults = 24

    /// Pure assessment for tests, previews, and future tuning. Callers can
    /// construct signatures without loading or registering any font files.
    static func assess(reference: FontSignature, candidate: FontSignature, intendedRole: TypeRole, mode: FontPairingMode) -> FontPairingAssessment {
        assessment(reference: reference, candidate: candidate, intendedRole: intendedRole, mode: mode, includeReasons: true)
    }

    private static func assessment(reference: FontSignature, candidate: FontSignature, intendedRole: TypeRole, mode: FontPairingMode, includeReasons: Bool) -> FontPairingAssessment {
        let writing = writingCompatibility(reference.writingSystems, candidate.writingSystems)
        let proportions = proportionCompatibility(reference, candidate)
        let visualCohesion = tagCohesion(reference.visualTags, candidate.visualTags)
        let compatibility = clamp(writing * 0.55 + proportions * 0.40 + visualCohesion * 0.05)
        let roleFitness = roleFitness(candidate, for: intendedRole)
        let contrast = contrastLevel(reference, candidate)
        let contrastFit = clamp(1 - abs(contrast - mode.contrastTarget) / mode.contrastTolerance)
        let weights = mode.scoreWeights
        var rawScore = compatibility * weights.compatibility + roleFitness * weights.role + contrastFit * weights.contrast

        // Symbols are not useful defaults for any current type-system role.
        // A non-monospace design is likewise not a truthful Monospace result.
        if candidate.category == .symbol { rawScore *= 0.08 }
        if intendedRole == .mono && !candidate.monospace && candidate.category != .mono { rawScore *= 0.10 }
        if !reference.writingSystems.isEmpty && !candidate.writingSystems.isEmpty && reference.writingSystems.isDisjoint(with: candidate.writingSystems) { rawScore *= 0.50 }

        let reasons = includeReasons ? explanations(reference: reference, candidate: candidate, intendedRole: intendedRole, mode: mode, writingCompatibility: writing, proportionCompatibility: proportions, roleFitness: roleFitness, contrast: contrast) : []
        return FontPairingAssessment(score: rounded(clamp(rawScore) * 100), compatibility: rounded(compatibility), roleFitness: rounded(roleFitness), contrast: rounded(contrast), reasons: reasons)
    }

    /// Ranks faces from the supplied on-device catalog and returns at most 24
    /// families. The family containing `reference` is always excluded.
    static func recommendations(for reference: Face, intendedRole: TypeRole, mode: FontPairingMode = .balanced, catalog: [Family], referenceCategory: Category? = nil, categoryOverrides: [String: Category] = [:], tagsByPostScriptName: [String: Set<String>] = [:], preferredFacesByFamily: [String: String] = [:], limit: Int = 12) -> [FontPairingResult] {
        guard limit > 0 else { return [] }
        let sourceFamilies = catalog.filter { family in family.faces.contains { $0.name == reference.name } }
        let excludedNames: Set<String>
        if sourceFamilies.isEmpty {
            excludedNames = Set(catalog.filter { $0.name.caseInsensitiveCompare(reference.originalFamily) == .orderedSame }.map(\.name))
        } else {
            excludedNames = Set(sourceFamilies.map(\.name))
        }
        let sourceFamily = sourceFamilies.first ?? catalog.first { $0.name.caseInsensitiveCompare(reference.originalFamily) == .orderedSame }
        let sourceCategory = referenceCategory ?? sourceFamily.map { categoryOverrides[$0.name] ?? $0.automaticCategory } ?? (reference.facts.monospace ? .mono : .other)
        let sourceSignature = FontSignature(face: reference, category: sourceCategory, tags: tagsByPostScriptName[reference.name] ?? [])
        var results: [FontPairingResult] = []

        for family in catalog where !family.faces.isEmpty && !excludedNames.contains(family.name) {
            let category = categoryOverrides[family.name] ?? family.automaticCategory
            guard category != .symbol else { continue }
            var best: (face: Face, assessment: FontPairingAssessment)?
            for face in family.faces {
                if intendedRole == .mono && !face.facts.monospace && category != .mono { continue }
                let signature = FontSignature(face: face, category: category, tags: tagsByPostScriptName[face.name] ?? [])
                let assessment = assessment(reference: sourceSignature, candidate: signature, intendedRole: intendedRole, mode: mode, includeReasons: false)
                if shouldPrefer(face: face, assessment: assessment, over: best, preferredName: preferredFacesByFamily[family.name], representativeName: family.representative.name) {
                    best = (face, assessment)
                }
            }
            if let best {
                let signature = FontSignature(face: best.face, category: category, tags: tagsByPostScriptName[best.face.name] ?? [])
                let explained = assessment(reference: sourceSignature, candidate: signature, intendedRole: intendedRole, mode: mode, includeReasons: true)
                results.append(FontPairingResult(family: family, face: best.face, intendedRole: intendedRole, mode: mode, assessment: explained))
            }
        }

        let count = min(maximumResults, limit)
        return Array(results.sorted { left, right in
            if left.score != right.score { return left.score > right.score }
            return stableName(left.family.name) < stableName(right.family.name)
        }.prefix(count))
    }

    /// Lightweight deterministic checks that do not depend on the installed
    /// font catalog. This can be wired into the app's existing self-test suite.
    static func selfTest() -> Bool {
        let reference = FontSignature(category: .serif, weight: 400, widthClass: 5, italic: false, monospace: false, xHeightRatio: 0.50, capHeightRatio: 0.72, ascenderRatio: 0.80, descenderRatio: 0.20, averageAdvanceRatio: 0.55, panose: [2, 2, 6, 3, 6, 2, 2, 2, 2, 4], writingSystems: [.latin, .cyrillic], visualTags: ["visual/editorial"])
        let subtle = FontSignature(category: .serif, weight: 500, widthClass: 5, italic: false, monospace: false, xHeightRatio: 0.51, capHeightRatio: 0.73, ascenderRatio: 0.81, descenderRatio: 0.20, averageAdvanceRatio: 0.56, panose: [2, 2, 6, 3, 6, 2, 2, 2, 2, 4], writingSystems: [.latin, .cyrillic], visualTags: ["visual/editorial"])
        let complementary = FontSignature(category: .sans, weight: 550, widthClass: 5, italic: false, monospace: false, xHeightRatio: 0.52, capHeightRatio: 0.73, ascenderRatio: 0.82, descenderRatio: 0.21, averageAdvanceRatio: 0.56, panose: [2, 11, 6, 3, 6, 2, 2, 2, 2, 4], writingSystems: [.latin, .cyrillic], visualTags: ["visual/editorial"])
        let dramatic = FontSignature(category: .display, weight: 800, widthClass: 3, italic: true, monospace: false, xHeightRatio: 0.54, capHeightRatio: 0.76, ascenderRatio: 0.84, descenderRatio: 0.22, averageAdvanceRatio: 0.60, panose: [2, 9, 8, 6, 9, 2, 2, 2, 2, 4], writingSystems: [.latin, .cyrillic], visualTags: ["visual/geometric"])
        let partialCoverage = FontSignature(category: .sans, weight: 550, widthClass: 5, italic: false, monospace: false, xHeightRatio: 0.52, capHeightRatio: 0.73, ascenderRatio: 0.82, descenderRatio: 0.21, averageAdvanceRatio: 0.56, panose: [2, 11, 6, 3, 6, 2, 2, 2, 2, 4], writingSystems: [.latin], visualTags: ["visual/editorial"])

        let safeSubtle = assess(reference: reference, candidate: subtle, intendedRole: .heading, mode: .safe)
        let safeDramatic = assess(reference: reference, candidate: dramatic, intendedRole: .heading, mode: .safe)
        let balanced = assess(reference: reference, candidate: complementary, intendedRole: .heading, mode: .balanced)
        let balancedPartial = assess(reference: reference, candidate: partialCoverage, intendedRole: .heading, mode: .balanced)
        let expressiveDramatic = assess(reference: reference, candidate: dramatic, intendedRole: .display, mode: .expressive)
        let expressiveSubtle = assess(reference: reference, candidate: subtle, intendedRole: .display, mode: .expressive)
        let assessments = [safeSubtle, safeDramatic, balanced, balancedPartial, expressiveDramatic, expressiveSubtle]
        return safeSubtle.score > safeDramatic.score && balanced.score > balancedPartial.score && expressiveDramatic.score > expressiveSubtle.score && assessments.allSatisfy { (0...100).contains($0.score) && (2...5).contains($0.reasons.count) }
    }

    private static func shouldPrefer(face: Face, assessment: FontPairingAssessment, over current: (face: Face, assessment: FontPairingAssessment)?, preferredName: String?, representativeName: String) -> Bool {
        guard let current else { return true }
        if assessment.score != current.assessment.score { return assessment.score > current.assessment.score }
        let faceRank = tieRank(face.name, preferredName: preferredName, representativeName: representativeName)
        let currentRank = tieRank(current.face.name, preferredName: preferredName, representativeName: representativeName)
        if faceRank != currentRank { return faceRank < currentRank }
        return stableName(face.name) < stableName(current.face.name)
    }

    private static func tieRank(_ name: String, preferredName: String?, representativeName: String) -> Int {
        if name == preferredName { return 0 }
        if name == representativeName { return 1 }
        return 2
    }

    private static func writingCompatibility(_ reference: Set<WritingSystem>, _ candidate: Set<WritingSystem>) -> Double {
        if reference.isEmpty && candidate.isEmpty { return 0.75 }
        if reference.isEmpty { return 0.85 }
        if candidate.isEmpty { return 0.55 }
        return Double(reference.intersection(candidate).count) / Double(reference.count)
    }

    private static func proportionCompatibility(_ reference: FontSignature, _ candidate: FontSignature) -> Double {
        var total = 0.0
        var weight = 0.0
        addCloseness(reference.xHeightRatio, candidate.xHeightRatio, scale: 0.18, importance: 0.32, total: &total, weight: &weight)
        addCloseness(reference.capHeightRatio, candidate.capHeightRatio, scale: 0.18, importance: 0.18, total: &total, weight: &weight)
        addCloseness(reference.averageAdvanceRatio, candidate.averageAdvanceRatio, scale: 0.24, importance: 0.28, total: &total, weight: &weight)
        addCloseness(reference.ascenderRatio, candidate.ascenderRatio, scale: 0.25, importance: 0.12, total: &total, weight: &weight)
        addCloseness(reference.descenderRatio, candidate.descenderRatio, scale: 0.18, importance: 0.10, total: &total, weight: &weight)
        return weight == 0 ? 0.70 : clamp(total / weight)
    }

    private static func addCloseness(_ first: Double?, _ second: Double?, scale: Double, importance: Double, total: inout Double, weight: inout Double) {
        guard let first, let second else { return }
        total += clamp(1 - abs(first - second) / scale) * importance
        weight += importance
    }

    private static func tagCohesion(_ first: Set<String>, _ second: Set<String>) -> Double {
        if first.isEmpty && second.isEmpty { return 0.70 }
        if first.isEmpty || second.isEmpty { return 0.60 }
        let union = first.union(second)
        let overlap = Double(first.intersection(second).count) / Double(max(1, union.count))
        return 0.55 + overlap * 0.45
    }

    private static func contrastLevel(_ reference: FontSignature, _ candidate: FontSignature) -> Double {
        let category = categoryContrast(reference.category, candidate.category)
        let weight = clamp(Double(abs(reference.weight - candidate.weight)) / 500)
        let width = clamp(Double(abs(reference.widthClass - candidate.widthClass)) / 5)
        let stroke: Double
        if let first = reference.panoseContrast, let second = candidate.panoseContrast {
            stroke = clamp(Double(abs(first - second)) / 7)
        } else {
            stroke = 0.25
        }
        let posture = reference.italic == candidate.italic ? 0.04 : 0.72
        let visual: Double
        if reference.visualTags.isEmpty && candidate.visualTags.isEmpty {
            visual = 0.30
        } else {
            let union = reference.visualTags.union(candidate.visualTags)
            visual = 1 - Double(reference.visualTags.intersection(candidate.visualTags).count) / Double(max(1, union.count))
        }
        return clamp(category * 0.40 + weight * 0.20 + width * 0.12 + stroke * 0.12 + posture * 0.08 + visual * 0.08)
    }

    private static func categoryContrast(_ first: Category, _ second: Category) -> Double {
        if first == second { return first == .other ? 0.24 : 0.12 }
        if first == .symbol || second == .symbol { return 1 }
        if (first == .serif && second == .sans) || (first == .sans && second == .serif) { return 0.62 }
        if first == .mono || second == .mono {
            let other = first == .mono ? second : first
            return other == .serif || other == .sans ? 0.55 : 0.68
        }
        if first == .display || first == .script || second == .display || second == .script {
            return (first == .display && second == .script) || (first == .script && second == .display) ? 0.68 : 0.82
        }
        if first == .other || second == .other { return 0.42 }
        return 0.55
    }

    private static func roleFitness(_ signature: FontSignature, for role: TypeRole) -> Double {
        let category = categoryRoleFitness(signature.category, monospace: signature.monospace, role: role)
        let weight: Double
        let width: Double
        switch role {
        case .display:
            weight = rangeFitness(signature.weight, ideal: 350...900, falloff: 300)
            width = rangeFitness(signature.widthClass, ideal: 2...8, falloff: 3)
        case .heading:
            weight = rangeFitness(signature.weight, ideal: 450...800, falloff: 300)
            width = rangeFitness(signature.widthClass, ideal: 3...7, falloff: 3)
        case .subheading:
            weight = rangeFitness(signature.weight, ideal: 400...700, falloff: 250)
            width = rangeFitness(signature.widthClass, ideal: 3...7, falloff: 3)
        case .body:
            weight = rangeFitness(signature.weight, ideal: 300...600, falloff: 250)
            width = rangeFitness(signature.widthClass, ideal: 4...6, falloff: 3)
        case .label:
            weight = rangeFitness(signature.weight, ideal: 350...650, falloff: 250)
            width = rangeFitness(signature.widthClass, ideal: 4...6, falloff: 3)
        case .caption:
            weight = rangeFitness(signature.weight, ideal: 350...650, falloff: 250)
            width = rangeFitness(signature.widthClass, ideal: 4...6, falloff: 3)
        case .mono:
            weight = rangeFitness(signature.weight, ideal: 300...600, falloff: 250)
            width = rangeFitness(signature.widthClass, ideal: 4...7, falloff: 3)
        }
        let posture: Double
        if !signature.italic { posture = 1 }
        else {
            switch role {
            case .display: posture = 0.92
            case .heading, .subheading: posture = 0.78
            case .body, .caption, .mono: posture = 0.58
            case .label: posture = 0.45
            }
        }
        let xHeight: Double
        if let value = signature.xHeightRatio {
            switch role {
            case .body, .label, .caption, .mono: xHeight = rangeFitness(value, ideal: 0.43...0.72, falloff: 0.22)
            case .display, .heading, .subheading: xHeight = rangeFitness(value, ideal: 0.34...0.82, falloff: 0.30)
            }
        } else {
            xHeight = 0.70
        }
        return clamp(category * 0.50 + weight * 0.20 + width * 0.12 + posture * 0.10 + xHeight * 0.08)
    }

    private static func categoryRoleFitness(_ category: Category, monospace: Bool, role: TypeRole) -> Double {
        if category == .symbol { return 0 }
        switch role {
        case .display:
            switch category { case .display: return 1; case .script: return 0.92; case .serif, .sans: return 0.88; case .mono: return 0.62; case .other: return 0.68; case .symbol: return 0 }
        case .heading:
            switch category { case .serif, .sans: return 1; case .display: return 0.92; case .script: return 0.66; case .mono: return 0.58; case .other: return 0.65; case .symbol: return 0 }
        case .subheading:
            switch category { case .serif, .sans: return 1; case .display: return 0.76; case .mono: return 0.66; case .script: return 0.46; case .other: return 0.62; case .symbol: return 0 }
        case .body:
            switch category { case .serif, .sans: return 1; case .mono: return 0.72; case .display: return 0.30; case .script: return 0.14; case .other: return 0.48; case .symbol: return 0 }
        case .label:
            switch category { case .sans: return 1; case .mono: return 0.86; case .serif: return 0.80; case .display: return 0.30; case .script: return 0.10; case .other: return 0.50; case .symbol: return 0 }
        case .caption:
            switch category { case .sans: return 1; case .serif: return 0.90; case .mono: return 0.78; case .display: return 0.24; case .script: return 0.10; case .other: return 0.48; case .symbol: return 0 }
        case .mono:
            return monospace || category == .mono ? 1 : 0.05
        }
    }

    private static func rangeFitness<T: BinaryInteger>(_ value: T, ideal: ClosedRange<T>, falloff: T) -> Double {
        if ideal.contains(value) { return 1 }
        let distance = value < ideal.lowerBound ? ideal.lowerBound - value : value - ideal.upperBound
        return clamp(1 - Double(distance) / Double(falloff))
    }

    private static func rangeFitness(_ value: Double, ideal: ClosedRange<Double>, falloff: Double) -> Double {
        if ideal.contains(value) { return 1 }
        let distance = value < ideal.lowerBound ? ideal.lowerBound - value : value - ideal.upperBound
        return clamp(1 - distance / falloff)
    }

    private static func explanations(reference: FontSignature, candidate: FontSignature, intendedRole: TypeRole, mode: FontPairingMode, writingCompatibility: Double, proportionCompatibility: Double, roleFitness: Double, contrast: Double) -> [String] {
        var reasons: [String] = []
        func add(_ value: String) { if !reasons.contains(value) { reasons.append(value) } }

        if !reference.writingSystems.isEmpty {
            if candidate.writingSystems.isEmpty {
                add("Coverage metadata is incomplete for the candidate")
            } else {
                let missing = reference.writingSystems.subtracting(candidate.writingSystems).sorted { $0.rawValue < $1.rawValue }
                if missing.isEmpty {
                    add(reference.writingSystems.count == 1 ? "Matches the reference writing-system coverage" : "Matches all \(reference.writingSystems.count) reference writing systems")
                } else {
                    let labels = missing.prefix(2).map(\.rawValue).joined(separator: " and ")
                    add("Coverage note: missing \(labels)")
                }
            }
        }

        if (reference.category == .serif && candidate.category == .sans) || (reference.category == .sans && candidate.category == .serif) {
            add("Serif–sans contrast creates clear hierarchy")
        } else if reference.category == candidate.category && candidate.category != .other {
            add("Same \(candidate.category.rawValue.lowercased()) category keeps the pairing cohesive")
        } else if candidate.category == .mono || candidate.monospace {
            add("Monospaced texture creates functional contrast")
        } else if candidate.category == .display || candidate.category == .script {
            add("Expressive category contrast gives the pairing a distinct voice")
        } else if reference.category == .display || reference.category == .script {
            add("Text-oriented category balances the expressive reference")
        } else {
            add("Weight and proportion differences separate the two families")
        }

        if roleFitness >= 0.72 {
            switch intendedRole {
            case .mono: add("Monospaced construction fits the Monospace role")
            case .body: add("Text-oriented proportions suit sustained Body copy")
            case .label: add("Practical width and posture suit UI labels")
            case .caption: add("Readable proportions suit small Caption text")
            case .display: add("The selected face has a strong Display profile")
            case .heading: add("The selected face supports clear Heading hierarchy")
            case .subheading: add("The selected face is measured for Subheading scale")
            }
        } else {
            add("Role fit is intentionally experimental for \(intendedRole.rawValue)")
        }

        if let first = reference.xHeightRatio, let second = candidate.xHeightRatio, abs(first - second) <= 0.045 {
            add("Compatible x-height keeps the vertical rhythm steady")
        } else if let first = reference.averageAdvanceRatio, let second = candidate.averageAdvanceRatio, abs(first - second) <= 0.05 {
            add("Compatible character width keeps the pair cohesive")
        } else if proportionCompatibility >= 0.72 {
            add("Compatible cap and character proportions support cohesion")
        }

        let weightDifference = abs(reference.weight - candidate.weight)
        if (90...280).contains(weightDifference) {
            add("Moderate weight contrast builds hierarchy")
        } else if weightDifference > 280 {
            add("Strong weight contrast adds emphasis")
        } else if let first = reference.panoseContrast, let second = candidate.panoseContrast {
            if abs(first - second) <= 1 { add("Related stroke contrast ties the families together") }
            else if abs(first - second) >= 3 { add("A stroke-contrast shift adds character") }
        }

        let sharedTags = reference.visualTags.intersection(candidate.visualTags).sorted()
        if let tag = sharedTags.first {
            let label = String(tag.dropFirst("visual/".count)).replacingOccurrences(of: "-", with: " ")
            add("Shared visual direction: \(label)")
        }

        if reasons.count < 2 {
            switch mode {
            case .safe: add("Subtle contrast favors a dependable starting point")
            case .balanced: add("Controlled contrast balances hierarchy and cohesion")
            case .expressive: add("Pronounced contrast creates a more distinctive pairing")
            }
        }
        if reasons.count < 2 {
            add(writingCompatibility >= 0.75 ? "Coverage and proportions provide a compatible base" : "Review language coverage before committing the pair")
        }
        if reasons.count < 2 {
            add(contrast >= mode.contrastTarget ? "Contrast meets the selected direction" : "Contrast stays below the selected direction")
        }
        return Array(reasons.prefix(5))
    }

    private static func clamp(_ value: Double) -> Double { min(1, max(0, value)) }
    private static func rounded(_ value: Double) -> Double { (value * 1_000).rounded() / 1_000 }
    private static func stableName(_ value: String) -> String { value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")) }
}

extension Library {
    /// Spaces integration convenience using the library's category overrides,
    /// preferred faces, and local visual tags.
    func pairingSuggestions(for reference: Face, intendedRole: TypeRole, mode: FontPairingMode = .balanced, limit: Int = 12) -> [FontPairingResult] {
        let sourceCategory = families.first(where: { $0.faces.contains { $0.name == reference.name } }).map(category)
        return FontPairingEngine.recommendations(for: reference, intendedRole: intendedRole, mode: mode, catalog: families, referenceCategory: sourceCategory, categoryOverrides: saved.overrides, tagsByPostScriptName: pro.tags, preferredFacesByFamily: pro.mainPreviews, limit: limit)
    }
}
