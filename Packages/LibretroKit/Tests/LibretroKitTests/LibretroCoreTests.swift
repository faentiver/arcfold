import Foundation
import LibretroKit
import Testing

/// What LibretroKit can show without a real core: discovery and the error paths.
/// Loading mGBA from the app bundle is tested in ArcfoldTests.
struct LibretroCoreTests {
    @Test func missingFrameworkIsReportedWithNameAndPath() throws {
        let fixture = try BundleFixture()

        let error = #expect(throws: LibretroError.self) {
            _ = try LibretroCore(named: "missing_libretro", in: fixture.bundle)
        }

        guard case let .frameworkNotFound(name, path) = error else {
            Issue.record("Expected frameworkNotFound, got \(String(describing: error))")
            return
        }
        #expect(name == "missing_libretro")
        #expect(path.contains("Frameworks/missing_libretro.framework"))
    }

    @Test func invalidBinaryIsReportedWithTheLoaderMessage() throws {
        let fixture = try BundleFixture()
        let binary = try fixture.addFramework(named: "broken_libretro")
        try Data("not a Mach-O file".utf8).write(to: binary)

        let error = #expect(throws: LibretroError.self) {
            _ = try LibretroCore(named: "broken_libretro", in: fixture.bundle)
        }

        guard case let .loadFailed(name, reason) = error else {
            Issue.record("Expected loadFailed, got \(String(describing: error))")
            return
        }
        #expect(name == "broken_libretro")
        #expect(reason.contains("broken_libretro"))
    }

    @Test func libraryWithoutLibretroAPIIsReportedWithTheMissingSymbol() throws {
        let fixture = try BundleFixture()
        let binary = try fixture.addFramework(named: "plain_libretro")
        // Any loadable Mach-O without retro_* exports will do: this test bundle's own binary.
        let testBinary = try #require(Bundle(for: BundleToken.self).executableURL)
        try FileManager.default.createSymbolicLink(at: binary, withDestinationURL: testBinary)

        let error = #expect(throws: LibretroError.self) {
            _ = try LibretroCore(named: "plain_libretro", in: fixture.bundle)
        }

        guard case let .symbolNotFound(name, symbol, reason) = error else {
            Issue.record("Expected symbolNotFound, got \(String(describing: error))")
            return
        }
        #expect(name == "plain_libretro")
        #expect(symbol == "retro_api_version")
        #expect(reason.contains("retro_api_version"))
    }

    @Test func embeddedCoreNamesListOnlyLibretroFrameworks() throws {
        let fixture = try BundleFixture()
        _ = try fixture.addFramework(named: "zeta_libretro")
        _ = try fixture.addFramework(named: "alpha_libretro")
        _ = try fixture.addFramework(named: "MoltenVK")

        #expect(LibretroCore.embeddedCoreNames(in: fixture.bundle) == ["alpha_libretro", "zeta_libretro"])
    }

    @Test func bundleWithoutFrameworksHasNoCores() throws {
        let fixture = try BundleFixture()

        #expect(LibretroCore.embeddedCoreNames(in: fixture.bundle).isEmpty)
    }
}

private final class BundleToken {}

/// A bundle in the temporary folder, removed again when the fixture goes away.
private struct BundleFixture: ~Copyable {
    let url: URL
    let bundle: Bundle

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appending(path: "LibretroKitTests-\(UUID().uuidString).bundle", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        bundle = try #require(Bundle(url: url))
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    /// Creates `Frameworks/<name>.framework` with an Info.plist and returns the
    /// URL where its executable belongs. The executable itself is up to the test.
    func addFramework(named name: String) throws -> URL {
        let frameworkURL = url.appending(path: "Frameworks/\(name).framework", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: frameworkURL, withIntermediateDirectories: true)
        let infoPlist: [String: String] = [
            "CFBundleExecutable": name,
            "CFBundleIdentifier": "test.\(name)",
            "CFBundlePackageType": "FMWK",
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: infoPlist, format: .xml, options: 0)
        try data.write(to: frameworkURL.appending(path: "Info.plist"))
        return frameworkURL.appending(path: name)
    }
}
