@testable import Arcfold
import CoreGraphics
import FoldLayout
import LibretroKit
import Testing

/// The touch mask as a pure function, without a session (ADR 0005, section 7),
/// built from the zones of FoldLayout (ADR 0006).
struct TouchLayoutTests {
    /// The outer display of the Duo Simulator: both systems move the
    /// vertical bar to the top (ADR 0006, section 7; ADR 0007).
    static let gbaClosed = FoldGeometry(container: PixelSize(width: 1398, height: 2034), safeArea: PixelInsets(top: 246, bottom: 102))
    static let dsClosed = gbaClosed
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
            TouchLayout(zones: gameLayout.controls!, scale: geometry.scale, hasXYButtons: system.hasXYButtons,
                        limits: TouchLayout.Limits(geometry: geometry))
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

    static let measured = (DuoGeometries.measuredPoses + DuoGeometries.largerScreenPoses).map {
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

    /// The DS on the closed Duo: the hinge of the console lies between the
    /// screens with L and R at its ends; the band below the touch screen
    /// holds the pad, Select, Start and the pause button in a column and the
    /// face buttons side by side. Nothing lies over a screen (ADR 0007).
    @Test func theDSClosedLayout() throws {
        let testCase = Self.cases[1]
        let layout = testCase.layout
        let touchScreen = try #require(testCase.touchScreen)
        let upper = testCase.gameLayout.screens[0].destination.points(scale: 3)
        let select = try Self.center(of: .select, in: layout)
        let start = try Self.center(of: .start, in: layout)
        let a = try Self.center(of: .a, in: layout)
        let l = try #require(layout.buttons.first { $0.buttons == .l }).frame
        let r = try #require(layout.buttons.first { $0.buttons == .r }).frame
        #expect(layout.pad.center.y > touchScreen.maxY && select.y > touchScreen.maxY)
        #expect(layout.pad.center.x < select.x && select.x == start.x && start.x < a.x)
        #expect(select.y < start.y && layout.pauseButton.minY > start.y, "Select, Start and the pause button from top to bottom")
        #expect(l.minY > upper.maxY && l.maxY < touchScreen.minY, "In the hinge between the screens")
        #expect(l.height == 40 && r.height == 40 && l.width == 100 && r.width == 100)
        #expect(abs(l.minX - layout.pad.frame.minX) < 0.01 && abs(r.maxX - Self.faceBox(layout).maxX) < 0.01,
                "On one line with pad and face buttons")
        #expect(layout.buttons.allSatisfy { $0.frame.minY >= 64 }, "Nothing in the top edge guard")
        #expect(!layout.overlapsScreen)
    }

