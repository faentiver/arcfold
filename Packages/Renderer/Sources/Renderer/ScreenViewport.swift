/// One emulated screen in the drawable of `GameScreen` (ADR 0006): a rectangle
/// of the core's frame, drawn at a whole-number scale with its top left corner
/// at the origin. All values are pixels.
///
/// The two DS screens are two viewports into the same uploaded frame
/// (256 × 384, upper screen in rows 0-191, lower in rows 192-383): one upload
/// per emulated frame, one Metal view, one display link.
public struct ScreenViewport: Sendable, Hashable {
    /// Where the screen lies in the core's frame.
    public var sourceX: Int
    public var sourceY: Int
    public var sourceWidth: Int
    public var sourceHeight: Int
    /// The top left corner of the scaled screen in the drawable.
    public var originX: Int
    public var originY: Int
    /// The whole-number scale, at least 1.
    public var scale: Int

    public init(
        sourceX: Int, sourceY: Int, sourceWidth: Int, sourceHeight: Int,
        originX: Int, originY: Int, scale: Int
    ) {
        self.sourceX = sourceX
        self.sourceY = sourceY
        self.sourceWidth = sourceWidth
        self.sourceHeight = sourceHeight
        self.originX = originX
        self.originY = originY
        self.scale = scale
    }

    /// The size of the scaled screen in the drawable.
    public var width: Int { sourceWidth * scale }
    public var height: Int { sourceHeight * scale }
}

/// Where the screens of each frame go in the drawable of `GameScreen`. The
/// drawable has `pixelsPerPoint` pixels per point of the view, the same scale
/// FoldLayout computed the viewports with, so that both agree on every pixel.
public struct ScreenArrangement: Sendable, Hashable {
    public var pixelsPerPoint: Int
    /// Drawn in this order; the rest of the drawable is black.
    public var viewports: [ScreenViewport]

    public init(pixelsPerPoint: Int, viewports: [ScreenViewport]) {
        self.pixelsPerPoint = pixelsPerPoint
        self.viewports = viewports
    }
}
