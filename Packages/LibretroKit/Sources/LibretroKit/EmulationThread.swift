internal import CLibretro
import Foundation
import os

/// The emulation thread of one session (ADR 0005, section 3).
///
/// One `Thread` per session, created by `load()`. It loads the core and the
/// game, runs frames with its `FrameClock`, answers commands at frame
/// boundaries and finally unloads everything. The core (`LibretroCore`) is
/// created on this thread and never leaves it. Nothing here is shared: the
/// app reaches the thread only through `SessionControl`.
final class EmulationThread {
    static let name = "Arcfold Emulation"
    /// The stack of the emulation thread; cores recurse deeply in places.
    static let stackSize = 16 << 20

    private enum Mode {
        /// Ready or paused: sleeps until a command arrives.
        case idle
        /// Runs frames with the configured pacing.
        case running
        /// `runFrames`: the remaining frames, as fast as possible.
        case stepping(remaining: Int, CheckedContinuation<Void, Never>)
    }

    private static let logger = Logger(subsystem: "com.faentiver.arcfold", category: "session")
    /// Signposts for Instruments: the interval "retro_run" and the event "resync".
    private let signpostLog = OSLog(subsystem: "com.faentiver.arcfold", category: "emulation")
    private let signpostID: OSSignpostID

    private let control: SessionControl
    private var mode = Mode.idle
    /// Commands taken from the mailbox and not handled yet, in order.
    private var commands: [SessionCommand] = []
    private var stopContinuations: [CheckedContinuation<SessionSummary, Never>] = []
    private var stopRequested = false
    private var clock: FrameClock
    private var metrics = FrameMetrics(start: HostTime.now())
    /// `retro_run` calls since load; the sequence number of the last frame.
    private var framesEmulated: UInt64 = 0
    /// The mapped game file, valid until `retro_unload_game`.
    private var game: NSData?
    /// The path in `retro_game_info`, kept as long as the game.
    private var gamePath: UnsafeMutablePointer<CChar>?

    private init(control: SessionControl) {
        self.control = control
        signpostID = OSSignpostID(log: signpostLog)
        // Replaced once the core reports its timing.
        clock = FrameClock(
            framesPerSecond: 60, sampleRate: 0, ticksPerSecond: HostTime.ticksPerSecond,
            pacing: control.configuration.pacing, start: HostTime.now()
        )
    }

    deinit {
        free(gamePath)
    }

    /// Starts the thread. `loaded` is resumed once the session is `.ready`
    /// or has failed.
    static func start(control: SessionControl, loaded: CheckedContinuation<Result<SessionInfo, SessionError>, Never>) {
        let thread = Thread {
            EmulationThread(control: control).main(loaded: loaded)
        }
        thread.name = name
        thread.qualityOfService = .userInteractive
        thread.stackSize = stackSize
        thread.start()
    }

    // MARK: Lifecycle

    private func main(loaded: CheckedContinuation<Result<SessionInfo, SessionError>, Never>) {
        let configuration = control.configuration
        let context = CallbackContext(
            coreOptions: configuration.coreOptions,
            systemDirectory: configuration.systemDirectory,
            saveDirectory: configuration.saveDirectory,
            input: control.input,
            events: control.eventSink
        )
        do throws(SessionError) {
            try createDirectories(for: configuration)
        } catch {
            return fail(error, context: context, loaded: loaded)
        }
        // Before retro_set_environment: mGBA calls the environment from inside it.
        guard CallbackSlot.claim(context) else {
            return fail(.anotherSessionActive, context: context, loaded: loaded)
        }
        let core: LibretroCore
        do throws(LibretroError) {
            core = try LibretroCore(named: configuration.coreName, in: configuration.bundle)
        } catch {
            CallbackSlot.release(context)
            return fail(.core(error), context: context, loaded: loaded)
        }
        let info: SessionInfo
        let battery: BatterySaveMonitor
        do throws(SessionError) {
            (info, battery) = try load(core, context: context)
        } catch {
            CallbackSlot.release(context)
            return fail(error, context: context, loaded: loaded)
        }

        var timing = info.timing
        if !(timing.framesPerSecond > 0) {
            Self.logger.error("The core reports \(timing.framesPerSecond) frames per second; pacing at 60")
            timing.framesPerSecond = 60
        }
        clock = FrameClock(
            framesPerSecond: timing.framesPerSecond, sampleRate: timing.sampleRate,
            ticksPerSecond: HostTime.ticksPerSecond, pacing: configuration.pacing, start: HostTime.now()
        )
        control.setState(.ready)
        loaded.resume(returning: .success(info))

        runLoop(core, context: context, battery: battery)

        let summary = unload(core, context: context, battery: battery)
        // After retro_deinit no callback may arrive any more.
        CallbackSlot.release(context)
        _ = consume core // dlclose before anyone learns that the session ended
        finish(summary: summary)
    }

