@testable import Arcfold
import CoreGraphics
import FoldLayout
import Testing

/// The case of the console around the screens (ADR 0007), in the poses the
/// Simulator reports for the GBA and the DS: every screen sits in a bezel,
/// no key stands on one, the fold of the device is the hinge, and on the
/// outer display the DS has a hinge of its own with L and R at its ends.
/// A control over a screen stays glass; every other one is a key.
struct ConsoleCaseTests {
    typealias Pose = DuoGeometries.Pose

    static let poses = DuoGeometries.measuredPoses + DuoGeometries.largerScreenPoses

    /// Every geometry of the tests with both systems.
    static let everyPose = DuoGeometries.everyPose

    static func parts(_ pose: Pose, controls: Bool = true) -> (layout: GameLayout, console: CaseLayout, keys: TouchLayout?) {
        let layout = GameLayout(system: pose.system.screens, geometry: pose.geometry, showsTouchControls: controls)
        let keys = layout.controls.map { TouchLayout(zones: $0, scale: pose.geometry.scale, hasXYButtons: pose.system.hasXYButtons,
                                                       limits: TouchLayout.Limits(geometry: pose.geometry)) }
        return (layout, CaseLayout(layout: layout, geometry: pose.geometry), keys)
    }

    /// Every screen sits in a bezel, no key stands on one, and a hinge of
    /// the console's own cuts no screen, in every geometry of the tests.
    /// A bezel never leaves the view at the sides: where it does not fit
    /// beside a screen, it ends square at the edge.
    @Test(arguments: everyPose)
    func everyScreenSitsInABezelAndNoKeyStandsOnOne(_ pose: Pose) throws {
        let (layout, console, keys) = Self.parts(pose)
        let controls = try #require(keys)
        let view = CGRect(origin: .zero, size: console.size)
        #expect(console.size == pose.geometry.container.points(scale: pose.geometry.scale))
        #expect(console.screens == layout.screens.map { $0.destination.points(scale: pose.geometry.scale) })
        for screen in console.screens {
            #expect(console.bezels.contains { $0.frame.insetBy(dx: -0.01, dy: -0.01).contains(screen) }, "no bezel around \(screen)")
        }
        for bezel in console.bezels {
            #expect(bezel.frame.minX >= view.minX && bezel.frame.maxX <= view.maxX, "\(pose): the bezel \(bezel.frame) leaves the view")
            #expect(bezel.endsAtLeftEdge == (bezel.frame.minX == view.minX && console.screens.contains { $0.minX - ConsoleSkin.bezelWidth < view.minX }))
            #expect(bezel.endsAtRightEdge == (bezel.frame.maxX == view.maxX && console.screens.contains { $0.maxX + ConsoleSkin.bezelWidth > view.maxX }))
        }
        if let hinge = console.hinge, hinge.kind == .bar {
            for screen in console.screens {
                #expect(!hinge.frame.intersects(screen), "\(pose): the hinge \(hinge.frame) cuts \(screen)")
            }
        }
        // L and R lie across the bezel where the console has a hinge of
        // its own; every other key stands clear of every bezel.
        let hasOwnHinge = console.hinge?.kind == .bar
        var frames = [("pad", controls.pad.frame), ("menu", controls.pauseButton)]
        frames += controls.buttons.filter { !(hasOwnHinge && $0.shape == .capsule) }.map { ($0.label, $0.frame) }
        for (name, frame) in frames {
            for bezel in console.bezels {
                #expect(!bezel.frame.intersects(frame), "\(name) \(frame) stands on the bezel \(bezel.frame)")
            }
        }
    }

    /// On the inner display the fold is the hinge: where the division
    /// region is, drawn bent while the device is folded there.
    @Test(arguments: DuoGeometries.measuredPoses.filter { $0.geometry.fold != nil })
    func theFoldOfTheDeviceIsTheHinge(_ pose: Pose) throws {
        let console = Self.parts(pose).console
        let fold = try #require(pose.geometry.fold).points(scale: pose.geometry.scale)
        let hinge = try #require(console.hinge)
        #expect(hinge.kind == .fold && hinge.frame == fold)
        #expect(hinge.isBent == pose.geometry.isFoldActive)
        #expect(hinge.isHorizontal == (fold.width > fold.height))
    }

