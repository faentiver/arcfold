@testable import LibretroKit
import Testing

/// The frame clock with simulated time (ADR 0005, section 3): the schedule,
/// catching up, resynchronization and the controller that follows the audio clock.
struct FrameClockTests {
    /// Host ticks per second on Apple silicon.
    static let ticksPerSecond = 24_000_000.0
    /// The GBA frame rate, 2^24 / 280 896 (mGBA reports 59.7275009155).
    static let framesPerSecond = 16_777_216.0 / 280_896.0
    static let sampleRate = 32_768.0

    static func clock(pacing: Pacing = .realTime, start: UInt64 = 1_000_000) -> FrameClock {
        FrameClock(
            framesPerSecond: framesPerSecond, sampleRate: sampleRate,
            ticksPerSecond: ticksPerSecond, pacing: pacing, start: start
        )
    }

    @Test func scheduleDoesNotDriftOverAMillionFrames() {
        let start: UInt64 = 1_000_000
        var clock = Self.clock(start: start)
        var waits = 0
        for _ in 0..<1_000_000 {
            let plan = clock.beginFrame(now: clock.deadline - 1)
            if plan.shouldWait { waits += 1 }
            clock.endFrame(audio: nil)
        }
        let expected = Double(start) + 1_000_000 * clock.periodTicks
        #expect(abs(Double(clock.deadline) - expected) <= 1)
        #expect(waits == 1_000_000)
        #expect(clock.resyncs == 0)
        // 10^6 GBA frames last 4 h 39 min.
        #expect(abs(Double(clock.deadline - start) / Self.ticksPerSecond - 1_000_000 / Self.framesPerSecond) < 1e-6)
    }

    @Test func lateFramesCatchUpWithoutMovingTheSchedule() {
        var clock = Self.clock(start: 0)
        let period = clock.periodTicks
        for _ in 0..<10 {
            _ = clock.beginFrame(now: clock.deadline)
            clock.endFrame(audio: nil)
        }
        // Frame 10 starts 2.5 periods late, for example after a hitch.
        let gridTen = clock.deadline
        let lateStart = gridTen + UInt64(2.5 * period)
        let late = clock.beginFrame(now: lateStart)
        #expect(!late.shouldWait)
        #expect(!late.resynchronized)
        #expect(late.deadline == gridTen)
        #expect(late.lateness == lateStart - gridTen)
        clock.endFrame(audio: nil)

        // Each following frame takes 2 ms; frames start at once until the clock caught up.
        var now = lateStart + UInt64(0.002 * Self.ticksPerSecond)
        var framesWithoutWaiting = 0
        for frame in 11..<40 {
            let plan = clock.beginFrame(now: now)
            // The deadlines stay on the original grid.
            #expect(abs(Double(plan.deadline) - Double(frame) * period) <= 1)
            if plan.shouldWait {
                now = plan.deadline
            } else {
                framesWithoutWaiting += 1
            }
            clock.endFrame(audio: nil)
            now += UInt64(0.002 * Self.ticksPerSecond)
        }
        #expect(framesWithoutWaiting > 0)
        #expect(framesWithoutWaiting <= 3)
        #expect(clock.resyncs == 0)
    }

    @Test func fallingMoreThanThreePeriodsBehindRestartsTheSchedule() {
        var clock = Self.clock(start: 0)
        let period = clock.periodTicks
        for _ in 0..<5 {
            _ = clock.beginFrame(now: clock.deadline)
            clock.endFrame(audio: nil)
        }
        // A stall of 3.5 periods, for example in the debugger.
        let now = clock.deadline + UInt64(3.5 * period)
        let plan = clock.beginFrame(now: now)
        #expect(plan.resynchronized)
        #expect(!plan.shouldWait)
        #expect(plan.deadline == now)
        #expect(plan.lateness == 0)
        #expect(clock.resyncs == 1)
        clock.endFrame(audio: nil)
        // The new schedule starts at the stall's end.
        #expect(abs(Double(clock.deadline) - (Double(now) + period)) <= 1)
        let next = clock.beginFrame(now: now + 1000)
        #expect(next.shouldWait)
    }

