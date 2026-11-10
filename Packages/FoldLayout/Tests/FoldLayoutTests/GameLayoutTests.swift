@testable import FoldLayout
import Testing

/// The pose follows from the division region alone (ADR 0006, section 7).
struct PostureTests {
    @Test func noFoldIsSingle() {
        #expect(Duo.closed(barOnTop: false).posture == .single)
        #expect(FoldGeometry(container: Duo.inner).posture == .single, "An iPhone without a hinge")
    }

    @Test func anInactiveFoldIsFlat() {
        #expect(Duo.foldAcross(band: 0, active: false).posture == .flat)
        #expect(Duo.foldDown(band: 0, active: false).posture == .flat)
        #expect(Duo.foldAcross(band: 16, active: false).posture == .flat)
    }

    @Test func anActiveFoldAcrossIsTabletopAndOneDownIsTheBookThatCountsAsFlat() {
        #expect(Duo.foldAcross(band: 16, active: true).posture == .tabletop)
        #expect(Duo.foldAcross(band: 0, active: true).posture == .tabletop, "Width 2007, height 0")
        #expect(Duo.foldDown(band: 16, active: true).posture == .flat, "Book counts as flat (plan, section 7)")
        #expect(Duo.foldDown(band: 0, active: true).posture == .flat)
    }

    @Test func aSquareFoldIsNoTabletop() {
        let geometry = FoldGeometry(container: Duo.inner, fold: PixelRect(x: 0, y: 0, width: 10, height: 10), isFoldActive: true)
        #expect(geometry.posture == .flat)
    }
}

/// Rules every layout keeps, over sizes of the Duo and an iPhone without a
/// hinge, upright and sideways, with and without the vertical bar, fold bands
/// of 0, 16, 32 and 64 pt, with and without margins, active and inactive,
/// with and without touch controls, with and without an occlusion region at
/// the top, for the GBA and the DS (ADR 0006).
struct LayoutInvariantTests {
    struct Case: Sendable, CustomTestStringConvertible {
        let name: String
        let geometry: FoldGeometry
        var testDescription: String { name }
    }

    static let cases: [Case] = {
        var all = [
            Case(name: "closed, bar at the side", geometry: Duo.closed(barOnTop: false)),
            Case(name: "closed, bar on top", geometry: Duo.closed(barOnTop: true)),
            Case(name: "closed, sideways", geometry: FoldGeometry(container: Duo.outerLandscape)),
            Case(name: "closed, sideways with the bar",
                 geometry: FoldGeometry(container: Duo.outerLandscape, safeArea: PixelInsets(bottom: 63, right: 252))),
            Case(name: "iPhone upright", geometry: FoldGeometry(
                container: PixelSize(width: 1206, height: 2622), safeArea: PixelInsets(top: 186, bottom: 102))),
            Case(name: "iPhone sideways", geometry: FoldGeometry(
                container: PixelSize(width: 2622, height: 1206), safeArea: PixelInsets(left: 186, bottom: 63, right: 186))),
            Case(name: "plan, tabletop", geometry: FoldGeometry(
                container: PixelSize(width: 1878, height: 2670), fold: PixelRect(x: 0, y: 1335, width: 1878, height: 0),
                isFoldActive: true)),
            // A camera in a lower corner of the inner display (an assumption
            // until the device test): the pause button moves away from it.
            Case(name: "book with a camera", geometry: {
                var geometry = Duo.foldDown(band: 16, active: true)
                geometry.occlusions = [PixelRect(x: 2600, y: 1800, width: 253, height: 207)]
                return geometry
            }()),
            Case(name: "tabletop with a camera", geometry: {
                var geometry = Duo.foldAcross(band: 16, active: true)
                geometry.occlusions = [PixelRect(x: 1750, y: 2600, width: 257, height: 253)]
                return geometry
            }()),
        ]
        for band in [0, 16, 32, 64] {
            for margin in [0, 8] {
                for active in [false, true] {
                    let state = "\(band) pt, margins \(margin) pt, \(active ? "active" : "inactive")"
                    all.append(Case(name: "fold across \(state)", geometry: Duo.foldAcross(band: band, margin: margin, active: active)))
                    all.append(Case(name: "fold down \(state)", geometry: Duo.foldDown(band: band, margin: margin, active: active)))
                }
            }
        }
        return all
    }()

