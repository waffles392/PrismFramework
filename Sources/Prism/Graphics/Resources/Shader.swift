import CSDL3
import Foundation

/// a GPU shader module (vertex, fragment, or compute)
///
/// shaders must be provided as SPIR-V bytecode. the shader is reference-counted
/// through the device's resource tracking and automatically released on deinit
///
/// 'Shader' is '@unchecked Sendable' because it is read-only after init:
/// the C handle is stored once and only read
public final class Shader: @unchecked Sendable {
    internal let handle: OpaquePointer
    public let stage: SDL_GPUShaderStage
    public let entrypoint: String
    public let format: SDL_GPUShaderFormat
    public let samplerCount: UInt32
    public let uniformBufferCount: UInt32
    
    private let device: GPUDevice
    private let resourceToken: UInt64
    
    /// validates a SPIR-V payload: the first word must be the SPIR-V magic number,
    /// the size must be a non-empty multiple of four bytes, and the module
    /// must be at least a five-word header
    public static func validateSPIRV(_ code: Data) {
        precondition(
            code.count >= 20,
            "SPIR-V shader is shorter than the 5-word header"
        )
        precondition(
            code.count % 4 == 0,
            "SPIR-V shader size must be a multiple of 4 bytes"
        )
        let magic = code.withUnsafeBytes { bytes -> UInt32 in
            bytes.load(as: UInt32.self)
        }
        precondition(
            magic == 0x07230203,
            "Shader payload is not valid SPIR-V (bad magic word)"
        )
    }
    
    internal init(
        device: GPUDevice,
        code: Data,
        format: SDL_GPUShaderFormat = SDL_GPU_SHADERFORMAT_SPIRV,
        stage: SDL_GPUShaderStage,
        entrypoint: String = "main",
        samplerCount: UInt32 = 0,
        uniformBufferCount: UInt32 = 0,
        forceGuard: Bool = false
    ) throws {
        self.device = device
        self.stage = stage
        self.entrypoint = entrypoint
        self.format = format
        self.samplerCount = samplerCount
        self.uniformBufferCount = uniformBufferCount
        
        guard let deviceHandle = device.handle else {
            throw GPUError.deviceShutdown
        }
        
        guard !code.isEmpty else {
            throw GPUError.shaderCreationFailed("Shader code is empty")
        }
        
        if forceGuard || device.forceShaderGuard {
            Self.validateSPIRV(code)
        }
        
        var info = SDL_GPUShaderCreateInfo()
        info.code_size = code.count
        info.format = format
        info.stage = stage
        info.num_samplers = samplerCount
        info.num_uniform_buffers = uniformBufferCount
        
        let shaderHandle: OpaquePointer = try entrypoint.withCString { entrypointPointer -> OpaquePointer in
            info.entrypoint = entrypointPointer
            
            return try code.withUnsafeBytes { bytes -> OpaquePointer in
                guard let baseAddress = bytes.baseAddress else {
                    throw GPUError.shaderCreationFailed("Shader code has no base address")
                }
                
                info.code = baseAddress.assumingMemoryBound(to: UInt8.self)
                
                guard let shader = SDL_CreateGPUShader(deviceHandle, &info) else {
                    throw GPUError.shaderCreationFailed(String(cString: SDL_GetError()))
                }
                
                return shader
            }
        }
        
        self.handle = shaderHandle
        self.resourceToken = device.registerResource { [weak device] in
            guard let deviceHandle = device?.handle else { return }
            SDL_ReleaseGPUShader(deviceHandle, shaderHandle)
        }
    }
    
    deinit {
        guard device.unregisterResource(resourceToken) else { return }
        guard let deviceHandle = device.handle else { return }
        SDL_ReleaseGPUShader(deviceHandle, handle)
    }
}