    @Test func exactlyThreePeriodsLateStillCatchesUp() {
        var clock = Self.clock(start: 0)
        let deadline = clock.deadline
        let plan = clock.beginFrame(now: deadline + UInt64(3 * clock.periodTicks))
        #expect(!plan.resynchronized)
        #expect(clock.resyncs == 0)
    }

    @Test func unthrottledNeverWaits() {
        var clock = Self.clock(pacing: .unthrottled, start: 5_000)
        for now: UInt64 in [0, 10, 20, 1_000_000] {
            let plan = clock.beginFrame(now: now)
            #expect(!plan.shouldWait)
            #expect(plan.deadline == now)
            clock.endFrame(audio: AudioBufferStatus(bufferedFrames: 100_000, targetFrames: 0, isConsuming: true))
        }
        #expect(clock.trim == 0)
    }

    @Test func trimIsLimitedToHalfAPercent() {
        var clock = Self.clock()
        // Ten seconds of audio too much: the period gets longer, at most 0.5 %.
        for _ in 0..<200 {
            _ = clock.beginFrame(now: clock.deadline)
            clock.endFrame(audio: AudioBufferStatus(bufferedFrames: 330_000, targetFrames: 1_000, isConsuming: true))
            #expect(abs(clock.trim) <= FrameClock.maximumTrim)
        }
        #expect(clock.trim == FrameClock.maximumTrim)
        #expect(clock.integral <= FrameClock.integralLimit)

        var starving = Self.clock()
        for _ in 0..<200 {
            _ = starving.beginFrame(now: starving.deadline)
            starving.endFrame(audio: AudioBufferStatus(bufferedFrames: 0, targetFrames: 330_000, isConsuming: true))
        }
        #expect(starving.trim == -FrameClock.maximumTrim)

        // The period changes by the trim: 0.5 % longer.
        var limited = Self.clock(start: 0)
        _ = limited.beginFrame(now: 0)
        limited.endFrame(audio: AudioBufferStatus(bufferedFrames: 330_000, targetFrames: 1_000, isConsuming: true))
        #expect(abs(Double(limited.deadline) - limited.periodTicks * 1.005) <= 1)
    }

    @Test func trimDecaysWhileTheOutputDoesNotConsume() {
        var clock = Self.clock()
        // 20 ms too much audio for a second: the trim grows.
        for _ in 0..<60 {
            _ = clock.beginFrame(now: clock.deadline)
            clock.endFrame(audio: AudioBufferStatus(bufferedFrames: 1_800, targetFrames: 1_145, isConsuming: true))
        }
        let trimmed = clock.trim
        #expect(trimmed > 0.0009)
        // Priming or suspended: the clock returns to the nominal rate.
        for _ in 0..<60 {
            _ = clock.beginFrame(now: clock.deadline)
            clock.endFrame(audio: AudioBufferStatus(bufferedFrames: 1_800, targetFrames: 1_145, isConsuming: false))
        }
        #expect(clock.trim < trimmed * 0.05)
        // No audio at all decays the same way.
        for _ in 0..<60 {
            _ = clock.beginFrame(now: clock.deadline)
            clock.endFrame(audio: nil)
        }
        #expect(clock.trim < trimmed * 0.003)
        #expect(clock.trim >= 0)
    }

    /// The emulation follows an audio device whose clock runs `drift` faster
    /// than the host clock, for 10 simulated minutes, as in the simulation of
    /// the design "Echtzeit robust": no underrun, and the trim settles on the drift.
    @Test(arguments: [-500.0, -100.0, 100.0, 500.0])
    func controllerFollowsTheAudioClock(driftPPM: Double) {
        let result = AudioClockSimulation(driftPPM: driftPPM, seconds: 600).run()
        #expect(result.underruns == 0)
        #expect(result.largestTrim <= FrameClock.maximumTrim)
        #expect(result.resyncs == 0)
        // A device that consumes faster needs a shorter period, so the trim is negative.
        let expectedTrim = -driftPPM * 1e-6
        #expect(abs(result.meanTrimSecondHalf - expectedTrim) < 0.1 * abs(expectedTrim),
                "mean trim \(result.meanTrimSecondHalf * 1e6) ppm for \(driftPPM) ppm drift")
        // The fill level stays well clear of an underrun.
        #expect(result.lowestFillWhilePlaying > 0)
    }
}

