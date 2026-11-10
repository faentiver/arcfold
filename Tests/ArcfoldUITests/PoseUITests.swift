import XCTest

/// Games from the library and pose changes while they run (ADR 0006,
/// sections 9, 10 and 15). A UI test cannot change the real pose of the
/// Simulator (Device Hub and the posture tool of `Scripts/pose-check.sh` act
/// from outside), so these tests change it through `DebugRemote` of the debug
/// build: Darwin notifications that replace the measured fold or hand a hinge
/// change to the game. They check what the app does with a new pose (layout,
/// emulation, sound, pause), not how the system moves the app between its
/// displays; that stays with the pose check (`Scripts/pose-check.sh`).
final class PoseUITests: XCTestCase {
    private struct Pose {
        let name: String
        let notification: String
        /// What the overlay's value shows in this pose.
        let shows: [String]
    }

    /// Every pose of the plan (section 7), ending where the Simulator is: closed.
    private static let poses = [
        Pose(name: "flat", notification: "fold.flat", shows: ["posture=flat", "override=true", ",inactive;"]),
        Pose(name: "book", notification: "fold.book", shows: ["posture=flat", "override=true", ",active;"]),
        Pose(name: "tabletop", notification: "fold.tabletop", shows: ["posture=tabletop", "override=true"]),
        Pose(name: "closed", notification: "fold.measured", shows: ["posture=single", "override=false"]),
    ]

    override func setUp() {
        continueAfterFailure = true
    }

    // MARK: Library

    /// Both test programs start from the library the way a person starts
    /// them: imported first, then tapped in the list. Each runs in the fold
    /// layout of its system: the DS with two screens and the touch screen, the
    /// GBA with one.
    @MainActor
    func testBothTestProgramsStartFromTheLibrary() throws {
        let app = XCUIApplication()
        for (system, fileExtension) in [("ds", "nds"), ("gba", "gba")] {
            app.launchArguments = ["-ArcfoldImport", try fixturePath("selftest", fileExtension)]
            app.launch()
            XCTAssertTrue(app.buttons["game-\(system)-selftest"].waitForExistence(timeout: 20),
                          "selftest.\(fileExtension) is not in the library")
        }
        app.terminate()
        app.launchArguments = []
        app.launch()
        for (system, screens, hasTouchScreen) in [("ds", 2, true), ("gba", 1, false)] {
            let entry = app.buttons["game-\(system)-selftest"]
            XCTAssertTrue(entry.waitForExistence(timeout: 20), "No \(system) entry in the library")
            entry.tap()
            let overlay = overlayWithLayout(in: app)
            let start = OverlayValues(overlay).frames ?? 0
            XCTAssertTrue(waitUntil(overlay, framesBeyond: start + 120), "\(system): the game does not run")
            let values = OverlayValues(overlay)
            XCTAssertEqual(values.screens.count, screens, "\(system): \(values.pairs)")
            XCTAssertEqual(values.touchScreen != nil, hasTouchScreen, "\(system): \(values.pairs)")
            keep(app.displayScreenshot(), named: "\(system) started from the library")

            let pause = app.buttons["pause"].firstMatch
            XCTAssertTrue(pause.waitForExistence(timeout: 5))
            pause.tap()
            let quit = app.buttons["quit"]
            XCTAssertTrue(quit.waitForExistence(timeout: 5))
            quit.tap()
            XCTAssertTrue(app.navigationBars["Library"].waitForExistence(timeout: 10), "\(system): not back in the library")
        }
    }

    // MARK: Poses

    @MainActor
    func testPoseChangesKeepTheDSRunning() throws {
        try checkPoseChanges(fileExtension: "nds", screens: 2, counters: [.dsARM7Frames, .dsARM9Frames])
    }

    @MainActor
    func testPoseChangesKeepTheGBARunning() throws {
        try checkPoseChanges(fileExtension: "gba", screens: 1, counters: [.gbaFrames])
    }

    /// Goes through every pose while the test program runs. In each change
    /// the overlay shows the new pose and layout, the emulation keeps running
    /// (frames go on, no pause, however short: the pause count and the
    /// sound's primings stay), nothing resynchronises and the sound has no
    /// underrun; the frame counter the program draws goes on too. Screenshots
    /// lie outside the measured windows, because a screenshot in the Simulator
    /// can delay the emulation thread.
    @MainActor
    private func checkPoseChanges(fileExtension: String, screens: Int, counters: [BlockRow]) throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ArcfoldAutorun", try fixturePath("selftest", fileExtension)]
        app.launch()
        let overlay = overlayWithLayout(in: app)
        XCTAssertTrue(waitUntil(overlay, hasValue: "primes=1;", timeout: 30), "The sound did not start")
        XCTAssertTrue(waitUntil(overlay, framesBeyond: 180), "The game does not run")

