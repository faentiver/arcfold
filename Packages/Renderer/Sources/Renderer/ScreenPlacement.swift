/// Where a picture lands in a drawable: scaled by a whole number so that
/// pixels stay sharp, and centred. All values are drawable pixels.
public struct ScreenPlacement: Sendable, Hashable {
    /// The scale factor, at least 1.
    public var scale: Int
    /// The top left corner of the picture.
    public var originX: Int
    public var originY: Int
    /// The size of the scaled picture.
    public var width: Int
    public var height: Int

    public init(scale: Int, originX: Int, originY: Int, width: Int, height: Int) {
        self.scale = scale
        self.originX = originX
        self.originY = originY
        self.width = width
        self.height = height
    }

    /// The largest whole-number scale of the source that fits the drawable,
    /// centred on whole pixels; scale 1 if the source is larger than the drawable.
    /// For example 240 x 160 in 1878 x 2670 gives scale 7 at (99, 775).
    public static func fitting(
        sourceWidth: Int, sourceHeight: Int, drawableWidth: Int, drawableHeight: Int
    ) -> ScreenPlacement {
        fatalError("M1 track A")
    }
}
