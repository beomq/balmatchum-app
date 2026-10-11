import Foundation
import Testing
@testable import WatchSyncContract

private let recordID = "a1111111-1111-4111-8111-111111111111"
private func data(_ text: String) -> Data { Data(text.utf8) }
private func snapshot(_ context: String = "A", _ revision: Int = 1, steps: String = "null") throws -> DisplaySnapshot {
    try DisplaySnapshot.decode(data("""
    {"schemaVersion":1,"contextId":"\(context)","revision":\(revision),"authState":"authenticated","selectedDog":null,"dailySteps":\(steps)}
    """))
}
private func ack(_ stage: String, context: String = "A", id: String = recordID) throws -> Acknowledgement {
    try Acknowledgement.decode(data("""
    {"schemaVersion":1,"contextId":"\(context)","recordId":"\(id)","stage":"\(stage)"}
    """))
}

@Test func contextBoundaryAndRevision() throws {
    var state = DisplayState()
    #expect(!state.apply(try snapshot()))
    state.activate(contextId: "A")
    #expect(state.apply(try snapshot("A", 2)))
    let staleAccepted = state.apply(try snapshot("A", 1))
    #expect(!staleAccepted)
    #expect(!state.apply(try snapshot("A", 2)))
    #expect(!state.apply(try snapshot("B", 99)))
    state.activate(contextId: "B")
    #expect(state.snapshot == nil)
    #expect(!state.apply(try snapshot("A", 100)))
    #expect(state.apply(try snapshot("B", 0)))
    state.activate(contextId: nil)
    #expect(state.snapshot == nil)
    #expect(!state.apply(try snapshot("B", 101)))
}

@Test func stepsNullZeroAndValidation() throws {
    #expect(try snapshot().dailySteps == nil)
    let steps = """
    {"date":"2026-10-09","timeZone":"Asia/Seoul","count":0,"observedAt":"2026-10-09T01:00:00Z"}
    """
    let zero = try snapshot(steps: steps)
    #expect(zero.dailySteps?.count == 0)
    #expect(try DisplaySnapshot.decode(JSONEncoder().encode(zero)) == zero)
    for bad in [steps.replacingOccurrences(of: "2026-10-09", with: "2026-02-30"),
                steps.replacingOccurrences(of: "Asia/Seoul", with: "UTC"),
                steps.replacingOccurrences(of: "\"count\":0", with: "\"count\":-1")] {
        #expect(throws: (any Error).self) { try snapshot(steps: bad) }
    }
}

@Test func explicitNullAndSignedOutBoundary() throws {
    let value = try snapshot()
    let encoded = try JSONEncoder().encode(value)
    let object = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
    #expect(object["selectedDog"] is NSNull)
    #expect(object["dailySteps"] is NSNull)
    var missing = object
    missing.removeValue(forKey: "dailySteps")
    #expect(throws: (any Error).self) {
        try DisplaySnapshot.decode(JSONSerialization.data(withJSONObject: missing))
    }
    var state = DisplayState()
    state.activate(contextId: "A")
    #expect(state.apply(try snapshot("A", 2)))
    state.activate(contextId: "A")
    #expect(!state.apply(try snapshot("A", 1)))
    let signedOut = try DisplaySnapshot.decode(data("""
    {"schemaVersion":1,"contextId":"A","revision":3,"authState":"signedOut","selectedDog":null,"dailySteps":null}
    """))
    let logoutAccepted = state.apply(signedOut)
    #expect(logoutAccepted)
    #expect(state.snapshot == nil)
    #expect(state.contextId == nil)
    let afterLogoutAccepted = state.apply(try snapshot("A", 4))
    #expect(!afterLogoutAccepted)
}

