import CLibretro
import Foundation
@testable import LibretroKit
import Testing

/// The one callback slot of the process and its trampolines (ADR 0005,
/// section 4). The only tests of this package that take the slot; serialized,
/// because the slot is global.
@Suite(.serialized)
struct CallbackSlotTests {
    @Test func aSecondClaimFailsUntilTheFirstIsReleased() {
        let first = Self.makeContext()
        let second = Self.makeContext()
        #expect(!CallbackSlot.isClaimed)

        #expect(CallbackSlot.claim(first))
        #expect(!CallbackSlot.claim(second))
        // Only the holder can release the slot.
        CallbackSlot.release(second)
        #expect(CallbackSlot.isClaimed)

        CallbackSlot.release(first)
        #expect(!CallbackSlot.isClaimed)
        #expect(CallbackSlot.claim(second))
        CallbackSlot.release(second)
        #expect(!CallbackSlot.isClaimed)
    }

    @Test func trampolinesForwardToTheContextInTheSlot() {
        let context = Self.makeContext()
        #expect(CallbackSlot.claim(context))
        defer { CallbackSlot.release(context) }

        var updated = true
        #expect(CallbackSlot.environment(EnvironmentCommand.getVariableUpdate, &updated))
        #expect(!updated)
        #expect(context.environmentCalls[EnvironmentCommand.getVariableUpdate] == 1)

        context.input.set(.select, from: .touch)
        CallbackSlot.inputPoll()
        let select = CallbackSlot.inputState(0, UInt32(RETRO_DEVICE_JOYPAD), 0, UInt32(RETRO_DEVICE_ID_JOYPAD_SELECT))
        #expect(select == 1)

        let samples: [Int16] = [5, 6, 7, 8]
        let consumed = samples.withUnsafeBufferPointer { CallbackSlot.audioSampleBatch($0.baseAddress, 2) }
        #expect(consumed == 2)
    }

    @Test func withoutAContextTheTrampolinesAnswerLikeAnEmptyHost() {
        #expect(!CallbackSlot.isClaimed)
        var updated = true
        #expect(!CallbackSlot.environment(EnvironmentCommand.getVariableUpdate, &updated))
        #expect(updated)
        CallbackSlot.inputPoll()
        #expect(CallbackSlot.inputState(0, UInt32(RETRO_DEVICE_JOYPAD), 0, UInt32(RETRO_DEVICE_ID_JOYPAD_MASK)) == 0)
        #expect(CallbackSlot.audioSampleBatch(nil, 3) == 3)
        CallbackSlot.videoRefresh(nil, 240, 160, 512)
        CallbackSlot.audioSample(1, 1)
    }

    static func makeContext() -> CallbackContext {
        let (_, events) = AsyncStream.makeStream(of: SessionEvent.self)
        return CallbackContext(
            coreOptions: [:],
            systemDirectory: URL(filePath: "/tmp/ArcfoldTests/System", directoryHint: .isDirectory),
            saveDirectory: URL(filePath: "/tmp/ArcfoldTests/Saves", directoryHint: .isDirectory),
            input: InputState(),
            events: events
        )
    }
}
