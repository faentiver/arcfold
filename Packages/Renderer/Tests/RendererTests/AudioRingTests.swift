import Darwin
import Foundation
import LibretroKit
import Renderer
import Synchronization
import Testing

/// The audio ring with its C render function, driven from Swift the way the
/// render block drives it (ADR 0005, section 6).
struct AudioRingTests {
    /// Interleaved stereo frames: left `start + n`, right the negated left value.
    static func frames(from start: Int16, count: Int) -> [Int16] {
        var samples: [Int16] = []
        samples.reserveCapacity(2 * count)
        for index in 0..<count {
            let left = start &+ Int16(truncatingIfNeeded: index)
            samples.append(left)
            samples.append(0 &- left)
        }
        return samples
    }

    @discardableResult
    static func write(_ ring: AudioRing, from start: Int16, count: Int) -> AudioBufferStatus {
        ring.write(frames(from: start, count: count).span)
    }

    /// Renders `count` frames; returns (left, right) pairs and the silence flag.
    static func render(_ ring: AudioRing, count: Int) -> (frames: [(Int16, Int16)], isSilence: Bool) {
        var output = [UInt32](repeating: 0xFFFF_FFFF, count: count)
        let isSilence = output.withUnsafeMutableBufferPointer { buffer in
            ring.renderForTesting(into: buffer.baseAddress!, frames: count)
        }
        return (output.map { (Int16(truncatingIfNeeded: $0 & 0xFFFF), Int16(truncatingIfNeeded: $0 >> 16)) }, isSilence)
    }

    /// `value` at step `step` of the fade-in after priming: (step + 1) / 64 of
    /// it, truncated like the C code.
    static func fadedIn(_ value: Int16, step: Int) -> Int16 {
        Int16(Int32(value) * Int32(step + 1) / 64)
    }

    /// `value` as the `index`-th frame played after priming.
    static func played(_ value: Int16, at index: Int) -> Int16 {
        index < 64 ? fadedIn(value, step: index) : value
    }

    @Test func primesUntilTheTargetIsBufferedThenPlays() {
        let ring = AudioRing(capacityFrames: 1024)
        ring.setTargetFrames(100)
        #expect(ring.counters.primes == 1, "A new ring starts priming")

        Self.write(ring, from: 1001, count: 60)
        let silent = Self.render(ring, count: 32)
        #expect(silent.isSilence)
        #expect(silent.frames.allSatisfy { $0 == (0, 0) })
        #expect(ring.counters.bufferedFrames == 60, "Priming consumes nothing")
        #expect(ring.state == .priming)

        Self.write(ring, from: 1061, count: 60)
        let playing = Self.render(ring, count: 32)
        #expect(!playing.isSilence)
        #expect(playing.frames.map(\.0) == (0..<32).map { Self.played(1001 + Int16($0), at: $0) })
        #expect(playing.frames.map(\.1) == (0..<32).map { Self.played(-1001 - Int16($0), at: $0) })
        #expect(ring.state == .playing)
        #expect(ring.counters.bufferedFrames == 88)
        #expect(ring.counters.underruns == 0)
    }

    @Test func startsPlayingWithAFadeInOverSixtyFourFrames() {
        let ring = AudioRing(capacityFrames: 1024)
        ring.setTargetFrames(10)
        let level: Int16 = 6400
        _ = ring.write([Int16](repeating: level, count: 2 * 100).span)

        // The fade continues across render calls.
        let played = Self.render(ring, count: 40).frames + Self.render(ring, count: 60).frames
        #expect(played.prefix(64).map(\.0) == (0..<64).map { Self.fadedIn(level, step: $0) })
        #expect(played.prefix(64).map(\.1) == (0..<64).map { Self.fadedIn(level, step: $0) })
        #expect(played[0].0 == 100, "The first frame keeps 1/64 of the level")
        #expect(played[63...].allSatisfy { $0 == (level, level) })
        #expect(ring.counters.underruns == 0)
    }

