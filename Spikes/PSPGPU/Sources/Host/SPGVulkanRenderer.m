#import "SPGVulkanRenderer.h"

#define VK_USE_PLATFORM_METAL_EXT 1
#import <vulkan/vulkan.h>

#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#import <libretro_vulkan.h>
#import <pthread.h>

#define SPG_SYNC_COUNT 2
#define SPG_MAX_SEMAPHORES 8
#define SPG_MAX_COMMAND_BUFFERS 8

static const char *const SPGPortabilitySubsetExtension = "VK_KHR_portability_subset";

/// State the libretro callbacks reach through the interface's handle.
typedef struct {
    VkDevice device;
    VkFence fences[SPG_SYNC_COUNT];
    uint32_t syncIndex;
    pthread_mutex_t queueLock;
    bool hasImage;
    struct retro_vulkan_image image;
    uint32_t srcQueueFamily;
    uint32_t waitSemaphoreCount;
    VkSemaphore waitSemaphores[SPG_MAX_SEMAPHORES];
    VkSemaphore signalSemaphore;
    uint32_t commandBufferCount;
    VkCommandBuffer commandBuffers[SPG_MAX_COMMAND_BUFFERS];
    NSUInteger imagesReceived;
} SPGVulkanState;

static void SPGSetImage(void *handle, const struct retro_vulkan_image *image, uint32_t semaphoreCount,
                        const VkSemaphore *semaphores, uint32_t srcQueueFamily) {
    SPGVulkanState *state = handle;
    state->image = *image;
    state->hasImage = true;
    state->srcQueueFamily = srcQueueFamily;
    state->waitSemaphoreCount = semaphoreCount < SPG_MAX_SEMAPHORES ? semaphoreCount : SPG_MAX_SEMAPHORES;
    for (uint32_t i = 0; i < state->waitSemaphoreCount; i++) {
        state->waitSemaphores[i] = semaphores[i];
    }
    state->imagesReceived++;
}

static uint32_t SPGGetSyncIndex(void *handle) {
    return ((SPGVulkanState *)handle)->syncIndex;
}

static uint32_t SPGGetSyncIndexMask(void *handle) {
    (void)handle;
    return (1u << SPG_SYNC_COUNT) - 1;
}

static void SPGSetCommandBuffers(void *handle, uint32_t count, const VkCommandBuffer *commandBuffers) {
    SPGVulkanState *state = handle;
    for (uint32_t i = 0; i < count && state->commandBufferCount < SPG_MAX_COMMAND_BUFFERS; i++) {
        state->commandBuffers[state->commandBufferCount++] = commandBuffers[i];
    }
}

static void SPGWaitSyncIndex(void *handle) {
    SPGVulkanState *state = handle;
    vkWaitForFences(state->device, 1, &state->fences[state->syncIndex], VK_TRUE, UINT64_MAX);
}

static void SPGLockQueue(void *handle) {
    pthread_mutex_lock(&((SPGVulkanState *)handle)->queueLock);
}

static void SPGUnlockQueue(void *handle) {
    pthread_mutex_unlock(&((SPGVulkanState *)handle)->queueLock);
}

static void SPGSetSignalSemaphore(void *handle, VkSemaphore semaphore) {
    ((SPGVulkanState *)handle)->signalSemaphore = semaphore;
}

static NSString *SPGVulkanVersion(uint32_t version) {
    return [NSString stringWithFormat:@"%u.%u.%u", VK_API_VERSION_MAJOR(version), VK_API_VERSION_MINOR(version),
                                      VK_API_VERSION_PATCH(version)];
}

@implementation SPGVulkanRenderer {
    uint32_t _width;
    uint32_t _height;
    VkInstance _instance;
    VkSurfaceKHR _surface;
    VkPhysicalDevice _gpu;
    VkDevice _device;
    VkQueue _queue;
    uint32_t _queueFamily;
    VkCommandPool _commandPool;
    VkCommandBuffer _commandBuffers[SPG_SYNC_COUNT];
    VkImage _hostImage;
    VkDeviceMemory _hostMemory;
    VkFormat _hostFormat;
    BOOL _metalObjects;
    CAMetalLayer *_layer;
    id<MTLCommandQueue> _metalQueue;
    const struct retro_hw_render_context_negotiation_interface_vulkan *_negotiation;
    SPGVulkanState _state;
    struct retro_hw_render_interface_vulkan _interface;
}

