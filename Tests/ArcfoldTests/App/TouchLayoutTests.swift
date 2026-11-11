@testable import Arcfold
import CoreGraphics
import FoldLayout
import LibretroKit
import Testing

/// The touch mask as a pure function, without a session (ADR 0005, section 7),
/// built from the zones of FoldLayout (ADR 0006).
struct TouchLayoutTests {
    /// The outer display of the Duo Simulator: the GBA moves the vertical bar
    /// to the top, the DS keeps it at the side (ADR 0006, section 7).
    static let gbaClosed = FoldGeometry(container: PixelSize(width: 1398, height: 2034), safeArea: PixelInsets(top: 246, bottom: 102))
    static let dsClosed = FoldGeometry(container: PixelSize(width: 1398, height: 2034), safeArea: PixelInsets(bottom: 102, right: 252))
    static let dsTabletop = FoldGeometry(container: PixelSize(width: 2007, height: 2853),
                                         fold: PixelRect(x: 0, y: 1402, width: 2007, height: 48), isFoldActive: true)
    static let gbaBook = FoldGeometry(container: PixelSize(width: 2853, height: 2007),
                                      fold: PixelRect(x: 1402, y: 0, width: 48, height: 2007), isFoldActive: true)

    struct Case: Sendable, CustomTestStringConvertible {
        let name: String
        let system: GameSystem
        let geometry: FoldGeometry
        var testDescription: String { name }

        var gameLayout: GameLayout {
            GameLayout(system: system.screens, geometry: geometry, showsTouchControls: true)
        }

        var layout: TouchLayout {
            TouchLayout(zones: gameLayout.controls!, scale: geometry.scale, hasXYButtons: system.hasXYButtons)
        }

        /// The touch screen in points, if the system has one.
        var touchScreen: CGRect? {
            gameLayout.touchScreen.map { $0.destination.points(scale: geometry.scale) }
        }
    }

    /// The first four are fixed, tests name them by index; the six poses the
    /// Simulator reports follow for both systems.
    static let cases = [
        Case(name: "GBA closed", system: .gba, geometry: gbaClosed),
        Case(name: "DS closed", system: .ds, geometry: dsClosed),
        Case(name: "DS tabletop", system: .ds, geometry: dsTabletop),
        Case(name: "GBA book", system: .gba, geometry: gbaBook),
    ] + measured

    static let measured = DuoGeometries.measuredPoses.map {
        Case(name: "measured: \($0.description)", system: $0.system, geometry: $0.geometry)
    }

    /// The frame around the face buttons.
    static func faceBox(_ layout: TouchLayout) -> CGRect {
        layout.buttons.filter { !$0.buttons.isDisjoint(with: [.a, .b, .x, .y]) }
            .reduce(CGRect.null) { $0.union($1.frame) }
    }

    /// Select, Start and the pause button.
    static func menuFrames(_ layout: TouchLayout) -> [(name: String, frame: CGRect)] {
        layout.buttons.filter { !$0.buttons.isDisjoint(with: [.select, .start]) }.map { ($0.label, $0.frame) }
            + [("pause", layout.pauseButton)]
    }

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

    @Test(arguments: cases)
    func everyButtonPressesItselfAtItsCentre(_ testCase: Case) throws {
        let layout = testCase.layout
        let expected = testCase.system.hasXYButtons
            ? ["A", "B", "X", "Y", "L", "R", "Select", "Start"] : ["A", "B", "L", "R", "Select", "Start"]
        #expect(layout.buttons.map(\.label) == expected)
        for button in layout.buttons {
            let point = try Self.center(of: button.buttons, in: layout)
            #expect(layout.buttons(at: point) == button.buttons, "\(button.label)")
        }
    }

