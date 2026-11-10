import XCTest

/// Starts the app the way a person does: the library, the Licenses screen and
/// the debug launch arguments of ADR 0005, section 9.
final class LaunchTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// selftest.gba from this UI test bundle.
    private func selftestPath() throws -> String {
        try fixturePath("selftest", "gba")
    }

    /// Keeps a screenshot in the result bundle as evidence of the run.
    @MainActor
    private func keepScreenshot(of app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// iOS 27 puts the back button into a toolbar of its own, not into the
    /// navigation bar.
    @MainActor
    private func goBack(in app: XCUIApplication) {
        let back = app.buttons["BackButton"]
        if back.waitForExistence(timeout: 5) {
            back.tap()
        } else {
            app.navigationBars.buttons.firstMatch.tap()
        }
    }

    @MainActor
    func testAppLaunchesIntoTheLibrary() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.navigationBars["Library"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["import"].exists)
        XCTAssertTrue(app.buttons["info-menu"].exists)
    }

    /// Swipes the list up until `element` exists; long lists lay out lazily.
    @MainActor
    private func scroll(to element: XCUIElement, in app: XCUIApplication, attempts: Int = 12) -> Bool {
        for _ in 0..<attempts where !element.exists {
            app.swipeUp()
        }
        return element.waitForExistence(timeout: 2)
    }

    @MainActor
    func testLicensesListsTheComponentsWithTheirTexts() {
        let app = XCUIApplication()
        app.launch()

        let info = app.buttons["info-menu"]
        XCTAssertTrue(info.waitForExistence(timeout: 20))
        info.tap()
        let licenses = app.buttons["Licenses"]
        XCTAssertTrue(licenses.waitForExistence(timeout: 5))
        licenses.tap()

        XCTAssertTrue(app.navigationBars["Licenses"].waitForExistence(timeout: 5))
        // The list starts with Arcfold and mGBA with its parts (ADR 0005).
        for name in ["Arcfold", "mGBA 0.10.5", "blip_buf 1.1.0", "inih", "libretro.h"] {
            XCTAssertTrue(app.staticTexts[name].exists, "\(name) is missing on the Licenses screen")
        }
        keepScreenshot(of: app, named: "Licenses")

        app.staticTexts["Arcfold"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "GNU GENERAL PUBLIC LICENSE"))
            .firstMatch.waitForExistence(timeout: 10))
        // The copyright notice and where the source code is (GPL-3.0, sections 5 and 6).
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "https://github.com/faentiver/arcfold"))
            .firstMatch.exists)
        keepScreenshot(of: app, named: "Arcfold")
        goBack(in: app)

        XCTAssertTrue(app.staticTexts["mGBA 0.10.5"].waitForExistence(timeout: 5))
        app.staticTexts["mGBA 0.10.5"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "github.com/mgba-emu/mgba"))
            .firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Mozilla Public License"))
            .firstMatch.exists)
        goBack(in: app)

        XCTAssertTrue(app.staticTexts["libretro.h"].waitForExistence(timeout: 5))
        app.staticTexts["libretro.h"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Permission is hereby granted"))
            .firstMatch.waitForExistence(timeout: 10))
        keepScreenshot(of: app, named: "libretro.h")
        goBack(in: app)

        // melonDS DS with its source, and the last entry, the fonts it embeds (ADR 0006).
        let melonDSDS = app.staticTexts["melonDS DS 1.4.0"]
        XCTAssertTrue(scroll(to: melonDSDS, in: app), "melonDS DS is missing on the Licenses screen")
        melonDSDS.tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "github.com/JesseTG/melonds-ds"))
            .firstMatch.waitForExistence(timeout: 10))
        goBack(in: app)

        let fonts = app.staticTexts["Open Sans"]
        XCTAssertTrue(scroll(to: fonts, in: app), "Open Sans is missing on the Licenses screen")
        keepScreenshot(of: app, named: "Licenses, end of the list")
        fonts.tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "SIL OPEN FONT LICENSE"))
            .firstMatch.waitForExistence(timeout: 10))
    }

    /// The Licenses screen lists every component of the app and of both
    /// cores with its license, in the order of `LicenseCatalog`: Arcfold,
    /// mGBA with what it builds in, libretro.h, and melonDS DS with every part
    /// it builds in (ADR 0005, section 9; ADR 0006, section 3), 24 entries.
    @MainActor
    func testLicensesListEveryComponentOfBothCores() {
        let app = XCUIApplication()
        app.launch()
        let info = app.buttons["info-menu"]
        XCTAssertTrue(info.waitForExistence(timeout: 20))
        info.tap()
        let licenses = app.buttons["Licenses"]
        XCTAssertTrue(licenses.waitForExistence(timeout: 5))
        licenses.tap()
        XCTAssertTrue(app.navigationBars["Licenses"].waitForExistence(timeout: 5))

        let entries: [(name: String, license: String)] = [
            ("Arcfold", "GPL-3.0-or-later"), ("mGBA 0.10.5", "MPL-2.0"), ("blip_buf 1.1.0", "LGPL-2.1-or-later"),
            ("inih", "BSD-3-Clause"), ("libretro.h", "MIT"), ("melonDS DS 1.4.0", "GPL-3.0-or-later"),
            ("melonDS", "GPL-3.0-or-later"), ("FreeBIOS", "BSD-2-Clause"), ("FatFs", "BSD-1-Clause"), ("teakra", "MIT"),
            ("Tiny AES in C", "Unlicense"), ("xxHash", "BSD-2-Clause"), ("libretro-common", "MIT"),
            ("libslirp", "BSD-3-Clause"), ("libslirp, parts from 4.4BSD", "BSD-3-Clause"),
            ("libslirp, MIT parts", "MIT"), ("{fmt}", "MIT"),
            ("OpenGL Mathematics (GLM)", "MIT"), ("pntr", "Zlib"), ("yamc", "MIT"), ("span lite", "BSL-1.0"),
            ("date", "MIT"), ("zlib", "Zlib"), ("Open Sans", "OFL-1.1"),
        ]
        XCTAssertEqual(entries.count, 24)
        for (index, entry) in entries.enumerated() {
            let row = app.staticTexts[entry.name]
            XCTAssertTrue(scroll(to: row, in: app), "\(entry.name) is missing on the Licenses screen")
            let license = app.staticTexts.matching(NSPredicate(format: "label == %@", entry.license))
            XCTAssertGreaterThan(license.count, 0, "No \(entry.license) next to \(entry.name)")
            if index == 0 || index == 11 || index == entries.count - 1 {
                keepScreenshot(of: app, named: "Licenses at \(entry.name)")
            }
        }
    }

    @MainActor
    func testDebugImportPutsTheGameIntoTheLibrary() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ArcfoldImport", try selftestPath()]
        app.launch()

        XCTAssertTrue(app.navigationBars["Library"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["game-gba-selftest"].waitForExistence(timeout: 10))
        keepScreenshot(of: app, named: "Library after the debug import")
    }

    /// The picture path without a core: the test pattern of PreviewContent goes
    /// through the mailbox, the display link and the shader onto the screen.
    @MainActor
    func testTheGameScreenShowsTheTestPattern() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ArcfoldTestPattern", "YES"]
        app.launch()

        let screen = app.descendants(matching: .any)["test-pattern-screen"]
        XCTAssertTrue(screen.waitForExistence(timeout: 20))
        let stats = app.descendants(matching: .any)["test-pattern-stats"]
        let shown = NSPredicate(format: "label CONTAINS %@", "shown 1")
        expectation(for: shown, evaluatedWith: stats)
        waitForExpectations(timeout: 10)

        let screenshot = app.displayScreenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "Test pattern"
        attachment.lifetime = .keepAlways
        add(attachment)

        // Find the picture in the screenshot: the pattern has a white frame,
        // everything around it is black. Then check that it sits centred in
        // the screen view at a whole-number scale, and sample the middle of
        // each of the eight bars in the upper third.
        let image = try XCTUnwrap(screenshot.uprightImage)
        let scale = screenshot.image.scale
        let pixels = try Pixels(image)
        let frame = screen.frame
        let area = (left: Int(frame.minX * scale), top: Int(frame.minY * scale),
                    right: Int(frame.maxX * scale) - 1, bottom: Int(frame.maxY * scale) - 1)
        let picture = try XCTUnwrap(pixels.boundsOfLight(in: area), "No picture in the screen view")
        let width = picture.right - picture.left + 1
        let height = picture.bottom - picture.top + 1
        XCTAssertEqual(width % 240, 0, "Picture width \(width) is no whole multiple of 240")
        XCTAssertEqual(width / 240 * 160, height, "Picture \(width) x \(height) does not keep 3:2")
        XCTAssertLessThanOrEqual(abs((picture.left - area.left) - (area.right - picture.right)), 2, "Not centred horizontally")
        XCTAssertLessThanOrEqual(abs((picture.top - area.top) - (area.bottom - picture.bottom)), 2, "Not centred vertically")

        let expected: [(red: Bool, green: Bool, blue: Bool)] = [
            (true, true, true), (true, true, false), (false, true, true), (false, true, false),
            (true, false, true), (true, false, false), (false, false, true), (false, false, false),
        ]
        for (index, color) in expected.enumerated() {
            let x = picture.left + width * (2 * index + 1) / 16
            let y = picture.top + height / 3
            let sample = pixels.rgb(x: x, y: y)
            XCTAssertEqual(sample.red > 200, color.red, "Bar \(index) red: \(sample)")
            XCTAssertEqual(sample.green > 200, color.green, "Bar \(index) green: \(sample)")
            XCTAssertEqual(sample.blue > 200, color.blue, "Bar \(index) blue: \(sample)")
            XCTAssertTrue([sample.red, sample.green, sample.blue].allSatisfy { $0 > 200 || $0 < 55 },
                          "Bar \(index) is not a clean colour: \(sample)")
        }
    }

    /// Starts selftest.gba through the debug launch and waits until the debug
    /// overlay shows a frame rate above 0. Returns the overlay.
    @MainActor
    private func launchTheSelftest(_ app: XCUIApplication) throws -> XCUIElement {
        app.launchArguments = ["-ArcfoldAutorun", try selftestPath()]
        app.launch()

        let overlay = app.descendants(matching: .any)["debug-overlay"].firstMatch
        XCTAssertTrue(overlay.waitForExistence(timeout: 30))
        let running = NSPredicate { element, _ in
            guard let label = (element as? XCUIElement)?.label,
                  let range = label.range(of: #"Emulation ([0-9.]+) fps"#, options: .regularExpression)
            else { return false }
            let number = label[range].split(separator: " ")[1]
            return (Double(number) ?? 0) > 0
        }
        expectation(for: running, evaluatedWith: overlay)
        waitForExpectations(timeout: 30)
        return overlay
    }

    /// Waits until the label of `element` contains `text`.
    @MainActor
    private func waitUntil(_ element: XCUIElement, shows text: String, timeout: TimeInterval = 10) {
        let shows = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", text), object: element)
        let result = XCTWaiter().wait(for: [shows], timeout: timeout)
        XCTAssertEqual(result, .completed, "Expected \"\(text)\" in: \(element.label)")
    }

    /// selftest.gba through the debug launch, the same import as the file
    /// importer: mGBA runs, and the debug overlay shows a frame rate.
    @MainActor
    func testTheGameRunsAndTheOverlayShowsAFrameRate() throws {
        let app = XCUIApplication()
        _ = try launchTheSelftest(app)
        XCTAssertTrue(app.descendants(matching: .any)["game-screen"].exists)
        keepScreenshot(of: app, named: "Game running")
    }

    /// The touch controls reach the session: holding A, then sliding from A
    /// to B (ADR 0005, section 7). A UI test cannot look while it presses, so
    /// it reads the input line of the debug overlay afterwards: the latest
    /// press and the number of presses stay there. That the session's buttons
    /// reach mGBA, `CoreSessionTests` checks with the key row of selftest.gba.
    /// One finger only; several fingers need the device.
    @MainActor
    func testTouchButtonsReachTheSession() throws {
        let app = XCUIApplication()
        let overlay = try launchTheSelftest(app)
        let buttonA = app.descendants(matching: .any)["touch-button-A"].firstMatch
        let buttonB = app.descendants(matching: .any)["touch-button-B"].firstMatch
        XCTAssertTrue(buttonA.waitForExistence(timeout: 10))
        XCTAssertTrue(buttonB.exists)
        let label = overlay.label
        let match = try XCTUnwrap(label.firstMatch(of: /presses ([0-9]+)/), "No press count in: \(label)")
        let before = try XCTUnwrap(Int(match.1))

        // The buttons draw without taking touches; the surface below them does.
        let a = buttonA.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let b = buttonB.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        a.press(forDuration: 1)
        waitUntil(overlay, shows: "Input held – · last A · presses \(before + 1)")

        a.press(forDuration: 1, thenDragTo: b, withVelocity: .slow, thenHoldForDuration: 1)
        waitUntil(overlay, shows: "Input held – · last B · presses \(before + 3)")
        keepScreenshot(of: app, named: "After holding A and sliding to B")
    }
}
