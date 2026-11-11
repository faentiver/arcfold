@testable import Arcfold
import CoreGraphics
import FoldLayout
import Testing

/// The deck and the plates of the glass controls on the layouts of M2 (ADR
/// 0007, rule R3): the deck lies behind every control that covers no screen
/// and never under a screen or across the fold; a control over a screen gets
/// the plate for the picture, every other one the plate for the deck.
struct ControlDeckTests {
    struct Case: Sendable, CustomTestStringConvertible {
        let system: GameSystem
        let geometry: DuoGeometries.Case
        var testDescription: String { "\(system.name), \(geometry.name)" }

        var layout: GameLayout {
            GameLayout(system: system.screens, geometry: geometry.geometry, showsTouchControls: true)
        }
    }

    static let cases = DuoGeometries.cases.flatMap { geometry in
        DuoGeometries.systems.map { Case(system: $0.system, geometry: geometry) }
    }

    @Test(arguments: cases)
    func theDeckLiesBehindTheControlsAndNeverUnderAScreen(_ testCase: Case) throws {
        let layout = testCase.layout
        let geometry = testCase.geometry.geometry
        let zones = try #require(layout.controls)
        let areas = DeckLayout.areas(of: layout, in: geometry)
        let screens = layout.screens.map(\.destination)
        for area in areas {
            #expect(geometry.bounds.contains(area), "\(area) leaves the view")
            for screen in screens {
                #expect(!area.intersects(screen), "the deck \(area) lies under the screen \(screen)")
            }
            if let fold = geometry.fold, !fold.isEmpty {
                #expect(!area.intersects(fold), "the deck \(area) crosses the fold \(fold)")
            }
        }
        // Every zone that covers no screen lies on the deck.
        for zone in zones.all where !zone.isEmpty && !screens.contains(where: { zone.intersects($0) }) {
            #expect(areas.contains { $0.contains(zone) }, "the zone \(zone) has no deck: \(areas)")
        }
    }

    @Test func withoutTouchControlsThereIsNoDeck() {
        for testCase in Self.cases {
            let layout = GameLayout(system: testCase.system.screens, geometry: testCase.geometry.geometry,
                                    showsTouchControls: false)
            #expect(DeckLayout.areas(of: layout, in: testCase.geometry.geometry).isEmpty)
        }
    }

    /// The closed Duo upright: the deck is the band below the screens, the
    /// whole width of the view, as the deck below the picture of ADR 0007.
    @Test func closedUprightTheDeckIsTheBandBelowTheScreens() throws {
        for (system, geometry) in [(GameSystem.gba, DuoGeometries.closed(barOnTop: true)),
                                   (GameSystem.ds, DuoGeometries.closed(barOnTop: false))] {
            let layout = GameLayout(system: system.screens, geometry: geometry, showsTouchControls: true)
            let areas = DeckLayout.areas(of: layout, in: geometry)
            let bottom = try #require(layout.screens.map(\.destination.maxY).max())
            #expect(areas == [PixelRect(x: 0, y: bottom, width: geometry.container.width, height: geometry.container.height - bottom)],
                    "\(system.name): \(areas)")
        }
    }

    /// Controls over a screen sit on the picture: L and R of the closed DS
    /// over the lower corners of the upper screen, and the pad, the face
    /// buttons, L and R of the GBA sideways when the columns lie over the
    /// picture. Select and Start lie below the picture there, on the deck.
    @Test func controlsOverAScreenGetThePictureAndTheOthersTheDeck() throws {
        let geometry = DuoGeometries.closed(barOnTop: false)
        let layout = GameLayout(system: SystemScreens.ds, geometry: geometry, showsTouchControls: true)
        let controls = TouchLayout(zones: try #require(layout.controls), scale: 3, hasXYButtons: true)
        let screens = layout.screens.map { $0.destination.points(scale: 3) }
        for button in controls.buttons {
            let expected: GlassBackdrop = ["L", "R"].contains(button.label) ? .picture : .deck
            #expect(GlassBackdrop.under(button.frame, screens: screens) == expected, "\(button.label)")
        }
        #expect(GlassBackdrop.under(controls.pad.frame, screens: screens) == .deck)

        let sideways = FoldGeometry(container: DuoGeometries.outerLandscape)
        let gba = GameLayout(system: SystemScreens.gba, geometry: sideways, showsTouchControls: true)
        let gbaControls = TouchLayout(zones: try #require(gba.controls), scale: 3, hasXYButtons: false)
        let picture = gba.screens.map { $0.destination.points(scale: 3) }
        for button in gbaControls.buttons {
            let expected: GlassBackdrop = ["Select", "Start"].contains(button.label) ? .deck : .picture
            #expect(GlassBackdrop.under(button.frame, screens: picture) == expected, "\(button.label)")
        }
        #expect(GlassBackdrop.under(gbaControls.pad.frame, screens: picture) == .picture)
        let bottom = gba.screens[0].destination.maxY
        #expect(DeckLayout.areas(of: gba, in: sideways) == [PixelRect(x: 0, y: bottom, width: 2034, height: 1398 - bottom)],
                "sideways the columns lie over the picture, the deck is the strip below it")
    }
}
