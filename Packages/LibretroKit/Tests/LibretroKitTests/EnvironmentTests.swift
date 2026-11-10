import CLibretro
import Foundation
@testable import LibretroKit
import Synchronization
import Testing

/// The callbacks of a session with C structures built by hand, without a core
/// (ADR 0005, section 4): environment, pictures, sound and input.
struct EnvironmentTests {
    // MARK: Core options

    @Test func setVariablesIsCopiedAndGetVariableAnswersWithStableStrings() {
        let (context, _) = makeContext(overrides: ["mgba_use_bios": "OFF"])
        let declarations: [String] = [
            "mgba_use_bios", "Use BIOS file if found (requires restart); ON|OFF",
            "mgba_frameskip", "Frameskip; 0|1|2|3",
            "mgba_idle_optimization", "Idle loop removal; Remove Known|Detect and Remove|Don't Remove",
        ]
        let strings = declarations.map { strdup($0)! }
        var variables = stride(from: 0, to: strings.count, by: 2).map {
            retro_variable(key: UnsafePointer(strings[$0]), value: UnsafePointer(strings[$0 + 1]))
        }
        variables.append(retro_variable(key: nil, value: nil))

        let handled = variables.withUnsafeMutableBufferPointer { buffer in
            context.environment(EnvironmentCommand.setVariables, buffer.baseAddress)
        }
        // mGBA frees its strings right after the call.
        strings.forEach { free($0) }

        #expect(handled)
        #expect(Set(context.options.declaredKeys) == ["mgba_use_bios", "mgba_frameskip", "mgba_idle_optimization"])
        let bios = variable("mgba_use_bios", in: context)
        let frameskip = variable("mgba_frameskip", in: context)
        let idle = variable("mgba_idle_optimization", in: context)
        #expect(bios.handled && bios.value == "OFF")
        #expect(frameskip.handled && frameskip.value == "0")
        #expect(idle.handled && idle.value == "Remove Known")
        // The same key always gets the same address, because cores keep it.
        #expect(variable("mgba_use_bios", in: context).address == bios.address)
        #expect(variable("mgba_idle_optimization", in: context).address == idle.address)

        let unknown = variable("mgba_unknown", in: context)
        #expect(!unknown.handled)
        #expect(unknown.address == nil)
        // An unknown key is a normal answer, not an unsupported command.
        #expect(context.unhandledCommands.isEmpty)
        #expect(context.environmentCalls[EnvironmentCommand.getVariable] == 6)
    }

    @Test func defaultsAreTheFirstValueOfTheDeclaration() {
        #expect(CoreOptions.defaultValue(of: "Use BIOS file if found; ON|OFF") == "ON")
        #expect(CoreOptions.defaultValue(of: "Solar sensor level;0|1|2") == "0")
        #expect(CoreOptions.defaultValue(of: "Idle loop removal; Remove Known|Don't Remove") == "Remove Known")
        #expect(CoreOptions.defaultValue(of: "ON|OFF") == "ON")
        #expect(CoreOptions.defaultValue(of: "Only one; single") == "single")
        #expect(CoreOptions.defaultValue(of: "Nothing; ") == "")
        #expect(CoreOptions.defaultValue(of: "") == "")
    }

    @Test func getVariableUpdateAnswersFalse() {
        let (context, _) = makeContext()
        var updated = true
        for _ in 0..<3 {
            updated = true
            #expect(context.environment(EnvironmentCommand.getVariableUpdate, &updated))
            #expect(!updated)
        }
        #expect(context.environmentCalls[EnvironmentCommand.getVariableUpdate] == 3)
    }

    // MARK: Queries and refusals

    @Test func inputBitmasksAreSupportedWithNullData() {
        let (context, _) = makeContext()
        #expect(context.environment(EnvironmentCommand.getInputBitmasks, nil))
        #expect(context.unhandledCommands.isEmpty)
    }

