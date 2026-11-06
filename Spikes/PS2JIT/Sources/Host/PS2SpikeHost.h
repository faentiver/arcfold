#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Result of retro_get_system_info.
NS_SWIFT_SENDABLE
@interface PS2CoreInfo : NSObject
@property (nonatomic, readonly, copy) NSString *libraryName;
@property (nonatomic, readonly, copy) NSString *libraryVersion;
@property (nonatomic, readonly, copy) NSString *validExtensions;
@property (nonatomic, readonly) BOOL needFullpath;
@property (nonatomic, readonly) NSUInteger apiVersion;
@property (nonatomic, readonly, copy) NSString *corePath;
- (instancetype)init NS_UNAVAILABLE;
@end

/// What happened during one boot of an ELF.
NS_SWIFT_SENDABLE
@interface PS2RunReport : NSObject
/// Value the host answered for RETRO_ENVIRONMENT_GET_JIT_CAPABLE.
@property (nonatomic, readonly) BOOL reportedJITCapable;
@property (nonatomic, readonly) BOOL gameLoaded;
/// Last text the core sent with RETRO_ENVIRONMENT_SET_MESSAGE.
@property (nonatomic, readonly, copy, nullable) NSString *coreMessage;
/// Hardware context the core asked for, for example "OpenGL ES 3".
@property (nonatomic, readonly, copy) NSString *requestedContext;
@property (nonatomic, readonly, copy) NSString *glRenderer;
/// retro_run calls that returned.
@property (nonatomic, readonly) NSInteger retroRunCalls;
/// video_refresh calls with RETRO_HW_FRAME_BUFFER_VALID.
@property (nonatomic, readonly) NSInteger framesPresented;
/// Time from the first retro_run until the run ended.
@property (nonatomic, readonly) double seconds;
/// How the run ended: "frames", "marker" or "timeout".
@property (nonatomic, readonly, copy) NSString *endReason;
@property (nonatomic, readonly) NSInteger frameWidth;
@property (nonatomic, readonly) NSInteger frameHeight;
@property (nonatomic, readonly, copy, nullable) NSData *lastFramePNG;
@property (nonatomic, readonly) NSInteger audioFrames;
/// Content of Play!'s ps2_stdout.txt after the run.
@property (nonatomic, readonly, copy) NSString *programOutput;
@property (nonatomic, readonly, copy, nullable) NSString *error;
- (instancetype)init NS_UNAVAILABLE;
@end

/// Minimal libretro frontend for the Play! core. The core is loaded with
/// dlopen from the app's Frameworks folder and runs on its own thread with an
/// OpenGL ES 3 context, because Play!'s libretro GS handler renders with
/// OpenGL ES. libretro allows one core per process, so a run happens once
/// per app launch.
@interface PS2SpikeHost : NSObject
+ (nullable PS2CoreInfo *)loadCoreInfoWithError:(NSError **)error;

/// Boots the ELF and calls retro_run up to `maxFrames` times. The run also
/// ends when the program printed `stopMarker` or after `timeout` seconds:
/// Play!'s retro_run waits for the next GS flip, and a program that never
/// writes GS registers produces none, so retro_run can block for good.
/// `jitCapable` is the answer to RETRO_ENVIRONMENT_GET_JIT_CAPABLE.
+ (void)runELFAtPath:(NSString *)path
           maxFrames:(NSInteger)maxFrames
          stopMarker:(nullable NSString *)stopMarker
             timeout:(NSTimeInterval)timeout
          jitCapable:(BOOL)jitCapable
          completion:(void (NS_SWIFT_SENDABLE ^)(PS2RunReport *report))completion;
@end

NS_ASSUME_NONNULL_END
