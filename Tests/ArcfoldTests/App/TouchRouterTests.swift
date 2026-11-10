@testable import Arcfold
import CoreGraphics
import FoldLayout
import LibretroKit
import Testing

/// Which finger goes to the buttons and which to the touch screen (ADR 0006,
/// section 6), with the DS on the closed Duo: the touch screen 4× at
/// (61, 768) px, the buttons in the band below it.
struct TouchRouterTests {
    typealias Router = TouchRouter<Int>

    static let geometry = TouchLayoutTests.dsClosed
    static let gameLayout = GameLayout(system: .ds, geometry: geometry, showsTouchControls: true)
    static let controls = TouchLayout(zones: gameLayout.controls!, scale: 3, hasXYButtons: true)
    static let touchScreen = TouchMapping(screen: gameLayout.touchScreen!, scale: 3)

    /// The point on the top left corner of view pixel (x, y).
    static func point(_ x: Int, _ y: Int) -> CGPoint {
        CGPoint(x: CGFloat(x) / 3, y: CGFloat(y) / 3)
    }

    static func touch(_ id: Int, _ location: CGPoint, active: Bool = true) -> Router.Touch {
        Router.Touch(id: id, location: location, isActive: active)
    }

    static var a: CGPoint {
        let frame = controls.buttons.first { $0.label == "A" }!.frame
        return CGPoint(x: frame.midX, y: frame.midY)
    }

    @Test func aFingerOnTheTouchScreenIsTheStylusAndStaysAtTheEdge() {
        var router = Router()
        // DS pixel (10, 20): view pixel (61 + 40, 768 + 80).
        var output = router.update([Self.touch(1, Self.point(101, 848))], controls: Self.controls, touchScreen: Self.touchScreen)
        #expect(output == Router.Output(buttons: [], touchPixel: .init(x: 10, y: 20)))
        // Sliding left off the screen keeps x at 0.
        output = router.update([Self.touch(1, Self.point(10, 848))], controls: Self.controls, touchScreen: Self.touchScreen)
        #expect(output.touchPixel == .init(x: 0, y: 20))
        // Down onto A: still the stylus, at the lower edge, and no button.
        output = router.update([Self.touch(1, Self.a)], controls: Self.controls, touchScreen: Self.touchScreen)
        #expect(output.buttons.isEmpty)
        #expect(output.touchPixel?.y == 191)
        output = router.update([Self.touch(1, Self.point(1300, 1800))], controls: Self.controls, touchScreen: Self.touchScreen)
        #expect(output == Router.Output(buttons: [], touchPixel: .init(x: 255, y: 191)))
        // Lifting releases it.
        output = router.update([Self.touch(1, Self.a, active: false)], controls: Self.controls, touchScreen: Self.touchScreen)
        #expect(output == Router.Output(buttons: [], touchPixel: nil))
    }

    @Test func buttonsNeverReactOnTheTouchScreen() {
        var router = Router()
        var output = router.update([Self.touch(1, Self.a)], controls: Self.controls, touchScreen: Self.touchScreen)
        #expect(output.buttons == .a)
        // The finger slides up onto the touch screen: no button, and no stylus.
        output = router.update([Self.touch(1, Self.point(600, 1500))], controls: Self.controls, touchScreen: Self.touchScreen)
        #expect(output == Router.Output(buttons: [], touchPixel: nil))
        // And back down onto A.
        output = router.update([Self.touch(1, Self.a)], controls: Self.controls, touchScreen: Self.touchScreen)
        #expect(output.buttons == .a)
    }

    @Test func buttonsAndTheTouchScreenWorkTogether() {
        var router = Router()
        let output = router.update(
            [Self.touch(1, Self.a), Self.touch(2, Self.point(61, 768))],
            controls: Self.controls, touchScreen: Self.touchScreen)
        #expect(output == Router.Output(buttons: .a, touchPixel: .init(x: 0, y: 0)))
    }

    @Test func aSecondFingerOnTheTouchScreenIsIgnored() {
        var router = Router()
        _ = router.update([Self.touch(1, Self.point(101, 848))], controls: Self.controls, touchScreen: Self.touchScreen)
        var output = router.update([Self.touch(1, Self.point(101, 848)), Self.touch(2, Self.point(1000, 1400))],
                                   controls: Self.controls, touchScreen: Self.touchScreen)
        #expect(output.touchPixel == .init(x: 10, y: 20))
        // The first lifts; the second does not become the stylus.
        output = router.update([Self.touch(2, Self.point(1000, 1400))], controls: Self.controls, touchScreen: Self.touchScreen)
        #expect(output == Router.Output(buttons: [], touchPixel: nil))
        // A new finger does.
        output = router.update([Self.touch(2, Self.point(1000, 1400)), Self.touch(3, Self.point(65, 772))],
                               controls: Self.controls, touchScreen: Self.touchScreen)
        #expect(output.touchPixel == .init(x: 1, y: 1))
    }

    @Test func aSystemWithoutTouchScreenOnlyHasButtons() {
        var router = Router()
        let output = router.update([Self.touch(1, Self.point(101, 848)), Self.touch(2, Self.a)],
                                   controls: Self.controls, touchScreen: nil)
        #expect(output == Router.Output(buttons: .a, touchPixel: nil))
        #expect(router.reset() == Router.Output(buttons: [], touchPixel: nil))
    }

    /// Without touch controls (a controller is in use) the touch screen still works.
    @Test func theTouchScreenWorksWithoutTouchControls() {
        var router = Router()
        let output = router.update([Self.touch(1, Self.point(1084, 1535))], controls: nil, touchScreen: Self.touchScreen)
        #expect(output == Router.Output(buttons: [], touchPixel: .init(x: 255, y: 191)))
    }
}
