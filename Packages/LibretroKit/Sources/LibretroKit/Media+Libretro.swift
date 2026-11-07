internal import CLibretro

// Conversions between the C structures of libretro.h and the public values.

extension PixelFormat {
    /// The format for a value of `enum retro_pixel_format`, nil for unknown values.
    init?(libretroValue: UInt32) {
        switch libretroValue {
        case RETRO_PIXEL_FORMAT_0RGB1555.rawValue: self = .rgb1555
        case RETRO_PIXEL_FORMAT_XRGB8888.rawValue: self = .xrgb8888
        case RETRO_PIXEL_FORMAT_RGB565.rawValue: self = .rgb565
        default: return nil
        }
    }

    /// Arcfold shows RGB565 and XRGB8888 (ADR 0005).
    var isSupported: Bool {
        self != .rgb1555
    }
}

extension VideoGeometry {
    init(_ geometry: retro_game_geometry) {
        let baseWidth = Int(geometry.base_width)
        let baseHeight = Int(geometry.base_height)
        // A core reports 0 (or less) for square pixels.
        let aspectRatio = geometry.aspect_ratio > 0
            ? Double(geometry.aspect_ratio)
            : (baseHeight > 0 ? Double(baseWidth) / Double(baseHeight) : 1)
        self.init(
            baseWidth: baseWidth,
            baseHeight: baseHeight,
            maxWidth: max(Int(geometry.max_width), baseWidth),
            maxHeight: max(Int(geometry.max_height), baseHeight),
            aspectRatio: aspectRatio
        )
    }
}

extension AVTiming {
    init(_ timing: retro_system_timing) {
        self.init(framesPerSecond: timing.fps, sampleRate: timing.sample_rate)
    }
}
