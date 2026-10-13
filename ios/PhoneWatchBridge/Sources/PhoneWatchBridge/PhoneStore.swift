import Foundation
import WatchSyncContract

public enum PhoneBridgeError: Error {
    case invalidInput, unavailable, corruptStore, inactiveContext, staleRevision
    case identityMismatch, payloadConflict, unknownRecord, receiptConflict, revisionOverflow
}

/// A replacement must either commit every byte or throw without changing the previous value.
public protocol PhonePersistence {
    func load() throws -> Data?
    func replace(with data: Data) throws
}

public struct FilePhonePersistence: PhonePersistence {
    public let url: URL
    public init(url: URL) { self.url = url }
    public func load() throws -> Data? {
        do { return try Data(contentsOf: url) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile { return nil }
    }
    public func replace(with data: Data) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}

public struct RecordIdentity: Hashable, Sendable {
    public let contextId: String
    public let recordId: String
    public init(contextId: String, recordId: String) {
        self.contextId = contextId
        self.recordId = recordId
    }
}

public struct ServerReceipt: Codable, Equatable, Sendable {
    public let contextId: String
    public let clientRecordId: String
    public let recordId: String
    public let persistedAt: String
    public let schemaVersion: Int

    public init(contextId: String, clientRecordId: String, recordId: String,
                persistedAt: String, schemaVersion: Int) throws {
        self.contextId = contextId
        self.clientRecordId = clientRecordId
        self.recordId = recordId
        self.persistedAt = persistedAt
        self.schemaVersion = schemaVersion
        try validate()
    }

    func validate() throws {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = formatter.date(from: persistedAt)
        if date == nil {
            formatter.formatOptions = [.withInternetDateTime]
            date = formatter.date(from: persistedAt)
        }
        guard schemaVersion == 1, UUID(uuidString: contextId) != nil,
              UUID(uuidString: clientRecordId) != nil, UUID(uuidString: recordId) != nil,
              persistedAt.hasSuffix("Z"), date != nil else { throw PhoneBridgeError.invalidInput }
    }
}

public struct ContextActivation: Sendable {
    public let contextId: String
    public let boundaryRevision: Int
    public let latestDisplayRevision: Int
}

public struct ConfirmedAcknowledgement: Sendable {
    public let identity: RecordIdentity
    public let stage: Acknowledgement.Stage
    public let json: Data
}

/// Synchronous operations are serialized, including publication snapshots. A failed write
/// poisons this instance: an old authenticated boundary must never be vouched for afterward.
public final class PhoneStore: @unchecked Sendable {
    private struct Entry: Codable {
        let record: Data
        var receipt: ServerReceipt?
    }
    private struct State: Codable {
        var version = 1
        var phoneInstallationId: String
        var boundaryRevision = 0
        var accounts: [String: String] = [:]
        var activeContextId: String?
        var displayHighwater: [String: Int] = [:]
        var snapshot: Data?
        var inbox: [Entry] = []
        var quarantine: [Data] = []
    }
    private let persistence: any PhonePersistence
    private let lock = NSLock()
    private var state: State
    private var failed = false

    /// One instance per native process. Restore never establishes authentication.
    public init(persistence: any PhonePersistence) throws {
        self.persistence = persistence
        if let data = try persistence.load() {
            do {
                state = try JSONDecoder().decode(State.self, from: data)
                try Self.validate(state)
            } catch { throw PhoneBridgeError.corruptStore }
            if state.activeContextId != nil {
                guard state.boundaryRevision < Int.max else { throw PhoneBridgeError.revisionOverflow }
                state.activeContextId = nil
                state.snapshot = nil
                state.boundaryRevision += 1
                try persistence.replace(with: JSONEncoder().encode(state))
            }
        } else {
            state = State(phoneInstallationId: UUID().uuidString)
            try persistence.replace(with: JSONEncoder().encode(state))
        }
    }

