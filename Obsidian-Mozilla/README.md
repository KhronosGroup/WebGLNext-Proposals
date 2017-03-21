# Obsidian API Proposal

21th March 2017 - [Dzmitry Malyshau](mailto:dmalyshau@mozilla.com), [Jeff Gilbert](mailto:jgilbert@mozilla.com)


## Introduction

This is Mozilla's draft proposal for the GPU API for the Web, called _Obsidian_. It is a low-level API that provides maximum feature set of the GPU to the web applications. The API is designed for WebAssembly, modern GPUs, and multi-threaded environment in mind.

_Obsidian_ is a temporary code name, signifying the Vulkan roots of the API:
> Obsidian is a naturally occurring volcanic glass formed as an extrusive igneous rock.

This proposal is not a specification. It includes reasoning for the design decisions, draft WebIDL and a bit of example code. We don't aim to provide a complete specification, instead we want this proposal to represent our vision of the future API in the working group discussions, a vision of rich graphics on the Web powered by a low-level explicit API.

The contents are split into the following sections:
  1. introduction and philosophy
  2. design details, differences from Vulkan/D3D12
  3. synchronization and memory model
  4. API and examples

### History

The need for a more efficient graphics API for the Web is clear. What is not clear is the look and design of such API. Previous mailing lists discussions were split into two groups: one that considered Metal as a good baseline for the new API, due to it simpler and higher level abstraction, which is easier to provide safely on the Web. Another group saw Vulkan as an ultimately portable API that just needs to be re-defined on the Web with some feature cuts.

We built a prototype into Servo, providing a Metal-like API in WebIDL (for JavaScript), backed by Vulkan. It exposed the problems of communicating with the graphics backend via the process barrier, transcoding the commands between different APIs, and briefly touched the security aspect. We found this way to be reachable, but we also realized that this is an unique opportunity for the Web to get so much more.

Providing render passes, for example, would open the door to efficient graphics on mobile. Having secondary command buffers can vastly increase the fidelity of the content being rendered. Even exposing the resource layout can make execution on AMD hardware (in particular) more predictable. And even if it imposes a bigger CPU overhead for sanitizing the commands, it gets faster when it reaches the GPU. Thus, we decided to focus on the capability of the API instead of the simplicity.

Within the next-gen APIs, Vulkan is the most feature rich, and Metal is the simplest. The advanced shader syntax (e.g. pointer semantics) of Metal don't map well to other APIs. Thus, we started with Vulkan and SPIR-V, and for each feature (that it has over other APIs), we evaluated the cost of emulating it on the other APIs versus the benefit of exposing it.

### Main concepts

  - _Command Buffer_ - an opaque object that stores hardware commands, such as binding resources and drawing. Recording the command buffers simultaneously on multiple threads and executing them on different command queues is essential for efficient parallelization of work on both CPU and GPU.
  - _Pipeline State Object_ - an object encapsulating the shader program as well as all the state that depends on it. Keeping all that state together allows early validation by the browser as well as the native API, which can make sure all the internally used shader code is ready for the state to be used for rendering.
  - _Descriptor Set_ - an object storing a set of descriptors to be used by shaders. Reduces the overhead of binding and validation of multiple resource descriptors.
  - _Render Pass_ - a definition of a rendering pass over a particular set of surfaces. It may consist of multiple sub-passes that are very efficient to render on tile-based hardware architectures.

### Platform

We believe in the power of the Web platform. The API's main goal is providing the enhanced GPU capabilities to the Web. If some of the features, like tessellation, are not available on a particular platform, we reserve the right to either suggest an emulation path, or gate the feature by a run-time flag available to applications.

Focusing on the platform means that we are less concerned about the difficulty of using the API directly. We expect 3rd parties will build higher-level interfaces on top of the new API, as has happened for WebGL with Three.js, among others.

### Open standards

Among the next-gen desktop APIs we see Vulkan as the most capable, portable, and open. Thus, our work can be seen as a reduction of Vulkan that would make sense for the Web. We believe that the basing on Vulkan would let us focus on the missing parts instead of bike-shedding the function names.

### Design constraints

The API has to be efficiently implementable in at least Vulkan and Metal, and likely D3D12 as well. Implementability on D3D11 and OpenGL is not a constraint.

