/// The screens of an emulated system as one frame of its core holds them.
public struct SystemScreens: Sendable, Hashable {
    /// Where each screen lies in the core's frame, in source pixels; the first
    /// is the upper or only screen.
    public var sources: [PixelRect]
    /// The screen that takes touches (the lower DS screen), if any.
    public var touchScreen: Int?

    public init(sources: [PixelRect], touchScreen: Int? = nil) {
        precondition(!sources.isEmpty && sources.count <= 2, "A system has one or two screens")
        precondition(touchScreen.map { sources.indices.contains($0) } ?? true, "The touch screen is one of the screens")
        self.sources = sources
        self.touchScreen = touchScreen
    }

    /// mGBA: one 240 × 160 frame.
    public static let gba = SystemScreens(sources: [PixelRect(x: 0, y: 0, width: 240, height: 160)])

    /// melonDS DS with the layout top-bottom and no gap: one 256 × 384 frame,
    /// the touch screen in the lower half (ADR 0006).
    public static let ds = SystemScreens(
        sources: [PixelRect(x: 0, y: 0, width: 256, height: 192), PixelRect(x: 0, y: 192, width: 256, height: 192)],
        touchScreen: 1
    )

    /// The size of the core's frame that holds all screens, for example
    /// 256 × 384 for the DS: the extent of libretro pointer coordinates.
    public var frameSize: PixelSize {
        PixelSize(width: sources.map(\.maxX).max() ?? 0, height: sources.map(\.maxY).max() ?? 0)
    }
}

/// What the game view knows about its place on the device, in pixels of the
/// view. The app reads it with `onFoldGeometryChange(scale:perform:)`.
public struct FoldGeometry: Sendable, Hashable {
    /// The size of the game view.
    public var container: PixelSize
    /// Screens and controls stay out of these insets (status bar, the vertical
    /// bar of the outer display, rounded corners, the camera).
    public var safeArea: PixelInsets
    /// The division region, the fold, including its margins, active or not;
    /// nil when the view has none (the outer display, an iPhone without a
    /// hinge, iOS before 27.1).
    public var fold: PixelRect?
    /// The margins the system puts into `fold` for interactive content:
    /// screens may reach into them, controls may not.
    public var foldMargins: PixelInsets
    /// The fold divides the view, because the device is partially open.
    public var isFoldActive: Bool
    /// Pixels per point of the view; 3 on iPhone Duo.
    public var scale: Int
    /// The active occlusion regions, such as the camera, in pixels of the
    /// view (`ReservedRegion.Kind.occlusion`). The pause button without touch
    /// controls stays off them; the debug overlay shows them, so that the
    /// device test can measure them on the inner display before the controls
    /// follow them too (ADR 0006).
    public var occlusions: [PixelRect]

    public init(
        container: PixelSize, safeArea: PixelInsets = .zero, fold: PixelRect? = nil,
        foldMargins: PixelInsets = .zero, isFoldActive: Bool = false, scale: Int = 3,
        occlusions: [PixelRect] = []
    ) {
        self.container = container
        self.safeArea = safeArea
        self.fold = fold
        self.foldMargins = foldMargins
        self.isFoldActive = isFoldActive
        self.scale = scale
        self.occlusions = occlusions
    }

    /// The pose as far as the layout cares: no fold is `single`, an inactive
    /// fold `flat`, an active fold across the view `tabletop`, and an active
    /// fold from top to bottom (the device held like a book) `flat` as well,
    /// because version 1 treats the book like flat (plan, section 7; ADR 0006).
    public var posture: Posture {
        guard let fold else { return .single }
        guard isFoldActive, fold.width > fold.height else { return .flat }
        return .tabletop
    }

    /// The whole view.
    public var bounds: PixelRect {
        PixelRect(x: 0, y: 0, width: container.width, height: container.height)
    }

    /// The part of the view inside the safe area.
    public var safeBounds: PixelRect {
        bounds.inset(by: safeArea)
    }

    /// The fold without its margins: the part nothing may cover while the
    /// fold is active, except a single screen in the book posture.
    public var foldCore: PixelRect? {
        fold.map { $0.inset(by: foldMargins) }
    }
}

/// The pose of the device as far as the layout cares (ADR 0006). There is no
/// API that names a pose; it follows from the division region.
public enum Posture: String, Sendable, Hashable, CaseIterable {
    /// No fold in the view: the outer display of the closed device, or an
    /// iPhone without a hinge.
    case single
    /// Open flat, or folded like a book.
    case flat
    /// Folded with the fold across the view: look at the upper part, touch the
    /// lower part.
    case tabletop
}

/// Sizes of the touch controls and of the case around the screens, in points.
/// The app draws a console around the screens: every screen sits in a bezel,
/// and the controls stand in the case beside or below it.
public struct LayoutMetrics: Sendable, Hashable {
    /// The narrowest column beside a screen that still holds the pad or the
    /// face buttons: the smallest pad, a margin on both sides and the bezel.
    public var controlColumn: Int
    /// Space around the controls.
    public var margin: Int
    /// The band at the top edge of the view that nothing taking touches
    /// covers: no control, no touch screen, no pause button. The top edge
    /// belongs to the system's edge gestures, and thumbs reach it worst. A
    /// safe area inset at the top counts towards it. Screens without touch
    /// may lie in it (ADR 0006, section "Nachbesserungen nach der Prüfung").
    public var topEdgeGuard: Int
    /// The frame the case draws around a screen. A control keeps this and
    /// a margin from a screen.
    public var bezel: Int
    /// The smallest pad, and the smallest square of face buttons, that a
    /// screen gets smaller for: below it a screen rather loses one step.
    public var smallestPad: Int
    /// The largest pad beside a screen or below two screens.
    public var pad: Int
    /// The largest pad where the controls have a part of the view to
    /// themselves: below a single screen or below the fold.
    public var largePad: Int
    /// The height of L and R, in every pose.
    public var shoulderHeight: Int
    /// The height of the row of Select, Start and the menu button: each a
    /// small button with its name below it, and a target for a finger.
    public var menuRow: Int
    /// The gap between two stacked screens on a display without a fold. The
    /// case draws a hinge there, with L and R at its ends: their height and
    /// the well around them.
    public var hinge: Int
    /// The same gap where the case gives up its rim for larger screens: a
    /// hinge too low for a key. L and R are its ends and take touches a bit
    /// above it.
    public var slimHinge: Int

    public init(
        controlColumn: Int = 134, margin: Int = 8, topEdgeGuard: Int = 64, bezel: Int = 8,
        smallestPad: Int = 110, pad: Int = 146, largePad: Int = 170, shoulderHeight: Int = 40,
        menuRow: Int = 44, hinge: Int = 44, slimHinge: Int = 20
    ) {
        self.controlColumn = controlColumn
        self.margin = margin
        self.topEdgeGuard = topEdgeGuard
        self.bezel = bezel
        self.smallestPad = smallestPad
        self.pad = pad
        self.largePad = largePad
        self.shoulderHeight = shoulderHeight
        self.menuRow = menuRow
        self.hinge = hinge
        self.slimHinge = slimHinge
    }

