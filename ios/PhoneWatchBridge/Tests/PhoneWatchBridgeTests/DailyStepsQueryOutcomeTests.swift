import Foundation
import HealthKit
import Testing
@testable import PhoneWatchBridge

@Test func noSamplesTodayIsEmptyNotErrorOrZero() {
    #expect(DailyStepsQueryOutcome(count: nil, error: HKError(.errorNoData)) == .empty)
    let bridged = NSError(domain: HKErrorDomain, code: HKError.Code.errorNoData.rawValue)
    #expect(DailyStepsQueryOutcome(count: nil, error: bridged) == .empty)
    #expect(DailyStepsQueryOutcome(count: nil, error: nil) == .empty)
}

@Test func realFailuresStayErrors() {
    #expect(DailyStepsQueryOutcome(count: nil, error: HKError(.errorDatabaseInaccessible)) == .error)
    #expect(DailyStepsQueryOutcome(count: nil, error: CocoaError(.fileReadUnknown)) == .error)
    #expect(DailyStepsQueryOutcome(count: 12, error: HKError(.errorAuthorizationDenied)) == .error)
    #expect(DailyStepsQueryOutcome(count: -1, error: nil) == .error)
    #expect(DailyStepsQueryOutcome(count: .nan, error: nil) == .error)
}

@Test func observedCountsIncludingZeroAreAvailable() {
    #expect(DailyStepsQueryOutcome(count: 0, error: nil) == .available(0))
    #expect(DailyStepsQueryOutcome(count: 1234, error: nil) == .available(1234))
}
