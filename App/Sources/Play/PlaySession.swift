import FoldLayout
import Foundation
import LibretroKit
import Observation
import os
import Renderer
import SwiftUI
import UIKit

/// One game on screen: owns the emulation session, the mailbox for pictures,
/// the audio ring and output, and the input sources, and runs them through
/// the transitions of ADR 0005, section 9, and ADR 0006, section 10.
///
/// Every transition goes through one queue of lifecycle steps, so that a quick
/// inactive, background, active sequence cannot overtake itself.
@Observable
final class PlaySession {
    enum Phase: Equatable {
        case idle
        case loading
        case running
        case stopped
        case failed(String)
    }

    let game: Game
    /// The system of the game: core, screens, buttons, vertical bar.
    let system: GameSystem
    private(set) var phase = Phase.idle
    /// Paused from the game menu, or after an output device went away.
    private(set) var isUserPaused = false
    /// The scene is inactive or in the background.
    private(set) var isScenePaused = false
    /// The system took the audio session, for example for a call.
    private(set) var isInterrupted = false
    /// The device was closed while the game ran (ADR 0006, section 10).
    private(set) var isFolded = false
    var isPaused: Bool { isUserPaused || isScenePaused || isInterrupted || isFolded }
    /// The pause menu shows while paused by hand or closed; on the outer
    /// display "Resume" plays on (plan, section 7).
    var showsPauseMenu: Bool { isUserPaused || isFolded }

    /// Exists once the core reported its geometry.
    private(set) var mailbox: FrameMailbox?
    private(set) var info: SessionInfo?
    /// Set when the sound could not start; the game runs without it.
    private(set) var audioProblem: String?
    /// A short message from the core or about the battery save.
    private(set) var notice: String?
    /// The core asked to end the game; the view closes.
    private(set) var coreRequestedShutdown = false
    private(set) var controllers: ControllerInput?

    let presentationStats = PresentationStats()
    let audioRing = AudioRing()

    @ObservationIgnored private let files: GameFiles
    @ObservationIgnored private let location: LibraryLocation
    @ObservationIgnored private var session: EmulationSession?
    @ObservationIgnored private var audioOutput: AudioOutput?
    /// AudioOutput.stop() ran when the scene went to the background.
    @ObservationIgnored private var isAudioStopped = false
    /// The emulation and the sound are held for a pause reason. Pausing and
    /// resuming happen only on a change, so that `.active` after a short
    /// `.inactive` does not flush the sound of a game that never stopped.
    @ObservationIgnored private var isHeld = false
    /// How often the game was held since it started, for the debug overlay:
    /// a UI test sees a pause too short to catch in `isPaused` (ADR 0006).
    @ObservationIgnored private(set) var pauseCount = 0
    @ObservationIgnored private var lifecycle: Task<Void, Never>?
    @ObservationIgnored private var watchers: [Task<Void, Never>] = []
    /// The pause that `.inactive` brings after `inactiveDelay`, unless another
    /// phase comes first.
    @ObservationIgnored private var inactivePause: Task<Void, Never>?

    /// A pose change may pass through `.inactive`; the emulation must not stop
    /// for it, so `.inactive` pauses only after this long (ADR 0006, section 10).
    static let inactiveDelay = Duration.milliseconds(300)

    /// The session of this process. Libretro callbacks carry no context, so
    /// only one core can run at a time (plan, guardrail 3).
    private static weak var current: PlaySession?
    private static let logger = Logger(subsystem: "com.faentiver.arcfold", category: "play")
    private static let statsLogger = Logger(subsystem: "com.faentiver.arcfold", category: "stats")
    /// Hinge, scene phases and gaps of the emulation, as evidence for the hand
    /// check of the poses (ADR 0006, section 9).
    private static let foldLogger = Logger(subsystem: "com.faentiver.arcfold", category: "fold")

    init(game: Game, files: GameFiles, location: LibraryLocation) {
        self.game = game
        self.files = files
        self.location = location
        system = GameSystem.system(id: game.system) ?? .gba
    }

    // MARK: Transitions

    /// Opens the game: load, connect, sound first, then the emulation (ADR 0005).
    func start() {
        enqueue { await $0.performStart() }
    }

    func setUserPaused(_ paused: Bool) {
        enqueue { session in
            session.isUserPaused = paused
            await session.applyPause()
        }
    }

    /// "Resume" in the pause menu: clears the pause by hand and the one of a
    /// closed device, so that the game plays on the outer display.
    func resumeFromMenu() {
        isFolded = false
        setUserPaused(false)
    }

