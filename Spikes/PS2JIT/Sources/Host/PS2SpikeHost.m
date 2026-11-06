#import "PS2SpikeHost.h"

#import <CoreGraphics/CoreGraphics.h>
#import <ImageIO/ImageIO.h>
#import <OpenGLES/EAGL.h>
#import <OpenGLES/ES3/gl.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <dlfcn.h>
#import <os/lock.h>
#import <stdatomic.h>

#import "libretro.h"

static NSString *const PS2SpikeErrorDomain = @"PS2SpikeHost";

// The output framebuffer is larger than any PS2 display mode at 1x, so the
// core never draws outside of it.
static const GLsizei PS2FramebufferWidth = 1280;
static const GLsizei PS2FramebufferHeight = 1024;

typedef struct {
    void (*init)(void);
    unsigned (*apiVersion)(void);
    void (*getSystemInfo)(struct retro_system_info *info);
    void (*setEnvironment)(retro_environment_t);
    void (*setVideoRefresh)(retro_video_refresh_t);
    void (*setAudioSample)(retro_audio_sample_t);
    void (*setAudioSampleBatch)(retro_audio_sample_batch_t);
    void (*setInputPoll)(retro_input_poll_t);
    void (*setInputState)(retro_input_state_t);
    bool (*loadGame)(const struct retro_game_info *game);
    void (*run)(void);
} PS2CoreAPI;

// libretro callbacks carry no context pointer, so the single active run lives
// in file-scope state. The emulation thread writes it; the watcher reads the
// atomics and, under the lock, the last frame.
static struct {
    PS2CoreAPI api;
    bool jitCapable;
    struct retro_hw_render_callback hwRender;
    bool hwRenderAccepted;
    GLuint framebuffer;
    char coreMessage[512];
    _Atomic long retroRunCalls;
    _Atomic long framesPresented;
    _Atomic long audioFrames;
    _Atomic unsigned lastWidth;
    _Atomic unsigned lastHeight;
    _Atomic bool finished;
} g_run;

// Last presented frame as read back from the framebuffer, guarded by the lock.
static os_unfair_lock g_frameLock = OS_UNFAIR_LOCK_INIT;
static NSData *g_framePixels;
static unsigned g_framePixelsWidth;
static unsigned g_framePixelsHeight;

#pragma mark - Report types

@implementation PS2CoreInfo
- (instancetype)initWithInfo:(const struct retro_system_info *)info
                  apiVersion:(unsigned)apiVersion
                    corePath:(NSString *)corePath {
    if ((self = [super init])) {
        _libraryName = [NSString stringWithUTF8String:info->library_name ?: ""];
        _libraryVersion = [NSString stringWithUTF8String:info->library_version ?: ""];
        _validExtensions = [NSString stringWithUTF8String:info->valid_extensions ?: ""];
        _needFullpath = info->need_fullpath;
        _apiVersion = apiVersion;
        _corePath = [corePath copy];
    }
    return self;
}
@end

@interface PS2RunReport ()
@property (nonatomic, readwrite) BOOL reportedJITCapable;
@property (nonatomic, readwrite) BOOL gameLoaded;
@property (nonatomic, readwrite, copy, nullable) NSString *coreMessage;
@property (nonatomic, readwrite, copy) NSString *requestedContext;
@property (nonatomic, readwrite, copy) NSString *glRenderer;
@property (nonatomic, readwrite) NSInteger retroRunCalls;
@property (nonatomic, readwrite) NSInteger framesPresented;
@property (nonatomic, readwrite) double seconds;
@property (nonatomic, readwrite, copy) NSString *endReason;
@property (nonatomic, readwrite) NSInteger frameWidth;
@property (nonatomic, readwrite) NSInteger frameHeight;
@property (nonatomic, readwrite, copy, nullable) NSData *lastFramePNG;
@property (nonatomic, readwrite) NSInteger audioFrames;
@property (nonatomic, readwrite, copy) NSString *programOutput;
@property (nonatomic, readwrite, copy, nullable) NSString *error;
@end

@implementation PS2RunReport
- (instancetype)initEmpty {
    if ((self = [super init])) {
        _requestedContext = @"";
        _glRenderer = @"";
        _endReason = @"";
        _programOutput = @"";
    }
    return self;
}
@end

#pragma mark - libretro callbacks

static uintptr_t PS2CurrentFramebuffer(void) {
    return g_run.framebuffer;
}

static retro_proc_address_t PS2GetProcAddress(const char *symbol) {
    return (retro_proc_address_t)dlsym(RTLD_DEFAULT, symbol);
}