- (instancetype)initWithNegotiation:(const struct retro_hw_render_context_negotiation_interface *)negotiation
                              width:(uint32_t)width
                             height:(uint32_t)height
                              error:(NSString **)error {
    self = [super init];
    if (!self) {
        return nil;
    }
    _width = width;
    _height = height;
    pthread_mutex_init(&_state.queueLock, NULL);

    if (!negotiation || negotiation->interface_type != RETRO_HW_RENDER_CONTEXT_NEGOTIATION_INTERFACE_VULKAN) {
        if (error) {
            *error = @"the core set no Vulkan negotiation interface";
        }
        return nil;
    }
    _negotiation = (const struct retro_hw_render_context_negotiation_interface_vulkan *)negotiation;
    if (!_negotiation->create_device) {
        if (error) {
            *error = @"the negotiation interface has no create_device";
        }
        return nil;
    }

    NSString *step = nil;
    if (![self createInstance:&step] || ![self createSurface:&step] || ![self pickPhysicalDevice:&step] ||
        ![self createDeviceThroughCore:&step] || ![self createHostObjects:&step]) {
        if (error) {
            *error = step;
        }
        [self tearDown];
        return nil;
    }

    _interface.interface_type = RETRO_HW_RENDER_INTERFACE_VULKAN;
    _interface.interface_version = RETRO_HW_RENDER_INTERFACE_VULKAN_VERSION;
    _interface.handle = &_state;
    _interface.instance = _instance;
    _interface.gpu = _gpu;
    _interface.device = _device;
    _interface.get_device_proc_addr = vkGetDeviceProcAddr;
    _interface.get_instance_proc_addr = vkGetInstanceProcAddr;
    _interface.queue = _queue;
    _interface.queue_index = _queueFamily;
    _interface.set_image = SPGSetImage;
    _interface.get_sync_index = SPGGetSyncIndex;
    _interface.get_sync_index_mask = SPGGetSyncIndexMask;
    _interface.set_command_buffers = SPGSetCommandBuffers;
    _interface.wait_sync_index = SPGWaitSyncIndex;
    _interface.lock_queue = SPGLockQueue;
    _interface.unlock_queue = SPGUnlockQueue;
    _interface.set_signal_semaphore = SPGSetSignalSemaphore;
    return self;
}

- (const struct retro_hw_render_interface *)renderInterface {
    return (const struct retro_hw_render_interface *)&_interface;
}

- (NSUInteger)imagesReceived {
    return _state.imagesReceived;
}

#pragma mark - Setup

