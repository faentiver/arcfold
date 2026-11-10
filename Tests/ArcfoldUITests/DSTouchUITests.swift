import XCTest

/// Touch on the DS touch screen from end to end (ADR 0006, sections 6 and 14):
/// a tap on a view pixel goes through `TouchMapping`, `PointerPosition`,
/// `InputState` and melonDS DS into selftest.nds, which draws a crosshair whose
/// crossing pixel is red exactly at the pixel it was touched. The overlay shows
/// the pointer the session's `InputState` saw, the screenshot the crosshair.
final class DSTouchUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = true
    }

    /// Starts selftest.nds and waits until it runs. Returns the overlay and
    /// the touch screen.
    @MainActor
    private func launchTheDSSelftest(_ app: XCUIApplication) throws -> (overlay: XCUIElement, touchScreen: PlacedRect, scale: Int) {
        app.launchArguments = ["-ArcfoldAutorun", try fixturePath("selftest", "nds")]
        app.launch()
        let overlay = overlayWithLayout(in: app)
        let running = NSPredicate { element, _ in
            guard let label = (element as? XCUIElement)?.label,
                  let range = label.range(of: #"Emulation ([0-9.]+) fps"#, options: .regularExpression)
            else { return false }
            return (Double(label[range].split(separator: " ")[1]) ?? 0) > 0
        }
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: running, object: overlay)], timeout: 30),
                       .completed, "selftest.nds does not run")
        let values = OverlayValues(overlay)
        let touchScreen = try XCTUnwrap(values.touchScreen, "No touch screen in \(values.pairs)")
        XCTAssertEqual(touchScreen.width, 256 * touchScreen.scale)
        XCTAssertEqual(touchScreen.height, 192 * touchScreen.scale)
        return (overlay, touchScreen, values.scale)
    }

    /// A tap on view pixel (`x`, `y`): its top left corner in points. The
    /// Simulator delivers touches on whole view pixels.
    @MainActor
    private func tap(_ app: XCUIApplication, viewPixelX x: Int, y: Int, scale: Int) {
        app.viewOrigin
            .withOffset(CGVector(dx: CGFloat(x) / CGFloat(scale), dy: CGFloat(y) / CGFloat(scale)))
            .tap()
    }

    /// Whether the screenshot shows the crosshair of selftest.nds crossing at
    /// DS pixel (`px`, `py`): that cell red over exactly k × k view pixels,
    /// the cells beside it on the crosshair white, the next diagonal one not.
    private func crosshair(in pixels: Pixels, at px: Int, _ py: Int, on screen: PlacedRect) -> String? {
        let k = screen.scale
        let left = screen.x + px * k
        let top = screen.y + py * k
        let red: (UInt8, UInt8, UInt8) = (255, 0, 0)
        let white: (UInt8, UInt8, UInt8) = (255, 255, 255)
        var problems: [String] = []
        for (x, y) in [(left, top), (left + k - 1, top), (left, top + k - 1), (left + k - 1, top + k - 1)]
            where !pixels.matches(x: x, y: y, red, tolerance: 60) {
            problems.append("not red: \(pixels.describe(x: x, y: y))")
        }
        var whites: [(Int, Int)] = []
        if px > 0 { whites.append((left - 1, top + k / 2)) }
        if px < 255 { whites.append((left + k, top + k / 2)) }
        if py > 0 { whites.append((left + k / 2, top - 1)) }
        if py < 191 { whites.append((left + k / 2, top + k)) }
        for (x, y) in whites where !pixels.matches(x: x, y: y, white, tolerance: 40) {
            problems.append("not white: \(pixels.describe(x: x, y: y))")
        }
        if px < 255, py < 191 {
            let (x, y) = (left + k + k / 2, top + k + k / 2)
            if pixels.matches(x: x, y: y, white, tolerance: 40) || pixels.matches(x: x, y: y, red, tolerance: 60) {
                problems.append("crosshair beside the pixel: \(pixels.describe(x: x, y: y))")
            }
        }
        return problems.isEmpty ? nil : problems.joined(separator: "; ")
    }

    /// Taps on DS pixel centres and on the first and last whole view pixel of
    /// cells, corners included; every tap must reach its pixel in the
    /// overlay and in the picture of selftest.nds, and no button may react.
    @MainActor
    func testEveryTapHitsItsDSPixel() throws {
        let app = XCUIApplication()
        let (overlay, screen, scale) = try launchTheDSSelftest(app)
        let k = screen.scale

        // (DS pixel, view pixel) pairs.
        var taps: [(pixel: (Int, Int), view: (Int, Int), what: String)] = []
        var centres = [(0, 0), (255, 0), (0, 191), (255, 191), (128, 96), (1, 1), (254, 190)]
        for i in stride(from: 3, to: 256, by: 23) {
            centres.append((i, (i * 3) % 192))
        }
        for (px, py) in centres {
            taps.append(((px, py), (screen.x + px * k + k / 2, screen.y + py * k + k / 2), "centre"))
        }
        for (px, py) in [(10, 20), (100, 101), (200, 150), (0, 0), (255, 191)] {
            taps.append(((px, py), (screen.x + px * k, screen.y + py * k), "first view pixel"))
            taps.append(((px, py), (screen.x + (px + 1) * k - 1, screen.y + (py + 1) * k - 1), "last view pixel"))
            if px < 255, py < 191 {
                taps.append(((px + 1, py + 1), (screen.x + (px + 1) * k, screen.y + (py + 1) * k), "first view pixel after a cell"))
            }
        }
        XCTAssertGreaterThanOrEqual(taps.count, 30)

        let start = OverlayValues(overlay)
        let buttonPresses = try XCTUnwrap(start.buttonPresses)
        var presses = try XCTUnwrap(start.pointerPresses)
        var hits = 0
        var drawn = 0
        for (pixel, view, what) in taps {
            tap(app, viewPixelX: view.0, y: view.1, scale: scale)
            presses += 1
            let expected = "pointer=\(pixel.0),\(pixel.1);pointerPresses=\(presses);"
            if waitUntil(overlay, hasValue: expected, timeout: 5) {
                hits += 1
            } else {
                XCTFail("Tap on view pixel \(view) (\(what) of \(pixel)): expected \(expected) in \(overlay.value as? String ?? "-")")
                presses = OverlayValues(overlay).pointerPresses ?? presses
                continue
            }
            // selftest.nds draws the crosshair a frame or two later. Where the
            // debug overlay lies over it (open and like a book the screens sit
            // side by side at the top), the overlay hides for the screenshot.
            let look = { () throws -> String? in
                var problem: String? = "no screenshot"
                let deadline = Date.now.addingTimeInterval(3)
                repeat {
                    let pixels = try Pixels(try XCTUnwrap(app.displayScreenshot().uprightImage))
                    problem = self.crosshair(in: pixels, at: pixel.0, pixel.1, on: screen)
                } while problem != nil && Date.now < deadline
                return problem
            }
            let around = CGRect(x: screen.x + (pixel.0 - 1) * k, y: screen.y + (pixel.1 - 1) * k, width: 3 * k, height: 3 * k)
            let problem = try overlayRect(in: app, scale: scale).map { $0.intersects(around) } == true
                ? withOverlayHidden(in: app, look) : look()
            if let problem {
                XCTFail("Crosshair for \(pixel) (\(what)): \(problem)")
            } else {
                drawn += 1
            }
        }
        keep(app.displayScreenshot(), named: "After \(taps.count) taps")
        XCTAssertEqual(hits, taps.count, "Taps that reached their pixel in the overlay")
        XCTAssertEqual(drawn, taps.count, "Taps that selftest.nds drew at their pixel")
        XCTAssertEqual(OverlayValues(overlay).buttonPresses, buttonPresses, "A button reacted on the touch screen")
    }

    /// Taps at computed places of the lower screen reach exactly their DS
    /// pixel in every pose that shows it: closed as the Simulator is, and
    /// flat, like a book and tabletop as `DebugRemote` sets them while
    /// the game runs (ADR 0006, sections 6 and 15). The places are the four
    /// corners, the middle, the middle of each edge, places near the lower
    /// edge and the first and last view pixel of two cells, all of them in
    /// every pose. The overlay must show every tap and the picture the
    /// crosshair at it; where the overlay lies over the crosshair, the
    /// picture is checked with the overlay hidden.
    ///
    /// Each pose begins with a tap at the very top edge, where nothing takes
    /// touches: under the full-screen cover of the library's navigation
    /// stack, such a tap took every later touch in the top 60 to 70 pt away
    /// from the game (ADR 0006, section "Nachbesserungen nach der Prüfung").
    /// The touch screen begins below the top edge guard of 64 pt anyway.
    @MainActor
    func testTapsHitTheirPixelsInEveryPose() throws {
        let app = XCUIApplication()
        let (overlay, _, scale) = try launchTheDSSelftest(app)
        var presses = try XCTUnwrap(OverlayValues(overlay).pointerPresses)
        let buttonPresses = OverlayValues(overlay).buttonPresses
        let poses: [(name: String, notification: String, shows: String)] = [
            ("closed", "fold.measured", "posture=single"),
            ("flat", "fold.flat", ",inactive;"),
            ("book", "fold.book", ",active;"),
            ("tabletop", "fold.tabletop", "posture=tabletop"),
        ]
        let centres = [(0, 0), (255, 0), (0, 191), (255, 191), (128, 96), (128, 0), (128, 191), (0, 96), (255, 96),
                       (37, 150), (0, 185), (255, 185), (128, 185), (37, 176), (200, 170)]
        for pose in poses {
            postDebugNotification(pose.notification)
            XCTAssertTrue(waitUntil(overlay, hasValue: pose.shows, timeout: 5), "\(pose.name): no \(pose.shows)")
            // The controls move animated; the picture follows the new arrangement.
            sleep(1)
            let values = OverlayValues(overlay)
            let screen = try XCTUnwrap(values.touchScreen, "\(pose.name): no touch screen in \(values.pairs)")
            XCTAssertGreaterThanOrEqual(screen.y, 64 * scale, "\(pose.name): the touch screen \(screen) lies in the top edge guard")
            // A tap at the very top edge first; it touches nothing.
            app.viewOrigin.withOffset(CGVector(dx: app.gameWindow.frame.width / 2, dy: 3)).tap()
            sleep(1)
            XCTAssertEqual(OverlayValues(overlay).pointerPresses, presses, "\(pose.name): the top edge touched the touch screen")
            let k = screen.scale
            var taps = centres.map { ($0, (screen.x + $0.0 * k + k / 2, screen.y + $0.1 * k + k / 2)) }
            for cell in [(100, 101), (60, 188)] {
                taps.append((cell, (screen.x + cell.0 * k, screen.y + cell.1 * k)))
                taps.append((cell, (screen.x + (cell.0 + 1) * k - 1, screen.y + (cell.1 + 1) * k - 1)))
            }
            XCTAssertEqual(taps.count, 19)
            let controls = coveredRects(in: app, scale: scale, includingOverlay: false)
            let overlayFrame = overlayRect(in: app, scale: scale)
            var hits = 0
            var drawn = 0
            for (pixel, view) in taps {
                tap(app, viewPixelX: view.0, y: view.1, scale: scale)
                presses += 1
                let expected = "pointer=\(pixel.0),\(pixel.1);pointerPresses=\(presses);"
                guard waitUntil(overlay, hasValue: expected, timeout: 5) else {
                    XCTFail("\(pose.name): tap on view pixel \(view) for \(pixel): expected \(expected) in \(overlay.value as? String ?? "–")")
                    presses = OverlayValues(overlay).pointerPresses ?? presses
                    continue
                }
                hits += 1
                // The crosshair; no control may lie over the touch screen.
                let around = CGRect(x: screen.x + (pixel.0 - 1) * k, y: screen.y + (pixel.1 - 1) * k, width: 3 * k, height: 3 * k)
                if let control = controls.first(where: { $0.intersects(around) }) {
                    XCTFail("\(pose.name): a control at \(control) lies over the touch screen near \(pixel)")
                    continue
                }
                let look = { () throws -> String? in
                    var problem: String? = "no screenshot"
                    let deadline = Date.now.addingTimeInterval(3)
                    repeat {
                        let pixels = try Pixels(try XCTUnwrap(app.displayScreenshot().uprightImage))
                        problem = self.crosshair(in: pixels, at: pixel.0, pixel.1, on: screen)
                    } while problem != nil && Date.now < deadline
                    return problem
                }
                let problem = try overlayFrame.map { $0.intersects(around) } == true ? withOverlayHidden(in: app, look) : look()
                if let problem {
                    XCTFail("\(pose.name): crosshair for \(pixel): \(problem)")
                } else {
                    drawn += 1
                }
            }
            keep(app.displayScreenshot(), named: "Touch, \(pose.name), \(k)× at (\(screen.x), \(screen.y))")
            XCTAssertEqual(hits, taps.count, "\(pose.name): taps that reached their pixel in the overlay")
            XCTAssertEqual(drawn, taps.count, "\(pose.name): taps that selftest.nds drew at their pixel")
        }
        XCTAssertEqual(OverlayValues(overlay).buttonPresses, buttonPresses, "A button reacted on the touch screen")
    }

    /// A finger that begins on the touch screen and slides onto a button
    /// presses no button; one that begins on the button and slides onto the
    /// touch screen touches nothing there. The button is one whose straight
    /// way to the touch screen crosses no other control.
    @MainActor
    func testButtonsNeverReactOnTheTouchScreen() throws {
        let app = XCUIApplication()
        let (overlay, screen, scale) = try launchTheDSSelftest(app)
        XCTAssertTrue(app.descendants(matching: .any)["touch-button-A"].firstMatch.waitForExistence(timeout: 10))
        let s = CGFloat(scale)
        let touchScreen = CGRect(x: CGFloat(screen.x) / s, y: CGFloat(screen.y) / s,
                                 width: CGFloat(screen.width) / s, height: CGFloat(screen.height) / s)
        let target = CGPoint(x: touchScreen.midX, y: touchScreen.midY)
        let controls = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@ OR identifier == %@ OR identifier == %@", "touch-button-", "touch-pad", "pause"))
        let frames = (0..<controls.count).map { controls.element(boundBy: $0) }.map { ($0.identifier, $0.frame) }
        let candidate = frames.first { identifier, frame in
            guard identifier.hasPrefix("touch-button-") else { return false }
            let from = CGPoint(x: frame.midX, y: frame.midY)
            // Sample the way from the button to the touch screen.
            return (1...100).allSatisfy { step in
                let t = CGFloat(step) / 100
                let point = CGPoint(x: from.x + (target.x - from.x) * t, y: from.y + (target.y - from.y) * t)
                return touchScreen.contains(point) || !frames.contains { other in
                    other.0 != identifier && other.1.insetBy(dx: -other.1.width / 3, dy: -other.1.height / 3).contains(point)
                }
            }
        }
        let (identifier, frame) = try XCTUnwrap(candidate, "No button with a clear way to the touch screen")
        let label = String(identifier.dropFirst("touch-button-".count))
        let origin = app.viewOrigin
        let button = origin.withOffset(CGVector(dx: frame.midX, dy: frame.midY))
        let middle = origin.withOffset(CGVector(dx: target.x, dy: target.y))

        var values = OverlayValues(overlay)
        let buttons = try XCTUnwrap(values.buttonPresses)
        let pointer = try XCTUnwrap(values.pointerPresses)

        middle.press(forDuration: 0.5, thenDragTo: button, withVelocity: .slow, thenHoldForDuration: 0.5)
        XCTAssertTrue(waitUntil(overlay, hasValue: "pointerPresses=\(pointer + 1);"), "The stylus did not press")
        values = OverlayValues(overlay)
        XCTAssertEqual(values.buttonPresses, buttons, "A finger from the touch screen pressed \(label)")

        button.press(forDuration: 0.5, thenDragTo: middle, withVelocity: .slow, thenHoldForDuration: 0.5)
        XCTAssertTrue(waitUntil(overlay, hasValue: "buttonPresses=\(buttons + 1);lastButtons=\(label)"), "\(label) did not press")
        // Time for the touch screen to show a press, if there were one.
        sleep(1)
        values = OverlayValues(overlay)
        XCTAssertEqual(values.pointerPresses, pointer + 1, "A finger from \(label) touched the touch screen")
        XCTAssertEqual(values.buttonPresses, buttons + 1)
        keep(app.displayScreenshot(), named: "After sliding both ways with \(label)")
    }
}
