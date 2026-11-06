import Darwin

/// Host time in `mach_absolute_time` ticks, the time base of `FrameStamp`,
/// `CACurrentMediaTime` and `AudioTimeStamp.mHostTime`.
enum HostTime {
    /// Ticks per nanosecond as numerator and denominator (`mach_timebase_info`).
    static let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    /// Ticks in one second, 24 000 000 on Apple silicon.
    static let ticksPerSecond = 1_000_000_000 * Double(timebase.denom) / Double(timebase.numer)

    static func now() -> UInt64 {
        mach_absolute_time()
    }

    static func nanoseconds(fromTicks ticks: UInt64) -> Int64 {
        Int64(Double(ticks) * Double(timebase.numer) / Double(timebase.denom))
    }

    static func ticks(fromSeconds seconds: Double) -> UInt64 {
        UInt64(max(0, (seconds * ticksPerSecond).rounded()))
    }

    /// Sleeps until `deadline` with `mach_wait_until`, which wakes at an absolute
    /// time and so never accumulates the error of relative sleeps (ADR 0005).
    static func wait(until deadline: UInt64) {
        while mach_absolute_time() < deadline {
            mach_wait_until(deadline)
        }
    }
}
