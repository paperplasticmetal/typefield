import AppKit

struct FontLabComponentUse: Codable, Equatable, Identifiable {
    var id = UUID()
    var source: String
    var x = 0.0
    var y = 0.0
    var scale = 1.0
    var isValid: Bool { source.count == 1 && x.isFinite && y.isFinite && scale.isFinite && abs(x) <= 2 && abs(y) <= 2 && (0.05...4).contains(scale) }
}

enum FontLabKerningSide: String, Codable, CaseIterable { case left = "First glyph", right = "Second glyph" }
struct FontLabKerningGroup: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var members: [String]
    var side: FontLabKerningSide = .left
    var isValid: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name.count <= 80 && !members.isEmpty && members.count <= 2000 && Set(members).count == members.count && members.allSatisfy { $0.count == 1 } }
}
struct FontLabKerningPair: Codable, Equatable, Identifiable {
    var id = UUID()
    // A literal character, or @ followed by a stable group UUID.
    var left: String
    var right: String
    var value: Double
    var isValid: Bool { value.isFinite && (-500...500).contains(value) && !left.isEmpty && !right.isEmpty }
}
struct FontLabMaster: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var weight = 400.0
    var glyphs: [String: FontLabGlyph]
    var metrics: FontLabMetrics
    var groups: [FontLabKerningGroup]?
    var pairs: [FontLabKerningPair]?
    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name.count <= 80 && weight.isFinite && (1...1000).contains(weight) && metrics.isValid &&
        FontLabDesign.valid(glyphs: glyphs, groups: groups ?? [], pairs: pairs ?? [])
    }
}

enum FontLabDesign {
    /// Decomposed uses need independent editing identities, including when the
    /// same source occurs twice in one glyph.
    static func detachedStrokes(_ strokes: [FontLabStroke]) -> [FontLabStroke] {
        strokes.map { source in
            var stroke = source; stroke.id = UUID()
            if var paths = stroke.vectorPaths {
                for p in paths.indices {
                    paths[p].id = UUID()
                    for n in paths[p].nodes.indices { paths[p].nodes[n].id = UUID() }
                }
                stroke.vectorPaths = paths
            }
            return stroke
        }
    }
    static func valid(glyphs: [String: FontLabGlyph], groups: [FontLabKerningGroup], pairs: [FontLabKerningPair]) -> Bool {
        guard glyphs.count <= 2000, glyphs.allSatisfy({ $0.key == $0.value.character && $0.value.isValid }), groups.count <= 256, pairs.count <= 5000,
              Set(groups.map(\.id)).count == groups.count, Set(pairs.map(\.id)).count == pairs.count, groups.allSatisfy(\.isValid), pairs.allSatisfy(\.isValid),
              Set(pairs.map { $0.left + "\u{1f}" + $0.right }).count == pairs.count,
              groups.allSatisfy({ $0.members.allSatisfy { glyphs[$0] != nil } }) else { return false }
        for side in FontLabKerningSide.allCases {
            let members = groups.filter { $0.side == side }.flatMap(\.members)
            guard Set(members).count == members.count else { return false }
        }
        let leftEndpoints = Set(glyphs.keys).union(groups.filter { $0.side == .left }.map { "@" + $0.id.uuidString })
        let rightEndpoints = Set(glyphs.keys).union(groups.filter { $0.side == .right }.map { "@" + $0.id.uuidString })
        guard pairs.allSatisfy({ leftEndpoints.contains($0.left) && rightEndpoints.contains($0.right) }) else { return false }
        for glyph in glyphs.values where glyph.components?.isEmpty == false {
            guard resolved(glyph.character, in: glyphs) != nil else { return false }
        }
        return true
    }
    /// Components are resolved into fresh drawing data for display/export only;
    /// source references in the saved project remain live and editable.
    static func resolved(_ character: String, in glyphs: [String: FontLabGlyph]) -> FontLabGlyph? {
        if let glyph = glyphs[character], glyph.components?.isEmpty != false {
            return glyph.isValid ? glyph : nil
        }
        var remaining = 30000
        func visit(_ character: String, chain: Set<String>) -> FontLabGlyph? {
            guard !chain.contains(character), chain.count < 8, var glyph = glyphs[character] else { return nil }
            var nextChain = chain; nextChain.insert(character)
            let uses = glyph.components ?? []; glyph.components = nil
            remaining -= glyph.strokes.reduce(0) { $0 + $1.points.count + ($1.contours?.reduce(0) { $0 + $1.count } ?? 0) + ($1.vectorPaths?.reduce(0) { $0 + $1.nodes.count } ?? 0) }
            guard remaining >= 0 else { return nil }
            for use in uses {
                guard use.isValid, let source = visit(use.source, chain: nextChain) else { return nil }
                let horizontal = source.resolvedDesignWidth / glyph.resolvedDesignWidth * use.scale
                func transformed(_ p: FontLabPoint) -> FontLabPoint {
                    var p = p; p.x = p.x * horizontal + use.x / glyph.resolvedDesignWidth; p.y = p.y * use.scale + use.y; return p
                }
                for var stroke in source.strokes {
                    stroke.points = stroke.points.map(transformed)
                    stroke.contours = stroke.contours?.map { $0.map(transformed) }
                    if var paths = stroke.vectorPaths {
                        for p in paths.indices { for n in paths[p].nodes.indices {
                            paths[p].nodes[n].point = transformed(paths[p].nodes[n].point)
                            paths[p].nodes[n].incoming = paths[p].nodes[n].incoming.map(transformed)
                            paths[p].nodes[n].outgoing = paths[p].nodes[n].outgoing.map(transformed)
                        } }
                        stroke.vectorPaths = paths
                    }
                    // Pen components use uniform physical scaling; contour widths
                    // are encoded in their geometry and do not use this field.
                    if !stroke.points.isEmpty { stroke.width *= use.scale }
                    guard stroke.isValid else { return nil }
                    glyph.strokes.append(stroke)
                }
            }
            return glyph.isValid ? glyph : nil
        }
        return visit(character, chain: [])
    }
    static func kerning(_ left: String, _ right: String, groups: [FontLabKerningGroup], pairs: [FontLabKerningPair]) -> Double {
        var best: (Int, Double)?
        func matches(_ endpoint: String, _ character: String) -> Bool {
            if endpoint == character { return true }
            return groups.first { "@" + $0.id.uuidString == endpoint }?.members.contains(character) == true
        }
        for pair in pairs where matches(pair.left, left) && matches(pair.right, right) {
            // Explicit glyph pairs outrank one-sided exceptions, which outrank
            // group pairs. A left-glyph exception wins an equal-specificity tie.
            let score = (pair.left == left ? 2 : 0) + (pair.right == right ? 1 : 0)
            if best == nil || score > best!.0 { best = (score, pair.value) }
        }
        return best?.1 ?? 0
    }
}

