import FoldLayout
import LibretroKit
import os
import Renderer
import SwiftUI
import UIKit

/// A running game: the screens and touch controls in the layout of the
/// current pose (ADR 0006), the debug overlay and a pause menu. One mechanism
/// for every system: the view measures its geometry and the fold, FoldLayout
/// computes the layout, `GameStage` shows it.
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
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.displayScale) private var displayScale

    /// The margin around the overlays.
    private static let margin: CGFloat = 8
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
                        GameStage(
                            system: session.system, geometry: geometry, layout: layout,
                            mailbox: session.mailbox, stats: session.presentationStats, isPaused: session.isPaused,
                            showsControls: session.phase == .running && showsTouchControls,
                            onButtons: { session.setTouchButtons($0) },
                            onPointer: { session.setTouchPointer($0) },
                            onPause: session.phase == .running ? { session.setUserPaused(true) } : nil
                        )
                        .ignoresSafeArea()
                    }
                }
            overlays
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

    /// The debug overlay's lines wrap before a pause button of its own in
    /// the upper half of the view; with touch controls it sits in their menu.
    private var overlayTrailingPadding: CGFloat {
        guard let geometry, let pause = layout?.pauseButton, pause.minY < geometry.container.height / 2 else { return 0 }
        return max(0, CGFloat(geometry.safeBounds.maxX - pause.minX) / CGFloat(geometry.scale))
    }

    // MARK: Overlays

    @ViewBuilder
    private var overlays: some View {
        VStack(alignment: .leading, spacing: 6) {
            if showsDebugOverlay, !hidesOverlayForScreenshots, session.phase == .running {
                let fold = readings
                DebugOverlay {
                    var values = session.debugReadings()
                    values.fold = fold
                    return values
                }
            }
            if let audioProblem = session.audioProblem {
                Text(audioProblem)
                    .font(.caption2)
                    .foregroundStyle(.yellow)
            }
        }
        .padding(Self.margin)
        // The lines wrap before they reach a pause button in the upper half.
        .padding(.trailing, overlayTrailingPadding)

        if let notice = session.notice {
            Text(notice)
                .font(.footnote)
                .foregroundStyle(.white)
                .padding(8)
                .background(.black.opacity(0.7), in: Capsule())
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 24)
        }

        if session.showsPauseMenu, session.phase == .running {
            pauseMenu
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }

        if session.phase == .loading || (session.phase == .running && session.mailbox == nil) {
            ProgressView()
                .tint(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }

        if case let .failed(message) = session.phase {
            ContentUnavailableView {
                Label {
                    Text("The Game Could Not Start", comment: "Title when a game fails to start.")
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                }
            } description: {
                Text(message)
            } actions: {
                Button {
                    quit()
                } label: {
                    Text("Close", comment: "Button that leaves a game that could not start.")
                }
                .buttonStyle(.borderedProminent)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.black)
        }
    }

    private var pauseMenu: some View {
        VStack(spacing: 12) {
            Text("Paused", comment: "Title of the menu of a paused game.")
                .font(.headline)
            Button {
                session.resumeFromMenu()
            } label: {
                Text("Resume", comment: "Button that continues a paused game.")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("resume")
            Button {
                showsDebugOverlay.toggle()
            } label: {
                Group {
                    if showsDebugOverlay {
                        Text("Hide Debug Overlay", comment: "Button that hides the measurements over the game.")
                    } else {
                        Text("Show Debug Overlay", comment: "Button that shows the measurements over the game.")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            Button(role: .destructive) {
                quit()
            } label: {
                Text("Quit Game", comment: "Button that ends the game and returns to the library.")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("quit")
        }
        .padding(20)
        .frame(maxWidth: 280)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    /// Ends the game: saves, unloads and stops the sound, then brings the
    /// library back.
    private func quit() {
        Task {
            await session.stop()
            onClose()
        }
    }
}
