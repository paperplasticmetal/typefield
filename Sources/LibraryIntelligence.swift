import Foundation

/// Explicit applications only. Browsing, previewing, favoriting, and shortlisting
/// are intentionally not treated as font use.
struct FontUsageRecord: Codable, Equatable {
    var lastAppliedAt: Date
    var applicationCount: Int
}

struct FontSignature: Equatable {
    let category: Category
    let weight: Int
    let widthClass: Int
    let italic: Bool
    let monospace: Bool
    let xHeightRatio: Double?
    let capHeightRatio: Double?
    let ascenderRatio: Double?
    let descenderRatio: Double?
    let averageAdvanceRatio: Double?
    let panose: [UInt8]
    let writingSystems: Set<WritingSystem>
    let visualTags: Set<String>

    init(category: Category, weight: Int, widthClass: Int, italic: Bool, monospace: Bool, xHeightRatio: Double? = nil, capHeightRatio: Double? = nil, ascenderRatio: Double? = nil, descenderRatio: Double? = nil, averageAdvanceRatio: Double? = nil, panose: [UInt8] = [], writingSystems: Set<WritingSystem> = [], visualTags: Set<String> = []) {
        self.category = category
        self.weight = weight
        self.widthClass = widthClass
        self.italic = italic
        self.monospace = monospace
        self.xHeightRatio = Self.metric(xHeightRatio)
        self.capHeightRatio = Self.metric(capHeightRatio)
        self.ascenderRatio = Self.metric(ascenderRatio)
        self.descenderRatio = Self.metric(descenderRatio)
        self.averageAdvanceRatio = Self.metric(averageAdvanceRatio)
        self.panose = panose.count == 10 ? panose : []
        self.writingSystems = writingSystems
        self.visualTags = Set(visualTags.map { $0.lowercased() }.filter { $0.hasPrefix("visual/") })
    }

    init(face: Face, category: Category, tags: Set<String>) {
        let facts = face.facts
        self.init(category: category, weight: facts.weight, widthClass: facts.widthClass, italic: facts.italic, monospace: facts.monospace, xHeightRatio: facts.xHeightRatio, capHeightRatio: facts.capHeightRatio, ascenderRatio: facts.ascenderRatio, descenderRatio: facts.descenderRatio, averageAdvanceRatio: facts.averageAdvanceRatio, panose: facts.panose, writingSystems: face.writingSystems, visualTags: tags)
    }

    var panoseContrast: Int? {
        guard panose.count == 10, panose[0] == 2, panose[4] >= 2 else { return nil }
        return Int(panose[4])
    }

    private static func metric(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value > 0, value < 4 else { return nil }
        return value
    }
}

struct FontSimilarityAssessment: Equatable {
    let distance: Double
    let reasons: [String]
}

struct FontSimilarityResult: Identifiable {
    var id: String { family.name }
    let family: Family
    let face: Face
    let distance: Double
    let reasons: [String]
}

struct FontDiscoveryResult: Identifiable {
    var id: String { family.name }
    let family: Family
    let face: Face
    let lastAppliedAt: Date?
    let applicationCount: Int
    let currentCanvasCount: Int
}

enum LibraryIntelligence {
    /// A deterministic, inspectable distance. The value is useful for ordering,
    /// not as a percentage or a claim that two designs are interchangeable.
    static func assess(_ reference: FontSignature, _ candidate: FontSignature) -> FontSimilarityAssessment {
        assessment(reference, candidate, includeReasons: true)
    }

