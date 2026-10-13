import CoreFoundation
import Foundation
import WatchSyncContract

public enum PhoneTransport {
    public static func isVersionOne(_ value: Any?) -> Bool {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else { return false }
        return number.doubleValue == 1
    }

    public static func contextRequestID(_ message: [String: Any]) throws -> String {
        guard isVersionOne(message["transportVersion"]), message["kind"] as? String == "contextRequest",
              let id = message["requestId"] as? String, UUID(uuidString: id) != nil else {
            throw PhoneBridgeError.invalidInput
        }
        return id
    }

    public static func receive(_ data: Data, metadata: [String: Any]?, into store: PhoneStore) throws
        -> ConfirmedAcknowledgement? {
        guard let metadata, isVersionOne(metadata["transportVersion"]),
              metadata["kind"] as? String == "gpsRecord",
              let context = metadata["contextId"] as? String,
              let record = metadata["recordId"] as? String else { throw PhoneBridgeError.invalidInput }
        return try store.receive(data, contextId: context, recordId: record)
    }

    public static func acknowledgement(in userInfo: [String: Any]) -> Acknowledgement? {
        guard isVersionOne(userInfo["transportVersion"]), userInfo["kind"] as? String == "ack",
              let data = userInfo["ackJSON"] as? Data else { return nil }
        return try? Acknowledgement.decode(data)
    }

    /// Never add a second concurrent transfer for an identity, even when its durable
    /// stage advances. Completion will schedule the higher stage. Global bound: 16.
    public static func nextAcknowledgements(
        durable: [ConfirmedAcknowledgement], outstanding: [Acknowledgement],
        completed: [RecordIdentity: Acknowledgement.Stage], limit: Int = 16
    ) -> [ConfirmedAcknowledgement] {
        let busy = Set(outstanding.map { RecordIdentity(contextId: $0.contextId, recordId: $0.recordId) })
        return Array(durable.filter {
            !busy.contains($0.identity) && completed[$0.identity] != $0.stage
        }.prefix(max(0, limit - outstanding.count)))
    }
}
