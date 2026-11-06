import XCTest

/// Starts the app the way a person does. Track A of M1 extends this with the
/// library, a running game and the Licenses screen.
final class LaunchTests: XCTestCase {
    @MainActor
    func testAppLaunchesToANavigationScreen() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 20))
    }
}