    /// Controls never overlap each other, and none lies on the touch screen.
    /// Round controls overlap when their circles do, not their frames: the
    /// diamond of the DS puts the corners of the frames into each other.
    @Test(arguments: cases)
    func controlsKeepClearOfEachOtherAndOfTheTouchScreen(_ testCase: Case) {
        let layout = testCase.layout
        let padFrame = CGRect(x: layout.pad.center.x - layout.pad.radius, y: layout.pad.center.y - layout.pad.radius,
                              width: 2 * layout.pad.radius, height: 2 * layout.pad.radius)
        let frames = [("pad", padFrame, true), ("pause", layout.pauseButton, false)]
            + layout.buttons.map { ($0.label, $0.frame, $0.shape == .circle) }
        func overlap(_ a: (String, CGRect, Bool), _ b: (String, CGRect, Bool)) -> Bool {
            guard a.2, b.2 else { return a.1.intersects(b.1) }
            let distance = hypot(a.1.midX - b.1.midX, a.1.midY - b.1.midY)
            return distance < (a.1.width + b.1.width) / 2
        }
        for (i, first) in frames.enumerated() {
            for second in frames[(i + 1)...] {
                #expect(!overlap(first, second), "\(first.0) overlaps \(second.0)")
            }
        }
        if let touchScreen = testCase.touchScreen {
            for (name, frame, _) in frames {
                #expect(!frame.intersects(touchScreen), "\(name) on the touch screen")
            }
        }
        #expect(layout.pad.radius >= 30)
    }

    @Test func thePadHasEightSectors() {
        let layout = Self.cases[0].layout
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
        let layout = Self.cases[0].layout
        #expect(layout.buttons(at: layout.pad.center).isEmpty)
        #expect(layout.buttons(at: Self.padPoint(layout, degrees: 90, share: 0.2)).isEmpty)
        #expect(layout.buttons(at: Self.padPoint(layout, degrees: 90, share: 0.35)) == .up)
        // The pad reaches a bit beyond its circle where no button is, then nothing.
        #expect(layout.buttons(at: Self.padPoint(layout, degrees: 180, share: 1.3)) == .left)
        #expect(layout.buttons(at: Self.padPoint(layout, degrees: 180, share: 1.5)).isEmpty)
    }

    @Test func everyFingerCounts() throws {
        let layout = Self.cases[1].layout
        let points = [
            Self.padPoint(layout, degrees: 90),
            try Self.center(of: .a, in: layout),
            try Self.center(of: .x, in: layout),
        ]
        #expect(layout.buttons(at: points) == [.up, .a, .x])
    }

    @Test func aFingerSlidesFromOneButtonToTheNext() throws {
        let layout = Self.cases[0].layout
        let b = try Self.center(of: .b, in: layout)
        let a = try Self.center(of: .a, in: layout)
        #expect(layout.buttons(at: [b]) == .b)
        #expect(layout.buttons(at: [CGPoint(x: b.x + (a.x - b.x) * 0.8, y: b.y + (a.y - b.y) * 0.8)]) == .a)
        #expect(layout.buttons(at: [a]) == .a)
    }

    @Test func emptySpaceAndNoTouchesPressNothing() {
        let layout = Self.cases[0].layout
        #expect(layout.buttons(at: [CGPoint]()).isEmpty)
        // The middle of the picture.
        #expect(layout.buttons(at: CGPoint(x: 233, y: 215)).isEmpty)
    }

    /// The DS on the closed Duo: the band below the screens holds the pad,
    /// Select, Start and the pause button in a column and the face buttons
    /// side by side; L and R lie over the lower corners of the upper screen,
    /// below the top edge guard (ADR 0006, section 8 and "Nachbesserungen
    /// nach der Prüfung").
    @Test func theDSClosedLayout() throws {
        let testCase = Self.cases[1]
        let layout = testCase.layout
        let touchScreen = try #require(testCase.touchScreen)
        let select = try Self.center(of: .select, in: layout)
        let start = try Self.center(of: .start, in: layout)
        let a = try Self.center(of: .a, in: layout)
        let l = try Self.center(of: .l, in: layout)
        #expect(layout.pad.center.y > touchScreen.maxY && select.y > touchScreen.maxY)
        #expect(layout.pad.center.x < select.x && select.x == start.x && start.x < a.x)
        #expect(select.y < start.y && layout.pauseButton.minY > start.y, "Select, Start and the pause button from top to bottom")
        #expect(l.y < touchScreen.minY && l.y > touchScreen.minY - 60, "Just above the touch screen")
        #expect(layout.buttons.allSatisfy { $0.frame.minY >= 64 }, "Nothing in the top edge guard")
        #expect(layout.overlapsScreen)
    }

