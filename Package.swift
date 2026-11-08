// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Still",
    platforms: [.macOS("27.0")],
    products: [.executable(name: "Still", targets: ["StillApp"])],
    targets: [
        .target(name: "CullingCore"),
        .executableTarget(name: "StillApp", dependencies: ["CullingCore"]),
        .testTarget(name: "CullingCoreTests", dependencies: ["CullingCore"])
    ]
)
