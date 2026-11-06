import Renderer
import Testing

/// Whole-number scaling, centred on whole pixels (ADR 0005, section 5). The
/// sizes are the Duo panels from the plan, section 3.
struct ScreenPlacementTests {
    struct Case: Sendable, CustomTestStringConvertible {
        let name: String
        let drawable: (width: Int, height: Int)
        let expected: ScreenPlacement

        var testDescription: String { name }
    }

    static let duoCases = [
        Case(name: "inner display upright", drawable: (1878, 2670),
             expected: ScreenPlacement(scale: 7, originX: 99, originY: 775, width: 1680, height: 1120)),
        Case(name: "inner display sideways", drawable: (2670, 1878),
             expected: ScreenPlacement(scale: 11, originX: 15, originY: 59, width: 2640, height: 1760)),
        Case(name: "outer display upright", drawable: (1398, 2034),
             expected: ScreenPlacement(scale: 5, originX: 99, originY: 617, width: 1200, height: 800)),
    ]

    @Test(arguments: duoCases)
    func gbaOnTheDuo(_ testCase: Case) {
        let placement = ScreenPlacement.fitting(
            sourceWidth: 240, sourceHeight: 160,
            drawableWidth: testCase.drawable.width, drawableHeight: testCase.drawable.height)
        #expect(placement == testCase.expected)
    }

    @Test func anExactFitHasNoBorder() {
        let placement = ScreenPlacement.fitting(sourceWidth: 240, sourceHeight: 160, drawableWidth: 720, drawableHeight: 480)
        #expect(placement == ScreenPlacement(scale: 3, originX: 0, originY: 0, width: 720, height: 480))
    }

    @Test func anOddRemainderGoesToTheRightAndBottom() {
        let placement = ScreenPlacement.fitting(sourceWidth: 240, sourceHeight: 160, drawableWidth: 481, drawableHeight: 323)
        #expect(placement == ScreenPlacement(scale: 2, originX: 0, originY: 1, width: 480, height: 320))
    }

    @Test func aSourceLargerThanTheDrawableKeepsScaleOneAndIsCentred() {
        let placement = ScreenPlacement.fitting(sourceWidth: 240, sourceHeight: 160, drawableWidth: 200, drawableHeight: 100)
        #expect(placement == ScreenPlacement(scale: 1, originX: -20, originY: -30, width: 240, height: 160))
    }

    @Test func anEmptySourceGivesAnEmptyPlacement() {
        let placement = ScreenPlacement.fitting(sourceWidth: 0, sourceHeight: 160, drawableWidth: 200, drawableHeight: 100)
        #expect(placement.width == 0)
        #expect(placement.height == 0)
        #expect(placement.scale == 1)
    }
}
