/// Plans when each frame starts (ADR 0005, section 3).
///
/// Deadlines are absolute host times: the next one is the previous one plus
/// the period, kept with its fractional tick, so the schedule never drifts.
/// A frame that starts late does not move the schedule; the following frames
/// run without waiting until the clock has caught up. Only when the thread is
/// more than three periods behind (background, debugger) does the schedule
/// restart from now, which `resyncs` counts.
///
/// The emulation follows the audio clock: a PI controller on the fill level
/// of the audio buffer trims the period by at most ±0.5 %. Without a consuming
/// audio output the trim decays to 0 and the clock runs at the nominal rate.
///
/// A value type without a clock of its own: the caller passes the time, so
/// tests can drive it with simulated time.
struct FrameClock {
    /// The plan for one frame.
    struct Plan: Hashable {
        /// The planned start of the frame, `FrameStamp.nominalTime`.
        var deadline: UInt64
        /// The caller has to wait until `deadline` before it runs the frame.
        var shouldWait: Bool
        /// Ticks the frame starts after its deadline, 0 if it is on time.
        var lateness: UInt64
        /// The schedule restarted from now because the thread fell behind.
        var resynchronized: Bool
    }

    /// The largest relative change of the period.
    static let maximumTrim = 0.005
    /// The bound of the controller's integral term.
    static let integralLimit = 0.5
    static let proportionalGain = 0.05
    static let integralGain = 0.005
    /// Further behind than this many periods, the schedule restarts from now.
    static let resyncPeriods = 3.0
    /// Factor per frame by which the trim decays while no output consumes.
    static let trimDecay = 0.95

    let pacing: Pacing
    /// The nominal period in seconds, `1 / framesPerSecond`.
    let period: Double
    /// The nominal period in host ticks.
    let periodTicks: Double
    /// Audio frames per second of the core, to turn the buffer error into seconds.
    let sampleRate: Double

    /// The planned start of the next frame.
    private(set) var deadline: UInt64
    /// The fractional tick of `deadline`, in 0..<1.
    private var fraction = 0.0
    /// The current relative correction of the period; positive is longer.
    private(set) var trim = 0.0
    /// The integral term of the controller, in seconds of buffer error times seconds.
    private(set) var integral = 0.0
    /// Times the schedule restarted from now.
    private(set) var resyncs: UInt64 = 0

    init(framesPerSecond: Double, sampleRate: Double, ticksPerSecond: Double, pacing: Pacing, start: UInt64) {
        precondition(framesPerSecond > 0 && ticksPerSecond > 0, "The clock needs a positive frame rate and time base")
        self.pacing = pacing
        period = 1 / framesPerSecond
        periodTicks = ticksPerSecond / framesPerSecond
        self.sampleRate = sampleRate
        deadline = start
    }

    /// Starts the schedule again at `now`, for example after a pause.
    mutating func restart(at now: UInt64) {
        deadline = now
        fraction = 0
    }

    /// Plans the next frame at time `now`. With `.unthrottled` every frame
    /// starts at once.
    mutating func beginFrame(now: UInt64) -> Plan {
        guard pacing == .realTime else {
            return Plan(deadline: now, shouldWait: false, lateness: 0, resynchronized: false)
        }
        if now < deadline {
            return Plan(deadline: deadline, shouldWait: true, lateness: 0, resynchronized: false)
        }
        let lateness = now - deadline
        if Double(lateness) > Self.resyncPeriods * periodTicks {
            restart(at: now)
            resyncs += 1
            return Plan(deadline: now, shouldWait: false, lateness: 0, resynchronized: true)
        }
        return Plan(deadline: deadline, shouldWait: false, lateness: lateness, resynchronized: false)
    }

    /// Ends the frame: updates the trim from the audio buffer and plans the
    /// next deadline.
    ///
    /// - Parameters:
    ///   - audio: The state the sink reported after the frame's last write,
    ///     nil if the frame wrote nothing.
    ///   - writtenFrames: Audio frames the frame wrote. The controller steers
    ///     the level before them, the low point of the buffer just before new
    ///     sound arrives, to `targetFrames`. Steering the level right after
    ///     the writes instead would leave only the target minus one frame of
    ///     sound as reserve (ADR 0005).
    mutating func endFrame(audio: AudioBufferStatus?, writtenFrames: Int = 0) {
        guard pacing == .realTime else { return }
        if let audio, audio.isConsuming, sampleRate > 0 {
            // Seconds of audio the buffer held above its target level before
            // this frame's sound arrived.
            let error = Double(audio.bufferedFrames - writtenFrames - audio.targetFrames) / sampleRate
            integral = min(max(integral + error * period, -Self.integralLimit), Self.integralLimit)
            let correction = Self.proportionalGain * error + Self.integralGain * integral
            trim = min(max(correction, -Self.maximumTrim), Self.maximumTrim)
        } else {
            trim *= Self.trimDecay
        }
        let step = periodTicks * (1 + trim) + fraction
        let whole = step.rounded(.down)
        deadline += UInt64(whole)
        fraction = step - whole
    }
}
