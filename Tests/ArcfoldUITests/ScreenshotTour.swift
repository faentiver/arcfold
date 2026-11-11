import XCTest

/// Screenshots of every state of the interface for the acceptance of ADR 0007,
/// one launch per state, so no state depends on the one before. Run by
/// `Scripts/screenshot-tour.sh` once per variant (light, dark, contrast,
/// large), which sets the appearance of the Simulator and exports the
/// attachments. Each screenshot is named `<variant>-<nn>-<state>`; the
/// measurements go into `<variant>-metrics`.
///
/// In its pose part the script sets each real pose of the Duo with the
/// private posture tool outside the repository and runs the states of the
/// whole app in it, once per variant: the game (30 and 31, with the pause
/// sheet), the library (32), the menu (33), the search (34), the licenses
/// (35), a long notice with the status chip (36) and the failure view (37),
/// and 12 sideways; in light and dark also the game without the debug
/// overlay (38), the pictures for the documents. The pose comes as
/// `ARCFOLD_TOUR_POSE`. Closed, upright and sideways, it runs the DS a second
/// time in the slim case (`ARCFOLD_TOUR_LARGER_SCREENS=1`, which launches the
/// game with `-LargerScreens YES`); its pictures and measurements carry the
/// pose with `-slim`. Every measurement of the variants that makes sense in
/// a pose is taken there too: the edge of the large title, the margins and
/// the height of the sheet, the keys of the console, the accent buttons, and
/// that the notices and the menu button leave the keys free.
///
/// The keys are measured as the console draws them (`ConsoleKeys`): the
/// letters and arrows against their cap (3 : 1), the names of Select, Start
/// and the menu button as text against the case (4.5 : 1), and with
/// Increase Contrast the edge of each cap against what lies around it
/// (3 : 1). Glass is left only over the picture: the menu button with a
/// controller where no corner of the case is free, the notices and the chip
/// (pages 14, 15 and 17).
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

    /// The pose part runs the DS in the slim case, for whoever prefers
    /// larger screens (`-LargerScreens YES`).
    static var prefersLargerScreens: Bool {
        ProcessInfo.processInfo.environment["ARCFOLD_TOUR_LARGER_SCREENS"] == "1"
    }

    /// The pose as the names of pictures and measurements carry it.
    static var place: String {
        prefersLargerScreens ? "\(pose)-slim" : pose
    }

    /// The launch arguments every game of the pose part gets.
    static var gameArguments: [String] {
        prefersLargerScreens ? ["-LargerScreens", "YES"] : []
    }

    /// The systems a state of the pose part runs: the slim case is the DS's alone.
    static var systemsInThePose: [(system: String, fileExtension: String)] {
        prefersLargerScreens ? [("ds", "nds")] : [("ds", "nds"), ("gba", "gba")]
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

    /// Skips a state of the pose part outside it; with `forTheSlimCase`
    /// false also in the pass of the slim case, which runs the DS only.
    func onlyInAPose(forTheSlimCase: Bool = true) throws {
        try XCTSkipIf(Self.variant.isEmpty, "Runs through Scripts/screenshot-tour.sh")
        try XCTSkipIf(Self.pose.isEmpty, "Runs in the pose part of Scripts/screenshot-tour.sh")
        try XCTSkipIf(!forTheSlimCase && Self.prefersLargerScreens, "The slim case runs the DS only")
    }

    @MainActor
    func shoot(_ app: XCUIApplication, _ number: Int, _ state: String) {
        keep(app.displayScreenshot(), named: "\(Self.variant)-\(String(format: "%02d", number))-\(state)")
    }

    /// Keeps a screenshot the way the view shows it, upright in every pose,
    /// for pictures that go into the documents. `shoot` keeps the bitmap of
    /// the display, which lies on its side while the Duo is held open like
    /// a book.
    @MainActor
    func shootUpright(_ app: XCUIApplication, _ number: Int, _ state: String) throws {
        let image = try XCTUnwrap(app.displayScreenshot().uprightImage, "The screenshot cannot be drawn upright")
        let attachment = XCTAttachment(image: UIImage(cgImage: image), quality: .original)
        attachment.name = "\(Self.variant)-\(String(format: "%02d", number))-\(state)"
        attachment.lifetime = .keepAlways
        add(attachment)
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

    // MARK: The keys of the console

    /// The keys of a system as the tour measures them: X and Y on the DS,
    /// and the menu button with Select and Start.
    static func keyNames(system: String) -> [String] {
        system == "ds"
            ? ["A", "B", "X", "Y", "L", "R", "Pad", "Select", "Start", "Menu"]
            : ["A", "B", "L", "R", "Pad", "Select", "Start", "Menu"]
    }

    /// The small buttons with their names on the case.
    static let knobs: Set<String> = ["Select", "Start", "Menu"]

    /// A key as the tour measures it: its frame in points of the window,
    /// the share of its real size that the page draws it at (below 1 on a
    /// gallery page scaled down), and whether the frame is what the layout
    /// gives the key (the markers of the gallery, the menu button) or what
    /// the key draws (the keys of a game, whose accessibility frame is the
    /// drawing: a cap with its well around it, a small button with its name).
    struct Key {
        let name: String
        let frame: CGRect
        var unit: CGFloat = 1
        var isCell = true
    }

    /// The keys of the running game where the game draws them: the frame of
    /// each key's accessibility element (`touch-button-<label>`, `touch-pad`,
    /// and `pause` for the menu button, which takes its touches on 44 pt).
    @MainActor
    static func keys(in app: XCUIApplication, system: String) -> [Key] {
        keyNames(system: system).map { name in
            let element = switch name {
            case "Pad": app.descendants(matching: .any)["touch-pad"].firstMatch
            case "Menu": app.buttons["pause"]
            default: app.descendants(matching: .any)["touch-button-\(name)"].firstMatch
            }
            return Key(name: name, frame: element.frame, isCell: name == "Menu" || name == "Pad")
        }
    }

    /// The keys of a row of a gallery page, from its markers
    /// (`gallery-key-<label>-<row>`), whose value is the scale of the panel.
    @MainActor
    static func galleryKeys(in app: XCUIApplication, row: String, names: [String]) -> [Key] {
        names.map { name in
            let marker = app.descendants(matching: .any)["gallery-key-\(name)-\(row)"]
            XCTAssertTrue(marker.waitForExistence(timeout: 5), "No marker for \(name) in \(row)")
            let unit = (marker.value as? String).flatMap(Double.init).map { CGFloat($0) } ?? 1
            return Key(name: name, frame: marker.frame, unit: unit)
        }
    }

    static func pixelRect(_ frame: CGRect, scale: CGFloat) -> CGRect {
        CGRect(x: frame.minX * scale, y: frame.minY * scale, width: frame.width * scale, height: frame.height * scale)
    }

    /// The names of Select, Start and the menu button stand beside them,
    /// in a column, where Select and Start share their left edge.
    static func namesStandBeside(_ keys: [Key]) -> Bool {
        guard let select = keys.first(where: { $0.name == "Select" })?.frame,
              let start = keys.first(where: { $0.name == "Start" })?.frame else { return false }
        return abs(select.minX - start.minX) < 1 && abs(select.midY - start.midY) >= 1
    }

    /// The measures of `ConsoleKnob` and `ConsoleSkin`, in points: the
    /// button, the smaller one in a row too low for it, the space to its
    /// name below or beside it, and the widest name.
    static let knob: CGFloat = 24
    static let smallKnob: CGFloat = 18
    static let nameBelow: CGFloat = 3
    static let nameBeside: CGFloat = 7
    static let widestName: CGFloat = 49
    /// The height of a line of the names, 11.5 pt rounded and semibold, as
    /// the accessibility frames of Select and Start show it: 42 pt for the
    /// well of the button, the button, the space and the name.
    static let nameHeight: CGFloat = 13.8
    /// The well around a small button, which its accessibility frame holds.
    static let knobWell: CGFloat = 2 * 0.6

    /// Where a small button draws its cap and its name inside `key`, as
    /// `ConsoleKnob` lays them out: below, the cap over the name in the
    /// middle of the cell; beside, the cap at the left with the name right
    /// of it, the pair in the middle of a column up to 100 pt wide. The box
    /// of a name below is 52 pt wide, the widest name with a little case.
    static func knobParts(of key: Key, beside: Bool) -> (cap: CGRect, name: CGRect) {
        let u = key.unit
        let cell = key.frame
        if beside {
            // A cell has the pair in its middle; what the button draws
            // begins with the well of its cap.
            let lead = key.isCell ? max(2, (cell.width / u - (knob + nameBeside + widestName)) / 2) : knobWell
            let cap = CGRect(x: cell.minX + lead * u, y: cell.midY - knob / 2 * u, width: knob * u, height: knob * u)
            let name = CGRect(x: cap.maxX + nameBeside * u, y: cell.midY - nameHeight / 2 * u,
                              width: widestName * u, height: nameHeight * u)
            return (cap, name)
        }
        let isLow = key.isCell ? cell.height / u < knob + nameBelow + 11.5 * 1.25
            : cell.height / u < knobWell + knob + nameBelow + nameHeight - 1
        let diameter = isLow ? smallKnob : knob
        let space = isLow ? 1 : nameBelow
        let top = key.isCell ? cell.midY - (diameter + space + nameHeight) / 2 * u : cell.minY + knobWell * u
        let cap = CGRect(x: cell.midX - diameter / 2 * u, y: top, width: diameter * u, height: diameter * u)
        let name = CGRect(x: cell.midX - 26 * u, y: top + (diameter + space) * u, width: 52 * u, height: nameHeight * u)
        return (cap, name)
    }

    /// Where the cross of the direction pad lies in its dish (0.88 of it),
    /// and the share of its height above and below the middle where the end
    /// of an arm runs straight (its corners take 0.3 of the arm's width).
    static func padCross(of dish: CGRect) -> CGRect {
        dish.insetBy(dx: dish.width * 0.06, dy: dish.height * 0.06)
    }

    static let straightArmEnd: CGFloat = 0.06

    /// How far the ring of Differentiate Without Color lies inside the cap
    /// of `key`, in points as drawn: 3 pt times the relief of the key, which
    /// is 0.6 on a small button and 0.5 on L or R lower than 30 pt.
    static func ringInset(of key: Key) -> CGFloat {
        if knobs.contains(key.name) { return 3 * 0.6 }
        if ["L", "R"].contains(key.name), key.frame.height / key.unit < 30 { return 3 * 0.5 }
        return 3
    }

    /// What a key carries and what holds its edge: the letter on its cap,
    /// the up arrow on the pad, the name of a small button on the case; the
    /// cap, the cross, the cap of a small button. In pixels.
    static func parts(of key: Key, beside: Bool, scale: CGFloat) -> (writing: CGRect, edge: CGRect, rows: CGFloat) {
        let frame = pixelRect(key.frame, scale: scale)
        if key.name == "Pad" {
            return (frame, padCross(of: frame), straightArmEnd)
        }
        if knobs.contains(key.name) {
            let parts = knobParts(of: key, beside: beside)
            return (pixelRect(parts.name, scale: scale), pixelRect(parts.cap, scale: scale), 0.15)
        }
        let cap = pixelRect(capFrame(of: key), scale: scale)
        return (cap, cap, 0.15)
    }

    /// The cap of a round key or of L and R. A key of a game reports what
    /// it draws: the cap with the well of 2 pt around it (1 pt on L and R
    /// at the ends of the slim hinge) and the light on the edge of the well
    /// 1 pt below it (`KeyCap`).
    static func capFrame(of key: Key) -> CGRect {
        guard !key.isCell else { return key.frame }
        let well = 2 * (["L", "R"].contains(key.name) && key.frame.height - 5 < 30 ? 0.5 : 1)
        return CGRect(x: key.frame.minX + well, y: key.frame.minY + well,
                      width: key.frame.width - 2 * well, height: key.frame.height - 2 * well - 1)
    }

    /// Measures every key of the console: the letters and the arrows
    /// against their cap (limit 3), the names of the small buttons as text
    /// against the case (limit 4.5), and the edge of each cap against what
    /// lies around it, its well and the case (limit 3 with Increase
    /// Contrast, which promises a border, where the keys have their real
    /// size; a gallery scaled down thins the 1.5 pt border). With Increase
    /// Contrast every key carries the same edge: no key measures less than
    /// half of the strongest key of its kind (face buttons, L and R, small
    /// buttons).
    @MainActor
    func measureKeys(_ keys: [Key], named name: String, in pixels: Pixels, scale: CGFloat, checksEdges: Bool) {
        var labels = "contrast \(name)"
        var edges = "edge \(name)"
        var measured: [(key: String, edge: Double)] = []
        let beside = Self.namesStandBeside(keys)
        for key in keys {
            let parts = Self.parts(of: key, beside: beside, scale: scale)
            let label = switch key.name {
            case "Pad": pixels.padArrowContrast(in: parts.writing)
            case _ where Self.knobs.contains(key.name): pixels.inscriptionContrast(in: parts.writing)
            default: pixels.labelContrast(in: parts.writing, writing: .either)
            }
            let edge = pixels.edgeContrast(in: parts.edge, scale: scale * key.unit, rows: parts.rows)
            measured.append((key.name, edge))
            labels += " \(key.name) \(Self.format(label))"
            edges += " \(key.name) \(Self.format(edge))"
            XCTAssertGreaterThanOrEqual(label, Self.knobs.contains(key.name) ? 4.5 : 3, "label of \(key.name), \(name)")
            if checksEdges, Self.variant == "contrast" {
                XCTAssertGreaterThanOrEqual(edge, 3, "edge of \(key.name), \(name)")
            }
        }
        // Keys of one kind among themselves, which stand in the same
        // surroundings: the face buttons in their wells in the case, L and
        // R in the case or at the ends of a hinge between dark bezels, the
        // small buttons in shallow wells with the case around them.
        if checksEdges, Self.variant == "contrast" {
            let kinds: [Set<String>] = [["A", "B", "X", "Y"], ["L", "R"], Self.knobs]
            for group in kinds.map({ kind in measured.filter { kind.contains($0.key) } }) {
                guard let strongest = group.map(\.edge).max() else { continue }
                for (key, edge) in group {
                    XCTAssertGreaterThanOrEqual(edge, strongest / 2,
                                                "the edge of \(key) is lighter than that of its neighbours, \(name)")
                }
            }
        }
        record(labels)
        record(edges)
        record("frames \(name)" + keys.map { " \($0.name) \(Self.format($0.frame.width))x\(Self.format($0.frame.height))" }.joined())
    }

    /// The menu button is a cell of the row or the column of Select and
    /// Start and takes touches on at least 44 pt each way: in a row its cell
    /// spans Select and Start from top to bottom and is at most 60 pt wide,
    /// in a column they begin in it and it is at most 100 pt wide. Select
    /// and Start report what they draw, the button with its name; the menu
    /// button its cell.
    @MainActor
    func checkTheMenuCell(in app: XCUIApplication, named name: String) {
        let pause = app.buttons["pause"].frame
        let select = app.descendants(matching: .any)["touch-button-Select"].firstMatch.frame
        let start = app.descendants(matching: .any)["touch-button-Start"].firstMatch.frame
        let inColumn = abs(select.minX - start.minX) < 1 && abs(select.midY - start.midY) >= 1
        record("\(name): menu \(pause) in the \(inColumn ? "column" : "row") of Select \(select) and Start \(start)")
        XCTAssertGreaterThanOrEqual(min(pause.width, pause.height), 44 - 0.01, "\(name): the menu button \(pause) is below 44 pt")
        // In a column, Select and Start begin in the left half of the cell
        // (their names may reach a point beyond it); in a row they lie
        // within its height.
        let spans = inColumn
            ? [select, start].allSatisfy { pause.minX <= $0.minX + 0.5 && $0.minX <= pause.midX }
            : [select, start].allSatisfy { pause.minY <= $0.minY + 0.5 && $0.maxY <= pause.maxY + 0.5 }
        XCTAssertTrue(spans, "\(name): the menu button \(pause) is no cell of the \(inColumn ? "column" : "row") of \(select) and \(start)")
        XCTAssertLessThanOrEqual(pause.width, inColumn ? 100.5 : 60.5, "\(name): the menu button is wider than its cell")
    }

    /// Select, Start and the menu button keep 24 pt from the pad and the
    /// face buttons in every direction (ADR 0006).
    @MainActor
    func checkTheMenuKeepsClear(of keys: [Key], named name: String) {
        func distance(_ a: CGRect, _ b: CGRect) -> CGFloat {
            hypot(max(0, a.minX - b.maxX, b.minX - a.maxX), max(0, a.minY - b.maxY, b.minY - a.maxY))
        }
        let menu = keys.filter { Self.knobs.contains($0.name) }
        let others = keys.filter { ["Pad", "A", "B", "X", "Y"].contains($0.name) }
        var closest: (CGFloat, String) = (.infinity, "–")
        for part in menu {
            for other in others {
                let gap = distance(part.frame, other.frame)
                if gap < closest.0 { closest = (gap, "\(part.name)–\(other.name)") }
                XCTAssertGreaterThanOrEqual(gap, 24 - 0.5, "\(name): \(part.name) only \(gap) pt from \(other.name)")
            }
        }
        record("\(name): menu to pad and face buttons at least \(Self.format(closest.0)) pt (\(closest.1))")
    }

    /// The text contrast of a prominent button on the accent, in pixels.
    @MainActor
    func measureAccentButton(_ button: XCUIElement, named name: String, in app: XCUIApplication) throws {
        let (pixels, scale) = try pixels(of: app)
        let contrast = Self.contrast(of: button.frame, in: pixels, scale: scale)
        record("accent \(name) \(Self.format(contrast))")
        XCTAssertGreaterThanOrEqual(contrast, 4.5, "white on the accent of \(name)")
    }

    /// The pause sheet is as high as its content: no more than the margin
    /// of the safe area lies below Quit Game (34 pt on the Duo). Less than
    /// that, or Quit Game below the sheet, means larger text makes the
    /// content scroll.
    @MainActor
    func measureTheSheetBelowQuit(in app: XCUIApplication, named name: String) {
        let sheet = app.descendants(matching: .any)["pause-menu"].firstMatch.frame
        let quit = app.buttons["quit"].frame
        let below = sheet.maxY - quit.maxY
        record("\(name): sheet height \(Self.format(sheet.height)), below Quit Game \(Self.format(below))")
        XCTAssertLessThanOrEqual(below, 40, "\(name): the sheet \(sheet) is higher than its content, Quit Game \(quit)")
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
        // The menu button is a small button of the row below the picture.
        checkTheMenuCell(in: app, named: "game upright")
        // The keys in the case at full size, where the game shows them.
        let (pixels, scale) = try pixels(of: app)
        measureKeys(Self.keys(in: app, system: "gba"), named: "game-upright", in: pixels, scale: scale, checksEdges: true)
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
        measureTheSheetBelowQuit(in: app, named: "sheet upright")
        try measureAccentButton(resume, named: "resume", in: app)
        shoot(app, 10, "pause-menu")
    }

    /// The gallery page with the game in the geometry of the closed Duo
    /// sideways, turned by 90 degrees, so that one page shows every part and
    /// overlay at once: the picture 5 times in the middle, pad and face
    /// buttons in the grips beside it, L and R above them, the row with the
    /// menu button below the picture. The real game sideways comes in the
    /// pose part (states 30 and 31, `closed-landscape`).
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
        try onlyInAPose(forTheSlimCase: false)
        try XCTSkipUnless(Self.pose == "closed-landscape", "Runs in the pose closed-landscape")
        let app = XCUIApplication()
        try launchTheSelftest(app)
        let window = app.gameWindow.frame
        try XCTSkipUnless(window.width > window.height, "The window does not turn sideways on this device")
        let pause = app.buttons["pause"]
        checkTheMenuCell(in: app, named: "pause sideways")
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
        measureTheSheetBelowQuit(in: app, named: "sheet sideways")
        try measureAccentButton(resume, named: "resume-sideways", in: app)
        shoot(app, 12, "pause-landscape")
    }

    // MARK: Gallery of the controls

    /// The keys of the closed GBA in the case at rest and pressed. The
    /// panels are scaled down; the edges are recorded, page 08 checks them.
    @MainActor
    func test13TouchUprightStates() throws {
        try only("light", "contrast")
        let app = launchGallery("touch-upright")
        let (pixels, scale) = try pixels(of: app)
        for row in ["rest", "a-up"] {
            let keys = Self.galleryKeys(in: app, row: row, names: Self.keyNames(system: "gba"))
            measureKeys(keys, named: "case-\(row)", in: pixels, scale: scale, checksEdges: false)
        }
        shoot(app, 13, "touch-upright-states")
    }

    /// What is left in glass over the picture: the menu button of the GBA
    /// sideways with a controller, where no corner of the case is free,
    /// over white, the test pattern and black, with the contrast of its
    /// symbol against the plate. No pose of the Duo puts a key over the
    /// picture; sideways the closed Duo keeps every key in the grips beside
    /// it (state 31, `closed-landscape`). The pressed look of the button is
    /// the system's interactive glass and is not drawn here.
    @MainActor
    func test14GlassOverThePicture() throws {
        try only("light", "contrast")
        let app = launchGallery("glass-over-picture")
        shoot(app, 14, "glass-over-picture")
        let (pixels, scale) = try pixels(of: app)
        var line = "contrast glass menu"
        var edges = "edge glass menu"
        for backdrop in ["white", "pattern", "black"] {
            let marker = app.descendants(matching: .any)["gallery-key-Menu-\(backdrop)"]
            XCTAssertTrue(marker.waitForExistence(timeout: 5), "No marker for the menu button over \(backdrop)")
            let circle = Self.pixelRect(Self.circle(in: marker.frame), scale: scale)
            let contrast = pixels.labelContrast(in: circle)
            line += " \(backdrop) \(Self.format(contrast))"
            edges += " \(backdrop) \(Self.format(pixels.edgeContrast(in: circle, scale: scale)))"
            if backdrop != "black" {
                XCTAssertGreaterThanOrEqual(contrast, 3, "the menu button over \(backdrop)")
            }
        }
        record(line)
        record(edges)
    }

    /// The circle a glass button draws in `frame`.
    static func circle(in frame: CGRect) -> CGRect {
        let side = min(frame.width, frame.height)
        return CGRect(x: frame.midX - side / 2, y: frame.midY - side / 2, width: side, height: side)
    }

    /// The same page flat (`-ArcfoldControlSurface flat`), the look while
    /// the system prefers reduced resource usage: the same plate without
    /// the glass, so the symbol keeps its contrast over a light picture.
    @MainActor
    func test15GlassFlat() throws {
        try only("light")
        let app = launchGallery("glass-over-picture", ["-ArcfoldControlSurface", "flat"])
        shoot(app, 15, "glass-flat")
        let (pixels, scale) = try pixels(of: app)
        var line = "contrast flat menu"
        for backdrop in ["white", "pattern", "black"] {
            let marker = app.descendants(matching: .any)["gallery-key-Menu-\(backdrop)"]
            XCTAssertTrue(marker.waitForExistence(timeout: 5), "No marker for the menu button over \(backdrop)")
            let contrast = pixels.labelContrast(in: Self.pixelRect(Self.circle(in: marker.frame), scale: scale))
            line += " \(backdrop) \(Self.format(contrast))"
            if backdrop != "black" {
                XCTAssertGreaterThanOrEqual(contrast, 3, "the flat menu button over \(backdrop)")
            }
        }
        record(line)
    }

    /// The DS in the tabletop pose as the Simulator measures it, below the
    /// fold: the touch screen with the keys beside and below it, A, Up and
    /// X pressed.
    @MainActor
    func test16TouchInner() throws {
        try only("light", "contrast")
        let app = launchGallery("touch-inner")
        let (pixels, scale) = try pixels(of: app)
        measureKeys(Self.galleryKeys(in: app, row: "inner", names: Self.keyNames(system: "ds")), named: "case-inner",
                    in: pixels, scale: scale, checksEdges: false)
        shoot(app, 16, "touch-inner")
    }

    /// The notice and the chip where the game places them upright, over
    /// white and the test pattern. With large text the notice shows its whole
    /// text and grows upwards inside the picture area.
    @MainActor
    func test17Notices() throws {
        try only("light", "contrast", "large")
        let app = launchGallery("notices")
        // A notice is one element as large as its glass (`status-notice`);
        // the text inside it reads the same words.
        let notices = app.staticTexts.matching(identifier: "status-notice")
            .matching(NSPredicate(format: "label BEGINSWITH 'Another game is already running'"))
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

    /// Pressed with Differentiate Without Color: a ring inside the cap of
    /// each pressed key, 3 pt in on a key, less on a small button and on L
    /// and R at the ends of the slim hinge (`KeyCap`); measured where it
    /// lies, on the cap of a small button too, not on its cell. The closed
    /// GBA, the closed DS with its hinge and the slim case.
    @MainActor
    func test19TouchDifferentiate() throws {
        try only("light", "contrast")
        let app = launchGallery("touch-differentiate")
        let (pixels, scale) = try pixels(of: app)
        let ds = ["A", "B", "X", "Y", "L", "R", "Select", "Start"]
        for (row, names) in [("differentiate-upright", ["A", "Start"]), ("differentiate-ds", ds), ("differentiate-slim", ds)] {
            var line = "ring \(row)"
            let keys = Self.galleryKeys(in: app, row: row, names: names + ["Select", "Start"].filter { !names.contains($0) })
            let beside = Self.namesStandBeside(keys)
            for key in keys where names.contains(key.name) {
                let cap = Self.knobs.contains(key.name) ? Self.knobParts(of: key, beside: beside).cap : key.frame
                let contrast = pixels.ringContrast(in: Self.pixelRect(cap, scale: scale), scale: scale * key.unit,
                                                   inset: Self.ringInset(of: key))
                line += " \(key.name) \(Self.format(contrast))"
                XCTAssertGreaterThanOrEqual(contrast, 3, "ring of \(key.name), \(row)")
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

    /// The closed DS in both cases: with its own hinge between the screens
    /// (the vertical bar on top) and slim (`-LargerScreens YES`, the bar at
    /// the side), every key with X, Y and the menu button. The panels are
    /// scaled down; the edges are recorded, the pose part checks them.
    @MainActor
    func test21TouchClosedDS() throws {
        try only("light", "contrast")
        let app = launchGallery("touch-closed-ds")
        let (pixels, scale) = try pixels(of: app)
        for row in ["hinge", "slim"] {
            measureKeys(Self.galleryKeys(in: app, row: row, names: Self.keyNames(system: "ds")), named: "case-ds-\(row)",
                        in: pixels, scale: scale, checksEdges: false)
        }
        shoot(app, 21, "touch-closed-ds")
    }

    // MARK: Real poses

    @MainActor
    func test30DSInThePose() throws {
        try shootTheGame(fileExtension: "nds", system: "ds", number: 30)
    }

    @MainActor
    func test31GBAInThePose() throws {
        try onlyInAPose(forTheSlimCase: false)
        try shootTheGame(fileExtension: "gba", system: "gba", number: 31)
    }

    /// A game in the real pose the script set: the layout the overlay
    /// reports, the menu button as a cell of its row or column, the keys and
    /// the menu button against each other, the keys of the console, a
    /// screenshot of the display it runs on, then the pause sheet out of the
    /// menu button with its margins and a screenshot of it, and Resume.
    @MainActor
    private func shootTheGame(fileExtension: String, system: String, number: Int) throws {
        try onlyInAPose()
        let app = XCUIApplication()
        app.launchArguments = ["-ArcfoldAutorun", try fixturePath("selftest", fileExtension)] + Self.gameArguments
        app.launch()
        let overlay = overlayWithLayout(in: app)
        XCTAssertTrue(waitUntil(overlay, framesBeyond: 120), "The game does not run")
        Thread.sleep(forTimeInterval: 1)
        let values = OverlayValues(overlay)
        let place = Self.place
        let expected = Self.expectedPosture[Self.pose]
        if let expected {
            XCTAssertEqual(values.posture, expected, "\(place): \(values.pairs)")
        }
        record("pose \(place) \(system): posture \(values.posture ?? "–") view \(values.pairs["view"] ?? "–") "
            + "safe \(values.pairs["safe"] ?? "–") fold \(values.pairs["fold"] ?? "–") screens \(values.pairs["screens"] ?? "–")")
        let pause = app.buttons["pause"]
        XCTAssertTrue(pause.waitForExistence(timeout: 5))
        checkTheMenuCell(in: app, named: "pose \(place) \(system)")
        XCTAssertGreaterThanOrEqual(pause.frame.minY, 64, "the menu button lies in the top edge guard")
        let keys = Self.keys(in: app, system: system)
        let overlapping = keys.filter { $0.name != "Menu" && $0.frame.intersects(pause.frame.insetBy(dx: 4, dy: 4)) }.map(\.name)
        record("pose \(place) \(system): menu \(pause.frame) keys under it \(overlapping.isEmpty ? "none" : overlapping.joined(separator: ","))")
        XCTAssertTrue(overlapping.isEmpty, "\(place) \(system): the menu button lies on \(overlapping)")
        checkTheMenuKeepsClear(of: keys, named: "pose \(place) \(system)")
        let (pixels, scale) = try pixels(of: app)
        measureKeys(keys, named: "\(place)-\(system)", in: pixels, scale: scale, checksEdges: true)
        shoot(app, number, "\(place)-\(system)")

        pause.tap()
        let resume = app.buttons["resume"]
        XCTAssertTrue(resume.waitForExistence(timeout: 5), "\(place): the pause sheet did not open")
        Thread.sleep(forTimeInterval: 1.5)
        let sheet = app.descendants(matching: .any)["pause-menu"].firstMatch
        record("pose \(place) \(system): sheet \(sheet.frame)")
        // Along the axis the button is long in, the content sits in the middle of the sheet.
        let margins = resume.frame.width >= resume.frame.height
            ? (resume.frame.minX - sheet.frame.minX, sheet.frame.maxX - resume.frame.maxX)
            : (resume.frame.minY - sheet.frame.minY, sheet.frame.maxY - resume.frame.maxY)
        record("pose \(place) \(system): sheet margins \(Self.format(margins.0)) \(Self.format(margins.1))")
        XCTAssertEqual(margins.0, margins.1, accuracy: 2, "\(place) \(system): the content of the sheet sits off centre")
        measureTheSheetBelowQuit(in: app, named: "pose \(place) \(system)")
        try measureAccentButton(resume, named: "resume-\(place)-\(system)", in: app)
        shoot(app, number, "\(place)-\(system)-sheet")
        resume.tap()
        XCTAssertTrue(waitUntilGone(resume), "\(place): the sheet stayed")
        XCTAssertTrue(waitUntil(overlay, hasValue: "paused=false;"), "\(place): Resume did not resume")
    }

    // MARK: Real poses: the rest of the app

    /// The library in the pose: the grid begins at the edge of the large
    /// title, and the first row with its names stands in the window.
    @MainActor
    func test32LibraryInThePose() throws {
        try onlyInAPose(forTheSlimCase: false)
        let app = launchGallery("library-shelf")
        XCTAssertTrue(app.buttons["game-gba-Arc-Light"].waitForExistence(timeout: 10))
        let window = app.gameWindow.frame
        let tile = app.buttons["game-gba-Arc-Light"].frame
        let title = app.navigationBars["Library"].staticTexts["Library"]
        record("pose \(Self.pose) library: columns \(columns(in: app)) window \(window) first tile \(tile)")
        XCTAssertTrue(window.contains(tile), "\(Self.pose): the first tile \(tile) leaves the window \(window)")
        if title.exists {
            record("pose \(Self.pose) library: margin tile \(tile.minX) title \(title.frame.minX)")
            XCTAssertEqual(tile.minX, title.frame.minX, accuracy: 1.5, "\(Self.pose): the grid does not line up with the title")
        } else {
            record("pose \(Self.pose) library: title not found")
        }
        shoot(app, 32, "\(Self.pose)-library")
    }

    @MainActor
    func test33MenuInThePose() throws {
        try onlyInAPose(forTheSlimCase: false)
        let app = XCUIApplication()
        app.launchArguments = ["-ArcfoldImport", try selftestPath()]
        app.launch()
        let more = app.buttons["info-menu"]
        XCTAssertTrue(more.waitForExistence(timeout: 20))
        more.tap()
        XCTAssertTrue(app.buttons["Licenses"].waitForExistence(timeout: 5), "\(Self.pose): the menu did not open")
        Thread.sleep(forTimeInterval: 1)
        shoot(app, 33, "\(Self.pose)-menu")
    }

    @MainActor
    func test34SearchInThePose() throws {
        try onlyInAPose(forTheSlimCase: false)
        let app = XCUIApplication()
        app.launchArguments = ["-ArcfoldImport", try selftestPath()]
        app.launch()
        XCTAssertTrue(app.buttons["game-gba-selftest"].waitForExistence(timeout: 20))
        let search = app.buttons["Search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5), "\(Self.pose): the search field did not open")
        field.typeText("self")
        XCTAssertTrue(app.buttons["game-gba-selftest"].waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 1)
        shoot(app, 34, "\(Self.pose)-search")
    }

    @MainActor
    func test35LicensesInThePose() throws {
        try onlyInAPose(forTheSlimCase: false)
        let app = XCUIApplication()
        app.launch()
        let more = app.buttons["info-menu"]
        XCTAssertTrue(more.waitForExistence(timeout: 20))
        more.tap()
        app.buttons["Licenses"].tap()
        XCTAssertTrue(app.navigationBars["Licenses"].waitForExistence(timeout: 5), "\(Self.pose): the licenses did not open")
        Thread.sleep(forTimeInterval: 1)
        shoot(app, 35, "\(Self.pose)-licenses")
    }

    /// A real long notice (a failed battery save, through the session's own
    /// path) with the status chip over a running game: the chip and the
    /// notice stand in the window, do not overlap and cover no key and not
    /// the menu button, and the card of the debug overlay ends above or
    /// beside them.
    @MainActor
    func test36NoticesInThePose() throws {
        try onlyInAPose()
        let place = Self.place
        for (system, fileExtension) in Self.systemsInThePose {
            let app = XCUIApplication()
            app.launchArguments = ["-ArcfoldAutorun", try fixturePath("selftest", fileExtension)] + Self.gameArguments
            app.launch()
            let overlay = overlayWithLayout(in: app)
            XCTAssertTrue(waitUntil(overlay, framesBeyond: 120), "The game does not run")
            postDebugNotification("chip.show")
            // The chip and the notice as the elements that have the shape
            // of their glass, not the texts inside them.
            let chip = app.staticTexts.matching(identifier: "status-chip")
                .matching(NSPredicate(format: "label BEGINSWITH 'The audio engine could not start'")).firstMatch
            XCTAssertTrue(chip.waitForExistence(timeout: 5), "\(place) \(system): no chip")
            postDebugNotification("notice.long")
            let notice = app.staticTexts.matching(identifier: "status-notice")
                .matching(NSPredicate(format: "label BEGINSWITH 'The save could not be written'")).firstMatch
            XCTAssertTrue(notice.waitForExistence(timeout: 5), "\(place) \(system): no notice")
            // The chip moves up for the notice; read both once they rest.
            // A notice stays four seconds: each frame is read once, and
            // the picture is taken before the keys are read, so that a
            // slow run finds the notice still there.
            Thread.sleep(forTimeInterval: 0.6)
            let chipFrame = chip.frame
            let noticeFrame = notice.frame
            let window = app.gameWindow.frame
            let card = overlay.exists ? overlay.frame : .zero
            shoot(app, 36, "\(place)-\(system)-notice")
            record("pose \(place) \(system): chip \(chipFrame) notice \(noticeFrame) debug overlay \(card)")
            XCTAssertFalse(card.insetBy(dx: -2, dy: -2).intersects(chipFrame) || card.insetBy(dx: -2, dy: -2).intersects(noticeFrame),
                           "\(place) \(system): the debug overlay \(card) lies under the chip or the notice")
            XCTAssertFalse(chipFrame.isEmpty || noticeFrame.isEmpty, "\(place) \(system): the notice went away too early")
            XCTAssertTrue(window.insetBy(dx: -1, dy: -1).contains(chipFrame) && window.insetBy(dx: -1, dy: -1).contains(noticeFrame),
                          "\(place) \(system): the chip or the notice leaves the window \(window)")
            XCTAssertFalse(chipFrame.insetBy(dx: -2, dy: -2).intersects(noticeFrame.insetBy(dx: -2, dy: -2)),
                           "\(place) \(system): the chip and the notice overlap")
            // Every key with X, Y and the menu button.
            let under = Self.keys(in: app, system: system).filter { $0.frame.intersects(chipFrame) || $0.frame.intersects(noticeFrame) }
                .map(\.name)
            XCTAssertTrue(under.isEmpty, "\(place) \(system): the chip or the notice covers \(under)")
            app.terminate()
        }
    }

    /// The failure view of a game that could not start, in the pose.
    @MainActor
    func test37FailureInThePose() throws {
        try onlyInAPose()
        let place = Self.place
        for (system, fileExtension) in Self.systemsInThePose {
            let app = XCUIApplication()
            app.launchArguments = ["-ArcfoldAutorun", try fixturePath("selftest", fileExtension), "-ArcfoldFailStart", "YES"]
                + Self.gameArguments
            app.launch()
            let close = app.buttons["Close"]
            XCTAssertTrue(close.waitForExistence(timeout: 30), "\(place) \(system): no failure view")
            let window = app.gameWindow.frame
            XCTAssertTrue(window.insetBy(dx: -1, dy: -1).contains(close.frame), "\(place) \(system): Close leaves the window")
            try measureAccentButton(close, named: "close-\(place)-\(system)", in: app)
            shoot(app, 37, "\(place)-\(system)-failure")
            app.terminate()
        }
    }

    /// The running games as a player sees them, without the debug overlay
    /// that every other picture of a game shows: DS and GBA in the pose, in
    /// light and dark, named `<variant>-38-<pose>-<system>-clean` (the slim
    /// case `<variant>-38-<pose>-slim-ds-clean`) and upright
    /// in every pose, for the documents. The overlay is hidden the way the
    /// pose tests hide it (`DebugRemote`), once the game has run its first
    /// frames, and comes back afterwards.
    @MainActor
    func test38CleanGamesInThePose() throws {
        try onlyInAPose()
        try XCTSkipUnless(["light", "dark"].contains(Self.variant), "The clean pictures are taken in light and dark")
        let place = Self.place
        for (system, fileExtension) in Self.systemsInThePose {
            let app = XCUIApplication()
            app.launchArguments = ["-ArcfoldAutorun", try fixturePath("selftest", fileExtension)] + Self.gameArguments
            app.launch()
            let overlay = overlayWithLayout(in: app)
            XCTAssertTrue(waitUntil(overlay, framesBeyond: 120), "\(place) \(system): the game does not run")
            XCTAssertTrue(app.buttons["pause"].waitForExistence(timeout: 5), "\(place) \(system): no pause button")
            try withOverlayHidden(in: app) {
                XCTAssertFalse(overlay.exists, "\(place) \(system): the debug overlay is still shown")
                try shootUpright(app, 38, "\(place)-\(system)-clean")
            }
            app.terminate()
        }
    }

    /// The posture each real pose must give (ADR 0006, section 7).
    static let expectedPosture = [
        "closed": "single", "closed-landscape": "single", "open": "flat", "book": "flat",
        "tabletop": "tabletop", "flat-upright": "flat",
    ]

    @MainActor
    func test99Metrics() throws {
        try XCTSkipIf(Self.variant.isEmpty, "Runs through Scripts/screenshot-tour.sh")
        let attachment = XCTAttachment(string: Self.metrics.joined(separator: "\n"))
        attachment.name = Self.pose.isEmpty ? "\(Self.variant)-metrics" : "\(Self.variant)-\(Self.place)-metrics"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