    @Test func anUnderrunFadesOutOverSixtyFourFramesAndPrimesAgain() {
        let ring = AudioRing(capacityFrames: 1024)
        ring.setTargetFrames(10)
        // A constant level makes the fade easy to follow. The first 64 frames
        // are the fade-in after priming, then 20 frames at the full level.
        let level: Int16 = 6400
        _ = ring.write([Int16](repeating: level, count: 2 * 84).span)
        _ = Self.render(ring, count: 64)

        let first = Self.render(ring, count: 100)
        #expect(first.frames.prefix(20).allSatisfy { $0 == (level, level) })
        // Frames 20 to 83 fade from 63/64 of the level to zero, then silence.
        let fade = first.frames[20..<84].map(\.0)
        let expected = (0..<64).map { Int16(Int32(level) * Int32(63 - $0) / 64) }
        #expect(fade == expected)
        #expect(first.frames[84...].allSatisfy { $0 == (0, 0) })

        let counters = ring.counters
        #expect(counters.underruns == 1)
        #expect(counters.underrunFrames == 80)
        #expect(counters.primes == 2)
        #expect(ring.state == .priming)
        #expect(Self.render(ring, count: 16).isSilence)
    }

    @Test func aFadeLongerThanOneCallContinuesInTheNext() {
        let ring = AudioRing(capacityFrames: 1024)
        ring.setTargetFrames(4)
        // 64 frames for the fade-in after priming, then 4 at the full level.
        _ = ring.write([Int16](repeating: 6400, count: 2 * 68).span)
        _ = Self.render(ring, count: 64)
        let first = Self.render(ring, count: 10)
        let second = Self.render(ring, count: 70)
        let fade: [Int16] = first.frames[4...].map(\.0) + second.frames.prefix(58).map(\.0)
        let expected: [Int16] = (0..<64).map { step in Int16(6400 * (63 - step) / 64) }
        #expect(fade == expected)
        #expect(second.frames[58...].allSatisfy { $0 == (0, 0) })
        #expect(ring.counters.underruns == 1)
    }

