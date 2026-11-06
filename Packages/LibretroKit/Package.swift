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
    name: "LibretroKit",
    platforms: [.iOS(.v27)],
    products: [
        .library(name: "LibretroKit", targets: ["LibretroKit"]),
    ],
    targets: [
        // libretro.h from libretro/libretro-common, see Sources/CLibretro/README.md.
        .target(
            name: "CLibretro",
            exclude: ["README.md"]
        ),
        .target(
            name: "LibretroKit",
            dependencies: ["CLibretro"],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "LibretroKitTests",
            // CLibretro gives the tests the constants of libretro.h.
            dependencies: ["LibretroKit", "CLibretro"],
            swiftSettings: swiftSettings
        ),
    ],
    swiftLanguageModes: [.v6]
)
