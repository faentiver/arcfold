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

    @Test func primesUntilTheTargetIsBufferedThenPlays() {
        let ring = AudioRing(capacityFrames: 1024)
        ring.setTargetFrames(100)
        #expect(ring.counters.primes == 1, "A new ring starts priming")

        Self.write(ring, from: 1, count: 60)
        let silent = Self.render(ring, count: 32)
        #expect(silent.isSilence)
        #expect(silent.frames.allSatisfy { $0 == (0, 0) })
        #expect(ring.counters.bufferedFrames == 60, "Priming consumes nothing")
        #expect(ring.state == .priming)

        Self.write(ring, from: 61, count: 60)
        let playing = Self.render(ring, count: 32)
        #expect(!playing.isSilence)
        #expect(playing.frames.map(\.0) == (1...32).map(Int16.init))
        #expect(playing.frames.map(\.1) == (1...32).map { -Int16($0) })
        #expect(ring.state == .playing)
        #expect(ring.counters.bufferedFrames == 88)
        #expect(ring.counters.underruns == 0)
    }

    @Test func anUnderrunFadesOutOverSixtyFourFramesAndPrimesAgain() {
        let ring = AudioRing(capacityFrames: 1024)
        ring.setTargetFrames(10)
        // A constant level makes the fade easy to follow.
        let level: Int16 = 6400
        _ = ring.write([Int16](repeating: level, count: 2 * 20).span)

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
        _ = ring.write([Int16](repeating: 6400, count: 2 * 4).span)
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
        Self.write(ring, from: 1, count: 64)
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
        #expect(resumed.frames.first?.0 == 17, "After the suspension the buffered frames play on")
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
        #expect(Self.render(ring, count: 4).frames.map(\.0) == [1000, 1001, 1002, 1003])
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
        var next: Int16 = 1
        var expected: Int16 = 1
        for _ in 0..<50 {
            Self.write(ring, from: next, count: 40)
            next &+= 40
            let played = Self.render(ring, count: 40).frames
            #expect(played.map(\.0) == (0..<40).map { expected &+ Int16($0) })
            #expect(played.map(\.1) == (0..<40).map { 0 &- (expected &+ Int16($0)) })
            expected &+= 40
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
    /// swapped channels. Right is left XOR 0x5A5A, which silence does not
    /// satisfy; a fade-out after an underrun is recognised by its formula.
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
        let end = Date.now.addingTimeInterval(1.5)
        while Date.now < end {
            output.withUnsafeMutableBufferPointer { buffer in
                _ = ring.renderForTesting(into: buffer.baseAddress!, frames: buffer.count)
            }
            for frame in output {
                let left = Int16(truncatingIfNeeded: frame & 0xFFFF)
                let right = Int16(truncatingIfNeeded: frame >> 16)
                guard right == left ^ 0x5A5A else { continue }
                if let last, left != last.left &+ 1 {
                    if Self.isFade(left: left, right: right, from: last) {
                        continue
                    }
                    jumps += 1
                }
                last = (left, right)
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
}
