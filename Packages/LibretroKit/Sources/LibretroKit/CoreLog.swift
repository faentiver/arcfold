internal import CLibretro
import Darwin
import os
import Synchronization

/// Where the log lines of cores go: `os.Logger` with subsystem
/// `com.faentiver.arcfold` and category `core`, rate limited.
///
/// The C shim in CLibretro (`arcfold_log.h`) only calls the sink for lines at
/// or above the minimum level, RETRO_LOG_WARN by default; below it, lines are
/// only counted. Above it, at most `RateLimiter.linesPerSecond` lines per
/// second reach the log, and the number of dropped lines follows the next one.
enum CoreLog {
    private static let logger = Logger(subsystem: "com.faentiver.arcfold", category: "core")
    private static let limiter = Mutex(RateLimiter(ticksPerSecond: HostTime.ticksPerSecond))

    /// Connects the C shim to `os.Logger`. Idempotent.
    static func installSink() {
        arcfold_log_set_sink(sink)
    }

    /// Lines below the minimum level, since the process started.
    static var suppressedLines: UInt64 {
        arcfold_log_suppressed_lines()
    }

    private static let sink: arcfold_log_sink_t = { level, message in
        guard let message else { return }
        let decision = limiter.withLock { $0.admit(at: HostTime.now()) }
        guard case let .admitted(droppedBefore) = decision else { return }
        let text = String(cString: message)
        if droppedBefore > 0 {
            logger.notice("\(droppedBefore, privacy: .public) core log lines dropped by the rate limit")
        }
        switch level {
        case RETRO_LOG_ERROR:
            logger.error("\(text, privacy: .public)")
        case RETRO_LOG_WARN:
            logger.warning("\(text, privacy: .public)")
        case RETRO_LOG_INFO:
            logger.info("\(text, privacy: .public)")
        default:
            logger.debug("\(text, privacy: .public)")
        }
    }
}

/// Lets at most `linesPerSecond` lines through per second of host time.
struct RateLimiter {
    enum Decision: Hashable {
        /// Log the line; `droppedBefore` lines were dropped since the last one.
        case admitted(droppedBefore: Int)
        case dropped
    }

    static let linesPerSecond = 20

    let windowTicks: UInt64
    private var windowStart: UInt64?
    private var linesInWindow = 0
    private var dropped = 0

    init(ticksPerSecond: Double) {
        windowTicks = UInt64(ticksPerSecond)
    }

    mutating func admit(at now: UInt64) -> Decision {
        if let start = windowStart, now >= start, now - start < windowTicks {
            guard linesInWindow < Self.linesPerSecond else {
                dropped += 1
                return .dropped
            }
        } else {
            windowStart = now
            linesInWindow = 0
        }
        linesInWindow += 1
        defer { dropped = 0 }
        return .admitted(droppedBefore: dropped)
    }
}
