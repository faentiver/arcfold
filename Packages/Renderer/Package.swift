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
        // The audio ring and its real-time render block in C and Objective-C,
        // because Swift is not supported on audio real-time threads (ADR 0005).
        .target(
            name: "CRendererAudio",
            linkerSettings: [.linkedFramework("AVFAudio")]
        ),
        .target(
            name: "Renderer",
            dependencies: [
                "CRendererAudio",
                .product(name: "LibretroKit", package: "LibretroKit"),
            ],
            // Compiled by Xcode into default.metallib inside Bundle.module.
            resources: [.process("Shaders")],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "RendererTests",
            dependencies: ["Renderer", "CRendererAudio"],
            swiftSettings: swiftSettings
        ),
    ],
    swiftLanguageModes: [.v6]
)