    public static let standard = LayoutMetrics()
}

/// One screen of the system in the view.
public struct PlacedScreen: Sendable, Hashable, CustomStringConvertible {
    /// Where the screen lies in the core's frame.
    public var source: PixelRect
    /// Where it lands in the view: `source.size × scale`, on whole pixels.
    public var destination: PixelRect
    /// The whole-number scale, at least 1.
    public var scale: Int

    public init(source: PixelRect, destination: PixelRect, scale: Int) {
        self.source = source
        self.destination = destination
        self.scale = scale
    }

    public var description: String { "\(source.size)×\(scale) at \(destination)" }
}

/// Where the touch controls go, in pixels of the view. Each control fills
/// its zone; the app turns the zones into buttons.
///
/// Pad and face buttons are level and mirror each other: their zones are
/// squares of one size over the same rows, as far from the left edge as from
/// the right. L and R are level too. Select, Start and the menu button sit
/// in the middle right below the picture and never below the face buttons,
/// where a thumb would hit them by accident.
public struct ControlZones: Sendable, Hashable {
    public var pad: PixelRect
    public var face: PixelRect
    public var leftShoulder: PixelRect
    public var rightShoulder: PixelRect
    /// Start and Select, and room for the app's pause button between them.
    /// When the menu is divided, the first part: Select and the pause button.
    public var menu: PixelRect
    /// The second part of a divided menu, for Start: a fold from top to
    /// bottom runs through the middle below the picture, so the menu
    /// continues behind it. Nil while the menu is in one piece.
    public var menuTrailing: PixelRect?
    /// What L and R show of themselves where they are the ends of a hinge
    /// too low for a key: their zones then reach above the hinge, over the
    /// lower corners of a screen without touch. Nil where L and R fill
    /// their zones.
    public var leftShoulderCap: PixelRect?
    public var rightShoulderCap: PixelRect?
    /// A zone covers part of a screen; the app draws the controls translucent.
    public var overlapsScreen: Bool

    public init(
        pad: PixelRect, face: PixelRect, leftShoulder: PixelRect, rightShoulder: PixelRect,
        menu: PixelRect, menuTrailing: PixelRect? = nil, leftShoulderCap: PixelRect? = nil,
        rightShoulderCap: PixelRect? = nil, overlapsScreen: Bool
    ) {
        self.pad = pad
        self.face = face
        self.leftShoulder = leftShoulder
        self.rightShoulder = rightShoulder
        self.menu = menu
        self.menuTrailing = menuTrailing
        self.leftShoulderCap = leftShoulderCap
        self.rightShoulderCap = rightShoulderCap
        self.overlapsScreen = overlapsScreen
    }

    /// Every zone, in the order pad, face, left shoulder, right shoulder,
    /// menu and, when the menu is divided, its second part.
    public var all: [PixelRect] {
        [pad, face, leftShoulder, rightShoulder, menu] + (menuTrailing.map { [$0] } ?? [])
    }
}

/// The screens, the controls and the touch screen of one system in one
/// geometry (ADR 0006, section "FoldLayout").
public struct GameLayout: Sendable, Hashable {
    public var posture: Posture
    public var isLandscape: Bool
    public var screens: [PlacedScreen]
    /// Nil without touch controls (a controller is in use).
    public var controls: ControlZones?
    /// The index of the screen that takes touches, if the system has one.
    public var touchScreenIndex: Int?
    /// Where the app's pause button goes while no touch controls show: a
    /// square of 44 pt in a corner of the safe area below the top edge guard,
    /// preferably a lower one, off the touch screen, the active fold and the
    /// occlusion regions. Nil with touch controls; their menu zone holds it.
    public var pauseButton: PixelRect?
    /// The row across the view in which the console has a hinge of its own:
    /// between two stacked screens, or below two screens side by side, on a
    /// display without a fold. L and R stand at its ends. Nil where the
    /// fold of the device is the hinge, and without touch controls.
    public var hinge: PixelRect?

    public init(
        posture: Posture, isLandscape: Bool, screens: [PlacedScreen], controls: ControlZones?,
        touchScreenIndex: Int?, pauseButton: PixelRect? = nil, hinge: PixelRect? = nil
    ) {
        self.posture = posture
        self.isLandscape = isLandscape
        self.screens = screens
        self.controls = controls
        self.touchScreenIndex = touchScreenIndex
        self.pauseButton = pauseButton
        self.hinge = hinge
    }

    /// The layout of `system` in `geometry`. The rules: screens stay in the
    /// safe area and never on an active fold, except a single screen in the
    /// book posture; controls never lie on the touch screen or on an active
    /// fold; nothing that takes touches lies in the top edge guard; every
    /// screen is scaled by a whole number; without touch controls the screens
    /// grow; pad and face buttons are level, and Start, Select and the pause
    /// button sit in the middle right below the picture, never below pad or
    /// face buttons. The templates per system and posture are in ADR 0006
    /// and docs/wissen/falz.md.
    public init(
        system: SystemScreens, geometry: FoldGeometry, showsTouchControls: Bool,
        metrics: LayoutMetrics = .standard
    ) {
        let templates = Templates(geometry: Self.placeable(geometry, metrics: metrics), metrics: metrics,
                                  showsControls: showsTouchControls)
        let (screens, zones, hinge) = system.sources.count == 1
            ? templates.oneScreen(system.sources[0])
            : templates.twoScreens(upper: system.sources[0], lower: system.sources[1])
        let touchScreen = system.touchScreen.map { screens[$0].destination }
        let controls = zones.map { templates.finished($0, screens: screens, touchScreen: touchScreen) }
        self.init(
            posture: geometry.posture, isLandscape: geometry.container.isLandscape, screens: screens,
            controls: controls, touchScreenIndex: system.touchScreen,
            pauseButton: controls == nil ? templates.pauseButton(screens: screens, touchScreen: touchScreen) : nil,
            hinge: controls == nil ? nil : hinge
        )
    }

    /// What the templates lay out in: `geometry`, or where the fold lies at
    /// the edge of the safe area, so that one side of it is empty or
    /// narrower across the fold than a column of controls (too low for the
    /// smallest pad with its margins and bezel), the other side alone
    /// without a fold. Screens and controls then follow the template of a
    /// display without a fold there instead of going into a side that holds
    /// nothing. The pose stays the one of `geometry`.
    static func placeable(_ geometry: FoldGeometry, metrics: LayoutMetrics) -> FoldGeometry {
        guard let fold = geometry.fold else { return geometry }
        let safe = geometry.safeBounds
        let least = metrics.controlColumn * max(1, geometry.scale)
        var result = geometry
        result.fold = nil
        result.foldMargins = .zero
        result.isFoldActive = false
        if fold.width >= fold.height {
            let above = safe.above(fold.minY).height
            let below = safe.below(fold.maxY).height
            guard min(above, below) < least else { return geometry }
            if above >= below {
                result.safeArea.bottom = max(geometry.safeArea.bottom, geometry.container.height - fold.minY)
            } else {
                result.safeArea.top = max(geometry.safeArea.top, fold.maxY)
            }
        } else {
            let before = safe.left(of: fold.minX).width
            let behind = safe.right(of: fold.maxX).width
            guard min(before, behind) < least else { return geometry }
            if before >= behind {
                result.safeArea.right = max(geometry.safeArea.right, geometry.container.width - fold.minX)
            } else {
                result.safeArea.left = max(geometry.safeArea.left, fold.maxX)
            }
        }
        return result
    }