    @Test(arguments: cases)
    func everyRuleHolds(_ testCase: Case) {
        for (systemName, system) in [("GBA", SystemScreens.gba), ("DS", SystemScreens.ds)] {
            for controls in [true, false] {
                let layout = GameLayout(system: system, geometry: testCase.geometry, showsTouchControls: controls)
                let problems = Self.violations(of: layout, system: system, geometry: testCase.geometry, controls: controls)
                #expect(problems.isEmpty, "\(systemName), \(controls ? "touch controls" : "controller"): \(problems)")
            }
        }
    }

    /// Without touch controls no screen gets smaller.
    @Test(arguments: cases)
    func aControllerNeverShrinksAScreen(_ testCase: Case) {
        for system in [SystemScreens.gba, .ds] {
            let touch = GameLayout(system: system, geometry: testCase.geometry, showsTouchControls: true)
            let controller = GameLayout(system: system, geometry: testCase.geometry, showsTouchControls: false)
            #expect(zip(touch.screens, controller.screens).allSatisfy { $0.scale <= $1.scale },
                    "\(touch.screens) → \(controller.screens)")
        }
    }

    static func violations(of layout: GameLayout, system: SystemScreens, geometry: FoldGeometry, controls: Bool) -> [String] {
        var problems: [String] = []
        let safe = geometry.safeBounds
        let pt = geometry.scale
        let activeFold = geometry.isFoldActive ? geometry.fold : nil
        let activeCore = geometry.isFoldActive ? geometry.foldCore : nil
        // Nothing that takes touches lies in the top edge guard.
        let firstInputRow = GameLayout.firstInputRow(in: geometry)
        if firstInputRow < LayoutMetrics.standard.topEdgeGuard * pt { problems.append("guard \(firstInputRow)") }

        if layout.posture != geometry.posture { problems.append("posture \(layout.posture)") }
        if layout.isLandscape != geometry.container.isLandscape { problems.append("orientation") }
        if layout.screens.map(\.source) != system.sources { problems.append("sources \(layout.screens)") }
        if layout.touchScreenIndex != system.touchScreen { problems.append("touch screen index") }

        for screen in layout.screens {
            if screen.scale < 1 { problems.append("scale \(screen)") }
            if screen.destination.size != PixelSize(width: screen.source.width * screen.scale,
                                                    height: screen.source.height * screen.scale) {
                problems.append("not whole-number scaled: \(screen)")
            }
            if !safe.contains(screen.destination) { problems.append("\(screen) outside the safe area \(safe)") }
            // The book counts as flat: one screen may span the fold then. Two
            // screens never do, and in tabletop nothing does.
            let mayCrossTheFold = system.sources.count == 1 && layout.posture == .flat
            if let core = activeCore, !mayCrossTheFold, screen.destination.intersects(core) {
                problems.append("\(screen) on the fold \(core)")
            }
        }
        if layout.screens.count == 2, layout.screens[0].destination.intersects(layout.screens[1].destination) {
            problems.append("screens overlap")
        }
        // The touch screen takes input like the controls: off the fold and its
        // margins, and below the top edge guard.
        if let touch = layout.touchScreen, let fold = activeFold, touch.destination.intersects(fold) {
            problems.append("touch screen on the fold or its margins")
        }
        if let touch = layout.touchScreen, touch.destination.minY < firstInputRow {
            problems.append("touch screen \(touch) in the top edge guard (\(firstInputRow))")
        }

        guard let zones = layout.controls else {
            if controls { problems.append("no controls") }
            // A controller is in use: the pause button alone takes touches.
            guard let pause = layout.pauseButton else {
                problems.append("no pause button")
                return problems
            }
            if pause.width < 44 * pt || pause.height < 44 * pt { problems.append("pause button too small: \(pause)") }
            if !safe.contains(pause) { problems.append("pause button \(pause) outside the safe area") }
            if pause.minY < firstInputRow { problems.append("pause button \(pause) in the top edge guard") }
            if let touch = layout.touchScreen, pause.intersects(touch.destination) { problems.append("pause button on the touch screen") }
            if let fold = activeFold, pause.intersects(fold) { problems.append("pause button on the fold") }
            if geometry.occlusions.contains(where: pause.intersects) { problems.append("pause button on an occlusion region") }
            return problems
        }
        if !controls { problems.append("controls without touch controls") }
        if layout.pauseButton != nil { problems.append("a pause button of its own beside the touch controls") }
        let named = [("pad", zones.pad), ("face", zones.face), ("L", zones.leftShoulder),
                     ("R", zones.rightShoulder), ("menu", zones.menu)]
        for (name, zone) in named {
            if zone.isEmpty { problems.append("\(name) empty") }
            if !safe.contains(zone) { problems.append("\(name) \(zone) outside the safe area") }
            if let touch = layout.touchScreen, zone.intersects(touch.destination) {
                problems.append("\(name) on the touch screen")
            }
            if let fold = activeFold, zone.intersects(fold) { problems.append("\(name) on the fold") }
            if zone.minY < firstInputRow { problems.append("\(name) \(zone) in the top edge guard (\(firstInputRow))") }
        }
        for (i, first) in named.enumerated() {
            for second in named[(i + 1)...] where first.1.intersects(second.1) {
                problems.append("\(first.0) overlaps \(second.0)")
            }
        }
        // Big enough to use: pad and face buttons at least 64 pt each way,
        // L and R and Start/Select at least 36 pt high.
        for (name, zone) in [("pad", zones.pad), ("face", zones.face)]
            where zone.width < 64 * pt || zone.height < 64 * pt {
            problems.append("\(name) too small: \(zone)")
        }
        for (name, zone) in [("L", zones.leftShoulder), ("R", zones.rightShoulder), ("menu", zones.menu)]
            where zone.height < 36 * pt || zone.width < 64 * pt {
            problems.append("\(name) too small: \(zone)")
        }
        let overlaps = zones.all.contains { zone in layout.screens.contains { zone.intersects($0.destination) } }
        if overlaps != zones.overlapsScreen { problems.append("overlapsScreen is \(zones.overlapsScreen)") }
        return problems
    }
}

