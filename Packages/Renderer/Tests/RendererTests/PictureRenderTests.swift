import LibretroKit
import Metal
import Renderer
import Testing

/// Offscreen renders with the screen's shaders, compared pixel by pixel with
/// what the CPU computes (ADR 0005, section 5). Runs in the Simulator, where
/// b5g6r5Unorm is not available; RGB565 goes through r16Uint and the shader.
struct PictureRenderTests {
    struct Rendered {
        let bytes: [UInt8]
        let width: Int
        let height: Int
        let placement: ScreenPlacement
    }

    static func makeRenderer() throws -> PictureRenderer {
        let device = try #require(MTLCreateSystemDefaultDevice(), "No Metal device")
        return try PictureRenderer(device: device)
    }

    /// Draws `picture` into a private bgra8Unorm target and copies it into a
    /// shared buffer for the CPU.
    static func render(_ renderer: PictureRenderer, picture: any MTLTexture, format: PixelFormat,
                       width: Int, height: Int, drawableWidth: Int, drawableHeight: Int) throws -> Rendered {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: PictureRenderer.targetPixelFormat, width: drawableWidth, height: drawableHeight, mipmapped: false)
        descriptor.usage = .renderTarget
        descriptor.storageMode = .private
        let target = try #require(renderer.device.makeTexture(descriptor: descriptor))
        let bytesPerRow = drawableWidth * 4
        let buffer = try #require(renderer.device.makeBuffer(length: bytesPerRow * drawableHeight, options: .storageModeShared))
        let commandBuffer = try #require(renderer.commandQueue.makeCommandBuffer())
        let placement = renderer.encode(into: commandBuffer, target: target, picture: picture, format: format,
                                        width: width, height: height)
        let blit = try #require(commandBuffer.makeBlitCommandEncoder())
        blit.copy(from: target, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                  sourceSize: MTLSize(width: drawableWidth, height: drawableHeight, depth: 1),
                  to: buffer, destinationOffset: 0, destinationBytesPerRow: bytesPerRow,
                  destinationBytesPerImage: bytesPerRow * drawableHeight)
        blit.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        #expect(commandBuffer.status == .completed, "\(String(describing: commandBuffer.error))")
        let bytes = UnsafeBufferPointer(start: buffer.contents().assumingMemoryBound(to: UInt8.self),
                                        count: bytesPerRow * drawableHeight)
        return Rendered(bytes: Array(bytes), width: drawableWidth, height: drawableHeight, placement: placement)
    }

    /// The 8-bit value of a 5- or 6-bit channel, rounded to the nearest.
    static func expand(_ value: Int, maximum: Int) -> UInt8 {
        UInt8((value * 255 * 2 + maximum) / (2 * maximum))
    }

    /// BGRA as the drawable holds it, for an RGB565 value.
    static func bgra(rgb565 value: UInt16) -> [UInt8] {
        let red = Int(value >> 11) & 31
        let green = Int(value >> 5) & 63
        let blue = Int(value) & 31
        return [expand(blue, maximum: 31), expand(green, maximum: 63), expand(red, maximum: 31), 255]
    }

    /// Counts drawable pixels that differ from the source texel or, outside
    /// the picture, from opaque black.
    static func mismatches(in rendered: Rendered, expected: (_ column: Int, _ row: Int) -> [UInt8]) -> (count: Int, first: String?) {
        let placement = rendered.placement
        var count = 0
        var first: String?
        for y in 0..<rendered.height {
            for x in 0..<rendered.width {
                let inside = x >= placement.originX && x < placement.originX + placement.width
                    && y >= placement.originY && y < placement.originY + placement.height
                let want = inside
                    ? expected((x - placement.originX) / placement.scale, (y - placement.originY) / placement.scale)
                    : [0, 0, 0, 255]
                let offset = (y * rendered.width + x) * 4
                let got = Array(rendered.bytes[offset..<offset + 4])
                if got != want {
                    count += 1
                    if first == nil {
                        first = "(\(x), \(y)): got \(got), expected \(want)"
                    }
                }
            }
        }
        return (count, first)
    }

    /// Every one of the 65 536 RGB565 values, once, at scale 2.
    @Test func decodesEveryRGB565ValueExactly() throws {
        let renderer = try Self.makeRenderer()
        let side = 256
        let pixels = (0..<side * side).map { UInt16($0) }
        let texture = try #require(renderer.makeUploadTexture(format: .rgb565, width: side, height: side))
        pixels.withUnsafeBytes { bytes in
            renderer.upload(pixels: bytes.baseAddress!, width: side, height: side, bytesPerRow: side * 2, into: texture)
        }
        let rendered = try Self.render(renderer, picture: texture, format: .rgb565, width: side, height: side,
                                       drawableWidth: 600, drawableHeight: 700)
        #expect(rendered.placement == ScreenPlacement(scale: 2, originX: 44, originY: 94, width: 512, height: 512))
        let result = Self.mismatches(in: rendered) { column, row in
            Self.bgra(rgb565: pixels[row * side + column])
        }
        #expect(result.count == 0, "\(result.count) pixels differ, first \(result.first ?? "-")")
    }

    /// The GBA picture on the three Duo drawables: placement and every pixel.
    @Test(arguments: [(1878, 2670), (2670, 1878), (1398, 2034)])
    func placesTheGBAPictureOnTheDuo(drawable: (width: Int, height: Int)) throws {
        let renderer = try Self.makeRenderer()
        let pixels = (0..<240 * 160).map { index in UInt16(truncatingIfNeeded: (index &* 2_654_435_761) >> 7) }
        let texture = try #require(renderer.makeUploadTexture(format: .rgb565, width: 240, height: 160))
        pixels.withUnsafeBytes { bytes in
            renderer.upload(pixels: bytes.baseAddress!, width: 240, height: 160, bytesPerRow: 480, into: texture)
        }
        let rendered = try Self.render(renderer, picture: texture, format: .rgb565, width: 240, height: 160,
                                       drawableWidth: drawable.width, drawableHeight: drawable.height)
        #expect(rendered.placement == ScreenPlacement.fitting(
            sourceWidth: 240, sourceHeight: 160, drawableWidth: drawable.width, drawableHeight: drawable.height))
        let result = Self.mismatches(in: rendered) { column, row in
            Self.bgra(rgb565: pixels[row * 240 + column])
        }
        #expect(result.count == 0, "\(result.count) pixels differ, first \(result.first ?? "-")")
    }

    /// XRGB8888 keeps every byte and ignores the unused one.
    @Test func showsXRGB8888Exactly() throws {
        let renderer = try Self.makeRenderer()
        let side = 256
        let pixels = (0..<side * side).map { index -> UInt32 in
            let x = UInt32(index % side)
            let y = UInt32(index / side)
            return 0x5500_0000 | (x ^ y) << 16 | y << 8 | x
        }
        let texture = try #require(renderer.makeUploadTexture(format: .xrgb8888, width: side, height: side))
        pixels.withUnsafeBytes { bytes in
            renderer.upload(pixels: bytes.baseAddress!, width: side, height: side, bytesPerRow: side * 4, into: texture)
        }
        let rendered = try Self.render(renderer, picture: texture, format: .xrgb8888, width: side, height: side,
                                       drawableWidth: 800, drawableHeight: 600)
        #expect(rendered.placement == ScreenPlacement(scale: 2, originX: 144, originY: 44, width: 512, height: 512))
        let result = Self.mismatches(in: rendered) { column, row in
            [UInt8(column), UInt8(row), UInt8(column ^ row), 255]
        }
        #expect(result.count == 0, "\(result.count) pixels differ, first \(result.first ?? "-")")
    }

    @Test func aPictureLargerThanTheTargetIsCutCentred() throws {
        let renderer = try Self.makeRenderer()
        let pixels = (0..<240 * 160).map { UInt16(truncatingIfNeeded: $0) }
        let texture = try #require(renderer.makeUploadTexture(format: .rgb565, width: 240, height: 160))
        pixels.withUnsafeBytes { bytes in
            renderer.upload(pixels: bytes.baseAddress!, width: 240, height: 160, bytesPerRow: 480, into: texture)
        }
        let rendered = try Self.render(renderer, picture: texture, format: .rgb565, width: 240, height: 160,
                                       drawableWidth: 200, drawableHeight: 100)
        #expect(rendered.placement.originX == -20)
        let result = Self.mismatches(in: rendered) { column, row in
            Self.bgra(rgb565: pixels[row * 240 + column])
        }
        #expect(result.count == 0, "\(result.count) pixels differ, first \(result.first ?? "-")")
    }
}