    /// The first row of the view in which something may take touches: the
    /// top edge guard of `metrics`, or the safe area's top when it is lower.
    public static func firstInputRow(in geometry: FoldGeometry, metrics: LayoutMetrics = .standard) -> Int {
        max(geometry.safeBounds.minY, metrics.topEdgeGuard * max(1, geometry.scale))
    }

    /// The screen that takes touches, if the system has one.
    public var touchScreen: PlacedScreen? {
        touchScreenIndex.map { screens[$0] }
    }

    /// The largest whole-number scale of `source` that fits `area`, at least 1.
    public static func largestScale(of source: PixelSize, in area: PixelSize) -> Int {
        guard source.width > 0, source.height > 0 else { return 1 }
        return max(1, min(max(0, area.width) / source.width, max(0, area.height) / source.height))
    }
}

// MARK: - Templates

/// The templates of ADR 0006, section 8, in pixels of the view.
private struct Templates {
    enum Alignment {
        case top
        case center
    }

    let geometry: FoldGeometry
    let posture: Posture
    /// The whole view. The case fills it, so controls are centred in it
    /// where the safe area allows.
    let view: PixelRect
    /// The safe part of the view.
    let safe: PixelRect
    /// The safe part is wider than high: a handheld held sideways.
    var isWide: Bool { safe.width > safe.height }
    let showsControls: Bool
    /// LayoutMetrics in pixels.
    let column: Int
    let margin: Int
    let bezel: Int
    let smallestPad: Int
    let pad: Int
    let largePad: Int
    /// The height of an L or R button.
    let shoulder: Int
    let hinge: Int
    let slimHinge: Int
    /// The well around L and R in a hinge.
    let well: Int
    /// What a control keeps from a screen: the bezel and a margin.
    let clearance: Int
    /// The least a control keeps from a bezel where the room is short.
    let hairline: Int
    /// The smallest pad or set of face buttons that is still comfortable.
    let minimumControl: Int
    /// What pad and face buttons keep from the left and right edge where
    /// no bezel gives them a line.
    let sideInset: Int
    /// The height of the row of Select, Start and the menu button.
    let menuRow: Int
    /// The lowest row of Select, Start and the menu button.
    let minimumMenuRow: Int
    /// The widest row of Select, the menu button and Start: three buttons
    /// of 60 pt and 8 pt between them.
    let menuWidth: Int
    /// The widest and the narrowest column of the three between pad and
    /// face buttons.
    let menuColumn: Int
    let narrowMenuColumn: Int
    /// The width of each part of a menu that a fold divides: Select and the
    /// menu button before the fold, Start behind it.
    let menuPart: Int
    /// What Select, Start and the menu button keep from pad and face buttons.
    let menuKeepOut: Int
    /// L or R at the end of a hinge, and the narrowest anywhere.
    let hingeShoulder: Int
    let minimumShoulder: Int
    /// The space between L or R and the pad or the face buttons below it,
    /// where no bezel gives L and R a line.
    let shoulderGap: Int
    /// The height of what takes the touches for L and R at a slim hinge.
    let slimShoulderTarget: Int
    /// The first row in which something may take touches (`LayoutMetrics.topEdgeGuard`).
    let topGuard: Int
    /// The safe part of the view below the top edge guard: controls, the
    /// touch screen and the pause button stay inside it.
    let inputSafe: PixelRect
    /// The side of the pause button without touch controls.
    let pauseSide: Int

    init(geometry: FoldGeometry, metrics: LayoutMetrics, showsControls: Bool) {
        let s = max(1, geometry.scale)
        self.geometry = geometry
        posture = geometry.posture
        view = geometry.bounds
        safe = geometry.safeBounds
        topGuard = GameLayout.firstInputRow(in: geometry, metrics: metrics)
        inputSafe = geometry.safeBounds.below(topGuard)
        pauseSide = 44 * s
        self.showsControls = showsControls
        column = metrics.controlColumn * s
        margin = metrics.margin * s
        bezel = metrics.bezel * s
        smallestPad = metrics.smallestPad * s
        pad = metrics.pad * s
        largePad = metrics.largePad * s
        shoulder = metrics.shoulderHeight * s
        hinge = metrics.hinge * s
        slimHinge = metrics.slimHinge * s
        well = max(0, metrics.hinge - metrics.shoulderHeight) * s / 2
        clearance = (metrics.bezel + metrics.margin) * s
        hairline = 2 * s
        minimumControl = 96 * s
        sideInset = 24 * s
        menuRow = metrics.menuRow * s
        minimumMenuRow = 28 * s
        menuWidth = 196 * s
        menuColumn = 100 * s
        narrowMenuColumn = 80 * s
        menuPart = 128 * s
        menuKeepOut = 24 * s
        hingeShoulder = 100 * s
        minimumShoulder = 64 * s
        shoulderGap = 22 * s
        slimShoulderTarget = 44 * s
    }

    // MARK: Fold

    /// The fold runs across the view (left to right).
    var foldIsHorizontal: Bool {
        guard let fold = geometry.fold else { return false }
        return fold.width >= fold.height
    }

    /// The safe area on both sides of the fold: `first` is the upper or left
    /// part, `second` the lower or right part, both without the fold and its
    /// margins, for controls and the touch screen. `firstForScreen` and
    /// `secondForScreen` reach into the margins, for screens without touch.
    func split() -> (first: PixelRect, second: PixelRect, firstForScreen: PixelRect, secondForScreen: PixelRect) {
        guard let fold = geometry.fold else { return (safe, .zero, safe, .zero) }
        let m = geometry.foldMargins
        if foldIsHorizontal {
            return (safe.above(fold.minY), safe.below(fold.maxY),
                    safe.above(fold.minY + m.top), safe.below(fold.maxY - m.bottom))
        } else {
            return (safe.left(of: fold.minX), safe.right(of: fold.maxX),
                    safe.left(of: fold.minX + m.left), safe.right(of: fold.maxX - m.right))
        }
    }

    // MARK: Placing

    func scale(_ source: PixelRect, in width: Int, _ height: Int) -> Int {
        GameLayout.largestScale(of: source.size, in: PixelSize(width: width, height: height))
    }

