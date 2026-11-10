import SwiftUI

/// The width class of a container, never of the device: the same window can
/// be the outer display upright (382 pt) or the inner display sideways
/// (951 pt), and GameLayout lays out each pose by its size (ADR 0006, 0007).
nonisolated enum DisplayClass: Sendable, Hashable, CaseIterable {
    case compact
    case regular
    case wide

    init(width: CGFloat) {
        switch width {
        case ..<430: self = .compact
        case ..<800: self = .regular
        default: self = .wide
        }
    }
}

/// Spacing and sizes per width class (docs/wissen/oberflaeche.md).
nonisolated enum Metrics {
    /// Side margin of the library.
    static func margin(for width: CGFloat) -> CGFloat {
        switch DisplayClass(width: width) {
        case .compact: 16
        case .regular: 20
        case .wide: 24
        }
    }

    /// Spacing between tiles of the library, across and down.
    static func gridSpacing(for width: CGFloat) -> (horizontal: CGFloat, vertical: CGFloat) {
        switch DisplayClass(width: width) {
        case .compact: (14, 20)
        case .regular: (16, 22)
        case .wide: (20, 24)
        }
    }

    /// The narrowest a tile may become before the grid drops a column.
    static func tileMinWidth(for width: CGFloat) -> CGFloat {
        switch DisplayClass(width: width) {
        case .compact: 150
        case .regular: 170
        case .wide: 180
        }
    }

    /// Corner radius of a tile, continuous.
    static func tileCorner(for width: CGFloat) -> CGFloat {
        switch DisplayClass(width: width) {
        case .compact: 14
        case .regular: 16
        case .wide: 18
        }
    }

    /// Distance of the overlays in a game from the edge of the safe area.
    static func overlayInset(for width: CGFloat) -> CGFloat {
        switch DisplayClass(width: width) {
        case .compact: 8
        case .regular: 12
        case .wide: 16
        }
    }

    /// The widest a notice may become.
    static func toastMaxWidth(for width: CGFloat) -> CGFloat {
        switch DisplayClass(width: width) {
        case .compact: 320
        case .regular: 400
        case .wide: 460
        }
    }
}

/// Animations. Nothing animates for good while a game runs, and a press of a
/// touch button never animates (rule R5 in docs/wissen/oberflaeche.md).
enum Motion {
    /// Notices and new tiles. With Reduce Motion or cross-fade transitions,
    /// a short fade only.
    static func appear(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.35, bounce: 0.2)
    }

    /// The press of a library tile.
    static let tilePress = Animation.spring(duration: 0.25, bounce: 0.3)

    /// The touch controls going and coming with the pause sheet: a fade
    /// only, also without Reduce Motion.
    static let fade = Animation.easeInOut(duration: 0.25)
}

extension Color {
    /// The dimming plate beneath in-game glass. Clear glass needs one so the
    /// game picture never decides whether a label can be read (rule R3).
    static func gamePlate(_ opacity: Double) -> Color {
        Color(white: 0.15).opacity(opacity)
    }
}

extension EnvironmentValues {
    /// Reduce Motion, or the cross-fade preference of iOS 26.4: either asks
    /// for fades instead of movement.
    var prefersFades: Bool {
        accessibilityReduceMotion || accessibilityPrefersCrossFadeTransitions
    }
}