- (BOOL)createInstance:(NSString **)step {
    uint32_t instanceVersion = VK_API_VERSION_1_0;
    vkEnumerateInstanceVersion(&instanceVersion);

    VkApplicationInfo application = {
        .sType = VK_STRUCTURE_TYPE_APPLICATION_INFO,
        .pApplicationName = "Arcfold PSP GPU spike",
        .pEngineName = "Arcfold",
    };
    NSString *coreRequest = @"none";
    if (_negotiation->get_application_info) {
        const VkApplicationInfo *coreApplication = _negotiation->get_application_info();
        if (coreApplication) {
            application = *coreApplication;
            application.pNext = NULL;
            coreRequest = [NSString stringWithFormat:@"%s, API %@", coreApplication->pApplicationName ?: "?",
                                                     SPGVulkanVersion(coreApplication->apiVersion)];
        }
    }
    // The core probes vkEnumerateInstanceVersion and uses what it finds, so
    // the instance has to offer that version, not the 1.0 it names.
    application.apiVersion = instanceVersion;

    uint32_t count = 0;
    vkEnumerateInstanceExtensionProperties(NULL, &count, NULL);
    VkExtensionProperties *properties = calloc(count, sizeof(VkExtensionProperties));
    vkEnumerateInstanceExtensionProperties(NULL, &count, properties);
    const char *wanted[] = {
        VK_KHR_SURFACE_EXTENSION_NAME,
        VK_EXT_METAL_SURFACE_EXTENSION_NAME,
        VK_KHR_GET_PHYSICAL_DEVICE_PROPERTIES_2_EXTENSION_NAME,
        VK_EXT_SWAPCHAIN_COLOR_SPACE_EXTENSION_NAME,
        VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME,
    };
    const char *enabled[5];
    uint32_t enabledCount = 0;
    BOOL portabilityEnumeration = NO;
    for (size_t w = 0; w < sizeof(wanted) / sizeof(wanted[0]); w++) {
        for (uint32_t i = 0; i < count; i++) {
            if (strcmp(properties[i].extensionName, wanted[w]) == 0) {
                enabled[enabledCount++] = wanted[w];
                if (strcmp(wanted[w], VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME) == 0) {
                    portabilityEnumeration = YES;
                }
                break;
            }
        }
    }
    free(properties);

    VkInstanceCreateInfo info = {
        .sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
        .flags = portabilityEnumeration ? VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR : 0,
        .pApplicationInfo = &application,
        .enabledExtensionCount = enabledCount,
        .ppEnabledExtensionNames = enabled,
    };
    VkResult result = vkCreateInstance(&info, NULL, &_instance);
    if (result != VK_SUCCESS) {
        *step = [NSString stringWithFormat:@"vkCreateInstance failed: %d", result];
        return NO;
    }
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (uint32_t i = 0; i < enabledCount; i++) {
        [names addObject:@(enabled[i])];
    }
    _deviceDescription = [NSString stringWithFormat:@"instance API %@ (core asked: %@), instance extensions: %@",
                                                    SPGVulkanVersion(instanceVersion), coreRequest,
                                                    [names componentsJoinedByString:@", "]];
    return YES;
}

- (BOOL)createSurface:(NSString **)step {
    _layer = [CAMetalLayer layer];
    _layer.device = MTLCreateSystemDefaultDevice();
    _layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
    _layer.drawableSize = CGSizeMake(_width, _height);
    VkMetalSurfaceCreateInfoEXT info = {
        .sType = VK_STRUCTURE_TYPE_METAL_SURFACE_CREATE_INFO_EXT,
        .pLayer = _layer,
    };
    VkResult result = vkCreateMetalSurfaceEXT(_instance, &info, NULL, &_surface);
    if (result != VK_SUCCESS) {
        *step = [NSString stringWithFormat:@"vkCreateMetalSurfaceEXT failed: %d", result];
        return NO;
    }
    return YES;
}

- (BOOL)pickPhysicalDevice:(NSString **)step {
    uint32_t count = 1;
    VkResult result = vkEnumeratePhysicalDevices(_instance, &count, &_gpu);
    if ((result != VK_SUCCESS && result != VK_INCOMPLETE) || count == 0) {
        *step = [NSString stringWithFormat:@"no Vulkan device: %d", result];
        return NO;
    }
    VkPhysicalDeviceProperties properties;
    vkGetPhysicalDeviceProperties(_gpu, &properties);

    uint32_t extensionCount = 0;
    vkEnumerateDeviceExtensionProperties(_gpu, NULL, &extensionCount, NULL);
    VkExtensionProperties *extensions = calloc(extensionCount, sizeof(VkExtensionProperties));
    vkEnumerateDeviceExtensionProperties(_gpu, NULL, &extensionCount, extensions);
    for (uint32_t i = 0; i < extensionCount; i++) {
        if (strcmp(extensions[i].extensionName, VK_EXT_METAL_OBJECTS_EXTENSION_NAME) == 0) {
            _metalObjects = YES;
        }
    }
    free(extensions);

    _deviceDescription = [NSString stringWithFormat:@"%@; device %s, API %@, driver 0x%x, %u device extensions",
                                                    _deviceDescription, properties.deviceName,
                                                    SPGVulkanVersion(properties.apiVersion), properties.driverVersion,
                                                    extensionCount];
    return YES;
}

