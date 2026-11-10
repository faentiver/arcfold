@testable import Arcfold
import CoreGraphics
import FoldLayout
import SwiftUI
import Testing

/// The columns of the library (`LibraryColumns`) in the windows of the Duo
/// and in every geometry of `LayoutInvariantTests` in FoldLayout, at every
/// text size: the grid begins and ends at the system's margins, its columns
/// are equal and apart, and a tile with its name fits into what the window
/// shows at once.
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
        for margins in Self.margins {
            let space = LibraryColumns.Space(geometry: geometry.geometry, margins: margins)
            let safe = geometry.geometry.safeBounds.points(scale: geometry.geometry.scale)
            #expect(abs(space.width - safe.width) < 0.01)
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