    @Test func queriesWithTheExpectedAnswerFalseAreNotCountedAsUnhandled() {
        let (context, _) = makeContext()
        var version: UInt32 = 99
        #expect(!context.environment(EnvironmentCommand.getCoreOptionsVersion, &version))
        #expect(version == 99)
        var jitCapable = true
        #expect(context.environment(EnvironmentCommand.getJITCapable, &jitCapable))
        #expect(!jitCapable)
        #expect(context.unhandledCommands.isEmpty)
    }

    @Test func refusedAndUnknownCommandsAreCounted() {
        let (context, _) = makeContext()
        #expect(!context.environment(EnvironmentCommand.setMemoryMaps, nil))
        #expect(!context.environment(EnvironmentCommand.setSupportAchievements, nil))
        #expect(!context.environment(EnvironmentCommand.setHWRender, nil))
        #expect(!context.environment(EnvironmentCommand.getRumbleInterface, nil))
        #expect(!context.environment(EnvironmentCommand.getSensorInterface, nil))
        #expect(!context.environment(EnvironmentCommand.setSystemAVInfo, nil))
        #expect(!context.environment(9_999, nil))
        #expect(!context.environment(9_999, nil))

        let refused: Set<UInt32> = [36 | 0x10000, 42 | 0x10000, 14, 23, 25 | 0x10000, 32, 9_999]
        #expect(context.unhandledCommands == refused)
        #expect(context.environmentCalls[9_999] == 2)
        #expect(context.environmentCalls[EnvironmentCommand.setMemoryMaps] == 1)
    }

    @Test func pixelFormatsRGB565AndXRGB8888AreAcceptedUntilTheSessionLoaded() {
        let (context, _) = makeContext()
        #expect(context.pixelFormat == .rgb1555)
        var format = RETRO_PIXEL_FORMAT_XRGB8888
        #expect(context.environment(EnvironmentCommand.setPixelFormat, &format))
        #expect(context.pixelFormat == .xrgb8888)
        format = RETRO_PIXEL_FORMAT_0RGB1555
        #expect(!context.environment(EnvironmentCommand.setPixelFormat, &format))
        #expect(context.pixelFormat == .xrgb8888)
        format = RETRO_PIXEL_FORMAT_RGB565
        #expect(context.environment(EnvironmentCommand.setPixelFormat, &format))
        #expect(context.pixelFormat == .rgb565)

        context.sessionDidLoad(geometry: Self.gbaGeometry)
        format = RETRO_PIXEL_FORMAT_XRGB8888
        #expect(!context.environment(EnvironmentCommand.setPixelFormat, &format))
        format = RETRO_PIXEL_FORMAT_RGB565
        #expect(context.environment(EnvironmentCommand.setPixelFormat, &format))
        #expect(context.pixelFormat == .rgb565)
    }

    @Test func directoriesLogAndDupeAreAnswered() {
        let (context, _) = makeContext()
        var path: UnsafePointer<CChar>?
        #expect(context.environment(EnvironmentCommand.getSystemDirectory, &path))
        #expect(path.map { String(cString: $0) } == "/tmp/ArcfoldTests/System")
        #expect(context.environment(EnvironmentCommand.getSaveDirectory, &path))
        #expect(path.map { String(cString: $0) } == "/tmp/ArcfoldTests/Saves")

        var log = retro_log_callback(log: nil)
        #expect(context.environment(EnvironmentCommand.getLogInterface, &log))
        #expect(log.log != nil)

        var canDupe = false
        #expect(context.environment(EnvironmentCommand.getCanDupe, &canDupe))
        #expect(canDupe)
        #expect(context.environment(EnvironmentCommand.setInputDescriptors, nil))
        #expect(context.unhandledCommands.isEmpty)
    }

