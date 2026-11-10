import SwiftUI

/// One game in the library: its artwork, its name and its system. Content,
/// so no glass (rule R1) and no context menu yet (that needs the model, M4).
struct GameTile: View {
    let game: Game
    let corner: CGFloat
    /// The height of the artwork, as `LibraryColumns` gives it.
    let artworkHeight: CGFloat

    /// Between the artwork and the name, and between the name and the system.
    nonisolated static let labelSpacing: CGFloat = 6
    nonisolated static let lineSpacing: CGFloat = 2

    var body: some View {
        VStack(alignment: .leading, spacing: Self.labelSpacing) {
            GameArtwork(style: GameStyle(game), variant: .tile(corner: corner, height: artworkHeight))
            VStack(alignment: .leading, spacing: Self.lineSpacing) {
                Text(verbatim: game.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(verbatim: GameSystem.system(id: game.system)?.name ?? game.system)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.leading)
        }
    }
}

/// A small press, as in Music and the App Store: the tile shrinks a little;
/// with Reduce Motion it fades instead.
struct TileButtonStyle: ButtonStyle {
    @Environment(\.prefersFades) private var prefersFades

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !prefersFades ? 0.96 : 1)
            .opacity(configuration.isPressed && prefersFades ? 0.75 : 1)
            .animation(Motion.tilePress, value: configuration.isPressed)
    }
}

/// The grid of tiles, shared by the library and the debug gallery. Where
/// the columns lie follows `LibraryColumns`.
struct GameGrid: View {
    let games: [Game]
    /// The room of the scroll view around the grid.
    let space: LibraryColumns.Space
    let play: (Game) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.prefersFades) private var prefersFades

    var body: some View {
        let layout = LibraryColumns(space: space, typeSize: dynamicTypeSize)
        LazyVGrid(columns: layout.gridItems, alignment: .leading, spacing: layout.rowSpacing) {
            ForEach(games) { game in
                Button {
                    play(game)
                } label: {
                    GameTile(game: game, corner: layout.corner, artworkHeight: layout.artworkHeight)
                        .contentShape(.rect(cornerRadius: layout.corner))
                }
                .buttonStyle(TileButtonStyle())
                .accessibilityHint(Text("Starts the game.", comment: "Accessibility hint of a game tile in the library."))
                // With the system, because a GBA and a DS game may share a name.
                .accessibilityIdentifier("game-\(game.system)-\(game.name)")
                .transition(.scale(scale: 0.85).combined(with: .opacity))
            }
        }
        .padding(.leading, layout.columns[0].x)
        // As wide as the room offered, never as wide as the columns ask:
        // they have fixed widths for the room measured last. A scroll view
        // grows with content that is wider than itself, so when its window
        // got narrower it stayed as wide as the old columns, and the room
        // measured on it never changed (closing the Duo left the columns of
        // the inner display on the outer one).
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .animation(Motion.appear(reduceMotion: prefersFades), value: games.map(\.id))
    }
}

#if DEBUG
#Preview("Grid, outer and inner width") {
    let games = (1...6).map { index in
        Game(id: "\(index)", name: ["Selftest", "Homebrew Demo", "Pixel Quest", "fold_runner", "Arc-Light", "Night Drive"][index - 1],
             system: "gba", originalFileName: "game.gba", size: 1024, importedAt: .now)
    }
    ScrollView {
        GameGrid(games: games, space: .init(width: 382)) { _ in }
            .frame(width: 382)
        Divider()
        GameGrid(games: games, space: .init(width: 669)) { _ in }
            .frame(width: 669)
    }
}
#endif
