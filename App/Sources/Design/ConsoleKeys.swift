import LibretroKit
import SwiftUI

/// The controls of a `TouchLayout` that stand in the case of the console:
/// every one that lies over no screen, as a key (ADR 0007). Controls over a
/// screen stay glass and are drawn by `TouchControlsArt`. Drawing only; a
/// press redraws the pressed key alone, the others compare equal.
struct ConsoleControls: View {
    let layout: TouchLayout
    let pressed: JoypadButtons
    /// The screens, in the coordinates of the controls.
    let screens: [CGRect]
    /// The menu button, which pauses the game: drawn here as a small button
    /// like Select and Start; the button that takes its touches lies above
    /// the touch surface (`PauseButton`). Nil without one.
    var pause: PauseGlass?

    var body: some View {
        ZStack(alignment: .topLeading) {
            if Self.standsInCase(layout.pad.frame, screens: screens) {
                ConsolePad(pad: layout.pad, directions: pressed.intersection([.up, .down, .left, .right]))
                    .equatable()
            }
            ForEach(layout.buttons.filter { Self.standsInCase($0.frame, screens: screens) }) { button in
                ConsoleKey(button: button, isPressed: pressed.isSuperset(of: button.buttons), knobLabel: layout.knobLabel,
                           isFlush: Self.standsRightAboveAScreen(button.frame, screens: screens))
                    .equatable()
            }
            if let pause, Self.standsInCase(pause.frame, screens: screens) {
                // The button above the touch surface is the element; the
                // knob hides its name from accessibility itself.
                ConsoleKnob(name: Self.menuName, size: pause.frame.size, isPressed: pause.isPressed,
                            label: layout.knobLabel, isMenu: true)
                    .position(x: pause.frame.midX, y: pause.frame.midY)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// The name on the case beside the menu button, like Select and Start a
    /// plain word, not translated.
    static let menuName = "Menu"

    /// A control at `frame` lies over no screen: it is a key in the case.
    nonisolated static func standsInCase(_ frame: CGRect, screens: [CGRect]) -> Bool {
        !screens.contains { $0.intersects(frame) }
    }

    /// A screen begins right below the well of a key at `frame`, as below L
    /// and R in the hinge between the two screens of the DS: the key then
    /// throws no shadow and no light beyond its well, so that the picture
    /// stays what the core drew, to the pixel.
    nonisolated static func standsRightAboveAScreen(_ frame: CGRect, screens: [CGRect]) -> Bool {
        screens.contains { screen in
            screen.minY >= frame.maxY && screen.minY - frame.maxY < ConsoleSkin.capReach
                && screen.minX < frame.maxX + ConsoleSkin.wellWidth && screen.maxX > frame.minX - ConsoleSkin.wellWidth
        }
    }
}

/// The menu button as the controls draw it: where it sits, and whether a
/// finger holds it down, which the button reports.
nonisolated struct PauseGlass: Sendable, Hashable {
    var frame: CGRect
    var isPressed = false

    /// Who draws a menu button in `frame`: the touch controls while they
    /// show, as one of their small buttons; without them the button itself,
    /// alone in its corner.
    static func drawnByControls(_ controls: TouchLayout?, frame: CGRect?, isPressed: Bool) -> PauseGlass? {
        guard controls != nil, let frame else { return nil }
        return PauseGlass(frame: frame, isPressed: isPressed)
    }
}

/// A cap that stands out of a well in the case: the well with the light on
/// the edge below it, the shadow the cap throws, and the cap with the light
/// on its upper edge. Pressed, the cap sits lower in its well, throws no
/// shadow and shows its other colour. No animation: what is shown pressed
/// is the mask that went to the session (rule R5).
struct KeyCap<S: InsettableShape>: View {
    let shape: S
    let isPressed: Bool
    /// The cap of the menu button has a colour of its own.
    var isMenu = false
    /// How far the cap stands out: 1 for a key, less for a small button.
    var relief: CGFloat = 1
    /// A screen begins right below the well: nothing of the key reaches
    /// beyond its well, neither the light on the edge below nor the shadow
    /// of the cap.
    var isFlush = false

    @Environment(\.consoleSkin) private var skin
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    var body: some View {
        let well = ConsoleSkin.wellWidth * relief
        ZStack {
            if !isFlush {
                shape.inset(by: -well)
                    .fill(skin.bodyLight.opacity(skin.isLight ? 1 : 0.3))
                    .offset(y: 1)
            }
            shape.inset(by: -well)
                .fill(skin.well.shadow(.inner(color: .black.opacity(0.4), radius: 1.5 * relief, x: 0, y: 1)))
            ZStack {
                if isPressed {
                    shape
                        .fill(face.shadow(.inner(color: .black.opacity(0.35), radius: 2.5 * relief, x: 0, y: 1.5 * relief)))
                        .offset(y: ConsoleSkin.capTravel * relief)
                } else {
                    shape
                        .fill(face
                            .shadow(.inner(color: skin.capGlint, radius: 0.5, x: 0, y: 1))
                            .shadow(.inner(color: .black.opacity(0.16), radius: 1.5 * relief, x: 0, y: -1.5 * relief))
                            .shadow(.drop(color: .black.opacity(0.42), radius: 2 * relief, x: 0, y: ConsoleSkin.capHeight * relief)))
                }
                // Increase Contrast: a firm edge around every key. Pressed
                // without colour: a ring inside it.
                if contrast == .increased {
                    shape.strokeBorder(skin.outline, lineWidth: 1.5)
                        .offset(y: isPressed ? ConsoleSkin.capTravel * relief : 0)
                }
                if isPressed, differentiateWithoutColor {
                    shape.inset(by: 3 * relief).strokeBorder(skin.legendStrong, lineWidth: 1.5)
                        .offset(y: ConsoleSkin.capTravel * relief)
                }
            }
            // The shadow of the cap ends with the well where a screen
            // begins below it, and falls on the case everywhere else.
            .clipShape(shape.inset(by: isFlush ? -well : -ConsoleSkin.capReach))
        }
    }

    private var face: LinearGradient {
        let colors: [Color] = switch (isMenu, isPressed) {
        case (false, false): [skin.capTop, skin.capBottom]
        case (false, true): [skin.capPressedTop, skin.capPressedBottom]
        case (true, false): [skin.menuTop, skin.menuBottom]
        case (true, true): [skin.menuBottom, skin.menuTop]
        }
        return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }
}

/// A letter engraved in a cap: shade at its upper edge, light below it.
/// Letters only, never an original symbol (hard rules).
struct KeyLegend: View {
    let text: String
    let size: CGFloat
    let isPressed: Bool
    var relief: CGFloat = 1

    @Environment(\.consoleSkin) private var skin
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Text(verbatim: text)
            .font(.system(size: size, weight: .bold, design: .rounded))
            .lineLimit(1)
            .foregroundStyle((isPressed || contrast == .increased ? skin.legendStrong : skin.legend)
                .shadow(.inner(color: .black.opacity(0.3), radius: 0.4, x: 0, y: 0.6)))
            .shadow(color: skin.capGlint.opacity(isPressed ? 0.4 : 0.9), radius: 0, x: 0, y: 0.8)
            .offset(y: isPressed ? ConsoleSkin.capTravel * relief : 0)
    }
}

/// A key of the console where `TouchLayout` puts it: a round face button, a
/// wide L or R, or a small button with its name. Drawing only; the touch
/// surface above takes the touches. Each key stays an accessibility element
/// of its own (`touch-button-<label>`), so UI tests find it.
struct ConsoleKey: View, Equatable {
    let button: TouchLayout.Button
    let isPressed: Bool
    /// Where a small button carries its name.
    let knobLabel: TouchLayout.KnobLabel
    /// A screen begins right below the key's well (`KeyCap.isFlush`).
    var isFlush = false

    nonisolated static func == (lhs: ConsoleKey, rhs: ConsoleKey) -> Bool {
        lhs.button == rhs.button && lhs.isPressed == rhs.isPressed && lhs.knobLabel == rhs.knobLabel
            && lhs.isFlush == rhs.isFlush
    }

    /// How far a key stands out of the case, and how wide its well is in
    /// shares of `ConsoleSkin.wellWidth`: L or R at the ends of a slim hinge
    /// half as far as every other key.
    nonisolated static func relief(of button: TouchLayout.Button) -> CGFloat {
        button.shape == .capsule && button.frame.height < ConsoleSkin.lowKey ? 0.5 : 1
    }

    var body: some View {
        Group {
            switch button.shape {
            case .circle:
                ZStack {
                    KeyCap(shape: Circle(), isPressed: isPressed, isFlush: isFlush)
                    KeyLegend(text: button.label, size: button.frame.height * ConsoleSkin.letterShare, isPressed: isPressed)
                }
            case .capsule:
                // L and R: the same key in every pose. At the ends of a
                // slim hinge they are lower and stand out half as far.
                let relief = Self.relief(of: button)
                ZStack {
                    KeyCap(shape: RoundedRectangle(cornerRadius: button.frame.height * ConsoleSkin.shoulderCorner, style: .continuous),
                           isPressed: isPressed, relief: relief, isFlush: isFlush)
                    KeyLegend(text: button.label,
                              size: max(ConsoleSkin.smallestLetter, button.frame.height * ConsoleSkin.shoulderLetterShare),
                              isPressed: isPressed, relief: relief)
                }
            case .knob:
                ConsoleKnob(name: button.label, size: button.frame.size, isPressed: isPressed, label: knobLabel)
            }
        }
        .frame(width: button.frame.width, height: button.frame.height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: button.label))
        .accessibilityIdentifier("touch-button-\(button.label)")
        .position(x: button.frame.midX, y: button.frame.midY)
    }
}

/// A small round button with its name written on the case, below it or
/// right of it: Select, Start and the menu button. `size` holds both and is
/// what takes the touches.
struct ConsoleKnob: View {
    let name: String
    let size: CGSize
    let isPressed: Bool
    let label: TouchLayout.KnobLabel
    var isMenu = false

