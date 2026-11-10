#if DEBUG
import FoldLayout
import LibretroKit
import Renderer
import SwiftUI

/// The building blocks of the interface on fixed pages, for screenshots that
/// look the same on every run: pressed states, backdrops and the sizes of the
/// inner display. Every page draws the controls, the deck, the pause button
/// and the overlays from `GameLayout` in a geometry of the Simulator's Duo
/// (ADR 0006), the way `GameStage` and `GameOverlays` do in a game. Opened by
/// `-ArcfoldGallery <page>` in debug builds (ADR 0007). Nothing here is
/// localized; the texts are for development only.
struct GlassGallery: View {
    enum Page: String, CaseIterable {
        case libraryEmpty = "library-empty"
        case libraryShelf = "library-shelf"
        case libraryInner = "library-inner"
        case touchUpright = "touch-upright"
        case touchLandscape = "touch-landscape"
        case touchInner = "touch-inner"
        /// Pressed controls with Differentiate Without Color.
        case touchDifferentiate = "touch-differentiate"
        case notices
        case failure
        case loading
        /// The game screen sideways, turned by 90 degrees to fit the upright
        /// window, so that one page shows every part of it at once.
        case gameLandscape = "game-landscape"
    }

    let page: Page

    /// The page of the launch arguments, if any.
    static var requestedPage: Page? {
        UserDefaults.standard.string(forKey: "ArcfoldGallery").flatMap(Page.init(rawValue:))
    }

    /// `-ArcfoldGalleryPressed YES` shows the sideways controls pressed; one
    /// state per launch keeps them large enough to measure.
    static var showsPressed: Bool {
        UserDefaults.standard.bool(forKey: "ArcfoldGalleryPressed")
    }

    /// selftest.gba, so the gallery shows the colours of the test game.
    static let selftest = Game(
        id: "7df143129e713b1188ec40b3d91bd84ccb95188dd1f6264f2bb75fba4544f9fd", name: "selftest", system: "gba",
        originalFileName: "selftest.gba", size: 864, importedAt: Date(timeIntervalSince1970: 1_794_000_000))

    /// Eight games with fixed ids. Sorted by name, as the library shows them,
    /// no two neighbours in two columns share their colours, and neighbours
    /// with the same pattern differ in colour.
    static let shelf: [Game] = [
        ("df60162d7ae3f63fc541113863366fd3d41e20880402df1be90330be59fe70ee", "Arc-Light"),
        ("b2f254e545c3cae39250e1be66b99882e07b0187e47a9baf00a1b1942f865494", "fold_runner"),
        ("24e1c5ac9c39f564dfbcd1ecc64dd1e18ceaf7ae28208c9bc2a02109f2ad1d88", "Homebrew Demo"),
        ("0c1fbee21907a1258e4a04c83e6dd09d5c8224afe513e54d42856957528701ee", "Night Drive"),
        ("b35ab202b5e842781ed9038e7c19a3cf935543b74f7735cffeb06c3e47e92b40", "Pixel Quest"),
        ("7df143129e713b1188ec40b3d91bd84ccb95188dd1f6264f2bb75fba4544f9fd", "selftest"),
        ("e01e585b235bdbb48894b0b2c1abad9614f9646a07322985c5d1548250f3604f", "Star Garden"),
        ("0bd9cb30441edfa4ea9e21a075162d7242ab8fea2d58d018f9d211e13d4175cd", "Tiny Racer"),
    ].enumerated().map { index, entry in
        Game(id: entry.0, name: entry.1, system: "gba", originalFileName: "\(entry.1).gba", size: 1024,
             importedAt: Date(timeIntervalSince1970: 1_794_000_000 - Double(index) * 86_400))
    }

