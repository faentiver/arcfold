@testable import Arcfold
import CoreGraphics
import FoldLayout
import SwiftUI
import Testing

/// The columns of the library (`LibraryColumns`) in the windows of the Duo
/// and in every geometry of `LayoutInvariantTests` in FoldLayout, at every
/// text size: the grid begins and ends at the system's margins, its columns
/// are equal and apart, a tile with its name fits into what the window
/// shows at once, and no tile lies on a fold that divides the window.
struct LibraryColumnsTests {
    /// A window as the library finds it: the width of its scroll view inside
    /// the safe area and the system's margins in it.
    struct Window: Sendable, CustomTestStringConvertible {
        let name: String
        let width: CGFloat
        let margins: SystemMargins
        /// The height of the scroll view inside the safe area.
        let visibleHeight: CGFloat
        var testDescription: String { name }

        var space: LibraryColumns.Space {
            LibraryColumns.Space(width: width, margins: margins, visibleHeight: visibleHeight)
        }
    }

    /// Measured in the Simulator (iOS 27.1): beside the bar of the outer
    /// display and of the inner display held like a book the trailing margin
    /// is 0, sideways the leading one, because the inset stands for it.
    static let measured = [
        Window(name: "closed upright, 382 pt beside the bar", width: 382, margins: SystemMargins(leading: 20, trailing: 0),
               visibleHeight: 562),
        Window(name: "closed sideways, 594 of 678 pt", width: 594, margins: SystemMargins(leading: 0, trailing: 20),
               visibleHeight: 350),
        Window(name: "flat upright and tabletop, 669 pt", width: 669, margins: .standard, visibleHeight: 783),
        Window(name: "open and book, 867 of 951 pt", width: 867, margins: SystemMargins(leading: 20, trailing: 0),
               visibleHeight: 553),
    ]

    /// The widths of the Duo's windows without a bar, with margins on both
    /// sides, as high as the lowest window (sideways on the outer display)
    /// and as the highest.
    static let whole = [382, 466, 678, 669, 951].flatMap { width in
        [350, 783].map { height in
            Window(name: "\(width) × \(height) pt", width: CGFloat(width), margins: .standard, visibleHeight: CGFloat(height))
        }
    }

    static let windows = measured + whole

    static let typeSizes = DynamicTypeSize.allCases

    static let margins = [
        SystemMargins.standard, SystemMargins(leading: 20, trailing: 0), SystemMargins(leading: 0, trailing: 20),
        SystemMargins(leading: 16, trailing: 16),
    ]

    /// The rules every grid keeps, whatever the room.
    static func check(_ layout: LibraryColumns, in space: LibraryColumns.Space, _ comment: Comment) {
        let columns = layout.columns
        #expect(!columns.isEmpty, comment)
        guard let first = columns.first, let last = columns.last else { return }
        // The edge of the large title, and the margin on the other side.
        #expect(abs(first.x - space.margins.leading) < 0.01, comment)
        #expect(last.maxX <= space.width - space.margins.trailing + 0.01, comment)
        for column in columns {
            #expect(abs(column.width - first.width) < 0.01, "columns differ in width: \(comment)")
            #expect(column.width > 0, comment)
        }
        for (column, next) in zip(columns, columns.dropFirst()) {
            #expect(next.x - column.maxX >= 8, "columns closer than 8 pt: \(comment)")
        }
        #expect(layout.gridItems.count == columns.count, comment)
        guard let fold = space.fold else { return }
        // Two pages: no tile on the fold, the same columns on each side.
        let before = columns.filter { $0.maxX <= fold.lowerBound + 0.01 }
        let after = columns.filter { $0.x >= fold.upperBound - 0.01 }
        #expect(before.count + after.count == columns.count, "a tile lies on the fold: \(comment)")
        #expect(before.count == after.count, comment)
        // The second page begins at the fold, or a tile distance from the
        // first page when the fold is narrower than that.
        let gap = (after.first?.x ?? 0) - (before.last?.maxX ?? 0)
        #expect(gap >= fold.upperBound - fold.lowerBound - 0.01 && gap >= 14, comment)
        if fold.upperBound - fold.lowerBound >= 20 {
            #expect(abs((after.first?.x ?? 0) - fold.upperBound) < 0.01, comment)
        }
    }

