import Foundation
import Testing
import WatchSyncContract
@testable import PhoneWatchBridge

private final class MemoryDisk: PhonePersistence {
    var bytes: Data?
    var fail = false
    var writes = 0
    func load() throws -> Data? { bytes }
    func replace(with data: Data) throws {
        if fail { throw CocoaError(.fileWriteOutOfSpace) }
        bytes = data
        writes += 1
    }
}

private let recordID = "a1111111-1111-4111-8111-111111111111"
private let serverID = "b1111111-1111-4111-8111-111111111111"

private func record(_ context: String, id: String = recordID, latitude: Double = 37.5) -> Data {
    Data("""
    {"schemaVersion":1,"kind":"gpsRecord","contextId":"\(context)","recordId":"\(id)",
    "startedAt":"2026-10-13T01:00:00Z","endedAt":"2026-10-13T01:01:00Z",
    "payload":{"points":[{"latitude":\(latitude),"longitude":127,"horizontalAccuracyMeters":5,"recordedAt":"2026-10-13T01:00:30Z"}]}}
    """.utf8)
}

private func snapshot(_ context: String, revision: Int) -> Data {
    Data("""
    {"schemaVersion":1,"contextId":"\(context)","revision":\(revision),"authState":"authenticated","selectedDog":null,"dailySteps":null}
    """.utf8)
}

private func receipt(_ context: String, client: String = recordID, server: String = serverID) throws -> ServerReceipt {
    try ServerReceipt(contextId: context, clientRecordId: client, recordId: server,
                      persistedAt: "2026-10-13T02:00:00Z", schemaVersion: 1)
}

@Test func stableMappingInstallationBoundariesAndColdLaunch() throws {
    let disk = MemoryDisk()
    let store = try PhoneStore(persistence: disk)
    let initial = try store.contextEnvelope()
    #expect(initial["boundaryRevision"] as? Int == 0)
    #expect(initial["contextId"] == nil)
    let a = try store.activate(accountId: "account-a")
    #expect(a.latestDisplayRevision == 0)
    #expect(a.boundaryRevision == 1)
    #expect(try store.activate(accountId: "account-a").boundaryRevision == 1)
    try store.publishDisplay(snapshot(a.contextId, revision: 8))
    let b = try store.activate(accountId: "account-b")
    #expect(b.contextId != a.contextId)
    #expect(b.boundaryRevision == 2)
    #expect(try store.contextEnvelope()["snapshotJSON"] == nil)
    let back = try store.activate(accountId: "account-a")
    #expect(back.contextId == a.contextId)
    #expect(back.latestDisplayRevision == 8)
    let restored = try PhoneStore(persistence: disk)
    let boundary = try restored.contextEnvelope()
    #expect(boundary["phoneInstallationId"] as? String == initial["phoneInstallationId"] as? String)
    #expect(boundary["boundaryRevision"] as? Int == 4)
    #expect(boundary["contextId"] == nil)
    #expect(boundary["snapshotJSON"] == nil)
    let validated = try restored.activate(accountId: "account-a")
    #expect(validated.contextId == a.contextId)
    #expect(validated.latestDisplayRevision == 8)
    #expect(throws: PhoneBridgeError.self) { try restored.publishDisplay(snapshot(a.contextId, revision: 8)) }
    try restored.publishDisplay(snapshot(a.contextId, revision: 9))
    try restored.clearContext()
    let revision = try restored.contextEnvelope()["boundaryRevision"] as? Int
    try restored.clearContext()
    #expect(try restored.contextEnvelope()["boundaryRevision"] as? Int == revision)
    #expect(throws: PhoneBridgeError.self) { try restored.publishDisplay(snapshot(a.contextId, revision: 10)) }
}

@Test func displayDoesNotActivateAndNeverAcceptsSignedOutBody() throws {
    let store = try PhoneStore(persistence: MemoryDisk())
    let context = UUID().uuidString
    #expect(throws: PhoneBridgeError.self) { try store.publishDisplay(snapshot(context, revision: 1)) }
    let a = try store.activate(accountId: "a")
    let data = snapshot(a.contextId, revision: 1)
    let signedOut = Data(String(decoding: data, as: UTF8.self).replacingOccurrences(of: "authenticated", with: "signedOut").utf8)
    #expect(throws: PhoneBridgeError.self) { try store.publishDisplay(signedOut) }
    #expect(try store.contextEnvelope()["contextId"] as? String == a.contextId)
}

