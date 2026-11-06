import Dispatch
import Synchronization

/// A request from the app to the emulation thread. Answered at a frame
/// boundary through its continuation (ADR 0005, section 3).
enum SessionCommand: Sendable {
    case connect(video: any VideoSink, audio: any AudioSink)
    case resume
    case pause(CheckedContinuation<Void, Never>)
    case runFrames(Int, CheckedContinuation<Void, Never>)
    case saveBattery(CheckedContinuation<Result<Void, SessionError>, Never>)
    /// Without a continuation when the session object went away.
    case stop(CheckedContinuation<SessionSummary, Never>?)

    /// Answers the command as if a session that has nothing loaded handled it:
    /// nothing runs, nothing needs saving.
    func answerWithoutThread(summary: SessionSummary) {
        switch self {
        case .connect, .resume:
            break
        case let .pause(continuation), let .runFrames(_, continuation):
            continuation.resume()
        case let .saveBattery(continuation):
            continuation.resume(returning: .success(()))
        case let .stop(continuation):
            continuation?.resume(returning: summary)
        }
    }
}

/// What the app and the emulation thread share: the command mailbox, the
/// state and the measurements. Every member is a lock or an atomic.
///
/// The emulation thread checks `hasMail` once per frame and takes the mailbox
/// only when it is set, with `withLockIfAvailable` while frames run, so it
/// never waits for the app. A paused thread sleeps on `wakeUp`.
final class SessionControl: Sendable {
    private struct Mailbox {
        var commands: [SessionCommand] = []
        /// An emulation thread exists and will take commands.
        var isOpen = false
        /// The summary of a session whose thread has ended.
        var summary: SessionSummary?
    }

    let configuration: SessionConfiguration
    let input = InputState()
    let stats = SessionStats()
    let events: AsyncStream<SessionEvent>
    let eventSink: AsyncStream<SessionEvent>.Continuation

    private let mailbox = Mutex(Mailbox())
    private let hasMail = Atomic<Bool>(false)
    private let wakeUp = DispatchSemaphore(value: 0)
    private let stateCode = Atomic<UInt8>(SessionState.idle.code)

    init(configuration: SessionConfiguration) {
        self.configuration = configuration
        // Events are rare (saves, messages); the newest 64 are kept if nobody reads.
        (events, eventSink) = AsyncStream.makeStream(of: SessionEvent.self, bufferingPolicy: .bufferingNewest(64))
    }

    // MARK: State

    var state: SessionState {
        SessionState(code: stateCode.load(ordering: .acquiring))
    }

    func setState(_ state: SessionState) {
        stateCode.store(state.code, ordering: .releasing)
    }

    /// Moves from `.idle` to `.loading` and opens the mailbox. False if the
    /// session left `.idle` already.
    func beginLoading() -> Bool {
        mailbox.withLock { mailbox in
            guard state == .idle, mailbox.summary == nil else { return false }
            setState(.loading)
            mailbox.isOpen = true
            return true
        }
    }

    // MARK: App side

    /// Queues `command` for the emulation thread. Without a thread the
    /// command is answered at once.
    func send(_ command: SessionCommand) {
        let summary: SessionSummary? = mailbox.withLock { mailbox in
            guard mailbox.isOpen else {
                if case .stop = command, state == .idle || state == .failed {
                    // Stopping a session that never ran ends it for good.
                    mailbox.summary = mailbox.summary ?? .empty
                    setState(.stopped)
                }
                return mailbox.summary ?? .empty
            }
            mailbox.commands.append(command)
            hasMail.store(true, ordering: .releasing)
            return nil
        }
        guard let summary else {
            wakeUp.signal()
            return
        }
        if case .stop = command {
            // No thread will finish the events of a session that never loaded.
            eventSink.finish()
        }
        command.answerWithoutThread(summary: summary)
    }

    // MARK: Emulation thread side

    /// Whether commands wait in the mailbox. One atomic load.
    var hasCommands: Bool {
        hasMail.load(ordering: .acquiring)
    }

    /// Takes the waiting commands. While frames run it does not wait for the
    /// lock (`blocking` false); if the app holds it, the commands stay for the
    /// next frame.
    func takeCommands(blocking: Bool) -> [SessionCommand] {
        if blocking {
            return mailbox.withLock { mailbox in Self.empty(&mailbox, flag: hasMail) }
        }
        return mailbox.withLockIfAvailable { mailbox in Self.empty(&mailbox, flag: hasMail) } ?? []
    }

    private static func empty(_ mailbox: inout Mailbox, flag: borrowing Atomic<Bool>) -> [SessionCommand] {
        let commands = mailbox.commands
        mailbox.commands = []
        flag.store(false, ordering: .relaxed)
        return commands
    }

    /// Sleeps until a command arrives. Wakeups without a command are harmless.
    func waitForCommands() {
        wakeUp.wait()
    }

    /// Ends the thread's part: stores the summary, closes the mailbox and
    /// returns the commands nobody will take any more.
    func close(summary: SessionSummary, state: SessionState) -> [SessionCommand] {
        mailbox.withLock { mailbox in
            mailbox.isOpen = false
            mailbox.summary = summary
            setState(state)
            let remaining = mailbox.commands
            mailbox.commands.removeAll()
            hasMail.store(false, ordering: .relaxed)
            return remaining
        }
    }
}

extension SessionSummary {
    static let empty = SessionSummary(framesEmulated: 0, environmentCalls: [:], unhandledEnvironmentCommands: [])
}

extension SessionState {
    var code: UInt8 {
        switch self {
        case .idle: 0
        case .loading: 1
        case .ready: 2
        case .running: 3
        case .paused: 4
        case .stopped: 5
        case .failed: 6
        }
    }

    init(code: UInt8) {
        self = switch code {
        case 1: .loading
        case 2: .ready
        case 3: .running
        case 4: .paused
        case 5: .stopped
        case 6: .failed
        default: .idle
        }
    }
}
