import CoreGraphics
import FoldLayout
import SwiftUI

/// Where the tiles of the library lie across its scroll view, in points from
/// the leading edge of the view. A pure rule, so that every window of the
/// Duo can be tested without one (docs/wissen/oberflaeche.md):
///
/// - The first column begins at the system's margin, where the large title
///   begins, and the last one ends at the margin on the other side.
/// - Spacing, the narrowest tile and the corners follow the width class of
///   the room between the margins, never the device.
nonisolated struct LibraryColumns: Sendable, Equatable {
    /// The room the grid has.
    struct Space: Sendable, Equatable {
        /// The width of the scroll view, inside the safe area.
        var width: CGFloat
        /// The system's margins inside the safe area.
        var margins: SystemMargins

        init(width: CGFloat, margins: SystemMargins = .standard) {
            self.width = width
            self.margins = margins
        }

        /// The room inside the safe area of `geometry`, as the library reads
        /// it with `onFoldGeometryChange(scale:perform:)`.
        init(geometry: FoldGeometry, margins: SystemMargins) {
            let scale = CGFloat(max(1, geometry.scale))
            self.init(width: CGFloat(geometry.safeBounds.width) / scale, margins: margins)
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

    init(space: Space, typeSize: DynamicTypeSize) {
        let start = space.margins.leading
        let room = max(space.width - space.margins.leading - space.margins.trailing, 1)
        let spacing = Metrics.gridSpacing(for: room)
        // From the accessibility sizes on, one tile per row.
        let minimum = typeSize.isAccessibilitySize ? room : Metrics.tileMinWidth(for: room)
        let count = Self.count(in: room, minimum: minimum, spacing: spacing.horizontal)
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

    /// How many tiles of at least `minimum` fit into `room`, one at least.
    private static func count(in room: CGFloat, minimum: CGFloat, spacing: CGFloat) -> Int {
        max(1, Int(((room + spacing) / (max(minimum, 1) + spacing)).rounded(.down)))
    }

    private static func tileWidth(in room: CGFloat, count: Int, spacing: CGFloat) -> CGFloat {
        (room - CGFloat(count - 1) * spacing) / CGFloat(count)
    }
}
