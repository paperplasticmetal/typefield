import Foundation

/// Resolve only the characters the word proof can display. Keep the complete
/// source dictionary available because a visible glyph may depend on a live
/// component source that does not itself appear in the proof text.
enum FontLabProofGeometry {
    static func glyphs(in project: FontLabProject, liveGlyph: FontLabGlyph? = nil) -> [String: FontLabGlyph] {
        let characters = Set(project.previewText.map(String.init))
        guard !characters.isEmpty else { return [:] }
        var sources = project.glyphs
        if let liveGlyph, project.characters.contains(liveGlyph.character) {
            sources[liveGlyph.character] = liveGlyph
        }
        var result: [String: FontLabGlyph] = [:]
        for character in characters {
            guard let original = sources[character] else { continue }
            // Match outputProject's fallback for temporarily unresolved or
            // invalid component geometry without altering the saved project.
            result[character] = FontLabDesign.resolved(original.character, in: sources) ?? original
        }
        return result
    }
}