    /// `source` at `scale`, centred horizontally in `area` on whole pixels (an
    /// odd remainder goes to the right), at its top or centred vertically.
    func place(_ source: PixelRect, scale: Int, in area: PixelRect, alignment: Alignment = .center) -> PlacedScreen {
        let width = source.width * scale
        let height = source.height * scale
        let x = area.x + ((area.width - width) >> 1)
        let y = alignment == .top ? area.y : area.y + ((area.height - height) >> 1)
        return PlacedScreen(source: source, destination: PixelRect(x: x, y: y, width: width, height: height), scale: scale)
    }

    /// `screen` moved up in `area` as far as it takes to leave a row below
    /// it for Select, Start and the menu button, and never out of `area`. A
    /// screen that leaves the room anyway stays where it is.
    func raised(_ screen: PlacedScreen, in area: PixelRect) -> PlacedScreen {
        let lowest = area.maxY - clearance - menuRow - screen.destination.height
        guard screen.destination.y > lowest else { return screen }
        var moved = screen
        moved.destination = PixelRect(x: screen.destination.x, y: max(area.minY, lowest),
                                      width: screen.destination.width, height: screen.destination.height)
        return moved
    }

    /// The lower edge the eye sees below `area`: the edge of the view where
    /// `area` ends at the safe area, because the case goes on below it.
    func visibleBottom(of area: PixelRect) -> Int {
        area.maxY >= safe.maxY ? view.maxY : area.maxY
    }

    /// The first row of a block `height` high that stands in the middle
    /// between the row `top` and the lower edge the eye sees below `area`,
    /// and never leaves the rows from `first` to the end of `area`.
    func centred(_ height: Int, below top: Int, in area: PixelRect, from first: Int? = nil) -> Int {
        let middle = top + (visibleBottom(of: area) - top - height) / 2
        return max(first ?? top, min(middle, area.maxY - height))
    }

    /// `rect` mirrored at the middle of `area`.
    func mirrored(_ rect: PixelRect, in area: PixelRect) -> PixelRect {
        PixelRect(x: area.minX + area.maxX - rect.maxX, y: rect.y, width: rect.width, height: rect.height)
    }

    /// A single picture in a view that is wider than high, as on a handheld:
    /// in the middle from left to right, with the row of the menu right
    /// below it, both together in the middle of the view from top to
    /// bottom, and never higher than its bezel fits into the safe area.
    func handheld(_ source: PixelRect, scale k: Int) -> PlacedScreen {
        var screen = place(source, scale: k, in: safe, alignment: .top)
        let block = screen.destination.height + clearance + menuRow
        let middle = view.minY + (view.height - block) / 2
        screen.destination.y = max(safe.minY + bezel, min(middle, safe.maxY - block))
        return screen
    }

    /// The largest scale of `source` at which a handheld fits the safe area:
    /// a column of the smallest pad on both sides, and below the picture its
    /// bezel, a hairline and the lowest row of the menu. Nil where not even
    /// scale 1 fits.
    func handheldScale(of source: PixelRect) -> Int? {
        let width = safe.width - 2 * column
        let height = safe.height - 2 * bezel - hairline - minimumMenuRow
        guard source.width <= width, source.height <= height else { return nil }
        return scale(source, in: width, height)
    }

    // MARK: One screen (GBA and the later single-screen systems)

    func oneScreen(_ source: PixelRect) -> ([PlacedScreen], ControlZones?, PixelRect?) {
        switch posture {
        case .single where isWide:
            // A handheld, on every display without a fold: the picture in
            // the middle, the menu below it and a column on both sides that
            // holds the pad or the face buttons, at the largest scale that
            // leaves all of them their smallest sizes, however many steps
            // that costs the picture (on an iPhone of 874 × 402 pt 6×
            // instead of 7×). Only where no scale from 1 on leaves that room,
            // a degenerate view, the picture takes the view and the controls
            // lie over it (as M1); it moves up to make room for the menu.
            let full = scale(source, in: safe.width, safe.height)
            let centred = place(source, scale: full, in: safe)
            guard showsControls else { return ([centred], nil, nil) }
            if let k = handheldScale(of: source) {
                let screen = handheld(source, scale: k)
                return ([screen], sideZones(in: safe, beside: screen.destination, below: screen.destination, mayCoverPicture: true), nil)
            }
            let screen = raised(centred, in: safe)
            return ([screen], sideZones(in: safe, beside: nil, below: screen.destination, mayCoverPicture: true), nil)
        case .single,
             .flat where !foldIsHorizontal && !isWide:
            // Upright: at the top, the controls below it: a bar with L, the
            // menu and R, then pad and face buttons. The scale counts for
            // more than the bezel at the sides: where the bezel does not fit
            // beside the picture, as on an iPhone 402 pt wide (5×, 1 pt from
            // each edge), the picture runs from edge to edge, and the case
            // draws its bezel there as a band across the whole width
            // (`CaseLayout`).
            // The same in a view that is higher than wide with a fold from
            // top to bottom, which no pose of the Duo gives: such a view
            // has no room for the grips of a handheld beside the picture.
            // The picture lies across the fold, as in the book, and the
            // menu stands on both sides of it (`bandZones`).
            guard showsControls else {
                return ([place(source, scale: scale(source, in: safe.width, safe.height), in: safe)], nil, nil)
            }
            let controls = clearance + menuRow + margin + smallestPad + margin
            let k = scale(source, in: safe.width, safe.height - controls)
            let screen = place(source, scale: k, in: safe, alignment: .top)
            let zones = bandZones(in: safe.below(screen.destination.maxY), gap: clearance,
                                  alignedWith: screen.destination, shoulderArea: safe.above(screen.destination.maxY))
            return ([screen], zones, nil)
        case .flat where !foldIsHorizontal:
            // Open sideways or like a book: across the fold, in the middle
            // with the menu below it, and a column that holds the pad or
            // the face buttons on both sides, like the grips of a handheld.
            guard showsControls else {
                return ([place(source, scale: scale(source, in: safe.width, safe.height), in: safe)], nil, nil)
            }
            let k = scale(source, in: safe.width - 2 * column, safe.height - bezel - clearance - menuRow)
            let screen = handheld(source, scale: k)
            return ([screen], sideZones(in: safe, beside: screen.destination, below: screen.destination, mayCoverPicture: true), nil)
        case .flat, .tabletop:
            // The fold across the view: the screen in the upper part, the
            // controls in the lower part. With touch controls the case keeps
            // a rim around the bezel, as wide as beside the other screens.
            let (upper, lower, upperForScreen, _) = split()
            let rim = showsControls ? 2 * clearance : 0
            let k = scale(source, in: upperForScreen.width - rim, upperForScreen.height - rim)
            // In the middle of the part above the fold, so that its bezel is
            // as far from the hinge as from the top; into the fold's margin
            // only when it does not fit otherwise.
            let screen = place(source, scale: k, in: source.height * k <= upper.height ? upper : upperForScreen)
            return ([screen], showsControls ? bandZones(in: lower, gap: margin, alignedWith: screen.destination, shoulderArea: lower) : nil, nil)
        }
    }

    // MARK: Two screens (DS)