    /// Loads core and game and copies the battery save in. On failure
    /// everything loaded so far is unloaded again.
    private func load(
        _ core: borrowing LibretroCore, context: CallbackContext
    ) throws(SessionError) -> (SessionInfo, BatterySaveMonitor) {
        let configuration = control.configuration
        let apiVersion = core.apiVersion()
        guard apiVersion == LibretroCore.hostAPIVersion else {
            throw .apiVersionMismatch(core: apiVersion, host: LibretroCore.hostAPIVersion)
        }
        let system = core.systemInfo()
        core.installCallbacks(
            environment: CallbackSlot.environment,
            videoRefresh: CallbackSlot.videoRefresh,
            audioSample: CallbackSlot.audioSample,
            audioSampleBatch: CallbackSlot.audioSampleBatch,
            inputPoll: CallbackSlot.inputPoll,
            inputState: CallbackSlot.inputState
        )
        core.initialize()
        // Some cores rename the thread they are initialized on (PPSSPP).
        Thread.current.name = Self.name

        do throws(SessionError) {
            let game = try readGame(configuration.game)
            self.game = game
            gamePath = configuration.game.withUnsafeFileSystemRepresentation { path in path.flatMap { strdup($0) } }
            var gameInfo = retro_game_info(path: gamePath, data: game.bytes, size: game.length, meta: nil)
            guard core.loadGame(&gameInfo) else {
                throw .gameRejected
            }
            do throws(SessionError) {
                guard context.pixelFormat.isSupported else {
                    throw .unsupportedPixelFormat(context.pixelFormat)
                }
                let avInfo = core.systemAVInfo()
                let geometry = VideoGeometry(avInfo.geometry)
                context.sessionDidLoad(geometry: geometry)
                // Before the first retro_run: mGBA takes the contents of its
                // save memory in the first frame.
                let memory = core.saveMemory()
                let battery = BatterySaveMonitor(
                    url: configuration.batterySave, capacity: memory?.count ?? 0, events: control.eventSink
                )
                try battery.load(into: memory)
                let info = SessionInfo(
                    system: system, geometry: geometry, timing: AVTiming(avInfo.timing),
                    pixelFormat: context.pixelFormat
                )
                return (info, battery)
            } catch {
                core.unloadGame()
                throw error
            }
        } catch {
            self.game = nil
            core.deinitialize()
            throw error
        }
    }

    /// Saves, unloads the game and deinitializes the core.
    private func unload(
        _ core: borrowing LibretroCore, context: CallbackContext, battery: BatterySaveMonitor
    ) -> SessionSummary {
        // retro_unload_game frees the save memory, so the last save comes first.
        battery.saveNow(core.saveMemory().map(UnsafeRawBufferPointer.init)) { _ in }
        battery.waitUntilWritten()
        core.unloadGame()
        game = nil
        core.deinitialize()
        publishStats(at: HostTime.now())
        return SessionSummary(
            framesEmulated: framesEmulated,
            environmentCalls: context.environmentCalls,
            unhandledEnvironmentCommands: context.unhandledCommands
        )
    }

    /// Ends a session that ran: answers every waiting command and finishes the events.
    private func finish(summary: SessionSummary) {
        let unanswered = control.close(summary: summary, state: .stopped)
        if case let .stepping(_, continuation) = mode {
            continuation.resume()
        }
        for command in commands + unanswered {
            command.answerWithoutThread(summary: summary)
        }
        for continuation in stopContinuations {
            continuation.resume(returning: summary)
        }
        control.eventSink.finish()
    }