    /// The sizes of the keys in the poses the Simulator reports (ADR 0007):
    /// L and R 40 pt high everywhere, the pad at least 110 pt, the face
    /// buttons of the DS at least 42 pt and those of the GBA at least 56 pt,
    /// Select, Start and the pause button at least 60 pt wide each and
    /// 44 pt high where they stand in a row.
    @Test(arguments: measured)
    func theKeysHaveTheirSizes(_ testCase: Case) throws {
        let layout = testCase.layout
        let isSlim = testCase.name.contains("closed, larger screens")
        for button in layout.buttons where button.shape == .capsule {
            #expect(button.frame.height == (isSlim ? 18 : 40), "\(button.label) is \(button.frame.height) pt high")
            #expect(button.target.height >= 40 && button.frame.width >= 80, "\(button.label)")
        }
        #expect(layout.pad.radius * 2 >= 110, "the pad is \(layout.pad.radius * 2) pt")
        for button in layout.buttons where button.shape == .circle {
            #expect(button.frame.width >= (testCase.system.hasXYButtons ? 42 : 56), "\(button.label) is \(button.frame.width) pt")
        }
        let menu = Self.menuFrames(layout)
        let isRow = Set(menu.map { ($0.frame.midY * 2).rounded() }).count == 1
        for (name, frame) in menu {
            #expect(frame.width >= 60 && frame.height >= (isRow ? 44 : TouchLayout.smallestRowHeight), "\(name) is \(frame.size)")
        }
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

    #if DEBUG
    /// The displays without a fold, held upright: the closed Duo and the
    /// iPhones, with the GBA.
    static let uprightWithoutAFold = [Case(name: "GBA closed Duo", system: .gba, geometry: gbaClosed)]
        + DuoGeometries.iPhones.map { Case(name: "GBA \($0.name)", system: .gba, geometry: $0.upright) }

    /// Upright, the book a debug build simulates on a display without a
    /// fold (`-ArcfoldFoldOverride book`, 16 pt from top to bottom through
    /// the middle) keeps every key of the GBA: on 402 pt the grips of the
    /// handheld left the menu 16 pt on each side of the fold, Select had
    /// no width and was gone, and the menu button took touches on the
    /// fold. With the controls below the picture Select and the menu
    /// button end 8 pt before the fold and Start begins 8 pt behind it,
    /// each presses itself at its centre, and nothing takes a touch on the
    /// fold.
    @MainActor
    @Test(arguments: uprightWithoutAFold)
    func uprightTheSimulatedBookKeepsEveryKeyOfTheGBA(_ view: Case) throws {
        let testCase = Case(name: "\(view.name), simulated book", system: view.system,
                            geometry: FoldOverride.book.applied(to: view.geometry))
        let layout = testCase.layout
        let fold = try #require(testCase.geometry.fold).points(scale: testCase.geometry.scale)
        #expect(layout.buttons.map(\.label) == ["A", "B", "L", "R", "Select", "Start"])
        for button in layout.buttons {
            let point = try Self.center(of: button.buttons, in: layout)
            #expect(layout.buttons(at: point) == button.buttons, "\(button.label)")
            #expect(!layout.hitArea(of: button).intersects(fold), "\(button.label) takes touches on the fold")
        }
        let select = try #require(layout.buttons.first { $0.buttons == .select }).frame
        let start = try #require(layout.buttons.first { $0.buttons == .start }).frame
        let menu = layout.pauseButton
        #expect(select.maxX < menu.minX && abs(menu.maxX - (fold.minX - 8)) < 0.5 && abs(start.minX - (fold.maxX + 8)) < 0.5)
        #expect(select.midY == start.midY && start.midY == menu.midY)
        #expect(select.width >= 28 && start.width >= 28 && menu.width >= PauseButton.minimumTarget,
                "Select \(select.width), the menu button \(menu.width), Start \(start.width) pt")
        #expect(!OverlayPlacement.target(around: menu).intersects(fold), "The menu button takes touches on the fold")
        TouchLimitTests.expectClear(layout, testCase.name)
        #expect(layout.buttons(at: CGPoint(x: fold.midX, y: menu.midY)).isEmpty, "A touch on the fold between the parts")
        // The fold is the hinge of the case, the picture keeps its bezel
        // across it, and no key stands on the hinge or on the bezel.
        let console = CaseLayout(layout: testCase.gameLayout, geometry: testCase.geometry)
        #expect(console.hinge?.kind == .fold && console.hinge?.frame == fold)
        for (name, frame) in [("pad", layout.pad.frame), ("menu", menu)] + layout.buttons.map({ ($0.label, $0.frame) }) {
            #expect(!frame.intersects(fold), "\(name) \(frame) stands on the hinge")
            #expect(!console.bezels.contains { $0.frame.intersects(frame) }, "\(name) \(frame) stands on the bezel")
        }
    }
    #endif
}

/// What takes touches, over every geometry of the tests and both systems
/// (ADR 0006): the slop around a button and the reach of the pad end where
/// the zones end, at the first row that takes touches and at the active
/// fold; and the menu button never takes the touches of Select and Start.
struct TouchLimitTests {
    typealias Pose = DuoGeometries.Pose

    static let poses = DuoGeometries.everyPose

    static func layout(_ pose: Pose) throws -> TouchLayout {
        let layout = GameLayout(system: pose.system.screens, geometry: pose.geometry, showsTouchControls: true)
        return try #require(GameStage.controls(of: layout, geometry: pose.geometry, system: pose.system, shows: true))
    }

