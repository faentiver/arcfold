@testable import Arcfold
import CoreGraphics
import SwiftUI
import Testing

/// The margins of the pause sheet's content beside the system column of the
/// outer display (ADR 0007), from the insets measured in the Simulator: the
/// sheet lies 8 pt inside the display, the column is 84 pt wide, and the
/// safe area at the bottom of the sheet is 34 pt.
struct PauseSheetMarginsTests {
    typealias Insets = PauseSheetMargins.Insets

    /// Sideways the column lies on the left, beside the whole sheet: the
    /// content was 96 pt from the left and 20 pt from the right edge.
    @Test func sidewaysTheMarginsAreEqual() {
        for insets in [Insets(leading: 76, trailing: 0), Insets(leading: 0, trailing: 76)] {
            let margins = PauseSheetMargins(insets: insets, isUpright: false)
            #expect(margins.spannedEdges.isEmpty, "the camera lies in the column beside the sheet")
            let content = margins.contentMargins(insets: insets, padding: 20)
            #expect(content.leading == 96 && content.trailing == 96)
        }
    }

    /// Upright the content takes the sheet's width, on whichever side the
    /// column lies.
    @Test func uprightTheContentSpansTheColumn() {
        let right = Insets(leading: 0, trailing: 76)
        let margins = PauseSheetMargins(insets: right, isUpright: true)
        #expect(margins.spannedEdges == .trailing && margins.leading == 0 && margins.trailing == 0)
        #expect(margins.contentMargins(insets: right, padding: 20) == (20, 20))
        let left = Insets(leading: 76, trailing: 0)
        #expect(PauseSheetMargins(insets: left, isUpright: true).spannedEdges == .leading)
        #expect(PauseSheetMargins(insets: left, isUpright: true).contentMargins(insets: left, padding: 20) == (20, 20))
    }

    /// Without a column, as on the inner display or with the bar on top,
    /// nothing changes; the rounding of the system (0.17 pt in the book
    /// pose) counts as none.
    @Test(arguments: [true, false])
    func equalInsetsNeedNothing(isUpright: Bool) {
        let sides: [(leading: CGFloat, trailing: CGFloat)] = [(0, 0), (20, 20), (0, 0.17)]
        for (leading, trailing) in sides {
            let insets = Insets(leading: leading, trailing: trailing)
            let margins = PauseSheetMargins(insets: insets, isUpright: isUpright)
            #expect(margins.spannedEdges.isEmpty && margins.leading == 0 && margins.trailing == 0)
        }
    }

    /// Below the last button the safe area of the sheet is the margin. Only
    /// where it is narrower than 20 pt, as without a home indicator, the
    /// content adds the rest.
    @Test(arguments: [true, false])
    func theSafeAreaIsTheMarginAtTheBottom(isUpright: Bool) {
        #expect(PauseSheetMargins.bottomMargin == 20)
        let paddings: [(inset: CGFloat, padding: CGFloat)] = [(34, 0), (20, 0), (12, 8), (0, 20)]
        for (inset, padding) in paddings {
            let margins = PauseSheetMargins(insets: Insets(leading: 0, trailing: 76, bottom: inset), isUpright: isUpright)
            #expect(margins.bottom == padding, "an inset of \(inset) pt")
        }
    }
}