    /// Ends a session whose load failed.
    private func fail(
        _ error: SessionError, context: CallbackContext,
        loaded: CheckedContinuation<Result<SessionInfo, SessionError>, Never>
    ) {
        let summary = SessionSummary(
            framesEmulated: 0,
            environmentCalls: context.environmentCalls,
            unhandledEnvironmentCommands: context.unhandledCommands
        )
        let unanswered = control.close(summary: summary, state: .failed)
        loaded.resume(returning: .failure(error))
        for command in unanswered {
            if case .stop = command {
                control.setState(.stopped)
            }
            command.answerWithoutThread(summary: summary)
        }
        control.eventSink.finish()
    }

    // MARK: Frames

    private func runLoop(_ core: borrowing LibretroCore, context: CallbackContext, battery: BatterySaveMonitor) {
        while true {
            if control.hasCommands {
                let isIdle = if case .idle = mode { true } else { false }
                commands += control.takeCommands(blocking: isIdle)
            }
            while !commands.isEmpty, !stopRequested {
                if case .stepping = mode { break }
                handle(commands.removeFirst(), core, context: context, battery: battery)
            }
            if stopRequested || context.shutdownRequested {
                return
            }
            switch mode {
            case .idle:
                control.waitForCommands()
            case .running:
                runFrame(core, context: context, battery: battery, paced: true)
            case let .stepping(remaining, continuation):
                runFrame(core, context: context, battery: battery, paced: false)
                if remaining > 1 {
                    mode = .stepping(remaining: remaining - 1, continuation)
                } else {
                    mode = .idle
                    publishStats(at: HostTime.now())
                    control.setState(.paused)
                    continuation.resume()
                }
            }
        }
    }

    private func handle(
        _ command: SessionCommand, _ core: borrowing LibretroCore,
        context: CallbackContext, battery: BatterySaveMonitor
    ) {
        switch command {
        case let .connect(video, audio):
            context.videoSink = video
            context.audioSink = audio
        case .resume:
            guard case .idle = mode else { return }
            let now = HostTime.now()
            mode = .running
            clock.restart(at: now)
            metrics.restart(at: now, frames: framesEmulated)
            control.setState(.running)
        case let .pause(continuation):
            if case .running = mode {
                mode = .idle
            }
            publishStats(at: HostTime.now())
            if framesEmulated > 0 {
                control.setState(.paused)
            }
            battery.saveNow(core.saveMemory().map(UnsafeRawBufferPointer.init)) { _ in
                continuation.resume()
            }
        case let .runFrames(count, continuation):
            guard count > 0 else {
                continuation.resume()
                return
            }
            mode = .stepping(remaining: count, continuation)
            metrics.restart(at: HostTime.now(), frames: framesEmulated)
            control.setState(.running)
        case let .saveBattery(continuation):
            battery.saveNow(core.saveMemory().map(UnsafeRawBufferPointer.init)) { result in
                continuation.resume(returning: result)
            }
        case let .stop(continuation):
            stopRequested = true
            if let continuation {
                stopContinuations.append(continuation)
            }
        }
    }

    /// One `retro_run`. Paced frames wait for their deadline; frames of
    /// `runFrames` start at once.
    private func runFrame(
        _ core: borrowing LibretroCore, context: CallbackContext, battery: BatterySaveMonitor, paced: Bool
    ) {
        let now = HostTime.now()
        let plan = paced
            ? clock.beginFrame(now: now)
            : FrameClock.Plan(deadline: now, shouldWait: false, lateness: 0, resynchronized: false)
        if plan.resynchronized {
            arcfold_signpost_resync(signpostLog)
        }
        if plan.shouldWait {
            HostTime.wait(until: plan.deadline)
        }
        let start = HostTime.now()
        framesEmulated += 1
        context.beginFrame(FrameStamp(sequence: framesEmulated, nominalTime: plan.deadline))
        arcfold_signpost_run_begin(signpostLog, signpostID.rawValue)
        autoreleasepool {
            core.run()
        }
        arcfold_signpost_run_end(signpostLog, signpostID.rawValue)
        context.endFrame()
        let end = HostTime.now()
        if paced {
            clock.endFrame(audio: context.lastAudioStatus, writtenFrames: context.audioFramesWritten)
        }
        metrics.record(start: start, end: end, deadline: plan.deadline)
        if framesEmulated % BatterySaveMonitor.checkInterval == 0 {
            battery.check(core.saveMemory().map(UnsafeRawBufferPointer.init))
        }
        if metrics.isDue(at: end) {
            publishStats(at: end)
        }
    }

