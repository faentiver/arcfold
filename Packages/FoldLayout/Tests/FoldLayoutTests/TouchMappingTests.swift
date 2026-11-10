import CoreGraphics
import FoldLayout
import Testing

/// Points to pixels of the DS touch screen (ADR 0006, section 6).
struct TouchMappingTests {
    /// The lower DS screen in the core's frame.
    static let source = PixelRect(x: 0, y: 192, width: 256, height: 192)

    static func mapping(scale k: Int, x: Int, y: Int) -> TouchMapping {
        TouchMapping(
            screen: PlacedScreen(source: source, destination: PixelRect(x: x, y: y, width: 256 * k, height: 192 * k), scale: k),
            scale: 3
        )
    }

    /// A point on view pixel (`x`, `y`): its top left corner in points, as
    /// the Simulator delivers touches (whole view pixels, thirds of a point).
    static func corner(_ x: Int, _ y: Int) -> CGPoint {
        CGPoint(x: CGFloat(x) / 3, y: CGFloat(y) / 3)
    }

    /// The origins: one of the closed Duo (61, 768) and some that are no
    /// multiple of 3, so cells start at thirds of a point.
    static let origins = [(0, 0), (61, 768), (363, 1446), (364, 1447), (365, 1448)]

    /// Every one of the 49 152 pixel centres maps back to its pixel, at every
    /// scale the layouts use.
    @Test(arguments: 1...7)
    func everyPixelCentreRoundTrips(k: Int) {
        for (x, y) in Self.origins {
            let mapping = Self.mapping(scale: k, x: x, y: y)
            var misses = 0
            var first: String?
            for row in 0..<192 {
                for column in 0..<256 {
                    let pixel = TouchMapping.Pixel(x: column, y: row)
                    let mapped = mapping.pixel(at: mapping.center(of: pixel))
                    if mapped != pixel {
                        misses += 1
                        first = first ?? "\(pixel) → \(String(describing: mapped))"
                    }
                }
            }
            #expect(misses == 0, "scale \(k), origin (\(x), \(y)): \(misses) misses, first \(first ?? "-")")
        }
    }

    /// Every view pixel of the screen, given as its top left corner in
    /// points, lands in the cell that holds it: the first and the last view
    /// pixel of a cell belong to it, the next one to the next cell.
    @Test(arguments: [1, 2, 3, 4, 5, 6, 7])
    func everyViewPixelLandsInItsCell(k: Int) {
        for (x0, y0) in Self.origins {
            let mapping = Self.mapping(scale: k, x: x0, y: y0)
            var misses = 0
            // Diagonal and one row and one column through all cells.
            for offset in 0..<(192 * k) {
                for (vx, vy) in [(x0 + offset, y0 + offset), (x0 + offset * 256 / 192, y0 + 5), (x0 + 7, y0 + offset)] {
                    let expected = TouchMapping.Pixel(x: (vx - x0) / k, y: (vy - y0) / k)
                    if mapping.pixel(at: Self.corner(vx, vy)) != expected {
                        misses += 1
                    }
                }
            }
            #expect(misses == 0, "scale \(k), origin (\(x0), \(y0))")
        }
    }

    @Test(arguments: [3, 4, 5, 7])
    func edgesAndCorners(k: Int) {
        let (x0, y0) = (364, 1447)
        let mapping = Self.mapping(scale: k, x: x0, y: y0)
        #expect(mapping.pixel(at: Self.corner(x0, y0)) == .init(x: 0, y: 0))
        #expect(mapping.pixel(at: Self.corner(x0 + k - 1, y0 + k - 1)) == .init(x: 0, y: 0))
        #expect(mapping.pixel(at: Self.corner(x0 + k, y0 + k)) == .init(x: 1, y: 1))
        #expect(mapping.pixel(at: Self.corner(x0 + 256 * k - 1, y0)) == .init(x: 255, y: 0))
        #expect(mapping.pixel(at: Self.corner(x0, y0 + 192 * k - 1)) == .init(x: 0, y: 191))
        #expect(mapping.pixel(at: Self.corner(x0 + 256 * k - 1, y0 + 192 * k - 1)) == .init(x: 255, y: 191))
        // Half open: one view pixel outside is no pixel.
        #expect(mapping.pixel(at: Self.corner(x0 - 1, y0)) == nil)
        #expect(mapping.pixel(at: Self.corner(x0, y0 - 1)) == nil)
        #expect(mapping.pixel(at: Self.corner(x0 + 256 * k, y0)) == nil)
        #expect(mapping.pixel(at: Self.corner(x0, y0 + 192 * k)) == nil)
        // A hair left of an edge in points is the cell before it.
        #expect(mapping.pixel(at: CGPoint(x: CGFloat(x0 + k) / 3 - 0.001, y: CGFloat(y0) / 3)) == .init(x: 0, y: 0))
    }

    @Test func aFingerThatSlidesOffStaysAtTheEdge() {
        let mapping = Self.mapping(scale: 4, x: 61, y: 768)
        #expect(mapping.clampedPixel(at: CGPoint(x: -50, y: -50)) == .init(x: 0, y: 0))
        #expect(mapping.clampedPixel(at: CGPoint(x: 5000, y: 5000)) == .init(x: 255, y: 191))
        #expect(mapping.clampedPixel(at: Self.corner(60, 768 + 5 * 4)) == .init(x: 0, y: 5))
        #expect(mapping.clampedPixel(at: Self.corner(61 + 1024, 768 + 5 * 4 + 3)) == .init(x: 255, y: 5))
        #expect(mapping.clampedPixel(at: Self.corner(61 + 10 * 4, 767)) == .init(x: 10, y: 0))
        #expect(mapping.clampedPixel(at: Self.corner(61 + 10 * 4, 768 + 768)) == .init(x: 10, y: 191))
        // Inside, it is the plain pixel.
        #expect(mapping.clampedPixel(at: Self.corner(61 + 100 * 4 + 3, 768 + 50 * 4)) == .init(x: 100, y: 50))
        #expect(mapping.clampedPixel(at: CGPoint(x: CGFloat.nan, y: .infinity)) == .init(x: 0, y: 191))
        #expect(mapping.pixel(at: CGPoint(x: CGFloat.nan, y: 300)) == nil)
    }

    /// The lower screen starts in row 192 of the core's frame.
    @Test func framePixelsOfTheLowerScreen() {
        let mapping = Self.mapping(scale: 4, x: 61, y: 768)
        #expect(mapping.framePixel(of: .init(x: 0, y: 0)) == .init(x: 0, y: 192))
        #expect(mapping.framePixel(of: .init(x: 255, y: 191)) == .init(x: 255, y: 383))
        #expect(SystemScreens.ds.frameSize == PixelSize(width: 256, height: 384))
        #expect(SystemScreens.gba.frameSize == PixelSize(width: 240, height: 160))
    }

    @Test func centresInPoints() {
        let mapping = Self.mapping(scale: 4, x: 61, y: 768)
        #expect(mapping.center(of: .init(x: 0, y: 0)) == CGPoint(x: 63.0 / 3, y: 770.0 / 3))
        #expect(mapping.center(of: .init(x: 255, y: 191)) == CGPoint(x: (61 + 1020 + 2) / 3.0, y: (768 + 764 + 2) / 3.0))
    }
}
