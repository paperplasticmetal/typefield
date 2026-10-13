import Foundation

/// Confined to one store's serial persistence queue. Revisions are captured with
/// each immutable snapshot; equality of user text or floating-point geometry is
/// never used to decide whether an encoded project can be reused.
final class FontLabPersistenceEncoder {
    private struct Entry {
        let revision: UUID
        let data: Data
        var use: UInt64
    }
    private var entries: [UUID: Entry] = [:]
    private var use: UInt64 = 0
    private let maximumBytes: Int
    private let maximumEntries: Int
    private let encoder: JSONEncoder
    private(set) var retainedByteCount = 0
    private(set) var lastEncodedProjectCount = 0
    var entryCount: Int { entries.count }

    init(maximumBytes: Int = 32 * 1024 * 1024, maximumEntries: Int = 128) {
        self.maximumBytes = max(0, maximumBytes)
        self.maximumEntries = max(0, maximumEntries)
        encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
    }

    func encode(_ snapshot: FontLabState, revisions: [UUID: UUID]) throws -> Data {
        lastEncodedProjectCount = 0
        let ids = snapshot.projects.map(\.id) + (snapshot.deletedProjects ?? []).map(\.id)
        // The store validates before saving. Keep a direct helper call with
        // duplicate identities from accidentally reusing one project's bytes.
        guard Set(ids).count == ids.count else { return try encoder.encode(snapshot) }
        var pending: [(UUID, Entry)] = []
        var usedIDs: [UUID] = []
        func array(_ projects: [FontLabProject]) throws -> Data {
            var result = Data("[".utf8)
            for (index, project) in projects.enumerated() {
                if index > 0 { result.append(44) }
                if let revision = revisions[project.id], let entry = entries[project.id], entry.revision == revision {
                    result.append(entry.data)
                    usedIDs.append(project.id)
                } else {
                    let data = try encoder.encode(project)
                    lastEncodedProjectCount += 1
                    result.append(data)
                    if let revision = revisions[project.id] {
                        pending.append((project.id, Entry(revision: revision, data: data, use: 0)))
                    }
                }
            }
            result.append(93)
            return result
        }

        let projects = try array(snapshot.projects)
        let deleted = try snapshot.deletedProjects.map { try array($0) }
        // Let the model's actual Codable conformance produce the envelope, so
        // new state metadata is retained without a second list of coding keys.
        var envelope = snapshot
        envelope.projects = []
        envelope.deletedProjects = snapshot.deletedProjects.map { _ in [] }
        let shell = try encoder.encode(envelope)
        var replacements: [(Range<Data.Index>, Data)] = []
        for (key, payload) in [("projects", Optional(projects)), ("deletedProjects", deleted)] {
            guard let payload else { continue }
            let marker = Data("\"\(key)\":[]".utf8)
            guard let range = shell.range(of: marker),
                  shell.range(of: marker, in: range.upperBound..<shell.endIndex) == nil else {
                // Future schemas with an ambiguous nested key remain correct.
                return try encoder.encode(snapshot)
            }
            replacements.append((range.upperBound - 2..<range.upperBound, payload))
        }
        var result = shell
        for (range, data) in replacements.sorted(by: { $0.0.lowerBound > $1.0.lowerBound }) {
            result.replaceSubrange(range, with: data)
        }

        // Publish new entries only after the entire snapshot encodes. A later
        // filesystem failure may reuse these bytes only for this same revision.
        let liveIDs = Set(ids)
        for id in entries.keys.filter({ !liveIDs.contains($0) }) { remove(id) }
        for id in usedIDs {
            use &+= 1
            entries[id]?.use = use
        }
        for (id, var entry) in pending {
            remove(id)
            guard maximumEntries > 0, entry.data.count <= maximumBytes else { continue }
            while entries.count >= maximumEntries || retainedByteCount > maximumBytes - entry.data.count {
                guard let oldest = entries.min(by: { $0.value.use < $1.value.use })?.key else { break }
                remove(oldest)
            }
            use &+= 1; entry.use = use
            entries[id] = entry
            retainedByteCount += entry.data.count
        }
        return result
    }

    private func remove(_ id: UUID) {
        if let entry = entries.removeValue(forKey: id) { retainedByteCount -= entry.data.count }
    }
}
