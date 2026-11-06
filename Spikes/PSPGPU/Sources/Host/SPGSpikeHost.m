#import "SPGSpikeHost.h"

#import "SPGFrame.h"
#import "SPGGLESRenderer.h"
#import "SPGVulkanRenderer.h"

#import <dlfcn.h>
#import <libretro.h>
#import <os/lock.h>
#import <stdarg.h>
#import <time.h>

@implementation SPGConfiguration

- (instancetype)initWithBackend:(SPGBackend)backend
                     frameCount:(NSInteger)frameCount
                    renderScale:(NSInteger)renderScale
                  captureFrames:(NSArray<NSNumber *> *)captureFrames
                     contentURL:(NSURL *)contentURL
                outputDirectory:(NSURL *)outputDirectory
            waitForGPUEachFrame:(BOOL)waitForGPUEachFrame {
    self = [super init];
    if (self) {
        _backend = backend;
        _waitForGPUEachFrame = waitForGPUEachFrame;
        _frameCount = frameCount;
        _renderScale = renderScale;
        _captureFrames = [captureFrames copy];
        _contentURL = [contentURL copy];
        _outputDirectory = [outputDirectory copy];
    }
    return self;
}

@end

@interface SPGResult ()
- (instancetype)initWithSucceeded:(BOOL)succeeded
                           report:(NSString *)report
                   capturedImages:(NSArray<NSURL *> *)capturedImages NS_DESIGNATED_INITIALIZER;
@end

@implementation SPGResult

- (instancetype)initWithSucceeded:(BOOL)succeeded report:(NSString *)report capturedImages:(NSArray<NSURL *> *)images {
    self = [super init];
    if (self) {
        _succeeded = succeeded;
        _report = [report copy];
        _capturedImages = [images copy];
    }
    return self;
}

@end

/// The libretro entry points, resolved with dlsym.
typedef struct {
    unsigned (*api_version)(void);
    void (*set_environment)(retro_environment_t);
    void (*set_video_refresh)(retro_video_refresh_t);
    void (*set_audio_sample)(retro_audio_sample_t);
    void (*set_audio_sample_batch)(retro_audio_sample_batch_t);
    void (*set_input_poll)(retro_input_poll_t);
    void (*set_input_state)(retro_input_state_t);
    void (*get_system_info)(struct retro_system_info *);
    void (*get_system_av_info)(struct retro_system_av_info *);
    void (*init)(void);
    void (*deinit)(void);
    bool (*load_game)(const struct retro_game_info *);
    void (*unload_game)(void);
    void (*run)(void);
} SPGCore;

static NSString *SPGBackendName(SPGBackend backend) {
    switch (backend) {
    case SPGBackendOpenGLES:
        return @"gles";
    case SPGBackendVulkan:
        return @"vulkan";
    case SPGBackendSoftware:
        return @"software";
    }
    return @"?";
}

static NSString *SPGContextTypeName(unsigned type) {
    switch (type) {
    case RETRO_HW_CONTEXT_NONE:
        return @"NONE";
    case RETRO_HW_CONTEXT_OPENGL:
        return @"OPENGL";
    case RETRO_HW_CONTEXT_OPENGLES2:
        return @"OPENGLES2";
    case RETRO_HW_CONTEXT_OPENGL_CORE:
        return @"OPENGL_CORE";
    case RETRO_HW_CONTEXT_OPENGLES3:
        return @"OPENGLES3";
    case RETRO_HW_CONTEXT_OPENGLES_VERSION:
        return @"OPENGLES_VERSION";
    case RETRO_HW_CONTEXT_VULKAN:
        return @"VULKAN";
    case RETRO_HW_CONTEXT_D3D11:
        return @"D3D11";
    case RETRO_HW_CONTEXT_D3D10:
        return @"D3D10";
    case RETRO_HW_CONTEXT_D3D12:
        return @"D3D12";
    case RETRO_HW_CONTEXT_D3D9:
        return @"D3D9";
    default:
        return [NSString stringWithFormat:@"%u", type];
    }
}

