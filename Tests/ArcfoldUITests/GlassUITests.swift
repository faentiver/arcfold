import XCTest

/// The pause menu as a system sheet and the placement of the overlays
/// (ADR 0007).
final class GlassUITests: GlassUITestCase {
    override func tearDown() {
        // UI tests run on the main thread.
        MainActor.assumeIsolated {
            XCUIDevice.shared.orientation = .portrait
        }
        super.tearDown()
    }

    /// The pause button opens the sheet, Resume closes it and the game runs on.
    @MainActor
    func testPauseOpensTheMenuAndResumes() throws {
        let app = XCUIApplication()
        let overlay = try launchTheSelftest(app)

        let pause = app.buttons["pause"]
        XCTAssertTrue(pause.waitForExistence(timeout: 10))
        pause.tap()
        let resume = app.buttons["resume"]
        XCTAssertTrue(resume.waitForExistence(timeout: 3), "The pause menu did not open within 3 s")
        XCTAssertTrue(app.descendants(matching: .any)["pause-menu"].firstMatch.exists)
        XCTAssertTrue(app.buttons["quit"].exists)
        XCTAssertTrue(app.switches["debug-overlay-toggle"].exists)

        resume.tap()
        XCTAssertTrue(waitUntilGone(resume), "The pause menu stayed open")
        XCTAssertTrue(pause.waitForExistence(timeout: 5))
        XCTAssertTrue(pause.isHittable)
        waitUntilRunning(overlay)
    }

    /// Quit closes the sheet, then the game, and the library returns.
    @MainActor
    func testQuitFromThePauseMenuReturnsToTheLibrary() throws {
        let app = XCUIApplication()
        try launchTheSelftest(app)

        app.buttons["pause"].tap()
        let quit = app.buttons["quit"]
        XCTAssertTrue(quit.waitForExistence(timeout: 3))
        quit.tap()
        XCTAssertTrue(app.navigationBars["Library"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.descendants(matching: .any)["game-screen"].exists)
    }

    /// The switch in the sheet hides the debug overlay and shows it again.
    @MainActor
    func testDebugOverlayToggle() throws {
        let app = XCUIApplication()
        let overlay = try launchTheSelftest(app)

        app.buttons["pause"].tap()
        let toggle = app.switches["debug-overlay-toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 3))
        XCTAssertEqual(toggle.value as? String, "1")
        flip(toggle)
        app.buttons["resume"].tap()
        XCTAssertTrue(waitUntilGone(overlay), "The debug overlay is still shown")

        app.buttons["pause"].tap()
        XCTAssertTrue(toggle.waitForExistence(timeout: 3))
        XCTAssertEqual(toggle.value as? String, "0")
        flip(toggle)
        app.buttons["resume"].tap()
        XCTAssertTrue(overlay.waitForExistence(timeout: 5), "The debug overlay did not come back")
    }

    /// Sideways, the pause button used to lie on R (M1). A press on R now
    /// reaches the game and opens no menu. The window is sideways once
    /// `Scripts/screenshot-tour.sh` turned the closed device with the private
    /// posture tool outside the repository (closed, sideways); turning
    /// the device from the test does not turn the window of the closed Duo
    /// (measured on 7 November 2026), so the test skips itself where the
    /// window stays upright.
    @MainActor
    func testSidewaysTheRButtonIsFree() throws {
        let app = XCUIApplication()
        let overlay = try launchTheSelftest(app)
        XCUIDevice.shared.orientation = .landscapeLeft

        let window = app.gameWindow
        let sideways = NSPredicate { element, _ in
            guard let frame = (element as? XCUIElement)?.frame else { return false }
            return frame.width > frame.height
        }
        let turned = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: sideways, object: window)],
                                      timeout: 10)
        try XCTSkipUnless(turned == .completed, "The window does not turn sideways on this device")
        let values = OverlayValues(overlayWithLayout(in: app))
        XCTAssertEqual(values.view.map { $0.width > $0.height }, true, "The layout is not sideways: \(values.pairs)")
        let before = try XCTUnwrap(Self.presses(in: overlay.label))

