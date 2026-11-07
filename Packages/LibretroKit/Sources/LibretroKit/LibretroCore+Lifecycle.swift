internal import CLibretro
import Darwin

/// The libretro functions a session calls besides `retro_api_version` and
/// `retro_get_system_info`, resolved once when the core is opened.
struct CoreFunctions {
    let setEnvironment: @convention(c) (retro_environment_t?) -> Void
    let setVideoRefresh: @convention(c) (retro_video_refresh_t?) -> Void
    let setAudioSample: @convention(c) (retro_audio_sample_t?) -> Void
    let setAudioSampleBatch: @convention(c) (retro_audio_sample_batch_t?) -> Void
    let setInputPoll: @convention(c) (retro_input_poll_t?) -> Void
    let setInputState: @convention(c) (retro_input_state_t?) -> Void
    let initialize: @convention(c) () -> Void
    let deinitialize: @convention(c) () -> Void
    let getSystemAVInfo: @convention(c) (UnsafeMutablePointer<retro_system_av_info>?) -> Void
    let loadGame: @convention(c) (UnsafePointer<retro_game_info>?) -> Bool
    let unloadGame: @convention(c) () -> Void
    let run: @convention(c) () -> Void
    let getMemoryData: @convention(c) (CUnsignedInt) -> UnsafeMutableRawPointer?
    let getMemorySize: @convention(c) (CUnsignedInt) -> Int

    init(handle: UnsafeMutableRawPointer, core name: String) throws(LibretroError) {
        setEnvironment = try LibretroCore.function("retro_set_environment", in: handle, core: name)
        setVideoRefresh = try LibretroCore.function("retro_set_video_refresh", in: handle, core: name)
        setAudioSample = try LibretroCore.function("retro_set_audio_sample", in: handle, core: name)
        setAudioSampleBatch = try LibretroCore.function("retro_set_audio_sample_batch", in: handle, core: name)
        setInputPoll = try LibretroCore.function("retro_set_input_poll", in: handle, core: name)
        setInputState = try LibretroCore.function("retro_set_input_state", in: handle, core: name)
        initialize = try LibretroCore.function("retro_init", in: handle, core: name)
        deinitialize = try LibretroCore.function("retro_deinit", in: handle, core: name)
        getSystemAVInfo = try LibretroCore.function("retro_get_system_av_info", in: handle, core: name)
        loadGame = try LibretroCore.function("retro_load_game", in: handle, core: name)
        unloadGame = try LibretroCore.function("retro_unload_game", in: handle, core: name)
        run = try LibretroCore.function("retro_run", in: handle, core: name)
        getMemoryData = try LibretroCore.function("retro_get_memory_data", in: handle, core: name)
        getMemorySize = try LibretroCore.function("retro_get_memory_size", in: handle, core: name)
    }
}

/// The lifecycle of a running core. Only `EmulationSession`'s emulation thread
/// calls these, in the order libretro prescribes: callbacks, `initialize`,
/// `loadGame`, `run` repeatedly, `unloadGame`, `deinitialize`.
extension LibretroCore {
    /// Installs the six callbacks. `retro_set_environment` comes first, because
    /// cores such as mGBA already call the environment from inside it.
    func installCallbacks(
        environment: retro_environment_t,
        videoRefresh: retro_video_refresh_t,
        audioSample: retro_audio_sample_t,
        audioSampleBatch: retro_audio_sample_batch_t,
        inputPoll: retro_input_poll_t,
        inputState: retro_input_state_t
    ) {
        functions.setEnvironment(environment)
        functions.setVideoRefresh(videoRefresh)
        functions.setAudioSample(audioSample)
        functions.setAudioSampleBatch(audioSampleBatch)
        functions.setInputPoll(inputPoll)
        functions.setInputState(inputState)
    }

    /// `retro_init`.
    func initialize() {
        functions.initialize()
    }

    /// `retro_deinit`.
    func deinitialize() {
        functions.deinitialize()
    }

    /// `retro_load_game`. `game` and the memory it points to must stay valid
    /// until `unloadGame()`.
    func loadGame(_ game: UnsafePointer<retro_game_info>) -> Bool {
        functions.loadGame(game)
    }

    /// `retro_unload_game`. Afterwards the memory regions of the game are gone.
    func unloadGame() {
        functions.unloadGame()
    }

    /// `retro_run`: one emulated frame, with the callbacks it triggers.
    func run() {
        functions.run()
    }

    /// `retro_get_system_av_info`. Valid after `loadGame`.
    func systemAVInfo() -> retro_system_av_info {
        var info = retro_system_av_info()
        functions.getSystemAVInfo(&info)
        return info
    }

    /// The memory region `id` (`RETRO_MEMORY_*`) at its current size, or nil if
    /// the core has none. The region belongs to the core: it can change size
    /// between frames (mGBA shrinks the save memory once it knows the save
    /// type) and is freed by `unloadGame()`.
    func memory(_ id: CUnsignedInt) -> UnsafeMutableRawBufferPointer? {
        guard let data = functions.getMemoryData(id) else { return nil }
        let size = functions.getMemorySize(id)
        guard size > 0 else { return nil }
        return UnsafeMutableRawBufferPointer(start: data, count: size)
    }

    /// The battery save memory (`RETRO_MEMORY_SAVE_RAM`).
    func saveMemory() -> UnsafeMutableRawBufferPointer? {
        memory(CUnsignedInt(RETRO_MEMORY_SAVE_RAM))
    }
}
