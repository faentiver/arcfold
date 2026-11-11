import FoldLayout
import SwiftUI

/// The menu button of a game, which pauses it and opens the pause sheet,
/// where `GameLayout` puts it (ADR 0006): with touch controls among Select
/// and Start, in a corner of the safe area without them. In the case of the
/// console it is a small button with its name, "Menu", like Select and
/// Start (ADR 0007); over a screen it is in-game glass, a circle over the
/// plate for the picture (rule R3). It takes touches on at least
/// 44 × 44 pt, also where it draws smaller. The pause sheet grows out of it.
///
/// With touch controls they draw it with the buttons beside it
/// (`TouchControlsArt`), and the button above the touch surface only takes
/// the touch and reports while a finger holds it down, so that it shows
/// pressed like the keys beside it. Alone in its corner the button draws
/// itself.
struct PauseButton: View {
    /// The pause sheet zooms out of the button; nil without a sheet.
    let transition: Namespace.ID?
    /// The button with its name as drawn, in points.
    let size: CGSize
    let backdrop: GlassBackdrop
    /// The touch controls draw the button; this one stays clear.
    var isDrawnByControls = false
    /// A finger holds the button down or let it go; for the button the
    /// controls draw.
    var onPress: (Bool) -> Void = { _ in }
    let pause: () -> Void

    /// Apple's smallest target for a touch, in points.
    nonisolated static let minimumTarget: CGFloat = 44

    /// A finger holds the button down, while it draws itself.
    @State private var isPressed = false

    var body: some View {
        Button(action: pause) {
            face
                .frame(width: max(size.width, Self.minimumTarget), height: max(size.height, Self.minimumTarget))
                .contentShape(Rectangle())
        }
        .buttonStyle(ReportsPress { pressed in
            isPressed = pressed
            onPress(pressed)
        })
        .accessibilityLabel(Text("Pause", comment: "Button that pauses the game and opens its menu."))
        // The case writes "MENU" beside the button: Voice Control answers to
        // the name on the case as well as to the label.
        .accessibilityInputLabels([Text(verbatim: ConsoleControls.menuName),
                                   Text("Pause", comment: "Button that pauses the game and opens its menu.")])
        .accessibilityIdentifier("pause")
        // The button keeps its size like a toolbar button; large content shows it bigger.
        .accessibilityShowsLargeContentViewer()
    }

    @ViewBuilder
    private var face: some View {
        let face = Group {
            if isDrawnByControls {
                Color.clear
                    .frame(width: size.width, height: size.height)
            } else if backdrop == .picture {
                let diameter = min(size.width, size.height)
                PauseSymbol(diameter: diameter)
                    .gameGlass(in: Circle(), isInteractive: true)
            } else {
                ConsoleKnob(name: ConsoleControls.menuName, size: size, isPressed: isPressed, label: .below, isMenu: true)
            }
        }
        if let transition {
            face.matchedTransitionSource(id: PauseMenu.transitionID, in: transition)
        } else {
            face
        }
    }
}

/// The symbol of the pause button in a circle of `diameter`, without glass.
struct PauseSymbol: View {
    let diameter: CGFloat

    var body: some View {
        Image(systemName: "pause.fill")
            .font(.system(size: min(diameter * 0.42, 20), weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: diameter, height: diameter)
    }
}

/// A plain button that reports while a finger holds it down.
private struct ReportsPress: ButtonStyle {
    let onPress: (Bool) -> Void

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, isPressed in
                onPress(isPressed)
            }
    }
}

/// The menu of a paused game: a system sheet with the system's glass, as
/// high as its content, zooming out of the pause button. The buttons inside
/// carry no glass of their own (rule R4: no glass on glass). Swiping it away
/// or Escape resumes the game.
struct PauseMenu: View {
    static let transitionID = "pause"

