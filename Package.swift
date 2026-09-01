// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PWELumenBar",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "PWELumenBar", targets: ["PWELumenBar"]),
        .library(name: "LumenBarCore", targets: ["LumenBarCore"]),
        .executable(name: "pwelumenctl", targets: ["pwelumenctl"]),
        // Development only — renders the welcome window for the documentation.
        .executable(name: "pwelumenshots", targets: ["pwelumenshots"]),
    ],
    targets: [
        // Display engines. No UI, so every capability can be exercised headlessly.
        .target(name: "LumenBarCore", swiftSettings: [.swiftLanguageMode(.v5)]),
        // The menu itself. A library so both the app and the screenshot renderer
        // can mount the exact same views.
        .target(name: "LumenBarUI", dependencies: ["LumenBarCore"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "PWELumenBar", dependencies: ["LumenBarUI"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "pwelumenctl", dependencies: ["LumenBarCore"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "pwelumenshots", dependencies: ["LumenBarUI"], swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
