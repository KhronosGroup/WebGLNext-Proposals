// main section

interface ObContext {
    sequence<DOMString>        getSupportedExtensions();
    any?                       enableExtension(DOMString name);
    sequence<ObPhysicalDevice> getPhysicalDevices();
    ObCreatedDevice            createDevice(ObPhysicalDevice device, sequence<ObQueueCreateInfo> queueInfos);
};

interface ObQueueFamily {
    readonly attribute ObQueueFlagsEnum queueFlags;
};

interface ObMemoryType {
    readonly attribute ObMemoryFlagsEnum memoryFlags;
};

interface ObPhysicalDevice {
    sequence<ObQueueFamily> getQueueFamilies();
    sequence<ObMemoryType>  getMemoryTypes();
};

interface ObDevice {
    ObSwapchain    createSwapchain(HTMLCanvasElement canvas, ObCanvasCreateInfo info);
    ObImage?       acquireNextImage(ObSwapchain swapchain, unsigned long timeout, ObSemaphore semaphore, optional ObFence? fence = null);
    ObDeviceError? getError();
    ObFence        createFence(boolean signalled);
    void           resetFences(sequence<ObFence> fences);
    boolean        waitForFences(sequence<ObFence> fences, boolean waitAll, unsigned long timeout);
    void           destroyFence(ObFence fence);
    ObSemaphore    createSemaphore();
    void           destroySemaphore(ObSemaphore semaphore);
    ObEvent        createEvent();
    void           setEvent(ObEvent event);
    void           resetEvent(ObEvent event);
    ObEventStatus  getEventStatus(ObEvent event);
    void           destroyEvent(ObEvent event);
    ObQueryPool             createQueryPool(ObQueryPoolCreateInfo info);
    sequence<ObQueryResult> getQueryPoolResults(ObQueryPool pool, unsigned short first, unsigned short count);
    void                    destroyQueryPool(ObQueryPool pool);
    void                      waitIdle();
    ObPrimaryCommandBuffer    createPrimaryCommandBuffer(ObQueueFamily family);
    ObSecondaryCommandBuffer  createSecondaryCommandBuffer(ObQueueFamily family, ObSecondaryCommandBufferCreateInfo info);
    void                      destroyCommandBuffer(ObCommandBuffer buffer);
    ObRenderPass              createRenderPass(ObRenderPassCreateInfo info);
    void                      destroyRenderPass(ObRenderPass pass);
    ObFramebuffer             createFramebuffer(ObFramebufferCreateInfo info);
    void                      destroyFramebuffer(ObFramebuffer buffer);
    ObShaderModule            createShaderModule((DOMString or Blob) glslTextOrSpirvBinary);
    void                      destroyShaderModule(ObShaderModule shaderModule);
    ObComputePipeline         createComputePipeline(ObComputePipelineCreateInfo info);
    ObGraphicsPipeline        createGraphicsPipeline(ObGraphicsPipelineCreateInfo info);
    void                      destroyPipeline(ObPipeline pipeline);
    ObSampler                 createSampler(ObSamplerCreateInfo info);
    void                      destroySampler(ObSampler sampler);
    ObDescriptorSetLayout     createDescriptorSetLayout(sequence<ObDescriptorSetBinding> bindings);
    void                      destroyDescriptorSetLayout(ObDescriptorSetLayout layout);
    ObPipelineLayout          createPipelineLayout(ObPipelineLayoutCreateInfo info);
    void                      destroyPipelineLayout(ObPipelineLayout layout);
    ObDescriptorPool          createDescriptorPool(ObDescriptorPoolCreateInfo info);
    void                      destroyDescriptorPool(ObDescriptorPool pool);
    sequence<ObDescriptorSet> allocateDescriptorSets(ObDescriptorPool pool, sequence<ObDescriptorSetLayout> layouts);
    void                      updateDescriptorSets(sequence<ObWriteDecriptorSet> writes, sequence<ObCopyDescriptorSet> copies);
    void                      freeDescriptorSets(ObDescriptorPool pool, sequence<ObDescriptorSet> sets);
    ObMemory                  allocateMemory(ObMemoryType type, ObMemoryRequirements requirements);
    void                      freeMemory(ObMemory memory);
    ObBuffer                  createBuffer(ObBufferCreateInfo info);
    void                      uploadBuffer(ObBuffer buffer, unsigned long offset, ArrayBuffer data);
    ArrayBuffer               downloadBuffer(ObBuffer buffer, unsigned long offset, unsigned long size);
    void                      destroyBuffer(ObBuffer buffer);
    void                      bindBufferMemory(ObBuffer buffer, ObMemory memory, unsigned long offset);
    void                      bindImageMemory(ObImage image, ObMemory memory, unsigned long offset);
};

