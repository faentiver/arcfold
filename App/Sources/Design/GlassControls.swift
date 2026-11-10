import FoldLayout
import LibretroKit
import Renderer
import SwiftUI

/// What the on-screen controls look like: one glass shape per button of a
/// `TouchLayout`, which this view never changes, in the zones `GameLayout`
/// gave it for the pose (ADR 0006, ADR 0007). Drawing only: it takes no
/// touches, `TouchSurface` above it does. Each button stays an accessibility
/// element of its own (`touch-button-<label>`, `touch-pad`), so UI tests find
/// it; VoiceOver plays through the surface, a direct touch area.
///
/// Rule R5: what is shown pressed is the mask that went to the session, at
/// once and without animation. No `.interactive()` glass, no springs, no
/// scaling: a reaction of the glass would lag behind the game and lift the
/// compositor to 120 Hz on every press.
struct TouchControlsArt: View {
    typealias Backdrop = GlassBackdrop

    let layout: TouchLayout
    let pressed: JoypadButtons
    /// The screens, in the coordinates of the controls: a control over one
    /// gets the plate for the moving picture, every other one the lighter
    /// plate for the still deck.
    let screens: [CGRect]

    var body: some View {
        // Spacing 0: neighbouring buttons (A and B 26.6 pt apart outside,
        // Select and Start 15.2 pt) must never melt into one shape.
        GlassEffectContainer(spacing: 0) {
            ZStack(alignment: .topLeading) {
                GlassPad(pad: layout.pad, pressed: pressed,
                         backdrop: Backdrop.under(layout.pad.frame, screens: screens))
                ForEach(layout.buttons) { button in
                    GlassKey(button: button, isPressed: pressed.isSuperset(of: button.buttons),
                             backdrop: Backdrop.under(button.frame, screens: screens))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

extension TouchLayout.Pad {
    /// The square around the pad's disc.
    nonisolated var frame: CGRect {
        CGRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius)
    }
}

/// A round or capsule button of the touch layout.
struct GlassKey: View {
    let button: TouchLayout.Button
    let isPressed: Bool
    let backdrop: TouchControlsArt.Backdrop

    @Environment(\.legibilityWeight) private var legibilityWeight
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    var body: some View {
        // Two branches, so the shape stays an InsettableShape.
        switch button.shape {
        case .circle: key(in: Circle())
        case .capsule: key(in: Capsule())
        }
    }

    private func key<S: InsettableShape>(in shape: S) -> some View {
        Text(verbatim: button.label)
            .font(.system(size: Self.labelSize(for: button), weight: legibilityWeight == .bold ? .bold : .semibold,
                          design: .rounded))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(backdrop == .picture ? 0.35 : 0), radius: 1.5)
            .padding(.horizontal, 4)
            .frame(width: button.frame.width, height: button.frame.height)
            // Pressed without colour: a ring, drawn as content of the glass
            // like the label, or the container puts it beneath the glass. White
            // like the label, which every pressed colour carries at 3 : 1.
            .overlay {
                if isPressed, differentiateWithoutColor {
                    shape.inset(by: 3).strokeBorder(.white, lineWidth: 1.5)
                }
            }
            .gameGlass(in: shape, isPressed: isPressed, isSmallLabel: button.frame.height <= 40, backdrop: backdrop)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: button.label))
            .accessibilityIdentifier("touch-button-\(button.label)")
            .position(x: button.frame.midX, y: button.frame.midY)
    }

    /// Button names as plain text, never original symbols (hard rules). The
    /// label grows with a round button up to 34 pt, so the inner display does
    /// not show a 22 pt letter in a 100 pt circle.
    static func labelSize(for button: TouchLayout.Button) -> CGFloat {
        switch button.shape {
        case .circle: min(button.frame.width * 0.38, 34)
        case .capsule: min(button.frame.height * 0.42, 22)
        }
    }
}

/// The direction pad: one glass disc. A pressed direction lights its sector
/// on the plate beneath the glass, the same eight sectors as
/// `TouchLayout.direction`, so the glass bends the light softly. The reach of
/// 1.4 r stays invisible; it belongs to `TouchLayout`.
struct GlassPad: View {
    let pad: TouchLayout.Pad
    let pressed: JoypadButtons
    let backdrop: TouchControlsArt.Backdrop