    var body: some View {
        switch page {
        case .libraryEmpty:
            LibraryView { _ in }
                .environment(GameLibrary(previewing: []))
        case .libraryShelf:
            LibraryView { _ in }
                .environment(GameLibrary(previewing: Self.shelf))
        case .libraryInner:
            ScaledToFit(size: CGSize(width: 669, height: 951)) {
                ScrollView {
                    GameGrid(games: Self.shelf, width: 669) { _ in }
                        .padding(.top, 8)
                }
                .background(Color(uiColor: .systemBackground))
            }
        case .touchUpright:
            // The band of the closed GBA below its picture, on the deck.
            InGamePage {
                VStack(spacing: 0) {
                    ForEach(Self.uprightRows, id: \.name) { row in
                        GalleryPanel(scene: .closedGBA, part: .controls, backdrop: .deck, pressed: row.pressed, row: row.name)
                    }
                }
            }
        case .touchLandscape:
            // The closed GBA sideways: every control lies over the picture.
            InGamePage {
                let isPressed = Self.showsPressed
                VStack(spacing: 0) {
                    ForEach(PanelBackdrop.allCases, id: \.self) { backdrop in
                        GalleryPanel(scene: .sidewaysGBA, part: .whole, backdrop: backdrop,
                                     pressed: isPressed ? Self.allPressed : [],
                                     row: "\(backdrop.rawValue)-\(isPressed ? "pressed" : "rest")")
                    }
                }
            }
        case .touchInner:
            // The DS in the tabletop pose of the inner display, below the fold.
            InGamePage {
                GalleryPanel(scene: .tabletopDS, part: .controls, backdrop: .pattern, pressed: [.a, .up, .x], row: "inner")
            }
        case .touchDifferentiate:
            InGamePage {
                VStack(spacing: 0) {
                    GalleryPanel(scene: .closedGBA, part: .controls, backdrop: .deck, pressed: [.a, .up, .start],
                                 row: "differentiate-upright")
                    GalleryPanel(scene: .sidewaysGBA, part: .whole, backdrop: .pattern, pressed: Self.allPressed,
                                 row: "differentiate-sideways")
                }
                .environment(\._accessibilityDifferentiateWithoutColor, true)
            }
        case .notices:
            // The picture of the closed GBA with the notice and the chip where
            // OverlayPlacement puts them, over white and the test pattern.
            InGamePage {
                VStack(spacing: 4) {
                    ForEach([PanelBackdrop.white, .pattern], id: \.self) { backdrop in
                        GalleryPanel(scene: .closedGBA, part: .picture, backdrop: backdrop, pressed: [],
                                     row: "notices-\(backdrop.rawValue)", overlays: .notices)
                    }
                }
            }
        case .failure:
            InGamePage {
                MeasuredFailure(message: "Core Failed to Load: the framework mgba_libretro could not be opened.")
            }
        case .gameLandscape:
            InGamePage {
                GeometryReader { proxy in
                    let size = GalleryScene.sidewaysGBA.size
                    let scale = min(proxy.size.width / size.height, proxy.size.height / size.width, 1)
                    GalleryPanel(scene: .sidewaysGBA, part: .whole, backdrop: .pattern, pressed: [], row: "game",
                                 overlays: .all, scalesToFit: false)
                        .frame(width: size.width, height: size.height)
                        .rotationEffect(.degrees(90))
                        .frame(width: size.height, height: size.width)
                        .scaleEffect(scale)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                }
            }
        case .loading:
            InGamePage {
                GalleryPanel(scene: .closedGBA, part: .whole, backdrop: .loading, pressed: [], row: "loading")
            }
        }
    }

    static let notice = "Another game is already running. Quit it before you start this one."
    static let audioProblem = "No audio output: the route could not be opened"

    static let uprightRows: [(name: String, pressed: JoypadButtons)] = [
        ("rest", []), ("a-up", [.a, .up]), ("b-down-right-start", [.b, .down, .right, .start]),
    ]

    static let allPressed: JoypadButtons = [.a, .b, .l, .r, .select, .start, .up]
}

/// A system in a geometry of the Simulator's Duo (docs/wissen/falz.md).
enum GalleryScene {
    /// The closed Duo upright with the GBA, which moves the vertical bar to the top.
    case closedGBA
    /// The closed Duo sideways with the GBA.
    case sidewaysGBA
    /// The DS on the inner display in the tabletop pose.
    case tabletopDS

    var system: GameSystem {
        switch self {
        case .closedGBA, .sidewaysGBA: .gba
        case .tabletopDS: .ds
        }
    }

    var geometry: FoldGeometry {
        switch self {
        case .closedGBA:
            FoldGeometry(container: PixelSize(width: 1398, height: 2034), safeArea: PixelInsets(top: 246, bottom: 102))
        case .sidewaysGBA:
            FoldGeometry(container: PixelSize(width: 2034, height: 1398))
        case .tabletopDS:
            FoldGeometry(container: PixelSize(width: 2007, height: 2853),
                         fold: PixelRect(x: 0, y: 1366, width: 2007, height: 121), isFoldActive: true)
        }
    }

    var layout: GameLayout {
        GameLayout(system: system.screens, geometry: geometry, showsTouchControls: true)
    }

    var size: CGSize {
        geometry.container.points(scale: geometry.scale)
    }

    var controls: TouchLayout {
        GameStage.controls(of: layout, scale: geometry.scale, system: system, shows: true)!
    }
}

