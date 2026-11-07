import Foundation

/// How the emulation thread schedules frames.
public enum Pacing: Sendable, Hashable {
    /// At the core's frame rate, trimmed by at most ±0.5 % to follow the
    /// audio output (ADR 0005). For playing.
    case realTime
    /// Back to back without waiting, for tests and benchmarks.
    case unthrottled
}

/// Everything a session needs to run one game.
public struct SessionConfiguration: Sendable {
    /// The framework name of the core, for example `mgba_libretro`.
    public var coreName: String
    /// The bundle whose `Frameworks` folder holds the core.
    public var bundle: Bundle
    /// The game file. The app passes its own copy, never a security-scoped URL.
    public var game: URL
    /// The battery save of this game. Read before the first frame if it
    /// exists, written atomically while the game runs and when it pauses or stops.
    public var batterySave: URL
    /// Answer to `RETRO_ENVIRONMENT_GET_SYSTEM_DIRECTORY`. Arcfold ships no
    /// BIOS files, so it stays empty. Created on load if missing.
    public var systemDirectory: URL
    /// Answer to `RETRO_ENVIRONMENT_GET_SAVE_DIRECTORY`. Created on load if missing.
    public var saveDirectory: URL
    /// Values for `RETRO_ENVIRONMENT_GET_VARIABLE` that replace the core's
    /// defaults, for example `["mgba_use_bios": "OFF"]`.
    public var coreOptions: [String: String]
    public var pacing: Pacing

    public init(
        coreName: String,
        bundle: Bundle = .main,
        game: URL,
        batterySave: URL,
        systemDirectory: URL,
        saveDirectory: URL,
        coreOptions: [String: String] = [:],
        pacing: Pacing = .realTime
    ) {
        self.coreName = coreName
        self.bundle = bundle
        self.game = game
        self.batterySave = batterySave
        self.systemDirectory = systemDirectory
        self.saveDirectory = saveDirectory
        self.coreOptions = coreOptions
        self.pacing = pacing
    }
}

/// Where a session is in its life.
public enum SessionState: Sendable, Hashable {
    /// Created, `load()` not called yet.
    case idle
    /// `load()` is running on the emulation thread.
    case loading
    /// Loaded, no frame has run yet.
    case ready
    case running
    case paused
    /// `stop()` finished, or the core asked to shut down. The session cannot run again.
    case stopped
    /// `load()` failed. The session cannot run.
    case failed
}

/// Something the app may want to show or log. Delivered on `EmulationSession.events`.
public enum SessionEvent: Sendable, Hashable {
    /// The battery save was written to disk.
    case batterySaveWritten(bytes: Int)
    /// Writing the battery save failed. The previous file is still intact.
    case batterySaveFailed(reason: String)
    /// The core sent a message for the user (`RETRO_ENVIRONMENT_SET_MESSAGE`).
    case coreMessage(String)
    /// The core asked to end the session (`RETRO_ENVIRONMENT_SHUTDOWN`).
    case coreRequestedShutdown
}

/// Why a session could not load or save.
public enum SessionError: Error, Sendable, Hashable, CustomStringConvertible {
    /// Another session holds the only callback slot of the process
    /// (one active core per process, plan guardrail 3).
    case anotherSessionActive
    /// The core framework could not be loaded.
    case core(LibretroError)
    /// The core speaks another libretro API version than the host.
    case apiVersionMismatch(core: UInt32, host: UInt32)
    /// The game file could not be read.
    case unreadableGame(path: String, reason: String)
    /// `retro_load_game` returned false.
    case gameRejected
    /// The core uses a pixel format Arcfold cannot show.
    case unsupportedPixelFormat(PixelFormat)
    /// Reading or writing the battery save failed.
    case batterySave(reason: String)

    public var description: String {
        switch self {
        case .anotherSessionActive:
            "Another core is already running"
        case let .core(error):
            error.description
        case let .apiVersionMismatch(core, host):
            "The core uses libretro API version \(core), the host version \(host)"
        case let .unreadableGame(path, reason):
            "The game at \(path) could not be read: \(reason)"
        case .gameRejected:
            "The core did not accept the game"
        case let .unsupportedPixelFormat(format):
            "The core uses the unsupported pixel format \(format)"
        case let .batterySave(reason):
            "The battery save failed: \(reason)"
        }
    }
}