- (BOOL)deviceHasExtension:(const char *)name {
    uint32_t count = 0;
    vkEnumerateDeviceExtensionProperties(_gpu, NULL, &count, NULL);
    VkExtensionProperties *extensions = calloc(count, sizeof(VkExtensionProperties));
    vkEnumerateDeviceExtensionProperties(_gpu, NULL, &count, extensions);
    BOOL found = NO;
    for (uint32_t i = 0; i < count && !found; i++) {
        found = strcmp(extensions[i].extensionName, name) == 0;
    }
    free(extensions);
    return found;
}

- (BOOL)createDeviceThroughCore:(NSString **)step {
    // PPSSPP does not enable VK_KHR_portability_subset itself, but the spec
    // requires it on MoltenVK. VK_EXT_metal_objects is for the host image.
    const char *required[2];
    unsigned requiredCount = 0;
    if ([self deviceHasExtension:SPGPortabilitySubsetExtension]) {
        required[requiredCount++] = SPGPortabilitySubsetExtension;
    }
    if (_metalObjects) {
        required[requiredCount++] = VK_EXT_METAL_OBJECTS_EXTENSION_NAME;
    }
    VkPhysicalDeviceFeatures features = {0};
    struct retro_vulkan_context context = {0};
    bool created = _negotiation->create_device(&context, _instance, _gpu, _surface, vkGetInstanceProcAddr, required,
                                               requiredCount, NULL, 0, &features);
    if (!created || context.device == VK_NULL_HANDLE) {
        *step = @"the core's create_device failed";
        return NO;
    }
    _device = context.device;
    _queue = context.queue;
    _queueFamily = context.queue_family_index;
    _state.device = _device;
    _deviceDescription = [NSString stringWithFormat:@"%@; device created by the core through negotiation interface v%u "
                                                    @"(create_instance %@, create_device2 %@), queue family %u",
                                                    _deviceDescription, _negotiation->interface_version,
                                                    _negotiation->create_instance ? @"set" : @"not set",
                                                    _negotiation->create_device2 ? @"set" : @"not set", _queueFamily];
    return YES;
}

- (BOOL)createHostObjects:(NSString **)step {
    VkCommandPoolCreateInfo poolInfo = {
        .sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
        .flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
        .queueFamilyIndex = _queueFamily,
    };
    if (vkCreateCommandPool(_device, &poolInfo, NULL, &_commandPool) != VK_SUCCESS) {
        *step = @"vkCreateCommandPool failed";
        return NO;
    }
    VkCommandBufferAllocateInfo allocateInfo = {
        .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        .commandPool = _commandPool,
        .level = VK_COMMAND_BUFFER_LEVEL_PRIMARY,
        .commandBufferCount = SPG_SYNC_COUNT,
    };
    if (vkAllocateCommandBuffers(_device, &allocateInfo, _commandBuffers) != VK_SUCCESS) {
        *step = @"vkAllocateCommandBuffers failed";
        return NO;
    }
    VkFenceCreateInfo fenceInfo = {
        .sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
        .flags = VK_FENCE_CREATE_SIGNALED_BIT,
    };
    for (int i = 0; i < SPG_SYNC_COUNT; i++) {
        if (vkCreateFence(_device, &fenceInfo, NULL, &_state.fences[i]) != VK_SUCCESS) {
            *step = @"vkCreateFence failed";
            return NO;
        }
    }
    return YES;
}

- (BOOL)memoryType:(uint32_t)typeBits properties:(VkMemoryPropertyFlags)wanted index:(uint32_t *)index {
    VkPhysicalDeviceMemoryProperties memory;
    vkGetPhysicalDeviceMemoryProperties(_gpu, &memory);
    for (uint32_t i = 0; i < memory.memoryTypeCount; i++) {
        if ((typeBits & (1u << i)) && (memory.memoryTypes[i].propertyFlags & wanted) == wanted) {
            *index = i;
            return YES;
        }
    }
    return NO;
}