static NSString *PS2ContextName(enum retro_hw_context_type type) {
    switch (type) {
    case RETRO_HW_CONTEXT_OPENGL: return @"OpenGL";
    case RETRO_HW_CONTEXT_OPENGLES2: return @"OpenGL ES 2";
    case RETRO_HW_CONTEXT_OPENGL_CORE: return @"OpenGL Core";
    case RETRO_HW_CONTEXT_OPENGLES3: return @"OpenGL ES 3";
    case RETRO_HW_CONTEXT_OPENGLES_VERSION: return @"OpenGL ES (version)";
    case RETRO_HW_CONTEXT_VULKAN: return @"Vulkan";
    default: return [NSString stringWithFormat:@"type %d", (int)type];
    }
}

static bool PS2Environment(unsigned command, void *data) {
    switch (command) {
    case RETRO_ENVIRONMENT_GET_JIT_CAPABLE:
        *(bool *)data = g_run.jitCapable;
        return true;
    case RETRO_ENVIRONMENT_SET_MESSAGE: {
        const struct retro_message *message = data;
        snprintf(g_run.coreMessage, sizeof(g_run.coreMessage), "%s", message->msg ?: "");
        NSLog(@"[JITSpike] core message: %s", g_run.coreMessage);
        return true;
    }
    case RETRO_ENVIRONMENT_SET_PIXEL_FORMAT:
        return *(const enum retro_pixel_format *)data == RETRO_PIXEL_FORMAT_XRGB8888;
    case RETRO_ENVIRONMENT_SET_HW_RENDER: {
        struct retro_hw_render_callback *callback = data;
        g_run.hwRender = *callback;
        if (callback->context_type != RETRO_HW_CONTEXT_OPENGLES3) {
            g_run.hwRenderAccepted = false;
            return false;
        }
        callback->get_current_framebuffer = PS2CurrentFramebuffer;
        callback->get_proc_address = PS2GetProcAddress;
        g_run.hwRender = *callback;
        g_run.hwRenderAccepted = true;
        return true;
    }
    case RETRO_ENVIRONMENT_SET_HW_SHARED_CONTEXT:
    case RETRO_ENVIRONMENT_GET_INPUT_BITMASKS:
    case RETRO_ENVIRONMENT_SET_INPUT_DESCRIPTORS:
    case RETRO_ENVIRONMENT_SET_CONTROLLER_INFO:
    case RETRO_ENVIRONMENT_SET_VARIABLES:
        return true;
    case RETRO_ENVIRONMENT_GET_VARIABLE_UPDATE:
        *(bool *)data = false;
        return true;
    default:
        return false;
    }
}

/// Copies the presented frame while the GL context is current, so the watcher
/// can encode it even if retro_run never returns again.
static void PS2CaptureFrame(unsigned width, unsigned height) {
    if (width == 0 || height == 0 || width > (unsigned)PS2FramebufferWidth ||
        height > (unsigned)PS2FramebufferHeight) {
        return;
    }
    NSMutableData *pixels = [NSMutableData dataWithLength:(NSUInteger)width * height * 4];
    glBindFramebuffer(GL_FRAMEBUFFER, g_run.framebuffer);
    glPixelStorei(GL_PACK_ALIGNMENT, 1);
    glReadPixels(0, 0, (GLsizei)width, (GLsizei)height, GL_RGBA, GL_UNSIGNED_BYTE, pixels.mutableBytes);
    os_unfair_lock_lock(&g_frameLock);
    g_framePixels = pixels;
    g_framePixelsWidth = width;
    g_framePixelsHeight = height;
    os_unfair_lock_unlock(&g_frameLock);
}

static void PS2VideoRefresh(const void *frame, unsigned width, unsigned height, size_t pitch) {
    (void)pitch;
    if (frame == RETRO_HW_FRAME_BUFFER_VALID) {
        atomic_fetch_add(&g_run.framesPresented, 1);
        atomic_store(&g_run.lastWidth, width);
        atomic_store(&g_run.lastHeight, height);
        PS2CaptureFrame(width, height);
    }
}

static void PS2AudioSample(int16_t left, int16_t right) {
    (void)left;
    (void)right;
    atomic_fetch_add(&g_run.audioFrames, 1);
}

static size_t PS2AudioSampleBatch(const int16_t *samples, size_t frames) {
    (void)samples;
    atomic_fetch_add(&g_run.audioFrames, (long)frames);
    return frames;
}

static void PS2InputPoll(void) {}

