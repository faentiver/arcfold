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
            // The poses as the Simulator reports them.
            Case(name: "measured: closed, sideways, bar on top", geometry: Duo.closedSideways(barOnTop: true)),
            Case(name: "measured: closed, sideways, bar at the side", geometry: Duo.closedSideways(barOnTop: false)),
            Case(name: "measured: open", geometry: Duo.measuredInner(sideways: true, active: false)),
            Case(name: "measured: book", geometry: Duo.measuredInner(sideways: true, active: true)),
            Case(name: "measured: flat upright", geometry: Duo.measuredInner(sideways: false, active: false)),
            Case(name: "measured: tabletop", geometry: Duo.measuredInner(sideways: false, active: true)),
            // A part of the inner display whose lower edge is the fold: the
            // side below it is empty.
            Case(name: "fold at the lower edge, active", geometry: Duo.foldAtTheLowerEdge(active: true)),
            Case(name: "fold at the lower edge, inactive", geometry: Duo.foldAtTheLowerEdge(active: false)),
        ]
        for phone in Duo.iPhones {
            all.append(Case(name: "\(phone.name) upright", geometry: phone.upright))
            all.append(Case(name: "\(phone.name) sideways", geometry: phone.sideways))
        }
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

    /// The cases in which controls lie over a screen, by name and system.
    /// Since every display without a fold shows a handheld, only the slim
    /// case of the DS remains: L and R are the ends of a hinge too low for
    /// a key and take touches a bit above it, over the lower corners of the
    /// upper screen. A degenerate view that leaves no scale room for the
    /// controls beside and below the picture would be the only other one;
    /// it has to be named here, so that a new layout with keys over a
    /// picture fails this test.
    static let controlsOverAScreen: Set<String> = ["closed, bar at the side|DS"]

    @Test(arguments: cases)
    func everyRuleHolds(_ testCase: Case) {
        for (systemName, system) in [("GBA", SystemScreens.gba), ("DS", SystemScreens.ds)] {
            for controls in [true, false] {
                let layout = GameLayout(system: system, geometry: testCase.geometry, showsTouchControls: controls)
                let problems = Self.violations(
                    of: layout, system: system, geometry: testCase.geometry, controls: controls,
                    mayLieOverAScreen: Self.controlsOverAScreen.contains("\(testCase.name)|\(systemName)"))
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

    static func violations(of layout: GameLayout, system: SystemScreens, geometry: FoldGeometry, controls: Bool,
                           mayLieOverAScreen: Bool = false) -> [String] {
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
            let bezel = LayoutMetrics.standard.bezel * pt
            for screen in layout.screens where pause.intersects(screen.destination.inset(all: -bezel))
                && !screen.destination.contains(pause) {
                problems.append("pause button \(pause) across the bezel of \(screen)")
            }
            return problems
        }
        if !controls { problems.append("controls without touch controls") }
        if layout.pauseButton != nil { problems.append("a pause button of its own beside the touch controls") }
        let menuParts = [("menu", zones.menu)] + (zones.menuTrailing.map { [("menu, second part", $0)] } ?? [])
        let named = [("pad", zones.pad), ("face", zones.face), ("L", zones.leftShoulder),
                     ("R", zones.rightShoulder)] + menuParts
        if zones.all != named.map(\.1) { problems.append("all is not every zone") }
        // Pad and face buttons are level.
        if zones.pad.minY != zones.face.minY || zones.pad.maxY != zones.face.maxY {
            problems.append("pad \(zones.pad) and face \(zones.face) are not level")
        }
        // L and R are level and equally large, pad and face buttons are two
        // squares of one size, as far from the left edge as from the right.
        if zones.leftShoulder.minY != zones.rightShoulder.minY || zones.leftShoulder.size != zones.rightShoulder.size {
            problems.append("L \(zones.leftShoulder) and R \(zones.rightShoulder) differ")
        }
        if zones.pad.size != zones.face.size || abs((zones.pad.minX - safe.minX) - (safe.maxX - zones.face.maxX)) > 1 {
            problems.append("pad \(zones.pad) and face \(zones.face) do not mirror each other in \(safe)")
        }
        if abs((zones.leftShoulder.minX - safe.minX) - (safe.maxX - zones.rightShoulder.maxX)) > 1 {
            problems.append("L \(zones.leftShoulder) and R \(zones.rightShoulder) do not mirror each other in \(safe)")
        }
        // Start, Select and the pause button never lie below the face buttons
        // or the pad, where a thumb hits them by accident.
        for (name, part) in menuParts {
            for (control, zone) in [("pad", zones.pad), ("face", zones.face)]
                where part.minX < zone.maxX && part.maxX > zone.minX && part.minY >= zone.maxY {
                problems.append("\(name) \(part) below the \(control) \(zone)")
            }
        }
        // A fold from top to bottom never runs through the menu, active or not.
        if let fold = geometry.fold, fold.height > fold.width {
            for (name, part) in menuParts where part.minX < fold.maxX && part.maxX > fold.minX {
                problems.append("\(name) \(part) across the fold \(fold)")
            }
        }
        // Select, Start and the menu button keep 24 pt from pad and face
        // buttons, in every direction.
        func distance(_ a: PixelRect, _ b: PixelRect) -> Double {
            let dx = Double(max(0, a.minX - b.maxX, b.minX - a.maxX))
            let dy = Double(max(0, a.minY - b.maxY, b.minY - a.maxY))
            return (dx * dx + dy * dy).squareRoot()
        }
        for (name, part) in menuParts {
            for (control, zone) in [("pad", zones.pad), ("face", zones.face)] where distance(part, zone) < Double(24 * pt) {
                problems.append("\(name) \(part) only \(distance(part, zone) / Double(pt)) pt from the \(control) \(zone)")
            }
        }
        // The parts of the menu stand in one row or in one column, and a
        // divided menu flanks a fold from top to bottom: the first part ends
        // before it, the second begins behind it.
        if let second = zones.menuTrailing {
            let row = second.minY == zones.menu.minY && second.maxY == zones.menu.maxY
            let column = second.minX == zones.menu.minX && second.maxX == zones.menu.maxX
            if !row && !column { problems.append("menu \(zones.menu) and \(second) neither in a row nor in a column") }
            if let fold = geometry.fold, fold.height > fold.width {
                if zones.menu.maxX > fold.minX || second.minX < fold.maxX {
                    problems.append("menu \(zones.menu) and \(second) do not flank the fold \(fold)")
                }
            } else {
                problems.append("menu divided without a fold from top to bottom")
            }
        }
        // The menu begins below every screen it stands under.
        for (name, part) in menuParts {
            for screen in layout.screens where part.minX < screen.destination.maxX && part.maxX > screen.destination.minX
                && part.minY < screen.destination.maxY && !mayLieOverAScreen {
                problems.append("\(name) \(part) begins above the lower edge of \(screen)")
            }
        }
        // Controls lie over a screen only where the case names it.
        if zones.overlapsScreen && !mayLieOverAScreen { problems.append("controls over a screen") }
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
        // L and R at least 36 pt high, Start/Select at least 28 pt.
        for (name, zone) in [("pad", zones.pad), ("face", zones.face)]
            where zone.width < 64 * pt || zone.height < 64 * pt {
            problems.append("\(name) too small: \(zone)")
        }
        for (name, zone) in [("L", zones.leftShoulder), ("R", zones.rightShoulder)]
            where zone.height < 36 * pt || zone.width < 64 * pt {
            problems.append("\(name) too small: \(zone)")
        }
        for (name, zone) in menuParts where zone.height < 28 * pt || zone.width < 64 * pt {
            problems.append("\(name) too small: \(zone)")
        }
        let overlaps = zones.all.contains { zone in layout.screens.contains { zone.intersects($0.destination) } }
        if overlaps != zones.overlapsScreen { problems.append("overlapsScreen is \(zones.overlapsScreen)") }
        return problems
    }
}

/// The numbers of ADR 0006, section 8, for the sizes of the Simulator, and the
/// plan's own calculation (plan, section 7). With touch controls the case of
/// the console keeps a rim around the screens (ADR 0007); with a controller
/// the screens take what the view has.
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
        // Sideways as the pose reports it: 5× in the middle between two
        // columns, its bezel of 8 pt at the top of the safe area.
        #expect(Self.screens(.gba, Duo.closedSideways(barOnTop: true)).map(\.destination)
            == [PixelRect(x: 417, y: 270, width: 1200, height: 800)])
        #expect(Self.screens(.gba, Duo.closedSideways(barOnTop: true), controls: false).map(\.scale) == [6])
        // Sideways without a safe area (an assumption): a handheld like
        // every display without a fold, 5× between the columns instead of
        // 8× with the controls over it; 8× with a controller.
        let sideways = GameLayout(system: .gba, geometry: FoldGeometry(container: Duo.outerLandscape), showsTouchControls: true)
        #expect(sideways.screens.map(\.destination) == [PixelRect(x: 417, y: 209, width: 1200, height: 800)])
        #expect(sideways.controls?.overlapsScreen == false)
        #expect(Self.screens(.gba, FoldGeometry(container: Duo.outerLandscape), controls: false).map(\.scale) == [8])
    }

    @Test func gbaOpen() {
        // Sideways and like a book: 8× between two grips, 11× with a controller.
        for geometry in [Duo.foldDown(band: 0, active: false), Duo.foldDown(band: 16, active: true)] {
            #expect(Self.screens(.gba, geometry).map(\.destination) == [PixelRect(x: 466, y: 273, width: 1920, height: 1280)])
            #expect(Self.screens(.gba, geometry, controls: false).map(\.scale) == [11])
        }
        // Upright and tabletop: 7× in the middle of the upper half, with a
        // rim around its bezel; 8× with a controller.
        let flat = Duo.foldAcross(band: 0, active: false)
        #expect(Self.screens(.gba, flat).map(\.destination) == [PixelRect(x: 163, y: 153, width: 1680, height: 1120)])
        #expect(Self.screens(.gba, flat, controls: false).map(\.destination) == [PixelRect(x: 43, y: 73, width: 1920, height: 1280)])
        let tabletop = Self.screens(.gba, Duo.foldAcross(band: 16, active: true))
        #expect(tabletop.map(\.destination) == [PixelRect(x: 163, y: 141, width: 1680, height: 1120)])
    }

    @Test func dsClosed() {
        // Bar on top, as the DS chooses: 3× each in the middle of the view,
        // the hinge of the case, 44 pt, between them; 4× with a controller.
        #expect(Self.screens(.ds, Duo.closed(barOnTop: true)).map(\.destination) == [
            PixelRect(x: 315, y: 246, width: 768, height: 576), PixelRect(x: 315, y: 954, width: 768, height: 576),
        ])
        #expect(Self.screens(.ds, Duo.closed(barOnTop: true), controls: false).map(\.scale) == [4, 4])
        // Bar at the side, for whoever prefers larger screens: 4× each from
        // the top of the view, a slim hinge of 20 pt between them.
        #expect(Self.screens(.ds, Duo.closed(barOnTop: false)).map(\.destination) == [
            PixelRect(x: 61, y: 0, width: 1024, height: 768), PixelRect(x: 61, y: 828, width: 1024, height: 768),
        ])
        // Sideways: 3× each, side by side below the bar.
        #expect(Self.screens(.ds, Duo.closedSideways(barOnTop: true)).map(\.destination) == [
            PixelRect(x: 231, y: 246, width: 768, height: 576), PixelRect(x: 1035, y: 246, width: 768, height: 576),
        ])
        let sideways = Self.screens(.ds, FoldGeometry(container: Duo.outerLandscape))
        #expect(sideways.map(\.destination.size) == [PixelSize(width: 768, height: 576), PixelSize(width: 768, height: 576)])
    }

    @Test func dsOpen() {
        // Upright, flat: the upper screen 6× above the fold with a rim, the
        // touch screen 4× below it between pad and face buttons; both 7×
        // with a controller.
        let flat = Duo.foldAcross(band: 0, active: false)
        #expect(Self.screens(.ds, flat).map(\.destination) == [
            PixelRect(x: 235, y: 137, width: 1536, height: 1152), PixelRect(x: 491, y: 1665, width: 1024, height: 768),
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
        // Tabletop: as flat upright, in the middle of the parts beside the fold.
        #expect(Self.screens(.ds, Duo.foldAcross(band: 16, active: true)).map(\.destination) == [
            PixelRect(x: 235, y: 125, width: 1536, height: 1152), PixelRect(x: 491, y: 1677, width: 1024, height: 768),
        ])
    }

    /// Plan, section 7: the upper DS screen 6× in tabletop from 1878 × 2670 px.
    /// The Simulator's 2007 × 2853 px give 7× up to a fold band of 55 pt with
    /// a controller; with touch controls the rim of the case keeps it at 6×.
    @Test func dsTabletopUpperScreen() {
        let plan = FoldGeometry(container: PixelSize(width: 1878, height: 2670),
                                fold: PixelRect(x: 0, y: 1335, width: 1878, height: 0), isFoldActive: true)
        #expect(Self.screens(.ds, plan).map(\.destination)[0] == PixelRect(x: 171, y: 91, width: 1536, height: 1152))
        for (band, scale) in [(0, 7), (16, 7), (32, 7), (55, 7), (56, 6), (64, 6)] {
            let geometry = Duo.foldAcross(band: band, active: true)
            #expect(Self.screens(.ds, geometry, controls: false)[0].scale == scale, "band \(band) pt")
            #expect(Self.screens(.ds, geometry)[0].scale == 6, "band \(band) pt with touch controls")
        }
    }

    /// Screens may reach into the fold's margins, the touch screen and the
    /// controls may not: with a band of 55 pt and margins of 8 pt the upper
    /// screen stays 7× with a controller only thanks to the margin.
    @Test func screensReachIntoTheMarginsAndTheTouchScreenDoesNot() {
        let geometry = Duo.foldAcross(band: 55, margin: 8, active: true)
        let fold = geometry.fold!
        let controller = GameLayout(system: .ds, geometry: geometry, showsTouchControls: false)
        #expect(controller.screens[0].scale == 7)
        #expect(controller.screens[0].destination.maxY > fold.minY, "The upper screen uses the margin")
        #expect(!controller.screens[0].destination.intersects(geometry.foldCore!))
        #expect(controller.screens[1].destination.minY >= fold.maxY)
        let layout = GameLayout(system: .ds, geometry: geometry, showsTouchControls: true)
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

/// Where the controls go on the outer display, and the pause button without
/// touch controls.
struct ControlZoneTests {
    /// DS closed with the bar on top: the case has a hinge of its own
    /// between the screens, and L and R are its ends, 40 pt high like
    /// everywhere. Below the touch screen the pad, the menu in a column
    /// and the face buttons stand with equal spaces between them and to the
    /// edges; L begins where the pad does, R ends where the face buttons do.
    @Test func dsClosedPutsLAndRAtTheEndsOfTheHinge() throws {
        let layout = GameLayout(system: .ds, geometry: Duo.closed(barOnTop: true), showsTouchControls: true)
        let zones = try #require(layout.controls)
        let upper = layout.screens[0].destination
        let touch = layout.screens[1].destination
        #expect(layout.hinge == PixelRect(x: 0, y: 828, width: 1398, height: 120))
        #expect(touch.minY - upper.maxY == 132, "A gap of 44 pt: L and R and the well around them")
        #expect(zones.leftShoulder == PixelRect(x: 91, y: 828, width: 300, height: 120))
        #expect(zones.rightShoulder == PixelRect(x: 1007, y: 828, width: 300, height: 120))
        #expect(zones.leftShoulderCap == nil && zones.rightShoulderCap == nil)
        #expect(!zones.overlapsScreen)
        #expect(zones.pad == PixelRect(x: 91, y: 1566, width: 366, height: 366))
        #expect(zones.menu == PixelRect(x: 549, y: 1566, width: 300, height: 366))
        #expect(zones.face == PixelRect(x: 941, y: 1566, width: 366, height: 366))
        #expect(zones.pad.minY == touch.maxY + 36, "The bezel of 8 pt and 4 pt below the touch screen")
        #expect(zones.leftShoulder.minX == zones.pad.minX && zones.rightShoulder.maxX == zones.face.maxX)
        let spaces = [zones.pad.minX, zones.menu.minX - zones.pad.maxX, zones.face.minX - zones.menu.maxX, 1398 - zones.face.maxX]
        #expect(spaces.max()! - spaces.min()! <= 1, "Equal spaces: \(spaces)")
    }

    /// DS closed with the bar at the side: the screens are one step larger
    /// and the case is slim. The hinge is 20 pt high, too low for a key: L
    /// and R are its ends and take touches from 24 pt above it, over the
    /// lower corners of the upper screen and never on the touch screen. The
    /// controls below begin 2 pt below the touch screen, the well of a key,
    /// and where its bezel begins, and end with the safe area.
    @Test func dsClosedBesideTheBarIsSlim() throws {
        let layout = GameLayout(system: .ds, geometry: Duo.closed(barOnTop: false), showsTouchControls: true)
        let zones = try #require(layout.controls)
        let upper = layout.screens[0].destination
        let touch = layout.screens[1].destination
        #expect(layout.screens.map(\.scale) == [4, 4])
        #expect(layout.hinge == PixelRect(x: 0, y: 768, width: 1146, height: 60))
        #expect(zones.leftShoulderCap == PixelRect(x: 37, y: 768, width: 263, height: 60))
        #expect(zones.rightShoulderCap == PixelRect(x: 846, y: 768, width: 263, height: 60))
        #expect(zones.leftShoulder == PixelRect(x: 0, y: 696, width: 300, height: 132))
        #expect(zones.rightShoulder == PixelRect(x: 846, y: 696, width: 300, height: 132))
        #expect(zones.leftShoulder.intersects(upper) && zones.rightShoulder.intersects(upper))
        #expect(zones.leftShoulder.maxY == touch.minY)
        #expect(!zones.leftShoulder.intersects(touch) && !zones.rightShoulder.intersects(touch))
        #expect(zones.overlapsScreen)
        #expect(zones.pad == PixelRect(x: 37, y: 1602, width: 330, height: 330))
        #expect(zones.menu == PixelRect(x: 453, y: 1602, width: 240, height: 330))
        #expect(zones.face == PixelRect(x: 779, y: 1602, width: 330, height: 330))
        #expect(zones.pad.minX == touch.minX - 24, "Where the bezel of the screens begins")
        #expect(zones.pad.minY == touch.maxY + 6 && zones.pad.maxY == 1932)
    }

    /// The GBA open sideways or like a book: L and R at the top of the
    /// grips, level with the upper edge of the bezel and below the top edge
    /// guard of 64 pt; pad and face buttons on the centre line of the picture.
    @Test func gbaOpenPutsLAndRLevelWithTheBezel() throws {
        for geometry in [Duo.foldDown(band: 0, active: false), Duo.foldDown(band: 16, active: true)] {
            let layout = GameLayout(system: .gba, geometry: geometry, showsTouchControls: true)
            let zones = try #require(layout.controls)
            let picture = layout.screens[0].destination
            #expect(zones.leftShoulder == PixelRect(x: 24, y: 249, width: 394, height: 120))
            #expect(zones.leftShoulder.minY == picture.minY - 24 && zones.leftShoulder.minY >= 192)
            #expect(zones.pad == PixelRect(x: 24, y: 716, width: 394, height: 394))
            #expect(zones.pad.minY + zones.pad.height / 2 == picture.minY + picture.height / 2)
        }
    }

    /// Without touch controls the pause button goes to a lower corner of the
    /// case, off the touch screen and clear of every bezel; where no corner
    /// of the case has the room, inside the screen without touch, at its
    /// lower right corner, never across the edge of a bezel.
    @Test func thePauseButtonWithoutTouchControls() throws {
        let gba = GameLayout(system: .gba, geometry: Duo.closed(barOnTop: true), showsTouchControls: false)
        #expect(gba.pauseButton == PixelRect(x: 1242, y: 1776, width: 132, height: 132))
        let ds = GameLayout(system: .ds, geometry: Duo.closed(barOnTop: false), showsTouchControls: false)
        #expect(ds.pauseButton == PixelRect(x: 990, y: 1776, width: 132, height: 132))
        #expect(ds.pauseButton.map { $0.minY >= ds.screens[1].destination.maxY } == true, "Below the touch screen")
        // Flat upright with a controller: the touch screen (7×) reaches into
        // both lower corners, and the bezel of the upper screen into both
        // upper ones.
        let flat = GameLayout(system: .ds, geometry: Duo.foldAcross(band: 0, active: false), showsTouchControls: false)
        let upper = flat.screens[0].destination
        #expect(flat.pauseButton == PixelRect(x: 1743, y: 1229, width: 132, height: 132))
        #expect(flat.pauseButton.map { upper.inset(all: 24).contains($0) } == true,
                "Inside the upper screen, which takes no touches, a margin from its edges")
    }

    /// The pause button without touch controls stays off an occlusion region.
    @Test func thePauseButtonAvoidsAnOcclusionRegion() throws {
        var geometry = Duo.foldDown(band: 16, active: true)
        let camera = PixelRect(x: 2600, y: 1800, width: 253, height: 207)
        geometry.occlusions = [camera]
        let pause = try #require(GameLayout(system: .gba, geometry: geometry, showsTouchControls: false).pauseButton)
        #expect(!pause.intersects(camera))
        // The picture (11×) and its bezel leave no corner of the case the
        // room: the lower left corner inside the picture.
        #expect(pause == PixelRect(x: 130, y: 1727, width: 132, height: 132), "The lower left corner of the picture")
    }

    /// GBA closed with the bar on top: everything below the picture, nothing
    /// over it. A bar 16 pt below the picture, 44 pt high, holds L, the menu
    /// and R; pad and face buttons, 170 pt, follow in the middle between the
    /// bar and the lower edge of the view. L, the pad and the bezel of the
    /// picture begin on one line, R, the face buttons and the bezel end on one.
    @Test func gbaClosedKeepsThePictureClear() throws {
        let layout = GameLayout(system: .gba, geometry: Duo.closed(barOnTop: true), showsTouchControls: true)
        let zones = try #require(layout.controls)
        let picture = layout.screens[0].destination
        #expect(!zones.overlapsScreen)
        #expect(zones.leftShoulder == PixelRect(x: 75, y: 1094, width: 306, height: 132))
        #expect(zones.menu == PixelRect(x: 405, y: 1094, width: 588, height: 132))
        #expect(zones.rightShoulder == PixelRect(x: 1017, y: 1094, width: 306, height: 132))
        #expect(zones.menu.minY == picture.maxY + 48, "The bezel and 8 pt below the picture")
        #expect(zones.pad == PixelRect(x: 75, y: 1375, width: 510, height: 510))
        #expect(zones.face == PixelRect(x: 813, y: 1375, width: 510, height: 510))
        #expect(zones.pad.minX == picture.minX - 24 && zones.leftShoulder.minX == zones.pad.minX)
        #expect(zones.face.maxX == picture.maxX + 24 && zones.rightShoulder.maxX == zones.face.maxX)
        #expect(zones.pad.minY - zones.menu.maxY == 2034 - zones.pad.maxY, "As far from the bar as from the lower edge")
    }

    @Test func noControlsWithAController() {
        let layout = GameLayout(system: .ds, geometry: Duo.foldAcross(band: 16, active: true), showsTouchControls: false)
        #expect(layout.controls == nil)
        #expect(layout.hinge == nil)
    }
}

