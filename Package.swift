// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Lumen",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Lumen", targets: ["Lumen"]),
        .library(name: "LumenCore", targets: ["LumenCore"]),
        .executable(name: "lumenctl", targets: ["lumenctl"]),
    ],
    targets: [
        // Display engines. No UI, so every capability can be exercised headlessly.
        .target(name: "LumenCore", swiftSettings: [.swiftLanguageMode(.v5)]),
        // The menu itself. A library so both the app and the screenshot renderer
        // can mount the exact same views.
        .target(name: "LumenUI", dependencies: ["LumenCore"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "Lumen", dependencies: ["LumenUI"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "lumenctl", dependencies: ["LumenCore"], swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