// Names of the environment commands this libretro.h defines, for the report.
#define SPG_COMMAND(name) {RETRO_ENVIRONMENT_##name, #name}
static const struct {
    unsigned command;
    const char *name;
} SPGCommandNames[] = {
    SPG_COMMAND(SET_ROTATION),
    SPG_COMMAND(GET_OVERSCAN),
    SPG_COMMAND(GET_CAN_DUPE),
    SPG_COMMAND(SET_MESSAGE),
    SPG_COMMAND(SHUTDOWN),
    SPG_COMMAND(SET_PERFORMANCE_LEVEL),
    SPG_COMMAND(GET_SYSTEM_DIRECTORY),
    SPG_COMMAND(SET_PIXEL_FORMAT),
    SPG_COMMAND(SET_INPUT_DESCRIPTORS),
    SPG_COMMAND(SET_KEYBOARD_CALLBACK),
    SPG_COMMAND(SET_DISK_CONTROL_INTERFACE),
    SPG_COMMAND(SET_HW_RENDER),
    SPG_COMMAND(GET_VARIABLE),
    SPG_COMMAND(SET_VARIABLES),
    SPG_COMMAND(GET_VARIABLE_UPDATE),
    SPG_COMMAND(SET_SUPPORT_NO_GAME),
    SPG_COMMAND(GET_LIBRETRO_PATH),
    SPG_COMMAND(SET_FRAME_TIME_CALLBACK),
    SPG_COMMAND(SET_AUDIO_CALLBACK),
    SPG_COMMAND(GET_RUMBLE_INTERFACE),
    SPG_COMMAND(GET_INPUT_DEVICE_CAPABILITIES),
    SPG_COMMAND(GET_SENSOR_INTERFACE),
    SPG_COMMAND(GET_CAMERA_INTERFACE),
    SPG_COMMAND(GET_LOG_INTERFACE),
    SPG_COMMAND(GET_PERF_INTERFACE),
    SPG_COMMAND(GET_LOCATION_INTERFACE),
    SPG_COMMAND(GET_CONTENT_DIRECTORY),
    SPG_COMMAND(GET_SAVE_DIRECTORY),
    SPG_COMMAND(SET_SYSTEM_AV_INFO),
    SPG_COMMAND(SET_PROC_ADDRESS_CALLBACK),
    SPG_COMMAND(SET_SUBSYSTEM_INFO),
    SPG_COMMAND(SET_CONTROLLER_INFO),
    SPG_COMMAND(SET_MEMORY_MAPS),
    SPG_COMMAND(SET_GEOMETRY),
    SPG_COMMAND(GET_USERNAME),
    SPG_COMMAND(GET_LANGUAGE),
    SPG_COMMAND(GET_CURRENT_SOFTWARE_FRAMEBUFFER),
    SPG_COMMAND(GET_HW_RENDER_INTERFACE),
    SPG_COMMAND(SET_SUPPORT_ACHIEVEMENTS),
    SPG_COMMAND(SET_HW_RENDER_CONTEXT_NEGOTIATION_INTERFACE),
    SPG_COMMAND(SET_SERIALIZATION_QUIRKS),
    SPG_COMMAND(GET_VFS_INTERFACE),
    SPG_COMMAND(GET_LED_INTERFACE),
    SPG_COMMAND(GET_AUDIO_VIDEO_ENABLE),
    SPG_COMMAND(GET_MIDI_INTERFACE),
    SPG_COMMAND(GET_FASTFORWARDING),
    SPG_COMMAND(GET_TARGET_REFRESH_RATE),
    SPG_COMMAND(GET_INPUT_BITMASKS),
    SPG_COMMAND(GET_CORE_OPTIONS_VERSION),
    SPG_COMMAND(SET_CORE_OPTIONS),
    SPG_COMMAND(SET_CORE_OPTIONS_INTL),
    SPG_COMMAND(SET_CORE_OPTIONS_DISPLAY),
    SPG_COMMAND(GET_PREFERRED_HW_RENDER),
    SPG_COMMAND(GET_DISK_CONTROL_INTERFACE_VERSION),
    SPG_COMMAND(SET_DISK_CONTROL_EXT_INTERFACE),
    SPG_COMMAND(GET_MESSAGE_INTERFACE_VERSION),
    SPG_COMMAND(SET_MESSAGE_EXT),
    SPG_COMMAND(GET_INPUT_MAX_USERS),
    SPG_COMMAND(SET_AUDIO_BUFFER_STATUS_CALLBACK),
    SPG_COMMAND(SET_MINIMUM_AUDIO_LATENCY),
    SPG_COMMAND(SET_FASTFORWARDING_OVERRIDE),
    SPG_COMMAND(SET_CONTENT_INFO_OVERRIDE),
    SPG_COMMAND(GET_GAME_INFO_EXT),
    SPG_COMMAND(SET_CORE_OPTIONS_V2),
    SPG_COMMAND(SET_CORE_OPTIONS_V2_INTL),
    SPG_COMMAND(SET_CORE_OPTIONS_UPDATE_DISPLAY_CALLBACK),
    SPG_COMMAND(SET_VARIABLE),
    SPG_COMMAND(GET_THROTTLE_STATE),
    SPG_COMMAND(GET_SAVESTATE_CONTEXT),
    SPG_COMMAND(GET_HW_RENDER_CONTEXT_NEGOTIATION_INTERFACE_SUPPORT),
    SPG_COMMAND(GET_JIT_CAPABLE),
    SPG_COMMAND(GET_MICROPHONE_INTERFACE),
    SPG_COMMAND(GET_DEVICE_POWER),
    SPG_COMMAND(SET_NETPACKET_INTERFACE),
    SPG_COMMAND(GET_PLAYLIST_DIRECTORY),
    SPG_COMMAND(GET_FILE_BROWSER_START_DIRECTORY),
    SPG_COMMAND(GET_TARGET_SAMPLE_RATE),
};
#undef SPG_COMMAND