/// Where Start, Select and the pause button go in the poses the Simulator
/// reports: in the middle right below the picture, never below the face
/// buttons, and pad and face buttons level beside or below it.
struct MenuPlacementTests {
    static func zones(_ system: SystemScreens, _ geometry: FoldGeometry) throws -> (ControlZones, [PlacedScreen]) {
        let layout = GameLayout(system: system, geometry: geometry, showsTouchControls: true)
        return (try #require(layout.controls), layout.screens)
    }

    /// DS closed: the menu is a column in the middle between pad and face
    /// buttons, over the same rows, with the bar on top and beside it.
    @Test func dsClosedPutsTheMenuBetweenPadAndFaceButtons() throws {
        for barOnTop in [true, false] {
            let (zones, _) = try Self.zones(.ds, Duo.closed(barOnTop: barOnTop))
            #expect(zones.menu.minY == zones.pad.minY && zones.menu.maxY == zones.pad.maxY)
            #expect(zones.menu.minX - zones.pad.maxX >= 72 && zones.face.minX - zones.menu.maxX >= 72, "24 pt beside it")
            #expect(zones.menu.minX - zones.pad.maxX == zones.face.minX - zones.menu.maxX)
            #expect(zones.menu.width < 588, "Too narrow for a row")
            #expect(zones.menuTrailing == nil)
        }
    }

    /// DS closed sideways: the screens side by side below the bar, the hinge
    /// of the case right below them with L and R at its ends, and below the
    /// hinge the pad, the menu in a row and the face buttons. Pad, L and
    /// the bezel of the screens begin on one line.
    @Test func dsClosedSidewaysPutsTheHingeBelowTheScreens() throws {
        let geometry = Duo.closedSideways(barOnTop: true)
        let layout = GameLayout(system: .ds, geometry: geometry, showsTouchControls: true)
        let zones = try #require(layout.controls)
        #expect(layout.screens.map(\.destination) == [PixelRect(x: 231, y: 246, width: 768, height: 576),
                                                      PixelRect(x: 1035, y: 246, width: 768, height: 576)])
        #expect(layout.hinge == PixelRect(x: 0, y: 828, width: 2034, height: 120))
        #expect(zones.leftShoulder == PixelRect(x: 207, y: 828, width: 300, height: 120))
        #expect(zones.rightShoulder == PixelRect(x: 1527, y: 828, width: 300, height: 120))
        #expect(zones.pad == PixelRect(x: 207, y: 966, width: 330, height: 330))
        #expect(zones.menu == PixelRect(x: 723, y: 966, width: 588, height: 330))
        #expect(zones.face == PixelRect(x: 1497, y: 966, width: 330, height: 330))
        #expect(zones.pad.minX == layout.screens[0].destination.minX - 24, "Where the bezel begins")
        #expect(zones.face.maxX == layout.screens[1].destination.maxX + 24, "Where the bezel ends")
    }

    /// DS open and in the book: a bar below the screens with L, Select and
    /// the pause button before the fold, Start and R behind it; the pad on
    /// the left page and the face buttons on the right page below the bar.
    @Test(arguments: [false, true])
    func dsOpenDividesTheMenuAtTheFold(active: Bool) throws {
        let geometry = Duo.measuredInner(sideways: true, active: active)
        let (zones, screens) = try Self.zones(.ds, geometry)
        let fold = try #require(geometry.fold)
        #expect(zones.leftShoulder == PixelRect(x: 43, y: 1200, width: 438, height: 132))
        #expect(zones.menu == PixelRect(x: 958, y: 1200, width: 384, height: 132))
        #expect(zones.menuTrailing == PixelRect(x: 1511, y: 1200, width: 384, height: 132))
        #expect(zones.rightShoulder == PixelRect(x: 2372, y: 1200, width: 438, height: 132))
        #expect(zones.menu.maxX + 24 == fold.minX && zones.menuTrailing?.minX == fold.maxX + 24, "8 pt beside the fold")
        #expect(zones.menu.minY == screens[0].destination.maxY + 48, "The bezel and 8 pt below the screens")
        #expect(zones.pad == PixelRect(x: 43, y: 1450, width: 438, height: 438))
        #expect(zones.face == PixelRect(x: 2372, y: 1450, width: 438, height: 438))
        #expect(zones.pad.minX == screens[0].destination.minX && zones.face.maxX == screens[1].destination.maxX,
                "On one line with the pictures")
        #expect(abs((zones.pad.minY - zones.menu.maxY) - (2007 - zones.pad.maxY)) <= 1, "As far from the bar as from the lower edge")
    }

    /// DS in tabletop and flat upright: the menu below the touch screen,
    /// between the columns; L and R level with the upper edge of its bezel,
    /// pad and face buttons on its centre line.
    @Test(arguments: [false, true])
    func dsBelowTheFoldPutsTheMenuBelowTheTouchScreen(active: Bool) throws {
        let (zones, screens) = try Self.zones(.ds, Duo.measuredInner(sideways: false, active: active))
        let touch = screens[1].destination
        #expect(touch == PixelRect(x: 491, y: 1696, width: 1024, height: 768))
        #expect(zones.menu == PixelRect(x: 709, y: 2512, width: 588, height: 132))
        #expect(zones.menu.minY == touch.maxY + 48 && zones.menu.minX >= touch.minX && zones.menu.maxX <= touch.maxX)
        #expect(zones.leftShoulder == PixelRect(x: 24, y: 1672, width: 419, height: 120))
        #expect(zones.leftShoulder.minY == touch.minY - 24, "Level with the bezel")
        #expect(zones.pad == PixelRect(x: 24, y: 1871, width: 419, height: 419))
        #expect(zones.face == PixelRect(x: 1564, y: 1871, width: 419, height: 419))
        #expect(abs((zones.pad.minY + zones.pad.maxY) - (touch.minY + touch.maxY)) <= 1, "On its centre line")
    }

    /// GBA closed sideways: the picture in the middle with the menu below
    /// it, its bezel at the top of the safe area; L and R level with the
    /// bezel, pad and face buttons on the centre line of the picture.
    @Test func gbaClosedSidewaysIsAHandheld() throws {
        let (zones, screens) = try Self.zones(.gba, Duo.closedSideways(barOnTop: true))
        let picture = screens[0].destination
        #expect(picture == PixelRect(x: 417, y: 270, width: 1200, height: 800))
        #expect(zones.menu == PixelRect(x: 723, y: 1118, width: 588, height: 132))
        #expect(zones.menu.minY == picture.maxY + 48)
        #expect(zones.leftShoulder == PixelRect(x: 24, y: 246, width: 345, height: 120))
        #expect(zones.pad == PixelRect(x: 24, y: 498, width: 345, height: 345))
        #expect(zones.face == PixelRect(x: 1665, y: 498, width: 345, height: 345))
        #expect(abs((zones.pad.minY + zones.pad.maxY) - (picture.minY + picture.maxY)) <= 1, "On its centre line")
    }

    /// GBA open and in the book: the menu below the picture on both sides of
    /// the fold, pad and face buttons in the grips beside the picture.
    @Test(arguments: [false, true])
    func gbaOpenDividesTheMenuBelowThePicture(active: Bool) throws {
        let (zones, screens) = try Self.zones(.gba, Duo.measuredInner(sideways: true, active: active))
        #expect(screens[0].destination == PixelRect(x: 466, y: 273, width: 1920, height: 1280))
        #expect(zones.menu == PixelRect(x: 958, y: 1601, width: 384, height: 132))
        #expect(zones.menuTrailing == PixelRect(x: 1511, y: 1601, width: 384, height: 132))
        #expect(zones.pad == PixelRect(x: 24, y: 716, width: 394, height: 394))
        #expect(zones.face == PixelRect(x: 2435, y: 716, width: 394, height: 394))
    }

    /// GBA in tabletop and flat upright: the bar right below the fold with L,
    /// the menu and R, pad and face buttons below it. L and R are as wide as
    /// pad and face buttons, and all begin and end where the bezel of the
    /// picture above the fold does.
    @Test(arguments: [false, true])
    func gbaBelowTheFoldPutsTheMenuInTheBar(active: Bool) throws {
        let (zones, screens) = try Self.zones(.gba, Duo.measuredInner(sideways: false, active: active))
        #expect(screens[0].destination == PixelRect(x: 163, y: 123, width: 1680, height: 1120))
        #expect(zones.leftShoulder == PixelRect(x: 139, y: 1511, width: 510, height: 132))
        #expect(zones.menu == PixelRect(x: 709, y: 1511, width: 588, height: 132))
        #expect(zones.rightShoulder == PixelRect(x: 1358, y: 1511, width: 510, height: 132))
        #expect(zones.pad == PixelRect(x: 139, y: 1993, width: 510, height: 510))
        #expect(zones.face == PixelRect(x: 1358, y: 1993, width: 510, height: 510))
        #expect(zones.pad.minX == screens[0].destination.minX - 24, "Where the bezel begins")
        #expect(zones.pad.minY - zones.menu.maxY == 2853 - zones.pad.maxY, "As far from the bar as from the lower edge")
    }

    /// A part below the fold that is exactly as high as the touch screen at
    /// 5×: the touch screen gets smaller, so that the menu keeps its row
    /// right below it, and pad and face buttons stay level.
    @Test func aLowPartBelowTheFoldKeepsTheMenuBelowTheTouchScreen() throws {
        let geometry = FoldGeometry(container: PixelSize(width: 2007, height: 2447),
                                    fold: PixelRect(x: 0, y: 1366, width: 2007, height: 121), isFoldActive: true)
        let (zones, screens) = try Self.zones(.ds, geometry)
        let touch = screens[1].destination
        #expect(touch == PixelRect(x: 619, y: 1589, width: 768, height: 576))
        #expect(zones.menu == PixelRect(x: 709, y: 2213, width: 588, height: 132))
        #expect(zones.menuTrailing == nil)
        #expect(zones.pad.minY == zones.face.minY && zones.pad.maxY == zones.face.maxY)
    }
}

