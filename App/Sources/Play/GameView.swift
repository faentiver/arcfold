import FoldLayout
import LibretroKit
import os
import Renderer
import SwiftUI
import UIKit

/// A running game: the screens and touch controls in the layout of the
/// current pose (ADR 0006), the debug overlay and the pause menu, a system
/// sheet (ADR 0007). One mechanism for every system: the view measures its
/// geometry and the fold, FoldLayout computes the layout, `GameStage` shows it.
///
/// The game ends only through `quit()`: "Quit Game", "Close" after a failed
/// start, or the core asking. The view disappearing does not end it, so that
/// a game whose view leaves the hierarchy while the system moves the scene to
/// the other display goes on when it comes back (ADR 0006, section 9). If the
/// view's state goes away for good, the session stops itself as it is freed.
struct GameView: View {
    /// Brings the library back, after the session stopped.
    let onClose: () -> Void
    @State private var session: PlaySession
    @State private var measured: FoldGeometry?
    @State private var showsDebugOverlay = DebugOverlay.isOnByDefault
    /// The pause sheet grows out of the pause button.
    @Namespace private var pauseTransition
    /// Its own state, not a binding on `showsPauseMenu`: resuming runs through
    /// the session's queue, so right after a swipe the session still reports
    /// a pause and SwiftUI would show the sheet again.
    @State private var isPauseMenuShown = false
    /// Quit closes the sheet first and ends the game in `onDismiss`.
    @State private var isQuitting = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.displayScale) private var displayScale

    private static let logger = Logger(subsystem: "com.faentiver.arcfold", category: "fold")

    init(game: Game, library: GameLibrary, onClose: @escaping () -> Void) {
        self.onClose = onClose
        _session = State(initialValue: PlaySession(
            game: game, files: library.files(for: game), location: library.location))
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Fills the safe area, so that it reads the insets (ADR 0006). The
            // stage hangs in its background: a background takes no part in
            // the size of its view, so the stage, which covers the whole view,
            // cannot grow the view it is measured with (docs/wissen/falz.md).
            Color.clear
                .onFoldGeometryChange(scale: pixelScale) { geometry in
                    measured = geometry
                }
                .background(alignment: .topLeading) {
                    if let geometry, let layout {
                        // The stage and its overlays in pixels of the whole
                        // view; OverlayPlacement places the overlays from the
                        // layout (ADR 0007).
                        ZStack(alignment: .topLeading) {
                            GameStage(
                                system: session.system, geometry: geometry, layout: layout,
                                mailbox: session.mailbox, stats: session.presentationStats, isPaused: session.isPaused,
                                showsControls: showsControls,
                                onButtons: { session.setTouchButtons($0) },
                                onPointer: { session.setTouchPointer($0) },
                                onPause: session.phase == .running ? { session.setUserPaused(true) } : nil,
                                pauseTransition: pauseTransition,
                                isCovered: isPauseMenuShown,
                                isLoading: session.phase == .loading || (session.phase == .running && session.mailbox == nil)
                            )
                            overlays(geometry: geometry, layout: layout)
                        }
                        .ignoresSafeArea()
                    }
                }
        }
        // Game controls keep their places in right-to-left languages too.
        .environment(\.layoutDirection, .leftToRight)
        .background(Color.black.ignoresSafeArea())
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .defersSystemGestures(on: .all)
        .modifier(VerticalBarBehavior(isDisabled: session.system.disablesVerticalBar))
        .onHingeStateChange { old, new in
            #if DEBUG
            DebugRemote.shared.noteHinge(new)
            #endif
            session.hingeChanged(from: old, to: new)
        }
        #if DEBUG
        // A hinge change simulated in the Simulator (DebugRemote).
        .onChange(of: DebugRemote.shared.hingeChange) { _, change in
            if let change {
                session.hingeChanged(from: change.old, to: change.new)
            }
        }
        // A notice or a status chip on request (DebugRemote).
        .onChange(of: DebugRemote.shared.sampleRequest) { _, request in
            if let request {
                session.show(request.sample)
            }
        }
        #endif
        .onChange(of: readings) { _, readings in
            if let readings {
                Self.logger.notice("Layout: \(readings.lines.joined(separator: " | "), privacy: .public)")
            }
        }
        .onAppear {
            // In the log, so that the pose check (Scripts/pose-check.sh) shows
            // whether a pose change rebuilds the view (ADR 0006, section 15).
            Self.logger.notice("Game view appeared, phase \(String(describing: session.phase), privacy: .public)")
            UIApplication.shared.isIdleTimerDisabled = true
            // Starts only once; a view that comes back finds the game running.
            session.start()
        }
        .onDisappear {
            Self.logger.notice("Game view disappeared, phase \(String(describing: session.phase), privacy: .public)")
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .onChange(of: scenePhase) { _, newPhase in
            session.scenePhaseChanged(to: newPhase)
        }
        .onChange(of: session.coreRequestedShutdown) { _, requested in
            if requested {
                quit()
            }
        }
        // The menu opens when the game is paused by hand or the device is
        // closed, also on the outer display, and closes when the session
        // resumes by itself, as when the device opens (ADR 0006, section 10).
        .onChange(of: session.showsPauseMenu && session.phase == .running, initial: true) { _, shows in
            isPauseMenuShown = shows
        }
        .sheet(isPresented: $isPauseMenuShown, onDismiss: {
            if isQuitting {
                quit()
            } else if session.showsPauseMenu {
                // Swiping the sheet away or Escape resumes, like "Resume".
                session.resumeFromMenu()
            }
        }) {
            PauseMenu(gameName: session.game.name, transition: pauseTransition,
                      showsDebugOverlay: $showsDebugOverlay,
                      resume: {
                          session.resumeFromMenu()
                          isPauseMenuShown = false
                      },
                      quit: {
                          isQuitting = true
                          isPauseMenuShown = false
                      })
        }
    }

    // MARK: Layout

    private var pixelScale: Int {
        max(1, Int(displayScale.rounded()))
    }

    /// The measured geometry, or in debug builds the one `-ArcfoldFoldOverride`
    /// or `DebugRemote` asks for. The pause never follows the override;
    /// it follows the hinge.
    private var geometry: FoldGeometry? {
        #if DEBUG
        measured.map { DebugRemote.shared.foldOverride?.applied(to: $0) ?? $0 }
        #else
        measured
        #endif
    }

    private var isOverridden: Bool {
        #if DEBUG
        DebugRemote.shared.foldOverride != nil
        #else
        false
        #endif
    }

    /// A debug build can hide the overlay for a screenshot of the whole
    /// picture (`DebugRemote`).
    private var hidesOverlayForScreenshots: Bool {
        #if DEBUG
        DebugRemote.shared.hidesOverlay
        #else
        false
        #endif
    }

    /// Without touch controls (a controller is in use) the screens grow.
    private var showsTouchControls: Bool {
        session.controllers?.isControllerInUse != true
    }

    private var layout: GameLayout? {
        geometry.map { GameLayout(system: session.system.screens, geometry: $0, showsTouchControls: showsTouchControls) }
    }

    private var readings: FoldReadings? {
        guard let geometry, let layout else { return nil }
        return FoldReadings(geometry: geometry, layout: layout, isOverridden: isOverridden)
    }

    /// The touch controls are drawn and take touches: the game runs and no
    /// controller is in use.
    private var showsControls: Bool {
        session.phase == .running && showsTouchControls
    }

    // MARK: Overlays

    private func overlays(geometry: FoldGeometry, layout: GameLayout) -> some View {
        let controls = GameStage.controls(of: layout, scale: geometry.scale, system: session.system, shows: showsControls)
        let fold = readings
        return GameOverlays(
            placement: OverlayPlacement(layout: layout, geometry: geometry, controls: controls),
            debugReadings: showsDebugOverlay && !hidesOverlayForScreenshots && session.phase == .running ? {
                var values = session.debugReadings()
                values.fold = fold
                return values
            } : nil,
            audioProblem: session.audioProblem,
            notice: session.notice,
            failure: failure,
            close: { quit() })
    }

    private var failure: String? {
        if case let .failed(message) = session.phase { message } else { nil }
    }

    /// Ends the game: saves, unloads and stops the sound, then brings the
    /// library back. An open pause sheet closes first.
    private func quit() {
        guard !isPauseMenuShown else {
            isQuitting = true
            isPauseMenuShown = false
            return
        }
        Task {
            await session.stop()
            onClose()
        }
    }
}
