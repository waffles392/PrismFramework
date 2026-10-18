import CSDL3
import Foundation

/// primitive assembly topology for graphics pipelines
public enum PrimitiveTopology: Sendable {
    case triangleList
    case lineList
    
    internal var nativeValue: SDL_GPUPrimitiveType {
        switch self {
        case .triangleList: return SDL_GPU_PRIMITIVETYPE_TRIANGLELIST
        case .lineList: return SDL_GPU_PRIMITIVETYPE_LINELIST
        }
    }
}

/// describes a vertex buffer layout for pipeline creation
public struct VertexBufferLayout: Sendable {
    public let slot: UInt32
    public let stride: UInt32
    public let inputRate: SDL_GPUVertexInputRate
    public let instanceStepRate: UInt32
    
    public init(
        slot: UInt32 = 0,
        stride: UInt32,
        inputRate: SDL_GPUVertexInputRate = SDL_GPU_VERTEXINPUTRATE_VERTEX,
        instanceStepRate: UInt32 = 0
    ) {
        self.slot = slot
        self.stride = stride
        self.inputRate = inputRate
        self.instanceStepRate = instanceStepRate
    }
}

/// describes a vertex attribute for pipeline creation
public struct VertexAttribute: Sendable {
    public let location: UInt32
    public let bufferSlot: UInt32
    public let format: SDL_GPUVertexElementFormat
    public let offset: UInt32
    
    public init(
        location: UInt32,
        bufferSlot: UInt32,
        format: SDL_GPUVertexElementFormat,
        offset: UInt32
    ) {
        self.location = location
        self.bufferSlot = bufferSlot
        self.format = format
        self.offset = offset
    }
    
    internal var sdlValue: SDL_GPUVertexAttribute {
        var attr = SDL_GPUVertexAttribute()
        attr.location = location
        attr.buffer_slot = bufferSlot
        attr.format = format
        attr.offset = offset
        return attr
    }
}

extension VertexAttribute {
    /// a 4-component 'float' attribute (16 bytes), for meshes that use a
    /// custom vertex layout such as packed 4D points
    public static func float4(
        location: UInt32 = 0,
        bufferSlot: UInt32 = 0,
        offset: UInt32 = 0
    ) -> VertexAttribute {
        VertexAttribute(
            location: location,
            bufferSlot: bufferSlot,
            format: SDL_GPU_VERTEXELEMENTFORMAT_FLOAT4,
            offset: offset
        )
    }
}

/// a graphics pipeline object
///
/// pipelines are created with a vertex shader, fragment shader, vertex layout,
/// blend mode, and render target format. they are reference-counted through
/// the device's resource tracking
///
/// 'Pipeline' is '@unchecked Sendable' because it is read-only after init:
/// the C handle is stored once and only read
public final class Pipeline: @unchecked Sendable {
    internal let handle: OpaquePointer
    
    private let device: GPUDevice
    private let resourceToken: UInt64
    
    /// creates a new graphics pipeline targeting the given color format
    public convenience init(
        device: GPUDevice,
        vertexShader: Shader,
        fragmentShader: Shader,
        vertexLayout: VertexBufferLayout,
        vertexAttributes: [VertexAttribute],
        targetFormat: TextureFormat,
        emissiveFormat: TextureFormat? = nil,
        blendMode: BlendMode = .alpha,
        primitiveTopology: PrimitiveTopology = .triangleList,
        cullMode: SDL_GPUCullMode = SDL_GPU_CULLMODE_NONE,
        frontFace: SDL_GPUFrontFace = SDL_GPU_FRONTFACE_COUNTER_CLOCKWISE,
        enableDepthTest: Bool = false,
        enableDepthWrite: Bool = false,
        depthFormat: TextureFormat = .depth24Stencil8
    ) throws {
        try self.init(
            device: device,
            vertexShader: vertexShader,
            fragmentShader: fragmentShader,
            vertexLayout: vertexLayout,
            vertexAttributes: vertexAttributes,
            targetFormatRaw: targetFormat.nativeValue,
            emissiveFormatRaw: emissiveFormat?.nativeValue,
            blendMode: blendMode,
            primitiveTopology: primitiveTopology,
            cullMode: cullMode,
            frontFace: frontFace,
            enableDepthTest: enableDepthTest,
            enableDepthWrite: enableDepthWrite,
            depthFormat: depthFormat
        )
    }

