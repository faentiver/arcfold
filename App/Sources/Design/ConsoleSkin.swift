import FoldLayout
import SwiftUI

/// The colour of the console a game is played on. Every system has a first
/// finish and at least one more to choose from (`ConsoleSkin.finishes`).
nonisolated enum CaseFinish: String, Sendable, Hashable, CaseIterable {
    /// A light case with indigo lettering.
    case chalk
    /// A dark case with light lettering.
    case graphite
    /// An indigo case with light keys.
    case indigo
    /// A dark teal case with light keys.
    case petrol
}

/// What the console around the screens looks like (ADR 0007): the colours of
/// one finish and the measures of case, bezels, hinge and keys, all in one
/// place. The case and its keys are Arcfold's own design: no device is
/// copied, no logo and no original symbol appears, the keys carry letters,
/// words and plain arrows only (hard rules in docs/PLAN.md, section 8).
nonisolated struct ConsoleSkin: Sendable, Hashable {
    var finish: CaseFinish

    // The case: a fine gradient from top to bottom, light from above.
    var bodyTop: Color
    var bodyBottom: Color
    /// The light that falls on the top of the case and on edges that face up.
    var bodyLight: Color
    /// The shade where the case curves away and below things that stand in it.
    var bodyShade: Color

    // The bezel around a screen, set into the case.
    var bezelTop: Color
    var bezelBottom: Color

    // The hinge: a barrel, light where the light falls and dark at its edges.
    var hingeLight: Color
    var hingeMiddle: Color
    var hingeDark: Color

    // The keys: caps that stand out of a well in the case.
    var capTop: Color
    var capBottom: Color
    var capPressedTop: Color
    var capPressedBottom: Color
    /// The light on the upper edge of a cap and below what is engraved in it.
    var capGlint: Color
    /// The well a key stands in.
    var well: Color
    /// Letters and arrows on the keys.
    var legend: Color
    /// The same on a pressed key and with Increase Contrast.
    var legendStrong: Color
    /// The edge of a key with Increase Contrast.
    var outline: Color

    // The cap of the menu button, which belongs to the app, not to the game.
    var menuTop: Color
    var menuBottom: Color

    /// The names of the small buttons, written on the case.
    var inscription: Color
    /// The same with Increase Contrast.
    var inscriptionStrong: Color
    /// The case is light: edges that face up take less light, shades are softer.
    var isLight: Bool

    // MARK: Measures, in points

    /// The bezel around a screen and its corners. The width is the one the
    /// layout keeps the controls clear of (`LayoutMetrics.bezel`).
    static let bezelWidth = CGFloat(LayoutMetrics.standard.bezel)
    static let bezelCorner: CGFloat = 13
    /// The well around a key. `LayoutMetrics.hinge` leaves room for it
    /// above and below L and R.
    static let wellWidth: CGFloat = 2
    /// How far a cap stands out: the offset of its shadow, and how far a
    /// pressed cap moves down.
    static let capHeight: CGFloat = 2.5
    static let capTravel: CGFloat = 1.5
    /// How far the shadow of a cap reaches beyond the cap at most.
    static let capReach: CGFloat = 12
    /// The arms of the direction pad as a share of its size, and the corners
    /// of the arms as a share of their width.
    static let padArm: CGFloat = 0.36
    static let padCorner: CGFloat = 0.3
    /// The corners of L and R as a share of their height.
    static let shoulderCorner: CGFloat = 0.38
    /// A small button: the same in every pose. A row too low for it and
    /// its name, which no pose of the Duo has, takes the smaller one.
    static let knob: CGFloat = 24
    static let smallKnob: CGFloat = 18
    /// The letters on round keys and on L and R as a share of their height,
    /// and the smallest letter on a key.
    static let letterShare: CGFloat = 0.5
    static let shoulderLetterShare: CGFloat = 0.52
    static let smallestLetter: CGFloat = 11
    /// The names of the small buttons: the same in every pose.
    static let inscriptionSize: CGFloat = 11.5
    /// The space between a small button and its name below or beside it.
    static let inscriptionBelow: CGFloat = 3
    static let inscriptionBeside: CGFloat = 7
    /// The width of the longest name, "SELECT": names beside their buttons
    /// begin on one line, and the column stands in the middle of its zone.
    static let widestInscription: CGFloat = 49
    /// L or R lower than this is the end of a slim hinge: it stands out
    /// half as far.
    static let lowKey: CGFloat = 30
    /// The cross of the direction pad in its dish, as a share of the dish.
    static let padCross: CGFloat = 0.88
    /// The dish of the case around the camera of the outer display, beyond
    /// the region the system reserves for it. With the status bar showing,
    /// the system hangs a capsule of 55 pt from the camera (measured in the
    /// Simulator); the dish stays inside it.
    static let lensRing: CGFloat = 4

    // MARK: Finishes

    /// The finishes of a system; the first is the one it starts with.
    static func finishes(forSystem id: String) -> [CaseFinish] {
        switch id {
        case "ds": [.chalk, .graphite]
        default: [.indigo, .petrol]
        }
    }

    /// The skin of a system: its first finish, or the one `preferred` names
    /// when the system offers it.
    static func skin(forSystem id: String, preferred: CaseFinish? = nil) -> ConsoleSkin {
        let finishes = finishes(forSystem: id)
        return ConsoleSkin(preferred.flatMap { finishes.contains($0) ? $0 : nil } ?? finishes[0])
    }

    /// The finish chosen for every system that offers it, nil for each
    /// system's first: the value of the user default `CaseFinish`, one of
    /// the names of `CaseFinish`. A launch argument sets it too, as in
    /// `-CaseFinish graphite`.
    static var preferredFinish: CaseFinish? {
        UserDefaults.standard.string(forKey: "CaseFinish").flatMap(CaseFinish.init(rawValue:))
    }

    /// Larger screens count for more than the rim of the case: a system
    /// whose screens grow beside the vertical bar of the outer display keeps
    /// the bar there (`GameSystem.disablesVerticalBar`), and its case becomes
    /// slim. The user default `LargerScreens`; a launch argument sets it
    /// too, as in `-LargerScreens YES`.
    static var prefersLargerScreens: Bool {
        UserDefaults.standard.bool(forKey: "LargerScreens")
    }

    init(_ finish: CaseFinish) {
        self.finish = finish
        switch finish {
        case .chalk:
            bodyTop = Color(hex: 0xF3F4F6)
            bodyBottom = Color(hex: 0xDDDFE5)
            bodyLight = .white
            bodyShade = Color(hex: 0x4A5060)
            bezelTop = Color(hex: 0x1C1D21)
            bezelBottom = Color(hex: 0x0D0E10)
            hingeLight = Color(hex: 0xFBFBFC)
            hingeMiddle = Color(hex: 0xD9DCE2)
            hingeDark = Color(hex: 0xB2B6C0)
            capTop = Color(hex: 0xFFFFFF)
            capBottom = Color(hex: 0xE3E5EA)
            capPressedTop = Color(hex: 0xC4C2F0)
            capPressedBottom = Color(hex: 0xD6D4F6)
            capGlint = .white.opacity(0.95)
            well = Color(hex: 0xC9CCD4)
            legend = Color(hex: 0x5A57D0)
            legendStrong = Color(hex: 0x2F2C96)
            outline = Color(hex: 0x1C1D21)
            menuTop = Color(hex: 0x7A77EA)
            menuBottom = Color(hex: 0x504DC6)
            inscription = Color(hex: 0x565B67)
            inscriptionStrong = Color(hex: 0x1C1D21)
            isLight = true
        case .graphite:
            bodyTop = Color(hex: 0x3E414A)
            bodyBottom = Color(hex: 0x292B31)
            bodyLight = Color(hex: 0xAEB3C2)
            bodyShade = .black
            bezelTop = Color(hex: 0x131417)
            bezelBottom = Color(hex: 0x08090A)
            hingeLight = Color(hex: 0x5A5E6A)
            hingeMiddle = Color(hex: 0x363940)
            hingeDark = Color(hex: 0x1D1F23)
            capTop = Color(hex: 0x5C616D)
            capBottom = Color(hex: 0x41454E)
            capPressedTop = Color(hex: 0x5451C4)
            capPressedBottom = Color(hex: 0x6966DA)
            capGlint = .white.opacity(0.22)
            well = Color(hex: 0x1A1C20)
            legend = Color(hex: 0xECEEF3)
            legendStrong = .white
            outline = .white
            menuTop = Color(hex: 0x8A87F4)
            menuBottom = Color(hex: 0x5F5CD6)
            inscription = Color(hex: 0xC2C6D0)
            inscriptionStrong = .white
            isLight = false
        case .indigo:
            bodyTop = Color(hex: 0x645EE2)
            bodyBottom = Color(hex: 0x413BB0)
            bodyLight = Color(hex: 0xC9C6FF)
            bodyShade = Color(hex: 0x14104A)
            bezelTop = Color(hex: 0x17162A)
            bezelBottom = Color(hex: 0x0B0A14)
            hingeLight = Color(hex: 0x8580F0)
            hingeMiddle = Color(hex: 0x4F49C4)
            hingeDark = Color(hex: 0x2D2890)
            capTop = Color(hex: 0xF7F6FE)
            capBottom = Color(hex: 0xD6D3EE)
            capPressedTop = Color(hex: 0xA9A4EC)
            capPressedBottom = Color(hex: 0xBEBAF4)
            capGlint = .white.opacity(0.95)
            well = Color(hex: 0x2A2586)
            legend = Color(hex: 0x413BB0)
            legendStrong = Color(hex: 0x1D1870)
            outline = .white
            menuTop = Color(hex: 0xFFD666)
            menuBottom = Color(hex: 0xF2A91E)
            inscription = Color(hex: 0xECEBFF)
            inscriptionStrong = .white
            isLight = false
        case .petrol:
            bodyTop = Color(hex: 0x21858C)
            bodyBottom = Color(hex: 0x115C63)
            bodyLight = Color(hex: 0xB5F0F2)
            bodyShade = Color(hex: 0x03282C)
            bezelTop = Color(hex: 0x121C1D)
            bezelBottom = Color(hex: 0x080E0F)
            hingeLight = Color(hex: 0x37A6AD)
            hingeMiddle = Color(hex: 0x17747B)
            hingeDark = Color(hex: 0x0A474C)
            capTop = Color(hex: 0xF4FAFA)
            capBottom = Color(hex: 0xD0E2E3)
            capPressedTop = Color(hex: 0x8FCCD0)
            capPressedBottom = Color(hex: 0xA9DADD)
            capGlint = .white.opacity(0.95)
            well = Color(hex: 0x09434A)
            legend = Color(hex: 0x0F5C63)
            legendStrong = Color(hex: 0x063A3F)
            outline = .white
            menuTop = Color(hex: 0xFFA98A)
            menuBottom = Color(hex: 0xF0704E)
            inscription = Color(hex: 0xE6F7F8)
            inscriptionStrong = .white
            isLight = false
        }
    }
}

extension Color {
    /// An opaque sRGB colour from 0xRRGGBB.
    nonisolated init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: 1)
    }
}

extension EnvironmentValues {
    /// The console the running game is played on; set where the game view
    /// is presented.
    @Entry var consoleSkin = ConsoleSkin(.indigo)
}
