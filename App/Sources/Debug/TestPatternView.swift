#if DEBUG
import FoldLayout
import LibretroKit
import Renderer
import SwiftUI

/// The game screen with a test pattern instead of a core, for checking the
/// picture path (mailbox, display link, shader) in the Simulator. Opened by
/// the launch argument `-ArcfoldTestPattern YES` in debug builds; a double
/// tap closes it.
struct TestPatternView: View {
    /// Brings the library back.
    let onClose: () -> Void
    @State private var mailbox = PreviewContent.mailboxWithTestPattern()
    @State private var stats = PresentationStats()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                let snapshot = stats.snapshot()
                Text(verbatim: "Test pattern · \(Int(snapshot.refreshRate.rounded())) Hz · shown \(snapshot.framesShown)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.white)
                    .padding(8)
                    .accessibilityIdentifier("test-pattern-stats")
            }
            GameScreen(mailbox: mailbox, stats: stats)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: "Test pattern"))
                .accessibilityIdentifier("test-pattern-screen")
        }
        .background(Color.black.ignoresSafeArea())
        .statusBarHidden()
        .onTapGesture(count: 2) {
            onClose()
        }
    }
}

/// The game view of a system with a test pattern instead of a core, in the
/// layout of the current pose (ADR 0006, section 15): the same stage, touch
/// controls and debug overlay as a running game, for checking the layouts in
/// the Simulator. Opened by `-ArcfoldTestPattern ds` or `gba` in debug builds.
/// Touches go into an `InputState` of its own, which the overlay shows.
struct LayoutTestPatternView: View {
    let system: GameSystem
    @State private var mailbox: FrameMailbox
    @State private var stats = PresentationStats()
    @State private var input = InputState()
    @State private var measured: FoldGeometry?
    @Environment(\.displayScale) private var displayScale

    init(system: GameSystem) {
        self.system = system
        _mailbox = State(initialValue: system.screens.touchScreen == nil
            ? PreviewContent.mailboxWithTestPattern() : PreviewContent.mailboxWithDSTestPattern())
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // As in GameView: the stage in the background of the reader.
            Color.clear
                .onFoldGeometryChange(scale: max(1, Int(displayScale.rounded()))) { geometry in
                    measured = geometry
                }
                .background(alignment: .topLeading) {
                    if let geometry, let layout {
                        GameStage(
                            system: system, geometry: geometry, layout: layout, mailbox: mailbox, stats: stats,
                            isPaused: false, showsControls: true,
                            onButtons: { input.set($0, from: .touch) },
                            onPointer: { input.setPointer($0) },
                            onPause: nil
                        )
                        .ignoresSafeArea()
                    }
                }
            DebugOverlay { readings }
                .padding(8)
        }
        .environment(\.layoutDirection, .leftToRight)
        .background(Color.black.ignoresSafeArea())
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .defersSystemGestures(on: .all)
        .modifier(VerticalBarBehavior(isDisabled: system.disablesVerticalBar))
    }

    private var geometry: FoldGeometry? {
        measured.map { DebugRemote.shared.foldOverride?.applied(to: $0) ?? $0 }
    }

    private var layout: GameLayout? {
        geometry.map { GameLayout(system: system.screens, geometry: $0, showsTouchControls: true) }
    }

    private var readings: DebugReadings {
        DebugReadings(
            emulation: nil,
            presentation: stats.snapshot(),
            mailbox: mailbox.counters,
            audio: AudioCounters(underruns: 0, underrunFrames: 0, droppedFrames: 0, primes: 0, renderCalls: 0,
                                 largestRequest: 0, bufferedFrames: 0, targetFrames: 0),
            audioSampleRate: 0,
            route: nil,
            input: InputReadings(input),
            pointer: system.screens.touchScreen.map {
                PointerReadings(input, frameSize: system.screens.frameSize, touchScreen: system.screens.sources[$0])
            },
            thermalState: ProcessInfo.processInfo.thermalState,
            isLowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled,
            fold: foldReadings
        )
    }

    private var foldReadings: FoldReadings? {
        guard let geometry, let layout else { return nil }
        return FoldReadings(geometry: geometry, layout: layout, isOverridden: DebugRemote.shared.foldOverride != nil)
    }
}
#endif
