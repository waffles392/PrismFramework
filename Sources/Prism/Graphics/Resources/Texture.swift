import CSDL3
import Foundation

/// texture format enumeration for 2D rendering
public enum TextureFormat: Sendable {
    case rgba8Unorm
    case rgba16Float
    case rgba32Float
    case r8Unorm
    case depth24Stencil8
    
    internal var nativeValue: SDL_GPUTextureFormat {
        switch self {
        case .rgba8Unorm: return SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM
        case .rgba16Float: return SDL_GPU_TEXTUREFORMAT_R16G16B16A16_FLOAT
        case .rgba32Float: return SDL_GPU_TEXTUREFORMAT_R32G32B32A32_FLOAT
        case .r8Unorm: return SDL_GPU_TEXTUREFORMAT_R8_UNORM
        case .depth24Stencil8: return SDL_GPU_TEXTUREFORMAT_D24_UNORM_S8_UINT
        }
    }
}

/// a GPU texture resource
///
/// textures can be used as render targets, sampled in shaders, or both
/// they are reference-counted through the device's resource tracking
///
/// 'GPUTexture' is '@unchecked Sendable' because it is read-only after init:
/// the C handle is stored once and only read
public final class GPUTexture: @unchecked Sendable {
    internal let handle: OpaquePointer
    public let width: UInt32
    public let height: UInt32
    public let format: TextureFormat
    public let usage: SDL_GPUTextureUsageFlags
    
    private let device: GPUDevice
    private let resourceToken: UInt64
    
    internal init(
        device: GPUDevice,
        width: UInt32,
        height: UInt32,
        format: TextureFormat,
        usage: SDL_GPUTextureUsageFlags
    ) throws {
        self.device = device
        self.width = width
        self.height = height
        self.format = format
        self.usage = usage
        
        guard let deviceHandle = device.handle else {
            throw GPUError.deviceShutdown
        }
        
        var info = SDL_GPUTextureCreateInfo()
        info.type = SDL_GPU_TEXTURETYPE_2D
        info.format = format.nativeValue
        info.width = width
        info.height = height
        info.layer_count_or_depth = 1
        info.num_levels = 1
        info.usage = usage
        
        guard let texture = SDL_CreateGPUTexture(deviceHandle, &info) else {
            throw GPUError.resourceCreationFailed(String(cString: SDL_GetError()))
        }
        
        self.handle = texture
        self.resourceToken = device.registerResource { [weak device] in
            guard let deviceHandle = device?.handle else { return }
            SDL_ReleaseGPUTexture(deviceHandle, texture)
        }
    }
    
    /// creates a texture suitable for use as a color render target and
    /// shader sampling
    public static func renderTarget(
        device: GPUDevice,
        width: UInt32,
        height: UInt32,
        format: TextureFormat = .rgba16Float
    ) throws -> GPUTexture {
        try GPUTexture(
            device: device,
            width: width,
            height: height,
            format: format,
            usage: SDL_GPU_TEXTUREUSAGE_COLOR_TARGET | SDL_GPU_TEXTUREUSAGE_SAMPLER
        )
    }
    
    /// creates a texture for sampling only (e.g., loaded from image data)
    public static func sampler(
        device: GPUDevice,
        width: UInt32,
        height: UInt32,
        format: TextureFormat = .rgba8Unorm
    ) throws -> GPUTexture {
        try GPUTexture(
            device: device,
            width: width,
            height: height,
            format: format,
            usage: SDL_GPU_TEXTUREUSAGE_SAMPLER
        )
    }
    
    deinit {
        guard device.unregisterResource(resourceToken) else { return }
        guard let deviceHandle = device.handle else { return }
        SDL_ReleaseGPUTexture(deviceHandle, handle)
    }
}

/// a render target wrapping an offscreen colour texture
///
/// used for offscreen rendering passes. the color target is a texture that can
/// be sampled in subsequent passes
public final class RenderTarget {
    public let texture: GPUTexture
    public let width: UInt32
    public let height: UInt32
    public let format: TextureFormat
    
    public init(texture: GPUTexture) {
        self.texture = texture
        self.width = texture.width
        self.height = texture.height
        self.format = texture.format
    }
    
    /// creates a new render target with the given dimensions and format
    public static func create(
        device: GPUDevice,
        width: UInt32,
        height: UInt32,
        format: TextureFormat = .rgba16Float
    ) throws -> RenderTarget {
        let texture = try GPUTexture.renderTarget(
            device: device,
            width: width,
            height: height,
            format: format
        )
        return RenderTarget(texture: texture)
    }
}