import LibretroKit
import Metal
import Renderer
import Testing

/// Both DS screens out of one uploaded frame, one viewport each, in one render
/// pass (ADR 0006, section 5): every drawable pixel is compared with what the
/// CPU computes, for XRGB8888 and RGB565, at different scales and odd origins.
struct ViewportRenderTests {
    /// The upper DS screen 3× at (107, 29) and the touch screen 2× at
    /// (363, 641) in a target of odd size; both origins are odd.
    static let dsViewports = [
        ScreenViewport(sourceX: 0, sourceY: 0, sourceWidth: 256, sourceHeight: 192, originX: 107, originY: 29, scale: 3),
        ScreenViewport(sourceX: 0, sourceY: 192, sourceWidth: 256, sourceHeight: 192, originX: 363, originY: 641, scale: 2),
    ]
    static let target = (width: 1301, height: 1033)

    /// Uploads `garbage` over the whole texture (as an older, larger frame
    /// would have left it) and then the frame at its top left, draws the
    /// viewports into a target and reads it back as BGRA bytes.
    static func render(format: PixelFormat, frame: [UInt8], frameWidth: Int, frameHeight: Int,
                       garbage: [UInt8], textureWidth: Int, textureHeight: Int,
                       viewports: [ScreenViewport], target: (width: Int, height: Int)) throws -> [UInt8] {
        let renderer = try PictureRenderTests.makeRenderer()
        let bytesPerPixel = format == .xrgb8888 ? 4 : 2
        let texture = try #require(renderer.makeUploadTexture(format: format, width: textureWidth, height: textureHeight))
        garbage.withUnsafeBytes { bytes in
            renderer.upload(pixels: bytes.baseAddress!, width: textureWidth, height: textureHeight,
                            bytesPerRow: textureWidth * bytesPerPixel, into: texture)
        }
        frame.withUnsafeBytes { bytes in
            renderer.upload(pixels: bytes.baseAddress!, width: frameWidth, height: frameHeight,
                            bytesPerRow: frameWidth * bytesPerPixel, into: texture)
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: PictureRenderer.targetPixelFormat, width: target.width, height: target.height, mipmapped: false)
        descriptor.usage = .renderTarget
        descriptor.storageMode = .private
        let targetTexture = try #require(renderer.device.makeTexture(descriptor: descriptor))
        let bytesPerRow = target.width * 4
        let buffer = try #require(renderer.device.makeBuffer(length: bytesPerRow * target.height, options: .storageModeShared))
        let commandBuffer = try #require(renderer.commandQueue.makeCommandBuffer())
        renderer.encode(into: commandBuffer, target: targetTexture, picture: texture, format: format,
                        frameWidth: frameWidth, frameHeight: frameHeight, viewports: viewports)
        let blit = try #require(commandBuffer.makeBlitCommandEncoder())
        blit.copy(from: targetTexture, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                  sourceSize: MTLSize(width: target.width, height: target.height, depth: 1),
                  to: buffer, destinationOffset: 0, destinationBytesPerRow: bytesPerRow,
                  destinationBytesPerImage: bytesPerRow * target.height)
        blit.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        #expect(commandBuffer.status == .completed, "\(String(describing: commandBuffer.error))")
        return Array(UnsafeBufferPointer(start: buffer.contents().assumingMemoryBound(to: UInt8.self),
                                         count: bytesPerRow * target.height))
    }

    /// The source pixel each target pixel shows, computed on the CPU: the last
    /// viewport that covers it, cut to the frame; nil for black.
    static func sourcePixel(x: Int, y: Int, viewports: [ScreenViewport], frameWidth: Int, frameHeight: Int) -> (Int, Int)? {
        var result: (Int, Int)?
        for viewport in viewports {
            let dx = x - viewport.originX
            let dy = y - viewport.originY
            guard dx >= 0, dy >= 0, dx < viewport.width, dy < viewport.height else { continue }
            let column = viewport.sourceX + dx / viewport.scale
            let row = viewport.sourceY + dy / viewport.scale
            guard column < frameWidth, row < frameHeight else { continue }
            result = (column, row)
        }
        return result
    }

    /// Compares every target pixel with the source pixel the CPU expects, or
    /// opaque black. `expected` holds the BGRA bytes of each frame pixel as
    /// one little-endian word, row by row; the loop works on words, so the
    /// comparison stays quick in debug builds next to the timing tests.
    static func mismatches(_ bytes: [UInt8], target: (width: Int, height: Int), viewports: [ScreenViewport],
                           frameWidth: Int, frameHeight: Int, expected: [UInt32]) -> (count: Int, first: String?) {
        let black: UInt32 = 0xFF00_0000
        var count = 0
        var first: String?
        bytes.withUnsafeBytes { raw in
            let got = raw.bindMemory(to: UInt32.self)
            for y in 0..<target.height {
                for x in 0..<target.width {
                    var want = black
                    if let pixel = sourcePixel(x: x, y: y, viewports: viewports,
                                               frameWidth: frameWidth, frameHeight: frameHeight) {
                        want = expected[pixel.1 * frameWidth + pixel.0]
                    }
                    let value = got[y * target.width + x]
                    if value == want { continue }
                    count += 1
                    if first == nil {
                        first = "(\(x), \(y)): got 0x\(String(value, radix: 16)), expected 0x\(String(want, radix: 16))"
                    }
                }
            }
        }
        return (count, first)
    }

