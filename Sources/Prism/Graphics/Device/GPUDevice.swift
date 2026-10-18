import CSDL3
import CVulkan
import Foundation

/// manages the SDL GPU device lifetime and provides resource creation
/// entry points
///
/// the GPU device is the central object for all graphics operations. it owns the
/// underlying 'SDL_GPUDevice' handle and ensures proper cleanup on shutdown
///
/// the device must be created with a valid window handle, which it claims for
/// GPU rendering. all resource creation (buffers, textures, shaders, pipelines)
/// goes through this device
///
/// thread safety: the device is not thread-safe. all operations must be
/// performed on the main thread (or the thread that owns the GPU device)
///
/// 'GPUDevice' is '@unchecked Sendable' because it is not thread-safe: it is
/// only operated from the main thread that owns it
public final class GPUDevice: @unchecked Sendable {
    private var _handle: OpaquePointer?
    private let _window: OpaquePointer
    private let _windowOwner: AnyObject?
    private let _capabilities: GPUCapabilities
    private var _resourceCount: Int = 0
    private var _releaseHandlers: [UInt64: () -> Void] = [:]
    private var _nextResourceToken: UInt64 = 1
    private var _isShutdown = false

    /// when 'true', shader payloads are validated as SPIR-V before GPU shader
    /// creation. the engine sets this from 'PrismEnvironment.forceShaderGuard'
    public var forceShaderGuard = false
    
    /// the underlying SDL GPU device handle, or nil if shut down
    public var handle: OpaquePointer? { _handle }
    
    /// the window this device is bound to
    public var window: OpaquePointer { _window }
    
    /// whether the device is alive and ready for use
    public var isAlive: Bool { _handle != nil && !_isShutdown }
    
    /// the device capabilities and limits
    public var capabilities: GPUCapabilities { _capabilities }
    
    /// the name of the GPU driver in use
    public var driverName: String {
        guard let handle = _handle else { return "unknown" }
        return String(cString: SDL_GetGPUDeviceDriver(handle))
    }
    
    /// creates a new GPU device for the given window
    ///
    /// - Parameters:
    ///   - window: the SDL window to claim for GPU rendering. must not be nil
    ///   - windowOwner: optional object that owns the window, kept alive
    ///     for lifetime tracking
    /// - Throws: 'GPUError' if device creation fails at any stage
    public init(window: OpaquePointer?, windowOwner: AnyObject? = nil) throws {
        guard let window else {
            throw GPUError.invalidWindow
        }
        
        self._window = window
        self._windowOwner = windowOwner
        
        // configure SDL_GPU device
        var vkOptions = SDL_GPUVulkanOptions()
        vkOptions.vulkan_api_version = (1 << 22) | (3 << 12) // Vulkan 1.3

        // 'SV_InstanceID' in a Slang vertex stage compiles to the SPIR-V
        // 'InstanceIndex' and 'BaseInstance' builtins, which require the
        // 'DrawParameters' capability, so instanced shaders only validate when
        // the device enables the matching feature. requesting it is a hard
        // requirement: a device without 'shaderDrawParameters' fails device
        // creation instead of silently misdrawing instances
        //
        // SDL reads the feature struct during device creation, so it has to
        // outlive this call and is therefore allocated rather than a local
        let vulkanFeatures = UnsafeMutablePointer<VkPhysicalDeviceVulkan11Features>.allocate(capacity: 1)
        vulkanFeatures.initialize(to: VkPhysicalDeviceVulkan11Features())
        defer { vulkanFeatures.deallocate() }

        vulkanFeatures.pointee.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_1_FEATURES
        vulkanFeatures.pointee.shaderDrawParameters = VK_TRUE
        vkOptions.feature_list = UnsafeMutableRawPointer(vulkanFeatures)

        let props = SDL_CreateProperties()
        guard props != 0 else {
            throw GPUError.propertyCreationFailed(String(cString: SDL_GetError()))
        }
        
        // ensure properties are destroyed even if initialization fails
        defer { SDL_DestroyProperties(props) }
        
        SDL_SetBooleanProperty(props, SDL_PROP_GPU_DEVICE_CREATE_SHADERS_SPIRV_BOOLEAN, true)
        SDL_SetStringProperty(props, SDL_PROP_GPU_DEVICE_CREATE_NAME_STRING, "vulkan")
        SDL_SetPointerProperty(props, SDL_PROP_GPU_DEVICE_CREATE_VULKAN_OPTIONS_POINTER, &vkOptions)
        
        guard SDL_GPUSupportsProperties(props) else {
            throw GPUError.unsupportedConfiguration(String(cString: SDL_GetError()))
        }
        
        guard let device = SDL_CreateGPUDeviceWithProperties(props) else {
            throw GPUError.deviceCreationFailed(String(cString: SDL_GetError()))
        }
        
        guard SDL_ClaimWindowForGPUDevice(device, window) else {
            let message = String(cString: SDL_GetError())
            SDL_DestroyGPUDevice(device)
            throw GPUError.windowClaimFailed(message)
        }
        
        self._handle = device
        self._capabilities = .standard
        
        // set default frames in flight
        SDL_SetGPUAllowedFramesInFlight(device, UInt32(_capabilities.preferredFramesInFlight))
    }
    
    /// registers a GPU resource and returns a token identifying it
    ///
    /// 'release' is invoked if the device shuts down while the resource is
    /// still alive, guaranteeing that no GPU objects outlive the device. an
    /// owner that releases the resource itself must first call
    /// 'unregisterResource(_:)'; it returns 'true' only if the owner is
    /// responsible for the release
    internal func registerResource(release: @escaping () -> Void) -> UInt64 {
        let token = _nextResourceToken
        _nextResourceToken &+= 1
        _releaseHandlers[token] = release
        _resourceCount += 1
        return token
    }
    
    /// marks a resource as released by its owner
    ///
    /// - Returns: 'true' if the owner is responsible for releasing the
    ///   underlying GPU object, or 'false' if the device already released it
    ///   during shutdown
    internal func unregisterResource(_ token: UInt64) -> Bool {
        guard _releaseHandlers.removeValue(forKey: token) != nil else {
            return false
        }
        _resourceCount = max(0, _resourceCount - 1)
        return true
    }
    
    /// returns the current number of tracked resources
    public var trackedResourceCount: Int { _resourceCount }
    
    /// shuts down the GPU device and releases all resources
    ///
    /// this waits for all in-flight GPU work to complete before destroying
    /// the device. after calling this, the device is no longer usable
    public func shutdown() {
        guard let device = _handle, !_isShutdown else { return }
        
        _isShutdown = true
        
        // wait for all submitted work to complete
        _ = SDL_WaitForGPUIdle(device)
        
        // release every tracked resource before destroying the device. this
        // covers resources whose owning Swift objects are still alive (for
        // example long-lived game meshes) which would otherwise outlive the
        // device and leak
        let handlers = _releaseHandlers
        _releaseHandlers.removeAll()
        _resourceCount = 0
        for release in handlers.values {
            release()
        }
        
        // release window and destroy device
        SDL_ReleaseWindowFromGPUDevice(device, _window)
        SDL_DestroyGPUDevice(device)
        
        _handle = nil
    }
    
    deinit {
        shutdown()
    }
}