import LibretroKit

/// The lock-free ring between the emulation thread (`AudioSink`) and the
/// real-time render block of the audio output.
///
/// Stereo Int16 frames as the core delivers them. The render block lives in C
/// and is checked by the compiler for allocations, locks and Objective-C
/// messages (ADR 0005); Swift never runs on the audio thread. Before playing,
/// and again after an underrun, the ring fills up to its target level.
/// One producer and one consumer.
public final class AudioRing: AudioSink, @unchecked Sendable {
    /// - Parameter capacityFrames: A power of two; 8192 frames are 250 ms at 32 768 Hz.
    public init(capacityFrames: Int = 8192) {
        fatalError("M1 track A")
    }

    public func write(_ samples: Span<Int16>) -> AudioBufferStatus {
        fatalError("M1 track A")
    }

    /// Counters of both sides, read atomically.
    public var counters: AudioCounters {
        fatalError("M1 track A")
    }
}

/// What happened in the audio ring. Priming at the start, after a pause or
/// after a route change does not count as an underrun.
public struct AudioCounters: Sendable, Hashable {
    /// Render calls that found fewer frames than requested while playing.
    public var underruns: UInt64
    /// Frames filled with silence because of underruns.
    public var underrunFrames: UInt64
    /// Frames the producer dropped because the ring was full.
    public var droppedFrames: UInt64
    /// Times the ring started filling up to its target level.
    public var primes: UInt64
    /// Calls of the render block.
    public var renderCalls: UInt64
    /// The largest number of frames one render call asked for.
    public var largestRequest: Int
    /// Frames buffered right now.
    public var bufferedFrames: Int
    /// The level the ring holds after a write.
    public var targetFrames: Int

    public init(
        underruns: UInt64, underrunFrames: UInt64, droppedFrames: UInt64, primes: UInt64,
        renderCalls: UInt64, largestRequest: Int, bufferedFrames: Int, targetFrames: Int
    ) {
        self.underruns = underruns
        self.underrunFrames = underrunFrames
        self.droppedFrames = droppedFrames
        self.primes = primes
        self.renderCalls = renderCalls
        self.largestRequest = largestRequest
        self.bufferedFrames = bufferedFrames
        self.targetFrames = targetFrames
    }
}
