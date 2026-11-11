@testable import Arcfold
import CoreGraphics
import FoldLayout
import Testing

/// Who draws the menu button, which pauses the game (ADR 0007), in every
/// geometry of `DuoGeometries` for the GBA and the DS: with touch controls
/// the controls draw it with Select and Start, as a small button of the
/// case or, over a picture, in their glass container (rule R4), in the
/// place `OverlayPlacement` names, and it overlaps none of the keys beside
/// it; without them the button draws itself, alone in its corner.
struct PauseGlassTests {
    typealias Case = OverlayPlacementTests.Case

    @Test(arguments: NoticePlacementTests.cases)
    func theControlsDrawThePauseGlassWhileTheyShow(_ testCase: Case) throws {
        let placement = testCase.placement
        let glass = PauseGlass.drawnByControls(testCase.controls, frame: placement.pauseButton, isPressed: false)
        guard let controls = testCase.controls else {
            #expect(glass == nil, "without touch controls the button draws its own glass")
            return
        }
        let frame = try #require(glass).frame
        #expect(frame == controls.pauseButton && frame == placement.pauseButton)
        // One container holds it with its neighbours: it overlaps none of
        // them, so the shapes stay apart at the container's spacing of 0.
        for button in controls.buttons {
            #expect(!frame.intersects(button.frame), "the pause glass overlaps \(button.label)")
        }
        #expect(!frame.intersects(controls.pad.frame), "the pause glass overlaps the pad")
    }

    /// Without a pause button, as while a game loads, nothing is drawn.
    @Test func noPauseButtonNoGlass() throws {
        let testCase = try #require(NoticePlacementTests.cases.first { $0.showsControls })
        #expect(PauseGlass.drawnByControls(testCase.controls, frame: nil, isPressed: false) == nil)
        let pressed = PauseGlass.drawnByControls(testCase.controls, frame: testCase.placement.pauseButton, isPressed: true)
        #expect(pressed?.isPressed == true)
    }
}
