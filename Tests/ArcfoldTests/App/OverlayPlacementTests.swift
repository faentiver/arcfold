@testable import Arcfold
import CoreGraphics
import FoldLayout
import Testing

/// The overlays of a game on the layouts of M2 (ADR 0006, ADR 0007), for the
/// GBA and the DS in every geometry of `LayoutInvariantTests`, with touch
/// controls and with a controller: the pause button sits where GameLayout
/// puts it and takes touches on at least 44 × 44 pt below the top edge
/// guard. The notices and the status chip have `NoticePlacementTests`, the
/// debug overlay `DebugPlacementTests`, the failure message
/// `FailurePlacementTests`.
struct OverlayPlacementTests {
    struct Case: Sendable, CustomTestStringConvertible {
        let system: GameSystem
        let geometry: DuoGeometries.Case
        let showsControls: Bool
        var testDescription: String {
            "\(system.name), \(geometry.name), \(showsControls ? "touch controls" : "controller")"
        }

        var layout: GameLayout {
            GameLayout(system: system.screens, geometry: geometry.geometry, showsTouchControls: showsControls)
        }

        var controls: TouchLayout? {
            GameStage.controls(of: layout, scale: geometry.geometry.scale, system: system, shows: showsControls)
        }

        var placement: OverlayPlacement {
            OverlayPlacement(layout: layout, geometry: geometry.geometry, controls: controls)
        }

        func points(_ rect: PixelRect) -> CGRect {
            rect.points(scale: geometry.geometry.scale)
        }
    }

    static let cases = DuoGeometries.cases.flatMap { geometry in
        DuoGeometries.systems.flatMap { system in
            [true, false].map { Case(system: system.system, geometry: geometry, showsControls: $0) }
        }
    }

    /// Every area that presses a button, with its name.
    static func buttonAreas(_ controls: TouchLayout?) -> [(String, CGRect)] {
        controls?.buttons.map { button in
            let slop = min(button.frame.width, button.frame.height) * TouchLayout.buttonSlop
            return (button.label, button.frame.insetBy(dx: -slop, dy: -slop))
        } ?? []
    }

    static func intersects(_ rect: CGRect, circle center: CGPoint, radius: CGFloat) -> Bool {
        let x = min(max(center.x, rect.minX), rect.maxX)
        let y = min(max(center.y, rect.minY), rect.maxY)
        return hypot(x - center.x, y - center.y) < radius
    }

    /// Nothing that takes touches and no glass may lie under `rect`.
    static func checkClear(_ rect: CGRect, named name: String, in testCase: Case) {
        let placement = testCase.placement
        for (label, area) in buttonAreas(testCase.controls) {
            #expect(!rect.intersects(area), "\(name) covers \(label): \(rect) ∩ \(area)")
        }
        if let pad = testCase.controls?.pad {
            #expect(!intersects(rect, circle: pad.center, radius: pad.radius * TouchLayout.padReach), "\(name) covers the pad")
        }
        if let target = placement.pauseTarget {
            #expect(!rect.intersects(target), "\(name) covers the pause button \(target)")
        }
        if let touch = testCase.layout.touchScreen {
            #expect(!rect.intersects(testCase.points(touch.destination)), "\(name) lies on the touch screen")
        }
        if let fold = testCase.geometry.geometry.fold, !fold.isEmpty {
            #expect(!rect.intersects(testCase.points(fold)), "\(name) lies on the fold \(fold)")
        }
        #expect(placement.pictureArea.contains(rect), "\(name) leaves the picture \(placement.pictureArea): \(rect)")
    }

    @Test(arguments: cases)
    func thePauseButtonSitsWhereGameLayoutPutsItAndTakesTouchesBelowTheTopEdge(_ testCase: Case) throws {
        let placement = testCase.placement
        let pause = try #require(placement.pauseButton)
        let target = try #require(placement.pauseTarget)
        if let controls = testCase.controls {
            #expect(pause == controls.pauseButton, "with touch controls the menu row holds it")
            let menu = testCase.points(try #require(testCase.layout.controls).menu)
            #expect(menu.insetBy(dx: -0.5, dy: -0.5).contains(pause), "\(pause) leaves the menu zone \(menu)")
            for button in controls.buttons {
                #expect(!target.intersects(button.frame), "the pause button covers \(button.label)")
            }
        } else {
            #expect(pause == testCase.points(try #require(testCase.layout.pauseButton)))
        }
        #expect(target.width >= 44 && target.height >= 44 && target.contains(pause))
        let guardRow = CGFloat(GameLayout.firstInputRow(in: testCase.geometry.geometry)) / CGFloat(testCase.geometry.geometry.scale)
        #expect(target.minY >= guardRow - 0.001, "\(target) reaches into the top edge guard at \(guardRow)")
        if let touch = testCase.layout.touchScreen {
            #expect(!target.intersects(testCase.points(touch.destination)), "the pause button lies on the touch screen")
        }
        let geometry = testCase.geometry.geometry
        if geometry.isFoldActive, let fold = geometry.fold {
            #expect(!target.intersects(testCase.points(fold)), "the pause button lies on the active fold")
        }
    }

    /// The two faults of M1 stay fixed on the layouts of M2: sideways the
    /// pause button lies on no shoulder button, upright no notice lies over
    /// Select and Start (they are part of every check above, named here).
    @Test func theFaultsOfM1StayFixed() throws {
        let sideways = Case(system: .gba, geometry: DuoGeometries.cases[2], showsControls: true)
        let target = try #require(sideways.placement.pauseTarget)
        for (label, area) in Self.buttonAreas(sideways.controls) where ["L", "R"].contains(label) {
            #expect(!target.intersects(area), "sideways the pause button covers \(label)")
        }
        for index in [0, 1] {
            let upright = Case(system: .gba, geometry: DuoGeometries.cases[index], showsControls: true)
            for (label, area) in Self.buttonAreas(upright.controls) where ["Select", "Start"].contains(label) {
                #expect(!upright.placement.noticeColumn.intersects(area), "upright a notice covers \(label)")
            }
        }
    }
}
