#import "SPGGLESRenderer.h"

#import <CoreVideo/CoreVideo.h>
#import <Metal/Metal.h>
#import <OpenGLES/EAGL.h>
#import <OpenGLES/ES3/glext.h>

@implementation SPGGLESRenderer {
    EAGLContext *_context;
    GLsizei _width;
    GLsizei _height;
    GLuint _colorRenderbuffer;
    GLuint _depthStencilRenderbuffer;
    CVPixelBufferRef _pixelBuffer;
    CVOpenGLESTextureCacheRef _glTextureCache;
    CVOpenGLESTextureRef _glTexture;
    CVMetalTextureCacheRef _metalTextureCache;
    CVMetalTextureRef _metalTexture;
    id<MTLDevice> _metalDevice;
    id<MTLCommandQueue> _metalQueue;
}

static NSString *SPGGLString(GLenum name) {
    const GLubyte *value = glGetString(name);
    return value ? @((const char *)value) : @"?";
}

- (instancetype)initWithWidth:(GLsizei)width height:(GLsizei)height error:(NSString **)error {
    self = [super init];
    if (!self) {
        return nil;
    }
    _width = width;
    _height = height;
    _context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES3];
    if (!_context) {
        _context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
    }
    if (!_context || ![EAGLContext setCurrentContext:_context]) {
        if (error) {
            *error = @"EAGLContext could not be created or made current";
        }
        return nil;
    }
    _contextDescription = [NSString stringWithFormat:@"EAGL API %d; GL_VERSION %@; GL_RENDERER %@; GL_VENDOR %@; GLSL %@",
                                                     (int)_context.API, SPGGLString(GL_VERSION),
                                                     SPGGLString(GL_RENDERER), SPGGLString(GL_VENDOR),
                                                     SPGGLString(GL_SHADING_LANGUAGE_VERSION)];

    glGenFramebuffers(1, &_framebuffer);
    glBindFramebuffer(GL_FRAMEBUFFER, _framebuffer);

    NSString *sharedError = nil;
    if ([self attachSharedColorBuffer:&sharedError]) {
        _interopDescription = @"IOSurface-backed CVPixelBuffer (32BGRA), GL texture via CVOpenGLESTextureCache, "
                              @"MTLTexture via CVMetalTextureCache, read back with a Metal blit";
    } else {
        glGenRenderbuffers(1, &_colorRenderbuffer);
        glBindRenderbuffer(GL_RENDERBUFFER, _colorRenderbuffer);
        glRenderbufferStorage(GL_RENDERBUFFER, GL_RGBA8, width, height);
        glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, _colorRenderbuffer);
        _interopDescription = [NSString stringWithFormat:@"plain renderbuffer and glReadPixels (IOSurface path failed: %@)",
                                                         sharedError];
    }

    glGenRenderbuffers(1, &_depthStencilRenderbuffer);
    glBindRenderbuffer(GL_RENDERBUFFER, _depthStencilRenderbuffer);
    glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH24_STENCIL8, width, height);
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, _depthStencilRenderbuffer);
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_STENCIL_ATTACHMENT, GL_RENDERBUFFER, _depthStencilRenderbuffer);

    GLenum status = glCheckFramebufferStatus(GL_FRAMEBUFFER);
    if (status != GL_FRAMEBUFFER_COMPLETE) {
        if (error) {
            *error = [NSString stringWithFormat:@"framebuffer incomplete: 0x%04x", status];
        }
        [self tearDown];
        return nil;
    }
    glViewport(0, 0, width, height);
    glClearColor(0, 0, 0, 1);
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT | GL_STENCIL_BUFFER_BIT);
    return self;
}

- (BOOL)attachSharedColorBuffer:(NSString **)error {
    NSDictionary *attributes = @{
        (id)kCVPixelBufferIOSurfacePropertiesKey : @{},
        (id)kCVPixelBufferOpenGLESCompatibilityKey : @YES,
        (id)kCVPixelBufferMetalCompatibilityKey : @YES,
    };
    CVReturn result = CVPixelBufferCreate(kCFAllocatorDefault, (size_t)_width, (size_t)_height,
                                          kCVPixelFormatType_32BGRA, (__bridge CFDictionaryRef)attributes,
                                          &_pixelBuffer);
    if (result != kCVReturnSuccess) {
        *error = [NSString stringWithFormat:@"CVPixelBufferCreate %d", result];
        return NO;
    }
    result = CVOpenGLESTextureCacheCreate(kCFAllocatorDefault, NULL, _context, NULL, &_glTextureCache);
    if (result != kCVReturnSuccess) {
        *error = [NSString stringWithFormat:@"CVOpenGLESTextureCacheCreate %d", result];
        return NO;
    }
    result = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault, _glTextureCache, _pixelBuffer, NULL,
                                                          GL_TEXTURE_2D, GL_RGBA, _width, _height, GL_BGRA_EXT,
                                                          GL_UNSIGNED_BYTE, 0, &_glTexture);
    if (result != kCVReturnSuccess) {
        *error = [NSString stringWithFormat:@"CVOpenGLESTextureCacheCreateTextureFromImage %d", result];
        return NO;
    }
    GLuint texture = CVOpenGLESTextureGetName(_glTexture);
    glBindTexture(GL_TEXTURE_2D, texture);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, texture, 0);
    glBindTexture(GL_TEXTURE_2D, 0);

    _metalDevice = MTLCreateSystemDefaultDevice();
    _metalQueue = [_metalDevice newCommandQueue];
    if (!_metalQueue) {
        *error = @"no Metal device";
        return NO;
    }
    result = CVMetalTextureCacheCreate(kCFAllocatorDefault, NULL, _metalDevice, NULL, &_metalTextureCache);
    if (result != kCVReturnSuccess) {
        *error = [NSString stringWithFormat:@"CVMetalTextureCacheCreate %d", result];
        return NO;
    }
    result = CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, _metalTextureCache, _pixelBuffer, NULL,
                                                       MTLPixelFormatBGRA8Unorm, (size_t)_width, (size_t)_height, 0,
                                                       &_metalTexture);
    if (result != kCVReturnSuccess) {
        *error = [NSString stringWithFormat:@"CVMetalTextureCacheCreateTextureFromImage %d", result];
        return NO;
    }
    return YES;
}