    let gameName: String
    let transition: Namespace.ID
    /// The height of the window below a fold that lies bent across it, in
    /// points: the sheet stays in it. Nil without such a fold.
    var roomBelowFold: CGFloat?
    @Binding var showsDebugOverlay: Bool
    let resume: () -> Void
    let quit: () -> Void

    /// The height of the content as laid out; nil before the first layout.
    @State private var contentHeight: CGFloat?
    /// The safe area the sheet gives its content, as measured: the system
    /// column of the outer display insets one of its sides. Before the
    /// first layout it counts as wide enough at the bottom, as on every
    /// display with a home indicator, so that the content is measured once.
    @State private var insets = PauseSheetMargins.Insets(bottom: PauseSheetMargins.bottomMargin)
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.prefersFades) private var prefersFades
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    var body: some View {
        let margins = PauseSheetMargins(insets: insets, isUpright: verticalSizeClass == .regular)
        let height = PauseSheetHeight(content: contentHeight, roomBelowFold: roomBelowFold, bottomInset: insets.bottom)
        // Scrolls only when larger text is higher than the sheet may become.
        ScrollView {
            PauseMenuContent(gameName: gameName, showsDebugOverlay: $showsDebugOverlay, resume: resume, quit: quit)
                .padding(.leading, margins.leading)
                .padding(.trailing, margins.trailing)
                .padding(.bottom, margins.bottom)
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { height in
                    contentHeight = height
                }
        }
        .scrollBounceBehavior(.basedOnSize)
        // The content sits in the middle of the sheet, with equal margins,
        // whichever side the system column insets (PauseSheetMargins).
        .ignoresSafeArea(.container, edges: margins.spannedEdges)
        // Read outside the modifier above, so the insets stay the sheet's.
        .onGeometryChange(for: PauseSheetMargins.Insets.self) { proxy in
            PauseSheetMargins.Insets(leading: proxy.safeAreaInsets.leading, trailing: proxy.safeAreaInsets.trailing,
                                     bottom: proxy.safeAreaInsets.bottom)
        } action: { insets in
            self.insets = insets
        }
        // A container, or the identifier would replace those of the buttons.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pause-menu")
        .presentationDetents(height.detents(isAccessibilitySize: dynamicTypeSize.isAccessibilitySize))
        .navigationTransition(prefersFades
            ? AnyNavigationTransition(.crossFade)
            : AnyNavigationTransition(.zoom(sourceID: Self.transitionID, in: transition)))
    }
}

/// What the pause sheet shows: the game, Resume, the switch of the debug
/// overlay and Quit Game, with the margins at the top and the sides. The
/// margin at the bottom comes from the sheet (`PauseSheetMargins`).
struct PauseMenuContent: View {
    let gameName: String
    @Binding var showsDebugOverlay: Bool
    let resume: () -> Void
    let quit: () -> Void

    var body: some View {
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
    }
}

