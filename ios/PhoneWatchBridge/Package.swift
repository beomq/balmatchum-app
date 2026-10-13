// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PhoneWatchBridge",
    platforms: [.iOS(.v13), .macOS(.v13)],
    products: [.library(name: "PhoneWatchBridge", targets: ["PhoneWatchBridge"])],
    dependencies: [.package(path: "../Watch/SyncContract")],
    targets: [
        .target(name: "PhoneWatchBridge", dependencies: [
            .product(name: "WatchSyncContract", package: "SyncContract"),
        ]),
        .testTarget(name: "PhoneWatchBridgeTests", dependencies: ["PhoneWatchBridge"]),
    ]
)