interface ObSwapchain {
    readonly attribute unsigned long width;
    readonly attribute unsigned long height;
    readonly attribute ObFormatEnum format;
};

interface ObQueue {
    void          submit(ObSubmitInfo info, optional ObFence? fence = null); //TODO
    void          present(ObSwapchain swapchain, sequence<ObSemaphore> semaphores);
    void          waitIdle();
    ObQueueError? getError();
};

interface ObCommandBuffer {
    void begin();
    void end();
    void cmdSetEvent(ObEvent event, ObStageMask stages);
    void cmdResetEvent(ObEvent event, ObStageMask stages);
    void cmdWaitEvents(sequence<ObEvent> events, ObStageMask sourceStages, ObStageMask destStages, ObMemoryBarriers barriers);
    void cmdBindPipeline(ObPipelineBindPointEnum bind, ObPipeline pipeline);
    void cmdBindDescriptorSets(ObPipelineBindPointEnum bind, ObPipelineLayout layout, sequence<ObDescriptorSet> descriptors, sequence<unsigned long> dynamicOffsets);
    void cmdPushConstants(ObPipelineLayout layout, ObShaderStage shaderStages, unsigned long offset, Blob data);
    void cmdBindIndexBuffer(ObBuffer buffer, unsigned long offset, ObIndexType type);
    void cmdDraw(unsigned long vertexCount, unsigned long instanceCount, unsigned long firstVertex, unsigned long firstInstance);
    void cmdDrawIndexed(unsigned long indexCount, unsigned long instanceCount, unsigned long firstIndex, unsigned long vertexOffset, unsigned long firstInstance);
    void cmdDrawIndirect(ObBuffer buffer, unsigned long offset, unsigned long drawCount, unsigned long stride);
    ObCommandBufferError? getError();
};

interface ObPrimaryCommandBuffer: ObCommandBuffer {
    void cmdExecuteCommands(sequence<ObSecondaryCommandBuffer> combufs);
    void cmdPipelineBarrier(ObStageMask sourceStages, ObStageMask destStages, ObMemoryBarriers barriers);
    void cmdBeginRenderPass(ObRenderPassBeginInfo info);
    void cmdNextSubpass();
    void cmdEndRenderPass();
    void cmdResetQueryPool(ObQueryPool pool, unsigned short first, unsigned short count);
    void cmdBeginQuery(ObQueryPool pool, unsigned short index);
    void cmdEndQuery(ObQueryPool pool, unsigned short index);
    void cmdClearColorImage(ObImage image, ObImageLayoutEnum layout, ObClearColorInfo info, sequence<ObSubresourceRange> ranges);
    void cmdClearDepthStencil(ObImage image, ObImageLayoutEnum layout, ObClearDepthStencilInfo info);
    void cmdClearAttachments(sequence<ObClearAttachment> attachments, sequence<ObClearRect> rectangles);
    void cmdFillBuffer(ObBuffer dest, unsigned long offset, unsigned long size, unsigned long value);
    void cmdUpdateBuffer(ObBuffer dest, unsigned long offset, unsigned long size, ArrayBuffer data);
    void cmdCopyBuffer(ObBuffer src, ObBuffer dst, sequence<ObBufferCopy> regions);
    void cmdCopyImage(ObImage src, ObImageLayoutEnum srcLayout, ObImage dst, ObImageLayoutEnum dstLayout, sequence<ObImageCopy> regions);
    void cmdCopyBufferToImage(ObBuffer src, ObImage dst, ObImageLayoutEnum dstLayout, sequence<ObBufferImageCopy> regions);
    void cmdCopyImageToBuffer(ObImage src, ObImageLayoutEnum srcLayout, ObBuffer dst, sequence<ObBufferImageCopy> regions);
    void cmdResolveImage(ObImage src, ObImageLayoutEnum srcLayout, ObImage dst, ObImageLayoutEnum dstLayout, sequence<ObImageResolve> regions);
};

