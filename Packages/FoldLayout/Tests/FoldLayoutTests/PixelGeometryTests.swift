import CoreGraphics
@testable import FoldLayout
import Testing

/// The pixel values everything in FoldLayout is built on.
struct PixelGeometryTests {
    @Test func rectanglesAreHalfOpen() {
        let left = PixelRect(x: 0, y: 0, width: 10, height: 10)
        let right = PixelRect(x: 10, y: 0, width: 10, height: 10)
        #expect(!left.intersects(right))
        #expect(left.intersects(PixelRect(x: 9, y: 9, width: 1, height: 1)))
        #expect(PixelRect(x: 0, y: 0, width: 20, height: 10).contains(right))
        #expect(!left.contains(right))
        #expect(!PixelRect.zero.intersects(left))
    }

    @Test func insetsNeverMakeARectangleNegative() {
        let rect = PixelRect(x: 0, y: 0, width: 1398, height: 2034)
        // The outer display of the Duo Simulator with its vertical bar: 84 pt
        // on the right, 34 pt at the bottom leave 382 × 644 pt.
        let safe = rect.inset(by: PixelInsets.covering(top: 0, left: 0, bottom: 34, right: 84, scale: 3))
        #expect(safe == PixelRect(x: 0, y: 0, width: 1146, height: 1932))
        #expect(rect.inset(by: PixelInsets(left: 2000)).width == 0)
    }

    @Test func pointsAndPixelsConvertOnWholePixels() {
        let rect = PixelRect(x: 93, y: 0, width: 960, height: 640)
        #expect(rect.points(scale: 3) == CGRect(x: 31, y: 0, width: 320, height: 640.0 / 3))
        // A rectangle in points covers every pixel it touches.
        #expect(PixelRect.covering(CGRect(x: 0.2, y: 1, width: 10, height: 0.5), scale: 3)
            == PixelRect(x: 0, y: 3, width: 31, height: 2))
    }

    @Test func cuttingKeepsInsideAndNeverGoesNegative() {
        let rect = PixelRect(x: 10, y: 20, width: 100, height: 50)
        #expect(rect.above(30) == PixelRect(x: 10, y: 20, width: 100, height: 10))
        #expect(rect.above(0).height == 0)
        #expect(rect.above(500) == rect)
        #expect(rect.below(30) == PixelRect(x: 10, y: 30, width: 100, height: 40))
        #expect(rect.below(500).height == 0)
        #expect(rect.below(0) == rect)
        #expect(rect.left(of: 60) == PixelRect(x: 10, y: 20, width: 50, height: 50))
        #expect(rect.right(of: 60) == PixelRect(x: 60, y: 20, width: 50, height: 50))
        #expect(rect.right(of: 500).width == 0)
        #expect(rect.inset(all: 5) == PixelRect(x: 15, y: 25, width: 90, height: 40))
        #expect(rect.intersection(PixelRect(x: 100, y: 0, width: 50, height: 30)) == PixelRect(x: 100, y: 20, width: 10, height: 10))
        #expect(rect.intersection(PixelRect(x: 200, y: 0, width: 5, height: 5)).isEmpty)
    }

    @Test func avoidingKeepsTheLargestPartBesideAnObstacle() {
        let zone = PixelRect(x: 0, y: 0, width: 100, height: 100)
        #expect(zone.avoiding(PixelRect(x: 200, y: 0, width: 10, height: 10)) == zone)
        #expect(zone.avoiding(PixelRect(x: 70, y: 0, width: 100, height: 100)) == PixelRect(x: 0, y: 0, width: 70, height: 100))
        #expect(zone.avoiding(PixelRect(x: 0, y: 20, width: 100, height: 10)) == PixelRect(x: 0, y: 30, width: 100, height: 70))
        #expect(!zone.avoiding(PixelRect(x: 40, y: 40, width: 20, height: 20)).intersects(PixelRect(x: 40, y: 40, width: 20, height: 20)))
    }

    @Test func theDSFrameHoldsTwoScreensAndTouchesTheLowerOne() {
        let ds = SystemScreens.ds
        #expect(ds.sources.map(\.size) == [PixelSize(width: 256, height: 192), PixelSize(width: 256, height: 192)])
        #expect(ds.sources[1].minY == 192)
        #expect(ds.touchScreen == 1)
        #expect(SystemScreens.gba.sources == [PixelRect(x: 0, y: 0, width: 240, height: 160)])
        #expect(SystemScreens.gba.touchScreen == nil)
    }
}