    @Test(arguments: windows)
    func theGridBeginsAndEndsAtTheSystemMargins(window: Window) {
        for typeSize in Self.typeSizes {
            let layout = LibraryColumns(space: window.space, typeSize: typeSize)
            Self.check(layout, in: window.space, "\(window.name), \(typeSize)")
            // One page: the grid fills the room between the margins.
            let end = layout.columns.last?.maxX ?? 0
            #expect(abs(end - (window.width - window.margins.trailing)) < 0.01, "\(window.name), \(typeSize)")
        }
    }

    @Test(arguments: DuoGeometries.cases)
    func theGridKeepsItsRulesInEveryGeometry(geometry: DuoGeometries.Case) {
        let fold = geometry.geometry.fold
        // Only the book divides the grid: an active fold from top to bottom.
        let divides = geometry.geometry.isFoldActive && fold.map { $0.height > $0.width } == true
        for margins in Self.margins {
            let space = LibraryColumns.Space(geometry: geometry.geometry, margins: margins)
            let safe = geometry.geometry.safeBounds.points(scale: geometry.geometry.scale)
            #expect(abs(space.width - safe.width) < 0.01)
            #expect((space.fold != nil) == divides, "\(geometry.name)")
            if let fold, let range = space.fold {
                let frame = fold.points(scale: geometry.geometry.scale)
                #expect(abs(range.lowerBound - (frame.minX - safe.minX)) < 0.01)
                #expect(abs(range.upperBound - (frame.maxX - safe.minX)) < 0.01)
            }
            for typeSize in Self.typeSizes {
                Self.check(LibraryColumns(space: space, typeSize: typeSize), in: space,
                           "\(geometry.name), margins \(margins.leading)/\(margins.trailing), \(typeSize)")
            }
        }
    }

    @Test func theMeasuredWindowsKeepTheirColumnsAtTheStandardSize() {
        let counts = Self.measured.map { LibraryColumns(space: $0.space, typeSize: .large).columns.count }
        #expect(counts == [2, 3, 3, 4])
    }

    /// The book as the Simulator reports it: the division region lies at
    /// 455.5 to 495.5 pt of 951, the bar takes 84 pt on the right.
    static let book = FoldGeometry(
        container: DuoGeometries.innerLandscape, safeArea: PixelInsets(top: 246, bottom: 102, right: 252),
        fold: PixelRect(x: 1366, y: 0, width: 121, height: 2007), foldMargins: PixelInsets(left: 60, right: 60),
        isFoldActive: true, scale: 3)

    @Test func theBookGetsTwoPagesOfEqualColumns() throws {
        let space = LibraryColumns.Space(geometry: Self.book, margins: SystemMargins(leading: 20, trailing: 0))
        let fold = try #require(space.fold)
        #expect(abs(fold.lowerBound - 455.33) < 0.01 && abs(fold.upperBound - 495.67) < 0.01)
        #expect(space.width == 867 && space.visibleHeight == 553)

        // Two columns on each page, as wide as the narrower page allows:
        // (867 - 495.67 - 14) / 2.
        let standard = LibraryColumns(space: space, typeSize: .large)
        Self.check(standard, in: space, "book")
        #expect(standard.columns.count == 4)
        #expect(abs(standard.columns[0].width - 178.67) < 0.01)
        #expect(standard.columns.map { ($0.x * 100).rounded() / 100 } == [20, 212.67, 495.67, 688.33])
        #expect(abs(standard.columns[3].maxX - 867) < 0.01)

        // Large text: one tile on each page.
        let large = LibraryColumns(space: space, typeSize: .accessibility2)
        Self.check(large, in: space, "book, large text")
        #expect(large.columns.count == 2)
        #expect(abs(large.columns[1].x - 495.67) < 0.01)
        for typeSize in Self.typeSizes {
            let layout = LibraryColumns(space: space, typeSize: typeSize)
            Self.check(layout, in: space, "book, \(typeSize)")
            #expect(Self.tileHeight(layout, typeSize) <= 553 - LibraryColumns.topPadding)
        }
    }

