import CoreGraphics
import FoldLayout
import LibretroKit

/// Sends every finger on the game view either to the buttons or to the touch
/// screen (ADR 0006, section 6). A pure value: tests feed it touches.
///
/// - A finger that begins on the touch screen is the stylus, if there is none
///   yet; it stays at the edge when it slides off and lifts with the finger.
///   A second finger that begins there is ignored: the DS knows one touch.
/// - Every other finger presses buttons and can slide from one to the next,
///   but never on the touch screen: there it presses nothing.
nonisolated struct TouchRouter<TouchID: Hashable> {
    /// One finger as the gesture reports it, in points of the game view.
    struct Touch {
        var id: TouchID
        var location: CGPoint
        /// False once the finger lifted or the touch was cancelled.
        var isActive: Bool
    }

    /// What the fingers do together.
    struct Output: Sendable, Hashable {
        var buttons: JoypadButtons
        /// The pixel of the touch screen under the stylus, nil while lifted.
        var touchPixel: TouchMapping.Pixel?
    }

    private enum Role: Sendable {
        case stylus
        case buttons
        case ignored
    }

    private var roles: [TouchID: Role] = [:]

    /// The output for the fingers on the view right now. `touches` holds each
    /// finger the gesture reports; fingers it no longer reports are gone.
    mutating func update(_ touches: [Touch], controls: TouchLayout?, touchScreen: TouchMapping?) -> Output {
        var stylusLocation: CGPoint?
        var buttonLocations: [CGPoint] = []
        let active = touches.filter(\.isActive)
        roles = roles.filter { id, _ in active.contains { $0.id == id } }
        for touch in active {
            let role: Role
            if let known = roles[touch.id] {
                role = known
            } else if let touchScreen, touchScreen.pixel(at: touch.location) != nil {
                role = roles.values.contains(.stylus) ? .ignored : .stylus
            } else {
                role = .buttons
            }
            roles[touch.id] = role
            switch role {
            case .stylus:
                stylusLocation = touch.location
            case .buttons:
                // Never a button on the touch screen.
                if touchScreen?.pixel(at: touch.location) == nil {
                    buttonLocations.append(touch.location)
                }
            case .ignored:
                break
            }
        }
        var touchPixel: TouchMapping.Pixel?
        if let stylusLocation, let touchScreen {
            touchPixel = touchScreen.clampedPixel(at: stylusLocation)
        }
        return Output(buttons: controls?.buttons(at: buttonLocations) ?? [], touchPixel: touchPixel)
    }

    /// Every finger lifted.
    mutating func reset() -> Output {
        roles = [:]
        return Output(buttons: [], touchPixel: nil)
    }
}

// SwiftUI's touch identifiers are not Sendable; the router is, when they are.
extension TouchRouter: Sendable where TouchID: Sendable {}
extension TouchRouter.Touch: Sendable where TouchID: Sendable {}
