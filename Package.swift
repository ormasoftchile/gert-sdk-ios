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
        .executable(name: "ComposeExample", targets: ["ComposeExample"]),
        .executable(name: "HomeAutomationExample", targets: ["HomeAutomationExample"]),
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.1.0"),
    ],
    targets: [
        .target(
            name: "GertSDK",
            dependencies: ["Yams"],
            path: "Sources/GertSDK"
        ),
        .executableTarget(
            name: "ComposeExample",
            dependencies: ["GertSDK"],
            path: "Examples/ComposeExample",
            resources: [.copy("Resources/templates")]
        ),
        .executableTarget(
            name: "HomeAutomationExample",
            dependencies: ["GertSDK"],
            path: "Examples/HomeAutomationExample",
            exclude: ["README.md", "Kitfile.yaml"]
        ),
        .testTarget(
            name: "GertSDKTests",
            dependencies: ["GertSDK"],
            path: "Tests/GertSDKTests"
        ),
    ]
)