/// The host image takes the core's format, which is known after the first
/// set_image. With VK_EXT_metal_objects it is created exportable.
- (BOOL)createHostImageWithFormat:(VkFormat)format error:(NSString **)error {
    VkExportMetalObjectCreateInfoEXT exportInfo = {
        .sType = VK_STRUCTURE_TYPE_EXPORT_METAL_OBJECT_CREATE_INFO_EXT,
        .exportObjectType = VK_EXPORT_METAL_OBJECT_TYPE_METAL_TEXTURE_BIT_EXT,
    };
    VkImageCreateInfo info = {
        .sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
        .pNext = _metalObjects ? &exportInfo : NULL,
        .imageType = VK_IMAGE_TYPE_2D,
        .format = format,
        .extent = {_width, _height, 1},
        .mipLevels = 1,
        .arrayLayers = 1,
        .samples = VK_SAMPLE_COUNT_1_BIT,
        .tiling = VK_IMAGE_TILING_OPTIMAL,
        .usage = VK_IMAGE_USAGE_TRANSFER_DST_BIT | VK_IMAGE_USAGE_TRANSFER_SRC_BIT | VK_IMAGE_USAGE_SAMPLED_BIT,
        .sharingMode = VK_SHARING_MODE_EXCLUSIVE,
        .initialLayout = VK_IMAGE_LAYOUT_UNDEFINED,
    };
    if (vkCreateImage(_device, &info, NULL, &_hostImage) != VK_SUCCESS) {
        *error = @"vkCreateImage for the host image failed";
        return NO;
    }
    VkMemoryRequirements requirements;
    vkGetImageMemoryRequirements(_device, _hostImage, &requirements);
    VkMemoryAllocateInfo allocateInfo = {
        .sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
        .allocationSize = requirements.size,
    };
    if (![self memoryType:requirements.memoryTypeBits
               properties:VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT
                    index:&allocateInfo.memoryTypeIndex] ||
        vkAllocateMemory(_device, &allocateInfo, NULL, &_hostMemory) != VK_SUCCESS ||
        vkBindImageMemory(_device, _hostImage, _hostMemory, 0) != VK_SUCCESS) {
        *error = @"memory for the host image failed";
        return NO;
    }
    _hostFormat = format;
    _interopDescription = _metalObjects ? @"core image copied into an exportable host VkImage (vkCmdCopyImage), "
                                          @"exported as MTLTexture with VK_EXT_metal_objects, read back with a Metal blit"
                                        : @"core image copied into a host VkImage, read back with vkCmdCopyImageToBuffer";
    return YES;
}

#pragma mark - Frames

static VkImageMemoryBarrier SPGBarrier(VkImage image, VkImageLayout from, VkImageLayout to, VkAccessFlags srcAccess,
                                       VkAccessFlags dstAccess) {
    VkImageMemoryBarrier barrier = {
        .sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
        .srcAccessMask = srcAccess,
        .dstAccessMask = dstAccess,
        .oldLayout = from,
        .newLayout = to,
        .srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED,
        .dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED,
        .image = image,
        .subresourceRange = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1},
    };
    return barrier;
}