/// Every display without a fold shows a handheld sideways, and upright the
/// scale counts for more than the bezel at the sides; a fold at the edge of
/// the view leaves the layout of a display without one.
struct HandheldTests {
    /// The GBA on iPhones held sideways: the largest scale at which pad and
    /// face buttons fit beside the picture and Select, Start and the menu
    /// button below it with their smallest sizes. Nothing lies over the
    /// picture; on 402 × 874 pt that is 6× instead of the 7× the view holds.
    @Test func theGBAOnAniPhoneSidewaysIsAHandheld() throws {
        let expected: [(scale: Int, picture: PixelRect, pad: Int, menu: PixelRect)] = [
            (5, PixelRect(x: 618, y: 72, width: 1200, height: 800), 414, PixelRect(x: 924, y: 920, width: 588, height: 132)),
            (5, PixelRect(x: 678, y: 99, width: 1200, height: 800), 429, PixelRect(x: 984, y: 947, width: 588, height: 132)),
            (6, PixelRect(x: 591, y: 24, width: 1440, height: 960), 333, PixelRect(x: 1017, y: 1014, width: 588, height: 129)),
            (6, PixelRect(x: 678, y: 75, width: 1440, height: 960), 429, PixelRect(x: 1104, y: 1083, width: 588, height: 132)),
            (6, PixelRect(x: 714, y: 90, width: 1440, height: 960), 438, PixelRect(x: 1140, y: 1098, width: 588, height: 132)),
        ]
        for (phone, expected) in zip(Duo.iPhones, expected) {
            let layout = GameLayout(system: .gba, geometry: phone.sideways, showsTouchControls: true)
            let zones = try #require(layout.controls)
            let picture = layout.screens[0].destination
            #expect(layout.screens.map(\.scale) == [expected.scale], "\(phone.name)")
            #expect(picture == expected.picture, "\(phone.name)")
            #expect(zones.pad.width == expected.pad && zones.face.width == expected.pad, "\(phone.name): \(zones.pad)")
            #expect(zones.menu == expected.menu, "\(phone.name)")
            #expect(!zones.overlapsScreen, "\(phone.name)")
            #expect(zones.pad.maxX <= picture.minX - 24 && zones.face.minX >= picture.maxX + 24, "\(phone.name): beside the bezel")
            #expect(zones.menu.minY >= picture.maxY + 24 + 6, "\(phone.name): below the bezel, a hairline off it")
            #expect(zones.pad.width >= 110 * 3 && zones.menu.height >= 28 * 3, "\(phone.name): the smallest sizes")
        }
        // With a controller the picture takes the view.
        #expect(GameLayout(system: .gba, geometry: Duo.iPhones[2].sideways, showsTouchControls: false).screens.map(\.scale) == [7])
    }

