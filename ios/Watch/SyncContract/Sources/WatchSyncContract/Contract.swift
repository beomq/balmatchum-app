import Foundation

public enum ContractError: Error { case invalidPayload }

public struct DisplaySnapshot: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let contextId: String
    public let revision: Int
    public let authState: AuthState
    public let selectedDog: Dog?
    public let dailySteps: Steps?

    public enum AuthState: String, Codable, Sendable { case authenticated, signedOut }
    public struct Dog: Codable, Equatable, Sendable {
        public let dogId: String
        public let displayName: String
        public let assetKey: String
    }
    public struct Steps: Codable, Equatable, Sendable {
        public let date: String
        public let timeZone: String
        public let count: Int
        public let observedAt: String
    }

    public static func decode(_ data: Data) throws -> Self {
        let value = try JSONDecoder().decode(Self.self, from: data)
        guard value.schemaVersion == 1, !value.contextId.isEmpty, value.revision >= 0 else {
            throw ContractError.invalidPayload
        }
        if let dog = value.selectedDog {
            guard !dog.dogId.isEmpty, !dog.displayName.isEmpty, !dog.assetKey.isEmpty else {
                throw ContractError.invalidPayload
            }
        }
        if let steps = value.dailySteps {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.isLenient = false
            guard steps.count >= 0, steps.timeZone == "Asia/Seoul",
                  let date = formatter.date(from: steps.date), formatter.string(from: date) == steps.date,
                  utcDate(steps.observedAt) != nil else { throw ContractError.invalidPayload }
        }
        guard value.authState != .signedOut || (value.selectedDog == nil && value.dailySteps == nil) else {
            throw ContractError.invalidPayload
        }
        return value
    }
}

func utcDate(_ value: String) -> Date? {
    guard value.hasSuffix("Z") else { return nil }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: value) { return date }
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: value)
}

public struct GPSRecord: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let kind: String
    public let contextId: String
    public let recordId: String
    public let startedAt: String
    public let endedAt: String
    public let payload: Payload
    public struct Payload: Codable, Equatable, Sendable { public let points: [Point] }
    public struct Point: Codable, Equatable, Sendable {
        public let latitude: Double
        public let longitude: Double
        public let horizontalAccuracyMeters: Double
        public let recordedAt: String
    }
    public static func decode(_ data: Data) throws -> Self {
        let value = try JSONDecoder().decode(Self.self, from: data)
        guard value.schemaVersion == 1, value.kind == "gpsRecord", !value.contextId.isEmpty,
              UUID(uuidString: value.recordId) != nil,
              let start = utcDate(value.startedAt), let end = utcDate(value.endedAt), end >= start else {
            throw ContractError.invalidPayload
        }
        var previous = start
        for point in value.payload.points {
            guard point.latitude.isFinite, (-90...90).contains(point.latitude),
                  point.longitude.isFinite, (-180...180).contains(point.longitude),
                  point.horizontalAccuracyMeters.isFinite, point.horizontalAccuracyMeters >= 0,
                  let time = utcDate(point.recordedAt), time >= previous, time <= end else {
                throw ContractError.invalidPayload
            }
            previous = time
        }
        return value
    }
}

public struct Acknowledgement: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let contextId: String
    public let recordId: String
    public let stage: Stage
    public let errorCode: String?
    public enum Stage: String, Codable, Sendable {
        case transferQueued, phoneReceived, serverSaved
        var rank: Int {
            switch self { case .transferQueued: 0; case .phoneReceived: 1; case .serverSaved: 2 }
        }
    }
    public static func decode(_ data: Data) throws -> Self {
        let value = try JSONDecoder().decode(Self.self, from: data)
        guard value.schemaVersion == 1, !value.contextId.isEmpty, UUID(uuidString: value.recordId) != nil else {
            throw ContractError.invalidPayload
        }
        return value
    }
}

public struct DisplayState {
    public private(set) var contextId: String?
    public private(set) var snapshot: DisplaySnapshot?
    public init() {}
    // Called only by the trusted iPhone authentication boundary, not incoming snapshots.
    public mutating func activate(contextId: String?) {
        self.contextId = contextId
        snapshot = nil
    }
    @discardableResult public mutating func apply(_ incoming: DisplaySnapshot) -> Bool {
        guard incoming.contextId == contextId, incoming.revision > (snapshot?.revision ?? -1) else { return false }
        snapshot = incoming
        return true
    }
}

public struct AcknowledgementState {
    public let contextId: String
    public let recordId: String
    public private(set) var stage: Acknowledgement.Stage = .transferQueued
    public init(contextId: String, recordId: String) {
        self.contextId = contextId
        self.recordId = recordId
    }
    @discardableResult public mutating func apply(_ ack: Acknowledgement) -> Bool {
        guard ack.contextId == contextId, ack.recordId == recordId,
              ack.errorCode == nil, ack.stage.rank > stage.rank else { return false }
        stage = ack.stage
        return true
    }
}
