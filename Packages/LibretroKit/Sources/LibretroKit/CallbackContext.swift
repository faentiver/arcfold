internal import CLibretro
import Darwin
import Foundation
import os

/// What happens behind the libretro callbacks of the one active session
/// (ADR 0005, section 4): the environment, pictures, sound and input.
///
/// Lives on the emulation thread; C reaches it through `CallbackSlot`. The
/// per-frame paths (`videoRefresh`, `audioSampleBatch`, `audioSample`,
/// `inputPoll`, `inputState` and `GET_VARIABLE_UPDATE`) neither allocate nor
/// lock: they copy pointers into spans, call the sinks and touch atomics.
final class CallbackContext {
    // MARK: Configuration

    let options: CoreOptions
    let input: InputState
    private let events: AsyncStream<SessionEvent>.Continuation
    private let systemDirectory: UnsafeMutablePointer<CChar>
    private let saveDirectory: UnsafeMutablePointer<CChar>

    // MARK: What the core asked for

    /// The pixel format the core set; libretro starts every core in 0RGB1555.
    private(set) var pixelFormat = PixelFormat.rgb1555
    /// Once the session is loaded, the pixel format can no longer change.
    private(set) var isPixelFormatLocked = false
    /// Pictures larger than this are dropped; set from the AV info at load.
    private(set) var maximumSize = (width: 0, height: 0)
    /// The current picture size; `SET_GEOMETRY` can change it within the maximum.
    private(set) var geometry: VideoGeometry?
    /// The core sent `RETRO_ENVIRONMENT_SHUTDOWN`.
    private(set) var shutdownRequested = false
    /// Calls per environment command below 256, with and without the
    /// experimental bit: a table, so that counting the per-frame
    /// GET_VARIABLE_UPDATE neither hashes nor, in debug builds, allocates.
    private let commandCounts: UnsafeMutableBufferPointer<Int>
    /// Calls of every other command.
    private var otherCommandCounts: [UInt32: Int] = [:]
    /// Commands refused because the host does not support them.
    private(set) var unhandledCommands: Set<UInt32> = []
    /// Pictures dropped because their size or pitch was impossible.
    private(set) var rejectedFrames: UInt64 = 0

    // MARK: Per frame

    var videoSink: (any VideoSink)?
    var audioSink: (any AudioSink)?
    /// The stamp of the frame that `retro_run` is producing.
    private(set) var stamp = FrameStamp(sequence: 0, nominalTime: 0)
    /// The state the audio sink reported after the frame's last write.
    private(set) var lastAudioStatus: AudioBufferStatus?
    /// Audio frames this frame wrote to the sink; with `lastAudioStatus` the
    /// frame clock knows the level before the frame's sound arrived.
    private(set) var audioFramesWritten = 0
    /// The buttons of this frame, taken in `inputPoll`.
    private var buttons: UInt32 = 0
    /// The pointer of this frame, taken in `inputPoll`.
    private var pointer = PointerSample.lifted
    /// Single samples from `retro_audio_sample`, written at the end of the frame.
    private let singleSamples: UnsafeMutableBufferPointer<Int16>
    private var singleSampleCount = 0

    private static let logger = Logger(subsystem: "com.faentiver.arcfold", category: "session")

    /// - Parameter singleSampleCapacity: Stereo frames `retro_audio_sample`
    ///   can deliver per frame before the buffer is written early.
    init(
        coreOptions: [String: String],
        systemDirectory: URL,
        saveDirectory: URL,
        input: InputState,
        events: AsyncStream<SessionEvent>.Continuation,
        singleSampleCapacity: Int = 4096
    ) {
        options = CoreOptions(overrides: coreOptions)
        self.input = input
        self.events = events
        self.systemDirectory = Self.duplicatePath(of: systemDirectory)
        self.saveDirectory = Self.duplicatePath(of: saveDirectory)
        singleSamples = .allocate(capacity: 2 * max(singleSampleCapacity, 1))
        commandCounts = .allocate(capacity: 2 * Self.tableCommands)
        commandCounts.initialize(repeating: 0)
        unhandledCommands.reserveCapacity(64)
    }

    deinit {
        free(systemDirectory)
        free(saveDirectory)
        singleSamples.deallocate()
        commandCounts.deallocate()
    }

