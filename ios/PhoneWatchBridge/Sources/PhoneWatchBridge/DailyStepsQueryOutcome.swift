import Foundation
import HealthKit

/// HealthKit reports a day without samples as `errorNoData` (or a nil sum).
/// That is "no data", never a failure and never zero steps.
public enum DailyStepsQueryOutcome: Equatable, Sendable {
    case available(Int)
    case empty
    case error

    public init(count: Double?, error: (any Error)?) {
        if let error {
            // The package supports iOS 13, where HealthKit has no errorNoData.
            guard #available(iOS 14.0, *) else { self = .error; return }
            self = (error as? HKError)?.code == .errorNoData ? .empty : .error
            return
        }
        guard let count else { self = .empty; return }
        guard count.isFinite, count >= 0, count < Double(Int.max) else { self = .error; return }
        self = .available(Int(count))
    }
}
