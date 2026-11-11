import SwiftUI

/// What fills the window: the library, or in its place a running game.
///
/// A game replaces the library instead of covering it with a full-screen
/// cover. Under a cover the library's navigation stack stays in the window,
/// and in the Duo Simulator (iOS 27.1) one touch at the top edge of the outer
/// display then sends every later touch in the top 60 to 70 pt to the
/// library's navigation bar instead of the game, as long as the game runs
/// (ADR 0006, section "Nachbesserungen nach der Prüfung"; docs/wissen/falz.md).
struct RootView: View {
    /// What the window shows.
    enum Stage: Hashable {
        case library
        case game(Game)
        #if DEBUG
        /// The game screen with the test pattern of M1 (`-ArcfoldTestPattern YES`).
        case testPattern
        /// The game view of a system with a test pattern (`-ArcfoldTestPattern ds|gba`).
        case layoutTestPattern(systemID: String)
        #endif
    }

    @Environment(GameLibrary.self) private var library
    @State private var stage = Stage.library

    var body: some View {
        switch stage {
        case .library:
            LibraryView { stage = $0 }
        case let .game(game):
            // A new game gets a view of its own, and with it a session of its own.
            GameView(game: game, library: library) { stage = .library }
                .id(game.id)
                // The game's colours for the artwork and the pause sheet,
                // the console of its system, and glass or flat for controls
                // over a screen (ADR 0007).
                .environment(\.gameStyle, GameStyle(game))
                .environment(\.consoleSkin, ConsoleSkin.skin(forSystem: game.system, preferred: ConsoleSkin.preferredFinish))
                .resolvesControlSurface()
                // A game is always dark; the pause sheet inherits it.
                .preferredColorScheme(.dark)
        #if DEBUG
        case .testPattern:
            TestPatternView { stage = .library }
        case let .layoutTestPattern(systemID):
            if let system = GameSystem.system(id: systemID) {
                LayoutTestPatternView(system: system)
                    .environment(\.consoleSkin, ConsoleSkin.skin(forSystem: system.id, preferred: ConsoleSkin.preferredFinish))
            }
        #endif
        }
    }
}