    func twoScreens(upper: PixelRect, lower: PixelRect) -> ([PlacedScreen], ControlZones?, PixelRect?) {
        let stack = PixelRect(x: 0, y: 0, width: max(upper.width, lower.width), height: upper.height + lower.height)
        switch posture {
        case .single where isWide:
            // Side by side at the top with the hinge of the case and the
            // controls below them, where the screens get no smaller than
            // in a stack; otherwise both stacked in the middle with the
            // controls in columns beside them and the menu below them, at
            // the largest scale that leaves the menu its row, as for one
            // screen. Only where no scale does, the menu goes to the foot of
            // the columns.
            let stacked = showsControls
                ? handheldScale(of: stack) ?? scale(stack, in: safe.width - 2 * column, safe.height)
                : scale(stack, in: safe.width, safe.height)
            if let row = sideBySide(upper: upper, lower: lower, beating: stacked) {
                return row
            }
            let centred = place(stack, scale: stacked, in: safe)
            guard showsControls else {
                return (self.stacked(upper: upper, lower: lower, scale: stacked, block: centred.destination, gap: 0), nil, nil)
            }
            // The stack moves up to make room for the menu below it.
            let block = raised(centred, in: safe).destination
            let screens = self.stacked(upper: upper, lower: lower, scale: stacked, block: block, gap: 0)
            return (screens, sideZones(in: safe, beside: block, below: block, mayCoverPicture: false), nil)
        case .single:
            // Upright: both screens at the top with the hinge of the case
            // between them, L and R at its ends, the other controls below.
            guard showsControls else {
                let k = scale(stack, in: safe.width, safe.height)
                return (stacked(upper: upper, lower: lower, scale: k, block: place(stack, scale: k, in: safe).destination, gap: 0), nil, nil)
            }
            return clamshell(upper: upper, lower: lower, stack: stack)
        case .flat where !foldIsHorizontal:
            // Sideways or like a book: the upper screen left of the fold, the
            // touch screen right of it, each in the middle of its page, both
            // at the top below the top edge guard, the controls below them;
            // nothing on the fold. The touch screen stays out of the fold's
            // margins like the controls, and the upper screen stays level
            // with it.
            let (left, right, leftForScreen, _) = split()
            let leftArea = leftForScreen.below(topGuard)
            let rightArea = right.below(topGuard)
            let controls = clearance + menuRow + margin + smallestPad + margin
            let height = showsControls ? min(leftArea.height, rightArea.height) - controls : min(leftArea.height, rightArea.height)
            let k = min(scale(upper, in: leftArea.width, height), scale(lower, in: rightArea.width, height))
            let alignment: Alignment = showsControls ? .top : .center
            // Into the fold's margin only when the page is too narrow.
            let upperScreen = place(upper, scale: k, in: upper.width * k <= left.width ? left.below(topGuard) : leftArea,
                                    alignment: alignment)
            let touchScreen = place(lower, scale: k, in: rightArea, alignment: alignment)
            guard showsControls else { return ([upperScreen, touchScreen], nil, nil) }
            let top = max(upperScreen.destination.maxY, touchScreen.destination.maxY)
            let zones = pageZones(left: left.below(top), right: right.below(top),
                                  inset: upperScreen.destination.minX - left.minX)
            return ([upperScreen, touchScreen], zones, nil)
        case .flat, .tabletop:
            // The fold across the view: the upper screen above it with a rim
            // of the case around its bezel, the touch screen below the fold
            // between pad and face buttons (plan, section 7).
            let (upperPart, lowerPart, upperForScreen, _) = split()
            let rim = showsControls ? 2 * clearance : 0
            let kUpper = scale(upper, in: upperForScreen.width - rim, upperForScreen.height - rim)
            let kLower = showsControls
                ? scale(lower, in: lowerPart.width - 2 * column, lowerPart.height - bezel - clearance - menuRow)
                : scale(lower, in: lowerPart.width, lowerPart.height)
            let upperScreen = place(upper, scale: kUpper, in: upper.height * kUpper <= upperPart.height ? upperPart : upperForScreen)
            let (screens, zones) = below(upperScreen, touchScreen: place(lower, scale: kLower, in: lowerPart), in: lowerPart)
            return (screens, zones, nil)
        }
    }

    /// The touch screen in the part below the fold with the menu right below
    /// it, both together in the middle of that part, and the controls in
    /// columns beside it.
    func below(_ upperScreen: PlacedScreen, touchScreen centred: PlacedScreen, in lowerPart: PixelRect) -> ([PlacedScreen], ControlZones?) {
        guard showsControls else { return ([upperScreen, centred], nil) }
        var touchScreen = centred
        let block = touchScreen.destination.height + clearance + menuRow
        // Its bezel below the fold where the part is high enough, and the
        // touch screen never on the fold.
        let first = min(lowerPart.minY + bezel, max(lowerPart.minY, lowerPart.maxY - block))
        let y = self.centred(block, below: lowerPart.minY, in: lowerPart, from: first)
        touchScreen.destination.y = max(lowerPart.minY, min(y, lowerPart.maxY - touchScreen.destination.height))
        let zones = sideZones(in: lowerPart, beside: touchScreen.destination, below: touchScreen.destination, mayCoverPicture: false)
        return ([upperScreen, touchScreen], zones)
    }

    /// Both screens one above the other on a display without a fold, like a
    /// console that folds: the hinge of the case between them with L and R
    /// at its ends, and below the touch screen the pad, the menu in a
    /// column and the face buttons. The case keeps a rim; where giving it
    /// up makes the screens one step larger, it becomes slim: the screens
    /// begin at the top, the hinge is too low for a key, so L and R are its
    /// ends and take touches a bit above it, over the lower corners of the
    /// upper screen, and the controls keep 2 pt from the touch screen, the
    /// well around a key.
    func clamshell(upper: PixelRect, lower: PixelRect, stack: PixelRect) -> ([PlacedScreen], ControlZones?, PixelRect?) {
        let lowBand = bezel + 2 * hairline + smallestPad
        let roomy = scale(stack, in: safe.width, safe.height - hinge - lowBand)
        let slim = scale(stack, in: safe.width, safe.height - slimHinge - hairline - smallestPad)
        guard slim > roomy else {
            var block = place(stack, scale: roomy, in: safe, alignment: .top).destination
            // A view without an inset at the top keeps a rim for the bezel
            // where there is room.
            let room = safe.height - block.height - hinge - lowBand
            block.y += max(0, min(clearance - (safe.minY - view.minY), room))
            let screens = stacked(upper: upper, lower: lower, scale: roomy, block: block, gap: hinge)
            let row = PixelRect(x: safe.minX, y: screens[0].destination.maxY + well, width: safe.width, height: shoulder)
            let plate = screens[1].destination.inset(all: -bezel)
            return (screens, hingeZones(row: row, below: plate.maxY + 2 * hairline, in: safe, plate: plate), row)
        }
        let block = place(stack, scale: slim, in: safe, alignment: .top).destination
        let screens = stacked(upper: upper, lower: lower, scale: slim, block: block, gap: slimHinge)
        let row = PixelRect(x: safe.minX, y: screens[0].destination.maxY, width: safe.width, height: slimHinge)
        let plate = screens[1].destination.inset(all: -bezel).intersection(safe)
        var zones = hingeZones(row: row, below: screens[1].destination.maxY + hairline, in: safe, plate: plate)
        // L and R: the ends of the hinge, as wide as the bezel allows, and
        // what takes their touches from a bit above the hinge.
        let width = min(hingeShoulder, (row.width - margin) / 2) - (plate.minX - safe.minX)
        let cap = PixelRect(x: plate.minX, y: row.minY, width: max(0, width), height: row.height)
        let targetTop = max(topGuard, row.maxY - slimShoulderTarget)
        let target = PixelRect(x: safe.minX, y: targetTop, width: cap.maxX - safe.minX, height: row.maxY - targetTop)
        zones.leftShoulder = target
        zones.rightShoulder = mirrored(target, in: safe)
        zones.leftShoulderCap = cap
        zones.rightShoulderCap = mirrored(cap, in: safe)
        return (screens, zones, row)
    }