    /// The file system path of `url` as a C string the caller frees.
    private static func duplicatePath(of url: URL) -> UnsafeMutablePointer<CChar> {
        let copy = url.withUnsafeFileSystemRepresentation { path -> UnsafeMutablePointer<CChar>? in
            path.flatMap { strdup($0) }
        }
        return copy ?? strdup("")
    }

    /// Called after `retro_load_game` with the AV info: from now on pictures up
    /// to the maximum size reach the sink, and the pixel format is fixed.
    func sessionDidLoad(geometry: VideoGeometry) {
        self.geometry = geometry
        maximumSize = (geometry.maxWidth, geometry.maxHeight)
        isPixelFormatLocked = true
    }

    // MARK: Frame boundaries

    /// Before `retro_run`.
    func beginFrame(_ stamp: FrameStamp) {
        self.stamp = stamp
        lastAudioStatus = nil
        audioFramesWritten = 0
    }

    /// After `retro_run`: writes the single samples the frame collected.
    func endFrame() {
        flushSingleSamples()
    }

    // MARK: Environment

    /// Commands below this number are counted in the table.
    private static let tableCommands = 256
    private static let experimental = UInt32(RETRO_ENVIRONMENT_EXPERIMENTAL)

    /// How often each environment command was called.
    var environmentCalls: [UInt32: Int] {
        var calls = otherCommandCounts
        for index in commandCounts.indices where commandCounts[index] > 0 {
            let number = UInt32(index % Self.tableCommands)
            calls[index < Self.tableCommands ? number : number | Self.experimental] = commandCounts[index]
        }
        return calls
    }

    private func count(_ command: UInt32) {
        let number = command & ~Self.experimental
        if number < Self.tableCommands {
            commandCounts[Int(number) + (command & Self.experimental != 0 ? Self.tableCommands : 0)] += 1
        } else {
            otherCommandCounts[command, default: 0] += 1
        }
    }

    /// `retro_environment_t`. Returns whether the command was handled.
    func environment(_ command: UInt32, _ data: UnsafeMutableRawPointer?) -> Bool {
        count(command)
        switch command {
        case EnvironmentCommand.getVariableUpdate:
            // Once per frame. Options never change while a game runs in M1.
            data?.storeBytes(of: false, as: Bool.self)
            return true
        case EnvironmentCommand.getVariable:
            guard let variable = data?.assumingMemoryBound(to: retro_variable.self),
                  let key = variable.pointee.key
            else {
                return false
            }
            let value = options.value(for: key)
            variable.pointee.value = value
            return value != nil
        case EnvironmentCommand.setVariables:
            guard let variables = data?.assumingMemoryBound(to: retro_variable.self) else {
                return false
            }
            options.declare(variables)
            return true
        case EnvironmentCommand.getCoreOptionsVersion:
            // Refused on purpose: the core falls back to SET_VARIABLES, whose
            // keys and defaults are all M1 needs. Not counted as unhandled.
            return false
        case EnvironmentCommand.setPixelFormat:
            guard let raw = data?.load(as: UInt32.self), let format = PixelFormat(libretroValue: raw),
                  format.isSupported, !isPixelFormatLocked || format == pixelFormat
            else {
                return refuse(command)
            }
            pixelFormat = format
            return true
        case EnvironmentCommand.getInputBitmasks:
            // `data` is ignored by definition, and mGBA passes NULL.
            return true
        case EnvironmentCommand.setInputDescriptors:
            // The app labels its own controls.
            return true
        case EnvironmentCommand.getLogInterface:
            CoreLog.installSink()
            return arcfold_log_fill_interface(data?.assumingMemoryBound(to: retro_log_callback.self))
        case EnvironmentCommand.getSystemDirectory:
            guard let data else { return false }
            data.storeBytes(of: UnsafePointer(systemDirectory), as: UnsafePointer<CChar>?.self)
            return true
        case EnvironmentCommand.getSaveDirectory:
            guard let data else { return false }
            data.storeBytes(of: UnsafePointer(saveDirectory), as: UnsafePointer<CChar>?.self)
            return true
        case EnvironmentCommand.getCanDupe:
            // A NULL picture repeats the previous one and never reaches the sink.
            data?.storeBytes(of: true, as: Bool.self)
            return true
        case EnvironmentCommand.setGeometry:
            guard let new = data?.load(as: retro_game_geometry.self), var geometry else {
                return false
            }
            geometry.baseWidth = min(Int(new.base_width), geometry.maxWidth)
            geometry.baseHeight = min(Int(new.base_height), geometry.maxHeight)
            if new.aspect_ratio > 0 {
                geometry.aspectRatio = Double(new.aspect_ratio)
            }
            self.geometry = geometry
            return true
        case EnvironmentCommand.shutdown:
            shutdownRequested = true
            events.yield(.coreRequestedShutdown)
            return true
        case EnvironmentCommand.setMessage:
            if let message = data?.load(as: retro_message.self).msg {
                report(message)
            }
            return true
        case EnvironmentCommand.setMessageExtended:
            if let message = data?.load(as: retro_message_ext.self).msg {
                report(message)
            }
            return true
        case EnvironmentCommand.getJITCapable:
            // Answered, with false: a core that gets no answer may crash (ADR
            // 0002). The JIT build gets its own hook later. Not counted as unhandled.
            data?.storeBytes(of: false, as: Bool.self)
            return true
        case EnvironmentCommand.setSystemAVInfo:
            // mGBA never sends it; M2 decides whether a core needs it.
            Self.logger.notice("Refused RETRO_ENVIRONMENT_SET_SYSTEM_AV_INFO")
            return refuse(command)
        default:
            // SET_MEMORY_MAPS, SET_SUPPORT_ACHIEVEMENTS, the rumble, sensor and
            // hardware rendering interfaces and every command M1 does not know.
            return refuse(command)
        }
    }