    @Environment(\.consoleSkin) private var skin
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.legibilityWeight) private var legibilityWeight

    var body: some View {
        // A row too low for the button with its name below it takes the
        // smaller button; no pose of the Duo has one.
        let isLow = label == .below && size.height < ConsoleSkin.knob + ConsoleSkin.inscriptionBelow + ConsoleSkin.inscriptionSize * 1.25
        let diameter = isLow ? ConsoleSkin.smallKnob : ConsoleSkin.knob
        let cap = KeyCap(shape: Circle(), isPressed: isPressed, isMenu: isMenu, relief: 0.6)
            .frame(width: diameter, height: diameter)
        let text = Text(verbatim: name.uppercased())
            .font(.system(size: ConsoleSkin.inscriptionSize, weight: legibilityWeight == .bold ? .bold : .semibold,
                          design: .rounded))
            .tracking(0.6)
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(contrast == .increased ? skin.inscriptionStrong : skin.inscription)
            // Engraved in a light case: the light catches its lower edge.
            .shadow(color: skin.bodyLight.opacity(skin.isLight ? 0.9 : 0), radius: 0, x: 0, y: 0.75)
            // The name is written on the case; the key or the menu button
            // it belongs to is the accessibility element.
            .accessibilityHidden(true)
        switch label {
        case .below:
            VStack(spacing: isLow ? 1 : ConsoleSkin.inscriptionBelow) {
                cap
                text
            }
            .frame(width: size.width, height: size.height)
        case .beside:
            let group = diameter + ConsoleSkin.inscriptionBeside + ConsoleSkin.widestInscription
            HStack(spacing: ConsoleSkin.inscriptionBeside) {
                cap
                text
            }
            .padding(.leading, max(ConsoleSkin.wellWidth, (size.width - group) / 2))
            .frame(width: size.width, height: size.height, alignment: .leading)
        }
    }
}

