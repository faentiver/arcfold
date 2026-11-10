import AVFAudio
import Foundation
import os

/// Plays an `AudioRing` through `AVAudioEngine` and owns the audio session.
///
/// The session uses the category `.ambient`: the ring/silent switch mutes the
/// game, and music from other apps keeps playing. The source node converts
/// from the core's rate to the hardware rate once; there is no dynamic
/// resampling, the emulation follows the audio clock instead (ADR 0005).
@MainActor
public final class AudioOutput {
    private let ring: AudioRing
    private let sampleRate: Double
    private let session = AVAudioSession.sharedInstance()
    private var engine: AVAudioEngine?
    private var sourceNode: AVAudioSourceNode?
    private let eventStream: AsyncStream<AudioOutputEvent>
    private let eventContinuation: AsyncStream<AudioOutputEvent>.Continuation
    private var observers: [any NSObjectProtocol] = []
    private var messageTokens: [NotificationCenter.ObservationToken] = []
    private var engineObserver: (any NSObjectProtocol)?
    private var restartTask: Task<Void, Never>?
    /// Between a successful `start()` and `stop()`.
    private var isStarted = false

    private nonisolated static let logger = Logger(subsystem: "com.faentiver.arcfold", category: "audio")

    /// - Parameters:
    ///   - ring: The ring the emulation thread writes into.
    ///   - sampleRate: `AVTiming.sampleRate` of the session.
    public init(ring: AudioRing, sampleRate: Double) {
        self.ring = ring
        self.sampleRate = sampleRate
        (eventStream, eventContinuation) = AsyncStream.makeStream(
            of: AudioOutputEvent.self, bufferingPolicy: .bufferingNewest(16))
    }

    isolated deinit {
        restartTask?.cancel()
        tearDownEngine()
        removeObservers()
        eventContinuation.finish()
    }

    /// Configures and activates the audio session, builds the engine graph,
    /// sets the ring's target level from the IO buffer and starts playing.
    public func start() async throws(AudioOutputError) {
        do {
            try session.setCategory(.ambient, mode: .default)
            // 5 ms keeps the target level at its 35 ms floor (ADR 0005).
            try session.setPreferredIOBufferDuration(0.005)
        } catch {
            throw .session(reason: error.localizedDescription)
        }
        let activated: Bool
        do {
            activated = try await session.activate(options: [])
        } catch {
            throw .session(reason: error.localizedDescription)
        }
        guard activated else {
            throw .session(reason: "The system did not activate the audio session")
        }
        if !isStarted {
            addObservers()
            isStarted = true
        }
        do throws(AudioOutputError) {
            try startEngine()
        } catch {
            stop()
            throw error
        }
    }

    /// Plays silence without counting underruns, while the emulation is paused.
    public func suspend() {
        ring.setSuspended(true)
    }

    /// Drops stale samples and fills the ring up again before playing.
    ///
    /// If the system stopped the engine, for example during an interruption,
    /// it is restarted in the background and `.restarted` follows.
    public func resume() {
        ring.requestFlush()
        ring.setSuspended(false)
        guard isStarted, engine?.isRunning != true, restartTask == nil else { return }
        restartTask = Task { [weak self] in
            await self?.restartAfterInterruption()
        }
    }

