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

/// Sizes of the touch controls, in points.
public struct LayoutMetrics: Sendable, Hashable {
    /// The narrowest column beside a screen that still holds the pad or the
    /// face buttons.
    public var controlColumn: Int
    /// The lowest band below a screen that still holds pad, face buttons and
    /// Start/Select.
    public var controlBand: Int
    /// Space around the controls.
    public var margin: Int
    /// The band at the top edge of the view that nothing taking touches
    /// covers: no control, no touch screen, no pause button. The top edge
    /// belongs to the system's edge gestures, and thumbs reach it worst. A
    /// safe area inset at the top counts towards it. Screens without touch
    /// may lie in it (ADR 0006, section "Nachbesserungen nach der Prüfung").
    public var topEdgeGuard: Int

    public init(controlColumn: Int = 112, controlBand: Int = 128, margin: Int = 8, topEdgeGuard: Int = 64) {
        self.controlColumn = controlColumn
        self.controlBand = controlBand
        self.margin = margin
        self.topEdgeGuard = topEdgeGuard
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

/// Where the touch controls go, in pixels of the view. Each control is drawn
/// inside its zone; the app turns the zones into buttons.
public struct ControlZones: Sendable, Hashable {
    public var pad: PixelRect
    public var face: PixelRect
    public var leftShoulder: PixelRect
    public var rightShoulder: PixelRect
    /// Start and Select, and room for the app's pause button between them.
    public var menu: PixelRect
    /// A zone covers part of a screen; the app draws the controls translucent.
    public var overlapsScreen: Bool

    public init(
        pad: PixelRect, face: PixelRect, leftShoulder: PixelRect, rightShoulder: PixelRect,
        menu: PixelRect, overlapsScreen: Bool
    ) {
        self.pad = pad
        self.face = face
        self.leftShoulder = leftShoulder
        self.rightShoulder = rightShoulder
        self.menu = menu
        self.overlapsScreen = overlapsScreen
    }

    /// Every zone, in the order pad, face, left shoulder, right shoulder, menu.
    public var all: [PixelRect] {
        [pad, face, leftShoulder, rightShoulder, menu]
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

    public init(
        posture: Posture, isLandscape: Bool, screens: [PlacedScreen], controls: ControlZones?,
        touchScreenIndex: Int?, pauseButton: PixelRect? = nil
    ) {
        self.posture = posture
        self.isLandscape = isLandscape
        self.screens = screens
        self.controls = controls
        self.touchScreenIndex = touchScreenIndex
        self.pauseButton = pauseButton
    }

    /// The layout of `system` in `geometry`. The rules: screens stay in the
    /// safe area and never on an active fold, except a single screen in the
    /// book posture; controls never lie on the touch screen or on an active
    /// fold; nothing that takes touches lies in the top edge guard; every
    /// screen is scaled by a whole number; without touch controls the screens
    /// grow. The templates per system and posture are in ADR 0006.
    public init(
        system: SystemScreens, geometry: FoldGeometry, showsTouchControls: Bool,
        metrics: LayoutMetrics = .standard
    ) {
        let templates = Templates(geometry: geometry, metrics: metrics, showsControls: showsTouchControls)
        let (screens, zones) = system.sources.count == 1
            ? templates.oneScreen(system.sources[0])
            : templates.twoScreens(upper: system.sources[0], lower: system.sources[1])
        let touchScreen = system.touchScreen.map { screens[$0].destination }
        let controls = zones.map { templates.finished($0, screens: screens, touchScreen: touchScreen) }
        self.init(
            posture: geometry.posture, isLandscape: geometry.container.isLandscape, screens: screens,
            controls: controls, touchScreenIndex: system.touchScreen,
            pauseButton: controls == nil ? templates.pauseButton(touchScreen: touchScreen) : nil
        )
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
    /// The safe part of the view.
    let safe: PixelRect
    let showsControls: Bool
    /// LayoutMetrics in pixels.
    let column: Int
    let band: Int
    let margin: Int
    /// The height of an L or R button.
    let shoulder: Int
    /// The height of Start, Select and the pause button.
    let menuRow: Int
    /// The smallest pad or set of face buttons that is still comfortable.
    let minimumControl: Int
    /// The widest row of Start, Select and the pause button.
    let menuWidth: Int
    /// The widest middle column of Start, Select and the pause button between
    /// pad and face buttons in a low band.
    let menuColumn: Int
    /// The widest L or R button over the corner of a screen.
    let cornerShoulder: Int
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
        safe = geometry.safeBounds
        topGuard = GameLayout.firstInputRow(in: geometry, metrics: metrics)
        inputSafe = geometry.safeBounds.below(topGuard)
        pauseSide = 44 * s
        self.showsControls = showsControls
        column = metrics.controlColumn * s
        band = metrics.controlBand * s
        margin = metrics.margin * s
        shoulder = 44 * s
        menuRow = 36 * s
        minimumControl = 96 * s
        menuWidth = 240 * s
        menuColumn = 140 * s
        cornerShoulder = 96 * s
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

    // MARK: One screen (GBA and the later single-screen systems)

    func oneScreen(_ source: PixelRect) -> ([PlacedScreen], ControlZones?) {
        switch posture {
        case .single where geometry.container.isLandscape:
            // As large as the view allows; the controls sit in columns at the
            // sides, over the screen unless the columns cost no scale (as M1).
            let full = scale(source, in: safe.width, safe.height)
            let screen = place(source, scale: full, in: safe)
            guard showsControls else { return ([screen], nil) }
            let beside = scale(source, in: safe.width - 2 * column, safe.height)
            let zones = beside < full ? sideZones(in: safe, beside: nil) : sideZones(in: safe, beside: screen.destination)
            return ([screen], zones)
        case .single:
            // Upright: at the top over the full width, the controls below.
            guard showsControls else {
                return ([place(source, scale: scale(source, in: safe.width, safe.height), in: safe)], nil)
            }
            let k = scale(source, in: safe.width, safe.height - band)
            let screen = place(source, scale: k, in: safe, alignment: .top)
            return ([screen], bandZones(in: safe.below(screen.destination.maxY),
                                        shoulderArea: safe.above(screen.destination.maxY)))
        case .flat where !foldIsHorizontal:
            // Open sideways or like a book: across the fold, columns of at
            // least `column` on both sides.
            guard showsControls else {
                return ([place(source, scale: scale(source, in: safe.width, safe.height), in: safe)], nil)
            }
            let k = scale(source, in: safe.width - 2 * column, safe.height)
            let screen = place(source, scale: k, in: safe)
            return ([screen], sideZones(in: safe, beside: screen.destination))
        case .flat, .tabletop:
            // The fold across the view: the screen in the upper part, the
            // controls in the lower part.
            let (_, lower, upperForScreen, _) = split()
            let screen = place(source, scale: scale(source, in: upperForScreen.width, upperForScreen.height), in: upperForScreen)
            return ([screen], showsControls ? bandZones(in: lower, shoulderArea: lower) : nil)
        }
    }

    // MARK: Two screens (DS)

    func twoScreens(upper: PixelRect, lower: PixelRect) -> ([PlacedScreen], ControlZones?) {
        let stack = PixelRect(x: 0, y: 0, width: max(upper.width, lower.width), height: upper.height + lower.height)
        switch posture {
        case .single where geometry.container.isLandscape:
            // Both screens stacked in the middle, the controls in columns beside them.
            let k = showsControls ? scale(stack, in: safe.width - 2 * column, safe.height) : scale(stack, in: safe.width, safe.height)
            let block = place(stack, scale: k, in: safe)
            let screens = stacked(upper: upper, lower: lower, scale: k, block: block.destination)
            return (screens, showsControls ? sideZones(in: safe, beside: block.destination) : nil)
        case .single:
            // Both screens at the top, the controls below; L and R over the
            // upper screen when the band below is too low for them.
            let k = showsControls ? scale(stack, in: safe.width, safe.height - band) : scale(stack, in: safe.width, safe.height)
            let block = place(stack, scale: k, in: safe, alignment: showsControls ? .top : .center)
            let screens = stacked(upper: upper, lower: lower, scale: k, block: block.destination)
            guard showsControls else { return (screens, nil) }
            return (screens, bandZones(in: safe.below(block.destination.maxY),
                                       shoulderArea: safe.above(screens[0].destination.maxY)))
        case .flat where !foldIsHorizontal:
            // Sideways or like a book: the upper screen left of the fold, the
            // touch screen right of it, both at the top below the top edge
            // guard, the controls below them; nothing on the fold. The touch
            // screen stays out of the fold's margins like the controls, and
            // the upper screen stays level with it.
            let (left, right, leftForScreen, _) = split()
            let leftArea = leftForScreen.below(topGuard)
            let rightArea = right.below(topGuard)
            let height = showsControls ? min(leftArea.height, rightArea.height) - band : min(leftArea.height, rightArea.height)
            let k = min(scale(upper, in: leftArea.width, height), scale(lower, in: rightArea.width, height))
            let alignment: Alignment = showsControls ? .top : .center
            let upperScreen = place(upper, scale: k, in: leftArea, alignment: alignment)
            let touchScreen = place(lower, scale: k, in: rightArea, alignment: alignment)
            guard showsControls else { return ([upperScreen, touchScreen], nil) }
            let top = max(upperScreen.destination.maxY, touchScreen.destination.maxY)
            return ([upperScreen, touchScreen], columnZones(left: left.below(top), right: right.below(top)))
        case .flat:
            // Flat, the fold across: the upper screen above, the touch screen
            // below the fold at the same scale, the controls beside it.
            let (_, lowerPart, upperForScreen, _) = split()
            let kUpper = scale(upper, in: upperForScreen.width, upperForScreen.height)
            let kLower = showsControls
                ? scale(lower, in: lowerPart.width - 2 * column, lowerPart.height)
                : scale(lower, in: lowerPart.width, lowerPart.height)
            let k = min(kUpper, kLower)
            let upperScreen = place(upper, scale: k, in: upperForScreen)
            let touchScreen = place(lower, scale: k, in: lowerPart)
            return ([upperScreen, touchScreen], showsControls ? sideZones(in: lowerPart, beside: touchScreen.destination) : nil)
        case .tabletop:
            // The upper screen as large as the upper part allows, the touch
            // screen and the controls below the fold (plan, section 7).
            let (_, lowerPart, upperForScreen, _) = split()
            let kUpper = scale(upper, in: upperForScreen.width, upperForScreen.height)
            let kLower = showsControls
                ? scale(lower, in: lowerPart.width - 2 * column, lowerPart.height)
                : scale(lower, in: lowerPart.width, lowerPart.height)
            let upperScreen = place(upper, scale: kUpper, in: upperForScreen)
            let touchScreen = place(lower, scale: kLower, in: lowerPart)
            return ([upperScreen, touchScreen], showsControls ? sideZones(in: lowerPart, beside: touchScreen.destination) : nil)
        }
    }

    func stacked(upper: PixelRect, lower: PixelRect, scale k: Int, block: PixelRect) -> [PlacedScreen] {
        let upperScreen = PixelRect(x: block.x + (block.width - upper.width * k) / 2, y: block.y,
                                    width: upper.width * k, height: upper.height * k)
        let lowerScreen = PixelRect(x: block.x + (block.width - lower.width * k) / 2, y: upperScreen.maxY,
                                    width: lower.width * k, height: lower.height * k)
        return [PlacedScreen(source: upper, destination: upperScreen, scale: k),
                PlacedScreen(source: lower, destination: lowerScreen, scale: k)]
    }

    // MARK: Control zones

    /// The controls in a band below the screens: L and R in its top row,
    /// pad and face buttons below them and Start/Select at the bottom. A band
    /// too low for that puts L and R over the lower corners of `shoulderArea`
    /// (not the upper ones: the top edge belongs to system gestures and is
    /// hard to reach), and one too low for a row of its own puts
    /// Start/Select in a column between pad and face buttons.
    func bandZones(in area: PixelRect, shoulderArea: PixelRect) -> ControlZones {
        let inner = area.inset(all: margin)
        var body = inner
        let leftShoulder: PixelRect
        let rightShoulder: PixelRect
        if inner.height >= shoulder + margin + minimumControl + margin + menuRow {
            let half = (inner.width - margin) / 2
            leftShoulder = PixelRect(x: inner.minX, y: inner.minY, width: half, height: shoulder)
            rightShoulder = PixelRect(x: inner.maxX - half, y: inner.minY, width: half, height: shoulder)
            body = inner.below(inner.minY + shoulder + margin)
        } else {
            let corners = shoulderArea.inset(all: margin).below(topGuard)
            let width = min(corners.width / 4, cornerShoulder)
            let height = min(shoulder, corners.height)
            leftShoulder = PixelRect(x: corners.minX, y: corners.maxY - height, width: width, height: height)
            rightShoulder = PixelRect(x: corners.maxX - width, y: corners.maxY - height, width: width, height: height)
        }
        let pad: PixelRect
        let face: PixelRect
        let menu: PixelRect
        if body.height >= minimumControl + margin + menuRow {
            let width = min(body.width / 2, menuWidth)
            menu = PixelRect(x: body.minX + (body.width - width) / 2, y: body.maxY - menuRow, width: width, height: menuRow)
            let controls = body.above(menu.minY - margin)
            let half = (controls.width - margin) / 2
            pad = PixelRect(x: controls.minX, y: controls.minY, width: half, height: controls.height)
            face = PixelRect(x: controls.maxX - half, y: controls.minY, width: half, height: controls.height)
        } else {
            let width = min(body.width / 3, menuColumn)
            let side = max(0, (body.width - width - 2 * margin) / 2)
            pad = PixelRect(x: body.minX, y: body.minY, width: side, height: body.height)
            menu = PixelRect(x: body.minX + side + margin, y: body.minY, width: width, height: body.height)
            face = PixelRect(x: body.maxX - side, y: body.minY, width: side, height: body.height)
        }
        return ControlZones(pad: pad, face: face, leftShoulder: leftShoulder, rightShoulder: rightShoulder,
                            menu: menu, overlapsScreen: false)
    }

    /// Columns at the left and right of `area`: up to the screen when
    /// `screen` is given, otherwise `column` wide over whatever lies there.
    func sideZones(in area: PixelRect, beside screen: PixelRect?) -> ControlZones {
        let leftWidth = screen.map { min(max(0, $0.minX - area.minX), area.width) } ?? min(column, area.width / 2)
        let rightWidth = screen.map { min(max(0, area.maxX - $0.maxX), area.width) } ?? min(column, area.width / 2)
        return columnZones(left: PixelRect(x: area.minX, y: area.minY, width: leftWidth, height: area.height),
                           right: PixelRect(x: area.maxX - rightWidth, y: area.minY, width: rightWidth, height: area.height))
    }

    /// L at the top of the left column with the pad below it; R at the top of
    /// the right column, the face buttons below it and Start/Select at its
    /// bottom, in one row when the column is wide enough and stacked otherwise.
    /// The columns begin below the top edge guard.
    func columnZones(left leftColumn: PixelRect, right rightColumn: PixelRect) -> ControlZones {
        let left = leftColumn.inset(all: margin).below(topGuard)
        let right = rightColumn.inset(all: margin).below(topGuard)
        let leftShoulder = left.above(left.minY + shoulder)
        let rightShoulder = right.above(right.minY + shoulder)
        let menuHeight = right.width >= 2 * menuColumn ? menuRow : 3 * menuRow + 2 * margin
        let menu = right.below(right.maxY - menuHeight)
        let pad = left.below(leftShoulder.maxY + margin)
        let face = right.below(rightShoulder.maxY + margin).above(menu.minY - margin)
        return ControlZones(pad: pad, face: face, leftShoulder: leftShoulder, rightShoulder: rightShoulder,
                            menu: menu, overlapsScreen: false)
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
    /// active fold. Marks zones that cover a screen. Occlusion regions do not
    /// move the zones yet: on the outer display they lie outside the safe
    /// area, on the inner one the device test measures them first.
    func finished(_ zones: ControlZones, screens: [PlacedScreen], touchScreen: PixelRect?) -> ControlZones {
        let obstacles = obstacles(touchScreen: touchScreen)
        func clear(_ zone: PixelRect) -> PixelRect {
            obstacles.reduce(zone.intersection(inputSafe)) { $0.avoiding($1) }
        }
        var result = ControlZones(
            pad: clear(zones.pad), face: clear(zones.face), leftShoulder: clear(zones.leftShoulder),
            rightShoulder: clear(zones.rightShoulder), menu: clear(zones.menu), overlapsScreen: false
        )
        result.overlapsScreen = result.all.contains { zone in screens.contains { zone.intersects($0.destination) } }
        return result
    }

    /// The pause button while no touch controls show: the first corner of
    /// the safe area below the top edge guard that touches neither the touch
    /// screen, an active fold nor an occlusion region, in the order lower
    /// right, lower left, upper right, upper left. It may lie over a screen
    /// without touch, as in M1.
    func pauseButton(touchScreen: PixelRect?) -> PixelRect {
        let area = inputSafe.inset(all: margin)
        let side = max(0, min(pauseSide, area.width, area.height))
        let corners = [
            PixelRect(x: area.maxX - side, y: area.maxY - side, width: side, height: side),
            PixelRect(x: area.minX, y: area.maxY - side, width: side, height: side),
            PixelRect(x: area.maxX - side, y: area.minY, width: side, height: side),
            PixelRect(x: area.minX, y: area.minY, width: side, height: side),
        ]
        let obstacles = obstacles(touchScreen: touchScreen) + geometry.occlusions
        return corners.first { corner in !obstacles.contains { corner.intersects($0) } } ?? corners[0]
    }
}
