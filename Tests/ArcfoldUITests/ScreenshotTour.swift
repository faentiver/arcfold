import XCTest

/// Screenshots of every state of the interface for the acceptance of ADR 0007,
/// one launch per state, so no state depends on the one before. Run by
/// `Scripts/screenshot-tour.sh` once per variant (light, dark, contrast,
/// large), which sets the appearance of the Simulator and exports the
/// attachments. Each screenshot is named `<variant>-<nn>-<state>`; the
/// measurements go into `<variant>-metrics`.
///
/// In its pose part the script sets each real pose of the Duo with
/// the private posture tool outside the repository and runs the states of the game in it (30 and
/// 31, and 12 sideways); the pose comes as `ARCFOLD_TOUR_POSE`.
final class ScreenshotTour: GlassUITestCase {
    /// The variant the script set up. Without it, as in a plain test run of
    /// the Store scheme, the tour skips every state.
    static var variant: String {
        ProcessInfo.processInfo.environment["ARCFOLD_TOUR_VARIANT"] ?? ""
    }

    /// The real pose the script set for the pose part, such as `open` or
    /// `closed-landscape`; empty in the states of the variants.
    static var pose: String {
        ProcessInfo.processInfo.environment["ARCFOLD_TOUR_POSE"] ?? ""
    }

    /// Measurements of all states, written by `test99Metrics`.
    @MainActor static var metrics: [String] = []

    override func setUp() {
        // A missed limit must not hide the other measurements.
        continueAfterFailure = true
    }

    /// Skips a state that is not part of the running variant, and every
    /// state of the variants in the pose part.
    func only(_ variants: String...) throws {
        try XCTSkipIf(Self.variant.isEmpty, "Runs through Scripts/screenshot-tour.sh")
        try XCTSkipUnless(Self.pose.isEmpty, "The pose part runs the states of the game only")
        try XCTSkipUnless(variants.contains(Self.variant), "Not part of the variant \(Self.variant)")
    }

    /// Skips a state of the pose part outside it.
    func onlyInAPose() throws {
        try XCTSkipIf(Self.variant.isEmpty, "Runs through Scripts/screenshot-tour.sh")
        try XCTSkipIf(Self.pose.isEmpty, "Runs in the pose part of Scripts/screenshot-tour.sh")
    }

    @MainActor
    func shoot(_ app: XCUIApplication, _ number: Int, _ state: String) {
        keep(app.displayScreenshot(), named: "\(Self.variant)-\(String(format: "%02d", number))-\(state)")
    }

    @MainActor
    func record(_ line: String) {
        Self.metrics.append(line)
    }

    /// Launches a gallery page and gives the picture path a moment for its first frames.
    @MainActor
    func launchGallery(_ page: String, _ arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ArcfoldGallery", page] + arguments
        app.launch()
        _ = app.wait(for: .runningForeground, timeout: 10)
        Thread.sleep(forTimeInterval: 2)
        return app
    }