    /// designated initializer accepting raw SDL color-target formats
    ///
    /// required for pipelines that render directly to the swapchain, whose
    /// format is only known at runtime and may not map to a named
    /// 'TextureFormat'
    ///
    /// 'emissiveFormatRaw' adds a second colour target used for emissive glow.
    /// when present, pipelines must be created against the same two formats as
    /// the render pass they are drawn into
    internal init(
        device: GPUDevice,
        vertexShader: Shader,
        fragmentShader: Shader,
        vertexLayout: VertexBufferLayout,
        vertexAttributes: [VertexAttribute],
        targetFormatRaw: SDL_GPUTextureFormat,
        emissiveFormatRaw: SDL_GPUTextureFormat? = nil,
        blendMode: BlendMode = .alpha,
        primitiveTopology: PrimitiveTopology = .triangleList,
        cullMode: SDL_GPUCullMode = SDL_GPU_CULLMODE_NONE,
        frontFace: SDL_GPUFrontFace = SDL_GPU_FRONTFACE_COUNTER_CLOCKWISE,
        enableDepthTest: Bool = false,
        enableDepthWrite: Bool = false,
        depthFormat: TextureFormat = .depth24Stencil8
    ) throws {
        self.device = device
        
        guard let deviceHandle = device.handle else {
            throw GPUError.deviceShutdown
        }
        
        guard targetFormatRaw != SDL_GPU_TEXTUREFORMAT_INVALID else {
            throw GPUError.pipelineCreationFailed("Invalid color target format")
        }
        
        var vertexBufferDesc = SDL_GPUVertexBufferDescription()
        vertexBufferDesc.slot = vertexLayout.slot
        vertexBufferDesc.pitch = vertexLayout.stride
        vertexBufferDesc.input_rate = vertexLayout.inputRate
        vertexBufferDesc.instance_step_rate = vertexLayout.instanceStepRate
        
        let colorWriteMask = SDL_GPUColorComponentFlags(
            SDL_GPU_COLORCOMPONENT_R |
            SDL_GPU_COLORCOMPONENT_G |
            SDL_GPU_COLORCOMPONENT_B |
            SDL_GPU_COLORCOMPONENT_A
        )

        var colorTargets: [SDL_GPUColorTargetDescription] = []

        var colorTarget = SDL_GPUColorTargetDescription()
        colorTarget.format = targetFormatRaw
        colorTarget.blend_state.color_write_mask = colorWriteMask
        colorTarget.blend_state.enable_blend = blendMode != .normal
        
        switch blendMode {
        case .normal:
            colorTarget.blend_state.src_color_blendfactor = SDL_GPU_BLENDFACTOR_ONE
            colorTarget.blend_state.dst_color_blendfactor = SDL_GPU_BLENDFACTOR_ZERO
            colorTarget.blend_state.src_alpha_blendfactor = SDL_GPU_BLENDFACTOR_ONE
            colorTarget.blend_state.dst_alpha_blendfactor = SDL_GPU_BLENDFACTOR_ZERO
        case .alpha:
            colorTarget.blend_state.src_color_blendfactor = SDL_GPU_BLENDFACTOR_SRC_ALPHA
            colorTarget.blend_state.dst_color_blendfactor = SDL_GPU_BLENDFACTOR_ONE_MINUS_SRC_ALPHA
            colorTarget.blend_state.src_alpha_blendfactor = SDL_GPU_BLENDFACTOR_ONE
            colorTarget.blend_state.dst_alpha_blendfactor = SDL_GPU_BLENDFACTOR_ONE_MINUS_SRC_ALPHA
        case .additive:
            colorTarget.blend_state.src_color_blendfactor = SDL_GPU_BLENDFACTOR_ONE
            colorTarget.blend_state.dst_color_blendfactor = SDL_GPU_BLENDFACTOR_ONE
            colorTarget.blend_state.src_alpha_blendfactor = SDL_GPU_BLENDFACTOR_ONE
            colorTarget.blend_state.dst_alpha_blendfactor = SDL_GPU_BLENDFACTOR_ONE
        case .multiply:
            colorTarget.blend_state.src_color_blendfactor = SDL_GPU_BLENDFACTOR_DST_COLOR
            colorTarget.blend_state.dst_color_blendfactor = SDL_GPU_BLENDFACTOR_ZERO
            colorTarget.blend_state.src_alpha_blendfactor = SDL_GPU_BLENDFACTOR_DST_ALPHA
            colorTarget.blend_state.dst_alpha_blendfactor = SDL_GPU_BLENDFACTOR_ZERO
        case .screen:
            colorTarget.blend_state.src_color_blendfactor = SDL_GPU_BLENDFACTOR_ONE
            colorTarget.blend_state.dst_color_blendfactor = SDL_GPU_BLENDFACTOR_ONE_MINUS_SRC_COLOR
            colorTarget.blend_state.src_alpha_blendfactor = SDL_GPU_BLENDFACTOR_ONE
            colorTarget.blend_state.dst_alpha_blendfactor = SDL_GPU_BLENDFACTOR_ONE_MINUS_SRC_ALPHA
        case .overlay:
            colorTarget.blend_state.src_color_blendfactor = SDL_GPU_BLENDFACTOR_ONE_MINUS_DST_COLOR
            colorTarget.blend_state.dst_color_blendfactor = SDL_GPU_BLENDFACTOR_ONE
            colorTarget.blend_state.src_alpha_blendfactor = SDL_GPU_BLENDFACTOR_ONE
            colorTarget.blend_state.dst_alpha_blendfactor = SDL_GPU_BLENDFACTOR_ONE_MINUS_SRC_ALPHA
        }
        colorTarget.blend_state.color_blend_op = SDL_GPU_BLENDOP_ADD
        colorTarget.blend_state.alpha_blend_op = SDL_GPU_BLENDOP_ADD

        colorTargets.append(colorTarget)

        // the emissive target always accumulates additively, even for opaque
        // '.normal' surfaces, so glow from separate draws sums rather than
        // overwriting the previous value
        if let emissiveFormatRaw {
            var emissiveTarget = SDL_GPUColorTargetDescription()
            emissiveTarget.format = emissiveFormatRaw
            emissiveTarget.blend_state.color_write_mask = colorWriteMask
            emissiveTarget.blend_state.enable_blend = true
            emissiveTarget.blend_state.src_color_blendfactor = SDL_GPU_BLENDFACTOR_ONE
            emissiveTarget.blend_state.dst_color_blendfactor = SDL_GPU_BLENDFACTOR_ONE
            emissiveTarget.blend_state.src_alpha_blendfactor = SDL_GPU_BLENDFACTOR_ONE
            emissiveTarget.blend_state.dst_alpha_blendfactor = SDL_GPU_BLENDFACTOR_ONE
            emissiveTarget.blend_state.color_blend_op = SDL_GPU_BLENDOP_ADD
            emissiveTarget.blend_state.alpha_blend_op = SDL_GPU_BLENDOP_ADD
            colorTargets.append(emissiveTarget)
        }
        
        var info = SDL_GPUGraphicsPipelineCreateInfo()
        info.vertex_shader = vertexShader.handle
        info.fragment_shader = fragmentShader.handle
        info.vertex_input_state.vertex_buffer_descriptions = withUnsafePointer(to: &vertexBufferDesc) { $0 }
        info.vertex_input_state.num_vertex_buffers = 1
        
        let sdlAttributes = vertexAttributes.map { $0.sdlValue }
        info.vertex_input_state.vertex_attributes = sdlAttributes.withUnsafeBufferPointer { $0.baseAddress }
        info.vertex_input_state.num_vertex_attributes = UInt32(sdlAttributes.count)
        
        info.primitive_type = primitiveTopology.nativeValue
        info.rasterizer_state.fill_mode = SDL_GPU_FILLMODE_FILL
        info.rasterizer_state.cull_mode = cullMode
        info.rasterizer_state.front_face = frontFace
        info.rasterizer_state.enable_depth_clip = true
        info.multisample_state.sample_count = SDL_GPU_SAMPLECOUNT_1
        info.depth_stencil_state.enable_depth_test = enableDepthTest
        info.depth_stencil_state.enable_depth_write = enableDepthWrite
        info.target_info.color_target_descriptions = colorTargets.withUnsafeBufferPointer { $0.baseAddress }
        info.target_info.num_color_targets = UInt32(colorTargets.count)
        info.target_info.depth_stencil_format = depthFormat.nativeValue
        info.target_info.has_depth_stencil_target = enableDepthTest
        
        guard let pipeline = SDL_CreateGPUGraphicsPipeline(deviceHandle, &info) else {
            let error = String(cString: SDL_GetError())
            throw GPUError.pipelineCreationFailed(error)
        }
        
        self.handle = pipeline
        self.resourceToken = device.registerResource { [weak device] in
            guard let deviceHandle = device?.handle else { return }
            SDL_ReleaseGPUGraphicsPipeline(deviceHandle, pipeline)
        }
    }
    