/// How high the pause sheet is: as high as its content, so that no empty
/// glass lies below the last button. The system keeps the sheet inside the
/// window, where larger text makes the content scroll.
///
/// The content is measured with the first layout, which comes while the
/// sheet already zooms out of the pause button. Until then the sheet has
/// the height of the content at the default text size, so that at the usual
/// sizes it opens without a second move; with the accessibility sizes it
/// begins at the system's medium height, as it used to.
///
/// Folded like a laptop, the sheet stays on the lower half, where the
/// system's medium height kept it, and what does not fit scrolls; a height
/// of one's own crosses the fold unless it is held. The sheet is given the
/// height of the window below the fold; the system keeps it 8 pt off the
/// edge of the display, so it begins 8 pt above the lower edge of the fold,
/// as the medium height did.
nonisolated struct PauseSheetHeight: Equatable {
    /// The height of the content as laid out; nil before the first layout.
    var content: CGFloat?
    /// The room for the content below a fold that lies bent across the
    /// window; nil without such a fold.
    var roomBelowFold: CGFloat?

    /// The height of `PauseMenuContent` at the default text size, with the
    /// safe area of the sheet as its margin at the bottom.
    static let contentAtDefaultSize: CGFloat = 235

    /// `roomBelowFold` is the height of the window below such a fold. The
    /// safe area at the bottom of the sheet, `bottomInset`, lies in it below
    /// the content.
    init(content: CGFloat?, roomBelowFold: CGFloat? = nil, bottomInset: CGFloat = 0) {
        self.content = content
        self.roomBelowFold = roomBelowFold.map { max(0, $0 - bottomInset) }
    }

    /// The height of the sheet's content area in whole points; nil before
    /// the first layout.
    var value: CGFloat? {
        guard let content else { return nil }
        let height = max(1, content.rounded(.up))
        guard let roomBelowFold else { return height }
        return min(height, max(1, roomBelowFold.rounded(.down)))
    }

    /// The fold holds the sheet lower than its content, which scrolls.
    var isHeldBelowFold: Bool {
        guard let content, let value else { return false }
        return value < content.rounded(.up)
    }

    /// The heights the sheet may have. Held below the fold, large text can
    /// still be pulled up to the full height, as with the medium height.
    func detents(isAccessibilitySize: Bool) -> Set<PresentationDetent> {
        guard let value else {
            return isAccessibilitySize ? [.medium] : [.height(Self.contentAtDefaultSize)]
        }
        return isHeldBelowFold && isAccessibilitySize ? [.height(value), .large] : [.height(value)]
    }

    /// The height of the view of `geometry` below a fold that lies bent
    /// across it, the tabletop posture, in points; nil in every other pose.
    static func roomBelowFold(in geometry: FoldGeometry?) -> CGFloat? {
        guard let geometry, geometry.posture == .tabletop, let fold = geometry.fold else { return nil }
        return CGFloat(geometry.container.height - fold.maxY) / CGFloat(geometry.scale)
    }
}

/// How the content of the pause sheet evens out the inset that the system
/// column of the outer display leaves on one side, from the safe area the
/// sheet measures; where the column lies and how wide it is are read, not
/// assumed.
///
/// Upright the content takes the sheet's width: the sheet lies below the
/// status bar and the sensors, so that part of the column holds nothing.
/// With the largest text the sheet reaches up beside them; there lies its
/// head, whose trailing end is empty, and the first button begins below
/// them (measured on the Duo: the sheet begins at 136 pt, the status bar
/// ends at 174 pt, Resume begins at 300 pt). Sideways the column lies beside
/// the whole sheet, with the camera in it: the content keeps clear of it and
/// gets the same margin on the other side.
///
/// At the bottom the safe area of the sheet is the margin; only where it is
/// narrower than `bottomMargin` the content adds the rest.
nonisolated struct PauseSheetMargins: Equatable {
    /// The safe area of the sheet's content, in points.
    struct Insets: Hashable {
        var leading: CGFloat = 0
        var trailing: CGFloat = 0
        var bottom: CGFloat = 0
    }

    /// The least distance of the content from the lower edge of the sheet.
    static let bottomMargin: CGFloat = 20

    /// The content ignores the safe area on these edges.
    var spannedEdges: Edge.Set = []
    /// Padding that makes both margins equal.
    var leading: CGFloat = 0
    var trailing: CGFloat = 0
    /// Padding below the content, inside the safe area.
    var bottom: CGFloat = 0

    init(insets: Insets, isUpright: Bool) {
        bottom = max(0, Self.bottomMargin - insets.bottom)
        guard abs(insets.leading - insets.trailing) > 0.5 else { return }
        if isUpright {
            spannedEdges = insets.leading > insets.trailing ? .leading : .trailing
        } else {
            leading = max(0, insets.trailing - insets.leading)
            trailing = max(0, insets.leading - insets.trailing)
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
            PauseButton(transition: transition, size: CGSize(width: 44, height: 44), backdrop: .picture) { isShown = true }
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
