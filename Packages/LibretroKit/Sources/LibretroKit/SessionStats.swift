import Synchronization

/// Measurements of the emulation thread. The thread publishes them about once
/// per second with relaxed atomic stores; reading never blocks it.
public final class SessionStats: Sendable {
    /// One reading of all values.
    public struct Snapshot: Sendable, Hashable {
        /// `retro_run` calls since `load()`.
        public var framesEmulated: UInt64
        /// Frames emulated per second over the last interval.
        public var framesPerSecond: Double
        /// Frames that started more than 2 ms after their deadline.
        public var lateFrames: UInt64
        /// Times the clock fell more than three frames behind and restarted
        /// its schedule from now instead of catching up.
        public var resyncs: UInt64
        /// Duration of the last `retro_run` call.
        public var lastRunTime: Duration
        /// Longest `retro_run` call in the last interval.
        public var maxRunTime: Duration
        /// Largest delay of a frame start behind its deadline in the last interval.
        public var maxLateness: Duration
        /// The relative correction of the frame period, within ±0.005.
        /// Positive values lengthen the period (the audio buffer is too full).
        public var periodTrim: Double

        public init(
            framesEmulated: UInt64,
            framesPerSecond: Double,
            lateFrames: UInt64,
            resyncs: UInt64,
            lastRunTime: Duration,
            maxRunTime: Duration,
            maxLateness: Duration,
            periodTrim: Double
        ) {
            self.framesEmulated = framesEmulated
            self.framesPerSecond = framesPerSecond
            self.lateFrames = lateFrames
            self.resyncs = resyncs
            self.lastRunTime = lastRunTime
            self.maxRunTime = maxRunTime
            self.maxLateness = maxLateness
            self.periodTrim = periodTrim
        }
    }

    // One writer (the emulation thread), any number of readers. Each value is
    // its own relaxed atomic, so a snapshot can mix two publications; for an
    // overlay that reads four times a second this does not matter.
    private let framesEmulated = Atomic<UInt64>(0)
    private let framesPerSecondBits = Atomic<UInt64>(0)
    private let lateFrames = Atomic<UInt64>(0)
    private let resyncs = Atomic<UInt64>(0)
    private let lastRunNanoseconds = Atomic<Int64>(0)
    private let maxRunNanoseconds = Atomic<Int64>(0)
    private let maxLatenessNanoseconds = Atomic<Int64>(0)
    private let periodTrimBits = Atomic<UInt64>(0)

    init() {}

    /// The latest published values.
    public func snapshot() -> Snapshot {
        Snapshot(
            framesEmulated: framesEmulated.load(ordering: .relaxed),
            framesPerSecond: Double(bitPattern: framesPerSecondBits.load(ordering: .relaxed)),
            lateFrames: lateFrames.load(ordering: .relaxed),
            resyncs: resyncs.load(ordering: .relaxed),
            lastRunTime: .nanoseconds(lastRunNanoseconds.load(ordering: .relaxed)),
            maxRunTime: .nanoseconds(maxRunNanoseconds.load(ordering: .relaxed)),
            maxLateness: .nanoseconds(maxLatenessNanoseconds.load(ordering: .relaxed)),
            periodTrim: Double(bitPattern: periodTrimBits.load(ordering: .relaxed))
        )
    }

    /// Emulation thread: publishes new values. No locks, no allocation.
    func publish(
        framesEmulated: UInt64,
        framesPerSecond: Double,
        lateFrames: UInt64,
        resyncs: UInt64,
        lastRunNanoseconds: Int64,
        maxRunNanoseconds: Int64,
        maxLatenessNanoseconds: Int64,
        periodTrim: Double
    ) {
        self.framesEmulated.store(framesEmulated, ordering: .relaxed)
        framesPerSecondBits.store(framesPerSecond.bitPattern, ordering: .relaxed)
        self.lateFrames.store(lateFrames, ordering: .relaxed)
        self.resyncs.store(resyncs, ordering: .relaxed)
        self.lastRunNanoseconds.store(lastRunNanoseconds, ordering: .relaxed)
        self.maxRunNanoseconds.store(maxRunNanoseconds, ordering: .relaxed)
        self.maxLatenessNanoseconds.store(maxLatenessNanoseconds, ordering: .relaxed)
        periodTrimBits.store(periodTrim.bitPattern, ordering: .relaxed)
    }
}
