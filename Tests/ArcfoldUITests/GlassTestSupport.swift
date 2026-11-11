import XCTest

/// Helpers for the UI tests of the Liquid Glass interface (ADR 0007). They
/// repeat what `LaunchTests` keeps private, so that file stays unchanged.
class GlassUITestCase: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// selftest.gba from this UI test bundle; the Simulator lets the app read it by path.
    func selftestPath() throws -> String {
        let url = try XCTUnwrap(Bundle(for: GlassUITestCase.self).url(forResource: "selftest", withExtension: "gba"),
                                "selftest.gba is not in the UI test bundle; check project.yml")
        return url.path(percentEncoded: false)
    }

    /// Starts selftest.gba through the debug launch and waits until the debug
    /// overlay shows a frame rate above 0. Returns the overlay.
    @MainActor
    @discardableResult
    func launchTheSelftest(_ app: XCUIApplication, arguments: [String] = []) throws -> XCUIElement {
        app.launchArguments = ["-ArcfoldAutorun", try selftestPath()] + arguments
        app.launch()
        let overlay = app.descendants(matching: .any)["debug-overlay"].firstMatch
        XCTAssertTrue(overlay.waitForExistence(timeout: 30))
        waitUntilRunning(overlay)
        return overlay
    }

    /// Waits until the overlay reports more than 0 frames per second.
    @MainActor
    func waitUntilRunning(_ overlay: XCUIElement, timeout: TimeInterval = 30) {
        let running = NSPredicate { element, _ in
            guard let label = (element as? XCUIElement)?.label else { return false }
            return Self.framesPerSecond(in: label).map { $0 > 0 } ?? false
        }
        let result = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: running, object: overlay)],
                                      timeout: timeout)
        XCTAssertEqual(result, .completed, "No frame rate above 0 in: \(overlay.label)")
    }

    static func framesPerSecond(in label: String) -> Double? {
        guard let match = label.firstMatch(of: /Emulation ([0-9.]+) fps/) else { return nil }
        return Double(match.1)
    }

    static func presses(in label: String) -> Int? {
        guard let match = label.firstMatch(of: /presses ([0-9]+)/) else { return nil }
        return Int(match.1)
    }

    /// Waits until the label of `element` contains `text`.
    @MainActor
    func waitUntil(_ element: XCUIElement, shows text: String, timeout: TimeInterval = 10) {
        let shows = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", text), object: element)
        let result = XCTWaiter().wait(for: [shows], timeout: timeout)
        XCTAssertEqual(result, .completed, "Expected \"\(text)\" in: \(element.label)")
    }

    /// Waits until `element` no longer exists.
    @MainActor
    func waitUntilGone(_ element: XCUIElement, timeout: TimeInterval = 10) -> Bool {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        return XCTWaiter().wait(for: [gone], timeout: timeout) == .completed
    }

    /// Flips a switch. A plain tap is often too short for a switch in the
    /// Simulator, so it presses a little longer, on the switch at the
    /// trailing end of the row.
    @MainActor
    func flip(_ toggle: XCUIElement) {
        let before = toggle.value as? String
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).press(forDuration: 0.15)
        let changed = XCTNSPredicateExpectation(
            predicate: NSPredicate { element, _ in ((element as? XCUIElement)?.value as? String) != before },
            object: toggle)
        XCTAssertEqual(XCTWaiter().wait(for: [changed], timeout: 3), .completed, "The switch did not change")
    }

    /// The pixels of the display the app runs on in view pixels, and their
    /// scale per point of the window (see `uprightImage`).
    @MainActor
    func pixels(of app: XCUIApplication) throws -> (pixels: Pixels, scale: CGFloat) {
        let screenshot = app.displayScreenshot()
        return (try Pixels(try XCTUnwrap(screenshot.uprightImage)), screenshot.image.scale)
    }

    /// The text contrast of an element in pixels: its middle half, where the
    /// label of a button sits; for a text, the text against its background.
    static func contrast(of frame: CGRect, in pixels: Pixels, scale: CGFloat) -> Double {
        let middle = frame.insetBy(dx: frame.width * 0.25, dy: frame.height * 0.25)
        return pixels.textContrast(in: CGRect(x: middle.minX * scale, y: middle.minY * scale,
                                              width: middle.width * scale, height: middle.height * scale))
    }

    // MARK: Accessibility audit

    /// Prominent buttons on the accent colour. White on indigo must pass
    /// for them; "nearly passed" is no exception here (ADR 0007).
    static let accentButtons: Set<String> = ["Resume", "Close", "Import Games"]

    static let auditTypes: XCUIAccessibilityAuditType = [.contrast, .hitRegion, .sufficientElementDescription,
                                                         .textClipped, .dynamicType]

    /// The system's own colours: secondary labels (the system line under a
    /// tile, the notes in the list of licenses, as in Music and the App Store).
    /// The audit rates them "nearly passed", just under 4.5 : 1 for regular
    /// text. A failed contrast still fails, and so does white on the accent.
    @MainActor
    static func isNearlyPassedContrast(_ issue: XCUIAccessibilityAuditIssue) -> Bool {
        let label = issue.element?.label ?? ""
        return issue.auditType == .contrast && issue.compactDescription == "Contrast nearly passed"
            && !accentButtons.contains(label)
    }

    @MainActor
    static func report(_ issue: XCUIAccessibilityAuditIssue, on screen: String) {
        print("Audit \(screen): \(issue.auditType) \(issue.compactDescription) – "
              + "\(issue.element?.identifier ?? "") \(issue.element?.label ?? "") "
              + "\(issue.element.map { "\($0.elementType.rawValue) \($0.frame)" } ?? "no element")")
    }

    /// Audits what the app shows now. Allowed are "nearly passed" for the
    /// system's secondary labels, a contrast finding whose element measures
    /// at least 4.5 : 1 in the pixels (over glass the audit misjudges text,
    /// docs/wissen/oberflaeche.md), and whatever `alsoAllowed` accepts.
    @MainActor
    func audit(_ app: XCUIApplication, screen: String,
               alsoAllowed: @escaping (XCUIAccessibilityAuditIssue) -> Bool = { _ in false }) throws {
        let (pixels, scale) = try pixels(of: app)
        try app.performAccessibilityAudit(for: Self.auditTypes) { issue in
            var allowed = Self.isNearlyPassedContrast(issue) || alsoAllowed(issue)
            if !allowed, issue.auditType == .contrast, let frame = issue.element?.frame, frame.width > 0 {
                let contrast = Self.contrast(of: frame, in: pixels, scale: scale)
                print("Audit \(screen): pixels of \(issue.element?.label ?? "") give \(String(format: "%.2f", contrast)) : 1")
                allowed = contrast >= 4.5
            }
            Self.report(issue, on: allowed ? "\(screen) (allowed)" : screen)
            return allowed
        }
    }

    /// The audit over every screen of ADR 0007: the library, Licenses, the
    /// notices and the failure (gallery pages), the game and the pause sheet.
    /// On the game screen only the controls (direct touch) and the debug
    /// overlay (fixed 10 pt) may report.
    @MainActor
    func auditTheInterface() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ArcfoldImport", try selftestPath()]
        app.launch()
        XCTAssertTrue(app.buttons["game-gba-selftest"].waitForExistence(timeout: 20))
        try audit(app, screen: "library")

        app.buttons["info-menu"].tap()
        app.buttons["Licenses"].tap()
        XCTAssertTrue(app.navigationBars["Licenses"].waitForExistence(timeout: 5))
        try audit(app, screen: "licenses")
        app.terminate()

        for page in ["notices", "failure"] {
            app.launchArguments = ["-ArcfoldGallery", page]
            app.launch()
            _ = app.wait(for: .runningForeground, timeout: 10)
            Thread.sleep(forTimeInterval: 2)
            try audit(app, screen: page) { issue in
                // Notices and the chip stop growing at accessibility2, so they
                // stay in the picture area; the system's ContentUnavailableView
                // of the failure limits its sizes itself (docs/wissen/oberflaeche.md).
                // At the 466 pt of the closed GBA the audit rates its title or
                // text as clipped, though the tour's screenshot shows both whole.
                (issue.auditType == .dynamicType && issue.compactDescription.contains("partially"))
                    || (page == "failure" && issue.auditType == .textClipped)
            }
            app.terminate()
        }

        try launchTheSelftest(app)
        // The keys and the debug overlay: the only parts of the game screen
        // that may report. The menu button of the console is a key like
        // Select and Start, with its name written on the case below it.
        let keys = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@ OR identifier == %@ OR identifier == %@ OR identifier == %@",
                        "touch-button-", "touch-pad", "debug-overlay", "pause"))
        let allowed = (0..<keys.count).map { keys.element(boundBy: $0).frame.insetBy(dx: -1, dy: -1) }
        try audit(app, screen: "game") { issue in
            let identifier = issue.element?.identifier ?? ""
            // The labels drawn on the touch buttons reach the audit as texts
            // of the keys (fixed sizes, played through the direct touch
            // area); the tour measures their contrast in pixels instead. The
            // lines of the debug overlay reach it as nodes without an element:
            // over the white bar of selftest.gba the card's 60 % black lets
            // the picture through.
            let isOnAKey = issue.element.map { element in allowed.contains { $0.contains(element.frame) } } ?? false
            return identifier.hasPrefix("touch-") || identifier == "debug-overlay" || isOnAKey
                || issue.element?.label.hasPrefix("Emulation") == true
                || (issue.element == nil && issue.auditType == .contrast)
        }
        app.buttons["pause"].tap()
        XCTAssertTrue(app.buttons["resume"].waitForExistence(timeout: 3))
        // Let the zoom finish; mid-way the text lies over the moving glass.
        Thread.sleep(forTimeInterval: 3)
        // The sheet's glass lets the moving game through, and the audit has
        // rated the red "Quit Game" as failed in some runs; such a finding
        // passes on the pixels (measured 5.5 : 1).
        //
        // An iPhone without a fold draws the sheet inset from the edges of
        // the display by scaling it (iOS 27.2: laid out 402 pt wide, drawn
        // 386 pt wide), where the outer display of the Duo lays it out
        // inset (iOS 27.1). The audit then holds each text against a frame
        // that is smaller than its layout and rates every text of the
        // sheet as clipped. Such a finding passes only where the sheet is
        // drawn scaled and the frame of the text is the layout's, on whole
        // pixels, drawn at the scale of the sheet.
        let sheet = app.descendants(matching: .any)["pause-menu"].firstMatch.frame
        let shrink = sheet.width / app.gameWindow.frame.width
        let pixelsPerPoint = app.displayScreenshot().image.scale
        let isSheetScaled = Self.isDrawnScaled(sheet.size, by: shrink, pixelsPerPoint: pixelsPerPoint)
        try audit(app, screen: "pause sheet") { issue in
            guard isSheetScaled, issue.auditType == .textClipped, let frame = issue.element?.frame else { return false }
            return Self.isDrawnScaled(frame.size, by: shrink, pixelsPerPoint: pixelsPerPoint)
        }
    }

    /// Whether `size`, in points, is a size on whole pixels drawn at the
    /// scale `shrink`, below 1: it lies off the pixels itself, and on them
    /// once the scale is taken out. A layout puts every frame on whole
    /// pixels; only a transform moves one off them.
    static func isDrawnScaled(_ size: CGSize, by shrink: CGFloat, pixelsPerPoint: CGFloat) -> Bool {
        func isOnPixels(_ length: CGFloat) -> Bool {
            let pixels = length * pixelsPerPoint
            return abs(pixels - pixels.rounded()) < 0.01
        }
        guard shrink > 0, shrink < 1, size.width > 0, size.height > 0 else { return false }
        return !(isOnPixels(size.width) && isOnPixels(size.height))
            && isOnPixels(size.width / shrink) && isOnPixels(size.height / shrink)
    }
}