@Test func acknowledgementMonotonicAndScoped() throws {
    var state = AcknowledgementState(contextId: "A", recordId: recordID)
    #expect(state.stage == .transferQueued)
    #expect(!state.apply(try ack("serverSaved", context: "B")))
    #expect(!state.apply(try ack("serverSaved", id: "b1111111-1111-4111-8111-111111111111")))
    #expect(state.apply(try ack("phoneReceived")))
    #expect(state.stage != .serverSaved)
    #expect(!state.apply(try ack("transferQueued")))
    #expect(state.apply(try ack("serverSaved")))
    #expect(!state.apply(try ack("phoneReceived")))
    #expect(!state.apply(try ack("serverSaved")))
}

@Test func gpsBoundaryAndRoundtrip() throws {
    #expect(!validRecordID("12345678-1234-1234-1234-123456789abc"))
    #expect(validRecordID("12345678-1234-4234-8234-123456789abc"))
    let json = """
    {"schemaVersion":1,"kind":"gpsRecord","contextId":"A","recordId":"\(recordID)","startedAt":"2026-10-09T01:00:00Z","endedAt":"2026-10-09T01:01:00Z","payload":{"points":[{"latitude":37.5,"longitude":127,"horizontalAccuracyMeters":5,"recordedAt":"2026-10-09T01:00:30Z"}]}}
    """
    let record = try GPSRecord.decode(data(json))
    #expect(try GPSRecord.decode(JSONEncoder().encode(record)) == record)
    for bad in [json.replacingOccurrences(of: "37.5", with: "91"),
                json.replacingOccurrences(of: "\"schemaVersion\":1", with: "\"schemaVersion\":2"),
                json.replacingOccurrences(of: "01:00:30", with: "02:00:00"),
                json.replacingOccurrences(of: "\"horizontalAccuracyMeters\":5", with: "\"horizontalAccuracyMeters\":-1")] {
        #expect(throws: (any Error).self) { try GPSRecord.decode(data(bad)) }
    }
}

@Test func gpsTimestampIntervalAndOrder() throws {
    func record(_ times: [String]) throws -> GPSRecord {
        let points = times.map {
            "{\"latitude\":37.5,\"longitude\":127,\"horizontalAccuracyMeters\":5,\"recordedAt\":\"2026-10-09T\($0)Z\"}"
        }.joined(separator: ",")
        return try GPSRecord.decode(data("""
        {"schemaVersion":1,"kind":"gpsRecord","contextId":"A","recordId":"\(recordID)","startedAt":"2026-10-09T01:00:00Z","endedAt":"2026-10-09T01:01:00Z","payload":{"points":[\(points)]}}
        """))
    }
    #expect(try record(["01:00:00", "01:00:30", "01:00:30", "01:01:00"]).payload.points.count == 4)
    for times in [["00:59:59"], ["01:01:01"], ["01:00:30", "01:00:29"]] {
        #expect(throws: ContractError.self) { try record(times) }
    }
}

@Test func appFixtureCrossCheck() throws {
    // Supplied explicitly by the integration command; normal package tests remain standalone.
    guard let path = ProcessInfo.processInfo.environment["APP_WATCH_FIXTURE"] else { return }
    let object = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: path))) as! [String: Any]
    let snapshotData = try JSONSerialization.data(withJSONObject: object["snapshot"]!)
    let recordData = try JSONSerialization.data(withJSONObject: object["record"]!)
    let ackData = try JSONSerialization.data(withJSONObject: object["ack"]!)
    let display = try DisplaySnapshot.decode(snapshotData)
    let record = try GPSRecord.decode(recordData)
    let acknowledgement = try Acknowledgement.decode(ackData)
    #expect(display.contextId == record.contextId)
    #expect(record.recordId == acknowledgement.recordId)
    #expect(try DisplaySnapshot.decode(JSONEncoder().encode(display)) == display)
    #expect(try GPSRecord.decode(JSONEncoder().encode(record)) == record)
    #expect(try Acknowledgement.decode(JSONEncoder().encode(acknowledgement)) == acknowledgement)
}
