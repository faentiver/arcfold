import CoreGraphics
import Foundation
import LibretroKit

/// Where the touch controls sit and which buttons a set of touches presses.
/// A pure value: the mask comes from `buttons(at:)` without a session, so
/// tests can check it directly (ADR 0005, section 7).
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

    /// Touches closer to the pad's centre than this share of its radius press nothing.
    static let deadZone: CGFloat = 0.3
    /// Touches count for the pad up to this multiple of its radius.
    static let padReach: CGFloat = 1.4
    /// Buttons react a bit beyond what they draw.
    static let buttonSlop: CGFloat = 0.25

    /// The controls for a view of `size` points. Upright, they fill the area
    /// below the picture; sideways, they sit at the sides over the picture.
    init(size: CGSize, isLandscape: Bool) {
        let width = size.width
        let height = size.height
        if isLandscape {
            let radius = min(width * 0.085, height * 0.2)
            pad = Pad(center: CGPoint(x: width * 0.11, y: height * 0.58), radius: radius)
            let face = radius * 0.45
            buttons = [
                Button(buttons: .a, label: "A", frame: Self.circle(x: width * 0.93, y: height * 0.50, radius: face), shape: .circle),
                Button(buttons: .b, label: "B", frame: Self.circle(x: width * 0.85, y: height * 0.64, radius: face), shape: .circle),
                Button(buttons: .l, label: "L", frame: CGRect(x: width * 0.02, y: height * 0.06, width: width * 0.16, height: 44), shape: .capsule),
                Button(buttons: .r, label: "R", frame: CGRect(x: width * 0.82, y: height * 0.06, width: width * 0.16, height: 44), shape: .capsule),
                Button(buttons: .select, label: "Select", frame: CGRect(x: width * 0.03, y: height * 0.86, width: width * 0.12, height: 36), shape: .capsule),
                Button(buttons: .start, label: "Start", frame: CGRect(x: width * 0.85, y: height * 0.86, width: width * 0.12, height: 36), shape: .capsule),
            ]
        } else {
            let radius = min(width * 0.17, height * 0.26)
            pad = Pad(center: CGPoint(x: width * 0.25, y: height * 0.48), radius: radius)
            let face = radius * 0.45
            buttons = [
                Button(buttons: .a, label: "A", frame: Self.circle(x: width * 0.84, y: height * 0.40, radius: face), shape: .circle),
                Button(buttons: .b, label: "B", frame: Self.circle(x: width * 0.67, y: height * 0.54, radius: face), shape: .circle),
                Button(buttons: .l, label: "L", frame: CGRect(x: width * 0.04, y: height * 0.04, width: width * 0.28, height: 44), shape: .capsule),
                Button(buttons: .r, label: "R", frame: CGRect(x: width * 0.68, y: height * 0.04, width: width * 0.28, height: 44), shape: .capsule),
                Button(buttons: .select, label: "Select", frame: CGRect(x: width * 0.30, y: height * 0.84, width: width * 0.18, height: 36), shape: .capsule),
                Button(buttons: .start, label: "Start", frame: CGRect(x: width * 0.52, y: height * 0.84, width: width * 0.18, height: 36), shape: .capsule),
            ]
        }
    }

    private static func circle(x: CGFloat, y: CGFloat, radius: CGFloat) -> CGRect {
        CGRect(x: x - radius, y: y - radius, width: 2 * radius, height: 2 * radius)
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

    /// What one touch presses: a pad direction, or else the nearest button
    /// whose enlarged area contains the point.
    func buttons(at point: CGPoint) -> JoypadButtons {
        let dx = point.x - pad.center.x
        let dy = point.y - pad.center.y
        let distance = (dx * dx + dy * dy).squareRoot()
        if distance <= pad.radius * Self.padReach {
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
        return best?.buttons ?? []
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
