/// Plays an `AudioRing` through `AVAudioEngine` and owns the audio session.
///
/// The session uses the category `.ambient`: the ring/silent switch mutes the
/// game, and music from other apps keeps playing. The source node converts
/// from the core's rate to the hardware rate once; there is no dynamic
/// resampling, the emulation follows the audio clock instead (ADR 0005).
@MainActor
public final class AudioOutput {
    /// - Parameters:
    ///   - ring: The ring the emulation thread writes into.
    ///   - sampleRate: `AVTiming.sampleRate` of the session.
    public init(ring: AudioRing, sampleRate: Double) {
        fatalError("M1 track A")
    }

    /// Configures and activates the audio session, builds the engine graph,
    /// sets the ring's target level from the IO buffer and starts playing.
    public func start() async throws(AudioOutputError) {
        fatalError("M1 track A")
    }

    /// Plays silence without counting underruns, while the emulation is paused.
    public func suspend() {
        fatalError("M1 track A")
    }

    /// Drops stale samples and fills the ring up again before playing.
    public func resume() {
        fatalError("M1 track A")
    }

    /// Stops the engine and deactivates the audio session.
    public func stop() {
        fatalError("M1 track A")
    }

    /// The current output route.
    public var route: AudioRoute {
        fatalError("M1 track A")
    }

    /// Interruptions and route changes the app reacts to. Meant for one consumer.
    public var events: AsyncStream<AudioOutputEvent> {
        fatalError("M1 track A")
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
