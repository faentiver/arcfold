#import <Foundation/Foundation.h>

#import "SPGFrame.h"

NS_ASSUME_NONNULL_BEGIN

struct retro_hw_render_context_negotiation_interface;
struct retro_hw_render_interface;

/// Vulkan through MoltenVK for a libretro core that asked for
/// RETRO_HW_CONTEXT_VULKAN. The host creates the instance and a surface on a
/// CAMetalLayer, the core creates the device through its negotiation
/// interface, and the host implements retro_hw_render_interface_vulkan.
/// After each frame the host copies the image the core handed over with
/// set_image into an image of its own, which it can export as an MTLTexture
/// (VK_EXT_metal_objects).
@interface SPGVulkanRenderer : NSObject
@property (nonatomic, readonly, copy) NSString *deviceDescription;
@property (nonatomic, readonly, copy) NSString *interopDescription;
/// Set by the first read through VK_EXT_metal_objects.
@property (nonatomic, readonly, copy, nullable) NSString *exportedTextureDescription;
@property (nonatomic, readonly) const struct retro_hw_render_interface *renderInterface;
@property (nonatomic, readonly) NSUInteger imagesReceived;
@property (nonatomic, readonly) NSUInteger framesCopied;

- (nullable instancetype)initWithNegotiation:(const struct retro_hw_render_context_negotiation_interface *)negotiation
                                       width:(uint32_t)width
                                      height:(uint32_t)height
                                       error:(NSString *_Nullable *_Nullable)error NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/// Copies the image the core set during the last retro_run into the host
/// image and advances the sync index. Returns NO on a Vulkan error.
- (BOOL)finishFrameWithWidth:(uint32_t)width
                      height:(uint32_t)height
                       error:(NSString *_Nullable *_Nullable)error;

/// Waits for the queue and reads the top-left width x height pixels of the
/// host image back.
- (nullable SPGFrame *)readFrameWithWidth:(uint32_t)width
                                   height:(uint32_t)height
                                    error:(NSString *_Nullable *_Nullable)error;

/// Waits until the GPU is idle. Call before the core tears its objects down.
- (void)waitIdle;

/// Destroys the device the core created (its destroy hook is empty) and the
/// host objects. Call after retro_unload_game.
- (void)tearDown;
@end

NS_ASSUME_NONNULL_END