    /// Both screens side by side at the top of a view that is wider than
    /// high, the hinge of the case right below them with L and R at its
    /// ends, and the other controls below the hinge; or nil when that gives
    /// smaller screens than the scale `stacked` of a stack.
    func sideBySide(upper: PixelRect, lower: PixelRect, beating stacked: Int) -> ([PlacedScreen], ControlZones?, PixelRect?)? {
        let gap = bezel + margin / 2
        let row = PixelRect(x: 0, y: 0, width: upper.width + lower.width, height: max(upper.height, lower.height))
        let area = safe.below(topGuard)
        let controls = showsControls ? hinge + 2 * hairline + smallestPad : 0
        let k = scale(row, in: area.width - gap, area.height - controls)
        guard k >= stacked else { return nil }
        let width = row.width * k + gap
        let height = row.height * k
        let x = area.minX + (area.width - width) / 2
        let y = showsControls ? area.minY : area.minY + (area.height - height) / 2
        let upperScreen = PlacedScreen(
            source: upper, destination: PixelRect(x: x, y: y, width: upper.width * k, height: upper.height * k), scale: k)
        let touchScreen = PlacedScreen(
            source: lower, destination: PixelRect(x: x + upper.width * k + gap, y: y, width: lower.width * k, height: lower.height * k),
            scale: k)
        guard showsControls else { return ([upperScreen, touchScreen], nil, nil) }
        let hingeRow = PixelRect(x: area.minX, y: y + height + well, width: area.width, height: shoulder)
        let plate = PixelRect(x: x - bezel, y: y - bezel, width: width + 2 * bezel, height: height + 2 * bezel)
        return ([upperScreen, touchScreen], hingeZones(row: hingeRow, below: y + height + hinge + 2 * hairline, in: area, plate: plate), hingeRow)
    }

    /// Both screens one above the other in `block`, `gap` between them.
    func stacked(upper: PixelRect, lower: PixelRect, scale k: Int, block: PixelRect, gap: Int) -> [PlacedScreen] {
        let upperScreen = PixelRect(x: block.x + (block.width - upper.width * k) / 2, y: block.y,
                                    width: upper.width * k, height: upper.height * k)
        let lowerScreen = PixelRect(x: block.x + (block.width - lower.width * k) / 2, y: upperScreen.maxY + gap,
                                    width: lower.width * k, height: lower.height * k)
        return [PlacedScreen(source: upper, destination: upperScreen, scale: k),
                PlacedScreen(source: lower, destination: lowerScreen, scale: k)]
    }

    // MARK: Control zones

    /// The controls in a band below the picture or below the fold: a bar
    /// `gap` below the top of `area` with L, the menu in the middle and R,
    /// and below the bar the pad at the left and the face buttons at the
    /// right, two squares of one size that mirror each other, in the middle
    /// between the bar and the lower edge of the view. L and R begin where
    /// pad and face buttons do and are as wide where the menu leaves the
    /// room; all four keep to the bezel of `picture` where that leaves them
    /// a margin. A band that is short of room gives up the gap first. A
    /// band too low for a bar puts L and R over the lower corners of
    /// `shoulderArea` (not the upper ones: the top edge belongs to system
    /// gestures and is hard to reach) and the menu in a column between pad
    /// and face buttons. A fold from top to bottom through the band divides
    /// the menu, and pad and face buttons each stay on their side of it.
    func bandZones(in area: PixelRect, gap: Int, alignedWith picture: PixelRect?, shoulderArea: PixelRect) -> ControlZones {
        var gap = gap
        var side = min(largePad, area.height - gap - menuRow - margin)
        if side < smallestPad {
            gap = max(hairline, min(gap, area.height - menuRow - margin - smallestPad))
            side = min(smallestPad, area.height - gap - menuRow - margin)
        }
        var inset = sideInset
        if let picture, picture.minX - bezel - area.minX >= 2 * margin, picture.minX - bezel - area.minX <= 2 * sideInset {
            inset = picture.minX - bezel - area.minX
        }
        side = min(side, (area.width - 2 * inset - menuKeepOut) / 2)
        let division = geometry.fold.flatMap { !foldIsHorizontal && $0.minX < area.maxX && $0.maxX > area.minX ? $0 : nil }
        if let division {
            // No wider than the narrower side of the fold leaves them.
            side = min(side, min(division.minX - area.minX, area.maxX - division.maxX) - inset)
        }
        guard side >= minimumControl else { return lowBandZones(in: area, shoulderArea: shoulderArea) }

        let bar = PixelRect(x: area.minX, y: area.minY + gap, width: area.width, height: menuRow)
        // What L and R leave the menu at their smallest width.
        let reach = inset + minimumShoulder + margin
        let menuWidth = min(self.menuWidth, max(0, bar.width - 2 * reach))
        let whole = PixelRect(x: bar.minX + (bar.width - menuWidth) / 2, y: bar.minY, width: menuWidth, height: bar.height)
        // Divided at the fold, the menu takes all of that: Select and the
        // menu button stand on one side and need more than half a row.
        let menu: (first: PixelRect, second: PixelRect?) = division == nil ? (whole, nil)
            : divided(PixelRect(x: bar.minX + reach, y: bar.minY, width: max(0, bar.width - 2 * reach), height: bar.height))
        let shoulderWidth = min(side, menu.first.minX - margin - bar.minX - inset)
        let left = PixelRect(x: bar.minX + inset, y: bar.minY, width: shoulderWidth, height: bar.height)
        let padZone = PixelRect(x: area.minX + inset, y: centred(side, below: bar.maxY, in: area, from: bar.maxY + margin),
                                width: side, height: side)
        return ControlZones(
            pad: padZone, face: mirrored(padZone, in: area),
            leftShoulder: left, rightShoulder: mirrored(left, in: area),
            menu: menu.first, menuTrailing: menu.second, overlapsScreen: false
        )
    }

