import FoldLayout
import LibretroKit
import SwiftUI

/// Draws the on-screen buttons of a `TouchLayout` in the coordinates of the
/// game view. Touches arrive at `TouchSurface`, which sees every finger; this
/// view only shows what is pressed. Each button is an accessibility element of
/// its own (`touch-button-<label>`, `touch-pad`), so UI tests find it.
struct TouchControls: View {
    let layout: TouchLayout
    let pressed: JoypadButtons

    var body: some View {
        let fill = layout.overlapsScreen ? 0.1 : 0.15
        ZStack(alignment: .topLeading) {
            PadShape(pad: layout.pad, pressed: pressed, fill: fill)
            ForEach(layout.buttons) { button in
                ButtonShape(button: button, isPressed: pressed.isSuperset(of: button.buttons), fill: fill)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Game controls", comment: "Accessibility label of the on-screen game buttons."))
        .accessibilityIdentifier("touch-controls")
    }
}

/// Every finger on the game view: buttons through `TouchLayout`, the stylus
/// on the touch screen through `TouchMapping` (`TouchRouter`). One
/// `SpatialEventGesture` sees all fingers, so several buttons work at once, a
/// finger can slide from one button to the next, and buttons and the touch
/// screen work together.
struct TouchSurface: View {
    let controls: TouchLayout?
    let touchScreen: TouchMapping?
    /// Called whenever the mask or the stylus changes.
    let onChange: (TouchRouter<SpatialEventCollection.Event.ID>.Output) -> Void

    @State private var router = TouchRouter<SpatialEventCollection.Event.ID>()
    @State private var last = TouchRouter<SpatialEventCollection.Event.ID>.Output(buttons: [], touchPixel: nil)

    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                SpatialEventGesture()
                    .onChanged { events in
                        let touches = events.map {
                            TouchRouter<SpatialEventCollection.Event.ID>.Touch(
                                id: $0.id, location: $0.location, isActive: $0.phase == .active)
                        }
                        report(router.update(touches, controls: controls, touchScreen: touchScreen))
                    }
                    .onEnded { _ in
                        report(router.reset())
                    }
            )
            .accessibilityHidden(true)
    }

    private func report(_ output: TouchRouter<SpatialEventCollection.Event.ID>.Output) {
        guard output != last else { return }
        last = output
        onChange(output)
    }
}

private struct PadShape: View {
    let pad: TouchLayout.Pad
    let pressed: JoypadButtons
    let fill: Double

    var body: some View {
        let size = pad.radius * 2
        ZStack {
            Circle()
                .fill(.white.opacity(fill))
                .stroke(.white.opacity(0.35), lineWidth: 1.5)
            ForEach(Direction.allCases, id: \.self) { direction in
                Image(systemName: direction.symbol)
                    .font(.system(size: pad.radius * 0.3, weight: .semibold))
                    .foregroundStyle(.white.opacity(pressed.contains(direction.button) ? 0.95 : 0.5))
                    .offset(x: direction.offset.width * pad.radius * 0.62, y: direction.offset.height * pad.radius * 0.62)
            }
        }
        .frame(width: size, height: size)
        .position(pad.center)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Direction pad", comment: "Accessibility label of the on-screen direction pad."))
        .accessibilityIdentifier("touch-pad")
    }

    private enum Direction: CaseIterable {
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

private struct ButtonShape: View {
    let button: TouchLayout.Button
    let isPressed: Bool
    let fill: Double

    var body: some View {
        ZStack {
            switch button.shape {
            case .circle:
                Circle().fill(.white.opacity(isPressed ? 0.45 : fill))
                Circle().stroke(.white.opacity(0.4), lineWidth: 1.5)
            case .capsule:
                Capsule().fill(.white.opacity(isPressed ? 0.45 : fill))
                Capsule().stroke(.white.opacity(0.4), lineWidth: 1.5)
            }
            // Button names as plain text; no original symbols.
            Text(verbatim: button.label)
                .font(.system(size: min(button.frame.height * 0.42, 22), weight: .semibold, design: .rounded))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 4)
        }
        .frame(width: button.frame.width, height: button.frame.height)
        .position(x: button.frame.midX, y: button.frame.midY)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: button.label))
        .accessibilityIdentifier("touch-button-\(button.label)")
    }
}