interface ObSecondaryCommandBuffer: ObCommandBuffer {
};

interface ObBuffer {
    ObMemoryRequirements getMemoryRequirements();
    ObBufferError?       getError();
};

// stubs

dictionary ObRenderPassCreateInfo {
    required byte stub;
};
dictionary ObFramebufferCreateInfo {
    required byte stub;
};
dictionary ObComputePipelineCreateInfo {
    required byte stub;
};
dictionary ObGraphicsPipelineCreateInfo {
    required byte stub;
};
dictionary ObSamplerCreateInfo {
    required byte stub;
};
dictionary ObDescriptorSetBinding {
    required byte stub;
};
dictionary ObPipelineLayoutCreateInfo {
    required byte stub;
};
dictionary ObDescriptorPoolCreateInfo {
    required byte stub;
};
dictionary ObQueryPoolCreateInfo {
    required byte stub;
};
dictionary ObBufferCreateInfo {
    required byte stub;
};
dictionary ObRenderPassBeginInfo {
    required byte stub;
};
dictionary ObClearDepthStencilInfo {
    required byte stub;
};
dictionary ObWriteDecriptorSet {};
dictionary ObCopyDescriptorSet {};
dictionary ObClearAttachment {};
dictionary ObClearRect {};
dictionary ObSubresourceRange {};
dictionary ObImageResolve {};
dictionary ObBufferCopy {};
dictionary ObImageCopy {};
dictionary ObBufferImageCopy {};
typedef byte ObDeviceError;
typedef byte ObQueueError;
typedef byte ObCommandBufferError;
typedef byte ObBufferError;
typedef sequence<float> ObClearColorInfo;
typedef byte ObEventStatus;
typedef byte ObQueryResult;
typedef byte ObStageMask;
typedef byte ObShaderStage;
typedef byte ObIndexType;
interface ObFence {};
interface ObSemaphore {};
interface ObEvent {};
interface ObRenderPass {};
interface ObFramebuffer {};
interface ObShaderModule {};
interface ObPipeline {};
interface ObComputePipeline: ObPipeline {};
interface ObGraphicsPipeline: ObPipeline {};
interface ObSampler {};
interface ObPipelineLayout {};
interface ObDescriptorSetLayout {};
interface ObDescriptorPool {};
interface ObDescriptorSet {};
interface ObQueryPool {};
interface ObMemory {};
interface ObImage {};

// structures

dictionary ObCreatedDevice {
    ObDevice          device;
    sequence<ObQueue> queues;
};

dictionary ObQueueCreateInfo {
    ObQueueFamily     queueFamily;
    sequence<float>    queuePriorities;
};

dictionary ObCanvasCreateInfo {
    required unsigned short minImageCount;
};

dictionary ObSubmitInfo {
    required sequence<ObSemaphore>            waitSemaphores;
    required sequence<ObStageMask>            waitDstStageMasks;
    required sequence<ObPrimaryCommandBuffer> commandBuffers;
    required sequence<ObSemaphore>            signalSemaphores;
};

dictionary ObMemoryRequirements {
    required unsigned long  size;
    required unsigned long  alignment;
    required ObMemoryFlagsEnum memoryFlags;
};