    @Test func suspendedPlaysSilenceWithoutConsumingOrCounting() {
        let ring = AudioRing(capacityFrames: 1024)
        ring.setTargetFrames(8)
        Self.write(ring, from: 1001, count: 64)
        _ = Self.render(ring, count: 16)
        #expect(ring.state == .playing)

        ring.setSuspended(true)
        let suspended = Self.render(ring, count: 200)
        #expect(ring.state == .suspended)
        #expect(ring.counters.bufferedFrames == 48, "Suspended consumes nothing")
        #expect(ring.counters.underruns == 0)
        #expect(suspended.frames[64...].allSatisfy { $0 == (0, 0) }, "Only the fade-out is not silent")

        ring.setSuspended(false)
        let resumed = Self.render(ring, count: 16)
        #expect(resumed.frames.map(\.0) == (0..<16).map { Self.fadedIn(1017 + Int16($0), step: $0) },
                "After the suspension the buffered frames play on and fade in")
        #expect(ring.counters.primes == 2)
        #expect(ring.counters.underruns == 0)
    }

    @Test func aFlushDropsWhatIsBufferedAndPrimesAgain() {
        let ring = AudioRing(capacityFrames: 1024)
        ring.setTargetFrames(8)
        Self.write(ring, from: 1, count: 64)
        _ = Self.render(ring, count: 16)
        ring.requestFlush()
        let flushed = Self.render(ring, count: 16)
        #expect(ring.counters.bufferedFrames == 0)
        #expect(ring.state == .priming)
        #expect(ring.counters.underruns == 0, "Priming after a flush is not an underrun")
        #expect(flushed.frames.allSatisfy { $0.0 >= 0 })

        Self.write(ring, from: 1000, count: 8)
        #expect(Self.render(ring, count: 4).frames.map(\.0) == (0..<4).map { Self.fadedIn(1000 + Int16($0), step: $0) })
    }

    @Test func dropsAndCountsWhatDoesNotFit() {
        let ring = AudioRing(capacityFrames: 64)
        let status = Self.write(ring, from: 1, count: 100)
        #expect(status.bufferedFrames == 64)
        #expect(ring.counters.droppedFrames == 36)
        #expect(!status.isConsuming)
    }

    @Test func keepsTheOrderAcrossTheEndOfTheStorage() {
        let ring = AudioRing(capacityFrames: 64)
        ring.setTargetFrames(1)
        var next: Int16 = 1001
        var expected: Int16 = 1001
        var playedSoFar = 0
        for _ in 0..<50 {
            Self.write(ring, from: next, count: 40)
            next &+= 40
            let played = Self.render(ring, count: 40).frames
            #expect(played.map(\.0) == (0..<40).map { Self.played(expected &+ Int16($0), at: playedSoFar + $0) })
            #expect(played.map(\.1) == (0..<40).map { Self.played(0 &- (expected &+ Int16($0)), at: playedSoFar + $0) })
            expected &+= 40
            playedSoFar += 40
        }
        #expect(ring.counters.underruns == 0)
        #expect(ring.counters.droppedFrames == 0)
    }

    @Test func countsRenderCallsAndTheLargestRequest() {
        let ring = AudioRing(capacityFrames: 1024)
        _ = Self.render(ring, count: 128)
        _ = Self.render(ring, count: 512)
        _ = Self.render(ring, count: 256)
        let counters = ring.counters
        #expect(counters.renderCalls == 3)
        #expect(counters.largestRequest == 512)
    }

    @Test func reportsConsumingOnlyWhilePlaying() {
        let ring = AudioRing(capacityFrames: 1024)
        ring.setTargetFrames(16)
        #expect(Self.write(ring, from: 1, count: 32).isConsuming == false, "Nothing rendered yet")
        _ = Self.render(ring, count: 8)
        let status = Self.write(ring, from: 33, count: 8)
        #expect(status.isConsuming)
        #expect(status.targetFrames == 16)
        #expect(status.bufferedFrames == 32)
        ring.setSuspended(true)
        _ = Self.render(ring, count: 8)
        #expect(Self.write(ring, from: 41, count: 8).isConsuming == false)
    }

    @Test func clampsTheTargetToHalfTheCapacity() {
        let ring = AudioRing(capacityFrames: 1024)
        ring.setTargetFrames(5000)
        #expect(ring.counters.targetFrames == 512)
    }

    /// The emulation thread and the render thread at full speed: every frame
    /// that comes out of the ring follows the one before, no jumps, no
    /// swapped channels. Right is left XOR 0x5A5A, which silence and faded
    /// frames do not satisfy. After an underrun the ring fades out, primes and
    /// fades in again, so the next full frame comes 64 frames on; a faded
    /// frame that satisfies the relation by chance is recognised by its formula.
    @Test func noJumpsUnderLoad() {
        let ring = AudioRing(capacityFrames: 8192)
        ring.setTargetFrames(1024)
        let stop = Atomic<Bool>(false)
        let producer = Thread {
            var next: Int16 = 1
            var chunk = [Int16](repeating: 0, count: 2 * 549)
            while !stop.load(ordering: .relaxed) {
                // Stay below the capacity, like real-time pacing does.
                guard ring.counters.bufferedFrames < 4096 else { continue }
                for frame in 0..<549 {
                    chunk[2 * frame] = next
                    chunk[2 * frame + 1] = next ^ 0x5A5A
                    next &+= 1
                }
                _ = ring.write(chunk.span)
            }
        }
        producer.start()

        var output = [UInt32](repeating: 0, count: 256)
        var checked = 0
        var jumps = 0
        var last: (left: Int16, right: Int16)?
        // Frames outside the sequence (fades, silence) came since `last`.
        var sawGap = false
        let end = Date.now.addingTimeInterval(1.5)
        while Date.now < end {
            output.withUnsafeMutableBufferPointer { buffer in
                _ = ring.renderForTesting(into: buffer.baseAddress!, frames: buffer.count)
            }
            for frame in output {
                let left = Int16(truncatingIfNeeded: frame & 0xFFFF)
                let right = Int16(truncatingIfNeeded: frame >> 16)
                guard right == left ^ 0x5A5A else {
                    sawGap = true
                    continue
                }
                if let last, left != last.left &+ 1 {
                    let afterFadeIn = sawGap && left == last.left &+ 64
                    if !afterFadeIn {
                        if Self.isFade(left: left, right: right, from: last)
                            || Self.isFadeIn(left: left, right: right, after: last)
                        {
                            continue
                        }
                        jumps += 1
                    }
                }
                last = (left, right)
                sawGap = false
                checked += 1
            }
        }
        stop.store(true, ordering: .relaxed)

        #expect(checked > 100_000)
        #expect(jumps == 0)
        #expect(ring.counters.droppedFrames == 0)
    }

    /// Whether a frame is one of the 64 fade-out frames after `last`.
    static func isFade(left: Int16, right: Int16, from last: (left: Int16, right: Int16)) -> Bool {
        (0..<64).contains { step in
            Int32(left) == Int32(last.left) * Int32(63 - step) / 64
                && Int32(right) == Int32(last.right) * Int32(63 - step) / 64
        }
    }

    /// Whether a frame is one of the 63 faded-in frames that follow `last`
    /// once the ring plays again after priming.
    static func isFadeIn(left: Int16, right: Int16, after last: (left: Int16, right: Int16)) -> Bool {
        (0..<63).contains { step in
            let value = last.left &+ 1 &+ Int16(step)
            return left == fadedIn(value, step: step) && right == fadedIn(value ^ 0x5A5A, step: step)
        }
    }
}
