// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WatchSyncContract",
    platforms: [.iOS(.v13), .watchOS(.v10), .macOS(.v13)],
    products: [.library(name: "WatchSyncContract", targets: ["WatchSyncContract"])],
    targets: [
        .target(name: "WatchSyncContract"),
        .testTarget(name: "WatchSyncContractTests", dependencies: ["WatchSyncContract"]),
    ]
)