dictionary ObMemoryBarriers {
    required ObAccessEnum      srcAccessMask;
    required ObAccessEnum      dstAccessMask;
    required ObImageLayoutEnum  oldLayout;
    required ObImageLayoutEnum  newLayout;
    required ObSubresourceRange subresourceRange;
};

// constants
//Note - WebIDL validator complains:
//> the Web platform is moving away from using named integer codes in the style of an enumeration, in favor of the use of strings

typedef byte ObQueueFlagsEnum;
interface ObQueueFlags {
    const byte GRAPHICS_BIT = 1;
    const byte PRESENT_BIT = 2;
};

typedef byte ObMemoryFlagsEnum;
interface ObMemoryFlags {
    const byte HOST_VISIBLE_BIT = 1;
    const byte DEVICE_LOCAL_BIT = 2;
};

typedef byte ObImageAspectEnum;
interface ObImageAspect {
    const byte COLOR_BIT = 1;
    const byte DEPTH_BIT = 2;
    const byte STENCIL_BIT = 4;
};

typedef byte ObImageLayoutEnum;
interface ObImageLayout {
    const byte UNDEFINED = 0;
    const byte GENERAL = 1;
    const byte COLOR_ATTACHMENT_OPTIMAL = 2;
    const byte DEPTH_STENCIL_ATTACHMENT_OPTIMAL = 3;
    const byte DEPTH_STENCIL_READ_ONLY_OPTIMAL = 4;
    const byte SHADER_READ_ONLY_OPTIMAL = 5;
    const byte TRANSFER_SRC_OPTIMAL = 6;
    const byte TRANSFER_DST_OPTIMAL = 7;
    const byte PREINITIALIZED = 8;
    const byte PRESENT_SRC = 9;
};

typedef long ObPipelineStageEnum;
interface ObPipelineStage {
    //TODO
    const long TRANSFER_BIT = 0x1000;
};

typedef byte ObPipelineBindPointEnum;
interface ObPipelineBindPoint {
    const byte GRAPHICS = 0;
    const byte COMPUTE = 1;
};

typedef long ObAccessEnum;
interface ObAccess {
    //TODO
    const long TRANSFER_WRITE_BIT = 0x00001000;
    const long MEMORY_READ_BIT    = 0x00008000;
};

typedef long ObSampleCountEnum;
interface ObSampleCount {
    const long S1_BIT = 1;
    //TODO
};

typedef byte ObAttachmentLoadOpEnum;
interface ObAttachmentLoadOp {
    const byte LOAD = 0;
    const byte CLEAR = 1;
    const byte DONT_CARE = 2;
};

typedef byte ObAttachmentStoreOpEnum;
interface ObAttachmentStoreOp {
    const byte STORE = 0;
    const byte DONT_CARE = 1;
};

typedef byte ObPrimitiveTopologyEnum;
interface ObPrimitiveTopology {
    //TODO
    const byte TRIANGLE_LIST = 3;
};

typedef byte ObFormatEnum;
interface ObFormat {
    const byte R32G32B32A32_SFLOAT = 109;
};

typedef long ObBufferUsageEnum;
interface ObBufferUsage {
    const long TRANSFER_SRC_BIT  = 0x00000001;
    const long TRANSFER_DST_BIT  = 0x00000002;
    const long VERTEX_BUFFER_BIT = 0x00000080;
    //TODO
};

typedef byte ObVertexInputRateEnum;
interface ObVertexInputRate {
    const byte VERTEX = 0;
    const byte INSTANCE = 1;
};

typedef byte ObPolygonModeEnum;
interface ObPolygonMode {
    const byte FILL = 0;
    const byte LINE = 1;
    const byte POINT = 2;
};

typedef byte ObCullModeEnum;
interface ObCullMode {
    const byte NONE = 0;
    const byte FRONT_BIT = 1;
    const byte BACK_BIT = 2;
    const byte FRONT_AND_BACK = 3;
};

typedef byte ObFrontFaceEnum;
interface ObFrontFace {
    const byte COUNTER_CLOCKWISE = 0;
    const byte CLOCKWISE = 1;
};
