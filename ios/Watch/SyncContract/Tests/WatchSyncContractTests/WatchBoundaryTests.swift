import Foundation
import Testing
@testable import WatchSyncContract

@Test func boundaryNonceRestartAndLogoutOrdering() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("boundary.json")
    let installation = UUID().uuidString
    let context = UUID().uuidString
    func envelope(_ revision: Int, _ active: Bool = true) -> [String: Any] {
        var result: [String: Any] = ["transportVersion": 1, "kind": "context", "phoneInstallationId": installation, "boundaryRevision": revision]
        if active { result["contextId"] = context }
        return result
    }
    let boundary = try WatchBoundary(file: file)
    #expect(try !boundary.receive(envelope(1), reply: false))
    #expect(boundary.sendContext == nil)
    let request = boundary.request()
    var reply = envelope(1)
    reply["kind"] = "contextReply"
    reply["requestId"] = request["requestId"]
    #expect(try boundary.receive(reply, reply: true))
    #expect(boundary.sendContext == context)
    #expect(try !boundary.receive(reply, reply: true))
    let restarted = try WatchBoundary(file: file)
    #expect(restarted.sendContext == nil)
    let pending = restarted.request()
    #expect(try restarted.receive(envelope(2, false), reply: false))
    reply["requestId"] = pending["requestId"]
    #expect(try !restarted.receive(reply, reply: true))
    #expect(restarted.sendContext == nil)
    #expect(throws: BoundaryError.self) { try restarted.receive(envelope(2), reply: false) }
    var foreign = envelope(3)
    foreign["phoneInstallationId"] = UUID().uuidString
    #expect(try !boundary.receive(foreign, reply: false))
    #expect(boundary.sendContext == nil)
    #expect(boundary.snapshot == nil)
    let reinstallRequest = boundary.request()
    foreign["kind"] = "contextReply"
    foreign["requestId"] = reinstallRequest["requestId"]
    #expect(try boundary.receive(foreign, reply: true))
    #expect(boundary.sendContext == context)
    #expect(try !boundary.receive(foreign, reply: true))
}

@Test func boundaryDisplayOrderingAndFailedPersistence() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let context = UUID().uuidString
    let boundary = try WatchBoundary(file: directory.appendingPathComponent("boundary.json"))
    func snapshot(_ revision: Int) -> Data {
        Data("""
        {"schemaVersion":1,"contextId":"\(context)","revision":\(revision),"authState":"authenticated","selectedDog":null,"dailySteps":null}
        """.utf8)
    }
    var envelope: [String: Any] = ["transportVersion": 1, "kind": "contextReply",
        "requestId": boundary.request()["requestId"]!, "phoneInstallationId": UUID().uuidString,
        "boundaryRevision": 0, "contextId": context, "snapshotJSON": snapshot(2)]
    #expect(try boundary.receive(envelope, reply: true))
    envelope["kind"] = "context"
    envelope.removeValue(forKey: "requestId")
    envelope["snapshotJSON"] = snapshot(1)
    #expect(try boundary.receive(envelope, reply: false))
    #expect(boundary.snapshot?.revision == 2)
    envelope["snapshotJSON"] = snapshot(3)
    #expect(try boundary.receive(envelope, reply: false))
    #expect(boundary.snapshot?.revision == 3)
    envelope["boundaryRevision"] = 1
    envelope.removeValue(forKey: "snapshotJSON")
    envelope.removeValue(forKey: "contextId")
    #expect(try boundary.receive(envelope, reply: false))
    #expect(boundary.snapshot == nil)
    #expect(boundary.sendContext == nil)
    // A disk failure cannot promote a new boundary or authorize transmission.
    let broken = try WatchBoundary(file: directory.appendingPathComponent("missing/store.json"))
    envelope["kind"] = "contextReply"
    envelope["requestId"] = broken.request()["requestId"]!
    #expect(throws: (any Error).self) { try broken.receive(envelope, reply: true) }
    #expect(!broken.confirmed)
    #expect(broken.sendContext == nil)
}

@Test func boundaryRejectsBooleanOrderingAndHidesOnWriteFailure() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("boundary.json")
    let boundary = try WatchBoundary(file: file)
    let context = UUID().uuidString
    var envelope: [String: Any] = ["transportVersion": 1, "kind": "contextReply",
        "requestId": boundary.request()["requestId"]!, "phoneInstallationId": UUID().uuidString,
        "boundaryRevision": 1, "contextId": context]
    var invalid = envelope
    invalid["transportVersion"] = true
    #expect(throws: BoundaryError.self) { try boundary.receive(invalid, reply: true) }
    invalid = envelope
    invalid["boundaryRevision"] = true
    #expect(throws: BoundaryError.self) { try boundary.receive(invalid, reply: true) }
    invalid["boundaryRevision"] = 1.5
    #expect(throws: BoundaryError.self) { try boundary.receive(invalid, reply: true) }
    #expect(try boundary.receive(envelope, reply: true))
    #expect(boundary.sendContext == context)
    try FileManager.default.removeItem(at: file)
    try FileManager.default.createDirectory(at: file, withIntermediateDirectories: true)
    envelope["kind"] = "context"
    envelope.removeValue(forKey: "requestId")
    #expect(throws: (any Error).self) { try boundary.receive(envelope, reply: false) }
    #expect(!boundary.confirmed)
    #expect(boundary.sendContext == nil)
    #expect(boundary.snapshot == nil)
}