    @Test func openFlatAndTabletopStayOnePage() {
        var flat = Self.book
        flat.isFoldActive = false
        #expect(LibraryColumns.Space(geometry: flat, margins: .standard).fold == nil)
        let tabletop = DuoGeometries.foldAcross(band: 0, margin: 20, active: true)
        #expect(LibraryColumns.Space(geometry: tabletop, margins: .standard).fold == nil)
        #expect(LibraryColumns(space: .init(geometry: tabletop, margins: .standard), typeSize: .large).columns.count == 3)
    }

    @Test func aFoldCountsFromTheLeadingEdge() throws {
        let margins = SystemMargins(leading: 20, trailing: 0)
        let leftToRight = try #require(LibraryColumns.Space(geometry: Self.book, margins: margins).fold)
        let rightToLeft = try #require(LibraryColumns.Space(geometry: Self.book, margins: margins, isRightToLeft: true).fold)
        #expect(abs(rightToLeft.lowerBound - (867 - leftToRight.upperBound)) < 0.01)
        #expect(abs(rightToLeft.upperBound - (867 - leftToRight.lowerBound)) < 0.01)
    }

    @Test func aSideTooNarrowForATileStaysEmpty() {
        let space = LibraryColumns.Space(width: 382, margins: .standard, fold: 60...76)
        let layout = LibraryColumns(space: space, typeSize: .large)
        #expect(layout.columns.allSatisfy { $0.x >= 76 })
        #expect(abs((layout.columns.last?.maxX ?? 0) - 362) < 0.01)
    }

    /// The height of a tile with a name of two lines.
    static func tileHeight(_ layout: LibraryColumns, _ typeSize: DynamicTypeSize) -> CGFloat {
        (layout.columns.first?.width ?? 0) / LibraryColumns.artworkAspect + LibraryColumns.labelHeight(for: typeSize)
    }

    @Test(arguments: windows)
    func aTileWithItsNameFitsIntoTheWindow(window: Window) {
        for typeSize in Self.typeSizes {
            let layout = LibraryColumns(space: window.space, typeSize: typeSize)
            let height = Self.tileHeight(layout, typeSize)
            #expect(height <= window.visibleHeight - LibraryColumns.topPadding + 0.01,
                    "\(window.name), \(typeSize): a tile of \(layout.columns[0].width) pt is \(height) pt high")
        }
    }

    @Test func largeTextTakesFewerColumnsButFollowsTheWidth() {
        let accessibility = Self.typeSizes.filter(\.isAccessibilitySize)
        let counts = Self.measured.map { window in
            accessibility.map { LibraryColumns(space: window.space, typeSize: $0).columns.count }
        }
        // Beside the bar of the outer display there is room for one tile.
        // Sideways there the height of a row asks for more columns again as
        // the label grows; every wider window keeps at least two.
        #expect(counts == [[1, 1, 1, 1, 1], [2, 2, 3, 3, 3], [2, 2, 2, 2, 2], [3, 3, 2, 2, 2]])
        for (window, counts) in zip(Self.measured, counts) {
            let standard = LibraryColumns(space: window.space, typeSize: .large).columns.count
            #expect(counts.allSatisfy { $0 <= standard }, "\(window.name)")
        }
    }

    @Test func theLabelGrowsWithTheTextSize() {
        let heights = Self.typeSizes.map { LibraryColumns.labelHeight(for: $0) }
        #expect(heights == heights.sorted())
        // 6 + 2 × 18 + 2 + 15 at the standard size.
        #expect(abs(LibraryColumns.labelHeight(for: .large) - 59) <= 2)
        #expect(LibraryColumns.labelHeight(for: .accessibility5) > 150)
    }

    @Test func withoutAVisibleHeightOnlyTheWidthCounts() {
        let space = LibraryColumns.Space(width: 594, margins: SystemMargins(leading: 0, trailing: 20))
        #expect(LibraryColumns(space: space, typeSize: .accessibility5).columns.count == 1)
    }
}
