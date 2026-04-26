// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GertSDK",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(name: "GertSDK", targets: ["GertSDK"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "GertSDK",
            dependencies: [],
            path: "Sources/GertSDK"
        ),
        .testTarget(
            name: "GertSDKTests",
            dependencies: ["GertSDK"],
            path: "Tests/GertSDKTests"
        ),
    ]
)