    private func refuse(_ command: UInt32) -> Bool {
        if unhandledCommands.insert(command).inserted {
            Self.logger.debug("Refused environment command \(command, privacy: .public)")
        }
        return false
    }

    private func report(_ message: UnsafePointer<CChar>) {
        let text = String(cString: message)
        if !text.isEmpty {
            events.yield(.coreMessage(text))
        }
    }

    // MARK: Pictures

    /// `retro_video_refresh_t`. A NULL picture (dupe) does not reach the sink.
    func videoRefresh(_ data: UnsafeRawPointer?, _ width: UInt32, _ height: UInt32, _ pitch: Int) {
        guard let data, let videoSink else { return }
        let width = Int(width)
        let height = Int(height)
        let rowBytes = width * pixelFormat.bytesPerPixel
        guard width > 0, height > 0, width <= maximumSize.width, height <= maximumSize.height, pitch >= rowBytes else {
            rejectedFrames += 1
            return
        }
        // The last row needs only its visible pixels, not the full pitch.
        let pixels = UnsafeRawBufferPointer(start: data, count: pitch * (height - 1) + rowBytes)
        videoSink.submit(
            pixels: pixels.bytes, width: width, height: height, bytesPerRow: pitch,
            format: pixelFormat, stamp: stamp
        )
    }

    // MARK: Sound

    /// `retro_audio_sample_batch_t`: interleaved stereo frames, straight to the sink.
    func audioSampleBatch(_ data: UnsafePointer<Int16>?, _ frames: Int) -> Int {
        guard let data, frames > 0 else { return 0 }
        flushSingleSamples()
        if let audioSink {
            lastAudioStatus = audioSink.write(UnsafeBufferPointer(start: data, count: 2 * frames).span)
            audioFramesWritten += frames
        }
        return frames
    }

    /// `retro_audio_sample_t`: one stereo frame, collected until the end of the frame.
    func audioSample(_ left: Int16, _ right: Int16) {
        if singleSampleCount == singleSamples.count {
            flushSingleSamples()
        }
        singleSamples[singleSampleCount] = left
        singleSamples[singleSampleCount + 1] = right
        singleSampleCount += 2
    }

    private func flushSingleSamples() {
        guard singleSampleCount > 0 else { return }
        if let audioSink {
            let samples = UnsafeBufferPointer(rebasing: singleSamples[..<singleSampleCount])
            lastAudioStatus = audioSink.write(samples.span)
            audioFramesWritten += singleSampleCount / 2
        }
        singleSampleCount = 0
    }

    // MARK: Input

