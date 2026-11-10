@testable import Arcfold
import CoreGraphics
import FoldLayout
import SwiftUI
import Testing

/// The columns of the library (`LibraryColumns`) in the windows of the Duo
/// and in every geometry of `LayoutInvariantTests` in FoldLayout, at every
/// text size: the grid begins and ends at the system's margins and its
/// columns are equal and apart.
struct LibraryColumnsTests {
    /// A window as the library finds it: the width of its scroll view inside
    /// the safe area and the system's margins in it.
    struct Window: Sendable, CustomTestStringConvertible {
        let name: String
        let width: CGFloat
        let margins: SystemMargins
        var testDescription: String { name }

        var space: LibraryColumns.Space {
            LibraryColumns.Space(width: width, margins: margins)
        }
    }

    /// Measured in the Simulator (iOS 27.1): beside the bar of the outer
    /// display and of the inner display held like a book the trailing margin
    /// is 0, sideways the leading one, because the inset stands for it.
    static let measured = [
        Window(name: "closed upright, 382 pt beside the bar", width: 382, margins: SystemMargins(leading: 20, trailing: 0)),
        Window(name: "closed sideways, 594 of 678 pt", width: 594, margins: SystemMargins(leading: 0, trailing: 20)),
        Window(name: "flat upright and tabletop, 669 pt", width: 669, margins: .standard),
        Window(name: "open and book, 867 of 951 pt", width: 867, margins: SystemMargins(leading: 20, trailing: 0)),
    ]

    /// The widths of the Duo's windows without a bar, with margins on both sides.
    static let whole = [382, 466, 678, 669, 951].map { width in
        Window(name: "\(width) pt", width: CGFloat(width), margins: .standard)
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
}