static int16_t PS2InputState(unsigned port, unsigned device, unsigned index, unsigned identifier) {
    (void)port;
    (void)device;
    (void)index;
    (void)identifier;
    return 0;
}

#pragma mark - Host

@implementation PS2SpikeHost

+ (NSString *)corePath {
    NSURL *frameworks = NSBundle.mainBundle.privateFrameworksURL;
    return [frameworks URLByAppendingPathComponent:@"play_libretro.framework/play_libretro"].path;
}

+ (BOOL)loadCoreWithError:(NSError **)error {
    if (g_run.api.run != NULL) {
        return YES;
    }
    void *handle = dlopen(self.corePath.fileSystemRepresentation, RTLD_NOW | RTLD_LOCAL);
    if (handle == NULL) {
        if (error) {
            NSString *reason = [NSString stringWithUTF8String:dlerror() ?: "unknown"];
            *error = [NSError errorWithDomain:PS2SpikeErrorDomain code:1
                                     userInfo:@{NSLocalizedDescriptionKey : reason}];
        }
        return NO;
    }
    PS2CoreAPI api;
    struct { const char *name; void **slot; } symbols[] = {
        {"retro_init", (void **)&api.init},
        {"retro_api_version", (void **)&api.apiVersion},
        {"retro_get_system_info", (void **)&api.getSystemInfo},
        {"retro_set_environment", (void **)&api.setEnvironment},
        {"retro_set_video_refresh", (void **)&api.setVideoRefresh},
        {"retro_set_audio_sample", (void **)&api.setAudioSample},
        {"retro_set_audio_sample_batch", (void **)&api.setAudioSampleBatch},
        {"retro_set_input_poll", (void **)&api.setInputPoll},
        {"retro_set_input_state", (void **)&api.setInputState},
        {"retro_load_game", (void **)&api.loadGame},
        {"retro_run", (void **)&api.run},
    };
    for (size_t index = 0; index < sizeof(symbols) / sizeof(symbols[0]); index++) {
        *symbols[index].slot = dlsym(handle, symbols[index].name);
        if (*symbols[index].slot == NULL) {
            if (error) {
                NSString *reason = [NSString stringWithFormat:@"missing symbol %s", symbols[index].name];
                *error = [NSError errorWithDomain:PS2SpikeErrorDomain code:2
                                         userInfo:@{NSLocalizedDescriptionKey : reason}];
            }
            return NO;
        }
    }
    // The handle stays open for the lifetime of the process: the core owns
    // threads that must never see their code unmapped.
    g_run.api = api;
    return YES;
}

+ (nullable PS2CoreInfo *)loadCoreInfoWithError:(NSError **)error {
    if (![self loadCoreWithError:error]) {
        return nil;
    }
    struct retro_system_info info;
    memset(&info, 0, sizeof(info));
    g_run.api.getSystemInfo(&info);
    return [[PS2CoreInfo alloc] initWithInfo:&info apiVersion:g_run.api.apiVersion() corePath:self.corePath];
}

/// Play! keeps its settings in Documents/Play Data Files. The run enables
/// iop.fileio.stdlogging, which makes the IOP write the program's stdout to
/// ps2_stdout.txt.
+ (NSURL *)preparePlayDataDirectory {
    NSURL *documents = [NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory
                                                            inDomains:NSUserDomainMask].firstObject;
    NSURL *directory = [documents URLByAppendingPathComponent:@"Play Data Files" isDirectory:YES];
    [NSFileManager.defaultManager createDirectoryAtURL:directory withIntermediateDirectories:YES
                                            attributes:nil error:NULL];
    NSString *config = @"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
                       @"<Config>\n"
                       @"\t<Preference Name=\"iop.fileio.stdlogging\" Type=\"boolean\" Value=\"true\" />\n"
                       @"</Config>\n";
    [config writeToURL:[directory URLByAppendingPathComponent:@"config.xml"] atomically:YES
              encoding:NSUTF8StringEncoding error:NULL];
    [NSData.data writeToURL:[directory URLByAppendingPathComponent:@"ps2_stdout.txt"] atomically:YES];
    return directory;
}

