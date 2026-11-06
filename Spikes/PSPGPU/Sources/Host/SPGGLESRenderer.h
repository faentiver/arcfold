#import <Foundation/Foundation.h>
#import <OpenGLES/ES3/gl.h>

#import "SPGFrame.h"

NS_ASSUME_NONNULL_BEGIN

/// OpenGL ES context and framebuffer for a libretro core that asked for
/// RETRO_HW_CONTEXT_OPENGLES*. The color buffer lives in an IOSurface that a
/// Metal texture shares, which is the zero-copy path a Metal renderer would
/// use. If the simulator refuses the texture cache, it falls back to a plain
/// renderbuffer and glReadPixels.
@interface SPGGLESRenderer : NSObject
@property (nonatomic, readonly) GLuint framebuffer;
@property (nonatomic, readonly, copy) NSString *contextDescription;
@property (nonatomic, readonly, copy) NSString *interopDescription;

- (nullable instancetype)initWithWidth:(GLsizei)width
                                height:(GLsizei)height
                                 error:(NSString *_Nullable *_Nullable)error NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/// Makes the context current on the calling thread.
- (void)makeCurrent;

/// Blocks until the GPU has finished all submitted commands.
- (void)finish;

/// Waits for the GPU and returns the visible part of the framebuffer.
- (nullable SPGFrame *)readFrameWithWidth:(GLsizei)width
                                   height:(GLsizei)height
                         bottomLeftOrigin:(BOOL)bottomLeftOrigin
                                    error:(NSString *_Nullable *_Nullable)error;

- (void)tearDown;
@end

NS_ASSUME_NONNULL_END
