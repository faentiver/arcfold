import LibretroKit
import SwiftUI

/// The on-screen buttons. One `SpatialEventGesture` sees every finger, so
/// several buttons work at once and a finger can slide from one to the next.
/// The mask comes from `TouchLayout`; this view only draws and forwards it.
struct TouchControls: View {
    let isLandscape: Bool
    /// Called with the full mask whenever it changes.
    let onChange: (JoypadButtons) -> Void

    @State private var pressed: JoypadButtons = []

    var body: some View {
        GeometryReader { proxy in
            let layout = TouchLayout(size: proxy.size, isLandscape: isLandscape)
            ZStack(alignment: .topLeading) {
                PadShape(pad: layout.pad, pressed: pressed)
                ForEach(layout.buttons) { button in
                    ButtonShape(button: button, isPressed: pressed.isSuperset(of: button.buttons))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .contentShape(Rectangle())
            .gesture(
                SpatialEventGesture()
                    .onChanged { events in
                        let points = events.filter { $0.phase == .active }.map(\.location)
                        update(layout.buttons(at: points))
                    }
                    .onEnded { _ in
                        update([])
                    }
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Game controls", comment: "Accessibility label of the on-screen game buttons."))
        .accessibilityIdentifier("touch-controls")
    }

    private func update(_ buttons: JoypadButtons) {
        guard buttons != pressed else { return }
        pressed = buttons
        onChange(buttons)
    }
}

private struct PadShape: View {
    let pad: TouchLayout.Pad
    let pressed: JoypadButtons

    var body: some View {
        let size = pad.radius * 2
        ZStack {
            Circle()
                .fill(.white.opacity(0.12))
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

    var body: some View {
        ZStack {
            switch button.shape {
            case .circle:
                Circle().fill(.white.opacity(isPressed ? 0.45 : 0.15))
                Circle().stroke(.white.opacity(0.4), lineWidth: 1.5)
            case .capsule:
                Capsule().fill(.white.opacity(isPressed ? 0.45 : 0.15))
                Capsule().stroke(.white.opacity(0.4), lineWidth: 1.5)
            }
            // Button names as plain text; no original symbols.
            Text(verbatim: button.label)
                .font(.system(size: min(button.frame.height * 0.42, 22), weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
        }
        .frame(width: button.frame.width, height: button.frame.height)
        .position(x: button.frame.midX, y: button.frame.midY)
    }
}

#Preview("Upright") {
    TouchControls(isLandscape: false) { _ in }
        .frame(width: 402, height: 420)
        .background(.black)
}

#Preview("Sideways") {
    TouchControls(isLandscape: true) { _ in }
        .frame(width: 874, height: 402)
        .background(.black)
}
