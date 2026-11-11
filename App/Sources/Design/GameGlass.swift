import OSLog
import SwiftUI

/// How the in-game controls are drawn. Glass is a comfort (rule R7): every
/// glass surface in a game has a flat variant through `Glass.identity`, with
/// the same view tree, so switching rebuilds nothing.
nonisolated enum ControlSurface: String, Sendable, Hashable {
    case glass
    case flat
}

extension EnvironmentValues {
    @Entry var controlSurface: ControlSurface = .glass
}

/// What lies beneath a control: the moving game picture, where the control
/// is in-game glass, or the case of the console beside or below the
/// screens, where it is a key of the case and carries no glass (ADR 0007).
nonisolated enum GlassBackdrop: Hashable, Sendable {
    case picture
    case deck

    /// The backdrop of a control at `frame`: the picture when it lies over
    /// one of `screens`, otherwise the case.
    static func under(_ frame: CGRect, screens: [CGRect]) -> GlassBackdrop {
        screens.contains { $0.intersects(frame) } ? .picture : .deck
    }
}

extension View {
    /// In-game glass over the picture: clear glass over a dimming plate, so
    /// the game picture never decides how a control looks. Beside or below
    /// the screens a control is a key of the case instead. The keys are
    /// never interactive; the touch surface owns their touches. Only the
    /// pause button, a real button, reacts like the system's glass buttons
    /// (`isInteractive`).
    func gameGlass<S: InsettableShape>(in shape: S, isPressed: Bool = false, isSmallLabel: Bool = false,
                                       isInteractive: Bool = false) -> some View {
        modifier(GameGlass(shape: shape, isPressed: isPressed, isSmallLabel: isSmallLabel,
                           isInteractive: isInteractive, plate: EmptyView()))
    }

    /// The same, with something drawn on the plate beneath the glass, such as
    /// the pressed sector of the direction pad.
    func gameGlass<S: InsettableShape, Plate: View>(
        in shape: S, isSmallLabel: Bool = false, @ViewBuilder plate: () -> Plate
    ) -> some View {
        modifier(GameGlass(shape: shape, isPressed: false, isSmallLabel: isSmallLabel,
                           isInteractive: false, plate: plate()))
    }

    /// Decides glass or flat for a game screen: flat while the system prefers
    /// reduced resource usage (iOS 27), glass otherwise. It decides only what
    /// lies over a picture: the menu button with a controller where no
    /// corner of the case is free, the notices and the status chip, and keys
    /// over a picture where a display leaves no room for the case. The keys
    /// of the console are never glass. In debug builds the launch argument
    /// `-ArcfoldControlSurface flat|glass` wins, for the screenshot tour.
    func resolvesControlSurface() -> some View {
        modifier(ResolvesControlSurface())
    }
}

/// The opacities of the dimming plate (docs/wissen/oberflaeche.md, 2.2).
nonisolated enum GamePlate {
    struct Look: Equatable {
        /// Opacity of `Color.gamePlate` beneath the glass.
        var plateOpacity: Double
        /// Width of the white edge, 0 for none.
        var borderWidth: CGFloat
        var borderOpacity: Double
    }

    /// The plate at rest; glass lies over the picture only. Small labels
    /// (capsules up to 40 pt high, notices) get a darker plate, because
    /// their text is small. Measured over white in the screenshot tour (the
    /// glass itself lightens a little): 0.60 and 0.70 as first planned gave
    /// 2.9 : 1 and 3.8 : 1, below 3 and 4.5, so both went up by 0.1
    /// (docs/wissen/oberflaeche.md).
    ///
    /// Increase Contrast draws a white edge at `contrastBorderOpacity`
    /// around every control: over a dark picture the plate has nothing to
    /// stand out from, so the edge has to. Show Borders alone draws the edge
    /// at `borderOpacity`.
    static func look(isSmallLabel: Bool, increasedContrast: Bool, reduceTransparency: Bool, showsBorders: Bool) -> Look {
        var opacity = isSmallLabel ? 0.80 : 0.70
        if increasedContrast {
            opacity = max(opacity, isSmallLabel ? 0.90 : 0.80)
        }
        if reduceTransparency {
            opacity = max(opacity, isSmallLabel ? 0.90 : 0.85)
        }
        let border = increasedContrast || showsBorders
        return Look(plateOpacity: opacity, borderWidth: border ? 1 : 0,
                    borderOpacity: border ? (increasedContrast ? contrastBorderOpacity : borderOpacity) : 0)
    }

    /// The white edge with Show Borders alone.
    static let borderOpacity = 0.35
    /// The white edge with Increase Contrast. At 0.35 it measured 2.84 to
    /// 2.92 : 1 against the dark picture of the test programs; from 0.90 on
    /// either the edge or the plate keeps 3 : 1 against a background of any
    /// brightness (`GamePlateTests`).
    static let contrastBorderOpacity = 0.90

    /// A pressed control shows the game's colour, nearly opaque: at 0.85 the
    /// glass over white left small labels at 3.3 : 1.
    static let pressedOpacity = 0.95

    /// Small labels pressed: the game's colour a little darker still.
    static func pressedFill(_ style: GameStyle, isSmallLabel: Bool) -> Color {
        isSmallLabel ? style.pressedFill.mix(with: .black, by: 0.25) : style.pressedFill
    }

    /// Flat: the same plate and the same pressed colour without the glass
    /// over them, so that a control reads over a picture of any brightness
    /// as it does in glass, and a white edge, because no glass bends the
    /// picture at its rim. The white plate of M1 at 0.10 left the menu
    /// button and the notices at 1.0 : 1 over a white picture.
    static let flatBorderWidth: CGFloat = 1.5
    static let flatBorderOpacity = 0.4
}