    /// A band too low for a bar: pad, the menu in a column and the face
    /// buttons side by side over its height, L and R over the lower corners
    /// of `shoulderArea`.
    func lowBandZones(in area: PixelRect, shoulderArea: PixelRect) -> ControlZones {
        let inner = area.inset(all: margin)
        let corners = shoulderArea.inset(all: margin).below(topGuard)
        let shoulderWidth = min(corners.width / 4, hingeShoulder)
        let height = min(shoulder, corners.height)
        let width = min(inner.width / 3, menuColumn)
        let side = max(0, (inner.width - width - 2 * margin) / 2)
        return ControlZones(
            pad: PixelRect(x: inner.minX, y: inner.minY, width: side, height: inner.height),
            face: PixelRect(x: inner.maxX - side, y: inner.minY, width: side, height: inner.height),
            leftShoulder: PixelRect(x: corners.minX, y: corners.maxY - height, width: shoulderWidth, height: height),
            rightShoulder: PixelRect(x: corners.maxX - shoulderWidth, y: corners.maxY - height, width: shoulderWidth, height: height),
            menu: PixelRect(x: inner.minX + side + margin, y: inner.minY, width: width, height: inner.height),
            overlapsScreen: false
        )
    }

    /// The controls of two screens with the hinge of the case in `row`,
    /// between or below them: L and R at the ends of the hinge, and from
    /// `top` on the pad at the left, the face buttons at the right, two
    /// squares of one size that mirror each other, and the menu in the
    /// middle between them over the same rows, in a row where the room is
    /// wide enough and in a column otherwise. Pad and face buttons begin
    /// and end where `plate`, the bezel of the screens, does, where that
    /// keeps them clear of the menu; otherwise the spaces beside the pad,
    /// the menu and the face buttons are all equal. L and R begin and end
    /// where pad and face buttons do.
    func hingeZones(row: PixelRect, below top: Int, in area: PixelRect, plate: PixelRect) -> ControlZones {
        let room = max(0, area.maxY - top)
        var side = min(pad, room)
        func fits(_ menu: Int) -> Bool { 2 * side + menu + 2 * menuKeepOut + 2 * margin <= area.width }
        var menuWidth = self.menuWidth
        if !fits(menuWidth) { menuWidth = menuColumn }
        if !fits(menuWidth) { menuWidth = narrowMenuColumn }
        side = max(0, min(side, (area.width - menuWidth - 2 * menuKeepOut - 2 * margin) / 2))
        let free = area.width - 2 * side - menuWidth
        let aligned = plate.minX - area.minX
        let inset = aligned >= margin && free / 2 - aligned >= menuKeepOut
            ? aligned : max(margin, min(free / 4, free / 2 - menuKeepOut))
        let padZone = PixelRect(x: area.minX + inset, y: centred(side, below: top, in: area), width: side, height: side)
        let faceZone = mirrored(padZone, in: area)
        let between = max(0, faceZone.minX - padZone.maxX - 2 * menuKeepOut)
        let width = min(menuWidth, between)
        let menu = PixelRect(x: area.minX + (area.width - width) / 2, y: padZone.minY, width: width, height: side)
        let shoulderWidth = max(0, min(hingeShoulder, (row.width - margin) / 2 - inset))
        let left = PixelRect(x: padZone.minX, y: row.minY, width: shoulderWidth, height: row.height)
        return ControlZones(
            pad: padZone, face: faceZone, leftShoulder: left, rightShoulder: mirrored(left, in: area),
            menu: menu, overlapsScreen: false
        )
    }

    /// Columns at the left and right of `area`, up to the bezel of the
    /// screen when `screen` is given and otherwise `column` wide over
    /// whatever lies there. Each holds a square, the pad at the left and the
    /// face buttons at the right, on the centre line of the screen, and L
    /// or R above it, as wide as the square: level with the upper edge of
    /// the bezel beside them, or a gap above the square where no bezel
    /// gives them a line. The menu sits between the columns right below
    /// `picture`. Where the room below it is too low for a row, the menu
    /// covers the lower edge of a picture without touch; below a touch
    /// screen its two parts go to the bottom of the columns instead.
    func sideZones(in area: PixelRect, beside screen: PixelRect?, below picture: PixelRect, mayCoverPicture: Bool) -> ControlZones {
        let leftWidth = screen.map { min(max(0, $0.minX - bezel - area.minX), area.width) } ?? min(column, area.width / 2)
        let rightWidth = screen.map { min(max(0, area.maxX - $0.maxX - bezel), area.width) } ?? min(column, area.width / 2)
        let width = min(leftWidth, rightWidth)
        let bottom = min(area.maxY, inputSafe.maxY)
        let left = PixelRect(x: area.minX + margin, y: max(area.minY, topGuard), width: max(0, width - 2 * margin),
                             height: max(0, bottom - margin - max(area.minY, topGuard)))
        let right = mirrored(left, in: area)

        let between = PixelRect(x: left.maxX + menuKeepOut, y: area.minY,
                                width: max(0, right.minX - left.maxX - 2 * menuKeepOut), height: area.height)
        let free = bottom - picture.maxY
        // Where the menu takes the bottom of the columns, they end above it.
        var rows = left
        let menu: (first: PixelRect, second: PixelRect?)
        if free >= minimumMenuRow {
            // The bezel and a margin above the menu; where the room is
            // short, the menu row gets lower before it comes closer to the
            // bezel than a hairline.
            let gap = max(0, min(clearance, free - menuRow), min(bezel + hairline, free - minimumMenuRow))
            menu = divided(PixelRect(x: between.minX, y: picture.maxY + gap, width: between.width, height: min(menuRow, free - gap)))
        } else if mayCoverPicture {
            menu = divided(PixelRect(x: between.minX, y: bottom - margin - menuRow, width: between.width, height: menuRow))
        } else {
            let first = left.below(left.maxY - menuRow)
            rows = left.above(first.minY - margin)
            menu = (first, mirrored(first, in: area))
        }

        let side = max(0, min(pad, rows.width, rows.height - shoulder - margin))
        // L and R level with the upper edge of the bezel beside them.
        let level = screen.map { max(rows.minY, $0.minY - bezel) }
        // The square on the centre line of the screen, below L or R.
        let middle = (screen ?? picture).minY + (screen ?? picture).height / 2
        let y = max((level ?? rows.minY) + shoulder + margin, min(middle - side / 2, rows.maxY - side))
        let padZone = PixelRect(x: rows.minX + (rows.width - side) / 2, y: y, width: side, height: side)
        let shoulderTop = level ?? max(rows.minY, y - shoulderGap - shoulder)
        let leftShoulder = PixelRect(x: padZone.minX, y: shoulderTop, width: side, height: shoulder)
        return ControlZones(pad: padZone, face: mirrored(padZone, in: area),
                            leftShoulder: leftShoulder, rightShoulder: mirrored(leftShoulder, in: area),
                            menu: menu.first, menuTrailing: menu.second, overlapsScreen: false)
    }