+ (nullable NSData *)encodeLastFrame {
    os_unfair_lock_lock(&g_frameLock);
    NSData *pixels = g_framePixels;
    unsigned width = g_framePixelsWidth;
    unsigned height = g_framePixelsHeight;
    os_unfair_lock_unlock(&g_frameLock);
    if (pixels == nil) {
        return nil;
    }
    // OpenGL rows start at the bottom; image rows start at the top.
    size_t rowBytes = (size_t)width * 4;
    NSMutableData *flipped = [NSMutableData dataWithLength:pixels.length];
    for (unsigned row = 0; row < height; row++) {
        memcpy((uint8_t *)flipped.mutableBytes + row * rowBytes,
               (const uint8_t *)pixels.bytes + (height - 1 - row) * rowBytes, rowBytes);
    }
    CGColorSpaceRef colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)flipped);
    CGImageRef image = CGImageCreate(width, height, 8, 32, rowBytes, colorSpace,
                                     (CGBitmapInfo)kCGImageAlphaNoneSkipLast, provider, NULL, false,
                                     kCGRenderingIntentDefault);
    NSMutableData *png = [NSMutableData data];
    CGImageDestinationRef destination =
        CGImageDestinationCreateWithData((__bridge CFMutableDataRef)png,
                                         (__bridge CFStringRef)UTTypePNG.identifier, 1, NULL);
    CGImageDestinationAddImage(destination, image, NULL);
    bool written = CGImageDestinationFinalize(destination);
    CFRelease(destination);
    CGImageRelease(image);
    CGDataProviderRelease(provider);
    CGColorSpaceRelease(colorSpace);
    return written ? png : nil;
}

+ (BOOL)createFramebufferWithError:(NSString **)error {
    GLuint color = 0;
    GLuint depth = 0;
    glGenFramebuffers(1, &g_run.framebuffer);
    glBindFramebuffer(GL_FRAMEBUFFER, g_run.framebuffer);
    glGenRenderbuffers(1, &color);
    glBindRenderbuffer(GL_RENDERBUFFER, color);
    glRenderbufferStorage(GL_RENDERBUFFER, GL_RGBA8, PS2FramebufferWidth, PS2FramebufferHeight);
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, color);
    glGenRenderbuffers(1, &depth);
    glBindRenderbuffer(GL_RENDERBUFFER, depth);
    glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH24_STENCIL8, PS2FramebufferWidth, PS2FramebufferHeight);
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_STENCIL_ATTACHMENT, GL_RENDERBUFFER, depth);
    GLenum status = glCheckFramebufferStatus(GL_FRAMEBUFFER);
    if (status != GL_FRAMEBUFFER_COMPLETE) {
        *error = [NSString stringWithFormat:@"framebuffer incomplete: 0x%x", status];
        return NO;
    }
    return YES;
}

+ (void)runELFAtPath:(NSString *)path
           maxFrames:(NSInteger)maxFrames
          stopMarker:(nullable NSString *)stopMarker
             timeout:(NSTimeInterval)timeout
          jitCapable:(BOOL)jitCapable
          completion:(void (NS_SWIFT_SENDABLE ^)(PS2RunReport *report))completion {
    NSThread *thread = [[NSThread alloc] initWithBlock:^{
        [self runOnCurrentThreadWithELF:path maxFrames:maxFrames stopMarker:stopMarker timeout:timeout
                             jitCapable:jitCapable completion:completion];
    }];
    thread.name = @"JITSpike.emulation";
    thread.stackSize = 8 << 20;
    thread.qualityOfService = NSQualityOfServiceUserInteractive;
    [thread start];
}

/// Fills in the counters and the output, then calls the completion handler
/// exactly once, whoever gets here first: the run loop or the watcher.
+ (void)finishReport:(PS2RunReport *)report
              reason:(NSString *)reason
               start:(CFAbsoluteTime)start
           stdoutURL:(nullable NSURL *)stdoutURL
          completion:(void (NS_SWIFT_SENDABLE ^)(PS2RunReport *report))completion {
    bool expected = false;
    if (!atomic_compare_exchange_strong(&g_run.finished, &expected, true)) {
        return;
    }
    report.endReason = reason;
    if (start > 0) {
        report.seconds = CFAbsoluteTimeGetCurrent() - start;
    }
    report.retroRunCalls = atomic_load(&g_run.retroRunCalls);
    report.framesPresented = atomic_load(&g_run.framesPresented);
    report.audioFrames = atomic_load(&g_run.audioFrames);
    report.frameWidth = atomic_load(&g_run.lastWidth);
    report.frameHeight = atomic_load(&g_run.lastHeight);
    report.lastFramePNG = [self encodeLastFrame];
    if (stdoutURL != nil) {
        report.programOutput = [NSString stringWithContentsOfURL:stdoutURL encoding:NSUTF8StringEncoding
                                                           error:NULL] ?: @"";
    }
    if (g_run.coreMessage[0] != '\0') {
        report.coreMessage = [NSString stringWithUTF8String:g_run.coreMessage];
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        completion(report);
    });
}