    @Test func geometryChangesStayWithinTheMaximum() {
        let (context, _) = makeContext()
        var geometry = retro_game_geometry(
            base_width: 200, base_height: 100, max_width: 0, max_height: 0, aspect_ratio: 2
        )
        // Before the session knows its maximum size there is nothing to change.
        #expect(!context.environment(EnvironmentCommand.setGeometry, &geometry))

        context.sessionDidLoad(geometry: Self.gbaGeometry)
        #expect(context.environment(EnvironmentCommand.setGeometry, &geometry))
        #expect(context.geometry?.baseWidth == 200)
        #expect(context.geometry?.baseHeight == 100)
        #expect(context.geometry?.aspectRatio == 2)
        geometry.base_width = 1_000
        #expect(context.environment(EnvironmentCommand.setGeometry, &geometry))
        #expect(context.geometry?.baseWidth == 240)
    }

    @Test func messagesAndShutdownBecomeEvents() async {
        let (stream, continuation) = AsyncStream.makeStream(of: SessionEvent.self)
        let context = makeContext(events: continuation)
        "Saved".withCString { text in
            var message = retro_message(msg: text, frames: 60)
            #expect(context.environment(EnvironmentCommand.setMessage, &message))
        }
        "Loaded".withCString { text in
            var message = retro_message_ext()
            message.msg = text
            #expect(context.environment(EnvironmentCommand.setMessageExtended, &message))
        }
        #expect(!context.shutdownRequested)
        #expect(context.environment(EnvironmentCommand.shutdown, nil))
        #expect(context.shutdownRequested)
        continuation.finish()

        var events: [SessionEvent] = []
        for await event in stream {
            events.append(event)
        }
        #expect(events == [.coreMessage("Saved"), .coreMessage("Loaded"), .coreRequestedShutdown])
    }

    // MARK: Pictures