    /// `.inactive` pauses after `inactiveDelay`, unless `.active` or
    /// `.background` comes first; `.background` pauses at once (ADR 0006,
    /// section 10).
    func scenePhaseChanged(to scenePhase: ScenePhase) {
        Self.foldLogger.notice("Scene phase \(String(describing: scenePhase), privacy: .public)")
        inactivePause?.cancel()
        inactivePause = nil
        guard scenePhase == .inactive else {
            enqueue { await $0.performScenePhaseChange(scenePhase) }
            return
        }
        inactivePause = Task { [weak self] in
            try? await Task.sleep(for: Self.inactiveDelay)
            guard !Task.isCancelled, let self else { return }
            self.inactivePause = nil
            Self.foldLogger.notice("Still inactive after \(Self.inactiveDelay, privacy: .public), pausing")
            self.enqueue { await $0.performScenePhaseChange(.inactive) }
        }
    }

    /// Closes the game: saves, unloads and stops the sound.
    func stop() async {
        let previous = lifecycle
        let task = Task { @MainActor [weak self] in
            await previous?.value
            await self?.performStop()
        }
        lifecycle = task
        await task.value
    }

    func toggleUserPause() {
        setUserPaused(!isUserPaused)
    }

    /// The mask of the touch controls. Called on the main actor only, so the
    /// touch source has one writer.
    func setTouchButtons(_ buttons: JoypadButtons) {
        session?.input.set(buttons, from: .touch)
    }

    /// The pointer of the touch screen, nil when lifted. Called on the main
    /// actor only, so the pointer has one writer (ADR 0006).
    func setTouchPointer(_ position: PointerPosition?) {
        session?.input.setPointer(position)
    }

    /// The hinge moved (ADR 0006): becoming `.closed` pauses the game with the
    /// reason "folded", sound first, and saves; leaving `.closed` resumes it if
    /// nothing else paused it. Changes between partially and fully open never
    /// pause.
    func hingeChanged(from old: HingeState?, to new: HingeState?) {
        Self.foldLogger.notice("Hinge \(Self.name(of: old), privacy: .public) → \(Self.name(of: new), privacy: .public)")
        // The state when the view appears (nil → closed) is no closing, and
        // without a hinge there is no such reason.
        let closes = new == .closed && (old == .partiallyOpen || old == .fullyOpen)
        let opens = isFolded && new != .closed
        guard closes || opens else { return }
        // Set at once, so that a quick close and open cannot overtake each
        // other; the queued step applies whatever holds when it runs.
        isFolded = closes
        enqueue { await $0.applyPause() }
    }

    /// Waits until every queued lifecycle step ran. For tests.
    func settle() async {
        while let current = lifecycle {
            await current.value
            if lifecycle == current {
                return
            }
        }
    }

    private static func name(of state: HingeState?) -> String {
        switch state {
        case .closed?: "closed"
        case .partiallyOpen?: "partially open"
        case .fullyOpen?: "fully open"
        case nil: "none"
        }
    }

    private func enqueue(_ step: @escaping @MainActor (PlaySession) async -> Void) {
        let previous = lifecycle
        lifecycle = Task { @MainActor [weak self] in
            await previous?.value
            guard let self else { return }
            await step(self)
        }
    }

    private func performStart() async {
        guard phase == .idle else { return }
        if let current = Self.current, current !== self, current.phase != .stopped {
            phase = .failed(String(localized: "Another game is already running. Quit it before you start this one.",
                                   comment: "Shown instead of a second game when a game runs in another window."))
            return
        }
        Self.current = self
        phase = .loading
        #if DEBUG
        if DebugLaunch.failsStart {
            release()
            phase = .failed(Self.message(for: .gameRejected))
            return
        }
        #endif

        let configuration = SessionConfiguration(
            coreName: system.coreName,
            game: files.game,
            batterySave: files.batterySave,
            systemDirectory: location.system,
            saveDirectory: files.folder,
            coreOptions: system.coreOptions,
            blankSaveMemoryByte: system.blankSaveMemoryByte,
            requiresSystemMemory: system.requiresSystemMemory
        )
        let session = EmulationSession(configuration: configuration)
        self.session = session
        let info: SessionInfo
        do throws(SessionError) {
            info = try await session.load()
        } catch {
            _ = await session.stop()
            self.session = nil
            release()
            phase = .failed(Self.message(for: error))
            return
        }
        self.info = info

        let mailbox = FrameMailbox(geometry: info.geometry, format: info.pixelFormat)
        self.mailbox = mailbox
        session.connect(video: mailbox, audio: audioRing)

        // Sound before the first frame: with frames running first, the ring
        // overflowed in the prototype (ADR 0005).
        let output = AudioOutput(ring: audioRing, sampleRate: info.timing.sampleRate)
        audioOutput = output
        do throws(AudioOutputError) {
            try await output.start()
        } catch {
            audioProblem = error.description
            Self.logger.error("No sound: \(error.description, privacy: .public)")
        }

        let controllers = ControllerInput(input: session.input)
        controllers.start()
        self.controllers = controllers
        watch(session: session, output: output)

        phase = .running
        isHeld = isPaused
        if isPaused {
            output.suspend()
        } else {
            session.resume()
        }
    }