    deinit {
        guard device.unregisterResource(resourceToken) else { return }
        guard let deviceHandle = device.handle else { return }
        SDL_ReleaseGPUGraphicsPipeline(deviceHandle, handle)
    }
}

/// pipeline cache for reusing pipeline objects
///
/// pipelines are expensive to create, so this cache reuses them based on their
/// creation parameters. the cache key is a combination of shader handles and
/// pipeline state settings
public final class PipelineCache {
    private var cache: [PipelineCacheKey: Pipeline] = [:]
    private let device: GPUDevice
    
    private struct PipelineCacheKey: Hashable {
        let vertexShaderHandle: UInt64
        let fragmentShaderHandle: UInt64
        let vertexStride: UInt32
        let targetFormat: TextureFormat
        let emissiveFormat: TextureFormat?
        let blendMode: BlendMode
        let primitiveTopology: PrimitiveTopology
        
        init(
            vertexShader: Shader,
            fragmentShader: Shader,
            vertexStride: UInt32,
            targetFormat: TextureFormat,
            emissiveFormat: TextureFormat?,
            blendMode: BlendMode,
            primitiveTopology: PrimitiveTopology
        ) {
            self.vertexShaderHandle = UInt64(UInt(bitPattern: vertexShader.handle))
            self.fragmentShaderHandle = UInt64(UInt(bitPattern: fragmentShader.handle))
            self.vertexStride = vertexStride
            self.targetFormat = targetFormat
            self.emissiveFormat = emissiveFormat
            self.blendMode = blendMode
            self.primitiveTopology = primitiveTopology
        }
    }
    
