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
    /// The safe area the sheet gives its content at the sides, as measured:
    /// the system column of the outer display insets one of them.
    @State private var sideInsets = PauseSheetMargins.Insets()
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.prefersFades) private var prefersFades
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    var body: some View {
        let margins = PauseSheetMargins(insets: sideInsets, isMediumHeight: detent == .medium,
                                        isUpright: verticalSizeClass == .regular)
        // Scrolls only when larger text no longer fits the medium detent.
        ScrollView {
            content
                .padding(.leading, margins.leading)
                .padding(.trailing, margins.trailing)
        }
        .scrollBounceBehavior(.basedOnSize)
        // The content sits in the middle of the sheet, with equal margins,
        // whichever side the system column insets (PauseSheetMargins).
        .ignoresSafeArea(.container, edges: margins.spannedEdges)
        // Read outside the modifier above, so the insets stay the sheet's.
        .onGeometryChange(for: PauseSheetMargins.Insets.self) { proxy in
            PauseSheetMargins.Insets(leading: proxy.safeAreaInsets.leading, trailing: proxy.safeAreaInsets.trailing)
        } action: { insets in
            sideInsets = insets
        }
        // A container, or the identifier would replace those of the buttons.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pause-menu")
        .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.medium, .large] : [.medium], selection: $detent)
        .navigationTransition(prefersFades
            ? AnyNavigationTransition(.crossFade)
            : AnyNavigationTransition(.zoom(sourceID: Self.transitionID, in: transition)))
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

/// How the content of the pause sheet evens out the inset that the system
/// column of the outer display leaves on one side, from the safe area the
/// sheet measures; where the column lies and how wide it is are read, not
/// assumed.
///
/// Upright at medium height the sheet lies below the status bar and the
/// sensors, so that part of the column holds nothing: the content takes the
/// sheet's width. Sideways the column lies beside the whole sheet, with the
/// camera in it: the content keeps clear of it and gets the same margin on
/// the other side. Upright at large height, which only large text reaches,
/// the status bar and the sensors lie beside the content and the inset
/// stays, because the text needs the width more than the symmetry.
nonisolated struct PauseSheetMargins: Equatable {
    /// The safe area at the sides of the sheet's content, in points.
    struct Insets: Hashable {
        var leading: CGFloat = 0
        var trailing: CGFloat = 0
    }

    /// The content ignores the safe area on these edges.
    var spannedEdges: Edge.Set = []
    /// Padding that makes both margins equal.
    var leading: CGFloat = 0
    var trailing: CGFloat = 0

    init(insets: Insets, isMediumHeight: Bool, isUpright: Bool) {
        guard abs(insets.leading - insets.trailing) > 0.5 else { return }
        if !isUpright {
            leading = max(0, insets.trailing - insets.leading)
            trailing = max(0, insets.leading - insets.trailing)
        } else if isMediumHeight {
            spannedEdges = insets.leading > insets.trailing ? .leading : .trailing
        }
    }

    /// The distance of the content from the sides of the sheet, for a
    /// content padding of `padding`.
    func contentMargins(insets: Insets, padding: CGFloat) -> (leading: CGFloat, trailing: CGFloat) {
        ((spannedEdges.contains(.leading) ? 0 : insets.leading) + leading + padding,
         (spannedEdges.contains(.trailing) ? 0 : insets.trailing) + trailing + padding)
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