    private func performScenePhaseChange(_ scenePhase: ScenePhase) async {
        switch scenePhase {
        case .active:
            isScenePaused = false
            if isAudioStopped, let audioOutput, phase == .running {
                isAudioStopped = false
                do throws(AudioOutputError) {
                    try await audioOutput.start()
                } catch {
                    audioProblem = error.description
                }
            }
            await applyPause()
        case .inactive:
            isScenePaused = true
            await applyPause()
        case .background:
            // iOS may suspend the app soon after this phase begins, so the
            // background task comes first and covers the pause, which already
            // saves, the save and stopping the sound.
            let task = BackgroundTask(name: "Pause and save the game")
            defer { task.end() }
            isScenePaused = true
            await applyPause()
            await saveBatteryNow()
            if phase == .running, let audioOutput, !isAudioStopped {
                audioOutput.stop()
                isAudioStopped = true
            }
        @unknown default:
            break
        }
    }

    /// Brings the emulation and the sound in line with the pause reasons.
    private func applyPause() async {
        guard phase == .running, let session else { return }
        if isPaused {
            guard !isHeld else { return }
            isHeld = true
            pauseCount += 1
            Self.foldLogger.notice("Paused: \(self.pauseReasons, privacy: .public)")
            // Silence first, so that the ring running dry while the emulation
            // stops does not count as underruns. Pausing saves the battery.
            audioOutput?.suspend()
            await session.pause()
        } else if !isAudioStopped, isHeld {
            isHeld = false
            Self.foldLogger.notice("Resumed")
            audioOutput?.resume()
            session.resume()
        }
    }

    /// The pause reasons that hold, for the log.
    private var pauseReasons: String {
        let reasons = [(isUserPaused, "by hand"), (isScenePaused, "scene"), (isInterrupted, "interrupted"),
                       (isFolded, "folded")]
        return reasons.filter(\.0).map(\.1).joined(separator: ", ")
    }

    /// The battery save must reach the disk before the app may be suspended;
    /// the caller holds a background task.
    private func saveBatteryNow() async {
        guard phase == .running, let session else { return }
        do throws(SessionError) {
            try await session.saveBatteryNow()
        } catch {
            Self.logger.error("Saving in the background failed: \(error.description, privacy: .public)")
        }
    }

    private func performStop() async {
        guard phase != .stopped else { return }
        inactivePause?.cancel()
        inactivePause = nil
        for watcher in watchers {
            watcher.cancel()
        }
        watchers = []
        controllers?.stop()
        if let session {
            let summary = await session.stop()
            Self.logger.info("Stopped after \(summary.framesEmulated) frames")
        }
        audioOutput?.stop()
        session = nil
        release()
        phase = .stopped
    }

    private func release() {
        if Self.current === self {
            Self.current = nil
        }
    }

    // MARK: Events

