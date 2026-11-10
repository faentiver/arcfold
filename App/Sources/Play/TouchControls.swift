import FoldLayout
import LibretroKit
import SwiftUI

/// Draws the on-screen buttons of a `TouchLayout` in glass (`TouchControlsArt`,
/// ADR 0007) in the coordinates of the game view. Touches arrive at
/// `TouchSurface`, which sees every finger; this view only shows what is
/// pressed, the mask that went to the session. Each button is an
/// accessibility element of its own (`touch-button-<label>`, `touch-pad`), so
/// UI tests find it.
struct TouchControls: View {
    let layout: TouchLayout
    let pressed: JoypadButtons
    /// The screens in points of the game view: a button over one sits on the
    /// plate for the picture, every other one on the deck.
    let screens: [CGRect]
    /// The glass of the pause button, in the container of the buttons.
    var pause: PauseGlass?

    var body: some View {
        TouchControlsArt(layout: layout, pressed: pressed, screens: screens, pause: pause)
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
            // With VoiceOver, touches on the game go straight to it: the
            // buttons and the touch screen are played, not explored.
            .accessibilityElement()
            .accessibilityLabel(Text("Game controls", comment: "Accessibility label of the on-screen game buttons."))
            .accessibilityIdentifier("touch-surface")
            .accessibilityDirectTouch(options: .silentOnTouch)
            .accessibilityHidden(controls == nil && touchScreen == nil)
    }

    private func report(_ output: TouchRouter<SpatialEventCollection.Event.ID>.Output) {
        guard output != last else { return }
        last = output
        onChange(output)
    }
}
