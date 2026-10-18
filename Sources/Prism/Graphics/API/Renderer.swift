import CSDL3
import Foundation

/// main renderer interface for the graphics system
///
/// the Renderer owns the GPU device, frame context, and provides high-level
/// rendering operations. it manages the frame lifecycle and resource creation
@MainActor
public final class Renderer {
    public let device: GPUDevice
    public let frameContext: FrameContext
    public let capabilities: GPUCapabilities
    public let pipelineCache: PipelineCache
    public let uploadArena: UploadArena
    public let diagnostics: Diagnostics

    /// a shared linear-filtering sampler for meshes and full-screen passes
    public let linearSampler: Sampler
    
    private var _isShutdown = false
    private var _isInterrupted = false
    
    /// whether the renderer has been shut down
    public var isShutdown: Bool { _isShutdown }
    
    /// whether the renderer has been interrupted (e.g., app closing)
    public var isInterrupted: Bool { _isInterrupted }
    
    /// the underlying SDL GPU device handle
    public var deviceHandle: OpaquePointer? { device.handle }
    
    /// the window handle
    public var windowHandle: OpaquePointer { device.window }
    
    /// creates a new renderer for the given window
    public init(window: OpaquePointer, windowOwner: AnyObject? = nil) throws {
        self.device = try GPUDevice(window: window, windowOwner: windowOwner)
        self.capabilities = device.capabilities
        self.frameContext = FrameContext(device: device, window: device.window)
        self.pipelineCache = PipelineCache(device: device)
        self.uploadArena = UploadArena(device: device)
        self.diagnostics = Diagnostics()
        self.linearSampler = try Sampler.linear(device: device)
        
        // set default vsync
        try frameContext.setVsync(true)
    }
    
    /// shuts down the renderer and releases all resources
    public func shutdown() {
        guard !_isShutdown else { return }
        _isShutdown = true
        
        // wait for GPU to finish
        try? frameContext.waitForIdle()
        
        // clear pipeline cache
        pipelineCache.clear()
        
        // shutdown device
        device.shutdown()
    }
    
    /// interrupts rendering (e.g., when app is closing)
    public func interrupt() {
        _isInterrupted = true
    }
    
    /// begins a new frame
    ///
    /// returns nil if the renderer is interrupted or a frame is already active
    /// throws if frame acquisition fails
    public func beginFrame() throws -> Frame? {
        guard !_isInterrupted, !_isShutdown else { return nil }
        return try frameContext.beginFrame()
    }
    
    /// ends and presents the current frame
    public func endFrame(_ frame: Frame) {
        frameContext.endFrame(frame)
        diagnostics.frameCompleted()
    }
    
    /// sets vertical sync
    public func setVsync(_ enabled: Bool) {
        try? frameContext.setVsync(enabled)
    }
    
    /// sets the maximum frames in flight
    public func setMaxFramesInFlight(_ frames: Int) {
        try? frameContext.setMaxFramesInFlight(frames)
    }
    
    /// creates a vertex buffer with the given capacity
    public func createVertexBuffer(capacity: Int) throws -> GPUBuffer {
        try GPUBuffer(
            device: device,
            size: UInt32(capacity * MemoryLayout<Vertex>.stride),
            usage: SDL_GPU_BUFFERUSAGE_VERTEX
        )
    }
    
    /// creates an index buffer with the given capacity
    public func createIndexBuffer(capacity: Int) throws -> GPUBuffer {
        try GPUBuffer(
            device: device,
            size: UInt32(capacity * MemoryLayout<UInt32>.stride),
            usage: SDL_GPU_BUFFERUSAGE_INDEX
        )
    }
    
    /// creates a uniform buffer with the given size
    public func createUniformBuffer(size: UInt32) throws -> GPUBuffer {
        try GPUBuffer(
            device: device,
            size: size,
            usage: SDL_GPU_BUFFERUSAGE_VERTEX  // Uniform buffers use vertex usage in SDL3
        )
    }
    
    /// creates a shader module from SPIR-V code
    public func createShader(
        code: Data,
        stage: SDL_GPUShaderStage,
        entrypoint: String = "main",
        samplerCount: UInt32 = 0,
        uniformBufferCount: UInt32 = 0,
        forceGuard: Bool = false
    ) throws -> Shader {
        try Shader(
            device: device,
            code: code,
            stage: stage,
            entrypoint: entrypoint,
            samplerCount: samplerCount,
            uniformBufferCount: uniformBufferCount,
            forceGuard: forceGuard
        )
    }
    
    /// creates a sampler
    public func createSampler(
        minFilter: SDL_GPUFilter = SDL_GPU_FILTER_LINEAR,
        magFilter: SDL_GPUFilter = SDL_GPU_FILTER_LINEAR,
        mipmapMode: SDL_GPUSamplerMipmapMode = SDL_GPU_SAMPLERMIPMAPMODE_LINEAR,
        addressModeU: SDL_GPUSamplerAddressMode = SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
        addressModeV: SDL_GPUSamplerAddressMode = SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
        addressModeW: SDL_GPUSamplerAddressMode = SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE
    ) throws -> Sampler {
        try Sampler(
            device: device,
            minFilter: minFilter,
            magFilter: magFilter,
            mipmapMode: mipmapMode,
            addressModeU: addressModeU,
            addressModeV: addressModeV,
            addressModeW: addressModeW
        )
    }
    
    /// creates a render target texture
    public func createRenderTarget(
        width: UInt32,
        height: UInt32,
        format: TextureFormat = .rgba16Float
    ) throws -> RenderTarget {
        try RenderTarget.create(device: device, width: width, height: height, format: format)
    }
    
    /// creates a graphics pipeline
    public func createPipeline(
        vertexShader: Shader,
        fragmentShader: Shader,
        vertexStride: UInt32,
        targetFormat: TextureFormat,
        emissiveFormat: TextureFormat? = nil,
        blendMode: BlendMode = .alpha,
        primitiveTopology: PrimitiveTopology = .triangleList
    ) throws -> Pipeline {
        try pipelineCache.pipeline(
            vertexShader: vertexShader,
            fragmentShader: fragmentShader,
            vertexStride: vertexStride,
            targetFormat: targetFormat,
            emissiveFormat: emissiveFormat,
            blendMode: blendMode,
            primitiveTopology: primitiveTopology
        )
    }
    
    /// prints a startup banner with engine and GPU info
    public func printStartupBanner(title: String, width: Int32, height: Int32) {
        let sdlVer = SDL_GetVersion()
        let sdlVersion = "\(sdlVer / 1_000_000).\((sdlVer / 1_000) % 1_000).\(sdlVer % 1_000)"
        let platform = String(cString: SDL_GetPlatform())
        let driver = device.driverName
        
        // diagnostics carry a '[prism]' tag; the banner and the live stats line
        // are displays, so they stay unprefixed
        print("app: '\(title)' (dimensions: '\(width)x\(height)', platform: '\(platform)')")
        print("running prism (sdl: \(sdlVersion), driver: \(driver))")
    }
}