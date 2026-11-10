@testable import Arcfold
import CoreGraphics
import FoldLayout
import SwiftUI
import Testing
import UIKit

/// The status chip and the notices (ADR 0007, rules R4 and R6) in every
/// geometry of `DuoGeometries`, for the GBA and the DS, with touch controls
/// and with a controller: they share one column on the picture that covers
/// no button with its slop, no reach of the pad, no pause button, no touch
/// screen and no fold over its whole height, so a notice of any length grows
/// upwards in it and moves the chip along. The stack itself is measured as
/// SwiftUI lays it out: the longest notice of the app is shown whole.
@MainActor
struct NoticePlacementTests {
    typealias Case = OverlayPlacementTests.Case

    /// The longest notice the app shows, and the chip of a missing output.
    nonisolated static let longNotice = "The save could not be written: The battery save failed: Cannot create battery.sav.tmp"
    nonisolated static let audioProblem = "The audio engine could not start: no output route"

    /// The closed Duo sideways as the Simulator reports it: the system
    /// column on the left with the camera (docs/wissen/falz.md).
    nonisolated static let measuredSideways = DuoGeometries.Case(
        name: "closed, sideways as measured",
        geometry: FoldGeometry(container: DuoGeometries.outerLandscape, safeArea: PixelInsets(left: 252, bottom: 102),
                               occlusions: [PixelRect(x: 87, y: 87, width: 112, height: 112),
                                            PixelRect(x: 0, y: 0, width: 252, height: 246)]))

    nonisolated static let cases = OverlayPlacementTests.cases + DuoGeometries.systems.flatMap { system in
        [true, false].map { Case(system: system.system, geometry: measuredSideways, showsControls: $0) }
    }

    /// The height of the stack as SwiftUI lays it out in a column of `width`
    /// that offers `height`.
    static func stackHeight(width: CGFloat, offering height: CGFloat = .greatestFiniteMagnitude, notice: String?,
                            audioProblem: String?, size: DynamicTypeSize = .large) -> CGFloat {
        let stack = NoticeStack(audioProblem: audioProblem, notice: notice)
            .frame(width: width)
            .environment(\.dynamicTypeSize, size)
        return UIHostingController(rootView: stack).sizeThatFits(in: CGSize(width: width, height: height)).height
    }

    @Test(arguments: cases)
    func theColumnStaysOnThePictureAndCoversNothing(_ testCase: Case) {
        let placement = testCase.placement
        let column = placement.noticeColumn
        OverlayPlacementTests.checkClear(column, named: "notice column", in: testCase)
        // The picture is the upper or only screen, never the touch screen.
        let pictureIndex = testCase.layout.touchScreenIndex == 0 ? 1 : 0
        #expect(placement.pictureArea == testCase.points(testCase.layout.screens[pictureIndex].destination))
        let available = placement.pictureArea.width - 2 * placement.inset
        #expect(column.width >= min(OverlayPlacement.toastMinWidth, available) - 0.001, "too narrow for a notice: \(column)")
        #expect(column.width <= Metrics.toastMaxWidth(for: placement.pictureArea.width) + 0.001)
        #expect(column.maxY <= placement.pictureArea.maxY - OverlayPlacement.toastBottomMargin + 0.001)
    }

