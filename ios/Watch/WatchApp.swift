import SwiftUI

@main
struct BalmatchumWatchApp: App {
    @StateObject private var connectivity = WatchConnectivityStore()
    var body: some Scene {
        WindowGroup {
            WatchDashboard(snapshot: connectivity.snapshot,
                           connectionMessage: connectivity.message,
                           storageError: connectivity.storageError)
        }
    }
}