    /// `retro_input_poll_t`: takes this frame's buttons and pointer.
    func inputPoll() {
        buttons = input.poll()
        pointer = input.pollPointer()
    }

    /// `retro_input_state_t`: the RetroPad on port 0, as a mask or bit by bit,
    /// and one pointer, the touch screen (ADR 0006).
    func inputState(_ port: UInt32, _ device: UInt32, _ index: UInt32, _ id: UInt32) -> Int16 {
        // RETRO_DEVICE_MASK, which Swift does not import: the base device without subclass.
        let deviceMask = UInt32(1 << RETRO_DEVICE_TYPE_SHIFT) - 1
        guard port == 0 else { return 0 }
        switch device & deviceMask {
        case UInt32(RETRO_DEVICE_JOYPAD):
            if id == UInt32(RETRO_DEVICE_ID_JOYPAD_MASK) {
                return Int16(truncatingIfNeeded: buttons)
            }
            guard id < 16 else { return 0 }
            return Int16((buttons >> id) & 1)
        case UInt32(RETRO_DEVICE_POINTER):
            // One finger: index 0 is the only pointer.
            guard index == 0 else { return 0 }
            switch id {
            case UInt32(RETRO_DEVICE_ID_POINTER_X): return pointer.position.x
            case UInt32(RETRO_DEVICE_ID_POINTER_Y): return pointer.position.y
            case UInt32(RETRO_DEVICE_ID_POINTER_PRESSED), UInt32(RETRO_DEVICE_ID_POINTER_COUNT):
                return pointer.isPressed ? 1 : 0
            default: return 0
            }
        default:
            return 0
        }
    }
}

/// The environment commands of libretro.h as `UInt32`, including the
/// experimental bit where the header sets it.
enum EnvironmentCommand {
    static let getCanDupe = UInt32(RETRO_ENVIRONMENT_GET_CAN_DUPE)
    static let setMessage = UInt32(RETRO_ENVIRONMENT_SET_MESSAGE)
    static let shutdown = UInt32(RETRO_ENVIRONMENT_SHUTDOWN)
    static let getSystemDirectory = UInt32(RETRO_ENVIRONMENT_GET_SYSTEM_DIRECTORY)
    static let setPixelFormat = UInt32(RETRO_ENVIRONMENT_SET_PIXEL_FORMAT)
    static let setInputDescriptors = UInt32(RETRO_ENVIRONMENT_SET_INPUT_DESCRIPTORS)
    static let setHWRender = UInt32(RETRO_ENVIRONMENT_SET_HW_RENDER)
    static let getVariable = UInt32(RETRO_ENVIRONMENT_GET_VARIABLE)
    static let setVariables = UInt32(RETRO_ENVIRONMENT_SET_VARIABLES)
    static let getVariableUpdate = UInt32(RETRO_ENVIRONMENT_GET_VARIABLE_UPDATE)
    static let getRumbleInterface = UInt32(RETRO_ENVIRONMENT_GET_RUMBLE_INTERFACE)
    static let getSensorInterface = UInt32(RETRO_ENVIRONMENT_GET_SENSOR_INTERFACE)
    static let getLogInterface = UInt32(RETRO_ENVIRONMENT_GET_LOG_INTERFACE)
    static let getSaveDirectory = UInt32(RETRO_ENVIRONMENT_GET_SAVE_DIRECTORY)
    static let setSystemAVInfo = UInt32(RETRO_ENVIRONMENT_SET_SYSTEM_AV_INFO)
    static let setMemoryMaps = UInt32(RETRO_ENVIRONMENT_SET_MEMORY_MAPS)
    static let setGeometry = UInt32(RETRO_ENVIRONMENT_SET_GEOMETRY)
    static let setSupportAchievements = UInt32(RETRO_ENVIRONMENT_SET_SUPPORT_ACHIEVEMENTS)
    static let getInputBitmasks = UInt32(RETRO_ENVIRONMENT_GET_INPUT_BITMASKS)
    static let getCoreOptionsVersion = UInt32(RETRO_ENVIRONMENT_GET_CORE_OPTIONS_VERSION)
    static let setMessageExtended = UInt32(RETRO_ENVIRONMENT_SET_MESSAGE_EXT)
    static let getJITCapable = UInt32(RETRO_ENVIRONMENT_GET_JIT_CAPABLE)
}