    public init(device: GPUDevice) {
        self.device = device
    }
    
    /// gets or creates a pipeline with the given parameters
    public func pipeline(
        vertexShader: Shader,
        fragmentShader: Shader,
        vertexStride: UInt32,
        targetFormat: TextureFormat,
        emissiveFormat: TextureFormat? = nil,
        blendMode: BlendMode = .alpha,
        primitiveTopology: PrimitiveTopology = .triangleList
    ) throws -> Pipeline {
        let key = PipelineCacheKey(
            vertexShader: vertexShader,
            fragmentShader: fragmentShader,
            vertexStride: vertexStride,
            targetFormat: targetFormat,
            emissiveFormat: emissiveFormat,
            blendMode: blendMode,
            primitiveTopology: primitiveTopology
        )
        
        if let existing = cache[key] {
            return existing
        }
        
        // standard 'Vertex' layout (offsets account for SIMD4 alignment)
        let vertexLayout = VertexBufferLayout(stride: vertexStride)
        let vertexAttributes = VertexLayout.attributes
        
        let pipeline = try Pipeline(
            device: device,
            vertexShader: vertexShader,
            fragmentShader: fragmentShader,
            vertexLayout: vertexLayout,
            vertexAttributes: vertexAttributes,
            targetFormat: targetFormat,
            emissiveFormat: emissiveFormat,
            blendMode: blendMode,
            primitiveTopology: primitiveTopology
        )
        
        cache[key] = pipeline
        return pipeline
    }
    
    /// clears the cache, releasing all pipelines
    public func clear() {
        cache.removeAll()
    }
}