/// What lies under the controls of a panel.
enum PanelBackdrop: String, CaseIterable, Hashable {
    case white
    case pattern
    case black
    /// The deck alone, without the screens.
    case deck
    /// The screens before the first picture.
    case loading

    static var allCases: [PanelBackdrop] { [.white, .pattern, .black] }
}

/// A part of a scene as `GameStage` and `GameOverlays` draw it: the backdrop,
/// the deck, the controls in glass with an invisible element per button that
/// carries its frame (`gallery-key-<label>-<row>`, so a UI test can measure
/// the pixels of each button), the pause button and, if asked, the overlays.
/// The part is cut out and scaled down to fit the space offered.
private struct GalleryPanel: View {
    enum Part {
        /// The whole view.
        case whole
        /// From the bottom of the picture, or the fold, to the bottom of the view.
        case controls
        /// The upper or only screen.
        case picture
    }

    enum Overlays {
        case none
        /// The notice and the status chip.
        case notices
        /// The debug overlay too.
        case all
    }

    let scene: GalleryScene
    let part: Part
    let backdrop: PanelBackdrop
    let pressed: JoypadButtons
    let row: String
    var overlays = Overlays.none
    var scalesToFit = true

    @State private var mailbox = PreviewContent.mailboxWithTestPattern()
    @State private var dsMailbox = PreviewContent.mailboxWithDSTestPattern()
    @State private var stats = PresentationStats()
    @Namespace private var transition

    var body: some View {
        let crop = self.crop
        let stage = self.stage
            .frame(width: scene.size.width, height: scene.size.height, alignment: .topLeading)
            .offset(x: -crop.minX, y: -crop.minY)
            .frame(width: crop.width, height: crop.height, alignment: .topLeading)
            .clipped()
        if scalesToFit {
            GeometryReader { proxy in
                let scale = min(proxy.size.width / crop.width, proxy.size.height / crop.height, 1)
                stage
                    .scaleEffect(scale)
                    .frame(width: proxy.size.width, height: proxy.size.height)
            }
        } else {
            stage
        }
    }

    /// The part of the view the panel shows, in points.
    private var crop: CGRect {
        let layout = scene.layout
        let scale = scene.geometry.scale
        let view = CGRect(origin: .zero, size: scene.size)
        switch part {
        case .whole:
            return view
        case .controls:
            let screensBottom = layout.screens.filter { $0.destination.minY < (scene.geometry.fold?.minY ?? .max) }
                .map { $0.destination.points(scale: scale).maxY }.max() ?? 0
            let top = max(screensBottom, scene.geometry.fold.map { $0.points(scale: scale).maxY } ?? 0)
            return CGRect(x: 0, y: top, width: view.width, height: view.height - top)
        case .picture:
            return layout.screens[0].destination.points(scale: scale)
        }
    }

    private var stage: some View {
        let layout = scene.layout
        let geometry = scene.geometry
        let scale = geometry.scale
        let controls = scene.controls
        let screens = layout.screens.map { $0.destination.points(scale: scale) }
        let placement = OverlayPlacement(layout: layout, geometry: geometry, controls: controls)
        return ZStack(alignment: .topLeading) {
            switch backdrop {
            case .white:
                Color.white
            case .black, .deck:
                Color.black
            case .pattern:
                GameScreen(mailbox: scene.system.screens.touchScreen == nil ? mailbox : dsMailbox, stats: stats,
                           arrangement: arrangement(of: layout, scale: scale))
            case .loading:
                ZStack(alignment: .topLeading) {
                    Color.black
                    ForEach(Array(screens.enumerated()), id: \.offset) { index, screen in
                        LoadingBackdrop(isLoading: true, showsProgress: index == 0)
                            .frame(width: screen.width, height: screen.height)
                            .offset(x: screen.minX, y: screen.minY)
                    }
                }
            }
            if [.pattern, .deck, .black].contains(backdrop) {
                ControlDeck(areas: DeckLayout.areas(of: layout, in: geometry).map { $0.points(scale: scale) })
            }
            // The picture alone shows no controls: cut off, they would still
            // be elements of the page for the accessibility audit.
            if backdrop != .loading, part != .picture {
                TouchControlsArt(layout: controls, pressed: pressed, screens: screens,
                                 pause: PauseGlass.drawnByControls(controls, frame: placement.pauseButton, isPressed: false))
                ForEach(controls.buttons) { button in
                    marker(button.label, frame: button.frame)
                }
                marker("Pad", frame: controls.pad.frame)
            }
            if part != .picture, let pause = placement.pauseButton {
                // As in GameStage: the controls draw its glass in their
                // container; while they are hidden the button draws its own.
                PauseButton(transition: transition, diameter: min(pause.width, pause.height),
                            backdrop: GlassBackdrop.under(pause, screens: screens),
                            isDrawnByControls: backdrop != .loading) {}
                    .position(x: pause.midX, y: pause.midY)
            }
            if overlays != .none {
                GameOverlays(
                    placement: placement,
                    debugReadings: overlays == .all ? { GlassGallery.readings } : nil,
                    audioProblem: GlassGallery.audioProblem, notice: GlassGallery.notice,
                    failure: nil, close: {})
            }
        }
    }

