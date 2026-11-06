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
    targets: [
        .target(
            name: "Renderer",
            swiftSettings: swiftSettings
        ),
    ],
    swiftLanguageModes: [.v6]
)
