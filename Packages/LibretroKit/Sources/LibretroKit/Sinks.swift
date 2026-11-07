// Where pictures and sound go (ADR 0005). LibretroKit only defines the
// protocols; Renderer implements them, tests record with their own sinks.
//
// Both sinks are called on the emulation thread, inside retro_run. That is a
// real-time path: an implementation must not allocate, block, take a lock that
// can be held by another thread, do file I/O or call Metal or AVFoundation.
// Copying the data and updating atomics is what it should do.

/// Identifies an emulated frame.
public struct FrameStamp: Sendable, Hashable {
    /// The number of the `retro_run` call that produced the frame, starting at
    /// 1 after `EmulationSession.load()`. Frames without a picture (a core may
    /// repeat the previous one) leave gaps.
    public var sequence: UInt64
    /// The deadline the frame clock planned for the start of this frame, in
    /// host time units (`mach_absolute_time`, the time base of
    /// `CACurrentMediaTime` and `AudioTimeStamp.mHostTime`). It is free of
    /// scheduling jitter, so a presenter can pick frames by it.
    public var nominalTime: UInt64

    public init(sequence: UInt64, nominalTime: UInt64) {
        self.sequence = sequence
        self.nominalTime = nominalTime
    }
}

/// Receives the pictures of a core.
public protocol VideoSink: AnyObject, Sendable {
    /// Called on the emulation thread once for every frame the core draws.
    ///
    /// - Parameters:
    ///   - pixels: `height` rows of `bytesPerRow` bytes, the last row may be
    ///     shorter (`width * format.bytesPerPixel`). Valid only during the call.
    ///   - width: Visible pixels per row, at most `VideoGeometry.maxWidth`.
    ///   - height: Rows, at most `VideoGeometry.maxHeight`.
    ///   - bytesPerRow: The core's pitch. It can exceed `width * bytesPerPixel`
    ///     (mGBA: 512 bytes for 240 pixels).
    ///   - format: Always `SessionInfo.pixelFormat` of the session.
    ///   - stamp: Sequence number and nominal start time of the frame.
    func submit(pixels: RawSpan, width: Int, height: Int, bytesPerRow: Int,
                format: PixelFormat, stamp: FrameStamp)
}

/// The fill state of an audio buffer right after a write. The frame clock of
/// the emulation thread trims its period from it (ADR 0005).
public struct AudioBufferStatus: Sendable, Hashable {
    /// Audio frames (one left and one right sample each) waiting to be played.
    public var bufferedFrames: Int
    /// The level the buffer should still hold when new sound arrives: the
    /// reserve the output needs against its IO buffer and late frames. The
    /// frame clock steers the level before each frame's sound to it, so right
    /// after a frame's writes the buffer holds about one frame of sound more
    /// (ADR 0005).
    public var targetFrames: Int
    /// False while the output is not pulling (priming, suspended, no output).
    /// The clock then runs at the nominal rate instead of following the buffer.
    public var isConsuming: Bool

    public init(bufferedFrames: Int, targetFrames: Int, isConsuming: Bool) {
        self.bufferedFrames = bufferedFrames
        self.targetFrames = targetFrames
        self.isConsuming = isConsuming
    }
}

/// Receives the sound of a core.
public protocol AudioSink: AnyObject, Sendable {
    /// Called on the emulation thread one or more times per frame.
    ///
    /// - Parameter samples: Interleaved stereo samples (left, right, left, …)
    ///   at `AVTiming.sampleRate`, `samples.count / 2` frames. Valid only
    ///   during the call.
    /// - Returns: The buffer state after the write. Samples that do not fit
    ///   are dropped by the sink and counted there.
    func write(_ samples: Span<Int16>) -> AudioBufferStatus
}