    /// Upright on an iPhone 402 pt wide the GBA stays 5×, 1 pt from each
    /// edge: the bezel of 8 pt does not fit beside it, so the picture runs
    /// from edge to edge and the case draws its bezel as a band.
    @Test func uprightTheScaleCountsForMoreThanTheBezelAtTheSides() throws {
        let geometry = Duo.iPhones[2].upright
        let layout = GameLayout(system: .gba, geometry: geometry, showsTouchControls: true)
        let picture = layout.screens[0].destination
        #expect(picture == PixelRect(x: 3, y: 186, width: 1200, height: 800))
        #expect(picture.minX - LayoutMetrics.standard.bezel * 3 < 0 && picture.maxX + LayoutMetrics.standard.bezel * 3 > 1206,
                "No room for the bezel beside the picture")
        let zones = try #require(layout.controls)
        #expect(zones.menu.minY >= picture.maxY + 24 && !zones.overlapsScreen)
    }

    /// A fold at the lower edge of the view leaves the side below it empty:
    /// screens and controls follow the template of a display without a
    /// fold in the part above it, as if the safe area ended at the fold,
    /// with and without touch controls, for the GBA and the DS. Nothing lies
    /// outside the view or on the fold.
    @Test(arguments: [false, true])
    func aFoldAtTheEdgeLeavesTheLayoutWithoutAFold(active: Bool) throws {
        let geometry = Duo.foldAtTheLowerEdge(active: active)
        let fold = try #require(geometry.fold)
        let above = FoldGeometry(container: geometry.container, safeArea: PixelInsets(bottom: geometry.container.height - fold.minY))
        for system in [SystemScreens.gba, .ds] {
            for controls in [true, false] {
                let layout = GameLayout(system: system, geometry: geometry, showsTouchControls: controls)
                let plain = GameLayout(system: system, geometry: above, showsTouchControls: controls)
                #expect(layout.posture == geometry.posture)
                #expect(layout.screens == plain.screens && layout.controls == plain.controls, "\(system.sources.count) screens, \(controls)")
                #expect(layout.pauseButton == plain.pauseButton && layout.hinge == plain.hinge)
                for screen in layout.screens {
                    #expect(geometry.bounds.contains(screen.destination) && !screen.destination.intersects(fold), "\(screen)")
                }
                for zone in layout.controls?.all ?? [] {
                    #expect(!zone.isEmpty && !zone.intersects(fold), "\(zone)")
                }
            }
        }
        // The DS keeps its touch screen and every control.
        let ds = GameLayout(system: .ds, geometry: geometry, showsTouchControls: true)
        #expect(ds.screens.map(\.scale) == [3, 3])
        #expect(ds.touchScreen.map { $0.destination.maxY <= fold.minY } == true)
    }

    /// Views that are higher than wide with a fold from top to bottom
    /// through their middle: the closed Duo and the iPhones, held upright.
    /// The fold is 16 pt wide and active, as the debug build simulates the
    /// book (`-ArcfoldFoldOverride book`), without a width and inactive, or
    /// the division region of the Simulator, 121 px with margins of 20 pt.
    /// No pose of the Duo gives such a view; the inner display is wider
    /// than high whenever its fold runs from top to bottom.
    static let uprightWithAFoldDown: [LayoutInvariantTests.Case] = {
        let views = [("closed Duo, bar on top", Duo.closed(barOnTop: true))] + Duo.iPhones.map { ($0.name, $0.upright) }
        return views.flatMap { name, view in
            var folded = [(16, true), (0, false)].map { band, active in
                var geometry = Duo.foldDown(view.container, band: band, active: active)
                geometry.safeArea = view.safeArea
                return LayoutInvariantTests.Case(name: "\(name), fold down \(band) pt, \(active ? "active" : "inactive")",
                                                 geometry: geometry)
            }
            var measured = view
            measured.fold = PixelRect(x: (view.container.width - 121) / 2, y: 0, width: 121, height: view.container.height)
            measured.foldMargins = PixelInsets(left: 60, right: 60)
            measured.isFoldActive = true
            folded.append(LayoutInvariantTests.Case(name: "\(name), fold down as measured, active", geometry: measured))
            return folded
        }
    }()

    /// Upright, a fold from top to bottom leaves no room for the grips of
    /// a handheld beside the picture: on 402 pt the picture was 1× and the
    /// menu had 16 pt on each side of the fold, too narrow for Select. The
    /// GBA keeps the layout of a display without a fold instead, the
    /// picture at the top across the fold as in the book and the controls
    /// below it, and the menu stands on both sides of the fold: Select and
    /// the menu button before it, Start behind it, 8 pt off it, each part
    /// as wide as L and R leave it at their smallest width and no wider
    /// than in the book. Pad and face buttons stay on their side of the
    /// fold; a fold as wide as the Simulator's makes them smaller for that
    /// on the narrower views.
    @Test(arguments: uprightWithAFoldDown)
    func uprightAFoldDownDividesTheMenuBelowThePicture(_ testCase: LayoutInvariantTests.Case) throws {
        let geometry = testCase.geometry
        let fold = try #require(geometry.fold)
        var plainGeometry = geometry
        plainGeometry.fold = nil
        plainGeometry.foldMargins = .zero
        plainGeometry.isFoldActive = false
        let plain = GameLayout(system: .gba, geometry: plainGeometry, showsTouchControls: true)
        let layout = GameLayout(system: .gba, geometry: geometry, showsTouchControls: true)
        let zones = try #require(layout.controls)
        let plainZones = try #require(plain.controls)
        #expect(LayoutInvariantTests.violations(of: layout, system: .gba, geometry: geometry, controls: true).isEmpty)
        #expect(layout.posture == .flat && layout.screens == plain.screens, "\(layout.screens)")
        // L and R begin and stand where they do without a fold, and give
        // the menu room down to their smallest width of 64 pt.
        #expect(zones.leftShoulder.minX == plainZones.leftShoulder.minX && zones.rightShoulder.maxX == plainZones.rightShoulder.maxX)
        #expect(zones.leftShoulder.minY == plainZones.leftShoulder.minY && zones.leftShoulder.height == plainZones.leftShoulder.height)
        #expect(zones.leftShoulder.width >= 64 * 3 && zones.leftShoulder.width <= plainZones.leftShoulder.width, "\(zones.leftShoulder)")
        #expect(zones.leftShoulder.maxX == zones.menu.minX - 24, "8 pt between L and the menu")
        #expect(zones.pad.maxX <= fold.minX && zones.face.minX >= fold.maxX, "\(zones.pad) and \(zones.face) at \(fold)")
        #expect(zones.pad.minX == plainZones.pad.minX && zones.face.maxX == plainZones.face.maxX)
        if fold.width <= 16 * 3 {
            #expect(zones.pad == plainZones.pad && zones.face == plainZones.face)
        } else {
            #expect(zones.pad.width >= 110 * 3, "\(zones.pad)")
        }
        // The row of the menu of the display without a fold, divided at
        // the fold.
        let second = try #require(zones.menuTrailing)
        #expect(zones.menu.minY == plainZones.menu.minY && zones.menu.height == plainZones.menu.height)
        #expect(zones.menu.maxX == fold.minX - 24 && second.minX == fold.maxX + 24, "8 pt beside the fold")
        #expect(zones.menu.width >= 64 * 3 && second.width >= 64 * 3, "\(zones.menu) and \(second)")
        #expect(zones.menu.width <= 128 * 3 && second.width <= 128 * 3, "\(zones.menu) and \(second)")
        #expect(second.maxX == zones.rightShoulder.minX - 24, "8 pt between the menu and R")
        // With a controller the picture takes the view, across the fold.
        let controller = GameLayout(system: .gba, geometry: geometry, showsTouchControls: false)
        #expect(LayoutInvariantTests.violations(of: controller, system: .gba, geometry: geometry, controls: false).isEmpty)
        #expect(controller.screens == GameLayout(system: .gba, geometry: plainGeometry, showsTouchControls: false).screens)
    }
}
