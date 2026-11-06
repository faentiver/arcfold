import CryptoKit
import Foundation
import Testing

/// The fixtures in the test bundle are exactly the files recorded in
/// Tests/Fixtures/LICENSES.md.
struct FixtureTests {
    @Test(arguments: Fixture.allCases)
    func fixtureMatchesTheRecordedChecksum(_ fixture: Fixture) throws {
        let data = try Data(contentsOf: fixture.url())
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()

        #expect(digest == fixture.sha256)
    }
}
