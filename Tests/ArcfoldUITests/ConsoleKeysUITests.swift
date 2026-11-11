import XCTest

/// Every key of the console presses where it is drawn (ADR 0007): a tap in
/// the middle of each key and on each arm of the direction pad reaches the
/// session as that button and as nothing else, and a tap on the menu button
/// opens the pause sheet. A UI test cannot look while it presses; it reads
/// the latest press and the number of presses from the debug overlay
/// afterwards. The test runs in the pose the device is in and then in the
/// poses `DebugRemote` sets while the game runs (flat, like a book,
/// tabletop), and taps relative to the window, so it holds on the inner
/// display too.
final class ConsoleKeysUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = true
    }

    /// The poses: the one the device is in, then the simulated ones, each
    /// with what the overlay shows once it applies (as in DSTouchUITests).
    private static let poses: [(name: String, notification: String, shows: String)] = [
        ("measured", "fold.measured", "posture="),
        ("flat", "fold.flat", ",inactive;"),
        ("book", "fold.book", ",active;"),
        ("tabletop", "fold.tabletop", "posture=tabletop"),
    ]

    @MainActor
    func testEveryKeyOfTheGBAPressesWhereItIsDrawn() throws {
        try checkEveryKey(fileExtension: "gba", names: ["A", "B", "L", "R", "Select", "Start"])
    }

    @MainActor
    func testEveryKeyOfTheDSPressesWhereItIsDrawn() throws {
        try checkEveryKey(fileExtension: "nds", names: ["A", "B", "X", "Y", "L", "R", "Select", "Start"])
    }

    /// The slim case of the DS (`-LargerScreens YES`): L and R draw 18 pt
    /// high at the ends of the hinge and take touches on 44 pt, so a tap
    /// above the hinge, over the corner of the upper screen, presses them
    /// too where the closed device shows the slim case. The case is slim
    /// only where that makes the screens one step larger, as on the closed
    /// Duo beside its vertical bar; an iPhone 402 pt wide shows them 4×
    /// with the hinge of 44 pt, and L and R stay keys of the full height
    /// there, which the test then checks instead.
    @MainActor
    func testEveryKeyOfTheSlimDSPressesWhereItIsDrawn() throws {
        try checkEveryKey(fileExtension: "nds", names: ["A", "B", "X", "Y", "L", "R", "Select", "Start"],
                          arguments: ["-LargerScreens", "YES"], poses: Array(Self.poses.prefix(1)), atTheSlimHinge: ["L", "R"])
    }

    /// The layout the overlay reports is the slim case: both screens one
    /// above the other with a hinge of 20 pt between them, too low for a key.
    private static func isSlimCase(_ values: OverlayValues) -> Bool {
        let screens = values.screens
        return screens.count == 2 && screens[0].x == screens[1].x && screens[1].y - screens[0].maxY == 20 * values.scale
    }

    /// `atTheSlimHinge` names the keys that are the ends of the hinge in
    /// the slim case, which the game was launched for.
    @MainActor
    private func checkEveryKey(fileExtension: String, names: [String], arguments: [String] = [],
                               poses: [(name: String, notification: String, shows: String)] = ConsoleKeysUITests.poses,
                               atTheSlimHinge: [String] = []) throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ArcfoldAutorun", try fixturePath("selftest", fileExtension)] + arguments
        app.launch()
        let overlay = overlayWithLayout(in: app)
        XCTAssertTrue(waitUntil(overlay, framesBeyond: 60), "The game does not run")
        // What the layout reports decides what L and R are at the ends of
        // the hinge. The closed Duo must show the slim case (ADR 0006).
        let layout = OverlayValues(overlay)
        let isSlim = !atTheSlimHinge.isEmpty && Self.isSlimCase(layout)
        if !atTheSlimHinge.isEmpty, layout.posture == "single", layout.view?.width == 1398, layout.view?.height == 2034 {
            XCTAssertTrue(isSlim, "The closed Duo does not show the slim case: \(layout.pairs)")
        }

        let origin = app.viewOrigin
        var presses = OverlayValues(overlay).buttonPresses ?? 0
        func press(_ name: String, at point: CGVector, _ what: String) {
            origin.withOffset(point).tap()
            presses += 1
            XCTAssertTrue(waitUntil(overlay, hasValue: "buttonPresses=\(presses);lastButtons=\(name);", timeout: 5),
                          "\(what) at \(point) did not press \(name): \(overlay.value as? String ?? "–")")
            presses = OverlayValues(overlay).buttonPresses ?? presses
        }

        for pose in poses {
            postDebugNotification(pose.notification)
            XCTAssertTrue(waitUntil(overlay, hasValue: pose.shows, timeout: 5), "\(pose.name): no \(pose.shows)")
            // The controls move animated.
            sleep(1)
            for name in names {
                let key = app.descendants(matching: .any)["touch-button-\(name)"].firstMatch
                XCTAssertTrue(key.waitForExistence(timeout: 5), "\(pose.name): no \(name)")
                let frame = key.frame
                press(name, at: CGVector(dx: frame.midX, dy: frame.midY), "\(pose.name): \(name) at \(frame)")
                if atTheSlimHinge.contains(name), pose.name == "measured" {
                    if isSlim {
                        // The target ends 1 pt below the key, the well, and
                        // reaches 44 pt up: 5 pt below its upper edge lies
                        // above the hinge.
                        let above = frame.maxY + 1 - 44 + 5
                        XCTAssertLessThan(above, frame.minY - 1, "\(name) at \(frame) is no key at a slim hinge")
                        press(name, at: CGVector(dx: frame.midX, dy: above), "\(pose.name): above the hinge, \(name)")
                    } else {
                        // No slim case here: a key of the full height.
                        XCTAssertGreaterThanOrEqual(frame.height, 40, "\(name) at \(frame) is no key of the full height")
                    }
                }
            }

            // The arms of the direction pad, a third of its size from its middle.
            let pad = app.descendants(matching: .any)["touch-pad"].firstMatch
            XCTAssertTrue(pad.waitForExistence(timeout: 5), "\(pose.name): no direction pad")
            let frame = pad.frame
            for (name, dx, dy) in [("Up", 0.0, -1.0), ("Down", 0.0, 1.0), ("Left", -1.0, 0.0), ("Right", 1.0, 0.0)] {
                press(name, at: CGVector(dx: frame.midX + dx * frame.width / 3, dy: frame.midY + dy * frame.height / 3),
                      "\(pose.name): the pad")
            }
            keep(app.displayScreenshot(), named: "\(fileExtension), \(pose.name): after every key")

            // The menu button, where it is drawn, opens the pause sheet;
            // Resume closes it, and the game goes on.
            let menu = app.buttons["pause"]
            XCTAssertTrue(menu.waitForExistence(timeout: 5), "\(pose.name): no menu button")
            origin.withOffset(CGVector(dx: menu.frame.midX, dy: menu.frame.midY)).tap()
            let sheet = app.descendants(matching: .any)["pause-menu"].firstMatch
            XCTAssertTrue(sheet.waitForExistence(timeout: 10), "\(pose.name): the menu button opened no sheet")
            let resume = app.buttons["resume"]
            XCTAssertTrue(resume.waitForExistence(timeout: 5), "\(pose.name): no Resume")
            resume.tap()
            let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: sheet)
            XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 10), .completed, "\(pose.name): Resume did not close the sheet")
            XCTAssertEqual(OverlayValues(overlay).buttonPresses, presses, "\(pose.name): the menu button pressed a key")
            sleep(1)
        }
        postDebugNotification("fold.measured")
    }
}
