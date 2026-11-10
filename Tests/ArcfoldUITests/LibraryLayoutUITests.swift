import XCTest

/// The library in the window the device gives it, whatever the pose: the
/// grid begins at the large title, a tile keeps its name in view at every
/// text size, and nothing lies on a fold that divides the window from top to
/// bottom or closer to it than the system's margin. The tests take the pose
/// as it is, so they run closed in a normal test run and again in every real
/// pose of the Duo.
///
/// A real fold reaches a test only from outside: `ARCFOLD_LIBRARY_FOLD`
/// (through `TEST_RUNNER_ARCFOLD_LIBRARY_FOLD`) names its left and right edge
/// in points of the window, for example `455.5,495.5` for the book in the
/// Simulator. Without it the tests of the fold use the artificial fold of
/// debug builds (`-ArcfoldFoldOverride book`), 16 pt down the middle.
final class LibraryLayoutUITests: XCTestCase {
    /// Text sizes from the standard one to the largest accessibility size.
    private static let textSizes = [
        "UICTContentSizeCategoryL", "UICTContentSizeCategoryXXXL", "UICTContentSizeCategoryAccessibilityM",
        "UICTContentSizeCategoryAccessibilityL", "UICTContentSizeCategoryAccessibilityXXXL",
    ]

    override func setUp() {
        continueAfterFailure = true
    }

    /// The library with the eight games of the gallery.
    @MainActor
    private func launchLibraryShelf(textSize: String = "UICTContentSizeCategoryL", arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ArcfoldGallery", "library-shelf", "-UIPreferredContentSizeCategoryName", textSize] + arguments
        app.launch()
        XCTAssertTrue(app.buttons["game-gba-Arc-Light"].waitForExistence(timeout: 15), "The library shows no games (\(textSize))")
        return app
    }

    /// The tiles on screen, in reading order.
    @MainActor
    private func libraryTiles(in app: XCUIApplication) -> [CGRect] {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'game-'")).allElementsBoundByIndex
            .map(\.frame)
            .filter { !$0.isEmpty }
            .sorted { ($0.minY, $0.minX) < ($1.minY, $1.minX) }
    }

    /// The fold named from outside, or nil.
    private static var namedFold: ClosedRange<CGFloat>? {
        guard let text = ProcessInfo.processInfo.environment["ARCFOLD_LIBRARY_FOLD"] else { return nil }
        let edges = text.split(separator: ",").compactMap { Double($0) }
        guard edges.count == 2, edges[0] < edges[1] else { return nil }
        return CGFloat(edges[0])...CGFloat(edges[1])
    }

    private func note(_ text: String) {
        print("LibraryLayout: \(text)")
    }

    @MainActor
    func testTheGridBeginsAtTheLargeTitle() {
        for textSize in ["UICTContentSizeCategoryL", "UICTContentSizeCategoryAccessibilityL"] {
            let app = launchLibraryShelf(textSize: textSize)
            let title = app.navigationBars["Library"].staticTexts["Library"]
            XCTAssertTrue(title.waitForExistence(timeout: 5), "The library shows no title (\(textSize))")
            let tile = app.buttons["game-gba-Arc-Light"].frame
            let window = app.gameWindow.frame
            note("title \(title.frame.minX) tile \(tile.minX) window \(window.width) x \(window.height) \(textSize)")
            XCTAssertEqual(tile.minX, title.frame.minX, accuracy: 1,
                           "The grid does not begin at the large title (\(textSize), window \(window.size))")
            app.terminate()
        }
    }

    @MainActor
    func testATileKeepsItsNameInViewAtEveryTextSize() {
        for textSize in Self.textSizes {
            let app = launchLibraryShelf(textSize: textSize)
            let window = app.gameWindow.frame
            let tiles = libraryTiles(in: app)
            guard let first = tiles.first else {
                XCTFail("No tile (\(textSize))")
                continue
            }
            // A tile is its artwork, its name and its system; the first row
            // ends above the lower edge of the window.
            let row = tiles.filter { abs($0.minY - first.minY) < 1 }
            let bottom = row.map(\.maxY).max() ?? 0
            note("first row \(row.count) tiles of \(first.width) x \(first.height), ends at \(bottom) of \(window.height) \(textSize)")
            XCTAssertLessThanOrEqual(bottom, window.maxY,
                                     "The first row ends below the window (\(textSize), window \(window.size))")
            XCTAssertGreaterThanOrEqual(first.minX, window.minX)
            XCTAssertLessThanOrEqual(row.map(\.maxX).max() ?? 0, window.maxX)
            app.terminate()
        }
    }

