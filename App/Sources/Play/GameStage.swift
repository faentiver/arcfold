import FoldLayout
import LibretroKit
import Renderer
import SwiftUI

/// The game in one geometry (ADR 0006): the screens where `GameLayout` puts
/// them, drawn from one texture with one viewport each; the touch controls in
/// their zones; and the surface that sends every finger to the buttons or to
/// the touch screen. Everything is laid out in pixels of the whole view, as
/// `FoldGeometry` measured them, so the stage ignores the safe area.
struct GameStage: View {
    let system: GameSystem
    let geometry: FoldGeometry
    let layout: GameLayout
    let mailbox: FrameMailbox?
    let stats: PresentationStats
    let isPaused: Bool
    /// The touch controls are drawn and take touches (the game runs and no
    /// controller is in use).
    let showsControls: Bool
    let onButtons: (JoypadButtons) -> Void
    /// The touch screen's pointer, nil when lifted.
    let onPointer: (PointerPosition?) -> Void
    /// The pause button: between Select and Start with touch controls, in
    /// the corner `GameLayout.pauseButton` names without them; nil hides it.
    let onPause: (() -> Void)?

    @State private var pressed: JoypadButtons = []

    /// Apple's smallest target for a touch, in points; a smaller pause button
    /// draws smaller but still takes touches over this square.
    static let minimumTarget: CGFloat = 44

    var body: some View {
        let scale = CGFloat(geometry.scale)
        let size = CGSize(width: CGFloat(geometry.container.width) / scale, height: CGFloat(geometry.container.height) / scale)
        let controls = showsControls ? layout.controls.map {
            TouchLayout(zones: $0, scale: geometry.scale, hasXYButtons: system.hasXYButtons)
        } : nil
        let touchScreen = layout.touchScreen.map { TouchMapping(screen: $0, scale: geometry.scale) }
        ZStack(alignment: .topLeading) {
            picture
                .frame(width: size.width, height: size.height)
                // The screens jump to their new place; only the controls move (ADR 0006, section 9).
                .transaction { $0.animation = nil }
            if let controls {
                TouchControls(layout: controls, pressed: pressed)
                    .frame(width: size.width, height: size.height)
                    .transition(.opacity)
            }
            TouchSurface(controls: controls, touchScreen: touchScreen) { output in
                if output.buttons != pressed {
                    pressed = output.buttons
                    onButtons(output.buttons)
                }
                onPointer(output.touchPixel.flatMap { pointer(at: $0, on: touchScreen) })
            }
            .frame(width: size.width, height: size.height)
            if let onPause {
                if let controls {
                    pauseButton(in: controls.pauseButton, action: onPause)
                } else if let pause = layout.pauseButton {
                    pauseButton(in: pause.points(scale: geometry.scale), action: onPause)
                }
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(.snappy, value: layout.controls)
        .onChange(of: showsControls) { _, shows in
            // Buttons held when the controls go away are released.
            if !shows, !pressed.isEmpty {
                pressed = []
                onButtons([])
            }
        }
    }

    @ViewBuilder
    private var picture: some View {
        if let mailbox {
            GameScreen(mailbox: mailbox, stats: stats, isPaused: isPaused, arrangement: arrangement)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Game picture", comment: "Accessibility label of the emulated picture."))
                .accessibilityIdentifier("game-screen")
        } else {
            Color.black
        }
    }

    /// The layout's screens as viewports of the drawable, which has the
    /// layout's pixels per point.
    private var arrangement: ScreenArrangement {
        ScreenArrangement(pixelsPerPoint: geometry.scale, viewports: layout.screens.map { screen in
            ScreenViewport(
                sourceX: screen.source.x, sourceY: screen.source.y,
                sourceWidth: screen.source.width, sourceHeight: screen.source.height,
                originX: screen.destination.x, originY: screen.destination.y, scale: screen.scale)
        })
    }

    /// The libretro pointer for a pixel of the touch screen: the pixel's place
    /// in the core's whole frame, for example row 192 + y on the DS.
    private func pointer(at pixel: TouchMapping.Pixel, on touchScreen: TouchMapping?) -> PointerPosition? {
        guard let touchScreen else { return nil }
        let frame = touchScreen.framePixel(of: pixel)
        let size = system.screens.frameSize
        return PointerPosition(pixelX: frame.x, pixelY: frame.y, frameWidth: size.width, frameHeight: size.height)
    }

    private func pauseButton(in frame: CGRect, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "pause.fill")
                .font(.system(size: min(frame.height * 0.45, 17), weight: .semibold))
                .frame(width: frame.width, height: frame.height)
                .background(.white.opacity(0.15), in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.4), lineWidth: 1.5))
                .frame(width: max(frame.width, Self.minimumTarget), height: max(frame.height, Self.minimumTarget))
                .contentShape(Rectangle())
        }
        .tint(.white)
        .accessibilityLabel(Text("Pause", comment: "Button that pauses the game and opens its menu."))
        .accessibilityIdentifier("pause")
        .position(x: frame.midX, y: frame.midY)
    }
}

/// The vertical system bar of the outer display: off for the whole game view
/// of systems that ask for it, so that the choice stays stable as Apple asks
/// (ADR 0006, section 7). iOS 27.1 and later.
struct VerticalBarBehavior: ViewModifier {
    let isDisabled: Bool

    func body(content: Content) -> some View {
        if #available(iOS 27.1, *) {
            content.toolbarVerticalBehavior(isDisabled ? .disabled : .automatic)
        } else {
            content
        }
    }
}