/// Diagnostics of a finished session, returned by `EmulationSession.stop()`.
public struct SessionSummary: Sendable, Hashable {
    /// `retro_run` calls since `load()`.
    public var framesEmulated: UInt64
    /// How often the core called each environment command (`RETRO_ENVIRONMENT_*`
    /// values as in libretro.h, including the experimental bit 0x10000).
    public var environmentCalls: [UInt32: Int]
    /// Commands the host refused because it does not support them: commands it
    /// does not know and those ADR 0005 lists as refused (for example
    /// `SET_MEMORY_MAPS`). Queries whose answer false is the expected reply
    /// (`GET_CORE_OPTIONS_VERSION`, `GET_JIT_CAPABLE`) do not count.
    public var unhandledEnvironmentCommands: Set<UInt32>

    public init(framesEmulated: UInt64, environmentCalls: [UInt32: Int], unhandledEnvironmentCommands: Set<UInt32>) {
        self.framesEmulated = framesEmulated
        self.environmentCalls = environmentCalls
        self.unhandledEnvironmentCommands = unhandledEnvironmentCommands
    }
}

/// One game running on its own emulation thread (ADR 0005).
///
/// The core is loaded, called and unloaded only on that thread; every method
/// here may be called from any isolation and never blocks the caller. Lifecycle:
/// `load()`, then `connect(video:audio:)`, then `resume()` and `pause()` as
/// often as needed, finally `stop()`. Only one session per process can be
/// loaded at a time, because libretro callbacks carry no context.
///
/// Commands reach the thread through a mailbox it checks once per frame, and
/// the async methods return once the thread has handled them at a frame
/// boundary. A session that is released without `stop()` stops on its own.
public final class EmulationSession: Sendable {
    private let control: SessionControl

    /// Creates the session. Nothing is loaded and no thread runs yet.
    public init(configuration: SessionConfiguration) {
        control = SessionControl(configuration: configuration)
        input = control.input
        stats = control.stats
        events = control.events
    }

    deinit {
        control.send(.stop(nil))
    }

    /// The buttons the core reads. Usable from creation on.
    public let input: InputState

    /// Measurements of the emulation thread, for the debug overlay.
    public let stats: SessionStats

    /// Events of this session. Meant for one consumer; finishes after `stop()`.
    /// While nobody reads, the newest 64 events are kept.
    public let events: AsyncStream<SessionEvent>

    /// The current state, read atomically.
    public var state: SessionState {
        control.state
    }

    /// Starts the emulation thread, loads core and game and copies the battery
    /// save into the core before the first frame. Ends in `.ready`, or in
    /// `.failed` when it throws. Call once; a second call traps.
    public func load() async throws(SessionError) -> SessionInfo {
        precondition(control.beginLoading(), "EmulationSession.load() may be called once, before stop()")
        let result = await withCheckedContinuation { continuation in
            EmulationThread.start(control: control, loaded: continuation)
        }
        return try result.get()
    }

    /// Sets where pictures and sound go. Call after `load()` and before the
    /// first frame; while paused it may replace the sinks. Without sinks,
    /// pictures and sound are dropped and the clock runs at the nominal rate.
    public func connect(video: any VideoSink, audio: any AudioSink) {
        control.send(.connect(video: video, audio: audio))
    }

    /// Runs frames with the configured pacing until `pause()` or `stop()`.
    /// Returns at once; after a pause the frame clock starts again from now.
    public func resume() {
        control.send(.resume)
    }

    /// Returns once the emulation thread stopped at a frame boundary and a
    /// changed battery save is on disk. A session that has not run a frame
    /// yet stays `.ready`.
    public func pause() async {
        await withCheckedContinuation { continuation in
            control.send(.pause(continuation))
        }
    }

    /// Runs exactly `count` frames as fast as possible and returns paused.
    /// Only while ready or paused; for tests. Commands sent meanwhile wait
    /// until the frames are done. The battery save is compared every 30
    /// frames as usual; `pause()` or `saveBatteryNow()` write it at once.
    public func runFrames(_ count: Int) async {
        await withCheckedContinuation { continuation in
            control.send(.runFrames(count, continuation))
        }
    }

    /// Writes the battery save now if it changed, for example before the app
    /// goes to the background.
    public func saveBatteryNow() async throws(SessionError) {
        let result = await withCheckedContinuation { continuation in
            control.send(.saveBattery(continuation))
        }
        try result.get()
    }

    /// Saves the battery save, unloads the game, deinitializes and closes the
    /// core and ends the thread. Ends in `.stopped`; safe to call in any state.
    public func stop() async -> SessionSummary {
        await withCheckedContinuation { continuation in
            control.send(.stop(continuation))
        }
    }
}
