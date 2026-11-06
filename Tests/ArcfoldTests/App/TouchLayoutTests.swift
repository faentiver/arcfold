@testable import Arcfold
import CoreGraphics
import LibretroKit
import Testing

/// The touch mask as a pure function, without a session (ADR 0005, section 7).
struct TouchLayoutTests {
    static let upright = TouchLayout(size: CGSize(width: 402, height: 440), isLandscape: false)
    static let sideways = TouchLayout(size: CGSize(width: 874, height: 402), isLandscape: true)

    static func center(of buttons: JoypadButtons, in layout: TouchLayout) throws -> CGPoint {
        let button = try #require(layout.buttons.first { $0.buttons == buttons })
        return CGPoint(x: button.frame.midX, y: button.frame.midY)
    }

    /// A point at `degrees` (0 is right, 90 is up) and `share` of the pad's radius.
    static func padPoint(_ layout: TouchLayout, degrees: CGFloat, share: CGFloat = 0.7) -> CGPoint {
        let radians = degrees * .pi / 180
        return CGPoint(
            x: layout.pad.center.x + cos(radians) * layout.pad.radius * share,
            y: layout.pad.center.y - sin(radians) * layout.pad.radius * share)
    }

    @Test(arguments: [false, true])
    func everyButtonPressesItselfAtItsCentre(isLandscape: Bool) throws {
        let layout = isLandscape ? Self.sideways : Self.upright
        #expect(layout.buttons.map(\.label) == ["A", "B", "L", "R", "Select", "Start"])
        for button in layout.buttons {
            let point = try Self.center(of: button.buttons, in: layout)
            #expect(layout.buttons(at: point) == button.buttons, "\(button.label)")
        }
    }

    @Test func thePadHasEightSectors() {
        let layout = Self.upright
        let expected: [(CGFloat, JoypadButtons)] = [
            (0, .right), (45, [.right, .up]), (90, .up), (135, [.up, .left]),
            (180, .left), (225, [.left, .down]), (270, .down), (315, [.down, .right]),
            // Just inside the neighbouring sector boundaries
            (22, .right), (23, [.right, .up]), (67, [.right, .up]), (68, .up),
        ]
        for (degrees, buttons) in expected {
            #expect(layout.buttons(at: Self.padPoint(layout, degrees: degrees)) == buttons, "\(degrees) degrees")
        }
    }

    @Test func theCentreOfThePadIsADeadZone() {
        let layout = Self.upright
        #expect(layout.buttons(at: layout.pad.center).isEmpty)
        #expect(layout.buttons(at: Self.padPoint(layout, degrees: 90, share: 0.2)).isEmpty)
        #expect(layout.buttons(at: Self.padPoint(layout, degrees: 90, share: 0.35)) == .up)
        // The pad reaches a bit beyond its circle, then nothing.
        #expect(layout.buttons(at: Self.padPoint(layout, degrees: 0, share: 1.3)) == .right)
        #expect(layout.buttons(at: Self.padPoint(layout, degrees: 0, share: 1.5)) != .right)
    }

    @Test func everyFingerCounts() throws {
        let layout = Self.upright
        let points = [
            Self.padPoint(layout, degrees: 90),
            try Self.center(of: .a, in: layout),
            try Self.center(of: .b, in: layout),
        ]
        #expect(layout.buttons(at: points) == [.up, .a, .b])
    }

    @Test func aFingerSlidesFromOneButtonToTheNext() throws {
        let layout = Self.upright
        let b = try Self.center(of: .b, in: layout)
        let a = try Self.center(of: .a, in: layout)
        #expect(layout.buttons(at: [b]) == .b)
        #expect(layout.buttons(at: [CGPoint(x: (a.x + b.x) / 2 + 30, y: (a.y + b.y) / 2 - 20)]) == .a)
        #expect(layout.buttons(at: [a]) == .a)
    }

    @Test func emptySpaceAndNoTouchesPressNothing() {
        #expect(Self.upright.buttons(at: [CGPoint]()).isEmpty)
        #expect(Self.upright.buttons(at: CGPoint(x: 201, y: 2)).isEmpty)
        #expect(Self.sideways.buttons(at: CGPoint(x: 437, y: 201)).isEmpty, "The middle of the picture is free")
    }

    @Test func sidewaysTheControlsSitAtTheSides() throws {
        let layout = Self.sideways
        #expect(layout.pad.center.x < 874 * 0.25)
        #expect(try Self.center(of: .a, in: layout).x > 874 * 0.75)
        #expect(try Self.center(of: .b, in: layout).x > 874 * 0.75)
    }
}