/// The direction pad: a cross with round arms that stands out of a dish in
/// the case. A pressed direction tips its arm: the arm shows the pressed
/// colour towards its end and the cross moves a point that way, at once and
/// without animation (rule R5). The dish is the circle that takes touches;
/// between the arms it takes the diagonals. The reach of 1.4 r stays
/// invisible; it belongs to `TouchLayout`.
struct ConsolePad: View, Equatable {
    let pad: TouchLayout.Pad
    /// The pressed directions.
    let directions: JoypadButtons

    @Environment(\.consoleSkin) private var skin
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    nonisolated static func == (lhs: ConsolePad, rhs: ConsolePad) -> Bool {
        lhs.pad == rhs.pad && lhs.directions == rhs.directions
    }

    var body: some View {
        let size = pad.radius * 2
        let cross = size * ConsoleSkin.padCross
        let arm = cross * ConsoleSkin.padArm
        let shape = PadCross(arm: ConsoleSkin.padArm, corner: ConsoleSkin.padCorner)
        let tip = Self.tip(of: directions)
        ZStack {
            // The dish: set into the case, dark at the top, light at the bottom.
            Circle()
                .fill(skin.bodyLight.opacity(skin.isLight ? 1 : 0.3))
                .offset(y: 1)
            Circle()
                .fill(LinearGradient(colors: [skin.bodyBottom.mix(with: skin.bodyShade, by: skin.isLight ? 0.2 : 0.4),
                                              skin.bodyTop.mix(with: skin.bodyBottom, by: 0.5)],
                                     startPoint: .top, endPoint: .bottom)
                    .shadow(.inner(color: skin.bodyShade.opacity(skin.isLight ? 0.4 : 0.7), radius: 3, x: 0, y: 2)))
            ZStack {
                shape
                    .fill(LinearGradient(colors: [skin.capTop, skin.capBottom], startPoint: .top, endPoint: .bottom)
                        .shadow(.inner(color: skin.capGlint, radius: 0.5, x: 0, y: 1))
                        .shadow(.inner(color: .black.opacity(0.16), radius: 1.5, x: 0, y: -1.5))
                        .shadow(.drop(color: .black.opacity(0.45), radius: 3, x: 0, y: 3)))
                ForEach(Arrow.allCases, id: \.self) { arrow in
                    let isPressed = directions.contains(arrow.button)
                    if isPressed {
                        // The arm from the middle to its end, darker towards the end.
                        PadArm(direction: arrow.offset, arm: ConsoleSkin.padArm, corner: ConsoleSkin.padCorner)
                            .fill(LinearGradient(colors: [skin.capPressedBottom.opacity(0), skin.capPressedTop],
                                                 startPoint: arrow.start, endPoint: arrow.end)
                                .shadow(.inner(color: .black.opacity(0.3), radius: 2.5, x: -arrow.offset.width * 1.5,
                                               y: -arrow.offset.height * 1.5)))
                    }
                    Image(systemName: arrow.symbol)
                        .font(.system(size: arm * 0.4, weight: .bold))
                        .foregroundStyle((isPressed || contrast == .increased ? skin.legendStrong : skin.legend.opacity(0.85))
                            .shadow(.inner(color: .black.opacity(0.3), radius: 0.4, x: 0, y: 0.6)))
                        .shadow(color: skin.capGlint.opacity(0.9), radius: 0, x: 0, y: 0.8)
                        .offset(x: arrow.offset.width * (cross - arm) / 2 * 0.86, y: arrow.offset.height * (cross - arm) / 2 * 0.86)
                    if isPressed, differentiateWithoutColor {
                        PadArm(direction: arrow.offset, arm: ConsoleSkin.padArm, corner: ConsoleSkin.padCorner)
                            .stroke(skin.legendStrong, lineWidth: 1.5)
                    }
                }
                // The hollow in the middle, where the thumb rests.
                Circle()
                    .fill(LinearGradient(colors: [skin.capBottom, skin.capTop], startPoint: .top, endPoint: .bottom)
                        .shadow(.inner(color: .black.opacity(0.22), radius: 1.5, x: 0, y: 1)))
                    .frame(width: arm * 0.5, height: arm * 0.5)
                if contrast == .increased {
                    shape.stroke(skin.outline, lineWidth: 1.5)
                }
            }
            .frame(width: cross, height: cross)
            .offset(x: tip.width, y: tip.height)
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Direction pad", comment: "Accessibility label of the on-screen direction pad."))
        .accessibilityIdentifier("touch-pad")
        .position(pad.center)
    }

    /// How far the cross moves towards the pressed directions.
    nonisolated static func tip(of directions: JoypadButtons) -> CGSize {
        var tip = CGSize.zero
        if directions.contains(.right) { tip.width += 1 }
        if directions.contains(.left) { tip.width -= 1 }
        if directions.contains(.down) { tip.height += 1 }
        if directions.contains(.up) { tip.height -= 1 }
        return tip
    }

    /// The four arrows on the arms: plain triangles, no original symbols.
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

        /// From the middle of the cross to the end of the arm.
        var start: UnitPoint { .center }
        var end: UnitPoint {
            switch self {
            case .up: .top
            case .down: .bottom
            case .left: .leading
            case .right: .trailing
            }
        }
    }
}

