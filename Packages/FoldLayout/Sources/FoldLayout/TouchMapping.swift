import CoreGraphics

/// Maps touches in the game view to pixels of an emulated touch screen, the
/// lower DS screen (ADR 0006, section "Touch").
///
/// Source pixel `i` of a screen at scale `k` with origin `x0` covers the view
/// pixels `x0 + i·k ..< x0 + (i + 1)·k`; a touch at `p` points hits pixel
/// `floor((p · scale − x0) / k)`, the same for y. The cells are half open: the
/// first view pixel of a cell belongs to it, its right or lower edge to the
/// next one.
public struct TouchMapping: Sendable, Hashable {
    /// A pixel of the touch screen, `0 ..< source.width` and `0 ..< source.height`.
    public struct Pixel: Sendable, Hashable, CustomStringConvertible {
        public var x: Int
        public var y: Int

        public init(x: Int, y: Int) {
            self.x = x
            self.y = y
        }

        public var description: String { "(\(x), \(y))" }
    }

    /// The touch screen as `GameLayout` placed it.
    public var screen: PlacedScreen
    /// Pixels per point of the view.
    public var scale: Int

    public init(screen: PlacedScreen, scale: Int) {
        self.screen = screen
        self.scale = scale
    }

    /// The pixel under `point` (in points of the view), or nil outside the screen.
    public func pixel(at point: CGPoint) -> Pixel? {
        let x = cell(viewPixel(point.x), origin: screen.destination.x)
        let y = cell(viewPixel(point.y), origin: screen.destination.y)
        guard (0..<screen.source.width).contains(x), (0..<screen.source.height).contains(y) else { return nil }
        return Pixel(x: x, y: y)
    }

    /// The pixel under `point`, or the nearest edge pixel outside the screen:
    /// for a finger that began on the touch screen and slid off it, which
    /// stays at the edge like a stylus.
    public func clampedPixel(at point: CGPoint) -> Pixel {
        let x = cell(viewPixel(point.x), origin: screen.destination.x)
        let y = cell(viewPixel(point.y), origin: screen.destination.y)
        return Pixel(x: min(max(x, 0), max(0, screen.source.width - 1)),
                     y: min(max(y, 0), max(0, screen.source.height - 1)))
    }

    /// The pixel in the core's whole frame: `pixel` moved by the screen's
    /// place in the frame, for example row 192 + y for the lower DS screen.
    public func framePixel(of pixel: Pixel) -> Pixel {
        Pixel(x: screen.source.x + pixel.x, y: screen.source.y + pixel.y)
    }

    /// The centre of `pixel` in points of the view, for tests that tap exactly there.
    public func center(of pixel: Pixel) -> CGPoint {
        let k = CGFloat(screen.scale)
        let s = CGFloat(max(1, scale))
        return CGPoint(x: (CGFloat(screen.destination.x) + (CGFloat(pixel.x) + 0.5) * k) / s,
                       y: (CGFloat(screen.destination.y) + (CGFloat(pixel.y) + 0.5) * k) / s)
    }

    /// The view pixel that holds a coordinate in points. Touches arrive in
    /// points that are fractions like 121.333…, whose product with the scale
    /// can fall a hair below the whole pixel they stand for; a millionth of a
    /// pixel of tolerance keeps them on it. Coordinates far outside any view
    /// are limited, so the conversion to Int cannot trap.
    private func viewPixel(_ coordinate: CGFloat) -> Int {
        let limit: CGFloat = 1e9
        guard !coordinate.isNaN else { return -Int(limit) }
        let pixels = coordinate * CGFloat(max(1, scale)) + 1e-6
        return Int(min(max(pixels, -limit), limit).rounded(.down))
    }

    /// The cell of a view pixel along one axis, rounded towards minus infinity.
    private func cell(_ viewPixel: Int, origin: Int) -> Int {
        let k = max(1, screen.scale)
        let offset = viewPixel - origin
        return offset >= 0 ? offset / k : -((-offset + k - 1) / k)
    }
}
