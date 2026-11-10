import FoldLayout
import LibretroKit
import Renderer
import SwiftUI

/// The game in one geometry (ADR 0006): the screens where `GameLayout` puts
/// them, drawn from one texture with one viewport each; the deck and the
/// touch controls in glass in their zones (ADR 0007); and the surface that
/// sends every finger to the buttons or to the touch screen. Everything is
/// laid out in pixels of the whole view, as `FoldGeometry` measured them, so
/// the stage ignores the safe area.
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
    /// The pause sheet grows out of the pause button.
    var pauseTransition: Namespace.ID?
    /// A sheet covers the stage: the glass of the controls would shine
    /// through the sheet's glass as smudges, so the controls fade out; the
    /// deck stays, and the sheet takes every touch anyway.
    var isCovered = false
    /// The core loads: the screens show the game's artwork with a spinner
    /// until the first picture.
    var isLoading = false

    @State private var pressed: JoypadButtons = []

    var body: some View {
        let scale = CGFloat(geometry.scale)
        let size = CGSize(width: CGFloat(geometry.container.width) / scale, height: CGFloat(geometry.container.height) / scale)
        let controls = Self.controls(of: layout, scale: geometry.scale, system: system, shows: showsControls)
        let placement = OverlayPlacement(layout: layout, geometry: geometry, controls: controls)
        let touchScreen = layout.touchScreen.map { TouchMapping(screen: $0, scale: geometry.scale) }
        let screens = layout.screens.map { $0.destination.points(scale: geometry.scale) }
        ZStack(alignment: .topLeading) {
            picture(screens: screens)
                .frame(width: size.width, height: size.height, alignment: .topLeading)
                // The screens jump to their new place; only the controls move (ADR 0006, section 9).
                .transaction { $0.animation = nil }
            if controls != nil {
                ControlDeck(areas: DeckLayout.areas(of: layout, in: geometry).map { $0.points(scale: geometry.scale) })
                    .frame(width: size.width, height: size.height)
                    .transaction { $0.animation = nil }
            }
            if let controls {
                TouchControls(layout: controls, pressed: pressed, screens: screens)
                    .frame(width: size.width, height: size.height)
                    .opacity(isCovered ? 0 : 1)
                    .animation(Motion.fade, value: isCovered)
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
            if let onPause, let pause = placement.pauseButton {
                // Where OverlayPlacement puts it, from GameLayout: between
                // Select and Start, or in a corner without touch controls.
                PauseButton(transition: pauseTransition, diameter: min(pause.width, pause.height),
                            backdrop: GlassBackdrop.under(pause, screens: screens), pause: onPause)
                    .position(x: pause.midX, y: pause.midY)
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

    /// The touch controls `GameStage` draws for `layout`, nil while they do
    /// not show; `OverlayPlacement` places the overlays around the same ones.
    nonisolated static func controls(of layout: GameLayout, scale: Int, system: GameSystem, shows: Bool) -> TouchLayout? {
        guard shows else { return nil }
        return layout.controls.map { TouchLayout(zones: $0, scale: scale, hasXYButtons: system.hasXYButtons) }
    }

    @ViewBuilder
    private func picture(screens: [CGRect]) -> some View {
        if let mailbox {
            GameScreen(mailbox: mailbox, stats: stats, isPaused: isPaused, arrangement: arrangement)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Game picture", comment: "Accessibility label of the emulated picture."))
                .accessibilityIdentifier("game-screen")
                // Smart Invert must not invert the game.
                .accessibilityIgnoresInvertColors()
        } else {
            // Before the first picture: the game's artwork on each screen,
            // the spinner on the first.
            ZStack(alignment: .topLeading) {
                Color.black
                ForEach(Array(screens.enumerated()), id: \.offset) { index, screen in
                    LoadingBackdrop(isLoading: isLoading, showsProgress: index == 0)
                        .frame(width: screen.width, height: screen.height)
                        .offset(x: screen.minX, y: screen.minY)
                }
            }
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
