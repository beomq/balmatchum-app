import Foundation
import Testing
@testable import WatchSyncContract

private func recordBytes(context: String = "A", latitude: Double = 37) -> Data {
    Data("""
    {"schemaVersion":1,"kind":"gpsRecord","contextId":"\(context)","recordId":"a1111111-1111-4111-8111-111111111111","startedAt":"2026-10-13T01:00:00Z","endedAt":"2026-10-13T01:01:00Z","payload":{"points":[{"latitude":\(latitude),"longitude":127,"horizontalAccuracyMeters":5,"recordedAt":"2026-10-13T01:00:30Z"}]}}
    """.utf8)
}
private func ackBytes(_ stage: String, context: String = "A", error: String = "null") -> Data {
    Data("""
    {"schemaVersion":1,"contextId":"\(context)","recordId":"a1111111-1111-4111-8111-111111111111","stage":"\(stage)","errorCode":\(error)}
    """.utf8)
}
private func temporaryStore(_ body: (URL) throws -> Void) throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try body(directory.appendingPathComponent("outbox.json"))
}

@Test func outboxRestartIdempotencyAndAccountIsolation() throws {
    try temporaryStore { file in
        let outbox = try DurableOutbox(file: file)
        #expect(try outbox.enqueue(recordBytes()))
        #expect(try !outbox.enqueue(recordBytes()))
        #expect(throws: OutboxError.self) { try outbox.enqueue(recordBytes(latitude: 38)) }
        #expect(try outbox.enqueue(recordBytes(context: "B")))
        let restored = try DurableOutbox(file: file)
        #expect(restored.entries.count == 2)
        #expect(restored.pending(contextId: nil).isEmpty)
        #expect(restored.pending(contextId: "A").count == 1)
        #expect(restored.pending(contextId: "B").count == 1)
        #expect(restored.pending(contextId: "C").isEmpty)
    }
}

@Test func outboxAcknowledgementsPersistWithoutDeletingPayload() throws {
    try temporaryStore { file in
        let outbox = try DurableOutbox(file: file)
        try outbox.enqueue(recordBytes())
        #expect(try !outbox.receive(ackBytes("serverSaved", context: "B")))
        #expect(try !outbox.receive(ackBytes("serverSaved", error: "\"unavailable\"")))
        #expect(try outbox.receive(ackBytes("phoneReceived")))
        let received = try DurableOutbox(file: file)
        #expect(received.pending(contextId: "A").count == 1)
        #expect(received.entries[0].stage == .phoneReceived)
        #expect(try !received.receive(ackBytes("transferQueued")))
        #expect(try received.receive(ackBytes("serverSaved")))
        #expect(try !received.receive(ackBytes("phoneReceived")))
        let saved = try DurableOutbox(file: file)
        #expect(saved.pending(contextId: "A").isEmpty)
        #expect(saved.entries.count == 1)
        #expect(saved.entries[0].stage == .serverSaved)
    }
}

@Test func outboxCorruptionAndWriteFailureDoNotClaimSuccess() throws {
    try temporaryStore { file in
        try Data("broken".utf8).write(to: file)
        #expect(throws: (any Error).self) { try DurableOutbox(file: file) }
        let unavailable = file.appendingPathComponent("child")
        let outbox = try DurableOutbox(file: unavailable)
        #expect(throws: (any Error).self) { try outbox.enqueue(recordBytes()) }
        #expect(outbox.entries.isEmpty)
    }
}

@Test func outboxFailedAcknowledgementWriteDoesNotAdvance() throws {
    try temporaryStore { file in
        let outbox = try DurableOutbox(file: file)
        try outbox.enqueue(recordBytes())
        let original = try Data(contentsOf: file)
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: true)
        #expect(throws: (any Error).self) { try outbox.receive(ackBytes("serverSaved")) }
        #expect(outbox.entries[0].stage == .transferQueued)
        #expect(outbox.pending(contextId: "A").count == 1)
        try FileManager.default.removeItem(at: file)
        try original.write(to: file, options: .atomic)
        #expect(try DurableOutbox(file: file).entries[0].stage == .transferQueued)
    }
}