- (BOOL)finishFrameWithWidth:(uint32_t)width height:(uint32_t)height error:(NSString **)error {
    if (!_state.hasImage) {
        return YES;
    }
    VkImage coreImage = _state.image.create_info.image;
    VkImageLayout coreLayout = _state.image.image_layout;
    if (!_hostImage && ![self createHostImageWithFormat:_state.image.create_info.format error:error]) {
        return NO;
    }
    if (_state.image.create_info.format != _hostFormat) {
        if (error) {
            *error = @"the core changed its image format";
        }
        return NO;
    }
    uint32_t copyWidth = width < _width ? width : _width;
    uint32_t copyHeight = height < _height ? height : _height;

    uint32_t index = _state.syncIndex;
    VkFence fence = _state.fences[index];
    vkWaitForFences(_device, 1, &fence, VK_TRUE, UINT64_MAX);
    vkResetFences(_device, 1, &fence);

    VkCommandBuffer commands = _commandBuffers[index];
    vkResetCommandBuffer(commands, 0);
    VkCommandBufferBeginInfo begin = {
        .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        .flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
    };
    vkBeginCommandBuffer(commands, &begin);
    VkImageMemoryBarrier toTransfer[2] = {
        SPGBarrier(coreImage, coreLayout, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
                   VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT | VK_ACCESS_TRANSFER_WRITE_BIT, VK_ACCESS_TRANSFER_READ_BIT),
        SPGBarrier(_hostImage, VK_IMAGE_LAYOUT_UNDEFINED, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 0,
                   VK_ACCESS_TRANSFER_WRITE_BIT),
    };
    vkCmdPipelineBarrier(commands, VK_PIPELINE_STAGE_ALL_COMMANDS_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT, 0, 0, NULL, 0,
                         NULL, 2, toTransfer);
    VkImageCopy region = {
        .srcSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1},
        .dstSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1},
        .extent = {copyWidth, copyHeight, 1},
    };
    vkCmdCopyImage(commands, coreImage, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, _hostImage,
                   VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &region);
    VkImageMemoryBarrier back[2] = {
        SPGBarrier(coreImage, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, coreLayout, VK_ACCESS_TRANSFER_READ_BIT,
                   VK_ACCESS_SHADER_READ_BIT | VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT),
        SPGBarrier(_hostImage, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, VK_IMAGE_LAYOUT_GENERAL,
                   VK_ACCESS_TRANSFER_WRITE_BIT, VK_ACCESS_MEMORY_READ_BIT),
    };
    vkCmdPipelineBarrier(commands, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_ALL_COMMANDS_BIT, 0, 0, NULL, 0,
                         NULL, 2, back);
    vkEndCommandBuffer(commands);

    VkCommandBuffer submitted[SPG_MAX_COMMAND_BUFFERS + 1];
    uint32_t submittedCount = 0;
    for (uint32_t i = 0; i < _state.commandBufferCount; i++) {
        submitted[submittedCount++] = _state.commandBuffers[i];
    }
    submitted[submittedCount++] = commands;
    VkPipelineStageFlags waitStages[SPG_MAX_SEMAPHORES];
    for (uint32_t i = 0; i < _state.waitSemaphoreCount; i++) {
        waitStages[i] = VK_PIPELINE_STAGE_ALL_COMMANDS_BIT;
    }
    VkSubmitInfo submit = {
        .sType = VK_STRUCTURE_TYPE_SUBMIT_INFO,
        .waitSemaphoreCount = _state.waitSemaphoreCount,
        .pWaitSemaphores = _state.waitSemaphores,
        .pWaitDstStageMask = waitStages,
        .commandBufferCount = submittedCount,
        .pCommandBuffers = submitted,
        .signalSemaphoreCount = _state.signalSemaphore ? 1 : 0,
        .pSignalSemaphores = &_state.signalSemaphore,
    };
    pthread_mutex_lock(&_state.queueLock);
    VkResult result = vkQueueSubmit(_queue, 1, &submit, fence);
    pthread_mutex_unlock(&_state.queueLock);
    _state.waitSemaphoreCount = 0;
    _state.commandBufferCount = 0;
    _state.signalSemaphore = VK_NULL_HANDLE;
    _state.syncIndex = (index + 1) % SPG_SYNC_COUNT;
    if (result != VK_SUCCESS) {
        if (error) {
            *error = [NSString stringWithFormat:@"vkQueueSubmit failed: %d", result];
        }
        return NO;
    }
    _framesCopied++;
    return YES;
}

- (void)waitIdle {
    if (_device) {
        pthread_mutex_lock(&_state.queueLock);
        vkQueueWaitIdle(_queue);
        pthread_mutex_unlock(&_state.queueLock);
    }
}

- (SPGFrame *)readFrameWithWidth:(uint32_t)width height:(uint32_t)height error:(NSString **)error {
    if (!_hostImage) {
        if (error) {
            *error = @"the core has not handed over an image yet";
        }
        return nil;
    }
    width = width < _width ? width : _width;
    height = height < _height ? height : _height;
    [self waitIdle];
    if (_metalObjects) {
        return [self readFrameThroughMetalWithWidth:width height:height error:error];
    }
    return [self readFrameThroughBufferWithWidth:width height:height error:error];
}