The API has to execute efficiently on WebAssembly and in multi-threaded environment. That means no GC allocations during the rendering loop in order to avoid the garbage collection pauses. Thus, we don't use strings for the enumeration types, and rendering routines don't create new objects.


## Details

The work flow we followed involved taking the Vulkan specification and evaluating features that can be ported to the Web. The main points of diversion are:

  - undefined behavior is made secure, and minimized when possible
  - restricted pipeline caches
  - restricted secondary command buffers
  - everything is internally synchronized

### Object creation, destruction, and error handling

Creating an object (e.g. buffer, descriptor set, etc) returns immediately with an opaque indentifier. The client can use this result right away for any dependent operations. The GPU process will ensure that the corresponding native object is created before it's used. If an error happens during the object creation, any operations involving this object will result in an error. We haven't finalized the exact error query mechanism, and we don't consider it vital to our core idea. For the purpose of this proposal, we added `getError` functions to some of the interfaces, allowing the client to check for a failure and react accordingly.

The destruction of the objects is explicit from the client point of view. The GPU process tracks all the real usage of a resource, and will delay the actual release of the resource until the GPU is done using it.

### Descriptor sets

Vulkan and D3D12 expose descriptor sets, which group resources ahead of time, allowing the application to bind them efficiently. These native APIs impose different restrictions on the contents of the descriptor sets, and we want to provide the intersection of their features:

  - samplers can not be mixed with any other resources in the same descriptor set
  - no descriptor arrays

On Metal, binding a descriptor set would translate to one or more calls of binding the resources (e.g. `setVertexBuffers`).

### Multiple render passes

Declaring multiple sub-passes inside a render pass is a form of providing a part of your rendering dependency graph to the driver and the hardware. It allows the results of one pixel shader to be consumed by a different one without taking a trip to the graphics memory. This is especially important on tiled architectures. For example, during the "Vulkan Game Development on Mobile" session at GDC, Hans-Kristian (of ARM) showed 30% FPS improvement and 80% bandwidth reduction from using sub-passes in a deferred renderer, when testing on Galaxy S7.