@Test func semanticDuplicateAndConflictAreNotByteComparisons() throws {
    let disk = MemoryDisk()
    let store = try PhoneStore(persistence: disk)
    let context = try store.activate(accountId: "a").contextId
    let original = record(context)
    let received = try store.receive(original, contextId: context, recordId: recordID)
    #expect(received?.stage == .phoneReceived)
    let writes = disk.writes
    let object = try JSONSerialization.jsonObject(with: original)
    let reordered = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .prettyPrinted])
    #expect(reordered != original)
    #expect(try store.receive(reordered, contextId: context, recordId: recordID)?.stage == .phoneReceived)
    #expect(disk.writes == writes)
    #expect(try store.pendingRecords().count == 1)
    #expect(throws: PhoneBridgeError.self) {
        try store.receive(record(context, latitude: 38), contextId: context, recordId: recordID)
    }
    #expect(throws: PhoneBridgeError.self) {
        try store.receive(original, contextId: context, recordId: serverID)
    }
    #expect(throws: ContractError.self) {
        try store.receive(record(context, latitude: 91), contextId: context, recordId: recordID)
    }
}

@Test func oldContextRetainedUnknownQuarantinedAndNeverAdopted() throws {
    let disk = MemoryDisk()
    let store = try PhoneStore(persistence: disk)
    let a = try store.activate(accountId: "a").contextId
    let b = try store.activate(accountId: "b").contextId
    #expect(try store.receive(record(a), contextId: a, recordId: recordID)?.stage == .phoneReceived)
    #expect(try store.pendingRecords().isEmpty)
    let unknown = UUID().uuidString
    #expect(try store.receive(record(unknown), contextId: unknown, recordId: recordID) == nil)
    #expect(try store.acknowledgements().count == 1)
    #expect(try store.contextEnvelope()["contextId"] as? String == b)
    let restored = try PhoneStore(persistence: disk)
    #expect(try restored.pendingRecords().isEmpty)
    _ = try restored.activate(accountId: "a")
    #expect(try restored.pendingRecords().count == 1)
    #expect(try restored.receive(record(unknown), contextId: unknown, recordId: recordID) == nil)
    #expect(try restored.acknowledgements().count == 1)
}

@Test func receiptUsesClientIdentityAndLateResponseCannotChangeCurrentAccount() throws {
    let disk = MemoryDisk()
    let store = try PhoneStore(persistence: disk)
    let a = try store.activate(accountId: "a").contextId
    try store.receive(record(a), contextId: a, recordId: recordID)
    let b = try store.activate(accountId: "b").contextId
    try store.publishDisplay(snapshot(b, revision: 4))
    try store.receive(record(b), contextId: b, recordId: recordID)
    let before = try store.contextEnvelope()
    let ack = try store.acknowledge(receipt(a))
    #expect(ack.stage == .serverSaved)
    let body = try Acknowledgement.decode(ack.json)
    #expect(body.recordId == recordID)
    #expect(body.recordId != serverID)
    #expect(body.contextId == a)
    #expect(try store.pendingRecords().count == 1)
    #expect(try store.contextEnvelope()["boundaryRevision"] as? Int == before["boundaryRevision"] as? Int)
    #expect(try store.contextEnvelope()["snapshotJSON"] as? Data == before["snapshotJSON"] as? Data)
    #expect(throws: PhoneBridgeError.self) { try store.acknowledge(receipt(a, client: serverID)) }
    #expect(throws: PhoneBridgeError.self) { try store.acknowledge(receipt(a, server: UUID().uuidString)) }
    #expect(try store.acknowledge(receipt(a)).stage == .serverSaved)
    #expect(try store.receive(record(a), contextId: a, recordId: recordID)?.stage == .serverSaved)
    let restored = try PhoneStore(persistence: disk)
    _ = try restored.activate(accountId: "a")
    #expect(try restored.pendingRecords().isEmpty)
    #expect(try restored.acknowledgements().count == 2)
}

