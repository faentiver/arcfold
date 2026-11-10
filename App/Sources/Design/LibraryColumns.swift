import CoreGraphics
import FoldLayout
import SwiftUI
import UIKit

/// Where the tiles of the library lie across its scroll view, in points from
/// the leading edge of the view. A pure rule, so that every window of the
/// Duo can be tested without one (docs/wissen/oberflaeche.md):
///
/// - The first column begins at the system's margin, where the large title
///   begins, and the last one ends at the margin on the other side.
/// - Spacing, the narrowest tile and the corners follow the width class of
///   the room between the margins, never the device.
/// - From the accessibility sizes on a tile must be wider, by the factor of
///   `tileScale(for:)`, so there are fewer columns; how many still follows
///   the width.
/// - A tile shows its artwork, its name and its system at once: while a row
///   is higher than the scroll view, the grid takes one more column, down
///   to tiles of `narrowestTile`.
/// - A fold that divides the window from top to bottom (the Duo held like a
///   book) divides the grid into two pages, as the system divides its own
///   apps there: the same number of equal columns on each side, from the
///   margin and from the fold on, and no tile on the division region; the
///   pages stay at least one tile distance apart. A
///   fold across the window and an inactive fold divide nothing, as in the
///   system.
nonisolated struct LibraryColumns: Sendable, Equatable {
    /// The room the grid has.
    struct Space: Sendable, Equatable {
        /// The width of the scroll view, inside the safe area.
        var width: CGFloat
        /// The system's margins inside the safe area.
        var margins: SystemMargins
        /// The height of the scroll view inside the safe area: what shows
        /// at once. Nil when it does not limit the tiles.
        var visibleHeight: CGFloat?
        /// An active fold from top to bottom: the division region with its
        /// margins, from the leading edge of the scroll view. Nil when no
        /// fold divides the width.
        var fold: ClosedRange<CGFloat>?

        init(width: CGFloat, margins: SystemMargins = .standard, visibleHeight: CGFloat? = nil,
             fold: ClosedRange<CGFloat>? = nil) {
            self.width = width
            self.margins = margins
            self.visibleHeight = visibleHeight
            self.fold = fold
        }

        /// The room inside the safe area of `geometry`, as the library reads
        /// it with `onFoldGeometryChange(scale:perform:)`.
        init(geometry: FoldGeometry, margins: SystemMargins, isRightToLeft: Bool = false) {
            let scale = CGFloat(max(1, geometry.scale))
            let safe = geometry.safeBounds
            self.init(width: CGFloat(safe.width) / scale, margins: margins, visibleHeight: CGFloat(safe.height) / scale)
            // The book: active, and higher than wide. The geometry counts
            // from the left, the grid from its leading edge.
            if geometry.isFoldActive, let fold = geometry.fold, fold.height > fold.width,
               fold.minX > safe.minX, fold.maxX < safe.maxX {
                let left = CGFloat(fold.minX - safe.minX) / scale
                let right = CGFloat(fold.maxX - safe.minX) / scale
                self.fold = isRightToLeft ? (width - right)...(width - left) : left...right
            }
        }
    }

    /// One column of tiles.
    struct Column: Sendable, Equatable {
        var x: CGFloat
        var width: CGFloat
        var maxX: CGFloat { x + width }
    }

    /// At least one column, from the leading edge on.
    let columns: [Column]
    /// The distance between two rows.
    let rowSpacing: CGFloat
    /// The corner radius of a tile.
    let corner: CGFloat

    /// Width to height of the artwork of a tile, as `GameArtwork` draws it.
    static let artworkAspect: CGFloat = 4 / 3
    /// The space above the first row of the grid.
    static let topPadding: CGFloat = 8
    /// Below this width a tile gets no narrower for the sake of its height.
    static let narrowestTile: CGFloat = 120

    init(space: Space, typeSize: DynamicTypeSize) {
        let pages = Self.pages(in: space)
        // Every page gets the columns that fit into the narrowest one.
        let room = pages.map { $0.upperBound - $0.lowerBound }.min() ?? 1
        let spacing = Metrics.gridSpacing(for: room)
        let minimum = Metrics.tileMinWidth(for: room) * Self.tileScale(for: typeSize)
        var count = Self.count(in: room, minimum: minimum, spacing: spacing.horizontal)
        if let visibleHeight = space.visibleHeight {
            // The artwork may take what the label leaves of the visible height.
            let limit = (visibleHeight - Self.topPadding - Self.labelHeight(for: typeSize)) * Self.artworkAspect
            while Self.tileWidth(in: room, count: count, spacing: spacing.horizontal) > limit,
                  Self.tileWidth(in: room, count: count + 1, spacing: spacing.horizontal) >= Self.narrowestTile {
                count += 1
            }
        }
        let width = Self.tileWidth(in: room, count: count, spacing: spacing.horizontal)
        columns = pages.flatMap { page in
            (0..<count).map { index in
                Column(x: page.lowerBound + CGFloat(index) * (width + spacing.horizontal), width: width)
            }
        }
        rowSpacing = spacing.vertical
        corner = Metrics.tileCorner(for: room)
    }

    /// The parts of the width that take tiles: between the margins, or on
    /// each side of the fold. A side too narrow for a tile stays empty.
    static func pages(in space: Space) -> [ClosedRange<CGFloat>] {
        let start = space.margins.leading
        let end = max(space.width - space.margins.trailing, start + 1)
        guard let fold = space.fold else { return [start...end] }
        // A fold narrower than the distance between two tiles, such as a
        // bare crease, still keeps the tiles that far apart.
        let gutter = max(Metrics.gridSpacing(for: end - start).horizontal - (fold.upperBound - fold.lowerBound), 0) / 2
        let sides = [(start, min(fold.lowerBound - gutter, end)), (max(fold.upperBound + gutter, start), end)]
            .filter { $0.1 - $0.0 >= Self.narrowestTile }
            .map { $0.0...$0.1 }
        return sides.isEmpty ? [start...end] : sides
    }

    /// The columns for `LazyVGrid`: fixed widths, each with the distance to
    /// the next one.
    var gridItems: [GridItem] {
        columns.indices.map { index in
            let column = columns[index]
            let gap = index + 1 < columns.count ? columns[index + 1].x - column.maxX : 0
            return GridItem(.fixed(column.width), spacing: gap, alignment: .top)
        }
    }

    /// How much wider than at the standard sizes a tile must be: the label
    /// grows to more than three times its size, the tile to less than twice,
    /// so that wide windows keep more than one column.
    static func tileScale(for typeSize: DynamicTypeSize) -> CGFloat {
        switch typeSize {
        case .accessibility1: 1.3
        case .accessibility2: 1.45
        case .accessibility3: 1.6
        case .accessibility4: 1.7
        case .accessibility5: 1.8
        default: 1
        }
    }

    /// The height of a tile below its artwork at `typeSize`, with a name of
    /// two lines: the fonts and distances of `GameTile`.
    static func labelHeight(for typeSize: DynamicTypeSize) -> CGFloat {
        let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(typeSize))
        let name = UIFont.preferredFont(forTextStyle: .subheadline, compatibleWith: traits).lineHeight
        let system = UIFont.preferredFont(forTextStyle: .caption1, compatibleWith: traits).lineHeight
        return GameTile.labelSpacing + 2 * name.rounded(.up) + GameTile.lineSpacing + system.rounded(.up)
    }

    /// How many tiles of at least `minimum` fit into `room`, one at least.
    private static func count(in room: CGFloat, minimum: CGFloat, spacing: CGFloat) -> Int {
        max(1, Int(((room + spacing) / (max(minimum, 1) + spacing)).rounded(.down)))
    }

    private static func tileWidth(in room: CGFloat, count: Int, spacing: CGFloat) -> CGFloat {
        (room - CGFloat(count - 1) * spacing) / CGFloat(count)
    }
}
