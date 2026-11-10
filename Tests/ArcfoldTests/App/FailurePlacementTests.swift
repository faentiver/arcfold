@testable import Arcfold
import CoreGraphics
import FoldLayout
import Testing

/// Where the message of a game that could not start sits (ADR 0007, rule
/// R6), in every geometry of `DuoGeometries`: on one screen, inside the safe
/// area, never on the fold, active or not, and never across the line of a
/// fold without a width; with room for the message and its button.
struct FailurePlacementTests {
    @Test(arguments: OverlayPlacementTests.cases)
    func theFailureMessageStaysOnOneScreen(_ testCase: OverlayPlacementTests.Case) {
        let geometry = testCase.geometry.geometry
        let area = testCase.placement.failureArea
        let safe = testCase.points(geometry.safeBounds)
        #expect(safe.contains(area), "\(area) leaves the safe area \(safe)")
        if let fold = geometry.fold.map(testCase.points) {
            // Above a fold across, left of a fold from top to bottom: the
            // upper or first screen of the layouts.
            if fold.width > fold.height {
                #expect(area.maxY <= fold.minY + 0.001, "\(area) reaches the fold \(fold)")
            } else {
                #expect(area.maxX <= fold.minX + 0.001, "\(area) reaches the fold \(fold)")
            }
        } else {
            #expect(area == safe || !geometry.occlusions.isEmpty, "without a fold the whole safe area")
        }
        for occlusion in geometry.occlusions.map(testCase.points) {
            #expect(!area.intersects(occlusion), "\(area) lies under the occlusion \(occlusion)")
        }
        // The title, three lines of message and the button at the default
        // size need about 280 × 260 pt.
        #expect(area.width >= 300 && area.height >= 300, "too small for the message: \(area)")
    }

    /// With a fold, the area is the side of the first screen of the layout,
    /// so the message replaces the upper or left picture. A screen may reach
    /// into the margins of the fold; the message may not.
    @Test(arguments: OverlayPlacementTests.cases)
    func theFailureMessageSharesItsSideWithTheFirstScreen(_ testCase: OverlayPlacementTests.Case) throws {
        guard let fold = testCase.geometry.geometry.fold.map(testCase.points), !fold.isEmpty,
              testCase.layout.screens.count > 1 else { return }
        let first = testCase.points(try #require(testCase.layout.screens.first).destination)
        let area = testCase.placement.failureArea
        if fold.width > fold.height {
            #expect(first.midY < fold.minY && area.maxY <= fold.minY + 0.001)
        } else {
            #expect(first.midX < fold.minX && area.maxX <= fold.minX + 0.001)
        }
    }

    /// The Simulator's Duo as measured: the fold is 121 px wide in the book,
    /// open and in the tabletop pose (docs/wissen/falz.md).
    @Test func theMeasuredPosesOfTheDuo() {
        let book = FoldGeometry(container: DuoGeometries.innerLandscape,
                                fold: PixelRect(x: 1366, y: 0, width: 121, height: 2007), isFoldActive: true)
        #expect(OverlayPlacement.failureArea(in: book) == CGRect(x: 0, y: 0, width: 1366.0 / 3, height: 669))
        var open = book
        open.isFoldActive = false
        #expect(OverlayPlacement.failureArea(in: open) == OverlayPlacement.failureArea(in: book))
        let tabletop = FoldGeometry(container: DuoGeometries.inner,
                                    fold: PixelRect(x: 0, y: 1366, width: 2007, height: 121), isFoldActive: true)
        #expect(OverlayPlacement.failureArea(in: tabletop) == CGRect(x: 0, y: 0, width: 669, height: 1366.0 / 3))
        let closed = DuoGeometries.closed(barOnTop: false)
        #expect(OverlayPlacement.failureArea(in: closed) == CGRect(x: 0, y: 0, width: 382, height: 644))
    }
}