    private func watch(session: EmulationSession, output: AudioOutput) {
        watchers.append(Task { [weak self] in
            for await event in session.events {
                self?.handle(event)
            }
        })
        watchers.append(Task { [weak self] in
            for await event in output.events {
                self?.handle(event)
            }
        })
        // A line every 10 s as evidence for acceptance runs (ADR 0005).
        watchers.append(Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                guard let self else { return }
                guard self.phase == .running, !self.isPaused else { continue }
                let line = self.debugReadings().lines.joined(separator: " | ")
                Self.statsLogger.notice("\(self.game.name, privacy: .public): \(line, privacy: .public)")
            }
        })
        watchers.append(Task { [weak self] in
            await self?.watchForGaps(in: session.stats)
        })
    }

    /// Logs gaps of the emulation thread over 50 ms (three frames) and every
    /// resynchronisation: "without stutter" in the Simulator means none of
    /// either during a pose change (ADR 0006, section 9). A gap is the frame
    /// period plus the largest lateness of a frame start the thread published
    /// for its last interval of about a second.
    private func watchForGaps(in stats: SessionStats) async {
        let period = 1 / max(info?.timing.framesPerSecond ?? 60, 1)
        var published: UInt64 = 0
        var resyncs = stats.snapshot().resyncs
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(250))
            let snapshot = stats.snapshot()
            if snapshot.resyncs > resyncs {
                Self.foldLogger.notice("Emulation resynchronized, \(snapshot.resyncs - resyncs) times, \(snapshot.resyncs) in all")
                resyncs = snapshot.resyncs
            }
            guard snapshot.framesEmulated != published else { continue }
            published = snapshot.framesEmulated
            let (seconds, attoseconds) = snapshot.maxLateness.components
            let gap = period + Double(seconds) + Double(attoseconds) * 1e-18
            if gap > 0.050 {
                Self.foldLogger.notice("Emulation gap of up to \(gap * 1000, format: .fixed(precision: 1)) ms before frame \(snapshot.framesEmulated)")
            }
        }
    }

    private func handle(_ event: SessionEvent) {
        switch event {
        case let .batterySaveWritten(bytes):
            Self.logger.info("Battery save written, \(bytes) bytes")
        case let .batterySaveFailed(reason):
            Self.logger.error("Battery save failed: \(reason, privacy: .public)")
            showNotice(String(localized: "The save could not be written: \(reason)",
                              comment: "Notice over the game. The value is the system's reason."))
        case let .coreMessage(message):
            showNotice(message)
        case .coreRequestedShutdown:
            coreRequestedShutdown = true
        }
    }

    private func handle(_ event: AudioOutputEvent) {
        switch event {
        case .interrupted:
            isInterrupted = true
            enqueue { await $0.applyPause() }
        case let .resumptionRecommended(shouldResume):
            // Without the recommendation the game stays paused until the
            // person resumes it from the menu.
            isInterrupted = false
            if !shouldResume {
                isUserPaused = true
            }
            enqueue { await $0.applyPause() }
        case .outputDeviceLost:
            setUserPaused(true)
        case .restarted:
            Self.logger.info("The audio output restarted")
        }
    }

    #if DEBUG
    /// Shows what `DebugRemote` asks for, the way the session shows the real
    /// thing: the notice of a failed battery save through `handle`, the chip
    /// of a missing audio output with the text of `AudioOutputError`.
    func show(_ sample: DebugRemote.Sample) {
        switch sample {
        case .longNotice:
            handle(.batterySaveFailed(reason: "The battery save failed: Cannot create battery.sav.tmp"))
        case let .audioProblem(shown):
            audioProblem = shown ? AudioOutputError.engine(reason: "no output route").description : nil
        }
    }
    #endif

    private func showNotice(_ text: String) {
        notice = text
        watchers.append(Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            if self?.notice == text {
                self?.notice = nil
            }
        })
    }

    // MARK: Readings

    /// Snapshots for the debug overlay; never blocks.
    func debugReadings() -> DebugReadings {
        DebugReadings(
            emulation: session?.stats.snapshot(),
            presentation: presentationStats.snapshot(),
            mailbox: mailbox?.counters,
            audio: audioRing.counters,
            audioSampleRate: info?.timing.sampleRate ?? 0,
            route: audioOutput?.route,
            input: session.map { InputReadings($0.input) },
            pointer: system.screens.touchScreen.flatMap { index in
                session.map { PointerReadings($0.input, frameSize: system.screens.frameSize,
                                              touchScreen: system.screens.sources[index]) }
            },
            thermalState: ProcessInfo.processInfo.thermalState,
            isLowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled,
            isPaused: isPaused,
            pauses: pauseCount
        )
    }

    private static func message(for error: SessionError) -> String {
        switch error {
        case .anotherSessionActive:
            String(localized: "Another game is already running. Quit it before you start this one.",
                   comment: "Shown instead of a second game when a game runs in another window.")
        case .gameNotRunnable:
            String(localized: "The core cannot run this game without the console's own system files, which Arcfold does not include.",
                   comment: "Shown when the core accepts a game it cannot run, for example an encrypted DS game.")
        default:
            String(localized: "The game could not start: \(error.description)",
                   comment: "Shown when a game fails to load. The value is the technical reason.")
        }
    }
}

/// Asks iOS for time to finish work after the app went to the background.
private final class BackgroundTask {
    private var identifier = UIBackgroundTaskIdentifier.invalid

    init(name: String) {
        identifier = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            self?.end()
        }
    }

    func end() {
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
    }
}