    private static func assessment(_ reference: FontSignature, _ candidate: FontSignature, includeReasons: Bool) -> FontSimilarityAssessment {
        var distance = 0.0
        var reasons: [String] = []

        if reference.category == candidate.category {
            if includeReasons && reference.category != .other { reasons.append("Same \(reference.category.rawValue.lowercased()) category") }
        } else if reference.category == .other || candidate.category == .other {
            distance += 0.45
        } else if reference.category == .symbol || candidate.category == .symbol {
            distance += 4
        } else {
            distance += 1.6
        }

        if reference.monospace != candidate.monospace { distance += 2.8 }
        if reference.italic != candidate.italic { distance += 1.1 }

        let weightDifference = abs(reference.weight - candidate.weight)
        distance += min(1.5, Double(weightDifference) / 600) * 0.9
        let widthDifference = abs(reference.widthClass - candidate.widthClass)
        distance += min(1.5, Double(widthDifference) / 4) * 1.35
        addMetric(reference.xHeightRatio, candidate.xHeightRatio, scale: 0.22, weight: 1.0, to: &distance)
        addMetric(reference.capHeightRatio, candidate.capHeightRatio, scale: 0.22, weight: 0.45, to: &distance)
        addMetric(reference.ascenderRatio, candidate.ascenderRatio, scale: 0.30, weight: 0.25, to: &distance)
        addMetric(reference.descenderRatio, candidate.descenderRatio, scale: 0.22, weight: 0.25, to: &distance)
        addMetric(reference.averageAdvanceRatio, candidate.averageAdvanceRatio, scale: 0.30, weight: 0.8, to: &distance)

        distance += panoseDistance(reference.panose, candidate.panose)

        let sharedVisualTags = reference.visualTags.intersection(candidate.visualTags)
        if !reference.visualTags.isEmpty || !candidate.visualTags.isEmpty {
            let union = reference.visualTags.union(candidate.visualTags)
            distance += (1 - Double(sharedVisualTags.count) / Double(max(1, union.count))) * 0.65
        }

        if !reference.writingSystems.isEmpty && !candidate.writingSystems.isEmpty {
            let shared = reference.writingSystems.intersection(candidate.writingSystems).count
            let total = reference.writingSystems.union(candidate.writingSystems).count
            distance += (1 - Double(shared) / Double(max(1, total))) * 0.2
        }

        guard includeReasons else { return FontSimilarityAssessment(distance: distance, reasons: []) }
        for tag in sharedVisualTags.sorted().prefix(2) {
            let label = String(tag.dropFirst("visual/".count)).replacingOccurrences(of: "-", with: " ")
            reasons.append("Shared visual label: \(label)")
        }
        if widthDifference == 0 { reasons.append("Same width class") }
        else if widthDifference == 1 { reasons.append("Similar width") }
        if let a = reference.xHeightRatio, let b = candidate.xHeightRatio, abs(a - b) <= 0.035 { reasons.append("Similar x-height") }
        if let a = reference.panoseContrast, let b = candidate.panoseContrast, abs(a - b) <= 1 { reasons.append("Similar stroke contrast") }
        if weightDifference <= 75 { reasons.append("Similar weight") }
        if let a = reference.averageAdvanceRatio, let b = candidate.averageAdvanceRatio, abs(a - b) <= 0.035 { reasons.append("Similar character width") }

        return FontSimilarityAssessment(distance: distance, reasons: Array(reasons.prefix(5)))
    }

