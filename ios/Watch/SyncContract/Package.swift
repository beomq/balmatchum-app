// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WatchSyncContract",
    products: [.library(name: "WatchSyncContract", targets: ["WatchSyncContract"])],
    targets: [
        .target(name: "WatchSyncContract"),
        .testTarget(name: "WatchSyncContractTests", dependencies: ["WatchSyncContract"]),
    ]
)
