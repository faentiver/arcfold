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

        init(width: CGFloat, margins: SystemMargins = .standard, visibleHeight: CGFloat? = nil) {
            self.width = width
            self.margins = margins
            self.visibleHeight = visibleHeight
        }

        /// The room inside the safe area of `geometry`, as the library reads
        /// it with `onFoldGeometryChange(scale:perform:)`.
        init(geometry: FoldGeometry, margins: SystemMargins) {
            let scale = CGFloat(max(1, geometry.scale))
            self.init(width: CGFloat(geometry.safeBounds.width) / scale, margins: margins,
                      visibleHeight: CGFloat(geometry.safeBounds.height) / scale)
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
        let start = space.margins.leading
        let room = max(space.width - space.margins.leading - space.margins.trailing, 1)
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
        columns = (0..<count).map { index in
            Column(x: start + CGFloat(index) * (width + spacing.horizontal), width: width)
        }
        rowSpacing = spacing.vertical
        corner = Metrics.tileCorner(for: room)
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
