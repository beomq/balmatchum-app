// Simulator-only executable. Never add this file to the product Watch target.
import SwiftUI
import WatchSyncContract

@main
struct WatchPreviewApp: App {
    private var scenario: String { ProcessInfo.processInfo.arguments.dropFirst().first ?? "signedOut" }
    private var snapshot: DisplaySnapshot? {
        if scenario == "signedOut" { return nil }
        let dog = scenario == "noDog" ? "null" : "{\"dogId\":\"fixture\",\"displayName\":\"미리보기 보리\",\"assetKey\":\"\(scenario == "unsupported" ? "unsupported" : "dog.preview.shih-tzu")\"}"
        let steps = scenario == "nullSteps" ? "null" : "{\"date\":\"2026-10-13\",\"timeZone\":\"Asia/Seoul\",\"count\":\(scenario == "zero" ? 0 : 4321),\"observedAt\":\"2026-10-13T01:00:00Z\"}"
        return try? DisplaySnapshot.decode(Data("""
        {"schemaVersion":1,"contextId":"preview","revision":1,"authState":"authenticated","selectedDog":\(dog),"dailySteps":\(steps)}
        """.utf8))
    }
    var body: some Scene {
        WindowGroup {
            VStack(spacing: 0) {
                Text("테스트 미리보기").font(.system(size: 9)).foregroundStyle(.orange)
                WatchDashboard(snapshot: snapshot,
                    connectionMessage: scenario == "stale" ? "iPhone 상태 확인 중 · 이전 정보" : scenario == "offline" ? "오프라인 · 마지막 정보" : "미리보기 데이터",
                    storageError: scenario == "error")
            }
            .environment(\.dynamicTypeSize, ProcessInfo.processInfo.arguments.contains("largeText") ? .accessibility3 : .large)
        }
    }
}