    @Test func picturesReachTheSinkWithoutThePaddingOfTheLastRow() {
        let (context, _) = makeContext()
        var format = RETRO_PIXEL_FORMAT_RGB565
        #expect(context.environment(EnvironmentCommand.setPixelFormat, &format))
        context.sessionDidLoad(geometry: Self.gbaGeometry)
        let sink = RecordingVideoSink()
        context.videoSink = sink
        let pixels = UnsafeMutableRawBufferPointer.allocate(byteCount: 512 * 160, alignment: 16)
        defer { pixels.deallocate() }
        pixels.initializeMemory(as: UInt8.self, repeating: 0x5A)

        context.beginFrame(FrameStamp(sequence: 7, nominalTime: 1_234))
        context.videoRefresh(pixels.baseAddress, 240, 160, 512)
        // A NULL picture repeats the previous one and does not reach the sink.
        context.videoRefresh(nil, 240, 160, 512)
        // Larger than the maximum, or a pitch shorter than a row: dropped.
        context.videoRefresh(pixels.baseAddress, 241, 160, 512)
        context.videoRefresh(pixels.baseAddress, 240, 160, 400)

        let calls = sink.calls
        #expect(calls.count == 1)
        #expect(calls.first == RecordingVideoSink.Call(
            byteCount: 512 * 159 + 240 * 2, width: 240, height: 160, bytesPerRow: 512,
            format: .rgb565, stamp: FrameStamp(sequence: 7, nominalTime: 1_234)
        ))
        #expect(context.rejectedFrames == 2)
    }

    // MARK: Sound

    @Test func batchesGoStraightToTheSinkAndSingleSamplesAtTheEndOfTheFrame() {
        let (context, _) = makeContext(singleSampleCapacity: 2)
        let status = AudioBufferStatus(bufferedFrames: 1_200, targetFrames: 1_145, isConsuming: true)
        let sink = RecordingAudioSink(status: status)
        context.audioSink = sink
        context.beginFrame(FrameStamp(sequence: 1, nominalTime: 0))
        #expect(context.lastAudioStatus == nil)

        let batch: [Int16] = [1, -1, 2, -2, 3, -3]
        let consumed = batch.withUnsafeBufferPointer { context.audioSampleBatch($0.baseAddress, 3) }
        #expect(consumed == 3)
        #expect(sink.writes == [batch])
        #expect(context.lastAudioStatus == status)
        #expect(context.audioFramesWritten == 3)

        context.audioSample(10, -10)
        context.audioSample(11, -11)
        #expect(sink.writes.count == 1)
        // The buffer holds two frames here; the third writes the first two.
        context.audioSample(12, -12)
        #expect(sink.writes.last == [10, -10, 11, -11])
        context.endFrame()
        #expect(sink.writes.last == [12, -12])
        #expect(sink.writes.count == 3)
        // Batch and single samples alike: the clock needs all audio frames
        // of the emulated frame to know the level before its sound.
        #expect(context.audioFramesWritten == 6)

        context.beginFrame(FrameStamp(sequence: 2, nominalTime: 0))
        #expect(context.lastAudioStatus == nil)
        #expect(context.audioFramesWritten == 0)
        context.endFrame()
        #expect(sink.writes.count == 3)
    }

    // MARK: Input

    @Test func inputStateAnswersTheMaskAndSingleButtonsOfPortZero() {
        let (context, _) = makeContext()
        context.input.set([.a, .start, .r3], from: .controller)
        context.inputPoll()
        let joypad = UInt32(RETRO_DEVICE_JOYPAD)
        let mask = context.inputState(0, joypad, 0, UInt32(RETRO_DEVICE_ID_JOYPAD_MASK))
        #expect(UInt16(bitPattern: mask) == UInt16(JoypadButtons([.a, .start, .r3]).rawValue))
        #expect(context.inputState(0, joypad, 0, UInt32(RETRO_DEVICE_ID_JOYPAD_A)) == 1)
        #expect(context.inputState(0, joypad, 0, UInt32(RETRO_DEVICE_ID_JOYPAD_B)) == 0)
        #expect(context.inputState(0, joypad, 0, UInt32(RETRO_DEVICE_ID_JOYPAD_R3)) == 1)
        #expect(context.inputState(0, joypad, 0, 16) == 0)
        // Other ports and devices see nothing.
        #expect(context.inputState(1, joypad, 0, UInt32(RETRO_DEVICE_ID_JOYPAD_MASK)) == 0)
        #expect(context.inputState(0, UInt32(RETRO_DEVICE_ANALOG), 0, 0) == 0)

        // The frame's buttons stay until the next poll.
        context.input.set([], from: .controller)
        #expect(context.inputState(0, joypad, 0, UInt32(RETRO_DEVICE_ID_JOYPAD_A)) == 1)
        context.inputPoll()
        #expect(context.inputState(0, joypad, 0, UInt32(RETRO_DEVICE_ID_JOYPAD_MASK)) == 0)
    }

    @Test func inputStateAnswersThePointerOfPortZero() {
        let (context, _) = makeContext()
        let pointer = UInt32(RETRO_DEVICE_POINTER)
        context.input.setPointer(PointerPosition(x: -7_295, y: 17_237))
        context.inputPoll()

        #expect(context.inputState(0, pointer, 0, UInt32(RETRO_DEVICE_ID_POINTER_X)) == -7_295)
        #expect(context.inputState(0, pointer, 0, UInt32(RETRO_DEVICE_ID_POINTER_Y)) == 17_237)
        #expect(context.inputState(0, pointer, 0, UInt32(RETRO_DEVICE_ID_POINTER_PRESSED)) == 1)
        #expect(context.inputState(0, pointer, 0, UInt32(RETRO_DEVICE_ID_POINTER_COUNT)) == 1)
        // One finger only, on port 0 only.
        #expect(context.inputState(0, pointer, 1, UInt32(RETRO_DEVICE_ID_POINTER_PRESSED)) == 0)
        #expect(context.inputState(1, pointer, 0, UInt32(RETRO_DEVICE_ID_POINTER_PRESSED)) == 0)
        // The pointer does not leak into the RetroPad.
        #expect(context.inputState(0, UInt32(RETRO_DEVICE_JOYPAD), 0, UInt32(RETRO_DEVICE_ID_JOYPAD_MASK)) == 0)

        // The frame keeps its pointer until the next poll.
        context.input.setPointer(nil)
        #expect(context.inputState(0, pointer, 0, UInt32(RETRO_DEVICE_ID_POINTER_PRESSED)) == 1)
        context.inputPoll()
        #expect(context.inputState(0, pointer, 0, UInt32(RETRO_DEVICE_ID_POINTER_PRESSED)) == 0)
        #expect(context.inputState(0, pointer, 0, UInt32(RETRO_DEVICE_ID_POINTER_COUNT)) == 0)
    }

    // MARK: Helpers

    static let gbaGeometry = VideoGeometry(baseWidth: 240, baseHeight: 160, maxWidth: 240, maxHeight: 160, aspectRatio: 1.5)

    private func makeContext(
        overrides: [String: String] = [:], singleSampleCapacity: Int = 4_096
    ) -> (CallbackContext, AsyncStream<SessionEvent>) {
        let (stream, continuation) = AsyncStream.makeStream(of: SessionEvent.self)
        let context = makeContext(overrides: overrides, events: continuation, singleSampleCapacity: singleSampleCapacity)
        return (context, stream)
    }

    private func makeContext(
        overrides: [String: String] = [:], events: AsyncStream<SessionEvent>.Continuation,
        singleSampleCapacity: Int = 4_096
    ) -> CallbackContext {
        CallbackContext(
            coreOptions: overrides,
            systemDirectory: URL(filePath: "/tmp/ArcfoldTests/System", directoryHint: .isDirectory),
            saveDirectory: URL(filePath: "/tmp/ArcfoldTests/Saves", directoryHint: .isDirectory),
            input: InputState(),
            events: events,
            singleSampleCapacity: singleSampleCapacity
        )
    }

    /// GET_VARIABLE for `key`: whether it was handled, the value and its address.
    private func variable(_ key: String, in context: CallbackContext) -> (handled: Bool, value: String?, address: UnsafePointer<CChar>?) {
        key.withCString { key in
            var variable = retro_variable(key: key, value: nil)
            let handled = context.environment(EnvironmentCommand.getVariable, &variable)
            return (handled, variable.value.map { String(cString: $0) }, variable.value)
        }
    }
}

