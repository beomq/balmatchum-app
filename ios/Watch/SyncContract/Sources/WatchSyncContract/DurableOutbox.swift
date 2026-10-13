import Foundation

public enum OutboxError: Error { case conflictingRecord, invalidStore }

/// One owner must serialize access. Payload and acknowledgement advance in one atomic write.
public final class DurableOutbox {
    public struct Entry: Codable, Equatable {
        public let record: GPSRecord
        public fileprivate(set) var acknowledgement: Acknowledgement?
        public var stage: Acknowledgement.Stage { acknowledgement?.stage ?? .transferQueued }
    }
    private struct Store: Codable {
        let version: Int
        var entries: [Entry]
    }
    private let file: URL
    public private(set) var entries: [Entry]

    public init(file: URL) throws {
        self.file = file
        if FileManager.default.fileExists(atPath: file.path) {
            let store = try JSONDecoder().decode(Store.self, from: Data(contentsOf: file))
            guard store.version == 1 else { throw OutboxError.invalidStore }
            var keys = Set<String>()
            for entry in store.entries {
                _ = try GPSRecord.decode(JSONEncoder().encode(entry.record))
                let key = entry.record.contextId + "\u{0}" + entry.record.recordId
                guard keys.insert(key).inserted else { throw OutboxError.invalidStore }
                if let ack = entry.acknowledgement {
                    _ = try Acknowledgement.decode(JSONEncoder().encode(ack))
                    guard ack.contextId == entry.record.contextId,
                          ack.recordId == entry.record.recordId, ack.errorCode == nil else {
                        throw OutboxError.invalidStore
                    }
                }
            }
            entries = store.entries
        } else {
            entries = []
        }
    }

    @discardableResult public func enqueue(_ data: Data) throws -> Bool {
        let record = try GPSRecord.decode(data)
        if let existing = entries.first(where: { $0.record.contextId == record.contextId && $0.record.recordId == record.recordId }) {
            guard existing.record == record else { throw OutboxError.conflictingRecord }
            return false
        }
        var next = entries
        next.append(Entry(record: record))
        try persist(next)
        return true
    }

    @discardableResult public func receive(_ data: Data) throws -> Bool {
        let ack = try Acknowledgement.decode(data)
        guard let index = entries.firstIndex(where: { $0.record.contextId == ack.contextId && $0.record.recordId == ack.recordId }) else { return false }
        var state = AcknowledgementState(contextId: ack.contextId, recordId: ack.recordId)
        if let previous = entries[index].acknowledgement { state.apply(previous) }
        guard state.apply(ack) else { return false }
        var next = entries
        next[index].acknowledgement = ack
        try persist(next)
        return true
    }

    /// Reachability or transfer callbacks never change persisted acknowledgement state.
    public func pending(contextId: String?) -> [Entry] {
        guard let contextId else { return [] }
        return entries.filter { $0.record.contextId == contextId && $0.stage != .serverSaved }
    }

    private func persist(_ next: [Entry]) throws {
        let bytes = try JSONEncoder().encode(Store(version: 1, entries: next))
        try bytes.write(to: file, options: .atomic)
        entries = next
    }
}
