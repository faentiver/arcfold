// swift-tools-version: 6.4

import PackageDescription

// The same language features as the app target: approachable concurrency in the
// Swift 6 language mode and member import visibility.
let swiftSettings: [SwiftSetting] = [
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("MemberImportVisibility"),
]

let package = Package(
    name: "Renderer",
    platforms: [.iOS(.v27)],
    products: [
        .library(name: "Renderer", targets: ["Renderer"]),
    ],
    dependencies: [
        // The sink protocols and media values come from LibretroKit (ADR 0005).
        // LibretroKit itself knows neither Metal nor AVFoundation.
        .package(path: "../LibretroKit"),
    ],
    targets: [
        .target(
            name: "Renderer",
            dependencies: [
                .product(name: "LibretroKit", package: "LibretroKit"),
            ],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "RendererTests",
            dependencies: ["Renderer"],
            swiftSettings: swiftSettings
        ),
    ],
    swiftLanguageModes: [.v6]
)
