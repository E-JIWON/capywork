// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CapyWork",
    platforms: [.macOS(.v15)],
    targets: [
        .target(name: "CapyKit"),
        .executableTarget(name: "CapyWork", dependencies: ["CapyKit"]),
        .testTarget(name: "CapyKitTests", dependencies: ["CapyKit"]),
        .testTarget(name: "CapyWorkTests", dependencies: ["CapyWork", "CapyKit"]),
    ]
)
