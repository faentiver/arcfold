import Foundation

/// Test programs from `Tests/Fixtures`. project.yml copies them into the test
/// bundles only, never into the app. Origin, license and checksum of each file
/// are listed in `Tests/Fixtures/LICENSES.md`.
enum Fixture: String, CaseIterable, Sendable {
    /// Own GBA test program: picture, PSG tone, input, SRAM boot counter and
    /// heartbeat. The layout is described in
    /// `Tests/Fixtures/gba/selftest/make_gba_selftest.py`.
    case gbaSelftest = "selftest.gba"

    /// The SHA-256 recorded in `Tests/Fixtures/LICENSES.md`.
    var sha256: String {
        switch self {
        case .gbaSelftest: "7df143129e713b1188ec40b3d91bd84ccb95188dd1f6264f2bb75fba4544f9fd"
        }
    }

    /// The file inside this test bundle.
    func url() throws -> URL {
        guard let url = Bundle(for: FixtureBundleToken.self).url(forResource: rawValue, withExtension: nil) else {
            throw FixtureError.missing(rawValue)
        }
        return url
    }
}

enum FixtureError: Error, CustomStringConvertible {
    case missing(String)

    var description: String {
        switch self {
        case let .missing(name): "\(name) is not in the test bundle; check the resources of ArcfoldTests in project.yml"
        }
    }
}

private final class FixtureBundleToken {}