    /// A name that ends in an ellipsis or breaks inside a word is clipped
    /// text for the system's audit. Sideways on the outer display the grid
    /// once squeezed three tiles into the row at the largest sizes.
    @MainActor
    func testNoNameOfATileIsCutShortAtAnyTextSize() throws {
        for textSize in Self.textSizes {
            let app = launchLibraryShelf(textSize: textSize)
            let window = app.gameWindow.frame
            let tiles = libraryTiles(in: app)
            let names = Set(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'game-gba-'")).allElementsBoundByIndex
                .map { String($0.identifier.dropFirst("game-gba-".count)) })
            XCTAssertFalse(names.isEmpty, "No tile (\(textSize))")
            note("names: \(Set(tiles.map(\.minX)).count) columns of \(tiles.first?.width ?? 0) pt, "
                + "window \(window.width) x \(window.height) \(textSize)")
            try app.performAccessibilityAudit(for: .textClipped) { issue in
                let label = issue.element?.label ?? ""
                // Only the names of the tiles count here; the audit of the
                // whole screen is testTheLibraryPassesTheAccessibilityAuditInItsWindow.
                let isName = names.contains(label)
                self.note("names\(isName ? "" : " (not a name)"): \(issue.compactDescription) \(label) "
                    + "\(issue.element?.frame ?? .zero) \(textSize)")
                return !isName
            }
            app.terminate()
        }
    }

    /// The fold the app lays out for: the one named from outside, or the
    /// artificial one down the middle of the window.
    private func fold(in window: CGRect) -> ClosedRange<CGFloat> {
        Self.namedFold ?? (window.midX - 8)...(window.midX + 8)
    }

    /// With a fold named from outside the app measures it itself.
    private static var foldArguments: [String] {
        namedFold == nil ? ["-ArcfoldFoldOverride", "book"] : []
    }

    /// The distance everything keeps from a fold that divides the window:
    /// the system's margin of the Duo.
    private static let foldMargin: CGFloat = 20

    @MainActor
    func testNoTileLiesOnAFoldThatDividesTheWindow() {
        for textSize in ["UICTContentSizeCategoryL", "UICTContentSizeCategoryAccessibilityL"] {
            let app = launchLibraryShelf(textSize: textSize, arguments: Self.foldArguments)
            let window = app.gameWindow.frame
            let fold = fold(in: window)
            let tiles = libraryTiles(in: app)
            // On neither side a tile sticks to the fold.
            let before = tiles.filter { $0.maxX <= fold.lowerBound - Self.foldMargin + 0.5 }
            let after = tiles.filter { $0.minX >= fold.upperBound + Self.foldMargin - 0.5 }
            note("fold \(fold.lowerBound)-\(fold.upperBound): \(before.count) tiles before, \(after.count) after, "
                + "edges \(Set(tiles.map(\.minX)).sorted()) width \(tiles.first?.width ?? 0), "
                + "\(fold.lowerBound - (before.map(\.maxX).max() ?? 0)) pt before the fold, "
                + "\((after.map(\.minX).min() ?? 0) - fold.upperBound) pt behind it \(textSize)")
            XCTAssertEqual(before.count + after.count, tiles.count,
                           "A tile lies on the fold \(fold) or at its edge (\(textSize), window \(window.size))")
            XCTAssertFalse(before.isEmpty, "No tile before the fold (\(textSize))")
            XCTAssertFalse(after.isEmpty, "No tile after the fold (\(textSize))")
            // The second page begins the margin behind the fold, with tiles
            // as wide as those of the first.
            if let second = after.map(\.minX).min(), let width = tiles.first?.width {
                XCTAssertEqual(second, fold.upperBound + Self.foldMargin, accuracy: 1,
                               "The second page does not begin the margin behind the fold (\(textSize))")
                XCTAssertTrue(tiles.allSatisfy { abs($0.width - width) < 0.5 }, "The tiles differ in width (\(textSize))")
            }
            // The first page still begins at the large title.
            let title = app.navigationBars["Library"].staticTexts["Library"]
            if title.exists, let first = tiles.first {
                XCTAssertEqual(first.minX, title.frame.minX, accuracy: 1)
            }
            app.terminate()
        }
    }

