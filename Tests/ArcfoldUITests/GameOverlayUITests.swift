import XCTest

/// What lies over a running game, in the pose the device is in when the
/// tests run (ADR 0007): the status chip above a notice, the debug overlay
/// clear of them and of every control, the pause sheet with equal margins
/// and as high as its content, the pause button in the row of the controls,
/// and the failure message on one screen.
/// A UI test cannot change the real pose, so the tests are run once per
/// pose, with the device brought into it beforehand. Everything here is
/// measured against the elements of the app, so each test holds in every
/// pose and needs no fixed geometry.
final class GameOverlayUITests: XCTestCase {
    private static let notice = "The save could not be written"
    private static let chip = "The audio engine could not start"
    private static let largestText = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]

    override func setUp() {
        continueAfterFailure = true
    }

    // MARK: Helpers

    /// Starts the test program of `system` and waits for the game.
    @MainActor
    private func overlayLaunch(_ system: String, arguments: [String] = []) throws -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ArcfoldAutorun", try fixturePath("selftest", system == "ds" ? "nds" : "gba")] + arguments
        app.launch()
        return app
    }

    @MainActor
    private func overlayWaitForTheGame(_ app: XCUIApplication) {
        XCTAssertTrue(app.descendants(matching: .any)["debug-overlay"].firstMatch.waitForExistence(timeout: 40),
                      "The game did not start")
    }

    /// The frames of everything that takes touches for the game: the
    /// buttons, the pad and the pause button.
    @MainActor
    private func overlayControlFrames(_ app: XCUIApplication) -> [(name: String, frame: CGRect)] {
        let controls = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@ OR identifier == %@ OR identifier == %@",
                        "touch-button-", "touch-pad", "pause"))
        return (0..<controls.count).map { index in
            let element = controls.element(boundBy: index)
            return (element.identifier, element.frame)
        }.filter { !$0.frame.isEmpty }
    }

    /// Keeps a screenshot of the display the app runs on.
    @MainActor
    private func overlayKeep(_ app: XCUIApplication, named name: String) {
        keep(app.displayScreenshot(), named: name)
    }

    @MainActor
    private func overlayText(_ app: XCUIApplication, beginning: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", beginning)).firstMatch
    }

    // MARK: Notices

    /// The chip and a long notice never overlap and cover no control, at the
    /// default text size and at the largest, for the GBA and the DS. The
    /// frames are those of their glass, 6 pt apart. The card of the debug
    /// overlay gives way to both: it ends above or beside them, with fewer
    /// lines where the room is short, and its element stays.
    @MainActor
    func testTheChipAndALongNoticeNeverOverlap() throws {
        for system in ["gba", "ds"] {
            for (size, arguments) in [("default", []), ("largest", Self.largestText)] {
                let app = try overlayLaunch(system, arguments: arguments)
                overlayWaitForTheGame(app)
                let card = app.descendants(matching: .any)["debug-overlay"].firstMatch
                postDebugNotification("chip.show")
                let chip = overlayText(app, beginning: Self.chip)
                XCTAssertTrue(chip.waitForExistence(timeout: 5), "\(system) \(size): no chip")
                postDebugNotification("notice.long")
                let notice = overlayText(app, beginning: Self.notice)
                XCTAssertTrue(notice.waitForExistence(timeout: 5), "\(system) \(size): no notice")
                // The chip moved up for the notice; read both once they rest.
                Thread.sleep(forTimeInterval: 0.6)
                let chipFrame = chip.frame
                let noticeFrame = notice.frame
                let cardExists = card.exists
                let cardFrame = cardExists ? card.frame : .zero
                overlayKeep(app, named: "notice-\(system)-\(size)")
                XCTAssertFalse(chipFrame.isEmpty || noticeFrame.isEmpty, "\(system) \(size): the notice went away too early")
                XCTAssertFalse(chipFrame.insetBy(dx: -2, dy: -2).intersects(noticeFrame.insetBy(dx: -2, dy: -2)),
                               "\(system) \(size): the chip \(chipFrame) and the notice \(noticeFrame) overlap")
                XCTAssertTrue(cardExists, "\(system) \(size): the debug overlay went away")
                for (name, frame) in [("chip", chipFrame), ("notice", noticeFrame)] {
                    XCTAssertFalse(cardFrame.insetBy(dx: -2, dy: -2).intersects(frame),
                                   "\(system) \(size): the debug overlay \(cardFrame) lies under the \(name) \(frame)")
                }
                for (name, frame) in overlayControlFrames(app) {
                    XCTAssertFalse(frame.intersects(chipFrame),
                                   "\(system) \(size): the chip \(chipFrame) covers \(name) \(frame)")
                    XCTAssertFalse(frame.intersects(noticeFrame),
                                   "\(system) \(size): the notice \(noticeFrame) covers \(name) \(frame)")
                }
                app.terminate()
            }
        }
    }

    // MARK: Debug overlay

    /// The card of the debug overlay covers no button, no pad and no pause
    /// button, for the GBA and the DS.
    @MainActor
    func testTheDebugOverlayCoversNoControl() throws {
        for system in ["gba", "ds"] {
            let app = try overlayLaunch(system)
            overlayWaitForTheGame(app)
            let overlay = app.descendants(matching: .any)["debug-overlay"].firstMatch
            let controls = overlayControlFrames(app)
            XCTAssertGreaterThanOrEqual(controls.count, 8, "\(system): the controls are missing")
            let card = overlay.frame
            overlayKeep(app, named: "debug-\(system)")
            XCTAssertFalse(card.isEmpty)
            for (name, frame) in controls {
                XCTAssertFalse(frame.intersects(card), "\(system): the debug overlay \(card) covers \(name) \(frame)")
            }
            app.terminate()
        }
    }

    // MARK: Pause

    /// The pause button takes touches on 44 × 44 pt beside Select and Start,
    /// overlaps neither, and opens the sheet, whose content has equal
    /// margins at both sides at the default text size, also sideways beside
    /// the system column.
    @MainActor
    func testThePauseButtonOpensASheetWithEqualMargins() throws {
        for system in ["gba", "ds"] {
            let app = try overlayLaunch(system)
            overlayWaitForTheGame(app)
            let pause = app.buttons["pause"]
            XCTAssertTrue(pause.waitForExistence(timeout: 10))
            let target = pause.frame
            XCTAssertGreaterThanOrEqual(target.width, 44)
            XCTAssertGreaterThanOrEqual(target.height, 44)
            for name in ["touch-button-Select", "touch-button-Start"] {
                let neighbour = app.descendants(matching: .any)[name].firstMatch.frame
                XCTAssertFalse(neighbour.isEmpty, "\(system): \(name) is missing")
                // The circle is drawn 36 pt wide inside its target.
                XCTAssertFalse(neighbour.intersects(target.insetBy(dx: 4, dy: 4)),
                               "\(system): the pause button \(target) lies on \(name) \(neighbour)")
            }
            overlayKeep(app, named: "pause-button-\(system)")

            pause.tap()
            let sheet = app.descendants(matching: .any)["pause-menu"].firstMatch
            XCTAssertTrue(sheet.waitForExistence(timeout: 10), "\(system): the pause button opened no sheet")
            let resume = app.buttons["resume"]
            XCTAssertTrue(resume.waitForExistence(timeout: 5))
            Thread.sleep(forTimeInterval: 1)
            let sheetFrame = sheet.frame
            let resumeFrame = resume.frame
            overlayKeep(app, named: "pause-sheet-\(system)")
            // Along the axis the button is long in, whichever way round the
            // display reports its frames.
            let margins = resumeFrame.width >= resumeFrame.height
                ? (resumeFrame.minX - sheetFrame.minX, sheetFrame.maxX - resumeFrame.maxX)
                : (resumeFrame.minY - sheetFrame.minY, sheetFrame.maxY - resumeFrame.maxY)
            XCTAssertEqual(margins.0, margins.1, accuracy: 1,
                           "\(system): Resume \(resumeFrame) is not centred in the sheet \(sheetFrame)")
            resume.tap()
            let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: sheet)
            XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 10), .completed, "\(system): Resume did not close the sheet")
            app.terminate()
        }
    }

    /// The most that may lie between Quit Game and the lower edge of the
    /// sheet: the safe area at the bottom of the sheet, 34 pt on the Duo.
    private static let sheetBottomMargin: CGFloat = 40

    /// The lower edge of a fold that lies bent across the window, in points,
    /// from the values of the debug overlay; nil in every other pose.
    @MainActor
    private func overlayBentFoldAcross(_ app: XCUIApplication) -> CGFloat? {
        let values = OverlayValues(app.descendants(matching: .any)["debug-overlay"].firstMatch)
        let parts = (values["fold"] ?? "").split(separator: ",")
        let numbers = parts.compactMap { Double($0) }
        guard parts.last == "active", numbers.count == 4, numbers[2] > numbers[3] else { return nil }
        return CGFloat(numbers[1] + numbers[3]) / CGFloat(values.scale)
    }

    /// The pause sheet is as high as its content: below Quit Game lies the
    /// margin of the safe area, not empty glass. Where the content is higher
    /// than the sheet may become, as with the largest text in a low window
    /// or below the fold of the tabletop pose, Quit Game ends in that margin
    /// or below it: the sheet is as high as it may be and scrolls. It never
    /// leaves the window, and below a fold that is bent across the window
    /// it begins no higher than the system's medium height did, 8 pt above
    /// the lower edge of the fold.
    @MainActor
    func testThePauseSheetIsAsHighAsItsContent() throws {
        for system in ["gba", "ds"] {
            for (size, arguments) in [("default", []), ("largest", Self.largestText)] {
                let app = try overlayLaunch(system, arguments: arguments)
                overlayWaitForTheGame(app)
                let fold = overlayBentFoldAcross(app)
                let pause = app.buttons["pause"]
                XCTAssertTrue(pause.waitForExistence(timeout: 10))
                pause.tap()
                let sheet = app.descendants(matching: .any)["pause-menu"].firstMatch
                XCTAssertTrue(sheet.waitForExistence(timeout: 10), "\(system) \(size): the pause button opened no sheet")
                let quit = app.buttons["quit"]
                XCTAssertTrue(quit.waitForExistence(timeout: 5))
                Thread.sleep(forTimeInterval: 1.5)
                let window = app.gameWindow.frame
                let sheetFrame = sheet.frame
                let quitFrame = quit.frame
                overlayKeep(app, named: "pause-sheet-height-\(system)-\(size)")
                let name = "\(system) \(size): the sheet \(sheetFrame) with Quit Game \(quitFrame) in the window \(window)"
                XCTAssertTrue(window.insetBy(dx: -1, dy: -1).contains(sheetFrame), "\(name) leaves the window")
                let below = sheetFrame.maxY - quitFrame.maxY
                XCTAssertLessThanOrEqual(below, Self.sheetBottomMargin, "\(name) is higher than its content")
                if below < 19 {
                    // The content scrolls: the sheet has grown as far as it may.
                    XCTAssertLessThanOrEqual(sheetFrame.minY, (fold ?? window.minY) + 12,
                                             "\(name) scrolls though it could be higher")
                }
                if let fold {
                    XCTAssertGreaterThanOrEqual(sheetFrame.minY, fold - 9, "\(name) lies on the fold that ends at \(fold)")
                }
                app.terminate()
            }
        }
    }

    // MARK: Failure

    /// The message of a game that could not start and its button stand on
    /// one screen. On the inner display of the Duo the fold crosses the
    /// middle of the long side, 121 px wide in the Simulator: nothing of the
    /// message reaches it, and everything lies on the same side. Close
    /// brings the library back.
    @MainActor
    func testTheFailureMessageStaysOnOneScreen() throws {
        for system in ["gba", "ds"] {
            let app = try overlayLaunch(system, arguments: ["-ArcfoldFailStart", "YES"])
            let close = app.buttons["Close"]
            XCTAssertTrue(close.waitForExistence(timeout: 30), "\(system): no failure message")
            let title = overlayText(app, beginning: "The Game Could Not Start")
            let message = overlayText(app, beginning: "The game could not start:")
            XCTAssertTrue(title.exists && message.exists)
            overlayKeep(app, named: "failure-\(system)")

            let window = app.gameWindow.frame
            let frames = [("Close", close.frame), ("title", title.frame), ("message", message.frame)]
            for (name, frame) in frames {
                XCTAssertTrue(window.insetBy(dx: -1, dy: -1).contains(frame), "\(system): \(name) \(frame) leaves the window \(window)")
            }
            let long = max(window.width, window.height)
            let isInnerDisplay = abs(long - 951) < 2 && abs(min(window.width, window.height) - 669) < 2
            if isInnerDisplay {
                // The division region as measured: 1366 to 1487 px of 2853.
                let fold = (1366.0 / 3)...(1487.0 / 3)
                let sides = frames.map { name, frame -> Int in
                    let extent = window.width > window.height ? (frame.minX, frame.maxX) : (frame.minY, frame.maxY)
                    XCTAssertTrue(extent.1 <= fold.lowerBound + 0.5 || extent.0 >= fold.upperBound - 0.5,
                                  "\(system): \(name) \(frame) lies on the fold")
                    return extent.1 <= fold.lowerBound + 0.5 ? 0 : 1
                }
                XCTAssertEqual(Set(sides).count, 1, "\(system): the message is split between the screens")
            }

            close.tap()
            XCTAssertTrue(app.descendants(matching: .any)["info-menu"].firstMatch.waitForExistence(timeout: 15),
                          "\(system): Close did not bring the library back")
            app.terminate()
        }
    }
}
