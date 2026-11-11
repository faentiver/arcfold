@testable import Arcfold
import CoreGraphics
import FoldLayout
import Testing

/// Where a fold divides a view (`FoldDivision`), in every geometry of
/// `LayoutInvariantTests` in FoldLayout: only an active fold from top to
/// bottom divides, and the first page ends where the division region begins.
struct FoldDivisionTests {
    @Test(arguments: DuoGeometries.cases)
    func onlyTheBookDivides(geometry: DuoGeometries.Case) {
        let fold = geometry.geometry.fold
        let isBook = geometry.geometry.isFoldActive && fold.map { $0.height > $0.width } == true
        let range = FoldDivision.range(in: geometry.geometry)
        #expect((range != nil) == isBook)
        let safe = geometry.geometry.safeBounds.points(scale: geometry.geometry.scale)
        let inset = FoldDivision.trailingInsetOfFirstPage(in: geometry.geometry)
        guard let fold, let range else {
            #expect(inset == 0)
            return
        }
        // The first page and the fold do not overlap, and the page has room.
        let frame = fold.points(scale: geometry.geometry.scale)
        #expect(abs(range.lowerBound - (frame.minX - safe.minX)) < 0.01)
        #expect(abs(range.upperBound - (frame.maxX - safe.minX)) < 0.01)
        #expect(abs((safe.width - inset) - range.lowerBound) < 0.01)
        #expect(safe.width - inset > 120)
    }

    @Test func theBookOfTheSimulatorEndsItsFirstPageAtTheFold() throws {
        let book = LibraryColumnsTests.book
        let range = try #require(FoldDivision.range(in: book))
        #expect(abs(range.lowerBound - 455.33) < 0.01 && abs(range.upperBound - 495.67) < 0.01)
        // 867 pt beside the bar; the first page is 455.33 pt wide.
        #expect(abs(FoldDivision.trailingInsetOfFirstPage(in: book) - (867 - 455.33)) < 0.01)
        // From the right, the first page lies between the bar and the fold.
        let mirrored = try #require(FoldDivision.range(in: book, isRightToLeft: true))
        #expect(abs(mirrored.lowerBound - (867 - 495.67)) < 0.01)
        #expect(abs(FoldDivision.trailingInsetOfFirstPage(in: book, isRightToLeft: true) - 495.67) < 0.01)
    }

    @Test func aFoldInTheSafeAreaInsetDividesNothing() {
        // A fold under the bar at the side is not in the view's safe area.
        let geometry = FoldGeometry(
            container: DuoGeometries.innerLandscape, safeArea: PixelInsets(right: 252),
            fold: PixelRect(x: 2700, y: 0, width: 60, height: 2007), isFoldActive: true, scale: 3)
        #expect(FoldDivision.range(in: geometry) == nil)
        #expect(FoldDivision.trailingInsetOfFirstPage(in: geometry) == 0)
    }
}