private struct GameGlass<S: InsettableShape, Plate: View>: ViewModifier {
    let shape: S
    let isPressed: Bool
    let isSmallLabel: Bool
    /// Reacts to a touch like the system's glass buttons; only for the pause
    /// button, never for the game's keys (rule R5).
    let isInteractive: Bool
    let plate: Plate

    @Environment(\.controlSurface) private var surface
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityShowBorders) private var showsBorders
    @Environment(\.gameStyle) private var gameStyle

    func body(content: Content) -> some View {
        let look = GamePlate.look(isSmallLabel: isSmallLabel,
                                  increasedContrast: contrast == .increased,
                                  reduceTransparency: reduceTransparency, showsBorders: showsBorders)
        content
            // Part of the glass's content, like the label: inside a
            // GlassEffectContainer an overlay after the effect ends up
            // beneath the glass, and the border of Increase Contrast was gone
            // (measured in the screenshot tour).
            .overlay {
                border(look: look)
                    .allowsHitTesting(false)
            }
            // .identity draws the content "as if no glass effect was applied"
            // (SDK), so flat keeps the same tree.
            .glassEffect(surface == .glass ? .clear.interactive(isInteractive) : .identity, in: shape)
            // Beneath the glass, as in the SDK: clear glass needs a dimming
            // layer under it. Always clipped to the shape, or the corners of
            // the rectangle would show.
            .background {
                ZStack {
                    plateFill(look: look)
                    plate
                }
                .clipShape(shape)
            }
    }

    /// The plate is the same in glass and flat.
    private func plateFill(look: GamePlate.Look) -> some View {
        Group {
            if isPressed {
                GamePlate.pressedFill(gameStyle, isSmallLabel: isSmallLabel).opacity(GamePlate.pressedOpacity)
            } else {
                Color.gamePlate(look.plateOpacity)
            }
        }
    }

    @ViewBuilder
    private func border(look: GamePlate.Look) -> some View {
        if surface == .flat {
            // Never weaker than the edge of Increase Contrast or Show Borders.
            shape.strokeBorder(.white.opacity(max(GamePlate.flatBorderOpacity, look.borderOpacity)),
                               lineWidth: GamePlate.flatBorderWidth)
        } else if look.borderWidth > 0 {
            shape.strokeBorder(.white.opacity(look.borderOpacity), lineWidth: look.borderWidth)
        }
    }
}

private struct ResolvesControlSurface: ViewModifier {
    @Environment(\.systemPrefersReducedResourceUsage) private var prefersReducedResourceUsage

    private static let logger = Logger(subsystem: "com.faentiver.arcfold", category: "ui")

    func body(content: Content) -> some View {
        let surface = resolved
        content
            .environment(\.controlSurface, surface)
            .onChange(of: surface, initial: true) { old, new in
                // Only the glass changes; nothing expensive happens here, as
                // the documentation of the environment value asks.
                if old == new {
                    Self.logger.info("Control surface \(new.rawValue, privacy: .public)")
                } else {
                    Self.logger.info("Control surface \(old.rawValue, privacy: .public) → \(new.rawValue, privacy: .public)")
                }
            }
    }

    private var resolved: ControlSurface {
        #if DEBUG
        if let argument = UserDefaults.standard.string(forKey: "ArcfoldControlSurface"),
           let surface = ControlSurface(rawValue: argument) {
            return surface
        }
        #endif
        return prefersReducedResourceUsage ? .flat : .glass
    }
}