/// Records what reaches a video sink.
final class RecordingVideoSink: VideoSink {
    struct Call: Hashable {
        var byteCount: Int
        var width: Int
        var height: Int
        var bytesPerRow: Int
        var format: PixelFormat
        var stamp: FrameStamp
    }

    private let recorded = Mutex<[Call]>([])

    var calls: [Call] {
        recorded.withLock { $0 }
    }

    func submit(pixels: RawSpan, width: Int, height: Int, bytesPerRow: Int, format: PixelFormat, stamp: FrameStamp) {
        let call = Call(
            byteCount: pixels.byteCount, width: width, height: height, bytesPerRow: bytesPerRow,
            format: format, stamp: stamp
        )
        recorded.withLock { $0.append(call) }
    }
}

/// Records what reaches an audio sink and answers with a fixed status.
final class RecordingAudioSink: AudioSink {
    private let status: AudioBufferStatus
    private let recorded = Mutex<[[Int16]]>([])

    init(status: AudioBufferStatus) {
        self.status = status
    }

    var writes: [[Int16]] {
        recorded.withLock { $0 }
    }

    func write(_ samples: Span<Int16>) -> AudioBufferStatus {
        let copy = samples.withUnsafeBufferPointer { Array($0) }
        recorded.withLock { $0.append(copy) }
        return status
    }
}