/// An emulation thread paced by `FrameClock` that writes 548.6 audio frames per
/// emulated frame into a buffer, and a device that pulls 256 frames at 48 kHz
/// on a clock `driftPPM` off the host clock, without ever pausing. Run times
/// vary between 1.5 and 3.5 ms with rare spikes up to 15.5 ms. The buffer fills
/// to 35 ms before the device starts and again after an underrun (priming).
struct AudioClockSimulation {
    struct Result {
        var underruns = 0
        var largestTrim = 0.0
        var meanTrimSecondHalf = 0.0
        var lowestFillWhilePlaying = Double.infinity
        var resyncs: UInt64 = 0
    }

    let driftPPM: Double
    let seconds: Double

    func run() -> Result {
        let ticksPerSecond = FrameClockTests.ticksPerSecond
        let sampleRate = FrameClockTests.sampleRate
        let framesPerSecond = FrameClockTests.framesPerSecond
        var clock = FrameClock(
            framesPerSecond: framesPerSecond, sampleRate: sampleRate,
            ticksPerSecond: ticksPerSecond, pacing: .realTime, start: 0
        )
        let deviceRate = 48_000.0
        let ioFrames = 256.0
        let ioPeriod = ioFrames / deviceRate / (1 + driftPPM * 1e-6) * ticksPerSecond
        let framesPerIO = ioFrames * sampleRate / deviceRate
        let perFrame = sampleRate / framesPerSecond
        let target = 0.035 * sampleRate
        let end = UInt64(seconds * ticksPerSecond)

        var random = SplitMix64(seed: 3)
        var result = Result()
        var fill = 0.0
        var priming = true
        var nextIO = ioPeriod
        var produced = 0.0
        var consumed = 0.0
        var now: UInt64 = 0
        var trimSum = 0.0
        var trimCount = 0
        while now < end {
            let plan = clock.beginFrame(now: now)
            let start = plan.shouldWait ? plan.deadline : now
            var run = random.uniform(0.0015, 0.0035)
            if random.uniform(0, 1) < 0.002 {
                run += random.uniform(0.004, 0.012)
            }
            let completion = start + UInt64(run * ticksPerSecond)
            // The device pulls on its own clock until this frame's write lands.
            while nextIO <= Double(completion) {
                consumed += framesPerIO
                let request = consumed.rounded(.down)
                consumed -= request
                if priming, fill >= target {
                    priming = false
                }
                if !priming {
                    if fill >= request {
                        fill -= request
                        result.lowestFillWhilePlaying = min(result.lowestFillWhilePlaying, fill)
                    } else {
                        result.underruns += 1
                        fill = 0
                        priming = true
                    }
                }
                nextIO += ioPeriod
            }
            produced += perFrame
            let amount = produced.rounded(.down)
            produced -= amount
            fill += amount
            clock.endFrame(audio: AudioBufferStatus(
                bufferedFrames: Int(fill), targetFrames: Int(target + perFrame), isConsuming: !priming
            ))
            result.largestTrim = max(result.largestTrim, abs(clock.trim))
            if Double(completion) > seconds / 2 * ticksPerSecond {
                trimSum += clock.trim
                trimCount += 1
            }
            now = completion
        }
        result.meanTrimSecondHalf = trimSum / Double(max(trimCount, 1))
        result.resyncs = clock.resyncs
        return result
    }
}

/// A small, fast pseudo random generator with a fixed seed (SplitMix64).
struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }

    /// A uniformly distributed value in `lower..<upper`.
    mutating func uniform(_ lower: Double, _ upper: Double) -> Double {
        lower + (upper - lower) * Double(next() >> 11) / Double(1 << 53)
    }
}
