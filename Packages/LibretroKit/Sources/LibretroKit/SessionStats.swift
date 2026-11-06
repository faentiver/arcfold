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

    /// The latest published values.
    public func snapshot() -> Snapshot {
        fatalError("M1 track K")
    }
}