    /// On the outer display the DS has a hinge of its own: a barrel between
    /// L and R, as high as they are and 4 pt from each. Upright it lies
    /// across one bezel that holds both screens; sideways the bezel of both
    /// screens ends at its row. The GBA has none.
    @Test func onTheOuterDisplayTheDSHasAHingeOfItsOwn() throws {
        for pose in DuoGeometries.measuredPoses.filter({ $0.geometry.fold == nil }) {
            let (_, console, keys) = Self.parts(pose)
            guard pose.system == .ds else {
                #expect(console.hinge == nil, "\(pose)")
                continue
            }
            let controls = try #require(keys)
            let hinge = try #require(console.hinge)
            let l = try #require(controls.buttons.first { $0.label == "L" }).frame
            let r = try #require(controls.buttons.first { $0.label == "R" }).frame
            #expect(hinge.kind == .bar && hinge.isHorizontal, "\(pose)")
            #expect(l.height == TouchLayout.shoulderHeight && r.height == l.height, "\(pose)")
            #expect(hinge.frame.minY == l.minY && hinge.frame.maxY == l.maxY, "\(pose)")
            #expect(abs(hinge.frame.minX - (l.maxX + CaseLayout.hingeGap)) < 0.01, "\(pose)")
            #expect(abs(hinge.frame.maxX - (r.minX - CaseLayout.hingeGap)) < 0.01, "\(pose)")
            #expect(console.bezels.count == 1, "\(pose): one bezel for both screens")
            let bezel = try #require(console.bezels.first).frame
            if pose.geometry.container.isLandscape {
                #expect(bezel.maxY == hinge.frame.minY, "\(pose): the bezel ends at the hinge")
            } else {
                #expect(bezel.minY < hinge.frame.minY && bezel.maxY > hinge.frame.maxY, "\(pose): the hinge lies across the bezel")
            }
        }
    }

