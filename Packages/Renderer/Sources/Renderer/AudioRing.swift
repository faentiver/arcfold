import AVFAudio
internal import CRendererAudio
import Darwin
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
    // @unchecked: `ring` points to C memory that only the C functions touch,
    // through atomics (ARCAudioRing in CRendererAudio.m). The pointer itself
    // never changes.
    private let ring: OpaquePointer

    /// - Parameter capacityFrames: A power of two; 8192 frames are 250 ms at 32 768 Hz.
    public init(capacityFrames: Int = 8192) {
        precondition(capacityFrames >= 64 && capacityFrames.nonzeroBitCount == 1,
                     "The capacity of an AudioRing must be a power of two of at least 64 frames")
        guard let ring = ARCAudioRingCreate(UInt32(capacityFrames)) else {
            fatalError("The audio ring could not allocate \(capacityFrames) frames")
        }
        self.ring = ring
    }

    deinit {
        ARCAudioRingDestroy(ring)
    }

    /// Called on the emulation thread. Copies the frames into the ring without
    /// allocating or locking; the C part is checked by the compiler.
    public func write(_ samples: Span<Int16>) -> AudioBufferStatus {
        var status = ARCAudioWriteStatus()
        let now = mach_absolute_time()
        samples.withUnsafeBufferPointer { buffer in
            if let base = buffer.baseAddress {
                ARCAudioRingWrite(ring, base, UInt32(truncatingIfNeeded: buffer.count / 2), now, &status)
            } else {
                // An empty span may have no address; the status is still wanted.
                var silence: Int16 = 0
                ARCAudioRingWrite(ring, &silence, 0, now, &status)
            }
        }
        return AudioBufferStatus(
            bufferedFrames: Int(status.bufferedFrames),
            targetFrames: Int(status.targetFrames),
            isConsuming: status.isConsuming
        )
    }

    /// Counters of both sides, read atomically.
    public var counters: AudioCounters {
        var counters = ARCAudioCounters()
        ARCAudioRingReadCounters(ring, &counters)
        return AudioCounters(
            underruns: counters.underruns,
            underrunFrames: counters.underrunFrames,
            droppedFrames: counters.droppedFrames,
            primes: counters.primes,
            renderCalls: counters.renderCalls,
            largestRequest: Int(counters.largestRequest),
            bufferedFrames: Int(counters.bufferedFrames),
            targetFrames: Int(counters.targetFrames)
        )
    }

    // MARK: Control, for AudioOutput and tests

    /// The level priming waits for, clamped to half the capacity.
    package func setTargetFrames(_ frames: Int) {
        ARCAudioRingSetTargetFrames(ring, UInt32(clamping: frames))
    }

    /// Silence without consuming or counting underruns; leaving it primes again.
    package func setSuspended(_ suspended: Bool) {
        ARCAudioRingSetSuspended(ring, suspended)
    }

    /// Drops what is buffered at the next render call and primes again.
    package func requestFlush() {
        ARCAudioRingRequestFlush(ring)
    }

    /// What the render function does right now.
    package var state: RingState {
        var counters = ARCAudioCounters()
        ARCAudioRingReadCounters(ring, &counters)
        return RingState(rawValue: counters.state.rawValue) ?? .priming
    }

    package enum RingState: UInt32, Sendable {
        case priming = 0
        case playing = 1
        case suspended = 2
    }

    /// The consumer side as the render block runs it, for tests: fills `frames`
    /// packed stereo frames (left in the low 16 bits) and reports silence.
    package func renderForTesting(into output: UnsafeMutablePointer<UInt32>, frames: Int) -> Bool {
        var isSilence = false
        ARCAudioRingRenderForTesting(ring, output, UInt32(frames), &isSilence)
        return isSilence
    }

    /// A source node that plays this ring. `format` is the core's format,
    /// interleaved stereo Int16; nil for any other format.
    func makeSourceNode(format: AVAudioFormat) -> AVAudioSourceNode? {
        ARCAudioMakeSourceNode(format, ring)
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