        let r = app.descendants(matching: .any)["touch-button-R"].firstMatch
        XCTAssertTrue(r.waitForExistence(timeout: 5))
        let pause = app.buttons["pause"].frame
        XCTAssertFalse(pause.intersects(r.frame), "The pause button \(pause) lies on R \(r.frame)")
        app.viewOrigin.withOffset(CGVector(dx: r.frame.midX, dy: r.frame.midY)).press(forDuration: 0.5)
        waitUntil(overlay, shows: "last R · presses \(before + 1)")
        XCTAssertFalse(app.buttons["resume"].exists, "The press opened the pause menu")
        keep(app.displayScreenshot(), named: "Sideways after R")
    }

    // MARK: The sheet on the game view of M2

    @MainActor
    func testAfterThePauseSheetTheTopEdgeTakesNothingAndTheDSControlsPress() throws {
        try checkTheTopEdgeAfterThePauseSheet(fileExtension: "nds", hasTouchScreen: true)
    }

    @MainActor
    func testAfterThePauseSheetTheTopEdgeTakesNothingAndTheGBAControlsPress() throws {
        try checkTheTopEdgeAfterThePauseSheet(fileExtension: "gba", hasTouchScreen: false)
    }

    /// The fault of M2 must not come back through the sheet: a presentation
    /// over the game (a full-screen cover over the library's navigation
    /// stack) took every touch in the top 60 to 70 pt after one touch at the
    /// top edge (ADR 0006, "Nachbesserungen nach der Prüfung"). After the
    /// pause button, the sheet and Resume, a tap at the very top edge presses
    /// nothing, and then L and R press and, on the DS, the touch screen hits
    /// its pixels, its top row too (ADR 0007, decision 5).
    @MainActor
    private func checkTheTopEdgeAfterThePauseSheet(fileExtension: String, hasTouchScreen: Bool) throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ArcfoldAutorun", try fixturePath("selftest", fileExtension)]
        app.launch()
        let overlay = overlayWithLayout(in: app)
        XCTAssertTrue(waitUntil(overlay, framesBeyond: 60), "The game does not run")

        let pause = app.buttons["pause"]
        XCTAssertTrue(pause.waitForExistence(timeout: 10))
        pause.tap()
        let resume = app.buttons["resume"]
        XCTAssertTrue(resume.waitForExistence(timeout: 5), "The pause sheet did not open")
        XCTAssertTrue(app.descendants(matching: .any)["pause-menu"].firstMatch.exists)
        // Let the zoom finish before Resume.
        sleep(1)
        resume.tap()
        XCTAssertTrue(waitUntilGone(resume), "The pause sheet stayed open")
        XCTAssertTrue(waitUntil(overlay, hasValue: "paused=false;"), "Resume did not resume")
        sleep(1)

        // Relative to the window: on the inner display the application keeps
        // the frame of the display's own orientation, and a tap relative to
        // it misses the window (UITestSupport).
        let origin = app.viewOrigin
        let before = OverlayValues(overlay)
        origin.withOffset(CGVector(dx: app.gameWindow.frame.width / 2, dy: 3)).tap()
        sleep(1)
        let afterEdge = OverlayValues(overlay)
        XCTAssertEqual(afterEdge.buttonPresses, before.buttonPresses, "The top edge pressed a button")
        XCTAssertEqual(afterEdge.pointerPresses, before.pointerPresses, "The top edge touched the touch screen")
        XCTAssertFalse(resume.exists, "The top edge opened the pause sheet")

        for name in ["L", "R"] {
            let button = app.descendants(matching: .any)["touch-button-\(name)"].firstMatch
            XCTAssertTrue(button.waitForExistence(timeout: 5), "No \(name)")
            let frame = button.frame
            let presses = OverlayValues(overlay).buttonPresses ?? 0
            origin.withOffset(CGVector(dx: frame.midX, dy: frame.midY)).tap()
            XCTAssertTrue(waitUntil(overlay, hasValue: "buttonPresses=\(presses + 1);lastButtons=\(name);", timeout: 5),
                          "\(name) at \(frame) did not press after the sheet: \(overlay.value as? String ?? "–")")
        }

        if hasTouchScreen {
            let values = OverlayValues(overlay)
            let screen = try XCTUnwrap(values.touchScreen, "No touch screen in \(values.pairs)")
            let k = screen.scale
            var presses = try XCTUnwrap(values.pointerPresses)
            for (px, py) in [(128, 0), (0, 0), (255, 0), (128, 96), (37, 150), (255, 191)] {
                let x = CGFloat(screen.x + px * k + k / 2) / CGFloat(values.scale)
                let y = CGFloat(screen.y + py * k + k / 2) / CGFloat(values.scale)
                origin.withOffset(CGVector(dx: x, dy: y)).tap()
                presses += 1
                XCTAssertTrue(waitUntil(overlay, hasValue: "pointer=\(px),\(py);pointerPresses=\(presses);", timeout: 5),
                              "The touch screen missed (\(px), \(py)) after the sheet: \(overlay.value as? String ?? "–")")
            }
        }
        keep(app.displayScreenshot(), named: "\(fileExtension): the controls after the pause sheet")
    }

    /// Closing the device pauses the game, and the pause menu is the sheet,
    /// also on the outer display; opening resumes by itself and closes the
    /// sheet (ADR 0006, section 10; ADR 0007). The hinge comes from
    /// `DebugRemote`, as in PoseUITests.
    @MainActor
    func testClosingShowsTheSheetAndOpeningClosesIt() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ArcfoldAutorun", try fixturePath("selftest", "nds")]
        app.launch()
        let overlay = overlayWithLayout(in: app)
        XCTAssertTrue(waitUntil(overlay, framesBeyond: 120), "The game does not run")
        postDebugNotification("hinge.open")
        sleep(1)

        postDebugNotification("hinge.closed")
        let sheet = app.descendants(matching: .any)["pause-menu"].firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5), "No pause sheet after closing")
        XCTAssertTrue(app.buttons["resume"].exists)
        XCTAssertTrue(app.buttons["quit"].exists)
        XCTAssertTrue(app.switches["debug-overlay-toggle"].exists)
        XCTAssertTrue(waitUntil(overlay, hasValue: "paused=true;"), "Closing did not pause")
        sleep(1)
        keep(app.displayScreenshot(), named: "Closed: the pause sheet")

        postDebugNotification("hinge.open")
        XCTAssertTrue(waitUntilGone(sheet), "Opening did not close the pause sheet")
        XCTAssertTrue(waitUntil(overlay, hasValue: "paused=false;"), "Opening did not resume")
        let frames = OverlayValues(overlay).frames ?? 0
        XCTAssertTrue(waitUntil(overlay, framesBeyond: frames + 100), "The game did not run after opening")
        XCTAssertFalse(app.buttons["resume"].exists, "The sheet came back")
    }

    /// Swiping the sheet away resumes, like Resume (ADR 0007, decision 5).
    @MainActor
    func testSwipingThePauseSheetAwayResumes() throws {
        let app = XCUIApplication()
        let overlay = try launchTheSelftest(app)
        app.buttons["pause"].tap()
        let sheet = app.descendants(matching: .any)["pause-menu"].firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
        XCTAssertTrue(waitUntil(overlay, hasValue: "paused=true;"))
        sleep(1)
        sheet.swipeDown(velocity: .fast)
        XCTAssertTrue(waitUntilGone(sheet), "The sheet stayed")
        XCTAssertTrue(waitUntil(overlay, hasValue: "paused=false;"), "Swiping the sheet away did not resume")
        sleep(1)
        XCTAssertFalse(sheet.exists, "The sheet came back")
    }

    /// The system's accessibility audit finds nothing in the library, the
    /// Licenses screen, the empty library, notices, the failure and the pause
    /// sheet. On the game screen only the controls (direct touch) and the
    /// debug overlay (fixed 10 pt) may report. The tour repeats it in dark
    /// mode and with Increase Contrast.
    @MainActor
    func testAccessibilityAudit() throws {
        try auditTheInterface()
    }
}