    /// BGRA bytes as one little-endian word.
    static func word(_ bgra: [UInt8]) -> UInt32 {
        UInt32(bgra[0]) | UInt32(bgra[1]) << 8 | UInt32(bgra[2]) << 16 | UInt32(bgra[3]) << 24
    }

    /// XRGB8888 as melonDS DS delivers it: every pixel of the 256 × 384
    /// frame differs (blue x, green the low bits of y, red the high bit of y).
    @Test func bothDSScreensFromOneXRGB8888Frame() throws {
        let (width, height) = (256, 384)
        var frame = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                frame[offset] = UInt8(x)
                frame[offset + 1] = UInt8(y & 0xFF)
                frame[offset + 2] = UInt8(0x40 | y >> 8)
                frame[offset + 3] = 0x77
            }
        }
        // melonDS DS reports up to 1024 × 576; the rest of the texture holds white.
        let garbage = [UInt8](repeating: 0xFF, count: 1024 * 576 * 4)
        let bytes = try Self.render(format: .xrgb8888, frame: frame, frameWidth: width, frameHeight: height,
                                    garbage: garbage, textureWidth: 1024, textureHeight: 576,
                                    viewports: Self.dsViewports, target: Self.target)
        let expected = (0..<width * height).map { index in
            Self.word([UInt8(index % width), UInt8((index / width) & 0xFF), UInt8(0x40 | (index / width) >> 8), 255])
        }
        let result = Self.mismatches(bytes, target: Self.target, viewports: Self.dsViewports,
                                     frameWidth: width, frameHeight: height, expected: expected)
        #expect(result.count == 0, "\(result.count) pixels differ, first \(result.first ?? "-")")
    }

    @Test func bothDSScreensFromOneRGB565Frame() throws {
        let (width, height) = (256, 384)
        let pixels = (0..<width * height).map { index in UInt16(truncatingIfNeeded: (index &* 2_654_435_761) >> 9) }
        let frame = pixels.withUnsafeBytes { Array($0) }
        let garbage = [UInt8](repeating: 0xFF, count: 512 * 512 * 2)
        let bytes = try Self.render(format: .rgb565, frame: frame, frameWidth: width, frameHeight: height,
                                    garbage: garbage, textureWidth: 512, textureHeight: 512,
                                    viewports: Self.dsViewports, target: Self.target)
        let result = Self.mismatches(bytes, target: Self.target, viewports: Self.dsViewports,
                                     frameWidth: width, frameHeight: height,
                                     expected: pixels.map { Self.word(PictureRenderTests.bgra(rgb565: $0)) })
        #expect(result.count == 0, "\(result.count) pixels differ, first \(result.first ?? "-")")
    }

    /// Viewports reach past the target on every side, and one asks for rows
    /// the frame does not have: those parts stay black instead of showing
    /// what the texture held before.
    @Test func viewportsAreCutToTheTargetAndTheFrame() throws {
        let (width, height) = (240, 160)
        let pixels = (0..<width * height).map { UInt16(truncatingIfNeeded: $0 &* 40_503) | 0x0821 }
        let frame = pixels.withUnsafeBytes { Array($0) }
        let viewports = [
            ScreenViewport(sourceX: 0, sourceY: 0, sourceWidth: 240, sourceHeight: 160, originX: -37, originY: -11, scale: 2),
            ScreenViewport(sourceX: 100, sourceY: 100, sourceWidth: 140, sourceHeight: 120, originX: 401, originY: 233, scale: 3),
            ScreenViewport(sourceX: 0, sourceY: 0, sourceWidth: 10, sourceHeight: 10, originX: 900, originY: 900, scale: 1),
        ]
        let target = (width: 711, height: 403)
        let garbage = [UInt8](repeating: 0xFF, count: 256 * 256 * 2)
        let bytes = try Self.render(format: .rgb565, frame: frame, frameWidth: width, frameHeight: height,
                                    garbage: garbage, textureWidth: 256, textureHeight: 256,
                                    viewports: viewports, target: target)
        let result = Self.mismatches(bytes, target: target, viewports: viewports, frameWidth: width, frameHeight: height,
                                     expected: pixels.map { Self.word(PictureRenderTests.bgra(rgb565: $0)) })
        #expect(result.count == 0, "\(result.count) pixels differ, first \(result.first ?? "-")")
    }

    @Test func visibleRectangles() {
        let viewport = ScreenViewport(sourceX: 0, sourceY: 192, sourceWidth: 256, sourceHeight: 192, originX: 61, originY: 768, scale: 4)
        let visible = PictureRenderer.visibleRect(of: viewport, frameWidth: 256, frameHeight: 384, targetWidth: 1398, targetHeight: 2034)
        #expect(visible.map { [$0.left, $0.top, $0.right, $0.bottom] } == [61, 768, 1085, 1536])
        // A GBA frame under the DS arrangement: no rows of the lower screen.
        #expect(PictureRenderer.visibleRect(of: viewport, frameWidth: 240, frameHeight: 160, targetWidth: 1398, targetHeight: 2034) == nil)
        let outside = ScreenViewport(sourceX: 0, sourceY: 0, sourceWidth: 256, sourceHeight: 192, originX: 2000, originY: 0, scale: 1)
        #expect(PictureRenderer.visibleRect(of: outside, frameWidth: 256, frameHeight: 384, targetWidth: 1398, targetHeight: 2034) == nil)
    }
}
