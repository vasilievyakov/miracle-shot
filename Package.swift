// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MiracleShot",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MiracleShot", targets: ["MiracleShotApp"]),
    ],
    targets: [
        .target(
            name: "MiracleShotCore",
            resources: [.copy("Resources/presets"), .copy("Resources/fonts")]
        ),
        .target(
            name: "MiracleShotUI",
            dependencies: ["MiracleShotCore"]
        ),
        .executableTarget(
            name: "MiracleShotApp",
            dependencies: ["MiracleShotUI", "MiracleShotCore"]
        ),
        .testTarget(
            name: "MiracleShotCoreTests",
            dependencies: ["MiracleShotCore"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "MiracleShotAppTests",
            dependencies: ["MiracleShotUI", "MiracleShotCore"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