/// Contrast measurements on the pixels of a screenshot.
extension Pixels {
    /// Relative luminance (WCAG) of the pixel at `x`, `y`.
    func luminance(x: Int, y: Int) -> Double {
        let x = min(max(x, 0), width - 1)
        let y = min(max(y, 0), height - 1)
        let offset = (y * width + x) * 4
        func linear(_ value: UInt8) -> Double {
            let channel = Double(value) / 255
            return channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(bytes[offset]) + 0.7152 * linear(bytes[offset + 1]) + 0.0722 * linear(bytes[offset + 2])
    }

    /// Which way what is written on a control stands out: light on a dark
    /// plate, as on glass over the picture, or either way, as on the keys
    /// of the console, whose letters are darker than a light cap and
    /// lighter than a dark one.
    enum Writing {
        case light
        case either
    }

    /// The contrast of `writing` against `ground`: the 98th percentile of
    /// `values` (the brightest strokes) or, for `.either`, the 2nd percentile
    /// (the darkest) where that stands out more. `values` are sorted.
    static func contrast(ofWriting values: [Double], against ground: Double, writing: Writing) -> Double {
        func ratio(_ a: Double, _ b: Double) -> Double { (max(a, b) + 0.05) / (min(a, b) + 0.05) }
        guard !values.isEmpty else { return 0 }
        let light = ratio(values[min(values.count - 1, Int(Double(values.count) * 0.98))], ground)
        guard writing == .either else { return light }
        return max(light, ratio(values[Int(Double(values.count) * 0.02)], ground))
    }

    /// The contrast of the label of a button against its plate or cap: the
    /// strokes of the label in the inner half of the button against the
    /// median of a ring just inside its edge (the plate, or the cap of a key
    /// of the console). `rect` is in pixels.
    func labelContrast(in rect: CGRect, writing: Writing = .light) -> Double {
        var inner: [Double] = []
        let core = rect.insetBy(dx: rect.width / 4, dy: rect.height / 4)
        for y in Int(core.minY)..<Int(core.maxY) {
            for x in Int(core.minX)..<Int(core.maxX) {
                inner.append(luminance(x: x, y: y))
            }
        }
        var rim: [Double] = []
        let ring = rect.insetBy(dx: min(rect.width, rect.height) * 0.12, dy: min(rect.width, rect.height) * 0.12)
        let step = max(1, Int(min(ring.width, ring.height) / 40))
        // Left and right edge of the ring, at mid height and above and below it.
        for y in stride(from: Int(ring.midY - ring.height * 0.2), through: Int(ring.midY + ring.height * 0.2), by: step) {
            rim.append(luminance(x: Int(ring.minX), y: y))
            rim.append(luminance(x: Int(ring.maxX), y: y))
        }
        inner.sort()
        rim.sort()
        guard !inner.isEmpty, !rim.isEmpty else { return 0 }
        return Self.contrast(ofWriting: inner, against: rim[rim.count / 2], writing: writing)
    }

    /// The name of a small button written on the case, in `rect` (pixels)
    /// around it: the darkest or brightest strokes against the median, the
    /// case, which the name covers less than half of.
    func inscriptionContrast(in rect: CGRect) -> Double {
        var values: [Double] = []
        for y in Int(rect.minY)..<Int(rect.maxY) {
            for x in Int(rect.minX)..<Int(rect.maxX) {
                values.append(luminance(x: x, y: y))
            }
        }
        values.sort()
        guard !values.isEmpty else { return 0 }
        return Self.contrast(ofWriting: values, against: values[values.count / 2], writing: .either)
    }

    /// Text against its background in `rect` (pixels): the 98th percentile of
    /// the luminance against the median, which is the background where the
    /// text covers less than half of the area. Works for light text on dark.
    func textContrast(in rect: CGRect) -> Double {
        var values: [Double] = []
        for y in Int(rect.minY)..<Int(rect.maxY) {
            for x in Int(rect.minX)..<Int(rect.maxX) {
                values.append(luminance(x: x, y: y))
            }
        }
        values.sort()
        guard !values.isEmpty else { return 0 }
        let text = values[min(values.count - 1, Int(Double(values.count) * 0.98))]
        let background = values[values.count / 2]
        return (max(text, background) + 0.05) / (min(text, background) + 0.05)
    }

    /// How well the edge of a control stands out from what lies around it,
    /// the boundary a user needs to see (WCAG non-text contrast): at mid
    /// height on the left and right, pixels just inside the edge, where the
    /// border of Increase Contrast or the rim of the glass lies, against the
    /// median just outside. Returns the weaker side. `rect` is in pixels,
    /// `scale` pixels per point of what is drawn (less on a gallery page
    /// scaled down); `rows` the share of the height above and below the
    /// middle that is measured, where the edge runs straight up and down.
    func edgeContrast(in rect: CGRect, scale: CGFloat, rows share: CGFloat = 0.15) -> Double {
        func side(edge: CGFloat, inward: CGFloat) -> Double {
            var outside: [Double] = []
            var inside: [Double] = []
            let rows = stride(from: Int(rect.midY - rect.height * share), through: Int(rect.midY + rect.height * share), by: 1)
            for y in rows {
                // Close to the edge: a key stands out from its well and the
                // case around it, not from a bezel a few points away.
                for step in stride(from: 1, through: 2, by: 0.5) {
                    outside.append(luminance(x: Int(edge - inward * step * scale), y: y))
                }
                for step in stride(from: 0.2, through: 2.2, by: 1 / scale) {
                    inside.append(luminance(x: Int(edge + inward * step * scale), y: y))
                }
            }
            outside.sort()
            guard !outside.isEmpty, !inside.isEmpty else { return 0 }
            let around = outside[outside.count / 2]
            let contrasts = inside.map { (max($0, around) + 0.05) / (min($0, around) + 0.05) }.sorted()
            return contrasts[min(contrasts.count - 1, Int(Double(contrasts.count) * 0.9))]
        }
        return min(side(edge: rect.minX, inward: 1), side(edge: rect.maxX - 1, inward: -1))
    }

    /// The ring of a pressed button with Differentiate Without Color against
    /// the fill inside it, at mid height on the left: the ring is 1.5 pt
    /// wide and lies `inset` points inside the edge of the cap (3 pt on a
    /// key, less on a small button or a low L or R, as `KeyCap` draws it).
    /// `rect` is the cap in pixels, `scale` pixels per point of what is drawn.
    func ringContrast(in rect: CGRect, scale: CGFloat, inset: CGFloat = 3) -> Double {
        var ring: [Double] = []
        var fill: [Double] = []
        for y in Int(rect.midY - rect.height * 0.1)...Int(rect.midY + rect.height * 0.1) {
            for step in stride(from: inset - 0.5, through: inset + 2, by: 1 / scale) {
                ring.append(luminance(x: Int(rect.minX + step * scale), y: y))
            }
            for step in stride(from: inset + 3.5, through: inset + 5.5, by: 1 / scale) {
                fill.append(luminance(x: Int(rect.minX + step * scale), y: y))
            }
        }
        ring.sort()
        fill.sort()
        guard !ring.isEmpty, !fill.isEmpty else { return 0 }
        // The ring is darker than a light cap or lighter than a dark one.
        return Self.contrast(ofWriting: ring, against: fill[fill.count / 2], writing: .either)
    }

    /// The contrast of the up arrow of the direction pad against the arm it
    /// lies on: the strokes in a box around the arrow against the median of
    /// points beside it on the same arm. `ConsolePad` draws the arrow at
    /// (padCross − padArm · padCross) / 2 · 0.86 of the dish's diameter from
    /// its middle, 0.48 r; the points beside it, 0.22 r to the left and
    /// right, lie on the arm, whose half width is 0.32 r. `rect` is the pad's
    /// dish in pixels.
    func padArrowContrast(in rect: CGRect, writing: Writing = .either) -> Double {
        let radius = rect.width / 2
        let center = CGPoint(x: rect.midX, y: rect.midY - radius * Self.padArrowDistance)
        var arrow: [Double] = []
        let half = radius * 0.16
        for y in Int(center.y - half)..<Int(center.y + half) {
            for x in Int(center.x - half)..<Int(center.x + half) {
                arrow.append(luminance(x: x, y: y))
            }
        }
        var beside: [Double] = []
        for dy in stride(from: -radius * 0.08, through: radius * 0.08, by: max(1, radius * 0.02)) {
            beside.append(luminance(x: Int(center.x - radius * 0.22), y: Int(center.y + dy)))
            beside.append(luminance(x: Int(center.x + radius * 0.22), y: Int(center.y + dy)))
        }
        arrow.sort()
        beside.sort()
        guard !arrow.isEmpty, !beside.isEmpty else { return 0 }
        return Self.contrast(ofWriting: arrow, against: beside[beside.count / 2], writing: writing)
    }

    /// Where `ConsolePad` draws its arrows, in radii of the dish from its
    /// middle: the cross takes 0.88 of the dish, an arm 0.36 of the cross.
    static let padArrowDistance: CGFloat = (0.88 * 2 - 0.88 * 2 * 0.36) / 2 * 0.86
}