    @Environment(\.gameStyle) private var gameStyle
    @Environment(\.controlSurface) private var surface
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    var body: some View {
        let radius = pad.radius
        let sector = Self.sectorAngle(of: pressed)
        ZStack {
            // The dead zone of TouchLayout as a thin ring.
            Circle()
                .strokeBorder(.white.opacity(0.14), lineWidth: 1)
                .frame(width: radius * 2 * TouchLayout.deadZone, height: radius * 2 * TouchLayout.deadZone)
            ForEach(Arrow.allCases, id: \.self) { arrow in
                Image(systemName: arrow.symbol)
                    .font(.system(size: radius * 0.3, weight: .semibold))
                    // At rest 0.85, not 0.55 as first planned: over white that
                    // measured 2.3 : 1. Pressed, the lit sector tells it apart.
                    .foregroundStyle(.white.opacity(pressed.contains(arrow.button) ? 1 : 0.85))
                    .offset(x: arrow.offset.width * radius * 0.62, y: arrow.offset.height * radius * 0.62)
            }
            if let sector, differentiateWithoutColor {
                PadSector(degrees: sector)
                    .stroke(.white, lineWidth: 1.5)
            }
        }
        .frame(width: radius * 2, height: radius * 2)
        .gameGlass(in: Circle(), backdrop: backdrop) {
            if let sector {
                PadSector(degrees: sector)
                    .fill(surface == .flat
                          ? Color.white.opacity(GamePlate.flatPressedOpacity - GamePlate.flatOpacity)
                          : gameStyle.pressedFill.opacity(GamePlate.pressedOpacity))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Direction pad", comment: "Accessibility label of the on-screen direction pad."))
        .accessibilityIdentifier("touch-pad")
        .position(pad.center)
    }

    /// The centre of the lit sector in degrees (0 is right, 90 is up), or nil
    /// when no direction is pressed.
    static func sectorAngle(of pressed: JoypadButtons) -> Double? {
        var x = 0.0
        var y = 0.0
        if pressed.contains(.right) { x += 1 }
        if pressed.contains(.left) { x -= 1 }
        if pressed.contains(.up) { y += 1 }
        if pressed.contains(.down) { y -= 1 }
        guard x != 0 || y != 0 else { return nil }
        return atan2(y, x) * 180 / .pi
    }

    private enum Arrow: CaseIterable {
        case up, down, left, right

        var symbol: String {
            switch self {
            case .up: "arrowtriangle.up.fill"
            case .down: "arrowtriangle.down.fill"
            case .left: "arrowtriangle.left.fill"
            case .right: "arrowtriangle.right.fill"
            }
        }

        var button: JoypadButtons {
            switch self {
            case .up: .up
            case .down: .down
            case .left: .left
            case .right: .right
            }
        }

        var offset: CGSize {
            switch self {
            case .up: CGSize(width: 0, height: -1)
            case .down: CGSize(width: 0, height: 1)
            case .left: CGSize(width: -1, height: 0)
            case .right: CGSize(width: 1, height: 0)
            }
        }
    }
}

/// A ring sector of 45 degrees from 0.30 r to 0.98 r around `degrees`.
nonisolated struct PadSector: Shape {
    var degrees: Double

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        // Screen y grows downwards, so the angle turns the other way.
        let start = Angle.degrees(-(degrees + 22.5))
        let end = Angle.degrees(-(degrees - 22.5))
        var path = Path()
        path.addArc(center: center, radius: radius * 0.98, startAngle: start, endAngle: end, clockwise: false)
        path.addArc(center: center, radius: radius * TouchLayout.deadZone, startAngle: end, endAngle: start, clockwise: true)
        path.closeSubpath()
        return path
    }
}

#if DEBUG
/// The controls of a system in a geometry of the Simulator's Duo, over the
/// deck and the test pattern, as `GameStage` draws them.
private struct ArtPreview: View {
    let system: GameSystem
    let geometry: FoldGeometry
    let pressed: JoypadButtons
    var flat = false

    var body: some View {
        let layout = GameLayout(system: system.screens, geometry: geometry, showsTouchControls: true)
        let scale = geometry.scale
        let screens = layout.screens.map { $0.destination.points(scale: scale) }
        let size = geometry.container.points(scale: scale)
        ZStack(alignment: .topLeading) {
            ForEach(Array(screens.enumerated()), id: \.offset) { _, screen in
                GameScreen(mailbox: PreviewContent.mailboxWithTestPattern(), stats: PresentationStats())
                    .frame(width: screen.width, height: screen.height)
                    .offset(x: screen.minX, y: screen.minY)
            }
            ControlDeck(areas: DeckLayout.areas(of: layout, in: geometry).map { $0.points(scale: scale) })
            if let zones = layout.controls {
                TouchControlsArt(layout: TouchLayout(zones: zones, scale: scale, hasXYButtons: system.hasXYButtons),
                                 pressed: pressed, screens: screens)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .background(.black)
        .environment(\.gameStyle, GameStyle(id: "1", name: "Selftest"))
        .environment(\.controlSurface, flat ? .flat : .glass)
    }
}

#Preview("Outer, closed", traits: .sizeThatFitsLayout) {
    HStack(spacing: 0) {
        ArtPreview(system: .gba, geometry: PreviewGeometry.closedBarOnTop, pressed: [])
        ArtPreview(system: .gba, geometry: PreviewGeometry.closedBarOnTop, pressed: [.a, .up])
        ArtPreview(system: .ds, geometry: PreviewGeometry.closed, pressed: [.x, .left])
        ArtPreview(system: .ds, geometry: PreviewGeometry.closed, pressed: [.a, .up], flat: true)
    }
}

#Preview("Inner, tabletop", traits: .sizeThatFitsLayout) {
    HStack(spacing: 0) {
        ArtPreview(system: .gba, geometry: PreviewGeometry.tabletop, pressed: [.a, .up])
        ArtPreview(system: .ds, geometry: PreviewGeometry.tabletop, pressed: [.y, .r])
    }
}

#Preview("Inner, book", traits: .sizeThatFitsLayout) {
    VStack(spacing: 0) {
        ArtPreview(system: .gba, geometry: PreviewGeometry.book, pressed: [])
        ArtPreview(system: .ds, geometry: PreviewGeometry.book, pressed: [.b, .down])
    }
}

/// Geometries of the Simulator's Duo for previews (docs/wissen/falz.md).
private enum PreviewGeometry {
    static let closed = FoldGeometry(container: PixelSize(width: 1398, height: 2034),
                                     safeArea: PixelInsets(bottom: 102, right: 252))
    static let closedBarOnTop = FoldGeometry(container: PixelSize(width: 1398, height: 2034),
                                             safeArea: PixelInsets(top: 246, bottom: 102))
    static let tabletop = FoldGeometry(container: PixelSize(width: 2007, height: 2853),
                                       fold: PixelRect(x: 0, y: 1366, width: 2007, height: 121), isFoldActive: true)
    static let book = FoldGeometry(container: PixelSize(width: 2853, height: 2007),
                                   fold: PixelRect(x: 1366, y: 0, width: 121, height: 2007), isFoldActive: true)
}
#endif