    static func similarFamilies(to reference: Face, referenceCategory: Category, catalog: [Family], categoryOverrides: [String: Category] = [:], tagsByPostScriptName: [String: Set<String>] = [:], limit: Int = 12) -> [FontSimilarityResult] {
        guard limit > 0 else { return [] }
        let excludedFamilies = Set(catalog.filter { $0.faces.contains { $0.name == reference.name } }.map(\.name))
        let source = FontSignature(face: reference, category: referenceCategory, tags: tagsByPostScriptName[reference.name] ?? [])
        var results: [FontSimilarityResult] = []
        for family in catalog where !excludedFamilies.contains(family.name) && !family.faces.isEmpty {
            let effectiveCategory = categoryOverrides[family.name] ?? family.automaticCategory
            var best: (face: Face, assessment: FontSimilarityAssessment)?
            for face in family.faces {
                let signature = FontSignature(face: face, category: effectiveCategory, tags: tagsByPostScriptName[face.name] ?? [])
                let assessment = assessment(source, signature, includeReasons: false)
                if best == nil || assessment.distance < best!.assessment.distance || (assessment.distance == best!.assessment.distance && stableName(face.name) < stableName(best!.face.name)) {
                    best = (face, assessment)
                }
            }
            if let best {
                results.append(FontSimilarityResult(family: family, face: best.face, distance: best.assessment.distance, reasons: []))
            }
        }
        // Explain only the displayed matches, after ranking. Large catalogs can
        // contain thousands of families that will never appear in the result.
        return results.sorted {
            if $0.distance != $1.distance { return $0.distance < $1.distance }
            return stableName($0.family.name) < stableName($1.family.name)
        }.prefix(limit).map { result in
            let category = categoryOverrides[result.family.name] ?? result.family.automaticCategory
            let signature = FontSignature(face: result.face, category: category, tags: tagsByPostScriptName[result.face.name] ?? [])
            let explained = assessment(source, signature, includeReasons: true)
            return FontSimilarityResult(family: result.family, face: result.face, distance: result.distance, reasons: explained.reasons)
        }
    }

    /// Returns only families supplied by the current local catalog. Stale usage
    /// records never become candidates on their own.
    static func leastRecentlyUsed(catalog: [Family], usage: [String: FontUsageRecord], currentUseCounts: [String: Int] = [:], preferredFaces: [String: String] = [:], excludingFamilyNames: Set<String> = [], includeSystemFonts: Bool = true, seed: UInt64 = 0, limit: Int = 12) -> [FontDiscoveryResult] {
        guard limit > 0 else { return [] }
        // Folding names and hashing the seed are linear in the name length.
        // Compute them once per family, not twice per sort comparison.
        let values = catalog.compactMap { family -> (result: FontDiscoveryResult, day: Double?, name: String, tie: UInt64)? in
            guard !family.faces.isEmpty, !excludingFamilyNames.contains(family.name), includeSystemFonts || family.userFont else { return nil }
            let records = family.faces.compactMap { usage[$0.name] }
            let last = records.map(\.lastAppliedAt).max()
            let applications = records.reduce(0) { saturatedAdd($0, max(0, $1.applicationCount)) }
            let current = family.faces.reduce(0) { saturatedAdd($0, max(0, currentUseCounts[$1.name] ?? 0)) }
            let preferred = preferredFaces[family.name].flatMap { name in family.faces.first { $0.name == name } }
            let result = FontDiscoveryResult(family: family, face: preferred ?? family.representative, lastAppliedAt: last, applicationCount: applications, currentCanvasCount: current)
            let name = stableName(family.name)
            return (result, last.map { floor($0.timeIntervalSinceReferenceDate / 86_400) }, name, stableHash(name, seed: seed))
        }
        return values.sorted { a, b in
            switch (a.day, b.day) {
            case (nil, .some): return true
            case (.some, nil): return false
            case let (.some(left), .some(right)):
                if left != right { return left < right }
            case (nil, nil): break
            }
            if a.result.currentCanvasCount != b.result.currentCanvasCount { return a.result.currentCanvasCount < b.result.currentCanvasCount }
            if a.result.applicationCount != b.result.applicationCount { return a.result.applicationCount < b.result.applicationCount }
            if a.tie != b.tie { return a.tie < b.tie }
            return a.name < b.name
        }.prefix(limit).map(\.result)
    }

    /// Counts a face at most once per current canvas and ignores checkpoints.
    static func currentCanvasUseCounts(in state: StudioState) -> [String: Int] {
        var result: [String: Int] = [:]
        for space in state.spaces {
            for board in space.boards {
                for direction in board.directions {
                    for name in StudioFontCollection.fontNames(in: direction) {
                        result[name] = saturatedAdd(result[name] ?? 0, 1)
                    }
                }
            }
        }
        return result
    }

