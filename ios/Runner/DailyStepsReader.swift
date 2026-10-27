import Foundation
import HealthKit

final class DailyStepsReader {
    private let store = HKHealthStore()

    /// Called only by the user-initiated MethodChannel request. Authorization's
    /// success is permission-dialog completion, never evidence of read access.
    func request(_ completion: @escaping ([String: Any]) -> Void) {
        func finish(_ status: String, _ steps: [String: Any]? = nil) {
            completion(["status": status, "dailySteps": steps as Any? ?? NSNull()])
        }
        // iOS does not expose macOS SecTask entitlement inspection. The app owner
        // may enable this only after verifying the signed target/profile entitlement.
        // Missing configuration must never call HK; device profiles are a release gate.
        guard Bundle.main.object(forInfoDictionaryKey: "BalmatchumHealthKitCapabilityVerified") as? Bool == true,
              let description = Bundle.main.object(forInfoDictionaryKey: "NSHealthShareUsageDescription") as? String,
              !description.isEmpty else {
            finish("capabilityUnavailable")
            return
        }
        guard HKHealthStore.isHealthDataAvailable(),
              let type = HKObjectType.quantityType(forIdentifier: .stepCount) else {
            finish("unavailable")
            return
        }
        store.requestAuthorization(toShare: [], read: [type]) { [self] completed, error in
            guard completed, error == nil else { finish("error"); return }
            let now = Date()
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
            let start = calendar.startOfDay(for: now)
            let predicate = HKQuery.predicateForSamples(withStart: start, end: now, options: .strictStartDate)
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate,
                                          options: .cumulativeSum) { _, statistics, error in
                guard error == nil else { finish("error"); return }
                guard let quantity = statistics?.sumQuantity() else { finish("empty"); return }
                let count = quantity.doubleValue(for: .count())
                guard count.isFinite, count >= 0, count < Double(Int.max) else { finish("error"); return }
                let date = DateFormatter()
                date.locale = Locale(identifier: "en_US_POSIX")
                date.calendar = calendar
                date.timeZone = calendar.timeZone
                date.dateFormat = "yyyy-MM-dd"
                finish("available", ["date": date.string(from: now), "timeZone": "Asia/Seoul",
                                     "count": Int(count), "observedAt": ISO8601DateFormatter().string(from: now)])
            }
            store.execute(query)
        }
    }
}
