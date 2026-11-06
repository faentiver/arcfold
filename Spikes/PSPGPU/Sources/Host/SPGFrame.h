#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// One captured frame as 32-bit pixels in BGRA byte order (alpha ignored).
@interface SPGFrame : NSObject
@property (nonatomic, readonly) NSUInteger width;
@property (nonatomic, readonly) NSUInteger height;
@property (nonatomic, readonly) NSUInteger bytesPerRow;
/// Rows start at the top of the picture.
@property (nonatomic, readonly, copy) NSData *pixels;

/// Copies the pixels. Set `bottomUp` when the first row in memory is the
/// bottom row of the picture, as with OpenGL framebuffers.
- (instancetype)initWithBytes:(const void *)bytes
                        width:(NSUInteger)width
                       height:(NSUInteger)height
                  bytesPerRow:(NSUInteger)bytesPerRow
                     bottomUp:(BOOL)bottomUp NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/// SHA-256 of the visible pixels with the unused alpha byte cleared, so the
/// same picture gives the same value on every graphics path.
- (NSString *)pixelDigest;

/// Share of pixels that differ from the clear color in the top-left corner,
/// a cheap check that the core drew something.
- (double)coverage;

- (BOOL)writePNGToURL:(NSURL *)url error:(NSError *_Nullable *_Nullable)error;
@end

NS_ASSUME_NONNULL_END
