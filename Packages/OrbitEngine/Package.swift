// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OrbitEngine",
    platforms: [.watchOS(.v11), .macOS(.v14), .iOS(.v18)],
    products: [
        .library(name: "OrbitEngine", targets: ["OrbitEngine"]),
    ],
    targets: [
        .target(
            name: "OrbitEngine",
            resources: [.copy("Resources/levels")]
        ),
        .testTarget(
            name: "OrbitEngineTests",
            dependencies: ["OrbitEngine"]
        ),
    ]
)