    static func format(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    /// The keys of the running game where the game draws them: the frame of
    /// each key's accessibility element (`touch-button-<label>`, `touch-pad`).
    @MainActor
    static func keys(in app: XCUIApplication, labels: [String] = ["A", "B", "L", "R", "Pad", "Select", "Start"])
        -> [(String, CGRect)] {
        labels.map { label in
            let identifier = label == "Pad" ? "touch-pad" : "touch-button-\(label)"
            return (label, app.descendants(matching: .any)[identifier].firstMatch.frame)
        }
    }

    static func pixelRect(_ frame: CGRect, scale: CGFloat) -> CGRect {
        CGRect(x: frame.minX * scale, y: frame.minY * scale, width: frame.width * scale, height: frame.height * scale)
    }

    /// Measures every key of a panel: the label against its plate (limit 3,
    /// Select and Start 4.5) and the edge against what lies around it (limit
    /// 3 with Increase Contrast, which promises a border, where the keys have
    /// their real size; a gallery scaled down thins the 1 pt border).
    @MainActor
    func measureKeys(_ keys: [(String, CGRect)], named name: String, in pixels: Pixels, scale: CGFloat,
                     checksEdges: Bool) {
        var labels = "contrast \(name)"
        var edges = "edge \(name)"
        for (key, frame) in keys {
            let rect = Self.pixelRect(frame, scale: scale)
            let label = key == "Pad" ? pixels.padArrowContrast(in: rect) : pixels.labelContrast(in: rect)
            let edge = pixels.edgeContrast(in: rect, scale: scale)
            labels += " \(key) \(Self.format(label))"
            edges += " \(key) \(Self.format(edge))"
            XCTAssertGreaterThanOrEqual(label, ["Select", "Start"].contains(key) ? 4.5 : 3, "label of \(key), \(name)")
            if checksEdges, Self.variant == "contrast" {
                XCTAssertGreaterThanOrEqual(edge, 3, "edge of \(key), \(name)")
            }
        }
        record(labels)
        record(edges)
    }

    /// The text contrast of a prominent button on the accent, in pixels.
    @MainActor
    func measureAccentButton(_ button: XCUIElement, named name: String, in app: XCUIApplication) throws {
        let (pixels, scale) = try pixels(of: app)
        let contrast = Self.contrast(of: button.frame, in: pixels, scale: scale)
        record("accent \(name) \(Self.format(contrast))")
        XCTAssertGreaterThanOrEqual(contrast, 4.5, "white on the accent of \(name)")
    }

    /// The number of columns of tiles: tiles in the first row share their top edge.
    @MainActor
    func columns(in app: XCUIApplication) -> Int {
        let tiles = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'game-'")).allElementsBoundByIndex
        guard let top = tiles.map(\.frame.minY).min() else { return 0 }
        return tiles.filter { abs($0.frame.minY - top) < 1 }.count
    }

    // MARK: Library

    @MainActor
    func test01LibraryEmpty() throws {
        try only("light", "dark", "contrast", "large")
        let app = launchGallery("library-empty")
        XCTAssertTrue(app.buttons["info-menu"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Search"].exists, "The empty library shows a search field")
        let importGames = app.buttons["Import Games"]
        XCTAssertTrue(importGames.waitForExistence(timeout: 5))
        try measureAccentButton(importGames, named: "import-games", in: app)
        shoot(app, 1, "library-empty")
    }

    @MainActor
    func test02LibraryShelf() throws {
        try only("light", "dark", "large")
        let app = launchGallery("library-shelf")
        // With large text there is one tile per row, and selftest lies below the screen.
        XCTAssertTrue(app.buttons["game-gba-Arc-Light"].waitForExistence(timeout: 10))
        let columns = columns(in: app)
        record("library-shelf columns \(columns)")
        XCTAssertEqual(columns, Self.variant == "large" ? 1 : 2)
        // The grid lines up with the large title.
        let tile = app.buttons["game-gba-Arc-Light"].frame
        let title = app.navigationBars["Library"].staticTexts["Library"]
        if title.exists {
            record("library-shelf margin tile \(tile.minX) title \(title.frame.minX)")
            XCTAssertEqual(tile.minX, title.frame.minX, accuracy: 1.5, "the grid does not line up with the title")
        } else {
            record("library-shelf margin tile \(tile.minX) title not found")
        }
        shoot(app, 2, "library-shelf")
    }

    @MainActor
    func test03LibraryInner() throws {
        try only("light", "dark")
        let app = launchGallery("library-inner")
        XCTAssertTrue(app.buttons["game-gba-selftest"].waitForExistence(timeout: 10))
        let columns = columns(in: app)
        record("library-inner columns \(columns)")
        XCTAssertEqual(columns, 3)
        shoot(app, 3, "library-inner")
    }

    @MainActor
    func test04LibraryImported() throws {
        try only("light", "dark")
        let app = XCUIApplication()
        app.launchArguments = ["-ArcfoldImport", try selftestPath()]
        app.launch()
        XCTAssertTrue(app.buttons["game-gba-selftest"].waitForExistence(timeout: 20))
        shoot(app, 4, "library-imported")
    }

    @MainActor
    func test05MoreMenu() throws {
        try only("light", "dark")
        let app = XCUIApplication()
        app.launchArguments = ["-ArcfoldImport", try selftestPath()]
        app.launch()
        let more = app.buttons["info-menu"]
        XCTAssertTrue(more.waitForExistence(timeout: 20))
        more.tap()
        XCTAssertTrue(app.buttons["Licenses"].waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 1)
        shoot(app, 5, "more-menu")
    }

    @MainActor
    func test06Search() throws {
        try only("light")
        let app = XCUIApplication()
        app.launchArguments = ["-ArcfoldImport", try selftestPath()]
        app.launch()
        XCTAssertTrue(app.buttons["game-gba-selftest"].waitForExistence(timeout: 20))
        let search = app.buttons["Search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("self")
        XCTAssertTrue(app.buttons["game-gba-selftest"].waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 1)
        shoot(app, 6, "search")
    }

    @MainActor
    func test07Licenses() throws {
        try only("light", "dark")
        let app = XCUIApplication()
        app.launch()
        let more = app.buttons["info-menu"]
        XCTAssertTrue(more.waitForExistence(timeout: 20))
        more.tap()
        app.buttons["Licenses"].tap()
        XCTAssertTrue(app.navigationBars["Licenses"].waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 1)
        shoot(app, 7, "licenses")
    }

    // MARK: Game

    @MainActor
    func test08GameUpright() throws {
        try only("light", "dark", "contrast")
        let app = XCUIApplication()
        try launchTheSelftest(app)
        // The pause button takes touches on 44 × 44 pt, also where it draws
        // the 36 pt of the menu row of M2.
        let pause = app.buttons["pause"]
        record("pause upright \(Int(pause.frame.width)) x \(Int(pause.frame.height)) at \(pause.frame.origin)")
        XCTAssertTrue((44...52).contains(pause.frame.width) && (44...52).contains(pause.frame.height))
        // The keys over the deck at full size, where the game shows them.
        let (pixels, scale) = try pixels(of: app)
        measureKeys(Self.keys(in: app), named: "game-upright-deck", in: pixels, scale: scale, checksEdges: true)
        shoot(app, 8, "game-upright")
    }

    @MainActor
    func test09GameUprightClean() throws {
        try only("light")
        let app = XCUIApplication()
        let overlay = try launchTheSelftest(app)
        app.buttons["pause"].tap()
        let toggle = app.switches["debug-overlay-toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 3))
        flip(toggle)
        app.buttons["resume"].tap()
        XCTAssertTrue(waitUntilGone(overlay))
        Thread.sleep(forTimeInterval: 1)
        shoot(app, 9, "game-upright-clean")
    }

    @MainActor
    func test10PauseMenu() throws {
        try only("light", "contrast", "large")
        let app = XCUIApplication()
        try launchTheSelftest(app)
        app.buttons["pause"].tap()
        XCTAssertTrue(app.buttons["resume"].waitForExistence(timeout: 3))
        Thread.sleep(forTimeInterval: 1)
        let sheet = app.descendants(matching: .any)["pause-menu"].firstMatch
        record("sheet upright \(sheet.frame)")
        // The content sits in the middle of the sheet, not left of it.
        let resume = app.buttons["resume"]
        let left = resume.frame.minX - sheet.frame.minX
        let right = sheet.frame.maxX - resume.frame.maxX
        record("sheet margins left \(Self.format(left)) right \(Self.format(right))")
        XCTAssertEqual(left, right, accuracy: 2, "the content of the sheet sits off centre")
        try measureAccentButton(resume, named: "resume", in: app)
        shoot(app, 10, "pause-menu")
    }

    /// The gallery page with the parts that the game places sideways, turned
    /// by 90 degrees, so that one page shows them all at once; the real game
    /// sideways comes in the pose part (state 30, `closed-landscape`).
    @MainActor
    func test11GameLandscape() throws {
        try only("light", "contrast")
        let app = launchGallery("game-landscape")
        XCTAssertTrue(app.buttons["pause"].waitForExistence(timeout: 10))
        // Turned by 90 degrees, so width and height swap.
        let pause = app.buttons["pause"].frame
        record("pause sideways (gallery, scaled) \(Int(pause.height)) x \(Int(pause.width))")
        shoot(app, 11, "game-landscape")
    }

    /// The pause sheet sideways, in the pose part after the script turned
    /// the closed device (`closed --orientation landscape-left`). It skips
    /// itself where the window stays upright.
    @MainActor
    func test12PauseLandscape() throws {
        try onlyInAPose()
        try XCTSkipUnless(Self.pose == "closed-landscape", "Runs in the pose closed-landscape")
        let app = XCUIApplication()
        try launchTheSelftest(app)
        let window = app.gameWindow.frame
        try XCTSkipUnless(window.width > window.height, "The window does not turn sideways on this device")
        let pause = app.buttons["pause"]
        record("pause sideways \(Int(pause.frame.width)) x \(Int(pause.frame.height)) at \(pause.frame.origin)")
        XCTAssertTrue((44...52).contains(pause.frame.width) && (44...52).contains(pause.frame.height))
        let r = app.descendants(matching: .any)["touch-button-R"].firstMatch.frame
        record("pause sideways ∩ R \(pause.frame.intersection(r).isNull ? "none" : "\(pause.frame.intersection(r))")")
        XCTAssertFalse(pause.frame.intersects(r), "sideways the pause button lies on R")
        record("safe area sideways (window) \(window)")
        pause.tap()
        let resume = app.buttons["resume"]
        XCTAssertTrue(resume.waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 1)
        let sheet = app.descendants(matching: .any)["pause-menu"].firstMatch
        record("sheet sideways \(sheet.frame)")
        try measureAccentButton(resume, named: "resume-sideways", in: app)
        shoot(app, 12, "pause-landscape")
    }

    // MARK: Gallery of the controls

    /// The controls on the deck at rest and pressed; the plates over the
    /// deck are lighter than over the picture.
    @MainActor
    func test13TouchUprightStates() throws {
        try only("light", "contrast")
        let app = launchGallery("touch-upright")
        let (pixels, scale) = try pixels(of: app)
        for row in ["rest", "a-up"] {
            let keys = ["A", "B", "L", "R", "Pad", "Select", "Start"].map { key in
                (key, app.descendants(matching: .any)["gallery-key-\(key)-\(row)"].frame)
            }
            // The panels are scaled to 0.58; the edges are recorded, page 08 checks them.
            measureKeys(keys, named: "deck-\(row)", in: pixels, scale: scale, checksEdges: false)
        }
        shoot(app, 13, "touch-upright-states")
    }

    /// The controls sideways over white, the test pattern and black, at rest
    /// and pressed, with the contrast of each label against its plate.
    @MainActor
    func test14TouchLandscapeBackdrops() throws {
        try only("light", "contrast")
        for pressed in [false, true] {
            let app = launchGallery("touch-landscape", pressed ? ["-ArcfoldGalleryPressed", "YES"] : [])
            let state = pressed ? "pressed" : "rest"
            shoot(app, 14, "touch-landscape-backdrops-\(state)")
            let (pixels, scale) = try pixels(of: app)
            for backdrop in ["white", "pattern", "black"] {
                var line = "contrast \(backdrop)-\(state)"
                var edges = "edge \(backdrop)-\(state)"
                for key in ["A", "B", "L", "R", "Pad", "Select", "Start"] {
                    let element = app.descendants(matching: .any)["gallery-key-\(key)-\(backdrop)-\(state)"]
                    XCTAssertTrue(element.waitForExistence(timeout: 5), "No marker for \(key) over \(backdrop)")
                    let rect = Self.pixelRect(element.frame, scale: scale)
                    let contrast = key == "Pad" ? pixels.padArrowContrast(in: rect) : pixels.labelContrast(in: rect)
                    line += " \(key) \(Self.format(contrast))"
                    if backdrop != "black" {
                        let limit = ["Select", "Start"].contains(key) ? 4.5 : 3.0
                        XCTAssertGreaterThanOrEqual(contrast, limit, "\(key) over \(backdrop), \(state)")
                    }
                    // The boundary of a resting key, recorded only: the panels are
                    // scaled to 0.69, which thins the border (page 08 checks it).
                    if !pressed {
                        edges += " \(key) \(Self.format(pixels.edgeContrast(in: rect, scale: scale)))"
                    }
                }
                record(line)
                if !pressed {
                    record(edges)
                }
            }
            app.terminate()
        }
    }

    @MainActor
    func test15TouchFlat() throws {
        try only("light")
        let app = launchGallery("touch-upright", ["-ArcfoldControlSurface", "flat"])
        shoot(app, 15, "touch-flat")
    }

    @MainActor
    func test16TouchInner() throws {
        try only("light")
        let app = launchGallery("touch-inner")
        shoot(app, 16, "touch-inner")
    }

    /// The notice and the chip where the game places them upright, over
    /// white and the test pattern. With large text the notice shows its whole
    /// text and grows upwards inside the picture area.
    @MainActor
    func test17Notices() throws {
        try only("light", "contrast", "large")
        let app = launchGallery("notices")
        let notices = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Another game is already running'"))
        XCTAssertEqual(notices.count, 2, "one notice per panel")
        for (index, notice) in notices.allElementsBoundByIndex.enumerated() {
            record("notice \(index) \(notice.frame)")
            XCTAssertGreaterThanOrEqual(notice.frame.minY, 0, "the notice leaves the picture area")
        }
        shoot(app, 17, "notices")
    }

    @MainActor
    func test18Failure() throws {
        try only("light", "contrast", "large")
        let app = launchGallery("failure")
        let close = app.buttons["Close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        try measureAccentButton(close, named: "close", in: app)
        // The message is the system's secondary text over the dimmed artwork.
        let message = app.staticTexts["Core Failed to Load: the framework mgba_libretro could not be opened."]
        XCTAssertTrue(message.exists)
        let (pixels, scale) = try pixels(of: app)
        let rect = Self.pixelRect(message.frame, scale: scale)
        let contrast = pixels.textContrast(in: rect)
        record("failure message \(Self.format(contrast))")
        XCTAssertGreaterThanOrEqual(contrast, 4.5, "the failure message")
        shoot(app, 18, "failure")
    }

    /// Pressed with Differentiate Without Color: a ring inside each pressed
    /// button, drawn as content of the glass.
    @MainActor
    func test19TouchDifferentiate() throws {
        try only("light", "contrast")
        let app = launchGallery("touch-differentiate")
        let (pixels, scale) = try pixels(of: app)
        for (row, keys) in [("differentiate-upright", ["A", "Start"]),
                            ("differentiate-sideways", ["A", "B", "L", "R", "Select", "Start"])] {
            var line = "ring \(row)"
            for key in keys {
                let element = app.descendants(matching: .any)["gallery-key-\(key)-\(row)"]
                XCTAssertTrue(element.waitForExistence(timeout: 5), "No marker for \(key) in \(row)")
                let contrast = pixels.ringContrast(in: Self.pixelRect(element.frame, scale: scale), scale: scale)
                line += " \(key) \(Self.format(contrast))"
                XCTAssertGreaterThanOrEqual(contrast, 3, "ring of \(key), \(row)")
            }
            record(line)
        }
        shoot(app, 19, "touch-differentiate")
    }

    /// The audit of GlassUITests in dark mode and with Increase Contrast,
    /// where white on the accent was weakest.
    @MainActor
    func test20Audit() throws {
        try only("dark", "contrast")
        try auditTheInterface()
        record("audit \((testRun?.failureCount ?? 0) == 0 ? "passed" : "failed")")
    }

    // MARK: Real poses

    @MainActor
    func test30DSInThePose() throws {
        try shootTheGame(fileExtension: "nds", system: "ds", number: 30)
    }

    @MainActor
    func test31GBAInThePose() throws {
        try shootTheGame(fileExtension: "gba", system: "gba", number: 31)
    }

    /// A game in the real pose the script set: the layout the overlay
    /// reports, a screenshot of the display it runs on, then the pause sheet
    /// out of the pause button and a screenshot of it, and Resume.
    @MainActor
    private func shootTheGame(fileExtension: String, system: String, number: Int) throws {
        try onlyInAPose()
        let app = XCUIApplication()
        app.launchArguments = ["-ArcfoldAutorun", try fixturePath("selftest", fileExtension)]
        app.launch()
        let overlay = overlayWithLayout(in: app)
        XCTAssertTrue(waitUntil(overlay, framesBeyond: 120), "The game does not run")
        Thread.sleep(forTimeInterval: 1)
        let values = OverlayValues(overlay)
        let expected = Self.expectedPosture[Self.pose]
        if let expected {
            XCTAssertEqual(values.posture, expected, "\(Self.pose): \(values.pairs)")
        }
        record("pose \(Self.pose) \(system): posture \(values.posture ?? "–") view \(values.pairs["view"] ?? "–") "
            + "safe \(values.pairs["safe"] ?? "–") fold \(values.pairs["fold"] ?? "–") screens \(values.pairs["screens"] ?? "–")")
        let pause = app.buttons["pause"]
        XCTAssertTrue(pause.waitForExistence(timeout: 5))
        XCTAssertTrue(pause.frame.width >= 44 && pause.frame.height >= 44, "pause \(pause.frame)")
        XCTAssertGreaterThanOrEqual(pause.frame.minY, 64, "the pause button lies in the top edge guard")
        shoot(app, number, "\(Self.pose)-\(system)")

        pause.tap()
        let resume = app.buttons["resume"]
        XCTAssertTrue(resume.waitForExistence(timeout: 5), "\(Self.pose): the pause sheet did not open")
        Thread.sleep(forTimeInterval: 1.5)
        record("pose \(Self.pose) \(system): sheet \(app.descendants(matching: .any)["pause-menu"].firstMatch.frame)")
        shoot(app, number, "\(Self.pose)-\(system)-sheet")
        resume.tap()
        XCTAssertTrue(waitUntilGone(resume), "\(Self.pose): the sheet stayed")
        XCTAssertTrue(waitUntil(overlay, hasValue: "paused=false;"), "\(Self.pose): Resume did not resume")
    }

    /// The posture each real pose must give (ADR 0006, section 7).
    static let expectedPosture = [
        "closed": "single", "closed-landscape": "single", "open": "flat", "book": "flat",
        "tabletop": "tabletop", "flat-upright": "flat",
    ]

    // MARK: Measurements

    /// Glass against flat in the Simulator, only with `ARCFOLD_TOUR_MEASURE=1`
    /// (ADR 0007): selftest.gba and selftest.nds, each 60 s with glass and
    /// 60 s flat right after it, in the pose the script set. Counted from 5 s
    /// after the first 120 frames to the end: emulated frames per second from
    /// the frame counter, and of the display the frames shown and skipped,
    /// late selections and busy GPU frames.
    @MainActor
    func test98MeasureGlassAgainstFlat() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["ARCFOLD_TOUR_MEASURE"] == "1",
                          "Set ARCFOLD_TOUR_MEASURE=1 to measure")
        let place = Self.pose.isEmpty ? "as the Simulator is" : Self.pose
        for (system, fileExtension) in [("gba", "gba"), ("ds", "nds")] {
            for surface in ["glass", "flat"] {
                let app = XCUIApplication()
                app.launchArguments = ["-ArcfoldAutorun", try fixturePath("selftest", fileExtension),
                                       "-ArcfoldControlSurface", surface]
                app.launch()
                let overlay = overlayWithLayout(in: app)
                XCTAssertTrue(waitUntil(overlay, framesBeyond: 120), "The game does not run")
                Thread.sleep(forTimeInterval: 5)
                let startTime = Date.now
                let start = (values: OverlayValues(overlay), label: overlay.label)
                Thread.sleep(forTimeInterval: 60)
                let end = (values: OverlayValues(overlay), label: overlay.label)
                let seconds = Date.now.timeIntervalSince(startTime)
                let frames = Double((end.values.frames ?? 0) - (start.values.frames ?? 0))
                let first = try XCTUnwrap(Self.display(in: start.label), "No display line in \(start.label)")
                let last = try XCTUnwrap(Self.display(in: end.label), "No display line in \(end.label)")
                let shown = last.shown - first.shown
                let skipped = last.skipped - first.skipped
                let share = shown + skipped > 0 ? 100 * Double(skipped) / Double(shown + skipped) : 0
                let line = "measure \(place) \(system) \(surface): \(String(format: "%.2f", frames / seconds)) frames/s over "
                    + "\(String(format: "%.1f", seconds)) s, display \(last.hertz) Hz, shown \(shown), skipped \(skipped) "
                    + "(\(String(format: "%.1f", share)) %), late \(last.late - first.late), GPU busy \(last.busy - first.busy), "
                    + "resyncs \((end.values.resyncs ?? 0) - (start.values.resyncs ?? 0)), "
                    + "underruns \((end.values.underruns ?? 0) - (start.values.underruns ?? 0))"
                record(line)
                let attachment = XCTAttachment(string: line)
                attachment.name = "\(Self.variant)-measure-\(Self.pose.isEmpty ? "here" : Self.pose)-\(system)-\(surface)"
                attachment.lifetime = .keepAlways
                add(attachment)
                app.terminate()
            }
        }
    }

    /// The display line of the debug overlay: refresh rate, frames shown and
    /// skipped, late selections and busy GPU frames since the start.
    static func display(in label: String) -> (hertz: Int, shown: Int, skipped: Int, late: Int, busy: Int)? {
        let pattern = /Display ([0-9]+) Hz · shown ([0-9]+) · repeated [0-9]+ · skipped ([0-9]+) · late ([0-9]+) · GPU busy ([0-9]+)/
        guard let match = label.firstMatch(of: pattern) else { return nil }
        guard let hertz = Int(match.1), let shown = Int(match.2), let skipped = Int(match.3), let late = Int(match.4),
              let busy = Int(match.5) else { return nil }
        return (hertz, shown, skipped, late, busy)
    }

    @MainActor
    func test99Metrics() throws {
        try XCTSkipIf(Self.variant.isEmpty, "Runs through Scripts/screenshot-tour.sh")
        let attachment = XCTAttachment(string: Self.metrics.joined(separator: "\n"))
        attachment.name = Self.pose.isEmpty ? "\(Self.variant)-metrics" : "\(Self.variant)-\(Self.pose)-metrics"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
