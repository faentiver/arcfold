import CoreGraphics
import FoldLayout
import Foundation
import LibretroKit

/// Where the touch controls sit and which buttons a set of touches presses.
/// A pure value built from the zones of `GameLayout` (ADR 0006): the mask
/// comes from `buttons(at:)` without a session, so tests can check it
/// directly (ADR 0005, section 7). All values are points of the game view.
nonisolated struct TouchLayout: Sendable, Hashable {
    /// The direction pad: a circle split into eight sectors around a dead zone.
    struct Pad: Sendable, Hashable {
        var center: CGPoint
        var radius: CGFloat
    }

    /// A button with a text label; no original symbols (hard rules in CLAUDE.md).
    struct Button: Sendable, Hashable, Identifiable {
        enum Shape: Sendable, Hashable {
            case circle
            case capsule
        }

        var buttons: JoypadButtons
        var label: String
        var frame: CGRect
        var shape: Shape

        var id: String { label }
    }

    var pad: Pad
    var buttons: [Button]
    /// The app's pause button, between Select and Start.
    var pauseButton: CGRect
    /// The controls lie over a screen; drawn more transparent.
    var overlapsScreen: Bool

    /// Touches closer to the pad's centre than this share of its radius press nothing.
    static let deadZone: CGFloat = 0.3
    /// Touches count for the pad up to this multiple of its radius, where no
    /// button claims them.
    static let padReach: CGFloat = 1.4
    /// Buttons react a bit beyond what they draw.
    static let buttonSlop: CGFloat = 0.25

    /// Largest sizes, in points.
    static let largestPadRadius: CGFloat = 80
    static let largestFaceRadius: CGFloat = 34
    static let largestShoulderWidth: CGFloat = 140
    static let rowHeight: CGFloat = 36
    static let menuButtonWidth: CGFloat = 72
    static let gap: CGFloat = 8

    /// The controls in `zones`, which are pixels at `scale` pixels per point.
    /// X and Y only for systems that have them.
    init(zones: ControlZones, scale: Int, hasXYButtons: Bool) {
        let s = CGFloat(max(1, scale))
        func points(_ rect: PixelRect) -> CGRect {
            CGRect(x: CGFloat(rect.x) / s, y: CGFloat(rect.y) / s, width: CGFloat(rect.width) / s, height: CGFloat(rect.height) / s)
        }
        let padZone = points(zones.pad)
        pad = Pad(center: CGPoint(x: padZone.midX, y: padZone.midY),
                  radius: min(min(padZone.width, padZone.height) / 2 * 0.9, Self.largestPadRadius))
        overlapsScreen = zones.overlapsScreen

        var buttons = Self.faceButtons(in: points(zones.face), hasXYButtons: hasXYButtons)
        buttons.append(Self.shoulder(.l, "L", in: points(zones.leftShoulder), alignedLeft: true))
        buttons.append(Self.shoulder(.r, "R", in: points(zones.rightShoulder), alignedLeft: false))
        let menu = Self.menu(in: points(zones.menu), trailing: zones.menuTrailing.map(points))
        buttons.append(Button(buttons: .select, label: "Select", frame: menu.select, shape: .capsule))
        buttons.append(Button(buttons: .start, label: "Start", frame: menu.start, shape: .capsule))
        self.buttons = buttons.filter { !$0.frame.isEmpty }
        pauseButton = menu.pause
    }

    /// A and B on a diagonal as on the GBA, or X, A, B and Y as a diamond as
    /// on the DS, around the middle of `zone`.
    private static func faceButtons(in zone: CGRect, hasXYButtons: Bool) -> [Button] {
        let side = min(zone.width, zone.height, 180)
        let center = CGPoint(x: zone.midX, y: zone.midY)
        func circle(_ dx: CGFloat, _ dy: CGFloat, radius: CGFloat) -> CGRect {
            CGRect(x: center.x + dx - radius, y: center.y + dy - radius, width: 2 * radius, height: 2 * radius)
        }
        guard hasXYButtons else {
            let radius = min(side * 0.2, largestFaceRadius)
            return [
                Button(buttons: .a, label: "A", frame: circle(side * 0.22, -side * 0.12, radius: radius), shape: .circle),
                Button(buttons: .b, label: "B", frame: circle(-side * 0.22, side * 0.12, radius: radius), shape: .circle),
            ]
        }
        let radius = min(side * 0.19, largestFaceRadius - 4)
        let distance = side * 0.3
        return [
            Button(buttons: .a, label: "A", frame: circle(distance, 0, radius: radius), shape: .circle),
            Button(buttons: .b, label: "B", frame: circle(0, distance, radius: radius), shape: .circle),
            Button(buttons: .x, label: "X", frame: circle(0, -distance, radius: radius), shape: .circle),
            Button(buttons: .y, label: "Y", frame: circle(-distance, 0, radius: radius), shape: .circle),
        ]
    }

    /// A capsule at the top of `zone`, at its outer edge.
    private static func shoulder(_ buttons: JoypadButtons, _ label: String, in zone: CGRect, alignedLeft: Bool) -> Button {
        let width = min(zone.width, largestShoulderWidth)
        let height = min(zone.height, 44)
        let x = alignedLeft ? zone.minX : zone.maxX - width
        return Button(buttons: buttons, label: label, frame: CGRect(x: x, y: zone.minY, width: width, height: height),
                      shape: .capsule)
    }

    /// The lowest row of the menu that is still a button.
    static let smallestRowHeight: CGFloat = 28

    /// Select, the pause button and Start. In one piece: in one row when
    /// `zone` is wide enough; in a column of three rows when it is narrower
    /// and high enough, with lower rows before the buttons would stand side
    /// by side close to pad and face buttons; Select and Start above the
    /// pause button when it holds two rows; and otherwise in one row squeezed
    /// to the zone's width. Divided: Select and the pause button at the end
    /// of `zone` and Start at the beginning of `trailing`, on both sides of
    /// what divides them.
    private static func menu(in zone: CGRect, trailing: CGRect?) -> (select: CGRect, pause: CGRect, start: CGRect) {
        // A zone lower than a row keeps a point of air above and below.
        let row = zone.height >= rowHeight ? rowHeight : max(0, zone.height - 2)
        if let trailing {
            let factor = min(1, zone.width / (menuButtonWidth + gap + row))
            let pause = CGRect(x: zone.maxX - row * factor, y: zone.midY - row / 2, width: row * factor, height: row)
            let select = CGRect(x: pause.minX - gap * factor - menuButtonWidth * factor, y: pause.minY,
                                width: menuButtonWidth * factor, height: row)
            let start = CGRect(x: trailing.minX, y: trailing.midY - row / 2,
                               width: min(menuButtonWidth, trailing.width), height: row)
            return (select, pause, start)
        }
        let oneRow = 2 * menuButtonWidth + row + 2 * gap
        let columnRow = min(row, (zone.height - 2 * gap) / 3)
        if zone.width < oneRow, columnRow >= smallestRowHeight {
            // A column: Select, Start, the pause button.
            let width = min(menuButtonWidth, zone.width)
            let top = zone.midY - (3 * columnRow + 2 * gap) / 2
            let x = zone.midX - width / 2
            return (CGRect(x: x, y: top, width: width, height: columnRow),
                    CGRect(x: zone.midX - columnRow / 2, y: top + 2 * (columnRow + gap), width: columnRow, height: columnRow),
                    CGRect(x: x, y: top + columnRow + gap, width: width, height: columnRow))
        }
        if zone.width < oneRow, zone.height >= 2 * row + gap {
            // Two rows: Select and Start, the pause button below them.
            let width = min(menuButtonWidth, (zone.width - gap) / 2)
            let top = zone.midY - (2 * row + gap) / 2
            let left = zone.midX - (2 * width + gap) / 2
            return (CGRect(x: left, y: top, width: width, height: row),
                    CGRect(x: zone.midX - row / 2, y: top + row + gap, width: row, height: row),
                    CGRect(x: left + width + gap, y: top, width: width, height: row))
        }
        // One row, centred; squeezed if the zone is narrower.
        let factor = min(1, zone.width / oneRow)
        let width = menuButtonWidth * factor
        let space = gap * factor
        let pause = row * factor
        let x = zone.midX - (2 * width + pause + 2 * space) / 2
        let y = zone.midY - row / 2
        return (CGRect(x: x, y: y, width: width, height: row),
                CGRect(x: x + width + space, y: y, width: pause, height: row),
                CGRect(x: x + width + space + pause + space, y: y, width: width, height: row))
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

    /// What one touch presses: a pad direction inside the pad's circle; else
    /// the nearest button whose enlarged area holds the point; else a pad
    /// direction up to the pad's reach.
    func buttons(at point: CGPoint) -> JoypadButtons {
        let dx = point.x - pad.center.x
        let dy = point.y - pad.center.y
        let distance = (dx * dx + dy * dy).squareRoot()
        if distance <= pad.radius {
            return Self.direction(dx: dx, dy: dy, distance: distance, radius: pad.radius)
        }
        var best: (buttons: JoypadButtons, distance: CGFloat)?
        for button in buttons {
            let slop = min(button.frame.width, button.frame.height) * Self.buttonSlop
            guard button.frame.insetBy(dx: -slop, dy: -slop).contains(point) else { continue }
            let centerDistance = hypot(point.x - button.frame.midX, point.y - button.frame.midY)
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
