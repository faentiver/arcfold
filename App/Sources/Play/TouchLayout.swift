import CoreGraphics
import FoldLayout
import Foundation
import LibretroKit

/// Where the touch controls sit and which buttons a set of touches presses.
/// A pure value built from the zones of `GameLayout` (ADR 0006): the mask
/// comes from `buttons(at:)` without a session, so tests can check it
/// directly (ADR 0005, section 7). All values are points of the game view.
///
/// Each control fills its zone: the pad and the face buttons their squares,
/// L and R their place in the bar, Select, Start and the menu button the
/// menu zone as small buttons with their names (ADR 0007).
nonisolated struct TouchLayout: Sendable, Hashable {
    /// The direction pad: a circle split into eight sectors around a dead zone.
    struct Pad: Sendable, Hashable {
        var center: CGPoint
        var radius: CGFloat
    }

    /// A button with a text label; no original symbols (hard rules in CLAUDE.md).
    struct Button: Sendable, Hashable, Identifiable {
        enum Shape: Sendable, Hashable {
            /// A round face button.
            case circle
            /// A wide button: L and R.
            case capsule
            /// A small round button with its name below or beside it:
            /// Select and Start. The frame holds both and takes the touches.
            case knob
        }

        var buttons: JoypadButtons
        var label: String
        /// What the button draws.
        var frame: CGRect
        var shape: Shape
        /// What takes its touches: `frame`, or more where the button draws
        /// smaller than a finger needs, like L and R at the ends of a slim
        /// hinge.
        var target: CGRect

        init(buttons: JoypadButtons, label: String, frame: CGRect, shape: Shape, target: CGRect? = nil) {
            self.buttons = buttons
            self.label = label
            self.frame = frame
            self.shape = shape
            self.target = target ?? frame
        }

        var id: String { label }
    }

    /// Where touches may count at all, in points of the game view: from the
    /// first row that may take touches down (the top edge guard, or the
    /// safe area's top when it is lower), and off the active fold with its
    /// margins. The zones keep to the same limits; these stop the slop
    /// around a button and the reach of the pad there (ADR 0006).
    struct Limits: Sendable, Hashable {
        var inputTop: CGFloat = 0
        var fold: CGRect?

        /// No limits.
        static let none = Limits()

        init(inputTop: CGFloat = 0, fold: CGRect? = nil) {
            self.inputTop = inputTop
            self.fold = fold
        }

        /// The limits of `geometry`, which the caller measured.
        init(geometry: FoldGeometry) {
            let s = CGFloat(max(1, geometry.scale))
            inputTop = CGFloat(GameLayout.firstInputRow(in: geometry)) / s
            fold = geometry.isFoldActive ? geometry.fold.map { $0.points(scale: geometry.scale) } : nil
        }

        /// A touch at `point` may count.
        func accepts(_ point: CGPoint) -> Bool {
            point.y >= inputTop && fold?.contains(point) != true
        }
    }

    /// Where the name of a small button stands.
    enum KnobLabel: Sendable, Hashable {
        /// Below the button: Select, the menu button and Start in a row.
        case below
        /// Right of the button: the three in a column.
        case beside
    }

    var pad: Pad
    var buttons: [Button]
    /// The app's menu button, which pauses the game: a small button like
    /// Select and Start, between or below them. The frame holds the button
    /// and its name.
    var pauseButton: CGRect
    /// Where Select, Start and the menu button carry their names.
    var knobLabel: KnobLabel
    /// The controls lie over a screen; drawn translucent there.
    var overlapsScreen: Bool
    /// Where touches may count at all.
    var limits: Limits

    /// Touches closer to the pad's centre than this share of its radius press nothing.
    static let deadZone: CGFloat = 0.3
    /// Touches count for the pad up to this multiple of its radius, where no
    /// button claims them.
    static let padReach: CGFloat = 1.4
    /// Buttons react a bit beyond what they draw.
    static let buttonSlop: CGFloat = 0.25

    /// Largest sizes, in points.
    static let largestPadRadius: CGFloat = 85
    static let largestShoulderWidth: CGFloat = 170
    /// The height of L and R in every pose, the one the layout keeps for
    /// them (`LayoutMetrics.shoulderHeight`).
    static let shoulderHeight = CGFloat(LayoutMetrics.standard.shoulderHeight)
    /// What L and R at the ends of a slim hinge keep from its edges: the
    /// well they stand in.
    static let slimWell: CGFloat = 1
    /// The share of their square that each of the two face buttons of the
    /// GBA and each of the four of the DS takes: 83 pt in a square of 170,
    /// 56 pt in one of 146.
    static let pairShare: CGFloat = 0.49
    static let diamondShare: CGFloat = 0.382
    /// How far A stands above B, as a share of their diameter.
    static let pairRise: CGFloat = 0.5
    /// A small button with its name below it: the row is this high (the
    /// row the layout keeps, `LayoutMetrics.menuRow`) and each of the three
    /// this wide, a target of at least 44 pt each way.
    static let rowHeight = CGFloat(LayoutMetrics.standard.menuRow)
    static let knobCell: CGFloat = 60
    /// The widest a small button with its name beside it becomes.
    static let knobRow: CGFloat = 100
    static let gap: CGFloat = 8

    /// The controls in `zones`, which are pixels at `scale` pixels per point.
    /// X and Y only for systems that have them. `limits` come from the
    /// caller, which knows the geometry the zones were made for.
    init(zones: ControlZones, scale: Int, hasXYButtons: Bool, limits: Limits = .none) {
        self.limits = limits
        let s = CGFloat(max(1, scale))
        func points(_ rect: PixelRect) -> CGRect {
            CGRect(x: CGFloat(rect.x) / s, y: CGFloat(rect.y) / s, width: CGFloat(rect.width) / s, height: CGFloat(rect.height) / s)
        }
        let padZone = points(zones.pad)
        pad = Pad(center: CGPoint(x: padZone.midX, y: padZone.midY),
                  radius: min(min(padZone.width, padZone.height) / 2, Self.largestPadRadius))
        overlapsScreen = zones.overlapsScreen

        var buttons = Self.faceButtons(in: points(zones.face), hasXYButtons: hasXYButtons)
        buttons.append(Self.shoulder(.l, "L", in: points(zones.leftShoulder), cap: zones.leftShoulderCap.map(points),
                                     alignedLeft: true))
        buttons.append(Self.shoulder(.r, "R", in: points(zones.rightShoulder), cap: zones.rightShoulderCap.map(points),
                                     alignedLeft: false))
        let menu = Self.menu(in: points(zones.menu), trailing: zones.menuTrailing.map(points))
        buttons.append(Button(buttons: .select, label: "Select", frame: menu.select, shape: .knob))
        buttons.append(Button(buttons: .start, label: "Start", frame: menu.start, shape: .knob))
        self.buttons = buttons.filter { !$0.frame.isEmpty }
        pauseButton = menu.pause
        knobLabel = menu.label
    }

    /// A and B on a diagonal as on the GBA, A at the upper right and B at
    /// the lower left, or X, A, B and Y as a diamond as on the DS. Both
    /// fill the square in the middle of `zone` from edge to edge, so the
    /// face buttons are as wide as the pad and as far from their edge.
    private static func faceButtons(in zone: CGRect, hasXYButtons: Bool) -> [Button] {
        let side = min(zone.width, zone.height, 2 * largestPadRadius)
        let center = CGPoint(x: zone.midX, y: zone.midY)
        func circle(_ dx: CGFloat, _ dy: CGFloat, diameter: CGFloat) -> CGRect {
            CGRect(x: center.x + dx - diameter / 2, y: center.y + dy - diameter / 2, width: diameter, height: diameter)
        }
        guard hasXYButtons else {
            let diameter = side * pairShare
            let dx = (side - diameter) / 2
            let dy = diameter * pairRise / 2
            return [
                Button(buttons: .a, label: "A", frame: circle(dx, -dy, diameter: diameter), shape: .circle),
                Button(buttons: .b, label: "B", frame: circle(-dx, dy, diameter: diameter), shape: .circle),
            ]
        }
        let diameter = side * diamondShare
        let distance = (side - diameter) / 2
        return [
            Button(buttons: .a, label: "A", frame: circle(distance, 0, diameter: diameter), shape: .circle),
            Button(buttons: .b, label: "B", frame: circle(0, distance, diameter: diameter), shape: .circle),
            Button(buttons: .x, label: "X", frame: circle(0, -distance, diameter: diameter), shape: .circle),
            Button(buttons: .y, label: "Y", frame: circle(-distance, 0, diameter: diameter), shape: .circle),
        ]
    }

    /// A wide button in the middle of the rows of `zone`, at its outer edge.
    /// Where `cap` is given, L or R is the end of a slim hinge: it draws in
    /// `cap`, inside its well, and `zone` takes its touches.
    private static func shoulder(_ buttons: JoypadButtons, _ label: String, in zone: CGRect, cap: CGRect?, alignedLeft: Bool) -> Button {
        if let cap {
            return Button(buttons: buttons, label: label, frame: cap.insetBy(dx: slimWell, dy: slimWell), shape: .capsule,
                          target: zone)
        }
        let width = min(zone.width, largestShoulderWidth)
        let height = min(zone.height, shoulderHeight)
        let x = alignedLeft ? zone.minX : zone.maxX - width
        return Button(buttons: buttons, label: label,
                      frame: CGRect(x: x, y: zone.midY - height / 2, width: width, height: height), shape: .capsule)
    }

    /// The lowest row of the menu that is still a button.
    static let smallestRowHeight: CGFloat = 28

    /// Select, the menu button and Start, each a small button with its
    /// name. In one piece: in one row with the names below when `zone` is
    /// wide enough; in a column of three rows with the names beside when it
    /// is narrower and high enough, with lower rows before the buttons
    /// would stand side by side close to pad and face buttons; Select and
    /// Start above the menu button when it holds two rows, which no pose
    /// of the Duo asks for; and otherwise in one row squeezed to the
    /// zone's width. Divided: Select and the menu
    /// button at the end of `zone` and Start at the beginning of `trailing`,
    /// on both sides of what divides them.
    private static func menu(in zone: CGRect, trailing: CGRect?)
        -> (select: CGRect, pause: CGRect, start: CGRect, label: KnobLabel) {
        let row = min(rowHeight, zone.height)
        // The menu button takes touches on 44 pt whatever its cell
        // (`PauseButton.minimumTarget`); where the cells get narrower, its
        // cell keeps that width and Select and Start give way, so that it
        // never takes their touches.
        let target = PauseButton.minimumTarget
        if let trailing {
            let available = max(0, zone.width - gap)
            let even = min(knobCell, available / 2)
            let pauseCell = max(even, min(target, available))
            let cell = min(even, available - pauseCell)
            let pause = CGRect(x: zone.maxX - pauseCell, y: zone.midY - row / 2, width: pauseCell, height: row)
            let select = CGRect(x: pause.minX - gap - cell, y: pause.minY, width: cell, height: row)
            let start = CGRect(x: trailing.minX, y: trailing.midY - row / 2, width: min(even, trailing.width), height: row)
            return (select, pause, start, .below)
        }
        let oneRow = 3 * knobCell + 2 * gap
        // In a column the buttons stand at equal distances, the middle one
        // in the middle of the zone, and the rows touch, so that each is as
        // high a target as the zone allows. The menu button takes touches
        // on 44 pt whatever its row; what it needs beyond its row comes off
        // the row of Start above it, at both ends, so that Start stays in
        // the middle of its row.
        let columnRow = min(row, zone.height / 3)
        let startRow = columnRow - max(0, PauseButton.minimumTarget - columnRow)
        if zone.width < oneRow, startRow >= smallestRowHeight {
            // A column: Select, Start, the menu button.
            let width = min(knobRow, zone.width)
            let x = zone.midX - width / 2
            let pause = CGRect(x: x, y: zone.midY + 0.5 * columnRow, width: width, height: columnRow)
            // Start ends exactly where the target of the menu button begins.
            let end = startRow < columnRow ? OverlayPlacement.target(around: pause).minY : zone.midY + startRow / 2
            let begin = 2 * zone.midY - end
            return (CGRect(x: x, y: zone.midY - 1.5 * columnRow, width: width, height: columnRow),
                    pause,
                    CGRect(x: x, y: begin, width: width, height: end - begin), .beside)
        }
        if zone.width < oneRow, zone.height >= 2 * row + gap {
            // Two rows: Select and Start, the menu button below them.
            let width = min(knobCell, (zone.width - gap) / 2)
            let top = zone.midY - (2 * row + gap) / 2
            let left = zone.midX - (2 * width + gap) / 2
            return (CGRect(x: left, y: top, width: width, height: row),
                    CGRect(x: zone.midX - width / 2, y: top + row + gap, width: width, height: row),
                    CGRect(x: left + width + gap, y: top, width: width, height: row), .below)
        }
        // One row, centred; squeezed if the zone is narrower, Select and
        // Start before the menu button.
        let factor = min(1, zone.width / oneRow)
        let space = gap * factor
        let width = min(zone.width, oneRow)
        let pauseCell = min(knobCell, max(knobCell * factor, min(target, width - 2 * space)))
        let cell = max(0, (width - pauseCell - 2 * space) / 2)
        let x = zone.midX - width / 2
        let y = zone.midY - row / 2
        return (CGRect(x: x, y: y, width: cell, height: row),
                CGRect(x: x + cell + space, y: y, width: pauseCell, height: row),
                CGRect(x: x + cell + 2 * space + pauseCell, y: y, width: cell, height: row), .below)
    }

    /// The buttons all `points` press together. A finger can slide from one
    /// button to the next; every finger counts.
    func buttons(at points: some Sequence<CGPoint>) -> JoypadButtons {
        var pressed: JoypadButtons = []
        for point in points {
            pressed.formUnion(buttons(at: point))
        }
        return pressed
    }

    /// What takes the touches of `button`: its target and a slop around it,
    /// a share of its smaller side, never above `limits.inputTop` and never
    /// on the active fold, where the zones end too.
    func hitArea(of button: Button) -> CGRect {
        let target = button.target
        let slop = min(target.width, target.height) * Self.buttonSlop
        var area = target.insetBy(dx: -slop, dy: -slop)
        let top = min(target.minY, max(area.minY, limits.inputTop))
        area = CGRect(x: area.minX, y: top, width: area.width, height: max(0, area.maxY - top))
        if let fold = limits.fold, area.intersects(fold) {
            if fold.width >= fold.height {
                if target.midY < fold.midY {
                    area.size.height = max(target.maxY, min(area.maxY, fold.minY)) - area.minY
                } else {
                    let top = min(target.minY, max(area.minY, fold.maxY))
                    area = CGRect(x: area.minX, y: top, width: area.width, height: area.maxY - top)
                }
            } else if target.midX < fold.midX {
                area.size.width = max(target.maxX, min(area.maxX, fold.minX)) - area.minX
            } else {
                let left = min(target.minX, max(area.minX, fold.maxX))
                area = CGRect(x: left, y: area.minY, width: area.maxX - left, height: area.height)
            }
        }
        return area
    }

    /// What one touch presses: nothing above the first row that takes
    /// touches or on the active fold; a pad direction inside the pad's
    /// circle; else the nearest button whose hit area holds the point; else
    /// a pad direction up to the pad's reach.
    func buttons(at point: CGPoint) -> JoypadButtons {
        guard limits.accepts(point) else { return [] }
        let dx = point.x - pad.center.x
        let dy = point.y - pad.center.y
        let distance = (dx * dx + dy * dy).squareRoot()
        if distance <= pad.radius {
            return Self.direction(dx: dx, dy: dy, distance: distance, radius: pad.radius)
        }
        var best: (buttons: JoypadButtons, distance: CGFloat)?
        for button in buttons {
            guard hitArea(of: button).contains(point) else { continue }
            let centerDistance = hypot(point.x - button.target.midX, point.y - button.target.midY)
            if best.map({ centerDistance < $0.distance }) ?? true {
                best = (button.buttons, centerDistance)
            }
        }
        if let best {
            return best.buttons
        }
        if distance <= pad.radius * Self.padReach {
            return Self.direction(dx: dx, dy: dy, distance: distance, radius: pad.radius)
        }
        return []
    }

    /// Eight sectors of 45 degrees, starting with right; screen y grows downwards.
    static func direction(dx: CGFloat, dy: CGFloat, distance: CGFloat, radius: CGFloat) -> JoypadButtons {
        guard distance >= radius * deadZone else { return [] }
        var degrees = atan2(-dy, dx) * 180 / .pi
        if degrees < 0 {
            degrees += 360
        }
        let sectors: [JoypadButtons] = [
            .right, [.right, .up], .up, [.up, .left], .left, [.left, .down], .down, [.down, .right],
        ]
        return sectors[Int((degrees + 22.5) / 45) % 8]
    }
}

extension TouchLayout.Pad {
    /// The square around the pad's disc.
    nonisolated var frame: CGRect {
        CGRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius)
    }
}