/// The numbers of ADR 0006, section 8, for the sizes of the Simulator, and the
/// plan's own calculation (plan, section 7).
struct DuoNumbersTests {
    static func screens(_ system: SystemScreens, _ geometry: FoldGeometry, controls: Bool = true) -> [PlacedScreen] {
        GameLayout(system: system, geometry: geometry, showsTouchControls: controls).screens
    }

    @Test func gbaClosed() {
        // Bar on top, as the GBA chooses: 5× instead of 4×.
        #expect(Self.screens(.gba, Duo.closed(barOnTop: true)).map(\.destination)
            == [PixelRect(x: 99, y: 246, width: 1200, height: 800)])
        // Bar at the side: 4× as in M1, at the top of the view.
        #expect(Self.screens(.gba, Duo.closed(barOnTop: false)).map(\.destination)
            == [PixelRect(x: 93, y: 0, width: 960, height: 640)])
        // Sideways (an assumption without safe area): 8×, the controls over it.
        let sideways = GameLayout(system: .gba, geometry: FoldGeometry(container: Duo.outerLandscape), showsTouchControls: true)
        #expect(sideways.screens.map(\.scale) == [8])
        #expect(sideways.screens[0].destination.size == PixelSize(width: 1920, height: 1280))
        #expect(sideways.controls?.overlapsScreen == true)
    }

    @Test func gbaOpen() {
        for geometry in [Duo.foldDown(band: 0, active: false), Duo.foldDown(band: 16, active: true)] {
            #expect(Self.screens(.gba, geometry).map(\.destination) == [PixelRect(x: 346, y: 283, width: 2160, height: 1440)])
            #expect(Self.screens(.gba, geometry, controls: false).map(\.scale) == [11])
        }
        // Upright and tabletop: 8× in the upper half.
        let flat = Self.screens(.gba, Duo.foldAcross(band: 0, active: false))
        #expect(flat.map(\.destination) == [PixelRect(x: 43, y: 73, width: 1920, height: 1280)])
        let tabletop = Self.screens(.gba, Duo.foldAcross(band: 16, active: true))
        #expect(tabletop.map(\.destination) == [PixelRect(x: 43, y: 61, width: 1920, height: 1280)])
    }

    @Test func dsClosed() {
        // Bar at the side, as the DS chooses: 4× each, stacked at the top.
        #expect(Self.screens(.ds, Duo.closed(barOnTop: false)).map(\.destination) == [
            PixelRect(x: 61, y: 0, width: 1024, height: 768), PixelRect(x: 61, y: 768, width: 1024, height: 768),
        ])
        // Bar on top: only 3×, 4× with a controller.
        #expect(Self.screens(.ds, Duo.closed(barOnTop: true)).map(\.scale) == [3, 3])
        #expect(Self.screens(.ds, Duo.closed(barOnTop: true), controls: false).map(\.scale) == [4, 4])
        // Sideways: 3× each.
        let sideways = Self.screens(.ds, FoldGeometry(container: Duo.outerLandscape))
        #expect(sideways.map(\.destination.size) == [PixelSize(width: 768, height: 576), PixelSize(width: 768, height: 576)])
    }

    @Test func dsOpen() {
        // Upright, flat: both 5× above and below the fold, 7× with a controller.
        let flat = Duo.foldAcross(band: 0, active: false)
        #expect(Self.screens(.ds, flat).map(\.destination) == [
            PixelRect(x: 363, y: 233, width: 1280, height: 960), PixelRect(x: 363, y: 1659, width: 1280, height: 960),
        ])
        #expect(Self.screens(.ds, flat, controls: false).map(\.scale) == [7, 7])
        // Sideways and like a book: both 5×, left and right of the fold, at
        // the top edge guard of 64 pt (192 px).
        #expect(Self.screens(.ds, Duo.foldDown(band: 0, active: false)).map(\.destination) == [
            PixelRect(x: 73, y: 192, width: 1280, height: 960), PixelRect(x: 1499, y: 192, width: 1280, height: 960),
        ])
        #expect(Self.screens(.ds, Duo.foldDown(band: 16, active: true)).map(\.destination) == [
            PixelRect(x: 61, y: 192, width: 1280, height: 960), PixelRect(x: 1511, y: 192, width: 1280, height: 960),
        ])
        // Tabletop: the upper screen 7×, the touch screen 5× below the fold.
        #expect(Self.screens(.ds, Duo.foldAcross(band: 16, active: true)).map(\.destination) == [
            PixelRect(x: 107, y: 29, width: 1792, height: 1344), PixelRect(x: 363, y: 1671, width: 1280, height: 960),
        ])
    }

    /// Plan, section 7: the upper DS screen 6× in tabletop from 1878 × 2670 px.
    /// The Simulator's 2007 × 2853 px give 7× up to a fold band of 55 pt.
    @Test func dsTabletopUpperScreen() {
        let plan = FoldGeometry(container: PixelSize(width: 1878, height: 2670),
                                fold: PixelRect(x: 0, y: 1335, width: 1878, height: 0), isFoldActive: true)
        #expect(Self.screens(.ds, plan).map(\.destination)[0] == PixelRect(x: 171, y: 91, width: 1536, height: 1152))
        for (band, scale) in [(0, 7), (16, 7), (32, 7), (55, 7), (56, 6), (64, 6)] {
            #expect(Self.screens(.ds, Duo.foldAcross(band: band, active: true))[0].scale == scale, "band \(band) pt")
        }
    }

    /// Screens may reach into the fold's margins, the touch screen and the
    /// controls may not: with a band of 55 pt and margins of 8 pt the upper
    /// screen stays 7× only thanks to the margin.
    @Test func screensReachIntoTheMarginsAndTheTouchScreenDoesNot() {
        let geometry = Duo.foldAcross(band: 55, margin: 8, active: true)
        let fold = geometry.fold!
        let layout = GameLayout(system: .ds, geometry: geometry, showsTouchControls: true)
        #expect(layout.screens[0].scale == 7)
        #expect(layout.screens[0].destination.maxY > fold.minY, "The upper screen uses the margin")
        #expect(!layout.screens[0].destination.intersects(geometry.foldCore!))
        #expect(layout.screens[1].destination.minY >= fold.maxY)
        #expect(layout.controls!.all.allSatisfy { !$0.intersects(fold) })
    }

    @Test func largestScale() {
        #expect(GameLayout.largestScale(of: PixelSize(width: 240, height: 160), in: PixelSize(width: 1398, height: 2034)) == 5)
        #expect(GameLayout.largestScale(of: PixelSize(width: 240, height: 160), in: PixelSize(width: 239, height: 5000)) == 1)
        #expect(GameLayout.largestScale(of: PixelSize(width: 240, height: 160), in: PixelSize(width: -5, height: -5)) == 1)
        #expect(GameLayout.largestScale(of: PixelSize(width: 0, height: 160), in: PixelSize(width: 100, height: 100)) == 1)
    }
}