    /// Pad and face buttons are level in every pose, and so are L and R.
    @Test(arguments: measured)
    func padAndFaceButtonsAreLevel(_ testCase: Case) throws {
        let layout = testCase.layout
        #expect(abs(Self.faceBox(layout).midY - layout.pad.center.y) < 0.5,
                "face buttons at \(Self.faceBox(layout).midY), pad at \(layout.pad.center.y)")
        #expect(try Self.center(of: .l, in: layout).y == Self.center(of: .r, in: layout).y)
    }

    /// Select, Start and the pause button sit in the middle below the picture:
    /// level with each other or in one column, never below the face buttons
    /// or the pad, and at least 24 pt away from both, so that no thumb hits
    /// them by accident.
    @Test(arguments: measured)
    func selectStartAndPauseKeepClearOfPadAndFaceButtons(_ testCase: Case) throws {
        let layout = testCase.layout
        let menu = Self.menuFrames(layout)
        let face = layout.buttons.filter { !$0.buttons.isDisjoint(with: [.a, .b, .x, .y]) }
        let faceBox = Self.faceBox(layout)
        let padBox = CGRect(x: layout.pad.center.x - layout.pad.radius, y: layout.pad.center.y - layout.pad.radius,
                            width: 2 * layout.pad.radius, height: 2 * layout.pad.radius)
        func gap(_ a: CGRect, _ b: CGRect) -> CGFloat {
            hypot(max(0, a.minX - b.maxX, b.minX - a.maxX), max(0, a.minY - b.maxY, b.minY - a.maxY))
        }
        for (name, frame) in menu {
            #expect(frame.height >= TouchLayout.smallestRowHeight, "\(name) is \(frame.height) pt high")
            for button in face {
                #expect(gap(frame, button.frame) >= 24, "\(name) is \(gap(frame, button.frame)) pt from \(button.label)")
            }
            let nearest = CGPoint(x: min(max(layout.pad.center.x, frame.minX), frame.maxX),
                                  y: min(max(layout.pad.center.y, frame.minY), frame.maxY))
            let fromPad = hypot(nearest.x - layout.pad.center.x, nearest.y - layout.pad.center.y) - layout.pad.radius
            #expect(fromPad >= 24, "\(name) is \(fromPad) pt from the pad")
            for (control, box) in [("the face buttons", faceBox), ("the pad", padBox)] {
                let below = frame.minY >= box.midY && frame.minX < box.maxX && frame.maxX > box.minX
                #expect(!below, "\(name) below \(control)")
            }
        }
        let rows = Set(menu.map { ($0.frame.midY * 2).rounded() })
        let columns = Set(menu.map { ($0.frame.midX * 2).rounded() })
        #expect(rows.count == 1 || columns.count == 1, "one row or one column: \(menu)")
    }

    /// Open and in the book the fold runs through the middle below the
    /// picture: Select and the pause button end 8 pt before it, Start begins
    /// 8 pt behind it.
    @Test(arguments: measured.filter { $0.name.hasSuffix("open") || $0.name.hasSuffix("book") })
    func theMenuFlanksAFoldFromTopToBottom(_ testCase: Case) throws {
        let layout = testCase.layout
        let fold = try #require(testCase.geometry.fold).points(scale: testCase.geometry.scale)
        let select = try #require(layout.buttons.first { $0.buttons == .select }).frame
        let start = try #require(layout.buttons.first { $0.buttons == .start }).frame
        #expect(select.maxX < layout.pauseButton.minX)
        #expect(abs(layout.pauseButton.maxX - (fold.minX - 8)) < 0.5)
        #expect(abs(start.minX - (fold.maxX + 8)) < 0.5)
        #expect(select.midY == start.midY && start.midY == layout.pauseButton.midY)
    }
}