    private func access<T>(_ body: () throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }
        guard !failed else { throw PhoneBridgeError.unavailable }
        return try body()
    }

    private func commit(_ next: State) throws {
        do { try persistence.replace(with: JSONEncoder().encode(next)) }
        catch { failed = true; throw error }
        state = next
    }

    private func advance(_ next: inout State) throws {
        guard next.boundaryRevision < Int.max else { throw PhoneBridgeError.revisionOverflow }
        next.boundaryRevision += 1
    }

    public func activate(accountId: String) throws -> ContextActivation {
        try access {
            guard !accountId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw PhoneBridgeError.invalidInput
            }
            var next = state
            let context = next.accounts[accountId] ?? UUID().uuidString
            if next.activeContextId != context {
                try advance(&next)
                next.accounts[accountId] = context
                next.activeContextId = context
                next.snapshot = nil
                try commit(next)
            }
            return ContextActivation(contextId: context, boundaryRevision: state.boundaryRevision,
                                     latestDisplayRevision: state.displayHighwater[context] ?? 0)
        }
    }

    public func clearContext() throws {
        try access {
            guard state.activeContextId != nil else { return }
            var next = state
            try advance(&next)
            next.activeContextId = nil
            next.snapshot = nil
            try commit(next)
        }
    }

    public func publishDisplay(_ json: Data) throws {
        try access {
            let snapshot = try DisplaySnapshot.decode(json)
            guard snapshot.contextId == state.activeContextId, snapshot.authState == .authenticated else {
                throw PhoneBridgeError.inactiveContext
            }
            guard snapshot.revision > (state.displayHighwater[snapshot.contextId] ?? -1) else {
                throw PhoneBridgeError.staleRevision
            }
            var next = state
            next.displayHighwater[snapshot.contextId] = snapshot.revision
            next.snapshot = try JSONEncoder().encode(snapshot)
            try commit(next)
        }
    }

    public func contextEnvelope(requestId: String? = nil) throws -> [String: Any] {
        try access {
            if let requestId, UUID(uuidString: requestId) == nil { throw PhoneBridgeError.invalidInput }
            var result: [String: Any] = [
                "transportVersion": 1, "kind": requestId == nil ? "context" : "contextReply",
                "phoneInstallationId": state.phoneInstallationId, "boundaryRevision": state.boundaryRevision,
            ]
            if let requestId { result["requestId"] = requestId }
            if let context = state.activeContextId { result["contextId"] = context }
            if let snapshot = state.snapshot { result["snapshotJSON"] = snapshot }
            return result
        }
    }

    /// The caller reads the temporary WC file inside its delegate callback. Unknown
    /// contexts remain quarantined, with no ACK or implicit account enrollment.
    @discardableResult
    public func receive(_ json: Data, contextId: String, recordId: String) throws -> ConfirmedAcknowledgement? {
        try access {
            let record = try GPSRecord.decode(json)
            guard record.contextId == contextId, record.recordId == recordId else {
                throw PhoneBridgeError.identityMismatch
            }
            guard UUID(uuidString: contextId) != nil else { throw PhoneBridgeError.invalidInput }
            if let entry = try state.inbox.first(where: { entry in
                let value = try GPSRecord.decode(entry.record)
                return value.contextId == contextId && value.recordId == recordId
            }) {
                guard try GPSRecord.decode(entry.record) == record else { throw PhoneBridgeError.payloadConflict }
                return try Self.ack(entry)
            }
            if let previous = try state.quarantine.first(where: {
                let value = try GPSRecord.decode($0)
                return value.contextId == contextId && value.recordId == recordId
            }) {
                guard try GPSRecord.decode(previous) == record else { throw PhoneBridgeError.payloadConflict }
                return nil
            }
            var next = state
            let canonical = try JSONEncoder().encode(record)
            guard state.accounts.values.contains(contextId) else {
                next.quarantine.append(canonical)
                try commit(next)
                return nil
            }
            let entry = Entry(record: canonical)
            next.inbox.append(entry)
            try commit(next)
            return try Self.ack(entry)
        }
    }

    public func pendingRecords() throws -> [String] {
        try access {
            guard let active = state.activeContextId else { return [] }
            return try state.inbox.compactMap {
                let record = try GPSRecord.decode($0.record)
                guard record.contextId == active, $0.receipt == nil else { return nil }
                return String(decoding: $0.record, as: UTF8.self)
            }
        }
    }

    public func acknowledge(_ receipt: ServerReceipt) throws -> ConfirmedAcknowledgement {
        try access {
            try receipt.validate()
            guard let index = try state.inbox.firstIndex(where: {
                let record = try GPSRecord.decode($0.record)
                return record.contextId == receipt.contextId && record.recordId == receipt.clientRecordId
            }) else { throw PhoneBridgeError.unknownRecord }
            if let previous = state.inbox[index].receipt {
                guard previous == receipt else { throw PhoneBridgeError.receiptConflict }
            } else {
                var next = state
                next.inbox[index].receipt = receipt
                // Even a late real receipt affects only the original identity, not active context.
                try commit(next)
            }
            return try Self.ack(state.inbox[index])
        }
    }

    public func acknowledgements() throws -> [ConfirmedAcknowledgement] {
        try access { try state.inbox.map(Self.ack) }
    }

    private static func ack(_ entry: Entry) throws -> ConfirmedAcknowledgement {
        let record = try GPSRecord.decode(entry.record)
        let stage: Acknowledgement.Stage = entry.receipt == nil ? .phoneReceived : .serverSaved
        let json = try JSONSerialization.data(withJSONObject: [
            "schemaVersion": 1, "contextId": record.contextId, "recordId": record.recordId,
            "stage": stage.rawValue,
        ])
        _ = try Acknowledgement.decode(json)
        return ConfirmedAcknowledgement(identity: RecordIdentity(contextId: record.contextId, recordId: record.recordId),
                                        stage: stage, json: json)
    }

    private static func validate(_ state: State) throws {
        let contexts = Set(state.accounts.values)
        guard state.version == 1, UUID(uuidString: state.phoneInstallationId) != nil,
              state.boundaryRevision >= 0, contexts.count == state.accounts.count,
              state.accounts.keys.allSatisfy({ !$0.isEmpty }),
              contexts.allSatisfy({ UUID(uuidString: $0) != nil }),
              state.activeContextId.map({ contexts.contains($0) }) ?? true,
              state.displayHighwater.allSatisfy({ contexts.contains($0.key) && $0.value >= 0 }) else {
            throw PhoneBridgeError.corruptStore
        }
        if let data = state.snapshot {
            let snapshot = try DisplaySnapshot.decode(data)
            guard snapshot.contextId == state.activeContextId, snapshot.authState == .authenticated,
                  snapshot.revision == state.displayHighwater[snapshot.contextId] else {
                throw PhoneBridgeError.corruptStore
            }
        }
        var identities = Set<RecordIdentity>()
        for entry in state.inbox {
            let record = try GPSRecord.decode(entry.record)
            guard contexts.contains(record.contextId), identities.insert(RecordIdentity(
                contextId: record.contextId, recordId: record.recordId)).inserted else {
                throw PhoneBridgeError.corruptStore
            }
            if let receipt = entry.receipt {
                try receipt.validate()
                guard receipt.contextId == record.contextId, receipt.clientRecordId == record.recordId else {
                    throw PhoneBridgeError.corruptStore
                }
            }
        }
        for data in state.quarantine {
            let record = try GPSRecord.decode(data)
            guard UUID(uuidString: record.contextId) != nil, !contexts.contains(record.contextId),
                  identities.insert(RecordIdentity(contextId: record.contextId, recordId: record.recordId)).inserted else {
                throw PhoneBridgeError.corruptStore
            }
        }
    }
}
