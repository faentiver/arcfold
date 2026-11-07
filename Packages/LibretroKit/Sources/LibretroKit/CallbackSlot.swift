internal import CLibretro
import Synchronization

/// The one callback slot of the process (plan, guardrail 3; ADR 0005, section 4).
///
/// libretro callbacks carry no context pointer, so every core reaches the host
/// through the six static trampolines below, and they forward to the context
/// whose address is in `active`. A session claims the slot before
/// `retro_set_environment`, because mGBA calls the environment from inside it,
/// and releases it after `retro_deinit`. While the slot is taken, no second
/// session can load.
enum CallbackSlot {
    /// The bits of the active context (unretained), 0 when no core is active.
    /// One atomic holds both facts, so there is no unsafe global state.
    private static let active = Atomic<UInt>(0)

    /// Takes the slot for `context`. False if another context holds it.
    /// The caller keeps `context` alive until `release`.
    static func claim(_ context: CallbackContext) -> Bool {
        active.compareExchange(expected: 0, desired: bits(of: context), ordering: .acquiringAndReleasing).exchanged
    }

    /// Frees the slot if `context` holds it.
    static func release(_ context: CallbackContext) {
        _ = active.compareExchange(expected: bits(of: context), desired: 0, ordering: .acquiringAndReleasing)
    }

    /// Whether any context holds the slot.
    static var isClaimed: Bool {
        active.load(ordering: .acquiring) != 0
    }

    /// The context the trampolines forward to.
    @inline(__always)
    static func current() -> CallbackContext? {
        guard let pointer = UnsafeRawPointer(bitPattern: active.load(ordering: .acquiring)) else {
            return nil
        }
        return Unmanaged<CallbackContext>.fromOpaque(pointer).takeUnretainedValue()
    }

    private static func bits(of context: CallbackContext) -> UInt {
        UInt(bitPattern: Unmanaged.passUnretained(context).toOpaque())
    }

    // The trampolines. Without an active context they answer like a host that
    // supports nothing, in case a core calls after `retro_deinit`.

    static let environment: retro_environment_t = { command, data in
        current()?.environment(command, data) ?? false
    }

    static let videoRefresh: retro_video_refresh_t = { data, width, height, pitch in
        current()?.videoRefresh(data, width, height, pitch)
    }

    static let audioSample: retro_audio_sample_t = { left, right in
        current()?.audioSample(left, right)
    }

    static let audioSampleBatch: retro_audio_sample_batch_t = { data, frames in
        current()?.audioSampleBatch(data, frames) ?? frames
    }

    static let inputPoll: retro_input_poll_t = {
        current()?.inputPoll()
    }

    static let inputState: retro_input_state_t = { port, device, index, id in
        current()?.inputState(port, device, index, id) ?? 0
    }
}