We expose the sub-passes similarly to Vulkan. On D3D12 and Metal, the pass dependencies would have to be emulated as texture parameters to the shaders, and the pass inputs replaced by regular texture fetching. The shader patching would be done before SPIR-V is converted to HLSL and MSL. Metal also has [storageModeMemoryless](https://developer.apple.com/reference/metal/mtlresourceoptions/1649224-storagemodememoryless) that can be used to store temporary sub-pass results.

### Resource layouts

Vulkan and D3D12 encapsulate the interior mutability of resources in their layouts/states. Whenever a resource is used on GPU, the user is expected to provide the current layout for it, which affects the way GPU treats the resource. If we were to track the layouts automatically, we'd face the following performance issues:

  1. In many cases, there are multiple compatible layouts (e.g. `ObImageLayout.GENERAL` can be used anywhere). We'd need some sort of heuristic to guess the best layout for a particular resource usage, which can not be as precise as the user specifying one directly.
  2. Tracking the current layout of a resource is non-trivial, especially if you consider a resource used simultaneously by multiple command buffers that are submitted to different command queues. This is the CPU overhead we'd like to avoid when recording a command buffer.
  3. User may know in advance what layout a resource is going to be used with, so they will be able to insert a memory barrier (for the layout transition) ahead of time, reducing the possible GPU stalls on waiting for that barrier.

Q: since we are going to keep track of the objects for the matter of their destruction, maybe it's not that much overhead to track the current resource layouts at the same time?
  - it is still an overhead, which becomes especially complicated when tracking comes from multiple queues and command buffers
  - this is not a problem for resource lifetime tracking, since reference counting is additive

Given no straightforward way to hide the layout mutability without compromising performance, we decided to expose this feature directly. In most cases, we are just going to pass the requested layouts down to the underlying API and guarantee that any read/writes to this resource would have undefined values, and would only touch the memory allocated for this resource.

Controlling the layout transitions directly makes the GPU performance more predictable. There is also evidence that a higher-level abstraction on the application side can handle the transitions efficiently: see Frostbite's [frame graph](http://www.frostbite.com/2017/03/framegraph-extensible-rendering-architecture-in-frostbite/).

Note: Metal, OpenGL, Direct3D11 do not expose the resource layouts, thus relevant browser implementations are free just ignore the user-provided layout transitions. Tracking and validating resource layouts would still be needed at the browser level, however.

### Undefined behavior

Undefined behavior is important to allow the graphics hardware and driver implementations to perform optimizations that rely on the input data/parameters being valid. However, we can't allow truly undefined behavior due to potential expoitability. Instead, we classify the types of such behavior and only allow restricted forms of it (with localized side effecs) in places where enforcing a particular behavior would compromise the performance. For example, when a particular operation on a resource can lead to undefined behavior, our goal is to ensure that no memory outside of the allocated region (for this resource) is accessed, and the contents of the allocated memory are initialized.

Note that we do not propose undefined behavior in any of the valid use case scenarios. What we want to constrain is the consequences of an application using the API incorrectly and running under a non-debugging session, thus with limited validation enabled.

We could classify the undefined behavior into the following classes:

  1. unrestricted. Example: loading a value outside of the resource memory. This could mean a driver crash, HW restart, access to non-owned memory, or anything else. This class poses a security risk that we can't allow for the Web API.
  2. possible GPU hangs/crashes. Example: infinite loop in the shader. This is inconvenient, and we would prefer limiting the cases to a minimum, but essentially we allow this, since it doesn't pose a security risk.
  3. undefined value. Example: accessing a resource with mismatched layout. We allow this behavior with one caveat: all resources imply a defined initial state (contrary to native APIs), so the value would never come from random GPU memory. We also recommend a validation layer in the browsers to detect and handle all occurencies of this behavior.

For the resource layouts, for example, we are working with hardware vendors, Microsoft, and Khronos to clarify the behavior (of handling mismatched layouts) in the native APIs.

### Shading language

We believe taking SPIR-V for the shading language is a straightforward and efficient solution for the Web, because:

  - it's an open, portable standard, already used for Vulkan and OpenCL
  - it maps well to the latest hardware features and has debugging meta-data
  - can be transformed to/from LLVM, allowing the source to be written in a large set of programming languages
  - it comes with a wide range of tools for reflection, optimization, and conversion to/from other shading languages, such as HLSL and GLSL

In order to guarantee secure execution on GPU, we'll need to validate the provided SPIR-V binaries and add extra checks or return an error if the code attempts to use unsafe features that we are unable to port. Here is an incomplete list of spots that we would need to patch in SPIR-V:

  - bounds checks/clamps for buffer/image access, if the underlying context does not provide robustness guarantees (part of Vulkan [device features](https://www.khronos.org/registry/vulkan/specs/1.0-wsi_extensions/html/vkspec.html#features), default in D3D11)
  - sub-pass inputs conversion to texture fetches, when the native backend doesn't support them natively
  - TODO

Concerns about SPIR-V:
  1. Non-human-readable:
    - similarly to WebAssembly, we believe that a machine-readable binary representation is the most efficient. It can be converted to a human-readable format by a tool in order to assist debugging.
    - the API can also accept GLSL specified inside the document, to be converted to SPIR-V using `glslValidator`
  2. Large binary size:
    - it is already on Khronos radar to address, plus there are community projects like SMOL-V
    - transferring the shader code is not expected to be a major network bottleneck, comparing to buffer and texture data

### Pipeline caches

Since we inspect and patch the shader code before passing it to GPU, we can't allow unknown pre-compiled binaries to be provided in the pipeline cache. In the worst case, a rogue shader can be used to exploit a driver bug and hack the system, posing a security risk. Thus, we are not providing any functions to pre-initialize a pipeline cache with data, or to get the data from cache. We do provide the pipeline caches for temporary use by an application, since can drastically reduce the time spent on pipeline creation.

### Secondary command buffers

Secondary command buffers (SCB) in Vulkan are useful for recording multiple command buffers simultaneously to be executed within sub-passes of a single primary command buffer pass. D3D12 has a similar concept, called "bundle", allowing to pre-record multiple draw calls for later re-use during the frame rendering. Early [tests(https://www.slideshare.net/DevCentralAMD/introduction-to-dx12-by-ivan-nevraev) by Microsoft] showed around 30% CPU time reduction on XBox from using bundles.

These features have slightly different goals and restrictions, but we propose to expose them via a single interface. To achieve that, we restrict SCB in the following way:

  - forbidden operations: clears, copies, command buffer executions, barriers, resolves, queries, render pass/target setups
  - a render pass, sub-pass index, and a framebuffer are provided for the SCB creation
  - you can only execute SCB inside a render pass
  - all the state that SCB can not change is inherited, no state is leaked after execution
  - it can be executed multiple times

The backend implementations would have to be smart about preserving the behavior:

  - Vulkan: use the native SCB and insert the calls to set up the framebuffer and render pass for the state initialization at the beginning of SCB.
  - D3D12: use the Bundle, reset the state back at the end of recording.
  - Metal: emulate the recording. Some sort of emulated command buffer is already required by the implementation in order to support command buffer re-submission (which native Metal doesn't have), so this logic just needs to be re-used for SCB.


## Synchronization

### CPU-CPU

Vulkan API considers most of the objects to be externally synchronized (`vkCommandBuffer`, `vkQueue`, etc). This means that the user is responsible for synchronizing the access to these objects from multiple threads.

The story of multi-threading on the client side of the Web is not finished. There are WebWorkers, and WebAssembly will eventually get its own threads. For now, we designate all objects as internally synchronized.

### CPU-GPU

The `ObFence` is the main primitive of synchronizing CPU with GPU. The API allows signalling a fence upon finishing execution of a command buffer, which the client can then wait on. Similarly, `ObDevice` and `ObQueue` objects have `waitIdle` methods.

The `ObEvent` can be used to stop a command buffer execution on the GPU until an event is fired by the client. It can also be polled by the client (but not waited upon) in case a GPU operation is expected to fire it.

### GPU-GPU

There are many levels of communication between GPU objects:

  - `ObSemaphore` allows synchronizing the resource access across multiple queues
  - `ObEvent` is a fine-grained primitive that can also be used to synchronize different command buffers
  - _Pipeline Barrier_ - provides synchronization between different parts of the GPU pipeline within a command buffer
  - _Render Passes_ - can encode dependency information between sub-passes and transit the resource layouts


## Memory model

Explicit memory allocation and re-use between resources is one of the key features of next-gen APIs (Vulkan and D3D12) for achieving a performance advantage over the older APIs.

We expose different memory types available to a device and require the memory to be allocated and bound to a resource before it can be used. A memory type can be visible to the host, be device local, or both. Any GPU operation on a resource (such as including it in a descriptor set, or in a framebuffer) requires its memory to be device local. Failure to satisfy this requirement would result in an error and the rendering operations to be discarded.

### Aliasing

Memory aliasing is useful to reduce the memory footprint of the application. For example, Frostbite engine got almost 50% reduction of render target memory usage by introducing the [transient resource system](http://www.frostbite.com/2017/03/framegraph-extensible-rendering-architecture-in-frostbite/). It does not allow using multiple resources pointing to aliased memory ranges at the same time. Doing so would result in undefined contents of the resources (see type 3 in the undefined behavior section). In other words, aliasing can be either temporal or spatial, but not both. Thus, we can safely emulate the aliasing on higher-level APIs like Metal and D3D11 by allocating the memory for each resource independently.

### CPU-GPU interaction

In order to copy the resource data between the host memory and device local memory, the following transfer operations can be recorded to a command buffer: `cmdCopyBuffer`, `cmdCopyBufferToImage`, and `cmdCopyImageToBuffer`. The temporary resource placed on the host memory is called a "staging" resource. The client can exchange the data with a staging buffer using `uploadBuffer` and `downloadBuffer` functions of the `ObDevice`.

### Initial data

The contents of all resources are initialized to 0 upon allocation. The implementation is free to skip the pre-initialization if it can prove that the resource memory is going to be completely overwritten by a transfer or draw command. For example, an allocation can be followed by an `uploadBuffer` call specifying the full range, which would override the zeroed contents completely. It makes no difference from the application point of view.

### Data races

Users are required to synchronize the access to memory (with relevant primitives described in the Synchronization section). Failure to accomplish this may lead to data races for read-vs-write and write-vs-write scenarios. We consider those data races secure, since the memory is guaranteed to be initialized, and the resulting data always comes from the user provided/generated content. This scenario falls into type 3 undefined behavior.

### Out of bounds

Any read of a resource outside of the designed bounds will return an undefined value within the resource boundaries. Any write out of bounds will be discarded. This is achieved by patching SPIR-V code before uploading it to GPU and/or enabling the robustness features of the backend API.

### Security

When a resource is bound to an allocated memory region, the implementation can check that the resource is completely contained within the memory bounds and trigger an error otherwise. Any operations with a resource that is not bound to memory are ignored, and errors are produced. Allocated memory is considered initialized, and simultaneous aliased access falls into "undefined content" category, which guarantees that no data from other applications can be leaked in.

The browser implementation tracks all resources bound to a particular memory region. The `freeMemory` operation on this region will only succeed if there are no resources that are bound to it.


## API

### Initialization

The context obtained from [Document](https://developer.mozilla.org/en/docs/Web/API/Document) is similar to [vkInstance](https://www.khronos.org/registry/vulkan/specs/1.0/man/html/VkInstance.html): it doesn't provide a single GPU device, but instead allows the user to query available GPUs and work with them manually. The browser can filter out the physically available devices, based on settings, available hardware, and the active power modes. Creating a GPU device also produces the command queues that can execute command buffers.

The user creates a swap chain manually as well by providing the [Canvas](https://developer.mozilla.org/en/docs/Web/API/Canvas) object. This is different from WebGL, where the context is obtained from the `Canvas`. Disconnecting the context from Canvas allows managing multiple canvases, potentially using different devices and command queues.

### WebIDL

_Obsidian_ is an object-oriented API [defined in WebIDL](API.webidl) for WebAssembly and JavaScript code. All related types have an `Ob` prefix (for the lack of proper namespaces in WebIDL). This convention is to be revised when we get closer to formalizing the specification.

Enumeration values as well as flags are defined as integer constants inside the corresponding interfaces, e.g. `ObPipelineStage.TRANSFER_BIT`. Using integers instead of strings (which are recommended for JavaScript-aimed WebIDL interfaces) would allow for more efficient WebAssembly interaction.

We presently use WebIDL dictionaries in place of structs in the function parameters. While the current WebAssembly implementations de-route to JavaScript for handling these, we've been assured by the WebAssembly team that the improvements are planned to map the dictionaries directly to structures, thus making them efficient for frequent in-frame function calls. Direct bindings are especially important for the native WASM threads, given that they will not have access to JavaScript.


## Examples

### Screen clear

```js
var context = document.getContext("obsidian-0.1");

// init device, queue, swapchain, and command buffer
var deviceProto = context.getPhysicalDevices()[0];
var queueFamily = deviceProto.getQueueFamilies().find(function(family) {
  return (family.queueFlags & ObQueueFlags.GRAPHICS_BIT) &&
         (family.queueFlags & ObQueueFlags.PRESENT_BIT);
});
var {device, queues: [queue]} = context.createDevice(deviceProto, [
  {
    queueFamily: queueFamily,
    queuePriorities: [1.0],
  }
]);

var canvas = document.getElementById("canvas");
var swapchain = device.createSwapchain(canvas, {
  minImageCount: 2,
});

var frameBeginSemaphore = device.createSemaphore();
var frameEndSemaphore = device.createSemaphore();
var commandBuffer = device.createPrimaryCommandBuffer(queueFamily);

// render a frame
var frameImage = device.acquireNextImage(swapchain, frameBeginSemaphore);
commandBuffer.begin();

var subresourceRange = {
  aspectMask: ObImageAspect.COLOR_BIT,
  baseMipLevel: 0,
  levelCount: 1,
  baseArrayLayer: 0,
  layerCount: 1,
};
commandBuffer.cmdPipelineBarrier(ObPipelineStage.TRANSFER_BIT, ObPipelineStage.TRANSFER_BIT, [
  {
    srcAccessMask: ObAccess.MEMORY_READ_BIT,
    dstAccessMask: ObAccess.TRANSFER_WRITE_BIT,
    oldLayout: ObImageLayout.UNDEFINED,
    newLayout: ObImageLayout.TRANSFER_DST_OPTIMAL,
    subresourceRange: subresourceRange,
  }
]);
commandBuffer.cmdClearColorImage(frameImage, ObImageLayout.TRANSFER_DST_OPTIMAL, [0.1, 0.2, 0.3, 1.0], [subresourceRange]);
commandBuffer.cmdPipelineBarrier(ObPipelineStage.TRANSFER_BIT, ObPipelineStage.TRANSFER_BIT, [
  {
    srcAccessMask: ObAccess.TRANSFER_WRITE_BIT,
    dstAccessMask: ObAccess.MEMORY_READ_BIT,
    oldLayout: ObImageLayout.TRANSFER_DST_OPTIMAL,
    newLayout: ObImageLayout.LAYOUT_PRESENT_SRC,
    subresourceRange: subresourceRange,
  }
]);

commandBuffer.end();
queue.submit({
    waitSemaphores: [frameBeginSemaphore],
    waitDstStageMasks: [ObPipelineStage.TRANSFER_BIT],
    commandBuffers: [commandBuffer],
    signalSemaphores: [frameEndSemaphore],
});
queue.present(swapchain, [frameEndSemaphore]);
```

### Specifying shaders in GLSL

While SPIR-V is the shader format of this API, the user can provide GLSL code in the document to be automatically converted to SPIR-V using [glslValidator](https://github.com/KhronosGroup/glslang):

```html
<script id="shader-vs" type="x-shader/x-vertex">
#version 450
layout(location = 0)
out vec4 vColor;
void main() {
    switch(gl_VertexIndex) {
        case 0: gl_Position = vec4(-0.5, -0.5, 0.0, 1.0); break;
        case 1: gl_Position = vec4(+0.5, -0.5, 0.0, 1.0); break;
        case 2: gl_Position = vec4(+0.0, +0.7, 0.0, 1.0); break;
    }
    vColor = gl_Position * 0.5 + 0.5;
}
</script>
<script id="shader-fs" type="x-shader/x-fragment">
#version 450
layout(location = 0)
in vec4 vColor;
layout(location = 0)
out vec4 oColor;
void main() {
    oColor = vColor;
}
</script>
```

### Triangle state preparation

```js
var renderpass = device.createRenderPass({
  attachments: [
    {
      format: swapchain.format,
      samples: ObSampleCount.S1_BIT,
      loadOp: ObAttachmentLoadOp.CLEAR,
      storeOp: ObAttachmentLoadOp.STORE,
      initialLayout: ObImageLayout.UNDEFINED,
      finalLayout: ObImageLayout.PRESENT_SRC,
    },
  ],
  subpasses: [
    {
      pipelineBindPoint: ObPipelineBindPoint.GRAPHICS,
      inputAttachments: [],
      colorAttachments: {
        0 => ObImageLayout.COLOR_ATTACHMENT_OPTIMAL,
      },
      preserveAttachments: [],
    }
  ],
  dependencies: [],
});
//Note: for rendering more than one frame, we'll need a framebuffer per swap image
var framebuffer = device.createFramebuffer({
  renderPass: renderPass,
  attachments: [frameImage],
  width: swapchain.width,
  height: swapchain.height,
  layers: 1,
});
//Note: providing GLSL text arguments to `createShaderModule`
var vsModule = device.createShaderModule(document.getElementById("shader-vs").textContent);
var fsModule = device.createShaderModule(document.getElementById("shader-fs").textContent);
var pipelineLayout = device.createPipelineLayout({
  descriptorSetLayouts: [],
  pushConstantRanges: [],
});
var [pipeline] = device.createGraphicsPipelines([
  {
    stages: {
      ObShaderStage.VERTEX_BIT => {
        module: vsModule,
        name: "main",
      },
      ObShaderStage.FRAGMENT_BIT => {
        module: fsModule,
        name: "main",
      },
    },
    vertexInputState: {
      vertexBindingDescriptions: [],
      vertexAttrbuteDescriptions: [],
    },
    inputAssemblyState: {
      topology: ObPrimitiveTopology.TRIANGLE_LIST,
    },
    viewportState: {
      viewports: [
        {
          x: 0,
          y: 0,
          width: swapchain.width,
          height: swapchain.height,
        }
      ],
      scissors: [
        {
          offset: [0, 0],
          extent: [swapchain.width, swapchain.height],
        }
      ],
    },
    rasterizationState: {
      polygonMode: ObPolygonMode.FILL,
      cullMode: ObCullMode.BACK_BIT,
      frontFace: ObFrontFace.COUNTER_CLOCKWISE,
    },
    multisampleState: {
      rasterizationSamples: ObSampleCount.S1_BIT,
    },
    colorBlendState: {
      logicOpEnable: false,
      attachments: [
        {
          blendEnable: false,
        }
      ],
      blendConstants: [0.0, 0.0, 0.0, 0.0],
    },
    layout: pipelineLayout,
    renderPass: renderPass,
    subpass: 0,
  }
]);
```

### Triangle rendering

```js
commandBuffer.cmdBeginRenderPass({
  renderPass: renderPass,
  framebuffer: framebuffer,
  renderArea: {
    offset: [0, 0],
    extent: [swapchain.width, swapchain.height],
  },
  clearValues: [
    [0.1, 0.2, 0.3, 1.0]
  ],
});
commandBuffer.cmdBindPipeline(ObPipelineBindPoint.GRAPHICS, pipeline);
commandBuffer.cmdDraw(3, 1, 0, 0);
commandBuffer.cmdEndRenderPass();
```

### Vertex data setup

```js
var hostMemoryType = deviceProto.getMemoryTypes().find(function(type) {
  return type.memoryFlags & ObMemoryFlags.HOST_VISIBLE_BIT;
});
var deviceMemoryType = deviceProto.getMemoryTypes().find(function(type) {
  return type.memoryFlags & ObMemoryFlags.DEVICE_LOCAL_BIT;
});

// allocate and fill the staging buffer
var bufferSize = 4 * 4 * (4 + 4);
var stagingBuffer = device.createBuffer({
  size: bufferSize,
  usage: ObBufferUsage.TRANSFER_SRC_BIT,
});
var stagingMemory = device.allocateMemory(hostMemoryType, stagingBuffer.getMemoryRequirements());
device.mapBufferMemory(stagingBuffer, stagingMemory, 0);
device.uploadBuffer(stagingBuffer, 0, new Float32Array([
  // X     Y    Z    W     R    G    B    A
  -0.7, -0.7, 0.0, 1.0,  1.0, 0.0, 0.0, 0.0,
  -0.7,  0.7, 0.0, 1.0,  0.0, 1.0, 0.0, 0.0,
   0.7, -0.7, 0.0, 1.0,  0.0, 0.0, 1.0, 0.0,
   0.7,  0.7, 0.0, 1.0,  0.3, 0.3, 0.3, 0.0,
]));

var vertexBuffer = device.createBuffer({
  size: bufferSize,
  usage: ObBufferUsage.TRANSFER_DST_BIT | ObBufferUsage.VERTEX_BUFFER_BIT,
});
var deviceBufferMemory = device.allocateMemory(deviceMemoryType, vertexBuffer.getMemoryRequirements());
device.mapBufferMemory(vertexBuffer, deviceBufferMemory, 0);

// the PSO initialization part
var vertexBinding = 0;
var vertexInputState = {
  vertexBindingDescriptions: {
    vertexBinding => {
      stride: (4 + 4) * 4,
      inputRate: ObVertexInputRate.VERTEX,
    }
  },
  vertexAttrbuteDescriptions: {
    0 => {
      binding: vertexBinding,
      format: ObFormat.R32G32B32A32_SFLOAT,
      offset: 0,
    },
    1 => {
      binding: vertexBinding,
      format: ObFormat.R32G32B32A32_SFLOAT,
      offset: 4 * 4,
    },
  },
};
// one-time initialization, assuming the `commandBuffer.begin()` was called
commandBuffer.cmdCopyBuffer(stagingBuffer, vertexBuffer, [
  {
    srcOffset: 0,
    dstOffset: 0,
    size: bufferSize,
  }
]);
```

## Acknowledgements

Mozillians:
  - Glenn Watson
  - Jeff Muizelaar
  - Nicolas Silva
  - Olli Pettay

External reviewers:
  - Baldur Karlsson
  - Markus Siglreithmaier
  - Martin Krastev
  - Pierre Krieger
  - Wolfgang Engel
