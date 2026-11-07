// Values that describe what a running core produces (ADR 0005). They cross
// threads, so all of them are Sendable value types.

/// The layout of the pixels a core hands to `VideoSink` (`enum retro_pixel_format`).
///
/// Libretro starts every core in 0RGB1555. Arcfold accepts RGB565 and
/// XRGB8888 only: a core that keeps 0RGB1555 fails to load with
/// `SessionError.unsupportedPixelFormat`.
public enum PixelFormat: Sendable, Hashable {
    /// A native-endian 16-bit value per pixel: red in bits 15-11, green in
    /// 10-5, blue in 4-0 (mGBA).
    case rgb565
    /// A native-endian 32-bit value per pixel, 0xXXRRGGBB; in memory on arm64
    /// the bytes are blue, green, red, unused (melonDS, M2).
    case xrgb8888
    /// A native-endian 16-bit value per pixel: bit 15 unused, red in 14-10,
    /// green in 9-5, blue in 4-0. The libretro default; refused by Arcfold.
    case rgb1555

    /// Bytes one pixel takes in a row.
    public var bytesPerPixel: Int {
        switch self {
        case .rgb565, .rgb1555: 2
        case .xrgb8888: 4
        }
    }
}

/// The picture size a core reports (`struct retro_game_geometry`).
public struct VideoGeometry: Sendable, Hashable {
    /// The usual picture size, for example 240 x 160 for the GBA.
    public var baseWidth: Int
    public var baseHeight: Int
    /// The largest picture the core can deliver. Buffers are sized for this.
    public var maxWidth: Int
    public var maxHeight: Int
    /// The display aspect ratio. A core's 0 (square pixels) is reported as
    /// `baseWidth / baseHeight`, so the value is always positive.
    public var aspectRatio: Double

    public init(baseWidth: Int, baseHeight: Int, maxWidth: Int, maxHeight: Int, aspectRatio: Double) {
        self.baseWidth = baseWidth
        self.baseHeight = baseHeight
        self.maxWidth = maxWidth
        self.maxHeight = maxHeight
        self.aspectRatio = aspectRatio
    }
}

/// The clocks of a core (`struct retro_system_timing`).
public struct AVTiming: Sendable, Hashable {
    /// Emulated frames per second, for example 59.7275 for the GBA.
    /// The emulation thread paces `retro_run` with it, never with the display.
    public var framesPerSecond: Double
    /// Audio frames per second the core delivers, for example 32768 for mGBA.
    public var sampleRate: Double

    public init(framesPerSecond: Double, sampleRate: Double) {
        self.framesPerSecond = framesPerSecond
        self.sampleRate = sampleRate
    }
}

/// What `EmulationSession.load()` learned about the core and the game.
public struct SessionInfo: Sendable, Hashable {
    /// Name, version and file extensions of the core.
    public var system: SystemInfo
    public var geometry: VideoGeometry
    public var timing: AVTiming
    /// The format of every picture this session delivers. It does not change
    /// while the session runs.
    public var pixelFormat: PixelFormat

    public init(system: SystemInfo, geometry: VideoGeometry, timing: AVTiming, pixelFormat: PixelFormat) {
        self.system = system
        self.geometry = geometry
        self.timing = timing
        self.pixelFormat = pixelFormat
    }
}