static NSString *SPGCommandName(unsigned command) {
    for (size_t i = 0; i < sizeof(SPGCommandNames) / sizeof(SPGCommandNames[0]); i++) {
        if (SPGCommandNames[i].command == command) {
            return @(SPGCommandNames[i].name);
        }
    }
    return [NSString stringWithFormat:@"%u", command];
}

static uint64_t SPGNow(void) {
    return clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
}

@interface SPGSpikeHost ()
- (void)note:(NSString *)format, ... NS_FORMAT_FUNCTION(1, 2);
- (bool)handleEnvironment:(unsigned)command data:(void *)data;
- (void)logFromCore:(enum retro_log_level)level message:(const char *)message;
- (void)videoRefresh:(const void *)data width:(unsigned)width height:(unsigned)height pitch:(size_t)pitch;
- (void)audioFrames:(size_t)frames;
@end

// libretro callbacks carry no context pointer, so they reach the one active
// host through this variable (plan, section 5, guideline 3).
static SPGSpikeHost *sActiveHost;
static GLuint sFramebuffer;

static bool SPGEnvironment(unsigned command, void *data) {
    return [sActiveHost handleEnvironment:command data:data];
}

static void SPGLog(enum retro_log_level level, const char *format, ...) {
    char message[2048];
    va_list arguments;
    va_start(arguments, format);
    vsnprintf(message, sizeof(message), format, arguments);
    va_end(arguments);
    [sActiveHost logFromCore:level message:message];
}

static void SPGVideoRefresh(const void *data, unsigned width, unsigned height, size_t pitch) {
    [sActiveHost videoRefresh:data width:width height:height pitch:pitch];
}

static void SPGAudioSample(int16_t left, int16_t right) {
    (void)left;
    (void)right;
    [sActiveHost audioFrames:1];
}

static size_t SPGAudioSampleBatch(const int16_t *data, size_t frames) {
    (void)data;
    [sActiveHost audioFrames:frames];
    return frames;
}

static void SPGInputPoll(void) {}

static int16_t SPGInputState(unsigned port, unsigned device, unsigned index, unsigned id) {
    (void)port;
    (void)device;
    (void)index;
    (void)id;
    return 0;
}

static uintptr_t SPGGetCurrentFramebuffer(void) {
    return sFramebuffer;
}

static retro_proc_address_t SPGGetProcAddress(const char *symbol) {
    return (retro_proc_address_t)dlsym(RTLD_DEFAULT, symbol);
}

@implementation SPGSpikeHost {
    SPGConfiguration *_configuration;
    NSMutableArray<NSString *> *_report;
    NSDictionary<NSString *, NSData *> *_variables;
    NSData *_systemDirectory;
    NSData *_saveDirectory;
    FILE *_coreLog;
    os_unfair_lock _logLock;
    // The core may call back from its own threads, for example during boot.
    os_unfair_lock _stateLock;
    NSUInteger _coreWarnings;
    NSUInteger _coreErrors;
    NSCountedSet<NSNumber *> *_environmentCalls;
    NSMutableSet<NSNumber *> *_unhandledCalls;
    enum retro_pixel_format _pixelFormat;
    struct retro_hw_render_callback _hwRender;
    BOOL _hwRenderAccepted;
    NSString *_hwRenderRequests;
    const struct retro_hw_render_context_negotiation_interface *_negotiation;
    SPGVulkanRenderer *_vulkan;
    NSUInteger _videoCalls;
    NSUInteger _hardwareFrames;
    NSUInteger _softwareFrames;
    NSUInteger _dupedFrames;
    unsigned _frameWidth;
    unsigned _frameHeight;
    NSMutableData *_softwarePixels;
    NSUInteger _softwarePitch;
    uint64_t _audioFrames;
    BOOL _shutdownRequested;
}

- (instancetype)initWithConfiguration:(SPGConfiguration *)configuration {
    self = [super init];
    if (self) {
        _configuration = configuration;
        _report = [NSMutableArray array];
        _environmentCalls = [NSCountedSet set];
        _unhandledCalls = [NSMutableSet set];
        _logLock = OS_UNFAIR_LOCK_INIT;
        _stateLock = OS_UNFAIR_LOCK_INIT;
        _hwRenderRequests = @"";
    }
    return self;
}

- (void)startWithCompletion:(void (^)(SPGResult *))completion {
    NSThread *thread = [[NSThread alloc] initWithBlock:^{
        SPGResult *result = [self run];
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(result);
        });
    }];
    thread.name = @"Emulation";
    thread.stackSize = 16 << 20;
    thread.qualityOfService = NSQualityOfServiceUserInteractive;
    [thread start];
}

- (void)note:(NSString *)format, ... {
    va_list arguments;
    va_start(arguments, format);
    NSString *line = [[NSString alloc] initWithFormat:format arguments:arguments];
    va_end(arguments);
    os_unfair_lock_lock(&_stateLock);
    [_report addObject:line];
    printf("SPIKE %s\n", line.UTF8String);
    fflush(stdout);
    os_unfair_lock_unlock(&_stateLock);
}

