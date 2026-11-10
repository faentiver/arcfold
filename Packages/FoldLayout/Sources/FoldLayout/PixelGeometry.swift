// FoldLayout turns the place of the game view on the device (size, safe area,
// the fold) into the rectangles for the screens and the touch controls of each
// system (docs/PLAN.md, sections 5 and 7; ADR 0006). Everything is in pixels of
// the view and every screen is scaled by a whole number, so pixels stay sharp.

import CoreGraphics

/// A size in pixels.
public struct PixelSize: Sendable, Hashable, CustomStringConvertible {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    /// Wider than high.
    public var isLandscape: Bool { width > height }

    public var description: String { "\(width)×\(height)" }
}

/// A rectangle in pixels, origin at the top left. Half open: it covers
/// `x ..< x + width` and `y ..< y + height`.
public struct PixelRect: Sendable, Hashable, CustomStringConvertible {
    public var x: Int
    public var y: Int
    public var width: Int
    public var height: Int

    public init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public static let zero = PixelRect(x: 0, y: 0, width: 0, height: 0)

    public var minX: Int { x }
    public var minY: Int { y }
    public var maxX: Int { x + width }
    public var maxY: Int { y + height }
    public var size: PixelSize { PixelSize(width: width, height: height) }
    public var isEmpty: Bool { width <= 0 || height <= 0 }

    /// Smaller by the insets on each side, never below zero.
    public func inset(by insets: PixelInsets) -> PixelRect {
        PixelRect(
            x: x + insets.left, y: y + insets.top,
            width: max(0, width - insets.left - insets.right),
            height: max(0, height - insets.top - insets.bottom)
        )
    }

    /// Whether `other` lies completely inside.
    public func contains(_ other: PixelRect) -> Bool {
        other.minX >= minX && other.maxX <= maxX && other.minY >= minY && other.maxY <= maxY
    }

    /// Whether the two share at least one pixel.
    public func intersects(_ other: PixelRect) -> Bool {
        !isEmpty && !other.isEmpty && other.minX < maxX && other.maxX > minX && other.minY < maxY && other.maxY > minY
    }

    /// The part that both share; empty (at the origin of `self`) when they
    /// share no pixel.
    public func intersection(_ other: PixelRect) -> PixelRect {
        let left = max(minX, other.minX)
        let top = max(minY, other.minY)
        let right = min(maxX, other.maxX)
        let bottom = min(maxY, other.maxY)
        guard right > left, bottom > top else { return PixelRect(x: x, y: y, width: 0, height: 0) }
        return PixelRect(x: left, y: top, width: right - left, height: bottom - top)
    }

    /// The same rectangle in points at `scale` pixels per point.
    public func points(scale: Int) -> CGRect {
        let s = CGFloat(scale)
        return CGRect(x: CGFloat(x) / s, y: CGFloat(y) / s, width: CGFloat(width) / s, height: CGFloat(height) / s)
    }

    /// The smallest pixel rectangle that covers `rect`, given in points.
    public static func covering(_ rect: CGRect, scale: Int) -> PixelRect {
        let s = CGFloat(scale)
        let minX = Int((rect.minX * s).rounded(.down))
        let minY = Int((rect.minY * s).rounded(.down))
        let maxX = Int((rect.maxX * s).rounded(.up))
        let maxY = Int((rect.maxY * s).rounded(.up))
        return PixelRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    public var description: String { "(\(x), \(y), \(width)×\(height))" }
}

// Cutting helpers for the templates of GameLayout. Each keeps the result inside
// the rectangle and never makes it negative.
extension PixelRect {
    /// Smaller by the given pixels on each side.
    func inset(top: Int = 0, left: Int = 0, bottom: Int = 0, right: Int = 0) -> PixelRect {
        inset(by: PixelInsets(top: top, left: left, bottom: bottom, right: right))
    }

    /// Smaller by `amount` on every side.
    func inset(all amount: Int) -> PixelRect {
        inset(top: amount, left: amount, bottom: amount, right: amount)
    }

    /// The rows above `limit`.
    func above(_ limit: Int) -> PixelRect {
        PixelRect(x: x, y: y, width: width, height: max(0, min(maxY, limit) - y))
    }

    /// The rows from `limit` downwards.
    func below(_ limit: Int) -> PixelRect {
        let top = min(max(y, limit), maxY)
        return PixelRect(x: x, y: top, width: width, height: maxY - top)
    }

    /// The columns left of `limit`.
    func left(of limit: Int) -> PixelRect {
        PixelRect(x: x, y: y, width: max(0, min(maxX, limit) - x), height: height)
    }

    /// The columns from `limit` rightwards.
    func right(of limit: Int) -> PixelRect {
        let left = min(max(x, limit), maxX)
        return PixelRect(x: left, y: y, width: maxX - left, height: height)
    }

    /// The largest of the four parts beside `obstacle` (left, right, above,
    /// below), or `self` when the two share no pixel.
    func avoiding(_ obstacle: PixelRect) -> PixelRect {
        guard intersects(obstacle) else { return self }
        let parts = [left(of: obstacle.minX), right(of: obstacle.maxX), above(obstacle.minY), below(obstacle.maxY)]
        return parts.max { $0.area < $1.area } ?? PixelRect(x: x, y: y, width: 0, height: 0)
    }

    var area: Int { isEmpty ? 0 : width * height }
}

/// Insets in pixels.
public struct PixelInsets: Sendable, Hashable, CustomStringConvertible {
    public var top: Int
    public var left: Int
    public var bottom: Int
    public var right: Int

    public init(top: Int = 0, left: Int = 0, bottom: Int = 0, right: Int = 0) {
        self.top = top
        self.left = left
        self.bottom = bottom
        self.right = right
    }

    public static let zero = PixelInsets()

    /// Insets given in points, rounded up to whole pixels, so that content
    /// never reaches into them.
    public static func covering(top: CGFloat, left: CGFloat, bottom: CGFloat, right: CGFloat, scale: Int) -> PixelInsets {
        let s = CGFloat(scale)
        func pixels(_ value: CGFloat) -> Int { Int((value * s).rounded(.up)) }
        return PixelInsets(top: pixels(top), left: pixels(left), bottom: pixels(bottom), right: pixels(right))
    }

    public var description: String { "t\(top) l\(left) b\(bottom) r\(right)" }
}