+ (void)runOnCurrentThreadWithELF:(NSString *)path
                        maxFrames:(NSInteger)maxFrames
                       stopMarker:(nullable NSString *)stopMarker
                          timeout:(NSTimeInterval)timeout
                       jitCapable:(BOOL)jitCapable
                       completion:(void (NS_SWIFT_SENDABLE ^)(PS2RunReport *report))completion {
    PS2RunReport *report = [[PS2RunReport alloc] initEmpty];
    report.reportedJITCapable = jitCapable;
    static atomic_bool alreadyRan = false;
    if (atomic_exchange(&alreadyRan, true)) {
        report.error = @"libretro allows one run per process; relaunch the app";
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(report);
        });
        return;
    }

    NSError *loadError = nil;
    if (![self loadCoreWithError:&loadError]) {
        report.error = loadError.localizedDescription;
        [self finishReport:report reason:@"error" start:0 stdoutURL:nil completion:completion];
        return;
    }
    NSURL *playData = [self preparePlayDataDirectory];
    NSURL *stdoutURL = [playData URLByAppendingPathComponent:@"ps2_stdout.txt"];

    EAGLContext *context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES3];
    if (context == nil || ![EAGLContext setCurrentContext:context]) {
        report.error = @"could not create an OpenGL ES 3 context";
        [self finishReport:report reason:@"error" start:0 stdoutURL:nil completion:completion];
        return;
    }
    report.glRenderer = [NSString stringWithFormat:@"%s | %s", (const char *)glGetString(GL_RENDERER),
                                                   (const char *)glGetString(GL_VERSION)];
    NSString *framebufferError = nil;
    if (![self createFramebufferWithError:&framebufferError]) {
        report.error = framebufferError;
        [self finishReport:report reason:@"error" start:0 stdoutURL:nil completion:completion];
        return;
    }

    g_run.jitCapable = jitCapable;
    g_run.api.setEnvironment(PS2Environment);
    g_run.api.setVideoRefresh(PS2VideoRefresh);
    g_run.api.setAudioSample(PS2AudioSample);
    g_run.api.setAudioSampleBatch(PS2AudioSampleBatch);
    g_run.api.setInputPoll(PS2InputPoll);
    g_run.api.setInputState(PS2InputState);
    g_run.api.init();

    struct retro_game_info game;
    memset(&game, 0, sizeof(game));
    game.path = path.fileSystemRepresentation;
    report.gameLoaded = g_run.api.loadGame(&game);
    report.requestedContext = PS2ContextName(g_run.hwRender.context_type);
    if (!report.gameLoaded) {
        [self finishReport:report reason:@"refused" start:0 stdoutURL:nil completion:completion];
        return;
    }
    if (!g_run.hwRenderAccepted || g_run.hwRender.context_reset == NULL) {
        report.error = [NSString stringWithFormat:@"core asked for an unsupported context: %@",
                                                  report.requestedContext];
        [self finishReport:report reason:@"error" start:0 stdoutURL:nil completion:completion];
        return;
    }
    g_run.hwRender.context_reset();

    CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
    dispatch_queue_t watcherQueue = dispatch_get_global_queue(QOS_CLASS_UTILITY, 0);
    dispatch_source_t watcher = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, watcherQueue);
    dispatch_source_set_timer(watcher, dispatch_time(DISPATCH_TIME_NOW, 250 * NSEC_PER_MSEC),
                              250 * NSEC_PER_MSEC, 50 * NSEC_PER_MSEC);
    dispatch_source_set_event_handler(watcher, ^{
        if (atomic_load(&g_run.finished)) {
            dispatch_source_cancel(watcher);
            return;
        }
        NSString *output = [NSString stringWithContentsOfURL:stdoutURL encoding:NSUTF8StringEncoding
                                                       error:NULL];
        if (stopMarker != nil && [output containsString:stopMarker]) {
            [self finishReport:report reason:@"marker" start:start stdoutURL:stdoutURL completion:completion];
        } else if (CFAbsoluteTimeGetCurrent() - start > timeout) {
            [self finishReport:report reason:@"timeout" start:start stdoutURL:stdoutURL completion:completion];
        }
    });
    dispatch_resume(watcher);

    for (NSInteger call = 0; call < maxFrames && !atomic_load(&g_run.finished); call++) {
        g_run.api.run();
        atomic_fetch_add(&g_run.retroRunCalls, 1);
    }
    [self finishReport:report reason:@"frames" start:start stdoutURL:stdoutURL completion:completion];
}

@end
