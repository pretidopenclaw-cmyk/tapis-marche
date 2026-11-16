// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WalkingPadKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "WalkingPadKit", targets: ["WalkingPadKit"]),
    ],
    targets: [
        .target(name: "WalkingPadKit"),
        .testTarget(name: "WalkingPadKitTests", dependencies: ["WalkingPadKit"]),
    ]
)