    private func publishStats(at now: UInt64) {
        metrics.publish(to: control.stats, at: now, frames: framesEmulated, clock: clock)
    }

    // MARK: Files

    /// The game, mapped instead of read: `NSData.bytes` stays valid as long as
    /// the object, which the session keeps until `retro_unload_game`.
    private func readGame(_ url: URL) throws(SessionError) -> NSData {
        do {
            return try NSData(contentsOf: url, options: .alwaysMapped)
        } catch {
            throw .unreadableGame(path: url.path(percentEncoded: false), reason: error.localizedDescription)
        }
    }

    /// Creates the system and save folders and the folder of the battery save
    /// if they are missing.
    private func createDirectories(for configuration: SessionConfiguration) throws(SessionError) {
        let manager = FileManager.default
        for directory in [configuration.systemDirectory, configuration.saveDirectory] {
            do {
                try manager.createDirectory(at: directory, withIntermediateDirectories: true)
            } catch {
                Self.logger.error(
                    "Cannot create \(directory.path(percentEncoded: false), privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
            }
        }
        do {
            try manager.createDirectory(
                at: configuration.batterySave.deletingLastPathComponent(), withIntermediateDirectories: true
            )
        } catch {
            throw .batterySave(reason: error.localizedDescription)
        }
    }
}

/// Measurements of the frames since the last publication.
private struct FrameMetrics {
    /// About once per second.
    static let publishInterval = HostTime.ticks(fromSeconds: 1)
    /// Shorter intervals give no meaningful frame rate or maxima; a pause right
    /// after a publication keeps the values of the previous interval.
    static let minimumInterval = HostTime.ticks(fromSeconds: 0.25)
    /// A frame that starts later than this after its deadline counts as late.
    static let lateThreshold = HostTime.ticks(fromSeconds: 0.002)

    private var intervalStart: UInt64
    private var framesAtIntervalStart: UInt64 = 0
    private var lateFrames: UInt64 = 0
    private var lastRun: UInt64 = 0
    // The current interval.
    private var maxRun: UInt64 = 0
    private var maxLateness: UInt64 = 0
    // What the last full interval published.
    private var framesPerSecond = 0.0
    private var publishedMaxRun: UInt64 = 0
    private var publishedMaxLateness: UInt64 = 0

    init(start: UInt64) {
        intervalStart = start
    }

    /// Starts a new interval, for example when frames start running again.
    mutating func restart(at now: UInt64, frames: UInt64) {
        intervalStart = now
        framesAtIntervalStart = frames
        maxRun = 0
        maxLateness = 0
    }

    mutating func record(start: UInt64, end: UInt64, deadline: UInt64) {
        lastRun = end &- start
        maxRun = max(maxRun, lastRun)
        let lateness = start > deadline ? start - deadline : 0
        maxLateness = max(maxLateness, lateness)
        if lateness > Self.lateThreshold {
            lateFrames += 1
        }
    }

    func isDue(at now: UInt64) -> Bool {
        now &- intervalStart >= Self.publishInterval
    }

    /// Publishes the values; an interval of at least `minimumInterval` ends here.
    mutating func publish(to stats: SessionStats, at now: UInt64, frames: UInt64, clock: FrameClock) {
        let elapsed = now &- intervalStart
        let isFullInterval = elapsed >= Self.minimumInterval
        if isFullInterval {
            framesPerSecond = Double(frames - framesAtIntervalStart) * HostTime.ticksPerSecond / Double(elapsed)
            publishedMaxRun = maxRun
            publishedMaxLateness = maxLateness
        } else {
            publishedMaxRun = max(publishedMaxRun, maxRun)
            publishedMaxLateness = max(publishedMaxLateness, maxLateness)
        }
        stats.publish(
            framesEmulated: frames,
            framesPerSecond: framesPerSecond,
            lateFrames: lateFrames,
            resyncs: clock.resyncs,
            lastRunNanoseconds: HostTime.nanoseconds(fromTicks: lastRun),
            maxRunNanoseconds: HostTime.nanoseconds(fromTicks: publishedMaxRun),
            maxLatenessNanoseconds: HostTime.nanoseconds(fromTicks: publishedMaxLateness),
            periodTrim: clock.trim
        )
        if isFullInterval {
            restart(at: now, frames: frames)
        }
    }
}
