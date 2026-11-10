import LibretroKit
import Testing

/// Libretro pointer coordinates for the DS touch screen (ADR 0006): the app
/// aims at the centre of a pixel, and both melonDS libretro cores read that
/// pixel back.
struct PointerPositionTests {
    /// melonDS DS: its pointer matrix scales by extent / (2 · 0x7FFF), moves by
    /// extent / 2 and truncates to a pixel (src/libretro/screenlayout.cpp).
    static func pixelMelonDSDS(_ coordinate: Int16, extent: Int) -> Int {
        let size = Float(extent)
        return Int(Float(coordinate) * size / (2 * 32_767) + size / 2)
    }

    /// The older libretro/melonDS: (p + 0x8000) · extent / 0x10000 in integers
    /// (src/libretro/input.cpp).
    static func pixelLibretroMelonDS(_ coordinate: Int16, extent: Int) -> Int {
        (Int(coordinate) + 0x8000) * extent / 0x10000
    }

    @Test(arguments: [192, 256, 384, 512])
    func everyPixelComesBackInBothCores(extent: Int) {
        for pixel in 0..<extent {
            let coordinate = PointerPosition.coordinate(forPixel: pixel, extent: extent)
            #expect(Self.pixelMelonDSDS(coordinate, extent: extent) == pixel, "pixel \(pixel) of \(extent)")
            #expect(Self.pixelLibretroMelonDS(coordinate, extent: extent) == pixel, "pixel \(pixel) of \(extent)")
        }
    }

    @Test func theCoordinateIsTheCentreOfThePixel() {
        // The edge between pixels 99 and 100 of 256 lies at -7167.78
        // (measured with melonDS DS 1.4.0, ADR 0006); the centres are a pixel
        // width of 256 units apart.
        #expect(PointerPosition.coordinate(forPixel: 99, extent: 256) == -7_296)
        #expect(PointerPosition.coordinate(forPixel: 100, extent: 256) == -7_040)
        #expect(PointerPosition.coordinate(forPixel: 0, extent: 256) == -32_639)
        #expect(PointerPosition.coordinate(forPixel: 255, extent: 256) == 32_639)
        // The lower DS screen starts at row 192 of the 384 rows.
        #expect(PointerPosition.coordinate(forPixel: 192, extent: 384) == 85)
    }

    @Test func aPixelOfTheLowerScreenAimsIntoTheLowerHalfOfTheFrame() {
        let position = PointerPosition(pixelX: 37, pixelY: 192 + 150, frameWidth: 256, frameHeight: 384)
        #expect(Self.pixelMelonDSDS(position.x, extent: 256) == 37)
        #expect(Self.pixelMelonDSDS(position.y, extent: 384) - 192 == 150)
        #expect(position.y > 0)
    }
}