/// A cross whose arms take `arm` of its size, their ends rounded by
/// `corner` of their width.
nonisolated struct PadCross: Shape {
    var arm: CGFloat
    var corner: CGFloat

    func path(in rect: CGRect) -> Path {
        let width = min(rect.width, rect.height) * arm
        let radius = width * corner
        let across = Path(roundedRect: CGRect(x: rect.minX, y: rect.midY - width / 2, width: rect.width, height: width),
                          cornerRadius: radius, style: .continuous)
        let down = Path(roundedRect: CGRect(x: rect.midX - width / 2, y: rect.minY, width: width, height: rect.height),
                        cornerRadius: radius, style: .continuous)
        return across.union(down)
    }
}

/// One arm of `PadCross` from the middle to its end, in the direction of
/// `direction`, a unit step.
nonisolated struct PadArm: Shape {
    var direction: CGSize
    var arm: CGFloat
    var corner: CGFloat

    func path(in rect: CGRect) -> Path {
        let width = min(rect.width, rect.height) * arm
        let radius = width * corner
        let frame: CGRect
        if direction.width != 0 {
            let x = direction.width < 0 ? rect.minX : rect.midX
            frame = CGRect(x: x, y: rect.midY - width / 2, width: rect.width / 2, height: width)
        } else {
            let y = direction.height < 0 ? rect.minY : rect.midY
            frame = CGRect(x: rect.midX - width / 2, y: y, width: width, height: rect.height / 2)
        }
        // Round at the end of the arm only: cut the rounded cross to the half.
        let whole = PadCross(arm: arm, corner: corner).path(in: rect)
        _ = radius
        return whole.intersection(Path(frame))
    }
}