    /// Only a picture too low for the chip above a notice of three lines,
    /// such as the DS sideways on an iPhone (128 pt), gives them less.
    @Test(arguments: cases)
    func theColumnHoldsTheChipAboveANotice(_ testCase: Case) {
        let placement = testCase.placement
        let room = placement.pictureArea.height - placement.inset - OverlayPlacement.toastBottomMargin
        let isLow = room < OverlayPlacement.heightForNoticeAndChip
        #expect(placement.noticeColumn.height >= OverlayPlacement.heightForNoticeAndChip - 0.001
                    || (isLow && placement.noticeColumn.height >= room - 0.001),
                "the column is \(placement.noticeColumn.height) pt high in a picture of \(placement.pictureArea.height) pt")
    }

    /// The longest notice is shown whole below the chip at the default size,
    /// also where the picture is narrow: sideways the upper DS screen is
    /// 256 pt wide, and three lines cut the message off there.
    @Test(arguments: cases)
    func theLongestNoticeIsShownWholeBelowTheChip(_ testCase: Case) {
        let column = testCase.placement.noticeColumn
        guard column.height >= OverlayPlacement.heightForNoticeAndChip else { return }
        let height = Self.stackHeight(width: column.width, notice: Self.longNotice, audioProblem: Self.audioProblem)
        #expect(height <= column.height + 0.5,
                "the stack needs \(height) pt in a column of \(column.width) × \(column.height) pt")
    }

    /// The chip sits above the notice in the stack, whatever the size of the
    /// text: the stack is as high as both and their spacing, at every size.
    @Test(arguments: [DynamicTypeSize.xSmall, .large, .xxxLarge, .accessibility1, .accessibility3, .accessibility5])
    func theChipMovesUpWithAGrowingNotice(_ size: DynamicTypeSize) {
        for width: CGFloat in [232, 320, 400] {
            let notice = Self.stackHeight(width: width, notice: Self.longNotice, audioProblem: nil, size: size)
            let chip = Self.stackHeight(width: width, notice: nil, audioProblem: Self.audioProblem, size: size)
            let both = Self.stackHeight(width: width, notice: Self.longNotice, audioProblem: Self.audioProblem, size: size)
            #expect(notice > 0 && chip > 0)
            #expect(abs(both - (notice + OverlayPlacement.spacing + chip)) <= 1,
                    "\(size) at \(width) pt: \(both) pt for a notice of \(notice) pt and a chip of \(chip) pt")
        }
    }

    /// The closed Duo upright with the GBA, which moves the bar to the top:
    /// the longest notice below the chip fits the picture up to the first
    /// accessibility size.
    @Test(arguments: [DynamicTypeSize.large, .xxxLarge, .accessibility1])
    func theStackFitsTheOuterDisplay(_ size: DynamicTypeSize) {
        let geometry = DuoGeometries.Case(name: "closed", geometry: DuoGeometries.closed(barOnTop: true))
        let column = Case(system: .gba, geometry: geometry, showsControls: true).placement.noticeColumn
        let height = Self.stackHeight(width: column.width, notice: Self.longNotice, audioProblem: Self.audioProblem,
                                      size: size)
        #expect(height <= column.height + 0.5, "\(size): \(height) pt in a column of \(column.height) pt")
    }

    /// A stack too high for its column, as with the largest text on a low
    /// picture, stays inside the column: the notice gives way, the chip
    /// keeps its height, and nothing beside the column is covered.
    @Test(arguments: cases)
    func theStackNeverLeavesItsColumn(_ testCase: Case) {
        let column = testCase.placement.noticeColumn
        let chip = Self.stackHeight(width: column.width, notice: nil, audioProblem: Self.audioProblem, size: .accessibility5)
        guard column.height >= chip + OverlayPlacement.spacing + 40 else { return }
        let height = Self.stackHeight(width: column.width, offering: column.height, notice: Self.longNotice,
                                      audioProblem: Self.audioProblem, size: .accessibility5)
        #expect(height <= column.height + 0.5, "\(height) pt in a column of \(column.height) pt")
        #expect(height >= chip + OverlayPlacement.spacing, "the chip lost its place: \(height) pt, chip \(chip) pt")
    }

    /// The free rectangles the column is chosen from.
    @Test func freeRectanglesKeepTheirDistance() {
        let area = CGRect(x: 0, y: 0, width: 300, height: 200)
        let obstacle = CGRect(x: 100, y: 50, width: 50, height: 50)
        let free = OverlayPlacement.freeRects(in: area, obstacles: [obstacle], gap: 6)
        let blocked = obstacle.insetBy(dx: -6, dy: -6)
        for rect in free {
            #expect(area.contains(rect) && !rect.intersects(blocked), "\(rect)")
        }
        #expect(free.contains(CGRect(x: 0, y: 0, width: 300, height: 44)))
        #expect(free.contains(CGRect(x: 0, y: 0, width: 94, height: 200)))
        #expect(free.contains(CGRect(x: 156, y: 0, width: 144, height: 200)))
        #expect(free.contains(CGRect(x: 0, y: 106, width: 300, height: 94)))
        #expect(OverlayPlacement.freeRects(in: area, obstacles: [], gap: 6) == [area])
    }
}
