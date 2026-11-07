import LibretroKit
import Renderer
import SwiftUI
import UIKit

/// A running game: the picture, the touch controls, the debug overlay and a
/// pause menu. Upright the picture sits at the top with the controls below it,
/// sideways it is centred with the controls at the sides. The fold layouts
/// follow in M2.
struct GameView: View {
    @State private var session: PlaySession
    @State private var showsDebugOverlay = DebugOverlay.isOnByDefault
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss

    /// The pause button at the top trailing corner, and the margin around it.
    private static let pauseButtonSize: CGFloat = 44
    private static let margin: CGFloat = 8

    init(game: Game, library: GameLibrary) {
        _session = State(initialValue: PlaySession(
            game: game, files: library.files(for: game), location: library.location))
    }

    var body: some View {
        GeometryReader { proxy in
            let isLandscape = proxy.size.width > proxy.size.height
            ZStack(alignment: .topLeading) {
                if isLandscape {
                    screen
                        .frame(width: proxy.size.width, height: proxy.size.height)
                    controls(isLandscape: true)
                } else {
                    VStack(spacing: 0) {
                        screen
                            .frame(width: proxy.size.width, height: proxy.size.width / aspectRatio)
                        controls(isLandscape: false)
                    }
                }
                overlays
            }
        }
        .background(Color.black.ignoresSafeArea())
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .defersSystemGestures(on: .all)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            session.start()
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            Task { await session.stop() }
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

    private var aspectRatio: CGFloat {
        CGFloat(session.info?.geometry.aspectRatio ?? 1.5)
    }

    @ViewBuilder
    private var screen: some View {
        if let mailbox = session.mailbox {
            GameScreen(mailbox: mailbox, stats: session.presentationStats, isPaused: session.isPaused)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Game picture", comment: "Accessibility label of the emulated picture."))
                .accessibilityIdentifier("game-screen")
        } else {
            Color.black
                .overlay {
                    if session.phase == .loading {
                        ProgressView()
                            .tint(.white)
                    }
                }
        }
    }

    @ViewBuilder
    private func controls(isLandscape: Bool) -> some View {
        if session.phase == .running, session.controllers?.isControllerInUse != true {
            TouchControls(isLandscape: isLandscape) { buttons in
                session.setTouchButtons(buttons)
            }
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private var overlays: some View {
        VStack(alignment: .leading, spacing: 6) {
            if showsDebugOverlay, session.phase == .running {
                DebugOverlay { session.debugReadings() }
            }
            if let audioProblem = session.audioProblem {
                Text(audioProblem)
                    .font(.caption2)
                    .foregroundStyle(.yellow)
            }
        }
        .padding(Self.margin)
        // The lines wrap before they reach the pause button.
        .padding(.trailing, Self.pauseButtonSize + Self.margin)

        if session.phase == .running {
            Button {
                session.setUserPaused(true)
            } label: {
                Image(systemName: "pause.fill")
                    .font(.title3)
                    .frame(width: Self.pauseButtonSize, height: Self.pauseButtonSize)
            }
            .tint(.white)
            .accessibilityLabel(Text("Pause", comment: "Button that pauses the game and opens its menu."))
            .accessibilityIdentifier("pause")
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .padding(Self.margin)
        }

        if let notice = session.notice {
            Text(notice)
                .font(.footnote)
                .foregroundStyle(.white)
                .padding(8)
                .background(.black.opacity(0.7), in: Capsule())
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 24)
        }

        if session.isUserPaused, session.phase == .running {
            pauseMenu
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
                    dismiss()
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
                session.setUserPaused(false)
            } label: {
                Text("Resume", comment: "Button that continues a paused game.")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
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
        }
        .padding(20)
        .frame(maxWidth: 280)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func quit() {
        Task {
            await session.stop()
            dismiss()
        }
    }
}