    /// Keeps a picture of the display that shows the app with the test, for
    /// the record. `app.screenshot()` would take the outer display, which is
    /// off while the app runs on the inner one.
    @MainActor
    private func keepLibraryScreenshot(of app: XCUIApplication, named name: String) {
        keep(app.displayScreenshot(), named: name)
    }

    /// Opens Licenses from the More menu and waits for the list.
    @MainActor
    private func openLicenses(in app: XCUIApplication) {
        app.buttons["info-menu"].tap()
        let licenses = app.buttons["Licenses"]
        XCTAssertTrue(licenses.waitForExistence(timeout: 5))
        licenses.tap()
        XCTAssertTrue(app.navigationBars["Licenses"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["GPL-3.0-or-later"].firstMatch.waitForExistence(timeout: 5))
    }

    /// The texts on screen that lie on `fold` or closer to it than the
    /// margin, with their frames.
    @MainActor
    private func textsAtTheFold(_ fold: ClosedRange<CGFloat>, in app: XCUIApplication) -> [String] {
        app.staticTexts.allElementsBoundByIndex
            .filter { $0.exists && !$0.frame.isEmpty }
            .filter { $0.frame.maxX > fold.lowerBound - Self.foldMargin + 0.5 && $0.frame.minX < fold.upperBound + Self.foldMargin - 0.5 }
            .map { "\($0.label) \($0.frame)" }
    }

    @MainActor
    func testTheEmptyLibraryStaysBesideAFold() {
        let app = XCUIApplication()
        app.launchArguments = ["-ArcfoldGallery", "library-empty"] + Self.foldArguments
        app.launch()
        let importGames = app.buttons["Import Games"]
        XCTAssertTrue(importGames.waitForExistence(timeout: 15))
        let fold = fold(in: app.gameWindow.frame)
        note("empty library: button \(importGames.frame), fold \(fold.lowerBound)-\(fold.upperBound)")
        // The glass button and the texts lie on the first page.
        XCTAssertLessThanOrEqual(importGames.frame.maxX, fold.lowerBound - Self.foldMargin + 0.5,
                                 "Import Games lies at or after the fold")
        XCTAssertEqual(textsAtTheFold(fold, in: app), [])
        keepLibraryScreenshot(of: app, named: "library-empty")
    }

    @MainActor
    func testASearchWithoutResultsStaysBesideAFold() {
        let app = launchLibraryShelf(arguments: Self.foldArguments)
        let fold = fold(in: app.gameWindow.frame)
        let search = app.buttons["Search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5), "The library shows no search button")
        search.tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("zzz")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'zzz'")).firstMatch.waitForExistence(timeout: 5),
                      "No message for a search without results")
        note("search: field \(field.frame), fold \(fold.lowerBound)-\(fold.upperBound)")
        XCTAssertEqual(textsAtTheFold(fold, in: app), [])
        // The system keeps its search field off a real fold.
        if Self.namedFold != nil {
            XCTAssertTrue(field.frame.maxX <= fold.lowerBound + 0.5 || field.frame.minX >= fold.upperBound - 0.5,
                          "The search field \(field.frame) lies on the fold")
        }
        keepLibraryScreenshot(of: app, named: "library-search-empty")
    }

    @MainActor
    func testCoresStayBesideAFold() {
        let app = launchLibraryShelf(arguments: Self.foldArguments)
        let fold = fold(in: app.gameWindow.frame)

        app.buttons["info-menu"].tap()
        let cores = app.buttons["Cores"]
        XCTAssertTrue(cores.waitForExistence(timeout: 5))
        cores.tap()
        XCTAssertTrue(app.navigationBars["Cores"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["mGBA"].waitForExistence(timeout: 10), "The list of cores is empty")
        XCTAssertEqual(textsAtTheFold(fold, in: app), [])
        // Name and version of a core both lie on the first page, and the
        // rows end the margin before the fold.
        for text in app.cells.staticTexts.allElementsBoundByIndex where text.exists {
            XCTAssertLessThanOrEqual(text.frame.maxX, fold.lowerBound - Self.foldMargin + 0.5, "\(text.label) lies at or after the fold")
        }
        let rows = app.cells.allElementsBoundByIndex.filter(\.exists).map(\.frame)
        note("cores: rows \(rows), fold \(fold.lowerBound)-\(fold.upperBound)")
        XCTAssertFalse(rows.isEmpty, "The list of cores has no rows")
        for row in rows {
            XCTAssertLessThanOrEqual(row.maxX, fold.lowerBound - Self.foldMargin + 0.5, "A row \(row) of the cores lies at the fold")
        }
        keepLibraryScreenshot(of: app, named: "cores")
    }

    /// Licenses in the window as it is: the list of the components. The list
    /// and a text share the window only at a real fold; the artificial one
    /// of debug builds does not reach the system, so that part needs a fold
    /// named from outside.
    @MainActor
    func testLicensesShowTheirListAndAtAFoldATextBesideIt() {
        let app = launchLibraryShelf()
        openLicenses(in: app)
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'mGBA 0.10.5'")).firstMatch
        XCTAssertTrue(row.exists, "The list of licenses has no row for mGBA")
        keepLibraryScreenshot(of: app, named: "licenses")
        guard let fold = Self.namedFold else { return }

        XCTAssertEqual(textsAtTheFold(fold, in: app), [])
        // The list on the first page, the margin before the fold; the text
        // of Arcfold on the second, the margin behind it.
        XCTAssertLessThanOrEqual(row.frame.maxX, fold.lowerBound - Self.foldMargin + 0.5)
        let names = app.staticTexts.matching(identifier: "Arcfold").allElementsBoundByIndex.map(\.frame)
        note("licenses: row \(row.frame), Arcfold at \(names), fold \(fold.lowerBound)-\(fold.upperBound)")
        XCTAssertTrue(names.contains { abs($0.minX - fold.upperBound - Self.foldMargin) <= 1 },
                      "No license text the margin behind the fold")

        // Another component: its text takes the second page.
        row.tap()
        let heading = app.staticTexts.matching(identifier: "mGBA").allElementsBoundByIndex.map(\.frame)
        XCTAssertTrue(heading.contains { abs($0.minX - fold.upperBound - Self.foldMargin) <= 1 },
                      "The text of mGBA does not begin the margin behind the fold")
        XCTAssertEqual(textsAtTheFold(fold, in: app), [])
        keepLibraryScreenshot(of: app, named: "licenses-mgba")
    }

    /// The system's accessibility audit of what the app shows. The system's
    /// secondary labels (the system under a tile, the license under a
    /// component) rate "nearly passed", as in the system's own apps; besides
    /// them only the tiles that leave the window may report.
    @MainActor
    private func auditLibraryScreen(_ app: XCUIApplication, named screen: String) throws {
        try app.performAccessibilityAudit(for: [.contrast, .hitRegion, .sufficientElementDescription, .textClipped, .dynamicType]) { issue in
            // Rows below the first leave the window while the audit enlarges
            // the text, so it rates their Dynamic Type "partially unsupported".
            let allowed = (issue.auditType == .contrast && issue.compactDescription == "Contrast nearly passed"
                && issue.element?.label != "Import Games")
                || (issue.auditType == .dynamicType && issue.compactDescription.contains("partially"))
            self.note("audit \(screen)\(allowed ? " (allowed)" : ""): \(issue.compactDescription) "
                + "\(issue.element?.label ?? "no element") \(issue.element?.frame ?? .zero)")
            return allowed
        }
    }

    /// The audit in the window as it is: the grid at the standard size and
    /// with large text, and Licenses, which at a real fold shows the list
    /// and a text side by side.
    @MainActor
    func testTheLibraryPassesTheAccessibilityAuditInItsWindow() throws {
        for textSize in ["UICTContentSizeCategoryL", "UICTContentSizeCategoryAccessibilityL"] {
            let app = launchLibraryShelf(textSize: textSize)
            try auditLibraryScreen(app, named: "library \(textSize)")
            app.terminate()
        }
        let app = launchLibraryShelf()
        openLicenses(in: app)
        try auditLibraryScreen(app, named: "licenses")
    }
}
