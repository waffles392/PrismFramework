import CSDL3
import Foundation

/// a GPU sampler for texture filtering and addressing modes
///
/// samplers define how textures are sampled in shaders. they are created through
/// the device and reference-counted for lifetime management
///
/// 'Sampler' is '@unchecked Sendable' because it is read-only after init:
/// the C handle is stored once and only read
public final class Sampler: @unchecked Sendable {
    internal let handle: OpaquePointer
    
    private let device: GPUDevice
    private let resourceToken: UInt64
    
    /// creates a new sampler with the given parameters
    public init(
        device: GPUDevice,
        minFilter: SDL_GPUFilter = SDL_GPU_FILTER_LINEAR,
        magFilter: SDL_GPUFilter = SDL_GPU_FILTER_LINEAR,
        mipmapMode: SDL_GPUSamplerMipmapMode = SDL_GPU_SAMPLERMIPMAPMODE_LINEAR,
        addressModeU: SDL_GPUSamplerAddressMode = SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
        addressModeV: SDL_GPUSamplerAddressMode = SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
        addressModeW: SDL_GPUSamplerAddressMode = SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
        enableAnisotropy: Bool = false,
        maxAnisotropy: Float = 1.0,
        enableCompare: Bool = false,
        compareOp: SDL_GPUCompareOp = SDL_GPU_COMPAREOP_NEVER,
        minLod: Float = 0.0,
        maxLod: Float = Float.greatestFiniteMagnitude,
        mipLodBias: Float = 0.0
    ) throws {
        self.device = device
        
        guard let deviceHandle = device.handle else {
            throw GPUError.deviceShutdown
        }
        
        var info = SDL_GPUSamplerCreateInfo()
        info.min_filter = minFilter
        info.mag_filter = magFilter
        info.mipmap_mode = mipmapMode
        info.address_mode_u = addressModeU
        info.address_mode_v = addressModeV
        info.address_mode_w = addressModeW
        info.enable_anisotropy = enableAnisotropy
        info.max_anisotropy = maxAnisotropy
        info.enable_compare = enableCompare
        info.compare_op = compareOp
        info.min_lod = minLod
        info.max_lod = maxLod
        info.mip_lod_bias = mipLodBias
        
        guard let sampler = SDL_CreateGPUSampler(deviceHandle, &info) else {
            throw GPUError.resourceCreationFailed(String(cString: SDL_GetError()))
        }
        
        self.handle = sampler
        self.resourceToken = device.registerResource { [weak device] in
            guard let deviceHandle = device?.handle else { return }
            SDL_ReleaseGPUSampler(deviceHandle, sampler)
        }
    }
    
    /// creates a standard linear filtering sampler with clamp-to-edge addressing
    public static func linear(device: GPUDevice) throws -> Sampler {
        try Sampler(device: device)
    }
    
    /// creates a nearest-neighbor filtering sampler with clamp-to-edge addressing
    public static func nearest(device: GPUDevice) throws -> Sampler {
        try Sampler(
            device: device,
            minFilter: SDL_GPU_FILTER_NEAREST,
            magFilter: SDL_GPU_FILTER_NEAREST,
            mipmapMode: SDL_GPU_SAMPLERMIPMAPMODE_NEAREST
        )
    }
    
    deinit {
        guard device.unregisterResource(resourceToken) else { return }
        guard let deviceHandle = device.handle else { return }
        SDL_ReleaseGPUSampler(deviceHandle, handle)
    }
}