- (void)makeCurrent {
    [EAGLContext setCurrentContext:_context];
}

- (void)finish {
    glFinish();
}

- (SPGFrame *)readFrameWithWidth:(GLsizei)width
                          height:(GLsizei)height
                bottomLeftOrigin:(BOOL)bottomLeftOrigin
                           error:(NSString **)error {
    if (width > _width || height > _height) {
        if (error) {
            *error = [NSString stringWithFormat:@"frame %dx%d is larger than the framebuffer", width, height];
        }
        return nil;
    }
    [self makeCurrent];
    glFinish();

    NSUInteger bytesPerRow = (NSUInteger)width * 4;
    if (_metalTexture) {
        id<MTLTexture> texture = CVMetalTextureGetTexture(_metalTexture);
        id<MTLBuffer> buffer = [_metalDevice newBufferWithLength:bytesPerRow * (NSUInteger)height
                                                         options:MTLResourceStorageModeShared];
        id<MTLCommandBuffer> commands = [_metalQueue commandBuffer];
        id<MTLBlitCommandEncoder> blit = [commands blitCommandEncoder];
        [blit copyFromTexture:texture
                     sourceSlice:0
                     sourceLevel:0
                    sourceOrigin:MTLOriginMake(0, 0, 0)
                      sourceSize:MTLSizeMake((NSUInteger)width, (NSUInteger)height, 1)
                        toBuffer:buffer
               destinationOffset:0
          destinationBytesPerRow:bytesPerRow
        destinationBytesPerImage:bytesPerRow * (NSUInteger)height];
        [blit endEncoding];
        [commands commit];
        [commands waitUntilCompleted];
        if (commands.error) {
            if (error) {
                *error = commands.error.localizedDescription;
            }
            return nil;
        }
        return [[SPGFrame alloc] initWithBytes:buffer.contents
                                         width:(NSUInteger)width
                                        height:(NSUInteger)height
                                   bytesPerRow:bytesPerRow
                                      bottomUp:bottomLeftOrigin];
    }

    NSMutableData *pixels = [NSMutableData dataWithLength:bytesPerRow * (NSUInteger)height];
    glBindFramebuffer(GL_FRAMEBUFFER, _framebuffer);
    glReadPixels(0, 0, width, height, GL_RGBA, GL_UNSIGNED_BYTE, pixels.mutableBytes);
    uint8_t *bytes = pixels.mutableBytes;
    for (NSUInteger i = 0; i < pixels.length; i += 4) {
        uint8_t red = bytes[i];
        bytes[i] = bytes[i + 2];
        bytes[i + 2] = red;
    }
    return [[SPGFrame alloc] initWithBytes:bytes
                                     width:(NSUInteger)width
                                    height:(NSUInteger)height
                               bytesPerRow:bytesPerRow
                                  bottomUp:bottomLeftOrigin];
}

- (void)tearDown {
    if (!_context) {
        return;
    }
    [self makeCurrent];
    if (_framebuffer) {
        glDeleteFramebuffers(1, &_framebuffer);
        _framebuffer = 0;
    }
    if (_colorRenderbuffer) {
        glDeleteRenderbuffers(1, &_colorRenderbuffer);
        _colorRenderbuffer = 0;
    }
    if (_depthStencilRenderbuffer) {
        glDeleteRenderbuffers(1, &_depthStencilRenderbuffer);
        _depthStencilRenderbuffer = 0;
    }
    if (_metalTexture) {
        CFRelease(_metalTexture);
        _metalTexture = NULL;
    }
    if (_metalTextureCache) {
        CFRelease(_metalTextureCache);
        _metalTextureCache = NULL;
    }
    if (_glTexture) {
        CFRelease(_glTexture);
        _glTexture = NULL;
    }
    if (_glTextureCache) {
        CFRelease(_glTextureCache);
        _glTextureCache = NULL;
    }
    if (_pixelBuffer) {
        CVPixelBufferRelease(_pixelBuffer);
        _pixelBuffer = NULL;
    }
    [EAGLContext setCurrentContext:nil];
    _context = nil;
}

- (void)dealloc {
    [self tearDown];
}

@end
