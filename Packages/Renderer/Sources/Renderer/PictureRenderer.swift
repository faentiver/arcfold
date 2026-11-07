import Foundation
import LibretroKit
import Metal

/// Uploads emulated pictures into textures and draws them at a whole-number
/// scale into a target texture. Used by `GameScreen` for the drawable and by
/// the tests for an offscreen texture.
///
/// RGB565 goes into an `r16Uint` texture and is decoded in the fragment shader,
/// XRGB8888 into a `bgra8Unorm` texture. The target is `bgra8Unorm`; sRGB
/// formats are avoided because the Simulator cannot write them (ADR 0005).
package final class PictureRenderer {
    package let device: any MTLDevice
    package let commandQueue: any MTLCommandQueue
    private let rgb565Pipeline: any MTLRenderPipelineState
    private let xrgb8888Pipeline: any MTLRenderPipelineState

    /// The pixel format of every target texture.
    package static let targetPixelFormat = MTLPixelFormat.bgra8Unorm

    package init(device: any MTLDevice) throws(PictureRendererError) {
        guard let commandQueue = device.makeCommandQueue() else {
            throw .metal(reason: "The device has no command queue")
        }
        let library: any MTLLibrary
        do {
            library = try device.makeDefaultLibrary(bundle: .module)
        } catch {
            throw .metal(reason: "The shader library is missing: \(error.localizedDescription)")
        }
        do {
            rgb565Pipeline = try Self.makePipeline(device: device, library: library, fragment: "picture_rgb565")
            xrgb8888Pipeline = try Self.makePipeline(device: device, library: library, fragment: "picture_xrgb8888")
        } catch {
            throw .metal(reason: "A render pipeline failed: \(error.localizedDescription)")
        }
        self.device = device
        self.commandQueue = commandQueue
    }

    private static func makePipeline(
        device: any MTLDevice, library: any MTLLibrary, fragment: String
    ) throws -> any MTLRenderPipelineState {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = fragment
        descriptor.vertexFunction = library.makeFunction(name: "picture_vertex")
        descriptor.fragmentFunction = library.makeFunction(name: fragment)
        descriptor.colorAttachments[0].pixelFormat = targetPixelFormat
        return try device.makeRenderPipelineState(descriptor: descriptor)
    }

    /// The texture format a picture of `format` is uploaded into.
    package static func texturePixelFormat(for format: PixelFormat) -> MTLPixelFormat? {
        switch format {
        case .rgb565: .r16Uint
        case .xrgb8888: .bgra8Unorm
        case .rgb1555: nil
        }
    }

    /// A texture the CPU writes with `upload` and the shader reads.
    package func makeUploadTexture(format: PixelFormat, width: Int, height: Int) -> (any MTLTexture)? {
        guard let pixelFormat = Self.texturePixelFormat(for: format) else { return nil }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat, width: width, height: height, mipmapped: false)
        descriptor.usage = .shaderRead
        descriptor.storageMode = .shared
        return device.makeTexture(descriptor: descriptor)
    }

    /// Copies compact rows into the top left of `texture`. The GPU must not
    /// be using the texture.
    package func upload(pixels: UnsafeRawPointer, width: Int, height: Int, bytesPerRow: Int,
                        into texture: any MTLTexture) {
        texture.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0,
                        withBytes: pixels, bytesPerRow: bytesPerRow)
    }

    /// Encodes one render pass into `target`: black everywhere, the picture of
    /// `width x height` pixels from the top left of `picture` at the placement
    /// `ScreenPlacement.fitting` chooses for the target size.
    @discardableResult
    package func encode(into commandBuffer: any MTLCommandBuffer, target: any MTLTexture,
                        picture: any MTLTexture, format: PixelFormat, width: Int, height: Int) -> ScreenPlacement {
        let placement = ScreenPlacement.fitting(
            sourceWidth: width, sourceHeight: height, drawableWidth: target.width, drawableHeight: target.height)
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return placement }
        defer { encoder.endEncoding() }

        // The viewport is the visible part of the scaled picture.
        let left = max(placement.originX, 0)
        let top = max(placement.originY, 0)
        let right = min(placement.originX + placement.width, target.width)
        let bottom = min(placement.originY + placement.height, target.height)
        guard right > left, bottom > top,
              let pipeline = format == .xrgb8888 ? xrgb8888Pipeline : format == .rgb565 ? rgb565Pipeline : nil
        else {
            return placement
        }
        encoder.setRenderPipelineState(pipeline)
        encoder.setViewport(MTLViewport(
            originX: Double(left), originY: Double(top),
            width: Double(right - left), height: Double(bottom - top), znear: 0, zfar: 1))
        var uniforms = PictureUniforms(
            origin: SIMD2(Int32(placement.originX), Int32(placement.originY)), scale: Int32(placement.scale))
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<PictureUniforms>.stride, index: 0)
        encoder.setFragmentTexture(picture, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        return placement
    }
}

/// Matches `PictureUniforms` in Picture.metal: int2 origin, int scale.
private struct PictureUniforms {
    var origin: SIMD2<Int32>
    var scale: Int32
}

/// Why the renderer could not be set up.
package enum PictureRendererError: Error, Sendable, Hashable, CustomStringConvertible {
    case metal(reason: String)

    package var description: String {
        switch self {
        case let .metal(reason): "Metal could not be set up: \(reason)"
        }
    }
}