static NSData *SPGCString(NSString *string) {
    return [NSData dataWithBytes:string.UTF8String length:strlen(string.UTF8String) + 1];
}

#pragma mark - Run

- (SPGResult *)run {
    NSArray<NSURL *> *captured = @[];
    BOOL succeeded = NO;
    if (sActiveHost) {
        [self note:@"error: another run is active"];
    } else {
        sActiveHost = self;
        succeeded = [self runCore:&captured];
        sActiveHost = nil;
    }
    if (_coreLog) {
        fclose(_coreLog);
        _coreLog = NULL;
    }
    return [[SPGResult alloc] initWithSucceeded:succeeded
                                         report:[_report componentsJoinedByString:@"\n"]
                                 capturedImages:captured];
}

- (BOOL)runCore:(NSArray<NSURL *> **)captured {
    SPGConfiguration *configuration = _configuration;
    NSString *backendName = SPGBackendName(configuration.backend);
    NSFileManager *files = NSFileManager.defaultManager;
    NSURL *output = configuration.outputDirectory;
    NSURL *saves = [output URLByAppendingPathComponent:@"saves" isDirectory:YES];
    [files createDirectoryAtURL:saves withIntermediateDirectories:YES attributes:nil error:NULL];
    _coreLog = fopen([output URLByAppendingPathComponent:@"core.log"].fileSystemRepresentation, "w");
    if (_coreLog) {
        setvbuf(_coreLog, NULL, _IOLBF, 0);
    }
    [self note:@"backend %@, %ld frames, render scale %ld, content %@%@", backendName, (long)configuration.frameCount,
               (long)configuration.renderScale, configuration.contentURL.lastPathComponent,
               configuration.waitForGPUEachFrame ? @", waiting for the GPU after every frame" : @""];

    // Load the core from the app bundle (plan, section 5, guideline 1).
    NSString *frameworkPath =
        [NSBundle.mainBundle.privateFrameworksPath stringByAppendingPathComponent:@"ppsspp_libretro.framework"];
    NSString *binaryPath = [frameworkPath stringByAppendingPathComponent:@"ppsspp_libretro"];
    uint64_t loadStart = SPGNow();
    void *library = dlopen(binaryPath.fileSystemRepresentation, RTLD_NOW | RTLD_LOCAL);
    if (!library) {
        [self note:@"error: dlopen failed: %s", dlerror()];
        return NO;
    }
    SPGCore core = {0};
#define SPG_RESOLVE(field, symbol)                                                                                     \
    core.field = (__typeof__(core.field))dlsym(library, #symbol);                                                      \
    if (!core.field) {                                                                                                 \
        [self note:@"error: %s is missing", #symbol];                                                                  \
        return NO;                                                                                                     \
    }
    SPG_RESOLVE(api_version, retro_api_version)
    SPG_RESOLVE(set_environment, retro_set_environment)
    SPG_RESOLVE(set_video_refresh, retro_set_video_refresh)
    SPG_RESOLVE(set_audio_sample, retro_set_audio_sample)
    SPG_RESOLVE(set_audio_sample_batch, retro_set_audio_sample_batch)
    SPG_RESOLVE(set_input_poll, retro_set_input_poll)
    SPG_RESOLVE(set_input_state, retro_set_input_state)
    SPG_RESOLVE(get_system_info, retro_get_system_info)
    SPG_RESOLVE(get_system_av_info, retro_get_system_av_info)
    SPG_RESOLVE(init, retro_init)
    SPG_RESOLVE(deinit, retro_deinit)
    SPG_RESOLVE(load_game, retro_load_game)
    SPG_RESOLVE(unload_game, retro_unload_game)
    SPG_RESOLVE(run, retro_run)
#undef SPG_RESOLVE
    [self note:@"dlopen %@ in %.1f ms", [binaryPath substringFromIndex:NSBundle.mainBundle.bundlePath.length],
               (SPGNow() - loadStart) / 1e6];
    if (core.api_version() != RETRO_API_VERSION) {
        [self note:@"error: libretro API %u, host expects %u", core.api_version(), RETRO_API_VERSION];
        return NO;
    }

    _systemDirectory = SPGCString([frameworkPath stringByAppendingPathComponent:@"system"]);
    _saveDirectory = SPGCString(saves.path);
    NSString *resolution = [NSString stringWithFormat:@"%ldx%ld", (long)(480 * configuration.renderScale),
                                                      (long)(272 * configuration.renderScale)];
    NSString *coreBackend = configuration.backend == SPGBackendOpenGLES ? @"opengl"
                            : configuration.backend == SPGBackendVulkan ? @"vulkan"
                                                                        : @"none";
    // "IR JIT" is PPSSPP's IR interpreter, which generates no machine code.
    NSDictionary<NSString *, NSString *> *variables = @{
        @"ppsspp_backend" : coreBackend,
        @"ppsspp_cpu_core" : @"IR JIT",
        @"ppsspp_internal_resolution" : resolution,
        @"ppsspp_inflight_frames" : @"No buffer",
    };
    NSMutableDictionary<NSString *, NSData *> *variableData = [NSMutableDictionary dictionary];
    [variables enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, BOOL *stop) {
        (void)stop;
        variableData[key] = SPGCString(value);
    }];
    _variables = variableData;
    [self note:@"core options %@",
               [[variables.allKeys sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@", "]];

    core.set_environment(SPGEnvironment);
    core.set_video_refresh(SPGVideoRefresh);
    core.set_audio_sample(SPGAudioSample);
    core.set_audio_sample_batch(SPGAudioSampleBatch);
    core.set_input_poll(SPGInputPoll);
    core.set_input_state(SPGInputState);

    struct retro_system_info info = {0};
    core.get_system_info(&info);
    [self note:@"core %s %s, extensions %s, need_fullpath %d", info.library_name, info.library_version,
               info.valid_extensions, info.need_fullpath];

    core.init();
    struct retro_game_info game = {.path = configuration.contentURL.fileSystemRepresentation};
    uint64_t loadGameStart = SPGNow();
    if (!core.load_game(&game)) {
        [self note:@"error: retro_load_game failed (hardware context requests: %@)", _hwRenderRequests];
        core.deinit();
        return NO;
    }
    [self note:@"retro_load_game in %.1f ms; hardware context requests: %@", (SPGNow() - loadGameStart) / 1e6,
               _hwRenderRequests.length ? _hwRenderRequests : @"none"];

    struct retro_system_av_info av = {0};
    core.get_system_av_info(&av);
    [self note:@"av info %ux%u (max %ux%u), %.3f fps, %.0f Hz audio", av.geometry.base_width,
               av.geometry.base_height, av.geometry.max_width, av.geometry.max_height, av.timing.fps,
               av.timing.sample_rate];

    SPGGLESRenderer *gles = nil;
    if (configuration.backend != SPGBackendSoftware && !_hwRenderAccepted) {
        [self note:@"error: the core did not set up a %@ hardware context", backendName];
        core.unload_game();
        core.deinit();
        return NO;
    }
    if (configuration.backend == SPGBackendOpenGLES) {
        NSString *error = nil;
        gles = [[SPGGLESRenderer alloc] initWithWidth:(GLsizei)av.geometry.max_width
                                               height:(GLsizei)av.geometry.max_height
                                                error:&error];
        if (!gles) {
            [self note:@"error: OpenGL ES setup failed: %@", error];
            core.unload_game();
            core.deinit();
            return NO;
        }
        sFramebuffer = gles.framebuffer;
        [self note:@"OpenGL ES: %@", gles.contextDescription];
        [self note:@"OpenGL ES interop: %@", gles.interopDescription];
    } else if (configuration.backend == SPGBackendVulkan) {
        NSString *error = nil;
        _vulkan = [[SPGVulkanRenderer alloc] initWithNegotiation:_negotiation
                                                            width:av.geometry.max_width
                                                           height:av.geometry.max_height
                                                            error:&error];
        if (!_vulkan) {
            [self note:@"error: Vulkan setup failed: %@", error];
            core.unload_game();
            core.deinit();
            return NO;
        }
        [self note:@"Vulkan: %@", _vulkan.deviceDescription];
    }
    if (_hwRender.context_reset) {
        uint64_t resetStart = SPGNow();
        _hwRender.context_reset();
        [self note:@"context_reset in %.1f ms", (SPGNow() - resetStart) / 1e6];
    }

    NSMutableArray<NSURL *> *images = [NSMutableArray array];
    NSSet<NSNumber *> *captureFrames = [NSSet setWithArray:configuration.captureFrames];
    NSInteger frameCount = configuration.frameCount;
    double *durations = calloc((size_t)frameCount, sizeof(double));
    NSInteger emulated = 0;
    NSInteger runs = 0;
    NSInteger firstEmulatedRun = -1;
    uint64_t emulationStart = 0;
    uint64_t bootDeadline = SPGNow() + 10 * NSEC_PER_SEC;
    BOOL failed = NO;
    while (emulated < frameCount && !_shutdownRequested && !failed) {
        if (firstEmulatedRun < 0 && SPGNow() > bootDeadline) {
            [self note:@"error: no emulated frame within 10 s of booting"];
            failed = YES;
            break;
        }
        NSUInteger hardwareBefore = _hardwareFrames;
        NSUInteger softwareBefore = _softwareFrames;
        uint64_t audioBefore = _audioFrames;
        uint64_t start = SPGNow();
        core.run();
        runs++;
        BOOL presented = _hardwareFrames > hardwareBefore || _softwareFrames > softwareBefore;
        if (_vulkan && presented) {
            NSString *error = nil;
            if (![_vulkan finishFrameWithWidth:_frameWidth height:_frameHeight error:&error]) {
                [self note:@"error: run %ld: %@", (long)runs, error];
                failed = YES;
            }
        }
        if (configuration.waitForGPUEachFrame) {
            [gles finish];
            [_vulkan waitIdle];
        }
        double duration = (SPGNow() - start) / 1e6;
        // A frame counts as emulated once the core delivers audio for it.
        // While PPSSPP boots on its loader thread, retro_run returns at once
        // with an empty frame. Pace those calls like a display would, so the
        // loader gets time; unloading during the boot crashes the core.
        if (_audioFrames == audioBefore) {
            if (firstEmulatedRun < 0) {
                usleep(1000);
            }
            continue;
        }
        if (firstEmulatedRun < 0) {
            firstEmulatedRun = runs;
            emulationStart = start;
        }
        durations[emulated] = duration;
        emulated++;
        if (presented && ([captureFrames containsObject:@(emulated)] || emulated == frameCount)) {
            NSURL *image = [self captureFrame:emulated gles:gles];
            if (image) {
                [images addObject:image];
            }
        }
    }
    double totalSeconds = emulationStart ? (SPGNow() - emulationStart) / 1e9 : 0;
    [self reportTimings:durations
                  count:emulated
                   runs:runs
       firstEmulatedRun:firstEmulatedRun
           totalSeconds:totalSeconds
            waitedForGPU:configuration.waitForGPUEachFrame];
    free(durations);

    // context_destroy first, then unload: PPSSPP frees its context in
    // retro_unload_game, so a later context_destroy would find none.
    [_vulkan waitIdle];
    [gles makeCurrent];
    if (_hwRender.context_destroy) {
        _hwRender.context_destroy();
    }
    core.unload_game();
    core.deinit();
    [gles tearDown];
    [_vulkan tearDown];
    sFramebuffer = 0;
    // No dlclose: PPSSPP keeps static state and threads that do not expect
    // the image to go away.

    [self note:@"video callbacks %lu (hardware %lu, software %lu, duplicate %lu), last size %ux%u",
               (unsigned long)_videoCalls, (unsigned long)_hardwareFrames, (unsigned long)_softwareFrames,
               (unsigned long)_dupedFrames, _frameWidth, _frameHeight];
    if (_vulkan) {
        [self note:@"Vulkan images received %lu, frames copied %lu", (unsigned long)_vulkan.imagesReceived,
                   (unsigned long)_vulkan.framesCopied];
        [self note:@"Vulkan interop: %@", _vulkan.interopDescription];
        if (_vulkan.exportedTextureDescription) {
            [self note:@"Vulkan exported texture: %@", _vulkan.exportedTextureDescription];
        }
    }
    [self note:@"audio frames %llu (%.2f s)", _audioFrames, _audioFrames / av.timing.sample_rate];
    [self note:@"core log: %lu warnings, %lu errors (core.log)", (unsigned long)_coreWarnings,
               (unsigned long)_coreErrors];
    [self note:@"environment calls: %@", [self environmentSummary]];
    *captured = images;
    BOOL succeeded = !failed && images.count > 0;
    [self note:@"result %@", succeeded ? @"OK" : @"FAILED"];
    return succeeded;
}

- (NSURL *)captureFrame:(NSInteger)frame gles:(SPGGLESRenderer *)gles {
    NSString *error = nil;
    SPGFrame *picture = nil;
    switch (_configuration.backend) {
    case SPGBackendOpenGLES:
        picture = [gles readFrameWithWidth:(GLsizei)_frameWidth
                                    height:(GLsizei)_frameHeight
                          bottomLeftOrigin:_hwRender.bottom_left_origin
                                     error:&error];
        break;
    case SPGBackendVulkan:
        picture = [_vulkan readFrameWithWidth:_frameWidth height:_frameHeight error:&error];
        break;
    case SPGBackendSoftware:
        if (_softwarePixels) {
            picture = [[SPGFrame alloc] initWithBytes:_softwarePixels.bytes
                                                width:_frameWidth
                                               height:_frameHeight
                                          bytesPerRow:_softwarePitch
                                             bottomUp:NO];
        } else {
            error = @"no software frame";
        }
        break;
    }
    if (!picture) {
        [self note:@"capture frame %ld failed: %@", (long)frame, error];
        return nil;
    }
    NSString *name = [NSString stringWithFormat:@"%@-frame-%04ld.png", SPGBackendName(_configuration.backend),
                                                (long)frame];
    NSURL *url = [_configuration.outputDirectory URLByAppendingPathComponent:name];
    NSError *writeError = nil;
    if (![picture writePNGToURL:url error:&writeError]) {
        [self note:@"capture frame %ld: PNG failed: %@", (long)frame, writeError];
        return nil;
    }
    [self note:@"capture frame %ld: %@ %lux%lu, drawn %.1f %%, sha256 %@", (long)frame, name,
               (unsigned long)picture.width, (unsigned long)picture.height, picture.coverage * 100,
               picture.pixelDigest];
    return url;
}

static int SPGCompareDoubles(const void *a, const void *b) {
    double left = *(const double *)a;
    double right = *(const double *)b;
    return (left > right) - (left < right);
}

- (void)reportTimings:(double *)durations
                count:(NSInteger)count
                 runs:(NSInteger)runs
     firstEmulatedRun:(NSInteger)firstEmulatedRun
         totalSeconds:(double)totalSeconds
         waitedForGPU:(BOOL)waitedForGPU {
    [self note:@"%ld retro_run calls, first emulated frame at call %ld; %ld emulated frames in %.2f s (%.1f frames/s)",
               (long)runs, (long)firstEmulatedRun, (long)count, totalSeconds,
               totalSeconds > 0 ? count / totalSeconds : 0];
    // Skip the first second so that the numbers describe steady emulation.
    NSInteger skip = count > 120 ? 60 : 0;
    NSInteger steady = count - skip;
    if (steady <= 0) {
        return;
    }
    double *sorted = malloc((size_t)steady * sizeof(double));
    memcpy(sorted, durations + skip, (size_t)steady * sizeof(double));
    qsort(sorted, (size_t)steady, sizeof(double), SPGCompareDoubles);
    double sum = 0;
    for (NSInteger i = 0; i < steady; i++) {
        sum += sorted[i];
    }
    [self note:@"frame time %@, frames %ld-%ld: mean %.2f ms, median %.2f ms, p95 %.2f ms, max %.2f ms "
               @"(simulator on the Mac's chip, not meaningful for the device)",
               waitedForGPU ? @"including GPU wait" : @"of retro_run", (long)skip + 1, (long)count, sum / steady,
               sorted[steady / 2], sorted[(steady * 95) / 100], sorted[steady - 1]];
    free(sorted);
}

- (NSString *)environmentSummary {
    NSArray<NSNumber *> *commands = [_environmentCalls.allObjects sortedArrayUsingSelector:@selector(compare:)];
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    for (NSNumber *command in commands) {
        [parts addObject:[NSString stringWithFormat:@"%@%@ x%lu", SPGCommandName(command.unsignedIntValue),
                                                    [_unhandledCalls containsObject:command] ? @" (unhandled)" : @"",
                                                    (unsigned long)[_environmentCalls countForObject:command]]];
    }
    return [parts componentsJoinedByString:@", "];
}

#pragma mark - Callbacks

- (bool)handleEnvironment:(unsigned)command data:(void *)data {
    os_unfair_lock_lock(&_stateLock);
    [_environmentCalls addObject:@(command)];
    os_unfair_lock_unlock(&_stateLock);
    SPGBackend backend = _configuration.backend;
    switch (command) {
    case RETRO_ENVIRONMENT_GET_LOG_INTERFACE:
        ((struct retro_log_callback *)data)->log = SPGLog;
        return true;
    case RETRO_ENVIRONMENT_GET_SYSTEM_DIRECTORY:
        *(const char **)data = _systemDirectory.bytes;
        return true;
    case RETRO_ENVIRONMENT_GET_SAVE_DIRECTORY:
        *(const char **)data = _saveDirectory.bytes;
        return true;
    case RETRO_ENVIRONMENT_GET_VARIABLE: {
        struct retro_variable *variable = data;
        NSData *value = variable->key ? _variables[@(variable->key)] : nil;
        variable->value = value.bytes;
        return value != nil;
    }
    case RETRO_ENVIRONMENT_GET_VARIABLE_UPDATE:
        *(bool *)data = false;
        return true;
    case RETRO_ENVIRONMENT_SET_VARIABLES:
    case RETRO_ENVIRONMENT_SET_CORE_OPTIONS_DISPLAY:
    case RETRO_ENVIRONMENT_SET_INPUT_DESCRIPTORS:
    case RETRO_ENVIRONMENT_SET_CONTROLLER_INFO:
        return true;
    case RETRO_ENVIRONMENT_SET_PIXEL_FORMAT: {
        enum retro_pixel_format format = *(const enum retro_pixel_format *)data;
        if (format != RETRO_PIXEL_FORMAT_XRGB8888) {
            return false;
        }
        _pixelFormat = format;
        return true;
    }
    case RETRO_ENVIRONMENT_GET_PREFERRED_HW_RENDER:
        if (backend == SPGBackendSoftware) {
            return false;
        }
        *(unsigned *)data = backend == SPGBackendVulkan ? RETRO_HW_CONTEXT_VULKAN : RETRO_HW_CONTEXT_OPENGLES3;
        return true;
    case RETRO_ENVIRONMENT_SET_HW_RENDER: {
        struct retro_hw_render_callback *callback = data;
        BOOL gles = callback->context_type == RETRO_HW_CONTEXT_OPENGLES2 ||
                    callback->context_type == RETRO_HW_CONTEXT_OPENGLES3 ||
                    callback->context_type == RETRO_HW_CONTEXT_OPENGLES_VERSION;
        BOOL accept = (backend == SPGBackendOpenGLES && gles) ||
                      (backend == SPGBackendVulkan && callback->context_type == RETRO_HW_CONTEXT_VULKAN);
        NSString *request = [NSString stringWithFormat:
                                          @"%@ v%u.%u (depth %d, stencil %d, bottom_left_origin %d, cache_context %d, "
                                          @"debug %d) -> %@",
                                          SPGContextTypeName(callback->context_type), callback->version_major,
                                          callback->version_minor, callback->depth, callback->stencil,
                                          callback->bottom_left_origin, callback->cache_context,
                                          callback->debug_context, accept ? @"accepted" : @"refused"];
        _hwRenderRequests = _hwRenderRequests.length ? [_hwRenderRequests stringByAppendingFormat:@"; %@", request]
                                                     : request;
        if (!accept) {
            return false;
        }
        if (gles) {
            callback->get_current_framebuffer = SPGGetCurrentFramebuffer;
            callback->get_proc_address = SPGGetProcAddress;
        }
        _hwRender = *callback;
        _hwRenderAccepted = YES;
        return true;
    }
    case RETRO_ENVIRONMENT_SET_HW_RENDER_CONTEXT_NEGOTIATION_INTERFACE:
        _negotiation = data;
        _hwRenderRequests = [_hwRenderRequests stringByAppendingFormat:@"; negotiation interface type %u v%u",
                                                                       _negotiation->interface_type,
                                                                       _negotiation->interface_version];
        return backend == SPGBackendVulkan;
    case RETRO_ENVIRONMENT_GET_HW_RENDER_INTERFACE:
        if (!_vulkan) {
            return false;
        }
        *(const struct retro_hw_render_interface **)data = _vulkan.renderInterface;
        return true;
    case RETRO_ENVIRONMENT_GET_JIT_CAPABLE:
        // The App Store build may not generate code (plan, section 8).
        *(bool *)data = false;
        return true;
    case RETRO_ENVIRONMENT_GET_LANGUAGE:
        *(unsigned *)data = RETRO_LANGUAGE_ENGLISH;
        return true;
    case RETRO_ENVIRONMENT_GET_USERNAME:
        *(const char **)data = "Arcfold";
        return true;
    case RETRO_ENVIRONMENT_GET_INPUT_BITMASKS:
        return true;
    case RETRO_ENVIRONMENT_GET_FASTFORWARDING:
        *(bool *)data = false;
        return true;
    case RETRO_ENVIRONMENT_GET_MESSAGE_INTERFACE_VERSION:
        *(unsigned *)data = 1;
        return true;
    case RETRO_ENVIRONMENT_SET_MESSAGE:
        [self note:@"core message: %s", ((const struct retro_message *)data)->msg];
        return true;
    case RETRO_ENVIRONMENT_SET_MESSAGE_EXT:
        [self note:@"core message: %s", ((const struct retro_message_ext *)data)->msg];
        return true;
    case RETRO_ENVIRONMENT_SET_SYSTEM_AV_INFO: {
        const struct retro_system_av_info *av = data;
        [self note:@"core changed av info: %ux%u, %.3f fps", av->geometry.base_width, av->geometry.base_height,
                   av->timing.fps];
        return true;
    }
    case RETRO_ENVIRONMENT_SET_GEOMETRY:
        return true;
    case RETRO_ENVIRONMENT_GET_CORE_OPTIONS_VERSION:
    case RETRO_ENVIRONMENT_GET_VFS_INTERFACE:
    case RETRO_ENVIRONMENT_SET_CORE_OPTIONS_UPDATE_DISPLAY_CALLBACK:
        // Not offered on purpose: legacy options, the core's own file access.
        return false;
    case RETRO_ENVIRONMENT_SHUTDOWN:
        [self note:@"core requested shutdown"];
        _shutdownRequested = YES;
        return true;
    default:
        os_unfair_lock_lock(&_stateLock);
        [_unhandledCalls addObject:@(command)];
        os_unfair_lock_unlock(&_stateLock);
        return false;
    }
}

- (void)logFromCore:(enum retro_log_level)level message:(const char *)message {
    static const char *const levels[] = {"debug", "info", "warn", "error"};
    const char *name = level <= RETRO_LOG_ERROR ? levels[level] : "?";
    size_t length = strlen(message);
    const char *newline = length > 0 && message[length - 1] == '\n' ? "" : "\n";
    os_unfair_lock_lock(&_logLock);
    if (_coreLog) {
        fprintf(_coreLog, "[%s] %s%s", name, message, newline);
    }
    if (level >= RETRO_LOG_WARN) {
        level == RETRO_LOG_WARN ? _coreWarnings++ : _coreErrors++;
        printf("CORE [%s] %s%s", name, message, newline);
    }
    os_unfair_lock_unlock(&_logLock);
}

- (void)videoRefresh:(const void *)data width:(unsigned)width height:(unsigned)height pitch:(size_t)pitch {
    _videoCalls++;
    if (data == NULL) {
        _dupedFrames++;
        return;
    }
    _frameWidth = width;
    _frameHeight = height;
    if (data == RETRO_HW_FRAME_BUFFER_VALID) {
        _hardwareFrames++;
        return;
    }
    _softwareFrames++;
    size_t length = pitch * height;
    if (_softwarePixels.length != length) {
        _softwarePixels = [NSMutableData dataWithLength:length];
    }
    memcpy(_softwarePixels.mutableBytes, data, length);
    _softwarePitch = pitch;
}

- (void)audioFrames:(size_t)frames {
    _audioFrames += frames;
}

@end
