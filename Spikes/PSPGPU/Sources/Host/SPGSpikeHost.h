#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// The graphics path the spike offers the PPSSPP core.
typedef NS_ENUM(NSInteger, SPGBackend) {
    SPGBackendOpenGLES NS_SWIFT_NAME(openGLES),
    SPGBackendVulkan,
    SPGBackendSoftware,
} NS_SWIFT_NAME(SpikeBackend);

NS_SWIFT_NAME(SpikeConfiguration)
NS_SWIFT_SENDABLE
@interface SPGConfiguration : NSObject
@property (nonatomic, readonly) SPGBackend backend;
@property (nonatomic, readonly) NSInteger frameCount;
@property (nonatomic, readonly) NSInteger renderScale;
@property (nonatomic, readonly, copy) NSArray<NSNumber *> *captureFrames;
@property (nonatomic, readonly, copy) NSURL *contentURL;
@property (nonatomic, readonly, copy) NSURL *outputDirectory;
/// Waits for the GPU after every frame, so frame times include GPU work.
@property (nonatomic, readonly) BOOL waitForGPUEachFrame;
/// How often the whole lifecycle runs in this process: dlopen, retro_init,
/// retro_load_game, the frames, retro_unload_game, retro_deinit.
@property (nonatomic, readonly) NSInteger cycles;
/// Calls dlclose at the end of every cycle and checks whether the image is
/// really gone.
@property (nonatomic, readonly) BOOL closesLibrary;

- (instancetype)initWithBackend:(SPGBackend)backend
                     frameCount:(NSInteger)frameCount
                    renderScale:(NSInteger)renderScale
                  captureFrames:(NSArray<NSNumber *> *)captureFrames
                     contentURL:(NSURL *)contentURL
                outputDirectory:(NSURL *)outputDirectory
            waitForGPUEachFrame:(BOOL)waitForGPUEachFrame
                         cycles:(NSInteger)cycles
                  closesLibrary:(BOOL)closesLibrary NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
@end

NS_SWIFT_NAME(SpikeResult)
NS_SWIFT_SENDABLE
@interface SPGResult : NSObject
@property (nonatomic, readonly) BOOL succeeded;
/// Human-readable report, one fact per line.
@property (nonatomic, readonly, copy) NSString *report;
/// PNG files of the captured frames, in frame order.
@property (nonatomic, readonly, copy) NSArray<NSURL *> *capturedImages;
- (instancetype)init NS_UNAVAILABLE;
@end

/// Loads the PPSSPP libretro core from the app bundle with dlopen, runs the
/// configured content for a number of frames on its own thread and saves
/// captured frames as PNG files. The report also lists threads the core
/// leaves behind and whether it changed the system directory inside the
/// framework. Only one run may be active at a time, because libretro
/// callbacks carry no context pointer.
NS_SWIFT_NAME(SpikeHost)
@interface SPGSpikeHost : NSObject
- (instancetype)initWithConfiguration:(SPGConfiguration *)configuration NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/// Starts the run on a dedicated emulation thread. The completion handler
/// runs on the main thread.
- (void)startWithCompletion:(void (NS_SWIFT_UI_ACTOR ^)(SPGResult *result))completion;
@end

NS_ASSUME_NONNULL_END