    /// The slim case of the DS beside the vertical bar: L and R are the ends
    /// of a hinge of 20 pt and draw inside it, while what takes their touches
    /// reaches 24 pt above it, over the upper screen and never on the touch
    /// screen. The bezel ends between the touch screen and the keys below it.
    @Test func theSlimCaseHasAHingeWithLAndRAsItsEnds() throws {
        let pose = DuoGeometries.largerScreenPoses[0]
        let (layout, console, keys) = Self.parts(pose)
        let controls = try #require(keys)
        let hinge = try #require(console.hinge)
        let screens = console.screens
        #expect(layout.screens.map(\.scale) == [4, 4])
        #expect(screens[1].minY - screens[0].maxY == 20)
        for label in ["L", "R"] {
            let button = try #require(controls.buttons.first { $0.label == label })
            #expect(button.frame.minY >= screens[0].maxY && button.frame.maxY <= screens[1].minY, "\(label) draws in the hinge")
            #expect(button.target.height == 44 && button.target.contains(button.frame), "\(label)")
            #expect(button.target.intersects(screens[0]) && !button.target.intersects(screens[1]), "\(label)")
            #expect(ConsoleControls.standsInCase(button.frame, screens: screens), "\(label) is a key")
            #expect(controls.buttons(at: CGPoint(x: button.frame.midX, y: button.frame.midY)) == button.buttons)
            #expect(controls.buttons(at: CGPoint(x: button.target.midX, y: button.target.minY + 4)) == button.buttons,
                    "\(label) takes touches above the hinge")
        }
        #expect(hinge.frame.minY > screens[0].maxY && hinge.frame.maxY < screens[1].minY)
        let bezel = try #require(console.bezels.first).frame
        #expect(console.bezels.count == 1 && bezel.maxY > screens[1].maxY && bezel.maxY < controls.pad.frame.minY)
    }

    /// With a controller the console has no touch controls and no hinge of
    /// its own; the fold stays the hinge. Every screen still sits in a
    /// bezel, and the menu button stays off bezels, the fold and the camera.
    @Test(arguments: everyPose)
    func withAControllerTheConsoleHasNoHingeOfItsOwn(_ pose: Pose) throws {
        let console = Self.parts(pose, controls: false).console
        #expect(console.hinge?.kind != .bar)
        #expect((console.hinge != nil) == (pose.geometry.fold.map { $0.width > 0 && $0.height > 0 } == true))
        for screen in console.screens {
            #expect(console.bezels.contains { $0.frame.insetBy(dx: -0.01, dy: -0.01).contains(screen) }, "\(pose): no bezel around \(screen)")
        }
        // The menu button alone in its corner: a small button of the case
        // clear of every bezel, or glass inside a picture, never on the
        // fold or the camera.
        let layout = GameLayout(system: pose.system.screens, geometry: pose.geometry, showsTouchControls: false)
        let pause = try #require(layout.pauseButton).points(scale: pose.geometry.scale)
        let overAPicture = console.screens.contains { $0.contains(pause) }
        #expect(overAPicture || !console.bezels.contains { $0.frame.intersects(pause) }, "\(pose): the menu button \(pause) on a bezel")
        if let fold = console.hinge?.frame {
            #expect(!fold.intersects(pause), "\(pose): the menu button \(pause) on the hinge")
        }
        for camera in pose.geometry.occlusions.map({ $0.points(scale: pose.geometry.scale) }) {
            #expect(!camera.intersects(pause), "\(pose): the menu button \(pause) on the camera")
        }
    }

    /// The GBA upright on an iPhone 402 pt wide: 5×, 1 pt from each edge,
    /// too close for the bezel at the sides. The picture runs from edge to
    /// edge, and the bezel is a band across the view, square at both ends.
    @Test func whereTheBezelDoesNotFitBesideThePictureItIsABand() throws {
        let geometry = DuoGeometries.iPhones[2].upright
        let console = Self.parts(Pose(name: "upright", system: .gba, geometry: geometry)).console
        let screen = try #require(console.screens.first)
        #expect(screen.minX == 1 && screen.width == 400)
        let bezel = try #require(console.bezels.first)
        #expect(console.bezels.count == 1)
        #expect(bezel.frame == CGRect(x: 0, y: screen.minY - 8, width: 402, height: screen.height + 16))
        #expect(bezel.endsAtLeftEdge && bezel.endsAtRightEdge)
        // On the Duo every bezel fits beside its screens.
        for pose in Self.poses {
            #expect(Self.parts(pose).console.bezels.allSatisfy { !$0.endsAtLeftEdge && !$0.endsAtRightEdge }, "\(pose)")
        }
    }

    /// A key throws nothing on a screen: its well touches none, and where a
    /// screen begins within the reach of its shadow below it, the key ends
    /// flush with its well, without light or shadow beyond it. L and R in
    /// the hinge of the DS stand like that, in both cases of the console.
    @Test(arguments: everyPose)
    func noKeyThrowsAnythingOnAScreen(_ pose: Pose) throws {
        let (_, console, keys) = Self.parts(pose)
        let controls = try #require(keys)
        let screens = console.screens
        var frames: [(String, CGRect, CGFloat)] = [("pad", controls.pad.frame, 1), ("menu", controls.pauseButton, 1)]
        frames += controls.buttons.map { ($0.label, $0.frame, ConsoleKey.relief(of: $0)) }
        for (name, frame, relief) in frames where ConsoleControls.standsInCase(frame, screens: screens) {
            let well = frame.insetBy(dx: -ConsoleSkin.wellWidth * relief, dy: -ConsoleSkin.wellWidth * relief)
            #expect(!screens.contains { $0.intersects(well) }, "\(pose): the well of \(name) \(well) touches a screen")
            let shade = CGRect(x: frame.minX - ConsoleSkin.capReach, y: frame.maxY,
                               width: frame.width + 2 * ConsoleSkin.capReach, height: ConsoleSkin.capReach)
            if screens.contains(where: { $0.intersects(shade) }) {
                #expect(ConsoleControls.standsRightAboveAScreen(frame, screens: screens), "\(pose): \(name) throws its shadow on a screen")
            }
        }
    }

    @Test(arguments: DuoGeometries.measuredPoses.filter { $0.system == .ds && $0.geometry.fold == nil && !$0.geometry.container.isLandscape }
        + DuoGeometries.largerScreenPoses.prefix(1))
    func lAndRInTheHingeEndFlushAboveTheTouchScreen(_ pose: Pose) throws {
        let (_, console, keys) = Self.parts(pose)
        let controls = try #require(keys)
        let touch = console.screens[1]
        for label in ["L", "R"] {
            let frame = try #require(controls.buttons.first { $0.label == label }).frame
            #expect(ConsoleControls.standsRightAboveAScreen(frame, screens: console.screens), "\(pose): \(label)")
            let button = try #require(controls.buttons.first { $0.label == label })
            #expect(abs(frame.maxY + ConsoleSkin.wellWidth * ConsoleKey.relief(of: button) - touch.minY) < 0.01,
                    "\(pose): \(label) \(frame) above \(touch)")
        }
    }

    /// Measures that the layout and the drawing both use are one value.
    @Test func doubledMeasuresAreCoupled() {
        #expect(ConsoleSkin.bezelWidth == CGFloat(LayoutMetrics.standard.bezel))
        #expect(TouchLayout.shoulderHeight == CGFloat(LayoutMetrics.standard.shoulderHeight))
        #expect(TouchLayout.rowHeight == CGFloat(LayoutMetrics.standard.menuRow))
    }

    /// The camera of the outer display gets a dish of the case, and the
    /// speaker opposite it mirrors it. Both stay clear of the bezels. Where
    /// the screens begin at the top, as in the slim case, there is no room
    /// for the speaker.
    @Test func theCameraGetsADishAndTheSpeakerMirrorsIt() throws {
        for system in [GameSystem.gba, .ds] {
            var geometry = DuoGeometries.closed(barOnTop: true)
            geometry.occlusions = DuoGeometries.outerOcclusions
            let console = Self.parts(Pose(name: "closed", system: system, geometry: geometry)).console
            let lens = try #require(console.lens)
            let speaker = try #require(console.speaker)
            #expect(lens == DuoGeometries.outerOcclusions[0].points(scale: 3))
            #expect(speaker.minY == lens.minY && speaker.size == lens.size)
            #expect(abs(speaker.minX - (console.size.width - lens.maxX)) < 0.01)
            for hole in [lens, speaker] {
                let dish = hole.insetBy(dx: -ConsoleSkin.lensRing, dy: -ConsoleSkin.lensRing)
                #expect(CGRect(origin: .zero, size: console.size).contains(dish))
                #expect(!console.bezels.contains { $0.frame.intersects(dish) }, "\(system.name): the dish \(dish) touches a bezel")
            }
        }
        var slim = DuoGeometries.closed(barOnTop: false)
        slim.occlusions = DuoGeometries.outerOcclusions
        let console = Self.parts(Pose(name: "closed, larger screens", system: .ds, geometry: slim)).console
        #expect(console.lens != nil && console.speaker == nil)
        // No camera in the view: no dish.
        #expect(Self.parts(DuoGeometries.measuredPoses[0]).console.lens == nil)
    }

    /// A control that lies over a screen stays in-game glass, every other
    /// one is a key in the case: a window of 340 × 300 pt, too narrow for a
    /// handheld at any scale, puts pad, face buttons, L and R of the GBA
    /// over the picture and Select and Start below it.
    @Test func controlsOverAScreenAreGlassAndTheOthersKeys() throws {
        let narrow = FoldGeometry(container: PixelSize(width: 1020, height: 900))
        let gba = GameLayout(system: SystemScreens.gba, geometry: narrow, showsTouchControls: true)
        let controls = TouchLayout(zones: try #require(gba.controls), scale: 3, hasXYButtons: false)
        let picture = gba.screens.map { $0.destination.points(scale: 3) }
        for button in controls.buttons {
            let isKey = ["Select", "Start"].contains(button.label)
            #expect(ConsoleControls.standsInCase(button.frame, screens: picture) == isKey, "\(button.label)")
            #expect(GlassBackdrop.under(button.frame, screens: picture) == (isKey ? .deck : .picture), "\(button.label)")
        }
        #expect(!ConsoleControls.standsInCase(controls.pad.frame, screens: picture))
        // In the poses the Simulator reports, every control is a key.
        for pose in Self.poses {
            let (_, console, keys) = Self.parts(pose)
            let controls = try #require(keys)
            #expect(ConsoleControls.standsInCase(controls.pad.frame, screens: console.screens), "\(pose): pad")
            #expect(ConsoleControls.standsInCase(controls.pauseButton, screens: console.screens), "\(pose): menu")
            for button in controls.buttons {
                #expect(ConsoleControls.standsInCase(button.frame, screens: console.screens), "\(pose): \(button.label)")
            }
        }
    }
}