    /// The controls below two screens that lie side by side with a fold
    /// between them: a bar in the top row with L at the outer left, the menu
    /// on both sides of the fold and R at the outer right, and below the bar
    /// the pad on the left page and the face buttons on the right page, two
    /// squares of one size over the same rows, as far from the outer edges
    /// as each other and, where that is no more than a margin and
    /// `sideInset`, as the screens (`inset`), in the middle between the bar
    /// and the lower edge of the view. L and R begin and end where pad and
    /// face buttons do.
    func pageZones(left leftPage: PixelRect, right rightPage: PixelRect, inset screenInset: Int) -> ControlZones {
        let top = max(max(leftPage.minY, rightPage.minY) + clearance, topGuard)
        let bottom = min(leftPage.maxY, rightPage.maxY)
        let pages = PixelRect(x: leftPage.minX, y: top, width: rightPage.maxX - leftPage.minX, height: max(0, bottom - top))
        // As far from the outer edges as the screens above them, so that
        // picture, L and pad begin on one line.
        let inset = max(margin, min(screenInset, sideInset + margin))
        let page = min(leftPage.width, rightPage.width)
        let side = max(0, min(pad, pages.height - menuRow - margin, page - 2 * inset))
        let part = min(menuPart, max(0, page - 2 * margin - minimumShoulder))
        let first = PixelRect(x: leftPage.maxX - margin - part, y: top, width: part, height: menuRow)
        let second = PixelRect(x: rightPage.minX + margin, y: top, width: part, height: menuRow)
        let outer = min(inset, max(margin, (page - side) / 2))
        let padZone = PixelRect(x: leftPage.minX + outer, y: centred(side, below: top + menuRow, in: pages, from: top + menuRow + margin),
                                width: side, height: side)
        let faceZone = PixelRect(x: rightPage.maxX - outer - side, y: padZone.minY, width: side, height: side)
        let shoulderWidth = max(0, min(side, first.minX - margin - padZone.minX))
        return ControlZones(
            pad: padZone, face: faceZone,
            leftShoulder: PixelRect(x: padZone.minX, y: top, width: shoulderWidth, height: menuRow),
            rightShoulder: PixelRect(x: faceZone.maxX - shoulderWidth, y: top, width: shoulderWidth, height: menuRow),
            menu: first, menuTrailing: second, overlapsScreen: false
        )
    }

    /// The menu in `band`: one zone in its middle, at most `menuWidth` wide.
    /// A fold from top to bottom that runs through the band, active or not,
    /// divides the menu into a part before it and a part behind it.
    func divided(_ band: PixelRect) -> (first: PixelRect, second: PixelRect?) {
        if let fold = geometry.fold, !foldIsHorizontal, fold.minX < band.maxX, fold.maxX > band.minX {
            let before = band.left(of: fold.minX - margin)
            let behind = band.right(of: fold.maxX + margin)
            return (before.right(of: before.maxX - min(menuPart, before.width)),
                    behind.left(of: behind.minX + min(menuPart, behind.width)))
        }
        let width = min(menuWidth, band.width)
        return (PixelRect(x: band.minX + (band.width - width) / 2, y: band.minY, width: width, height: band.height), nil)
    }

    /// What controls stay off: the touch screen and an active fold with its
    /// margins.
    func obstacles(touchScreen: PixelRect?) -> [PixelRect] {
        var obstacles: [PixelRect] = []
        if let touchScreen {
            obstacles.append(touchScreen)
        }
        if geometry.isFoldActive, let fold = geometry.fold {
            obstacles.append(fold)
        }
        return obstacles
    }

    /// The rules every template keeps, enforced once more: every zone in the
    /// safe area below the top edge guard, none on the touch screen or an
    /// active fold, pad and face buttons over the same rows. Marks zones
    /// that cover a screen. Occlusion regions do not move the zones yet: on
    /// the outer display they lie outside the safe area, on the inner one
    /// the device test measures them first.
    func finished(_ zones: ControlZones, screens: [PlacedScreen], touchScreen: PixelRect?) -> ControlZones {
        let obstacles = obstacles(touchScreen: touchScreen)
        func clear(_ zone: PixelRect) -> PixelRect {
            obstacles.reduce(zone.intersection(inputSafe)) { $0.avoiding($1) }
        }
        var result = ControlZones(
            pad: clear(zones.pad), face: clear(zones.face), leftShoulder: clear(zones.leftShoulder),
            rightShoulder: clear(zones.rightShoulder), menu: clear(zones.menu),
            menuTrailing: zones.menuTrailing.map(clear), leftShoulderCap: zones.leftShoulderCap.map(clear),
            rightShoulderCap: zones.rightShoulderCap.map(clear), overlapsScreen: false
        )
        if !result.pad.isEmpty, !result.face.isEmpty {
            let top = max(result.pad.minY, result.face.minY)
            let bottom = min(result.pad.maxY, result.face.maxY)
            result.pad = result.pad.below(top).above(bottom)
            result.face = result.face.below(top).above(bottom)
        }
        result.overlapsScreen = result.all.contains { zone in screens.contains { zone.intersects($0.destination) } }
        return result
    }

    /// The pause button while no touch controls show: the first corner of
    /// the safe area below the top edge guard that touches neither the touch
    /// screen, an active fold nor an occlusion region, in the order lower
    /// right, lower left, upper right, upper left, and that keeps clear of
    /// every screen with its bezel, so that it stands in the case. Where no
    /// corner of the case has the room, it lies inside a screen without
    /// touch, at the first of its corners in the same order, as in M1, and
    /// never across the edge of a bezel.
    func pauseButton(screens: [PlacedScreen], touchScreen: PixelRect?) -> PixelRect {
        let area = inputSafe.inset(all: margin)
        let side = max(0, min(pauseSide, area.width, area.height))
        func corners(of area: PixelRect) -> [PixelRect] {
            [
                PixelRect(x: area.maxX - side, y: area.maxY - side, width: side, height: side),
                PixelRect(x: area.minX, y: area.maxY - side, width: side, height: side),
                PixelRect(x: area.maxX - side, y: area.minY, width: side, height: side),
                PixelRect(x: area.minX, y: area.minY, width: side, height: side),
            ]
        }
        let obstacles = obstacles(touchScreen: touchScreen) + geometry.occlusions
        func isFree(_ corner: PixelRect) -> Bool { !obstacles.contains { corner.intersects($0) } }
        let framed = screens.map { $0.destination.inset(all: -bezel) }
        let inCase = corners(of: area).first { corner in isFree(corner) && !framed.contains { corner.intersects($0) } }
        if let inCase { return inCase }
        for screen in screens.map(\.destination) where screen != touchScreen {
            let inside = screen.intersection(area).inset(all: margin)
            guard inside.width >= side, inside.height >= side else { continue }
            if let corner = corners(of: inside).first(where: isFree) { return corner }
        }
        return corners(of: area).first(where: isFree) ?? corners(of: area)[0]
    }
}