    private static func addMetric(_ first: Double?, _ second: Double?, scale: Double, weight: Double, to distance: inout Double) {
        switch (first, second) {
        case let (.some(a), .some(b)): distance += min(1.5, abs(a - b) / scale) * weight
        case (.some, nil), (nil, .some): distance += 0.08 * weight
        case (nil, nil): break
        }
    }

    private static func panoseDistance(_ first: [UInt8], _ second: [UInt8]) -> Double {
        guard first.count == 10, second.count == 10, first[0] >= 2, second[0] >= 2 else { return 0 }
        guard first[0] == second[0] else { return 0.6 }
        let weights = [0.0, 0.65, 0.25, 0.65, 0.55, 0.35, 0.25, 0.45, 0.20, 0.30]
        var result = 0.0
        for index in 1..<10 where first[index] >= 2 && second[index] >= 2 {
            if [2, 4, 9].contains(index) {
                result += min(1, Double(abs(Int(first[index]) - Int(second[index]))) / 7) * weights[index]
            } else if first[index] != second[index] {
                result += weights[index]
            }
        }
        return result
    }

    private static func stableName(_ value: String) -> String { value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")) }

    private static func stableHash(_ value: String, seed: UInt64) -> UInt64 {
        var hash = UInt64(1_469_598_103_934_665_603) ^ seed
        for byte in value.utf8 { hash ^= UInt64(byte); hash &*= 1_099_511_628_211 }
        return hash
    }

    private static func saturatedAdd(_ first: Int, _ second: Int) -> Int {
        first > Int.max - second ? Int.max : first + second
    }
}

extension Library {
    var fontUsage: [String: FontUsageRecord] { saved.fontUsage ?? [:] }

    func fontUsage(for postScriptName: String) -> FontUsageRecord? { saved.fontUsage?[postScriptName] }

    @discardableResult func recordFontUse(_ postScriptName: String, at date: Date = Date()) -> Bool {
        recordFontUses([postScriptName], at: date)
    }

    @discardableResult func recordFontUses(_ postScriptNames: [String], at date: Date = Date()) -> Bool {
        let names = Set(postScriptNames).intersection(availableFaceNames)
        guard !names.isEmpty else { return false }
        let previous = saved.fontUsage
        var usage = previous ?? [:]
        for name in names {
            let existing = usage[name]
            let count = existing?.applicationCount ?? 0
            usage[name] = FontUsageRecord(lastAppliedAt: max(existing?.lastAppliedAt ?? date, date), applicationCount: count == Int.max ? Int.max : max(0, count) + 1)
        }
        saved.fontUsage = usage
        guard save() else { saved.fontUsage = previous; return false }
        return true
    }

    func similarFamilies(to reference: Face, limit: Int = 12) -> [FontSimilarityResult] {
        guard let family = families.first(where: { $0.faces.contains { $0.name == reference.name } }) else { return [] }
        return LibraryIntelligence.similarFamilies(to: reference, referenceCategory: category(family), catalog: families, categoryOverrides: saved.overrides, tagsByPostScriptName: pro.tags, limit: limit)
    }

    func discoveryCandidates(in eligibleFamilies: [Family]? = nil, currentUseCounts: [String: Int]? = nil, excludingFamilyNames: Set<String> = [], includeSystemFonts: Bool = true, seed: UInt64 = 0, limit: Int = 12) -> [FontDiscoveryResult] {
        let catalog: [Family]
        if let eligibleFamilies {
            let eligibleNames = Set(eligibleFamilies.map(\.name))
            catalog = families.filter { eligibleNames.contains($0.name) }
        } else {
            catalog = families
        }
        let counts = currentUseCounts ?? LibraryIntelligence.currentCanvasUseCounts(in: studio.state)
        return LibraryIntelligence.leastRecentlyUsed(catalog: catalog, usage: fontUsage, currentUseCounts: counts, preferredFaces: pro.mainPreviews, excludingFamilyNames: excludingFamilyNames, includeSystemFonts: includeSystemFonts, seed: seed, limit: limit)
    }
}