    /// Stops the engine and deactivates the audio session.
    public func stop() {
        restartTask?.cancel()
        restartTask = nil
        tearDownEngine()
        removeObservers()
        isStarted = false
        // An explicitly sendable handler: the session calls it on its own queue.
        session.deactivate(options: .notifyOthersOnDeactivation) { @Sendable _, error in
            if let error {
                Self.logger.info("Deactivating the audio session failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// The current output route.
    public var route: AudioRoute {
        AudioRoute(
            hardwareSampleRate: session.sampleRate,
            ioBufferDuration: session.ioBufferDuration,
            outputLatency: session.outputLatency
        )
    }

    /// Interruptions and route changes the app reacts to. Meant for one consumer.
    public var events: AsyncStream<AudioOutputEvent> {
        eventStream
    }

    // MARK: Engine

    private func startEngine() throws(AudioOutputError) {
        if engine == nil {
            try buildEngine()
        }
        guard let engine else { return }
        updateTargetLevel()
        guard !engine.isRunning else { return }
        ring.requestFlush()
        engine.prepare()
        do {
            try engine.start()
        } catch {
            throw .engine(reason: error.localizedDescription)
        }
    }

    /// The rate the source node converts from: the core's rate, rounded to
    /// whole hertz. melonDS DS plays at 33 513 982 / 1024 = 32 728.498046875 Hz,
    /// so the node gets 32 728 Hz. From a fractional rate (first 32 728.5 Hz)
    /// the node's conversion broke down after 80 to 90 s in each of three
    /// runs in the iOS 27.1 Simulator: it stopped pulling, then the ring ran
    /// dry over and over. From whole hertz it ran steadily, 32 729 Hz for
    /// 250 s and 32 728 Hz for 182 s in the app (docs/wissen/renderer.md).
    /// Half a hertz is 15 ppm, inaudible, and the emulation follows the audio
    /// clock anyway (ADR 0005).
    package static func nodeSampleRate(for coreRate: Double) -> Double {
        max(1, coreRate.rounded())
    }

    private func buildEngine() throws(AudioOutputError) {
        // The block format is the core's format, so the render block only
        // copies; the node converts rate, bit depth and interleaving once.
        let nodeRate = Self.nodeSampleRate(for: sampleRate)
        guard let coreFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16, sampleRate: nodeRate, channels: 2, interleaved: true),
              let node = ring.makeSourceNode(format: coreFormat)
        else {
            throw .engine(reason: "No source node for stereo Int16 at \(nodeRate) Hz")
        }
        let engine = AVAudioEngine()
        engine.attach(node)
        try connect(node, in: engine)
        self.engine = engine
        sourceNode = node
        engineObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.engineConfigurationChanged()
            }
        }
    }

    /// Connects with the hardware rate, so that only the source node converts.
    /// Without a format the node ran at 44.1 kHz and the mixer converted a
    /// second time (ADR 0005).
    private func connect(_ node: AVAudioSourceNode, in engine: AVAudioEngine) throws(AudioOutputError) {
        let outputRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        let hardwareRate = outputRate > 0 ? outputRate : session.sampleRate
        guard let mixerFormat = AVAudioFormat(standardFormatWithSampleRate: hardwareRate, channels: 2) else {
            throw .engine(reason: "No mixer format for \(hardwareRate) Hz")
        }
        do {
            try engine.connectNode(node, to: engine.mainMixerNode, format: mixerFormat)
        } catch {
            throw .engine(reason: error.localizedDescription)
        }
    }

    private func tearDownEngine() {
        if let engineObserver {
            NotificationCenter.default.removeObserver(engineObserver)
        }
        engineObserver = nil
        // stop() returns after the render block ran for the last time, so the
        // ring may be freed afterwards.
        engine?.stop()
        if let engine, let sourceNode {
            engine.detach(sourceNode)
        }
        sourceNode = nil
        engine = nil
    }

    /// The target level: at least 35 ms, and 20 ms more than one IO buffer.
    private func updateTargetLevel() {
        let seconds = max(0.035, session.ioBufferDuration + 0.020)
        ring.setTargetFrames(Int((seconds * sampleRate).rounded(.up)))
    }

    // MARK: Events

    private func addObservers() {
        let center = NotificationCenter.default
        messageTokens.append(center.addObserver(of: session, for: .didBecomeInactive) { [weak self] message in
            if case .systemInterruption = message.deactivationResult {
                self?.eventContinuation.yield(.interrupted)
            }
        })
        messageTokens.append(center.addObserver(of: session, for: .resumptionRecommendation) { [weak self] message in
            self?.eventContinuation.yield(.resumptionRecommended(message.recommendation == .shouldResume))
        })
        observers.append(center.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: session, queue: .main
        ) { [weak self] notification in
            let reason = (notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt)
                .flatMap(AVAudioSession.RouteChangeReason.init(rawValue:))
            MainActor.assumeIsolated {
                self?.routeChanged(reason: reason)
            }
        })
        observers.append(center.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification, object: session, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.mediaServicesWereReset()
            }
        })
    }

    private func removeObservers() {
        let center = NotificationCenter.default
        for token in messageTokens {
            center.removeObserver(token)
        }
        for observer in observers {
            center.removeObserver(observer)
        }
        messageTokens = []
        observers = []
    }

    private func routeChanged(reason: AVAudioSession.RouteChangeReason?) {
        updateTargetLevel()
        if reason == .oldDeviceUnavailable {
            eventContinuation.yield(.outputDeviceLost)
        }
    }

    /// The engine stopped itself because the hardware format changed: connect
    /// again with the new rate and start once more.
    private func engineConfigurationChanged() {
        guard isStarted, let engine, let sourceNode else { return }
        do throws(AudioOutputError) {
            try connect(sourceNode, in: engine)
            try startEngine()
            eventContinuation.yield(.restarted)
        } catch {
            Self.logger.error("Restarting after a configuration change failed: \(error.description, privacy: .public)")
        }
    }

    /// The media services restarted: every audio object is invalid. Build
    /// everything again.
    private func mediaServicesWereReset() {
        guard isStarted else { return }
        tearDownEngine()
        restartTask?.cancel()
        restartTask = Task { [weak self] in
            await self?.restartAfterInterruption()
        }
    }

    private func restartAfterInterruption() async {
        defer { restartTask = nil }
        do throws(AudioOutputError) {
            try await start()
            eventContinuation.yield(.restarted)
        } catch {
            Self.logger.error("Restarting the audio output failed: \(error.description, privacy: .public)")
        }
    }
}

/// The output route as the audio session reports it.
public struct AudioRoute: Sendable, Hashable {
    /// The hardware sample rate, for example 48 000 Hz.
    public var hardwareSampleRate: Double
    /// Seconds of one IO buffer.
    public var ioBufferDuration: Double
    /// Seconds from the render block to the speaker.
    public var outputLatency: Double

    public init(hardwareSampleRate: Double, ioBufferDuration: Double, outputLatency: Double) {
        self.hardwareSampleRate = hardwareSampleRate
        self.ioBufferDuration = ioBufferDuration
        self.outputLatency = outputLatency
    }
}

/// Something that happened to the audio output.
public enum AudioOutputEvent: Sendable, Hashable {
    /// The audio session became inactive, for example for a call. Pause the game.
    case interrupted
    /// After an interruption the system recommends resuming (true) or not (false).
    case resumptionRecommended(Bool)
    /// The output device went away, for example headphones were unplugged. Pause the game.
    case outputDeviceLost
    /// The engine was rebuilt after a configuration change or a media services
    /// reset; playback continues after priming.
    case restarted
}

/// Why the audio output could not start.
public enum AudioOutputError: Error, Sendable, Hashable, CustomStringConvertible {
    /// Configuring or activating the audio session failed.
    case session(reason: String)
    /// Building or starting the engine failed.
    case engine(reason: String)

    public var description: String {
        switch self {
        case let .session(reason): "The audio session could not start: \(reason)"
        case let .engine(reason): "The audio engine could not start: \(reason)"
        }
    }
}