- (SPGFrame *)readFrameThroughMetalWithWidth:(uint32_t)width height:(uint32_t)height error:(NSString **)error {
    VkExportMetalTextureInfoEXT textureInfo = {
        .sType = VK_STRUCTURE_TYPE_EXPORT_METAL_TEXTURE_INFO_EXT,
        .image = _hostImage,
        .plane = VK_IMAGE_ASPECT_PLANE_0_BIT,
    };
    VkExportMetalDeviceInfoEXT deviceInfo = {
        .sType = VK_STRUCTURE_TYPE_EXPORT_METAL_DEVICE_INFO_EXT,
        .pNext = &textureInfo,
    };
    VkExportMetalObjectsInfoEXT objects = {
        .sType = VK_STRUCTURE_TYPE_EXPORT_METAL_OBJECTS_INFO_EXT,
        .pNext = &deviceInfo,
    };
    vkExportMetalObjectsEXT(_device, &objects);
    id<MTLTexture> texture = textureInfo.mtlTexture;
    id<MTLDevice> device = deviceInfo.mtlDevice;
    if (!texture || !device) {
        if (error) {
            *error = @"vkExportMetalObjectsEXT returned no texture";
        }
        return nil;
    }
    if (!_metalQueue) {
        _metalQueue = [device newCommandQueue];
    }
    NSUInteger bytesPerRow = (NSUInteger)width * 4;
    id<MTLBuffer> buffer = [device newBufferWithLength:bytesPerRow * height options:MTLResourceStorageModeShared];
    id<MTLCommandBuffer> commands = [_metalQueue commandBuffer];
    id<MTLBlitCommandEncoder> blit = [commands blitCommandEncoder];
    [blit copyFromTexture:texture
                 sourceSlice:0
                 sourceLevel:0
                sourceOrigin:MTLOriginMake(0, 0, 0)
                  sourceSize:MTLSizeMake(width, height, 1)
                    toBuffer:buffer
           destinationOffset:0
      destinationBytesPerRow:bytesPerRow
    destinationBytesPerImage:bytesPerRow * height];
    [blit endEncoding];
    [commands commit];
    [commands waitUntilCompleted];
    if (commands.error) {
        if (error) {
            *error = commands.error.localizedDescription;
        }
        return nil;
    }
    if (!_exportedTextureDescription) {
        _exportedTextureDescription =
            [NSString stringWithFormat:@"%lux%lu, pixel format %lu, storage mode %lu, usage 0x%lx, on %@",
                                       (unsigned long)texture.width, (unsigned long)texture.height,
                                       (unsigned long)texture.pixelFormat, (unsigned long)texture.storageMode,
                                       (unsigned long)texture.usage, device.name];
    }
    return [[SPGFrame alloc] initWithBytes:buffer.contents width:width height:height bytesPerRow:bytesPerRow bottomUp:NO];
}