        var counter = try programCounter(app, overlay, counters, named: "\(fileExtension) before the first change")
        for pose in Self.poses {
            // Time for anything a screenshot delayed to show in the counters.
            sleep(2)
            let before = OverlayValues(overlay)
            postDebugNotification(pose.notification)
            for text in pose.shows {
                XCTAssertTrue(waitUntil(overlay, hasValue: text, timeout: 5),
                              "\(pose.name): no \"\(text)\" in \(overlay.value as? String ?? "–")")
            }
            sleep(2)
            let after = OverlayValues(overlay)
            XCTAssertEqual(after.screens.count, screens, "\(pose.name): \(after.pairs)")
            XCTAssertTrue(after.screens.allSatisfy { $0.scale >= 1 }, "\(pose.name): \(after.screens)")
            XCTAssertEqual(after.isPaused, false, "\(pose.name): the change paused the game")
            // A short pause would not show in isPaused two seconds later: it
            // counts, and resuming primes the sound again.
            XCTAssertEqual(after.pauses, before.pauses, "\(pose.name): the change paused the game for a moment")
            XCTAssertEqual(after.primes, before.primes, "\(pose.name): the sound primed again, so it was held")
            XCTAssertGreaterThanOrEqual((after.frames ?? 0) - (before.frames ?? 0), 100,
                                        "\(pose.name): the emulation stood still")
            XCTAssertEqual(after.resyncs, before.resyncs, "\(pose.name): the emulation resynchronised")
            XCTAssertEqual(after.underruns, before.underruns, "\(pose.name): the sound ran dry")
            XCTAssertEqual(after.dropped, before.dropped, "\(pose.name): the sound dropped frames")

            let next = try programCounter(app, overlay, counters, named: "\(fileExtension) \(pose.name)")
            if let previous = counter, let next {
                XCTAssertGreaterThanOrEqual(next.value - previous.value, 100,
                                            "\(pose.name): the program's \(next.row) went from \(previous.value) to \(next.value)")
            }
            counter = next
        }
    }

    /// The frame counter the test program draws, read from a screenshot
    /// without the overlay: the first of `rows` that no control covers. A
    /// screenshot with the overlay is kept. Fails when no row can be read.
    @MainActor
    private func programCounter(_ app: XCUIApplication, _ overlay: XCUIElement, _ rows: [BlockRow],
                                named name: String) throws -> (value: Int, row: BlockRow)? {
        let values = OverlayValues(overlay)
        let screen = try XCTUnwrap(values.screens.first, "No screen in \(values.pairs)")
        keep(app.displayScreenshot(), named: name)
        // The overlay lies over the upper screen; the counter is read without it.
        return try withOverlayHidden(in: app) {
            let covered = coveredRects(in: app, scale: values.scale, includingOverlay: false)
            let pixels = try Pixels(try XCTUnwrap(app.displayScreenshot().uprightImage))
            for row in rows {
                if let value = row.value(in: pixels, on: screen, covered: covered) {
                    return (value, row)
                }
            }
            XCTFail("\(name): no counter row of \(rows) is readable on \(screen)")
            return nil
        }
    }

    // MARK: Shoulder buttons

    @MainActor
    func testShoulderButtonsOfTheDSWorkInEveryPose() throws {
        try checkShoulderButtons(fileExtension: "nds", hasTouchScreen: true)
    }

    @MainActor
    func testShoulderButtonsOfTheGBAWorkInEveryPose() throws {
        try checkShoulderButtons(fileExtension: "gba", hasTouchScreen: false)
    }

    /// L and R press in every pose, also right after a touch at the very top
    /// edge, and they lie below the top edge guard of 64 pt (ADR 0006,
    /// section "Nachbesserungen nach der Prüfung"). The touch at the edge
    /// presses nothing. Under the full-screen cover of the library's
    /// navigation stack such a touch took every later touch in the top 60 to
    /// 70 pt away from the game; since the game replaces the library, it
    /// does not.
    @MainActor
    private func checkShoulderButtons(fileExtension: String, hasTouchScreen: Bool) throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ArcfoldAutorun", try fixturePath("selftest", fileExtension)]
        app.launch()
        let overlay = overlayWithLayout(in: app)
        XCTAssertTrue(waitUntil(overlay, framesBeyond: 60), "The game does not run")
        let origin = app.viewOrigin
        let closed = Pose(name: "closed at the start", notification: "fold.measured", shows: ["posture=single"])
        for pose in [closed] + Self.poses {
            postDebugNotification(pose.notification)
            for text in pose.shows {
                XCTAssertTrue(waitUntil(overlay, hasValue: text, timeout: 5), "\(pose.name): no \"\(text)\"")
            }
            // The controls move animated.
            sleep(1)
            let before = OverlayValues(overlay)
            origin.withOffset(CGVector(dx: app.gameWindow.frame.width / 2, dy: 3)).tap()
            sleep(1)
            let afterEdge = OverlayValues(overlay)
            XCTAssertEqual(afterEdge.buttonPresses, before.buttonPresses, "\(pose.name): the top edge pressed a button")
            if hasTouchScreen {
                XCTAssertEqual(afterEdge.pointerPresses, before.pointerPresses, "\(pose.name): the top edge touched the touch screen")
            }
            for name in ["L", "R"] {
                let button = app.descendants(matching: .any)["touch-button-\(name)"].firstMatch
                XCTAssertTrue(button.waitForExistence(timeout: 5), "\(pose.name): no \(name)")
                let frame = button.frame
                XCTAssertGreaterThanOrEqual(frame.minY, 64, "\(pose.name): \(name) at \(frame) lies in the top edge guard")
                let presses = OverlayValues(overlay).buttonPresses ?? 0
                origin.withOffset(CGVector(dx: frame.midX, dy: frame.midY)).tap()
                XCTAssertTrue(waitUntil(overlay, hasValue: "buttonPresses=\(presses + 1);lastButtons=\(name);", timeout: 5),
                              "\(pose.name): \(name) at \(frame) did not press: \(overlay.value as? String ?? "–")")
            }
            keep(app.displayScreenshot(), named: "\(fileExtension) L and R, \(pose.name)")
        }
    }

    // MARK: Hinge

    /// Closing pauses the game with its menu on the outer display, "Resume"
    /// plays on there, and opening after a close without "Resume" resumes by
    /// itself (ADR 0006, section 10; plan, section 7). The emulation stands
    /// still while paused, and pausing silences the sound before it stops, so
    /// no underrun counts.
    @MainActor
    func testClosingPausesAndResumePlaysOnTheOuterDisplay() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ArcfoldAutorun", try fixturePath("selftest", "nds")]
        app.launch()
        let overlay = overlayWithLayout(in: app)
        XCTAssertTrue(waitUntil(overlay, hasValue: "primes=1;", timeout: 30), "The sound did not start")
        XCTAssertTrue(waitUntil(overlay, framesBeyond: 180), "The game does not run")
        let resume = app.buttons["resume"]

        // Opening a device that is already running pauses nothing.
        postDebugNotification("hinge.open")
        sleep(1)
        XCTAssertEqual(OverlayValues(overlay).isPaused, false)
        let underruns = OverlayValues(overlay).underruns
        let pauses = try XCTUnwrap(OverlayValues(overlay).pauses)

        // Closing: paused with the menu, the emulation stands still.
        postDebugNotification("hinge.closed")
        XCTAssertTrue(waitUntil(overlay, hasValue: "paused=true;"), "Closing did not pause")
        XCTAssertTrue(resume.waitForExistence(timeout: 5), "No pause menu after closing")
        sleep(2)
        let stopped = OverlayValues(overlay).frames
        sleep(2)
        XCTAssertEqual(OverlayValues(overlay).frames, stopped, "The emulation ran on while closed")
        XCTAssertEqual(OverlayValues(overlay).pauses, pauses + 1, "Closing is one pause")
        keep(app.displayScreenshot(), named: "Closed: paused with the menu")

        // "Resume" on the outer display plays on.
        resume.tap()
        XCTAssertTrue(waitUntil(overlay, hasValue: "paused=false;"), "Resume did not resume")
        XCTAssertTrue(waitUntil(overlay, framesBeyond: (stopped ?? 0) + 100), "The game did not play on")
        XCTAssertFalse(resume.exists, "The menu stayed")
        keep(app.displayScreenshot(), named: "Resumed on the outer display")

        // Opening again changes nothing; closing pauses, opening resumes by itself.
        postDebugNotification("hinge.open")
        sleep(1)
        XCTAssertEqual(OverlayValues(overlay).isPaused, false)
        postDebugNotification("hinge.closed")
        XCTAssertTrue(waitUntil(overlay, hasValue: "paused=true;"), "Closing again did not pause")
        XCTAssertTrue(resume.waitForExistence(timeout: 5))
        sleep(1)
        let closedAgain = OverlayValues(overlay).frames ?? 0
        postDebugNotification("hinge.open")
        XCTAssertTrue(waitUntil(overlay, hasValue: "paused=false;"), "Opening did not resume")
        XCTAssertTrue(waitUntil(overlay, framesBeyond: closedAgain + 100), "The game did not run after opening")
        XCTAssertFalse(resume.exists, "The menu stayed after opening")
        XCTAssertEqual(OverlayValues(overlay).underruns, underruns, "Pausing made the sound run dry")
        XCTAssertEqual(OverlayValues(overlay).pauses, pauses + 2, "Two closings, two pauses, nothing else")
    }
}

extension XCTestCase {
    /// Waits until the overlay counts more than `frames` emulated frames.
    @MainActor
    func waitUntil(_ overlay: XCUIElement, framesBeyond frames: Int, timeout: TimeInterval = 30) -> Bool {
        let beyond = NSPredicate { element, _ in
            guard let element = element as? XCUIElement else { return false }
            return (OverlayValues(element).frames ?? 0) > frames
        }
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: beyond, object: overlay)], timeout: timeout) == .completed
    }
}
