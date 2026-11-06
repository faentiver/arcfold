#import "SPGFrame.h"

#import <CommonCrypto/CommonDigest.h>
#import <CoreGraphics/CoreGraphics.h>
#import <ImageIO/ImageIO.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@implementation SPGFrame

- (instancetype)initWithBytes:(const void *)bytes
                        width:(NSUInteger)width
                       height:(NSUInteger)height
                  bytesPerRow:(NSUInteger)bytesPerRow
                     bottomUp:(BOOL)bottomUp {
    self = [super init];
    if (self) {
        _width = width;
        _height = height;
        _bytesPerRow = width * 4;
        NSMutableData *pixels = [NSMutableData dataWithLength:_bytesPerRow * height];
        const uint8_t *source = bytes;
        uint8_t *target = pixels.mutableBytes;
        for (NSUInteger row = 0; row < height; row++) {
            NSUInteger sourceRow = bottomUp ? height - 1 - row : row;
            memcpy(target + row * _bytesPerRow, source + sourceRow * bytesPerRow, _bytesPerRow);
        }
        _pixels = pixels;
    }
    return self;
}

- (NSString *)pixelDigest {
    NSMutableData *opaque = [self.pixels mutableCopy];
    uint8_t *bytes = opaque.mutableBytes;
    for (NSUInteger i = 3; i < opaque.length; i += 4) {
        bytes[i] = 0;
    }
    uint8_t digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(opaque.bytes, (CC_LONG)opaque.length, digest);
    NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) {
        [hex appendFormat:@"%02x", digest[i]];
    }
    return hex;
}

- (double)coverage {
    const uint32_t *pixels = self.pixels.bytes;
    NSUInteger count = self.width * self.height;
    if (count == 0) {
        return 0;
    }
    uint32_t clear = pixels[0] & 0x00ffffff;
    NSUInteger drawn = 0;
    for (NSUInteger i = 0; i < count; i++) {
        if ((pixels[i] & 0x00ffffff) != clear) {
            drawn++;
        }
    }
    return (double)drawn / (double)count;
}

- (BOOL)writePNGToURL:(NSURL *)url error:(NSError **)error {
    CGColorSpaceRef colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)self.pixels);
    CGImageRef image = CGImageCreate(self.width, self.height, 8, 32, self.bytesPerRow, colorSpace,
                                     kCGBitmapByteOrder32Little | (CGBitmapInfo)kCGImageAlphaNoneSkipFirst,
                                     provider, NULL, false, kCGRenderingIntentDefault);
    CGDataProviderRelease(provider);
    CGColorSpaceRelease(colorSpace);
    if (!image) {
        if (error) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteUnknownError userInfo:nil];
        }
        return NO;
    }
    CGImageDestinationRef destination =
        CGImageDestinationCreateWithURL((__bridge CFURLRef)url, (__bridge CFStringRef)UTTypePNG.identifier, 1, NULL);
    BOOL written = NO;
    if (destination) {
        CGImageDestinationAddImage(destination, image, NULL);
        written = CGImageDestinationFinalize(destination);
        CFRelease(destination);
    }
    CGImageRelease(image);
    if (!written && error) {
        *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteUnknownError userInfo:nil];
    }
    return written;
}

@end