@Test func failedInboxWriteCannotProduceAckOrForgetPreviousBytes() throws {
    let disk = MemoryDisk()
    let store = try PhoneStore(persistence: disk)
    let context = try store.activate(accountId: "a").contextId
    let before = disk.bytes
    disk.fail = true
    #expect(throws: (any Error).self) { try store.receive(record(context), contextId: context, recordId: recordID) }
    #expect(disk.bytes == before)
    #expect(throws: PhoneBridgeError.self) { try store.acknowledgements() }
    #expect(throws: PhoneBridgeError.self) { try store.contextEnvelope() }
    disk.fail = false
    let restored = try PhoneStore(persistence: disk)
    #expect(try restored.acknowledgements().isEmpty)
    #expect(try restored.contextEnvelope()["contextId"] == nil)
}

@Test func failedReceiptWriteRetainsPhoneReceivedAndReplayableRecord() throws {
    let disk = MemoryDisk()
    let store = try PhoneStore(persistence: disk)
    let context = try store.activate(accountId: "a").contextId
    try store.receive(record(context), contextId: context, recordId: recordID)
    let before = disk.bytes
    disk.fail = true
    #expect(throws: (any Error).self) { try store.acknowledge(receipt(context)) }
    #expect(disk.bytes == before)
    disk.fail = false
    let restored = try PhoneStore(persistence: disk)
    _ = try restored.activate(accountId: "a")
    #expect(try restored.pendingRecords().count == 1)
    #expect(try restored.acknowledgements().first?.stage == .phoneReceived)
}

@Test func failedLogoutActivationDisplayAndColdLaunchAllFailClosed() throws {
    for operation in ["logout", "activate", "display", "coldLaunch"] {
        let disk = MemoryDisk()
        let store = try PhoneStore(persistence: disk)
        let context = try store.activate(accountId: "a").contextId
        let before = disk.bytes
        disk.fail = true
        #expect(throws: (any Error).self) {
            switch operation {
            case "logout": try store.clearContext()
            case "activate": _ = try store.activate(accountId: "b")
            case "display": try store.publishDisplay(snapshot(context, revision: 1))
            default: _ = try PhoneStore(persistence: disk)
            }
        }
        #expect(disk.bytes == before)
        if operation != "coldLaunch" {
            #expect(throws: PhoneBridgeError.self) { try store.contextEnvelope() }
            #expect(throws: PhoneBridgeError.self) { try store.pendingRecords() }
        }
    }
}

@Test func corruptionDoesNotResetInstallationOrOverwriteDisk() throws {
    let disk = MemoryDisk()
    disk.bytes = Data("broken".utf8)
    #expect(throws: PhoneBridgeError.self) { try PhoneStore(persistence: disk) }
    #expect(disk.writes == 0)
    #expect(disk.bytes == Data("broken".utf8))
}

@Test func callbackHarnessRequiresMetadataAndFreshHandshakeShape() throws {
    let store = try PhoneStore(persistence: MemoryDisk())
    let context = try store.activate(accountId: "a").contextId
    let metadata: [String: Any] = ["transportVersion": 1, "kind": "gpsRecord", "contextId": context, "recordId": recordID]
    #expect(try PhoneTransport.receive(record(context), metadata: metadata, into: store)?.stage == .phoneReceived)
    for bad: [String: Any]? in [nil, [:], metadata.merging(["transportVersion": true]) { _, new in new },
                                metadata.merging(["contextId": UUID().uuidString]) { _, new in new }] {
        #expect(throws: (any Error).self) { try PhoneTransport.receive(record(context), metadata: bad, into: store) }
    }
    let request = UUID().uuidString
    let id = try PhoneTransport.contextRequestID(["transportVersion": 1, "kind": "contextRequest", "requestId": request])
    let reply = try store.contextEnvelope(requestId: id)
    #expect(reply["requestId"] as? String == request)
    #expect(reply["kind"] as? String == "contextReply")
    #expect(!reply.keys.contains("accountId"))
    #expect(throws: PhoneBridgeError.self) { try PhoneTransport.contextRequestID(["transportVersion": 1, "kind": "contextRequest"]) }
    #expect(try PropertyListSerialization.data(fromPropertyList: reply, format: .binary, options: 0).count > 0)
}