/// Where the controls go in the poses the Simulator can show, closed.
struct ControlZoneTests {
    /// DS closed with the bar at the side: the band below the screens is
    /// 132 pt high; pad, Start/Select and face buttons share it side by side,
    /// L and R sit over the lower corners of the upper screen, just above the
    /// touch screen: off the top edge and nearer the thumbs.
    @Test func dsClosedPutsLAndROverTheLowerCornersOfTheUpperScreen() throws {
        let layout = GameLayout(system: .ds, geometry: Duo.closed(barOnTop: false), showsTouchControls: true)
        let zones = try #require(layout.controls)
        let upper = layout.screens[0].destination
        let touch = layout.screens[1].destination
        #expect(zones.leftShoulder == PixelRect(x: 24, y: 612, width: 274, height: 132))
        #expect(zones.rightShoulder == PixelRect(x: 848, y: 612, width: 274, height: 132))
        #expect(zones.leftShoulder.intersects(upper) && zones.rightShoulder.intersects(upper))
        #expect(zones.leftShoulder.maxY + 24 == touch.minY, "8 pt above the touch screen")
        #expect(!zones.leftShoulder.intersects(touch) && !zones.rightShoulder.intersects(touch))
        #expect(zones.pad.minY >= 1536 && zones.face.minY >= 1536 && zones.menu.minY >= 1536)
        #expect(zones.pad.maxX <= zones.menu.minX && zones.menu.maxX <= zones.face.minX)
        #expect(zones.overlapsScreen)
    }

