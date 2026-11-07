import XCTest

/// Starts the app the way a person does: the library, the Licenses screen and
/// the debug launch arguments of ADR 0005, section 9.
final class LaunchTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// selftest.gba from this UI test bundle. The Simulator lets the app read it
    /// by path, which is what the debug launch arguments need.
    private func selftestPath() throws -> String {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "selftest", withExtension: "gba"),
                                "selftest.gba is not in the UI test bundle; check project.yml")
        return url.path(percentEncoded: false)
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

    @MainActor
    func testLicensesListsFiveComponentsWithTheirTexts() {
        let app = XCUIApplication()
        app.launch()

        let info = app.buttons["info-menu"]
        XCTAssertTrue(info.waitForExistence(timeout: 20))
        info.tap()
        let licenses = app.buttons["Licenses"]
        XCTAssertTrue(licenses.waitForExistence(timeout: 5))
        licenses.tap()

        XCTAssertTrue(app.navigationBars["Licenses"].waitForExistence(timeout: 5))
        let names = ["Arcfold", "mGBA 0.10.5", "blip_buf 1.1.0", "inih", "libretro.h"]
        for name in names {
            XCTAssertTrue(app.staticTexts[name].exists, "\(name) is missing on the Licenses screen")
        }
        XCTAssertEqual(app.cells.count, names.count)
        keepScreenshot(of: app, named: "Licenses")

        app.staticTexts["Arcfold"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "GNU GENERAL PUBLIC LICENSE"))
            .firstMatch.waitForExistence(timeout: 10))
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
    }

    @MainActor
    func testDebugImportPutsTheGameIntoTheLibrary() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ArcfoldImport", try selftestPath()]
        app.launch()

        XCTAssertTrue(app.navigationBars["Library"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["game-selftest"].waitForExistence(timeout: 10))
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

        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "Test pattern"
        attachment.lifetime = .keepAlways
        add(attachment)

        // Find the picture in the screenshot: the pattern has a white frame,
        // everything around it is black. Then check that it sits centred in
        // the screen view at a whole-number scale, and sample the middle of
        // each of the eight bars in the upper third.
        let image = try XCTUnwrap(screenshot.image.cgImage)
        let scale = CGFloat(image.width) / app.frame.width
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
        let controls = app.descendants(matching: .any)["touch-controls"].firstMatch
        XCTAssertTrue(controls.waitForExistence(timeout: 10))
        let label = overlay.label
        let match = try XCTUnwrap(label.firstMatch(of: /presses ([0-9]+)/), "No press count in: \(label)")
        let before = try XCTUnwrap(Int(match.1))

        // TouchLayout, upright: A at (0.84, 0.40), B at (0.67, 0.54) of the controls.
        let a = controls.coordinate(withNormalizedOffset: CGVector(dx: 0.84, dy: 0.40))
        let b = controls.coordinate(withNormalizedOffset: CGVector(dx: 0.67, dy: 0.54))
        a.press(forDuration: 1)
        waitUntil(overlay, shows: "Input held – · last A · presses \(before + 1)")

        a.press(forDuration: 1, thenDragTo: b, withVelocity: .slow, thenHoldForDuration: 1)
        waitUntil(overlay, shows: "Input held – · last B · presses \(before + 3)")
        keepScreenshot(of: app, named: "After holding A and sliding to B")
    }
}

/// A screenshot that could not be drawn into a bitmap.
private struct UnreadableScreenshot: Error {}

/// RGBA bytes of a screenshot.
private struct Pixels {
    let bytes: [UInt8]
    let width: Int
    let height: Int

    init(_ image: CGImage) throws {
        width = image.width
        height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        guard drawn else { throw UnreadableScreenshot() }
        self.bytes = bytes
    }

    /// The smallest rectangle around every pixel brighter than dark grey in `area`.
    func boundsOfLight(in area: (left: Int, top: Int, right: Int, bottom: Int))
        -> (left: Int, top: Int, right: Int, bottom: Int)?
    {
        var result: (left: Int, top: Int, right: Int, bottom: Int)?
        for y in max(area.top, 0)...min(area.bottom, height - 1) {
            for x in max(area.left, 0)...min(area.right, width - 1) {
                let pixel = rgb(x: x, y: y)
                guard pixel.red > 40 || pixel.green > 40 || pixel.blue > 40 else { continue }
                if let current = result {
                    result = (min(current.left, x), min(current.top, y), max(current.right, x), max(current.bottom, y))
                } else {
                    result = (x, y, x, y)
                }
            }
        }
        return result
    }

    func rgb(x: Int, y: Int) -> (red: UInt8, green: UInt8, blue: UInt8) {
        let x = min(max(x, 0), width - 1)
        let y = min(max(y, 0), height - 1)
        let offset = (y * width + x) * 4
        return (bytes[offset], bytes[offset + 1], bytes[offset + 2])
    }
}
