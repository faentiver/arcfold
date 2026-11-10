import SwiftUI

/// One game in the library: its artwork, its name and its system. Content,
/// so no glass (rule R1) and no context menu yet (that needs the model, M4).
struct GameTile: View {
    let game: Game
    let corner: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GameArtwork(style: GameStyle(game), variant: .tile(corner: corner))
            VStack(alignment: .leading, spacing: 2) {
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

/// The grid of tiles, shared by the library and the debug gallery. Columns,
/// spacing and corners follow the width class of the grid, never the device.
struct GameGrid: View {
    let games: [Game]
    let width: CGFloat
    /// The width with the system column of the outer display, when it is
    /// wider than the grid. The margin follows its width class, as the large
    /// title does, so the grid lines up with the title: 20 pt beside the
    /// column, not 16 for the 382 pt of the grid.
    var windowWidth: CGFloat?
    let play: (Game) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.prefersFades) private var prefersFades

    var body: some View {
        let margin = Metrics.margin(for: max(windowWidth ?? 0, width))
        let spacing = Metrics.gridSpacing(for: width)
        let corner = Metrics.tileCorner(for: width)
        // From the accessibility sizes on, one tile per row.
        let minimum = dynamicTypeSize.isAccessibilitySize
            ? max(width - 2 * margin, 1)
            : Metrics.tileMinWidth(for: width)
        LazyVGrid(columns: [GridItem(.adaptive(minimum: minimum), spacing: spacing.horizontal, alignment: .top)],
                  alignment: .leading, spacing: spacing.vertical) {
            ForEach(games) { game in
                Button {
                    play(game)
                } label: {
                    GameTile(game: game, corner: corner)
                        .contentShape(.rect(cornerRadius: corner))
                }
                .buttonStyle(TileButtonStyle())
                .accessibilityHint(Text("Starts the game.", comment: "Accessibility hint of a game tile in the library."))
                // With the system, because a GBA and a DS game may share a name.
                .accessibilityIdentifier("game-\(game.system)-\(game.name)")
                .transition(.scale(scale: 0.85).combined(with: .opacity))
            }
        }
        .padding(.horizontal, margin)
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
        GameGrid(games: games, width: 382) { _ in }
            .frame(width: 382)
        Divider()
        GameGrid(games: games, width: 669) { _ in }
            .frame(width: 669)
    }
}
#endif