extension FontLabProject {
    var designIsValid: Bool {
        (masters?.count ?? 0) <= 16 && (masters?.allSatisfy(\.isValid) ?? true) &&
        Set(masters?.map(\.id) ?? []).count == (masters?.count ?? 0) &&
        (activeMasterID == nil || masters?.contains { $0.id == activeMasterID } == true) &&
        FontLabDesign.valid(glyphs: glyphs, groups: kerningGroups ?? [], pairs: kerningPairs ?? [])
    }
    func resolvedGlyph(_ character: String) -> FontLabGlyph? { FontLabDesign.resolved(character, in: glyphs) }
    var outputProject: FontLabProject {
        var copy = self
        copy.glyphs = glyphs.mapValues { FontLabDesign.resolved($0.character, in: glyphs) ?? $0 }
        copy.masters = nil; copy.activeMasterID = nil
        return copy
    }
    func kerning(_ left: String, _ right: String) -> Double { FontLabDesign.kerning(left, right, groups: kerningGroups ?? [], pairs: kerningPairs ?? []) }
    mutating func captureActiveMaster() {
        guard let index = masters?.firstIndex(where: { $0.id == activeMasterID }) else { return }
        masters?[index].glyphs = glyphs; masters?[index].metrics = metrics
        masters?[index].groups = kerningGroups; masters?[index].pairs = kerningPairs
    }
    mutating func addMaster(name: String, weight: Double) {
        if masters?.isEmpty != false {
            let base = FontLabMaster(name: "Regular", glyphs: glyphs, metrics: metrics, groups: kerningGroups, pairs: kerningPairs)
            masters = [base]; activeMasterID = base.id
        }
        captureActiveMaster()
        let master = FontLabMaster(name: name, weight: weight, glyphs: glyphs, metrics: metrics, groups: kerningGroups, pairs: kerningPairs)
        masters?.append(master); activeMasterID = master.id
    }
    mutating func switchMaster(_ id: UUID) {
        guard id != activeMasterID, masters?.contains(where: { $0.id == id }) == true else { return }
        captureActiveMaster()
        guard let master = masters?.first(where: { $0.id == id }) else { return }
        glyphs = master.glyphs; metrics = master.metrics; kerningGroups = master.groups; kerningPairs = master.pairs; activeMasterID = id
    }
}

struct FontLabResolvedKern: Equatable {
    let left: String
    let right: String
    let value: Int
}
extension FontLabProject {
    func resolvedKerning(characters: Set<String>) throws -> [FontLabResolvedKern] {
        struct Pair: Hashable { let left: String; let right: String }
        var result: [Pair: Int] = [:]
        let groups = Dictionary(uniqueKeysWithValues: (kerningGroups ?? []).map { ("@" + $0.id.uuidString, $0.members) })
        func members(_ endpoint: String) -> [String] { (groups[endpoint] ?? [endpoint]).filter { characters.contains($0) } }
        func priority(_ pair: FontLabKerningPair) -> Int { (groups[pair.left] == nil ? 2 : 0) + (groups[pair.right] == nil ? 1 : 0) }
        for pair in (kerningPairs ?? []).sorted(by: { priority($0) < priority($1) }) {
            for left in members(pair.left) { for right in members(pair.right) {
                result[Pair(left: left, right: right)] = Int(pair.value.rounded())
                guard result.count <= 10000 else { throw FontLabTrueTypeExporter.ExportError.valueOutOfRange("kerning: reduce groups to fewer than 10,000 expanded pairs") }
            } }
        }
        return result.filter { $0.value != 0 }.map { FontLabResolvedKern(left: $0.key.left, right: $0.key.right, value: $0.value) }.sorted { ($0.left, $0.right) < ($1.left, $1.right) }
    }
}