    /// The GBA open sideways or like a book: L and R at the top of the side
    /// columns, but below the top edge guard of 64 pt.
    @Test func gbaOpenKeepsLAndRBelowTheTopEdgeGuard() throws {
        for geometry in [Duo.foldDown(band: 0, active: false), Duo.foldDown(band: 16, active: true)] {
            let zones = try #require(GameLayout(system: .gba, geometry: geometry, showsTouchControls: true).controls)
            #expect(zones.leftShoulder.minY == 192 && zones.rightShoulder.minY == 192)
            #expect(zones.leftShoulder.height == 132)
        }
    }

    /// Without touch controls the pause button goes to a lower corner, off the
    /// touch screen; where both lower corners touch it, to an upper one below
    /// the top edge guard, over the screen without touch.
    @Test func thePauseButtonWithoutTouchControls() throws {
        let gba = GameLayout(system: .gba, geometry: Duo.closed(barOnTop: true), showsTouchControls: false)
        #expect(gba.pauseButton == PixelRect(x: 1242, y: 1776, width: 132, height: 132))
        let ds = GameLayout(system: .ds, geometry: Duo.closed(barOnTop: false), showsTouchControls: false)
        #expect(ds.pauseButton == PixelRect(x: 990, y: 1776, width: 132, height: 132))
        #expect(ds.pauseButton.map { $0.minY >= ds.screens[1].destination.maxY } == true, "Below the touch screen")
        // Flat upright with a controller: the touch screen (7×) reaches into
        // both lower corners.
        let flat = GameLayout(system: .ds, geometry: Duo.foldAcross(band: 0, active: false), showsTouchControls: false)
        #expect(flat.pauseButton == PixelRect(x: 1851, y: 216, width: 132, height: 132))
        #expect(flat.pauseButton.map { $0.intersects(flat.screens[0].destination) } == true,
                "Over the upper screen, which takes no touches")
    }

    /// The pause button without touch controls stays off an occlusion region.
    @Test func thePauseButtonAvoidsAnOcclusionRegion() throws {
        var geometry = Duo.foldDown(band: 16, active: true)
        let camera = PixelRect(x: 2600, y: 1800, width: 253, height: 207)
        geometry.occlusions = [camera]
        let pause = try #require(GameLayout(system: .gba, geometry: geometry, showsTouchControls: false).pauseButton)
        #expect(!pause.intersects(camera))
        #expect(pause == PixelRect(x: 24, y: 1851, width: 132, height: 132), "The lower left corner")
    }

    /// GBA closed with the bar on top: everything below the picture, nothing over it.
    @Test func gbaClosedKeepsThePictureClear() throws {
        let layout = GameLayout(system: .gba, geometry: Duo.closed(barOnTop: true), showsTouchControls: true)
        let zones = try #require(layout.controls)
        #expect(!zones.overlapsScreen)
        #expect(zones.leftShoulder.maxY <= zones.pad.minY && zones.pad.maxY <= zones.menu.minY)
    }

    @Test func noControlsWithAController() {
        let layout = GameLayout(system: .ds, geometry: Duo.foldAcross(band: 16, active: true), showsTouchControls: false)
        #expect(layout.controls == nil)
    }
}
