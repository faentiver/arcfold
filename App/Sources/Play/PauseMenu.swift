import SwiftUI

/// The pause button of a game, where `GameLayout` puts it (ADR 0006): in
/// the menu row between Select and Start with touch controls, in a corner of
/// the safe area without them. In-game glass, a circle of the size of its
/// place, over the plate of what lies beneath (rule R3), reacting to a touch
/// like the system's glass buttons. It takes touches on at least 44 × 44 pt,
/// also where it draws smaller. The pause sheet grows out of it.
///
/// Not the system's glass button style: that style sizes the glass by its
/// control size (47 pt at `.large`), and the menu row of M2 is 36 pt high.
struct PauseButton: View {
    /// The pause sheet zooms out of the button; nil without a sheet.
    let transition: Namespace.ID?
    /// The circle as drawn, in points.
    let diameter: CGFloat
    let backdrop: GlassBackdrop
    let pause: () -> Void

    /// Apple's smallest target for a touch, in points.
    nonisolated static let minimumTarget: CGFloat = 44

    var body: some View {
        Button(action: pause) {
            circle
                .frame(width: max(diameter, Self.minimumTarget), height: max(diameter, Self.minimumTarget))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Pause", comment: "Button that pauses the game and opens its menu."))
        .accessibilityIdentifier("pause")
        // The symbol keeps its size like a toolbar button; large content shows it bigger.
        .accessibilityShowsLargeContentViewer()
    }

    @ViewBuilder
    private var circle: some View {
        let circle = Image(systemName: "pause.fill")
            .font(.system(size: min(diameter * 0.42, 20), weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: diameter, height: diameter)
            .gameGlass(in: Circle(), backdrop: backdrop, isInteractive: true)
        if let transition {
            circle.matchedTransitionSource(id: PauseMenu.transitionID, in: transition)
        } else {
            circle
        }
    }
}

/// The menu of a paused game: a system sheet at medium height with the
/// system's glass, zooming out of the pause button. The buttons inside carry
/// no glass of their own (rule R4: no glass on glass). Swiping it away or
/// Escape resumes the game.
struct PauseMenu: View {
    static let transitionID = "pause"

    let gameName: String
    let transition: Namespace.ID
    @Binding var showsDebugOverlay: Bool
    let resume: () -> Void
    let quit: () -> Void

    @State private var detent = PresentationDetent.medium
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.prefersFades) private var prefersFades
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.layoutDirection) private var layoutDirection

    var body: some View {
        // Scrolls only when larger text no longer fits the medium detent.
        ScrollView {
            content
        }
        .scrollBounceBehavior(.basedOnSize)
        // Upright at medium height the sheet reaches over the system column
        // of the outer display, below its status bar, but the content kept
        // the column's inset and sat 38 pt left of centre (measured). That
        // part of the column holds nothing, so the content takes the sheet's
        // width. At large height the status bar and the sensors lie beside
        // the content, so the inset stays.
        .ignoresSafeArea(.container, edges: detent == .medium && verticalSizeClass == .regular ? columnEdge : [])
        // A container, or the identifier would replace those of the buttons.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pause-menu")
        .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.medium, .large] : [.medium], selection: $detent)
        .navigationTransition(prefersFades
            ? AnyNavigationTransition(.crossFade)
            : AnyNavigationTransition(.zoom(sourceID: Self.transitionID, in: transition)))
    }

    /// The column lies on the right of the outer display, whatever the
    /// direction of the language.
    private var columnEdge: Edge.Set {
        layoutDirection == .rightToLeft ? .leading : .trailing
    }

    private var content: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                GameArtwork(variant: .thumbnail)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Paused", comment: "Title of the menu of a paused game.")
                        .font(.headline)
                    // Primary and medium: over the sheet's glass the audit
                    // rated regular secondary text as failed (measured in
                    // pixels: 12.6 : 1 for primary).
                    Text(verbatim: gameName)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            VStack(spacing: 12) {
                Button(action: resume) {
                    Label {
                        Text("Resume", comment: "Button that continues a paused game.")
                    } icon: {
                        Image(systemName: "play.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("resume")

                Toggle(isOn: $showsDebugOverlay) {
                    Label {
                        Text("Debug Overlay", comment: "Switch in the pause menu that shows the measurements over the game.")
                    } icon: {
                        Image(systemName: "gauge.with.dots.needle.67percent")
                    }
                }
                .padding(.horizontal, 4)
                .accessibilityIdentifier("debug-overlay-toggle")

                Button(role: .destructive, action: quit) {
                    Label {
                        Text("Quit Game", comment: "Button that ends the game and returns to the library.")
                    } icon: {
                        Image(systemName: "xmark")
                    }
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("quit")
            }
            .controlSize(.extraLarge)
            .buttonSizing(.flexible)
            .buttonBorderShape(.capsule)
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 16)
    }
}

#if DEBUG
private struct PauseMenuPreview: View {
    @Namespace private var transition
    @State private var isShown = true
    @State private var showsDebugOverlay = true

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            PauseButton(transition: transition, diameter: 36, backdrop: .picture) { isShown = true }
                .padding(8)
        }
        .sheet(isPresented: $isShown) {
            PauseMenu(gameName: "selftest", transition: transition, showsDebugOverlay: $showsDebugOverlay,
                      resume: { isShown = false }, quit: { isShown = false })
        }
        .environment(\.gameStyle, GameStyle(id: "1", name: "selftest"))
        .preferredColorScheme(.dark)
    }
}

#Preview("Outer display", traits: .fixedLayout(width: 466, height: 678)) {
    PauseMenuPreview()
}

#Preview("Inner display", traits: .fixedLayout(width: 669, height: 951)) {
    PauseMenuPreview()
}
#endif
