import CoreFoundation
import Foundation

public enum BoundaryError: Error { case invalidEnvelope, conflictingRevision }

/// Persisted ordering is separate from per-process permission to send.
public final class WatchBoundary {
    private struct State: Codable {
        var installation: String
        var revision: Int
        var context: String?
        var snapshot: DisplaySnapshot?
    }
    private let file: URL
    private var state: State?
    private var requestId: String?
    public private(set) var confirmed = false
    private var hideCached = false
    public var snapshot: DisplaySnapshot? { hideCached ? nil : state?.snapshot }
    public var sendContext: String? { confirmed ? state?.context : nil }

    public init(file: URL) throws {
        self.file = file
        if FileManager.default.fileExists(atPath: file.path) {
            let stored = try JSONDecoder().decode(State.self, from: Data(contentsOf: file))
            guard UUID(uuidString: stored.installation) != nil, stored.revision >= 0,
                  stored.context == nil || UUID(uuidString: stored.context!) != nil else {
                throw BoundaryError.invalidEnvelope
            }
            if let snapshot = stored.snapshot {
                _ = try DisplaySnapshot.decode(JSONEncoder().encode(snapshot))
                guard snapshot.contextId == stored.context, snapshot.authState == .authenticated else {
                    throw BoundaryError.invalidEnvelope
                }
            }
            state = stored
        }
    }

    public func reconcile() {
        confirmed = false
        requestId = nil
    }

    public func request() -> [String: Any] {
        let id = UUID().uuidString
        requestId = id
        return ["transportVersion": 1, "kind": "contextRequest", "requestId": id]
    }

    @discardableResult public func receive(_ envelope: [String: Any], reply: Bool) throws -> Bool {
        guard let version = integer(envelope["transportVersion"]), version == 1,
              envelope["kind"] as? String == (reply ? "contextReply" : "context"),
              let installation = envelope["phoneInstallationId"] as? String,
              UUID(uuidString: installation) != nil,
              let revision = integer(envelope["boundaryRevision"]), revision >= 0 else {
            throw BoundaryError.invalidEnvelope
        }
        if reply {
            guard let nonce = envelope["requestId"] as? String, nonce == requestId else { return false }
            requestId = nil
        }
        let context = envelope["contextId"] as? String
        guard envelope["contextId"] == nil || (context != nil && UUID(uuidString: context!) != nil) else {
            throw BoundaryError.invalidEnvelope
        }
        if installation != state?.installation && !reply {
            confirmed = false
            hideCached = true
            requestId = nil
            if var cleared = state {
                cleared.snapshot = nil
                try JSONEncoder().encode(cleared).write(to: file, options: .atomic)
                state = cleared
            }
            return false
        }
        if let state, state.installation == installation {
            guard revision >= state.revision else { return false }
            if revision == state.revision && context != state.context {
                confirmed = false
                hideCached = true
                requestId = nil
                throw BoundaryError.conflictingRevision
            }
        }
        var snapshot = installation == state?.installation && context == state?.context ? state?.snapshot : nil
        if let bytes = envelope["snapshotJSON"] as? Data {
            let incoming = try DisplaySnapshot.decode(bytes)
            guard incoming.contextId == context, incoming.authState == .authenticated else {
                throw BoundaryError.invalidEnvelope
            }
            if incoming.revision > (snapshot?.revision ?? -1) { snapshot = incoming }
        } else if envelope["snapshotJSON"] != nil { throw BoundaryError.invalidEnvelope }
        if context == nil { snapshot = nil }
        if context != state?.context || installation != state?.installation {
            confirmed = false
            hideCached = true
        }
        let next = State(installation: installation, revision: revision, context: context, snapshot: snapshot)
        do { try JSONEncoder().encode(next).write(to: file, options: .atomic) }
        catch {
            confirmed = false
            hideCached = true
            requestId = nil
            throw error
        }
        state = next
        hideCached = false
        if reply { confirmed = true }
        return true
    }

    private func integer(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              let exact = Int(exactly: number.doubleValue), NSNumber(value: exact) == number else { return nil }
        return exact
    }
}