- (SPGFrame *)readFrameThroughBufferWithWidth:(uint32_t)width height:(uint32_t)height error:(NSString **)error {
    VkDeviceSize size = (VkDeviceSize)width * height * 4;
    VkBufferCreateInfo bufferInfo = {
        .sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
        .size = size,
        .usage = VK_BUFFER_USAGE_TRANSFER_DST_BIT,
    };
    VkBuffer buffer = VK_NULL_HANDLE;
    VkDeviceMemory memory = VK_NULL_HANDLE;
    vkCreateBuffer(_device, &bufferInfo, NULL, &buffer);
    VkMemoryRequirements requirements;
    vkGetBufferMemoryRequirements(_device, buffer, &requirements);
    VkMemoryAllocateInfo allocateInfo = {
        .sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
        .allocationSize = requirements.size,
    };
    SPGFrame *frame = nil;
    if ([self memoryType:requirements.memoryTypeBits
              properties:VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT
                   index:&allocateInfo.memoryTypeIndex] &&
        vkAllocateMemory(_device, &allocateInfo, NULL, &memory) == VK_SUCCESS &&
        vkBindBufferMemory(_device, buffer, memory, 0) == VK_SUCCESS) {
        VkCommandBuffer commands = _commandBuffers[_state.syncIndex];
        vkWaitForFences(_device, 1, &_state.fences[_state.syncIndex], VK_TRUE, UINT64_MAX);
        vkResetCommandBuffer(commands, 0);
        VkCommandBufferBeginInfo begin = {
            .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
            .flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
        };
        vkBeginCommandBuffer(commands, &begin);
        VkImageMemoryBarrier toTransfer = SPGBarrier(_hostImage, VK_IMAGE_LAYOUT_GENERAL,
                                                     VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, VK_ACCESS_MEMORY_READ_BIT,
                                                     VK_ACCESS_TRANSFER_READ_BIT);
        vkCmdPipelineBarrier(commands, VK_PIPELINE_STAGE_ALL_COMMANDS_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT, 0, 0, NULL,
                             0, NULL, 1, &toTransfer);
        VkBufferImageCopy region = {
            .imageSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1},
            .imageExtent = {width, height, 1},
        };
        vkCmdCopyImageToBuffer(commands, _hostImage, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, buffer, 1, &region);
        VkImageMemoryBarrier back = SPGBarrier(_hostImage, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
                                               VK_IMAGE_LAYOUT_GENERAL, VK_ACCESS_TRANSFER_READ_BIT,
                                               VK_ACCESS_MEMORY_READ_BIT);
        vkCmdPipelineBarrier(commands, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_ALL_COMMANDS_BIT, 0, 0, NULL,
                             0, NULL, 1, &back);
        vkEndCommandBuffer(commands);
        VkSubmitInfo submit = {
            .sType = VK_STRUCTURE_TYPE_SUBMIT_INFO,
            .commandBufferCount = 1,
            .pCommandBuffers = &commands,
        };
        pthread_mutex_lock(&_state.queueLock);
        vkQueueSubmit(_queue, 1, &submit, VK_NULL_HANDLE);
        vkQueueWaitIdle(_queue);
        pthread_mutex_unlock(&_state.queueLock);
        void *mapped = NULL;
        if (vkMapMemory(_device, memory, 0, size, 0, &mapped) == VK_SUCCESS) {
            frame = [[SPGFrame alloc] initWithBytes:mapped
                                              width:width
                                             height:height
                                        bytesPerRow:(NSUInteger)width * 4
                                           bottomUp:NO];
            vkUnmapMemory(_device, memory);
        }
    }
    if (!frame && error) {
        *error = @"reading the host image through a buffer failed";
    }
    if (memory) {
        vkFreeMemory(_device, memory, NULL);
    }
    if (buffer) {
        vkDestroyBuffer(_device, buffer, NULL);
    }
    return frame;
}

#pragma mark - Teardown

- (void)tearDown {
    if (_device) {
        [self waitIdle];
        vkDeviceWaitIdle(_device);
        for (int i = 0; i < SPG_SYNC_COUNT; i++) {
            if (_state.fences[i]) {
                vkDestroyFence(_device, _state.fences[i], NULL);
                _state.fences[i] = VK_NULL_HANDLE;
            }
        }
        if (_commandPool) {
            vkDestroyCommandPool(_device, _commandPool, NULL);
            _commandPool = VK_NULL_HANDLE;
        }
        if (_hostImage) {
            vkDestroyImage(_device, _hostImage, NULL);
            _hostImage = VK_NULL_HANDLE;
        }
        if (_hostMemory) {
            vkFreeMemory(_device, _hostMemory, NULL);
            _hostMemory = VK_NULL_HANDLE;
        }
        if (_negotiation && _negotiation->destroy_device) {
            _negotiation->destroy_device();
        } else {
            vkDestroyDevice(_device, NULL);
        }
        _device = VK_NULL_HANDLE;
    }
    if (_surface) {
        vkDestroySurfaceKHR(_instance, _surface, NULL);
        _surface = VK_NULL_HANDLE;
    }
    if (_instance) {
        vkDestroyInstance(_instance, NULL);
        _instance = VK_NULL_HANDLE;
    }
}

- (void)dealloc {
    [self tearDown];
    pthread_mutex_destroy(&_state.queueLock);
}

@end
