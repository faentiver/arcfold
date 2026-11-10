@testable import Arcfold
import CoreGraphics
import SwiftUI
import Testing

/// The margins of the pause sheet's content beside the system column of the
/// outer display (ADR 0007), from the insets measured in the Simulator: the
/// sheet lies 8 pt inside the display, the column is 84 pt wide.
struct PauseSheetMarginsTests {
    typealias Insets = PauseSheetMargins.Insets

    /// Sideways the column lies on the left, beside the whole sheet: the
    /// content was 96 pt from the left and 20 pt from the right edge.
    @Test func sidewaysTheMarginsAreEqual() {
        for insets in [Insets(leading: 76, trailing: 0), Insets(leading: 0, trailing: 76)] {
            for isMedium in [true, false] {
                let margins = PauseSheetMargins(insets: insets, isMediumHeight: isMedium, isUpright: false)
                #expect(margins.spannedEdges.isEmpty, "the camera lies in the column beside the sheet")
                let content = margins.contentMargins(insets: insets, padding: 20)
                #expect(content.leading == 96 && content.trailing == 96)
            }
        }
    }

    /// Upright at medium height the content takes the sheet's width, on
    /// whichever side the column lies.
    @Test func uprightAtMediumHeightTheContentSpansTheColumn() {
        let right = Insets(leading: 0, trailing: 76)
        let margins = PauseSheetMargins(insets: right, isMediumHeight: true, isUpright: true)
        #expect(margins.spannedEdges == .trailing && margins.leading == 0 && margins.trailing == 0)
        #expect(margins.contentMargins(insets: right, padding: 20) == (20, 20))
        let left = Insets(leading: 76, trailing: 0)
        #expect(PauseSheetMargins(insets: left, isMediumHeight: true, isUpright: true).spannedEdges == .leading)
    }

    /// Upright at large height the status bar and the sensors lie beside the
    /// content: the inset stays.
    @Test func uprightAtLargeHeightTheInsetStays() {
        let insets = Insets(leading: 0, trailing: 76)
        let margins = PauseSheetMargins(insets: insets, isMediumHeight: false, isUpright: true)
        #expect(margins == PauseSheetMargins(insets: Insets(), isMediumHeight: false, isUpright: true))
        #expect(margins.contentMargins(insets: insets, padding: 20) == (20, 96))
    }

    /// Without a column, as on the inner display or with the bar on top,
    /// nothing changes.
    @Test(arguments: [true, false], [true, false])
    func equalInsetsNeedNothing(isMedium: Bool, isUpright: Bool) {
        for inset: CGFloat in [0, 20] {
            let insets = Insets(leading: inset, trailing: inset)
            let margins = PauseSheetMargins(insets: insets, isMediumHeight: isMedium, isUpright: isUpright)
            #expect(margins.spannedEdges.isEmpty && margins.leading == 0 && margins.trailing == 0)
        }
    }
}
