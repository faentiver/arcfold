import XCTest

/// The fold layouts on the screen (ADR 0006, section 14). The tests depend on
/// no pose: they run in the pose the Simulator is in (closed after booting),
/// read pose and rectangles from the debug overlay and check the screenshot
/// against them; for the closed Duo they also check the numbers of ADR 0006.
final class FoldLayoutUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = true
    }

    /// The closed Duo: the outer display, 1398 × 2034 px.
    private func isClosedDuo(_ values: OverlayValues) -> Bool {
        values.posture == "single" && values.view?.width == 1398 && values.view?.height == 2034
    }

    /// Screens are whole-number scaled, inside the safe area, apart.
    private func checkRules(_ values: OverlayValues, sources: [(width: Int, height: Int)]) {
        let screens = values.screens
        XCTAssertEqual(screens.count, sources.count, "Screens: \(screens)")
        guard let view = values.view, let safe = values.safe else {
            return XCTFail("No view or safe area in the overlay")
        }
        for (screen, source) in zip(screens, sources) {
            XCTAssertEqual(screen.width, source.width * screen.scale, "\(screen)")
            XCTAssertEqual(screen.height, source.height * screen.scale, "\(screen)")
            XCTAssertTrue(screen.x >= safe.left && screen.y >= safe.top
                          && screen.maxX <= view.width - safe.right && screen.maxY <= view.height - safe.bottom,
                          "\(screen) outside the safe area \(safe) of \(view)")
        }
        if screens.count == 2 {
            let (a, b) = (screens[0], screens[1])
            XCTAssertTrue(a.maxX <= b.x || b.maxX <= a.x || a.maxY <= b.y || b.maxY <= a.y, "The screens overlap")
        }
    }

    /// Takes a screenshot of the display that shows the app and checks that
    /// it has the size of the game view, give or take the pixel that XCTest
    /// leaves off on the inner display (`displayScreenshot()`).
    @MainActor
    private func screenshot(of app: XCUIApplication, _ values: OverlayValues, named name: String) throws -> Pixels {
        let screenshot = app.displayScreenshot()
        keep(screenshot, named: name)
        let pixels = try Pixels(try XCTUnwrap(screenshot.uprightImage))
        if let view = values.view {
            XCTAssertLessThanOrEqual(abs(pixels.width - view.width), 1, "The screenshot is not the game view")
            XCTAssertLessThanOrEqual(abs(pixels.height - view.height), 1, "The screenshot is not the game view")
        }
        return pixels
    }

    /// Checks `color` at view pixel (`x`, `y`) unless something lies over it.
    /// Returns whether it checked.
    @discardableResult
    private func expect(_ pixels: Pixels, x: Int, y: Int, _ color: (UInt8, UInt8, UInt8), _ what: String,
                        covered: [CGRect], tolerance: Int = 24) -> Bool {
        guard !covered.contains(where: { $0.contains(CGPoint(x: x, y: y)) }) else { return false }
        XCTAssertTrue(pixels.matches(x: x, y: y, color, tolerance: tolerance),
                      "\(what): expected \(color), got \(pixels.describe(x: x, y: y))")
        return true
    }

    // MARK: Test patterns

    /// The DS test pattern: each screen in its own colour with a white frame
    /// exactly at its rectangle, black around it, and marker pixels as cells
    /// of exactly `scale × scale` view pixels (PreviewContent.DSPattern).
    @MainActor
    func testTheDSTestPatternSitsOnItsRectangles() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ArcfoldTestPattern", "ds"]
        app.launch()
        let overlay = overlayWithLayout(in: app)
        XCTAssertTrue(waitUntil(overlay, hasValue: "touch=1"))
        let shown = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "shown 1"), object: overlay)
        XCTAssertEqual(XCTWaiter().wait(for: [shown], timeout: 10), .completed, "The pattern was never shown")
        let values = OverlayValues(overlay)
        checkRules(values, sources: [(256, 192), (256, 192)])
        if isClosedDuo(values) {
            // ADR 0006, section 8: the DS keeps the vertical bar, 4× each, stacked at the top.
            XCTAssertEqual(values.safe?.right, 252, "The vertical bar at the side")
            XCTAssertEqual(values.screens, [PlacedRect(x: 61, y: 0, width: 1024, height: 768, scale: 4),
                                            PlacedRect(x: 61, y: 768, width: 1024, height: 768, scale: 4)])
        }

        let covered = coveredRects(in: app, scale: values.scale)
        let pixels = try screenshot(of: app, values, named: "DS test pattern")
        let colors: [(fill: (UInt8, UInt8, UInt8), marker: (UInt8, UInt8, UInt8), markers: [(Int, Int)])] = [
            ((0x30, 0x60, 0xC0), (0xFF, 0x00, 0x00), [(20, 150), (235, 150), (128, 100)]),
            ((0x30, 0xA0, 0x50), (0xFF, 0xFF, 0x00), [(20, 20), (235, 171), (128, 96)]),
        ]
        let white: (UInt8, UInt8, UInt8) = (255, 255, 255)
        let black: (UInt8, UInt8, UInt8) = (0, 0, 0)
        var checks = 0
        for (screen, color) in zip(values.screens, colors) {
            let k = screen.scale
            let middleX = screen.x + screen.width / 2 + k / 2
            let middleY = screen.y + screen.height / 2 + k / 2
            // The frame: the first and the last row and column of the screen
            // are white over exactly k view pixels, inside them the fill.
            for (x, y, what) in [(screen.x, middleY, "left edge"), (screen.x + k - 1, middleY, "left edge, last pixel"),
                                 (screen.maxX - 1, middleY, "right edge"), (screen.maxX - k, middleY, "right edge, first pixel"),
                                 (middleX, screen.y, "top edge"), (middleX, screen.maxY - 1, "bottom edge"),
                                 (middleX, screen.y + k - 1, "top edge, last pixel"), (middleX, screen.maxY - k, "bottom edge, first pixel")] {
                checks += expect(pixels, x: x, y: y, white, "\(screen) \(what)", covered: covered) ? 1 : 0
            }
            for (x, y, what) in [(screen.x + k, middleY, "inside the left edge"), (screen.maxX - k - 1, middleY, "inside the right edge"),
                                 (middleX, screen.y + k, "inside the top edge"), (middleX, screen.maxY - k - 1, "inside the bottom edge")] {
                checks += expect(pixels, x: x, y: y, color.fill, "\(screen) \(what)", covered: covered) ? 1 : 0
            }
            // Black right outside, where no other screen lies.
            for (x, y, what) in [(screen.x - 1, middleY, "left of"), (screen.maxX, middleY, "right of")]
                where !values.screens.contains(where: { $0.contains(x: x, y: y) }) && x >= 0 {
                checks += expect(pixels, x: x, y: y, black, "\(what) \(screen)", covered: covered, tolerance: 12) ? 1 : 0
            }
            // Each marker is one source pixel: k × k view pixels, its
            // neighbours on all four sides in the fill colour.
            for (mx, my) in color.markers {
                let left = screen.x + mx * k
                let top = screen.y + my * k
                for (x, y) in [(left, top), (left + k - 1, top + k - 1), (left + k / 2, top + k / 2)] {
                    checks += expect(pixels, x: x, y: y, color.marker, "\(screen) marker (\(mx), \(my))", covered: covered) ? 1 : 0
                }
                for (x, y) in [(left - 1, top + k / 2), (left + k, top + k / 2), (left + k / 2, top - 1), (left + k / 2, top + k)] {
                    checks += expect(pixels, x: x, y: y, color.fill, "\(screen) next to marker (\(mx), \(my))", covered: covered) ? 1 : 0
                }
            }
        }
        // The touch screen is never covered: all of its checks ran.
        XCTAssertGreaterThanOrEqual(checks, 33, "Too few pixels checked")
    }

    /// The GBA test pattern of M1 in the layout: its white frame exactly at
    /// the rectangle, the eight colour bars inside.
    @MainActor
    func testTheGBATestPatternSitsOnItsRectangle() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ArcfoldTestPattern", "gba"]
        app.launch()
        let overlay = overlayWithLayout(in: app)
        let shown = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "shown 1"), object: overlay)
        XCTAssertEqual(XCTWaiter().wait(for: [shown], timeout: 10), .completed, "The pattern was never shown")
        let values = OverlayValues(overlay)
        checkRules(values, sources: [(240, 160)])
        if isClosedDuo(values) {
            // ADR 0006, section 8: the GBA moves the vertical bar to the top, 5×.
            XCTAssertEqual(values.safe?.top, 246, "The vertical bar on top")
            XCTAssertEqual(values.screens, [PlacedRect(x: 99, y: 246, width: 1200, height: 800, scale: 5)])
        }
        let screen = try XCTUnwrap(values.screens.first)
        let covered = coveredRects(in: app, scale: values.scale)
        let pixels = try screenshot(of: app, values, named: "GBA test pattern")
        let k = screen.scale
        let white: (UInt8, UInt8, UInt8) = (255, 255, 255)
        var checks = 0
        let middleY = screen.y + screen.height * 5 / 6
        for (x, y, what) in [(screen.x, middleY, "left edge"), (screen.x + k - 1, middleY, "left edge, last pixel"),
                             (screen.maxX - 1, middleY, "right edge"), (screen.maxX - k, middleY, "right edge, first pixel"),
                             (screen.x + screen.width / 2, screen.maxY - 1, "bottom edge")] {
            checks += expect(pixels, x: x, y: y, white, what, covered: covered) ? 1 : 0
        }
        checks += expect(pixels, x: screen.x - 1, y: middleY, (0, 0, 0), "left of the picture", covered: covered, tolerance: 12) ? 1 : 0
        checks += expect(pixels, x: screen.maxX, y: middleY, (0, 0, 0), "right of the picture", covered: covered, tolerance: 12) ? 1 : 0
        // The bars in the upper two thirds, sampled in the middle of each.
        let bars: [(UInt8, UInt8, UInt8)] = [(255, 255, 255), (255, 255, 0), (0, 255, 255), (0, 255, 0),
                                             (255, 0, 255), (255, 0, 0), (0, 0, 255), (0, 0, 0)]
        for (index, color) in bars.enumerated() {
            let x = screen.x + (240 * (2 * index + 1) / 16) * k + k / 2
            for row in [60, 100] {
                checks += expect(pixels, x: x, y: screen.y + row * k + k / 2, color, "bar \(index)", covered: covered, tolerance: 40) ? 1 : 0
            }
        }
        XCTAssertGreaterThanOrEqual(checks, 10, "Too few pixels checked")
    }

    // MARK: Real games

    /// selftest.gba in the layout: the picture on its rectangle.
    @MainActor
    func testTheGBAGameSitsOnItsRectangle() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ArcfoldAutorun", try fixturePath("selftest", "gba")]
        app.launch()
        let overlay = overlayWithLayout(in: app)
        XCTAssertTrue(waitUntil(overlay, hasValue: "screens="))
        waitForFrames(overlay)
        let values = OverlayValues(overlay)
        checkRules(values, sources: [(240, 160)])
        if isClosedDuo(values) {
            XCTAssertEqual(values.screens, [PlacedRect(x: 99, y: 246, width: 1200, height: 800, scale: 5)])
        }
        let screen = try XCTUnwrap(values.screens.first)
        let covered = coveredRects(in: app, scale: values.scale)
        let pixels = try screenshot(of: app, values, named: "selftest.gba in the layout")
        // Around the picture, black; inside, the picture of selftest.gba is
        // not black everywhere.
        var checks = 0
        for y in [screen.y + screen.height / 2, screen.maxY - 2] {
            checks += expect(pixels, x: screen.x - 1, y: y, (0, 0, 0), "left of the picture", covered: covered, tolerance: 12) ? 1 : 0
            checks += expect(pixels, x: screen.maxX, y: y, (0, 0, 0), "right of the picture", covered: covered, tolerance: 12) ? 1 : 0
        }
        XCTAssertGreaterThanOrEqual(checks, 2, "Too few pixels checked")
        let bounds = pixels.boundsOfLight(in: (screen.x, screen.y, screen.maxX - 1, screen.maxY - 1))
        XCTAssertNotNil(bounds, "The picture is black")
    }

    /// selftest.nds in the layout: both screens in their background colours on
    /// their rectangles (top 0x2884, bottom 0x0920 in BGR555), black around them.
    @MainActor
    func testTheDSGameSitsOnItsRectangles() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ArcfoldAutorun", try fixturePath("selftest", "nds")]
        app.launch()
        let overlay = overlayWithLayout(in: app)
        waitForFrames(overlay)
        let values = OverlayValues(overlay)
        checkRules(values, sources: [(256, 192), (256, 192)])
        if isClosedDuo(values) {
            XCTAssertEqual(values.screens, [PlacedRect(x: 61, y: 0, width: 1024, height: 768, scale: 4),
                                            PlacedRect(x: 61, y: 768, width: 1024, height: 768, scale: 4)])
        }
        XCTAssertEqual(values.touchScreen, values.screens.last)
        let covered = coveredRects(in: app, scale: values.scale)
        let pixels = try screenshot(of: app, values, named: "selftest.nds in the layout")
        let top = values.screens[0]
        let bottom = values.screens[1]
        // BGR555 to 8 bits as melonDS draws it: top (4, 4, 10) → (32, 32, 81),
        // bottom (0, 9, 2) → (0, 73, 16).
        let topColor: (UInt8, UInt8, UInt8) = (32, 32, 81)
        let bottomColor: (UInt8, UInt8, UInt8) = (0, 73, 16)
        var checks = 0
        // The lower screen: its corners and middle, before any touch.
        for (sx, sy) in [(0, 0), (255, 0), (0, 191), (255, 191), (200, 100)] {
            let x = bottom.x + sx * bottom.scale + bottom.scale / 2
            let y = bottom.y + sy * bottom.scale + bottom.scale / 2
            checks += expect(pixels, x: x, y: y, bottomColor, "lower screen pixel (\(sx), \(sy))", covered: covered, tolerance: 16) ? 1 : 0
        }
        // The upper screen right of the block rows (x 250 to 255, rows 140 to 143).
        for (sx, sy) in [(252, 141), (255, 191), (0, 191)] {
            let x = top.x + sx * top.scale + top.scale / 2
            let y = top.y + sy * top.scale + top.scale / 2
            checks += expect(pixels, x: x, y: y, topColor, "upper screen pixel (\(sx), \(sy))", covered: covered, tolerance: 16) ? 1 : 0
        }
        for screen in [top, bottom] {
            let middleY = screen.y + screen.height / 2 + 1
            for x in [screen.x - 1, screen.maxX] where !values.screens.contains(where: { $0.contains(x: x, y: middleY) }) {
                checks += expect(pixels, x: x, y: middleY, (0, 0, 0), "beside \(screen)", covered: covered, tolerance: 12) ? 1 : 0
            }
        }
        XCTAssertGreaterThanOrEqual(checks, 7, "Too few pixels checked")
    }

    /// Waits until the emulation runs: a frame rate above 0 in the overlay.
    @MainActor
    private func waitForFrames(_ overlay: XCUIElement) {
        let running = NSPredicate { element, _ in
            guard let label = (element as? XCUIElement)?.label,
                  let range = label.range(of: #"Emulation ([0-9.]+) fps"#, options: .regularExpression)
            else { return false }
            return (Double(label[range].split(separator: " ")[1]) ?? 0) > 0
        }
        let expectation = XCTNSPredicateExpectation(predicate: running, object: overlay)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: 30), .completed, "The game does not run")
    }
}