    private func arrangement(of layout: GameLayout, scale: Int) -> ScreenArrangement {
        ScreenArrangement(pixelsPerPoint: scale, viewports: layout.screens.map { screen in
            ScreenViewport(
                sourceX: screen.source.x, sourceY: screen.source.y,
                sourceWidth: screen.source.width, sourceHeight: screen.source.height,
                originX: screen.destination.x, originY: screen.destination.y, scale: screen.scale)
        })
    }

    private func marker(_ label: String, frame: CGRect) -> some View {
        Color.clear
            .frame(width: frame.width, height: frame.height)
            .accessibilityElement()
            .accessibilityLabel(Text(verbatim: label))
            .accessibilityIdentifier("gallery-key-\(label)-\(row)")
            .position(x: frame.midX, y: frame.midY)
    }
}

extension GlassGallery {
    /// Fixed measurements for the debug card of the gallery.
    static let readings = DebugReadings(
        emulation: SessionStats.Snapshot(
            framesEmulated: 3584, framesPerSecond: 59.73, lateFrames: 0, resyncs: 0,
            lastRunTime: .microseconds(420), maxRunTime: .microseconds(1100),
            maxLateness: .microseconds(800), periodTrim: -0.00012),
        presentation: PresentationStats.Snapshot(
            displayUpdates: 7200, refreshRate: 120, framesShown: 3583, framesRepeated: 3617,
            framesSkipped: 0, lateSelections: 0, gpuBusy: 0),
        mailbox: MailboxCounters(published: 3584, overwritten: 0),
        audio: AudioCounters(
            underruns: 0, underrunFrames: 0, droppedFrames: 0, primes: 1, renderCalls: 12_000,
            largestRequest: 164, bufferedFrames: 1130, targetFrames: 1147),
        audioSampleRate: 32768,
        route: AudioRoute(hardwareSampleRate: 48000, ioBufferDuration: 0.0053, outputLatency: 0.012),
        input: InputReadings(held: [], lastPressed: .a, presses: 12),
        thermalState: .nominal,
        isLowPowerModeEnabled: false
    )
}

/// The failure message in the geometry the page measures, where
/// `OverlayPlacement` puts it in a game: on one screen, never across the fold.
private struct MeasuredFailure: View {
    let message: String
    @State private var measured: FoldGeometry?
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        // As in GameView: the reader fills the safe area, the message hangs
        // in its background in the coordinates of the whole view.
        Color.clear
            .onFoldGeometryChange(scale: max(1, Int(displayScale.rounded()))) { geometry in
                measured = geometry
            }
            .background(alignment: .topLeading) {
                if let measured {
                    GameFailureView(message: message, area: OverlayPlacement.failureArea(in: measured)) {}
                        .ignoresSafeArea()
                }
            }
    }
}

/// A page that looks like a running game of selftest.gba: dark, without
/// status bar, the vertical bar on top as the GBA has it, so that its
/// picture of 400 pt fits without scaling, with the game's colours and the
/// control surface of the launch arguments.
private struct InGamePage<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .background(Color.black.ignoresSafeArea())
            .statusBarHidden()
            .persistentSystemOverlays(.hidden)
            .modifier(VerticalBarBehavior(isDisabled: GameSystem.gba.disablesVerticalBar))
            .environment(\.gameStyle, GameStyle(GlassGallery.selftest))
            .resolvesControlSurface()
            .preferredColorScheme(.dark)
    }
}

/// Lays `content` out at `size` and scales it down to fit the space offered.
private struct ScaledToFit<Content: View>: View {
    let size: CGSize
    @ViewBuilder let content: Content

    var body: some View {
        GeometryReader { proxy in
            let scale = min(proxy.size.width / size.width, proxy.size.height / size.height, 1)
            content
                .frame(width: size.width, height: size.height)
                .scaleEffect(scale)
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}
#endif
