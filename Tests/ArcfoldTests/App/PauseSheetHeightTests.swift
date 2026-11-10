@testable import Arcfold
import CoreGraphics
import FoldLayout
import SwiftUI
import Testing
import UIKit

/// The height of the pause sheet (ADR 0007): that of its content, so no
/// empty glass lies below the last button, and never across a fold that is
/// bent across the window. The numbers are those measured in the Simulator's
/// Duo: the content is 235 pt high at the default text size, the safe area
/// at the bottom of the sheet 34 pt, and the fold of the inner display is
/// 121 px wide.
struct PauseSheetHeightTests {
    /// The inner display folded like a laptop, as measured.
    static let tabletop = FoldGeometry(container: DuoGeometries.inner,
                                       fold: PixelRect(x: 0, y: 1366, width: 2007, height: 121), isFoldActive: true)

    /// The height of the content as SwiftUI lays it out in a sheet of the
    /// outer display, 450 pt wide, without the margin at the bottom, which
    /// the safe area of the sheet gives.
    @MainActor static func contentHeight(width: CGFloat = 450, size: DynamicTypeSize = .large) -> CGFloat {
        let content = PauseMenuContent(gameName: "selftest", showsDebugOverlay: .constant(true), resume: {}, quit: {})
            .frame(width: width)
            .environment(\.dynamicTypeSize, size)
        return UIHostingController(rootView: content).sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude)).height
    }

    /// Before the first layout the sheet has the height its content has at
    /// the default text size, so that it opens without a second move; that
    /// height is the one SwiftUI lays the content out with, in a sheet of
    /// any width of the Duo. With the accessibility sizes it begins at the
    /// system's medium height.
    @MainActor @Test func beforeTheFirstLayoutTheSheetIsAsHighAsTheContentAtTheDefaultSize() {
        let height = PauseSheetHeight(content: nil)
        #expect(height.value == nil && !height.isHeldBelowFold)
        #expect(height.detents(isAccessibilitySize: false) == [.height(PauseSheetHeight.contentAtDefaultSize)])
        #expect(height.detents(isAccessibilitySize: true) == [.medium])
        for width: CGFloat in [450, 459, 653, 662] {
            let measured = PauseSheetHeight(content: Self.contentHeight(width: width))
            #expect(measured.value == PauseSheetHeight.contentAtDefaultSize, "\(width) pt: \(Self.contentHeight(width: width)) pt")
        }
    }

    /// Larger text makes the content higher, never lower.
    @MainActor @Test func theContentGrowsWithTheText() {
        var previous: CGFloat = 0
        for size in DynamicTypeSize.allCases {
            let height = Self.contentHeight(size: size)
            #expect(height >= previous, "\(size): \(height) pt after \(previous) pt")
            previous = height
        }
        #expect(previous > 2 * PauseSheetHeight.contentAtDefaultSize - 100, "the largest text: \(previous) pt")
    }

    /// The sheet is as high as its content, in whole points, at every text
    /// size; the system keeps a content higher than the window inside it.
    @Test(arguments: [234.67, 235, 500.33, 2000])
    func theSheetIsAsHighAsItsContent(content: Double) {
        let height = PauseSheetHeight(content: content)
        let expected = CGFloat(content.rounded(.up))
        #expect(height.value == expected && !height.isHeldBelowFold)
        for isAccessibilitySize in [false, true] {
            #expect(height.detents(isAccessibilitySize: isAccessibilitySize) == [.height(expected)])
        }
        // A content never gives a sheet without a height.
        #expect(PauseSheetHeight(content: 0).value == 1)
    }

    /// Only a fold that is bent across the view holds the sheet: the
    /// tabletop posture, with the height of the view below the fold. Flat,
    /// in the book pose and on the outer display the sheet may be as high as
    /// the window.
    @Test func onlyAFoldBentAcrossTheViewHoldsTheSheet() {
        #expect(PauseSheetHeight.roomBelowFold(in: nil) == nil)
        #expect(PauseSheetHeight.roomBelowFold(in: Self.tabletop) == CGFloat(2853 - 1487) / 3)
        for testCase in DuoGeometries.cases {
            let geometry = testCase.geometry
            let room = PauseSheetHeight.roomBelowFold(in: geometry)
            if geometry.posture == .tabletop, let fold = geometry.fold {
                #expect(room == CGFloat(geometry.container.height - fold.maxY) / CGFloat(geometry.scale), "\(testCase.name)")
                #expect(geometry.isFoldActive && fold.width > fold.height)
            } else {
                #expect(room == nil, "\(testCase.name)")
            }
        }
    }

    /// Folded like a laptop, 455.33 pt of the window lie below the fold, and
    /// the safe area at the bottom of the sheet takes 34 pt of them: 421 pt
    /// for the content, as the system's medium height gave it. The content
    /// of the default size fits and the sheet is as high as it; the content
    /// of the largest text is held and scrolls, and may be pulled up to the
    /// full height.
    @Test func foldedLikeALaptopTheSheetStaysBelowTheFold() throws {
        let room = try #require(PauseSheetHeight.roomBelowFold(in: Self.tabletop))
        let fits = PauseSheetHeight(content: 234.67, roomBelowFold: room, bottomInset: 34)
        #expect(fits.roomBelowFold == room - 34)
        #expect(fits.value == 235 && !fits.isHeldBelowFold)
        #expect(fits.detents(isAccessibilitySize: true) == [.height(235)])

        let held = PauseSheetHeight(content: 438, roomBelowFold: room, bottomInset: 34)
        #expect(held.value == 421 && held.isHeldBelowFold)
        #expect(held.detents(isAccessibilitySize: true) == [.height(421), .large])
        #expect(held.detents(isAccessibilitySize: false) == [.height(421)])
        // With its safe area the sheet is no higher than the window below the fold.
        #expect((held.value ?? 0) + 34 <= room)
    }

    /// Without such a fold nothing holds the sheet, whatever the safe area;
    /// a room smaller than the safe area leaves the sheet its least height.
    @Test func withoutAFoldNothingHoldsTheSheet() {
        #expect(PauseSheetHeight(content: 438, roomBelowFold: nil, bottomInset: 34).value == 438)
        #expect(PauseSheetHeight(content: 438, roomBelowFold: nil, bottomInset: 34).roomBelowFold == nil)
        #expect(PauseSheetHeight(content: 438, roomBelowFold: 20, bottomInset: 34).value == 1)
    }
}