@Test func watchAndPhonePersistAcrossLostAcknowledgementAndRestart() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let phoneDisk = FilePhonePersistence(url: root.appendingPathComponent("phone.json"))
    let phone = try PhoneStore(persistence: phoneDisk)
    let context = try phone.activate(accountId: "account-a").contextId
    let boundary = try WatchBoundary(file: root.appendingPathComponent("boundary.json"))
    let nonce = try PhoneTransport.contextRequestID(boundary.request())
    #expect(try boundary.receive(phone.contextEnvelope(requestId: nonce), reply: true))
    #expect(boundary.sendContext == context)
    let outboxURL = root.appendingPathComponent("outbox.json")
    let watch = try DurableOutbox(file: outboxURL)
    let bytes = record(context)
    try watch.enqueue(bytes)
    let metadata: [String: Any] = ["transportVersion": 1, "kind": "gpsRecord",
                                   "contextId": context, "recordId": recordID]
    let received = try #require(try PhoneTransport.receive(bytes, metadata: metadata, into: phone))
    #expect(try watch.receive(received.json))
    #expect(try DurableOutbox(file: outboxURL).entries.first?.stage == .phoneReceived)
    let reopenedPhone = try PhoneStore(persistence: phoneDisk)
    #expect(try reopenedPhone.pendingRecords().isEmpty)
    #expect(try reopenedPhone.activate(accountId: "account-a").contextId == context)
    #expect(try reopenedPhone.pendingRecords().count == 1)
    // This is a fixture receipt at the API boundary, not a real server claim.
    // Drop the outgoing ACK, then restart and replay the durable receipt.
    _ = try reopenedPhone.acknowledge(receipt(context))
    let recoveredPhone = try PhoneStore(persistence: phoneDisk)
    let saved = try #require(try recoveredPhone.acknowledgements().first)
    let recoveredWatch = try DurableOutbox(file: outboxURL)
    #expect(try recoveredWatch.receive(saved.json))
    #expect(recoveredWatch.pending(contextId: context).isEmpty)
    #expect(recoveredWatch.entries.count == 1)
    _ = try recoveredPhone.activate(accountId: "account-b")
    #expect(try recoveredPhone.pendingRecords().isEmpty)
    #expect(try !recoveredWatch.receive(received.json))
    #expect(recoveredWatch.entries.first?.stage == .serverSaved)
}

@Test func outstandingTransfersBoundedAcrossStageAdvanceAndReconnect() throws {
    let store = try PhoneStore(persistence: MemoryDisk())
    let context = try store.activate(accountId: "a").contextId
    let received = try store.receive(record(context), contextId: context, recordId: recordID)
    let first = try #require(received)
    let pending = try Acknowledgement.decode(first.json)
    _ = try store.acknowledge(receipt(context))
    var durable = try store.acknowledgements()
    #expect(PhoneTransport.nextAcknowledgements(durable: durable, outstanding: [pending], completed: [:]).isEmpty)
    #expect(PhoneTransport.nextAcknowledgements(durable: durable, outstanding: [], completed: [first.identity: .phoneReceived]).first?.stage == .serverSaved)
    #expect(PhoneTransport.nextAcknowledgements(durable: durable, outstanding: [], completed: [first.identity: .serverSaved]).isEmpty)
    for _ in 0..<20 {
        let id = UUID().uuidString
        try store.receive(record(context, id: id), contextId: context, recordId: id)
    }
    durable = try store.acknowledgements()
    #expect(PhoneTransport.nextAcknowledgements(durable: durable, outstanding: [], completed: [:]).count == 16)
    #expect(PhoneTransport.nextAcknowledgements(durable: durable, outstanding: [pending], completed: [:]).count == 15)
}

@Test func realFilePersistenceSurvivesReopening() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let persistence = FilePhonePersistence(url: directory.appendingPathComponent("state-v1.json"))
    let store = try PhoneStore(persistence: persistence)
    let context = try store.activate(accountId: "a").contextId
    try store.receive(record(context), contextId: context, recordId: recordID)
    let restored = try PhoneStore(persistence: persistence)
    #expect(try restored.contextEnvelope()["contextId"] == nil)
    #expect(try restored.activate(accountId: "a").contextId == context)
    #expect(try restored.pendingRecords().count == 1)
}