    /// No hit area with its slop lies above the first row that may take
    /// touches or in the region of the active fold, and every hit area
    /// holds what the button draws and its target. A touch there presses
    /// nothing, also not the pad by its reach.
    @Test(arguments: poses)
    func noHitAreaReachesTheTopEdgeGuardOrTheFold(_ pose: Pose) throws {
        let controls = try Self.layout(pose)
        let geometry = pose.geometry
        let top = CGFloat(GameLayout.firstInputRow(in: geometry)) / CGFloat(geometry.scale)
        let fold = geometry.isFoldActive ? geometry.fold?.points(scale: geometry.scale) : nil
        #expect(controls.limits.inputTop == top && controls.limits.fold == fold)
        for button in controls.buttons {
            let area = controls.hitArea(of: button)
            #expect(area.contains(button.target) && area.contains(button.frame), "\(pose): \(button.label)")
            #expect(area.minY >= top, "\(pose): \(button.label) takes touches from \(area.minY) pt, above \(top)")
            if let fold {
                let shared = area.intersection(fold)
                #expect(shared.isNull || shared.width <= 0 || shared.height <= 0,
                        "\(pose): \(button.label) \(area) reaches into the fold \(fold)")
            }
            let above = CGPoint(x: button.target.midX, y: top - 0.5)
            #expect(controls.buttons(at: above).isEmpty, "\(pose): \(button.label) above the top edge guard")
        }
        #expect(controls.buttons(at: CGPoint(x: controls.pad.center.x, y: top - 0.5)).isEmpty, "\(pose): the pad above the guard")
        if let fold, fold.width > 0, fold.height > 0 {
            for point in [CGPoint(x: fold.midX, y: fold.midY), CGPoint(x: fold.minX + 0.5, y: fold.minY + 0.5),
                          CGPoint(x: fold.maxX - 0.5, y: fold.maxY - 0.5)] {
                #expect(controls.buttons(at: point).isEmpty, "\(pose): a touch on the fold at \(point)")
            }
        }
    }

    /// The menu button takes touches on 44 × 44 pt around its cell; that
    /// never covers the target of Select or Start.
    @Test(arguments: poses)
    func theMenuButtonNeverTakesTheTouchesOfSelectAndStart(_ pose: Pose) throws {
        let controls = try Self.layout(pose)
        Self.expectClear(controls, "\(pose)")
    }

    /// Menu zones narrower than three whole cells and too low for the
    /// column, in one piece and divided: the cell of the menu button keeps
    /// 44 pt, Select and Start give way.
    @Test func inANarrowRowSelectAndStartGiveWay() throws {
        let pt = 3
        for width in stride(from: 120, through: 196, by: 4) {
            for height in [28, 36, 44] {
                for divided in [false, true] {
                    let menu = PixelRect(x: 300 * pt, y: 600 * pt, width: width * pt, height: height * pt)
                    let zones = ControlZones(
                        pad: PixelRect(x: 0, y: 0, width: 110 * pt, height: 110 * pt),
                        face: PixelRect(x: 600 * pt, y: 0, width: 110 * pt, height: 110 * pt),
                        leftShoulder: PixelRect(x: 0, y: 700 * pt, width: 100 * pt, height: 40 * pt),
                        rightShoulder: PixelRect(x: 600 * pt, y: 700 * pt, width: 100 * pt, height: 40 * pt),
                        menu: menu, menuTrailing: divided ? menu.offsetBy(x: (width + 40) * pt) : nil, overlapsScreen: false)
                    let controls = TouchLayout(zones: zones, scale: pt, hasXYButtons: false)
                    let name = "\(width) × \(height) pt\(divided ? ", divided" : "")"
                    #expect(controls.pauseButton.width >= PauseButton.minimumTarget, "\(name): \(controls.pauseButton)")
                    Self.expectClear(controls, name)
                    for label in ["Select", "Start"] {
                        let button = try #require(controls.buttons.first { $0.label == label }, "\(name): \(label)")
                        #expect(button.frame.width >= 30, "\(name): \(label) is \(button.frame.width) pt")
                    }
                }
            }
        }
    }

    static func expectClear(_ controls: TouchLayout, _ name: String) {
        let target = OverlayPlacement.target(around: controls.pauseButton)
        for button in controls.buttons where button.buttons == .select || button.buttons == .start {
            #expect(!target.intersects(button.target), "\(name): the menu button \(target) covers \(button.label) \(button.target)")
        }
    }
}

private extension PixelRect {
    func offsetBy(x dx: Int) -> PixelRect { PixelRect(x: x + dx, y: y, width: width, height: height) }
}
