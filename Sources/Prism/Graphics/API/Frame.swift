import CSDL3
import Foundation

/// represents a single frame being rendered
///
/// a frame encapsulates the command buffer, swapchain texture, and dimensions
/// it is acquired at the beginning of a frame and submitted at the end
public struct Frame {
    public let commandBuffer: OpaquePointer
    /// the swapchain texture for this frame. may be nil if the window is
    /// minimised / occluded; callers must guard against nil
    public let swapchainTexture: OpaquePointer?
    /// the color format of the swapchain for this frame
    public let targetFormat: SDL_GPUTextureFormat
    
    public let width: UInt32
    public let height: UInt32
    
    internal init(
        device: OpaquePointer,
        window: OpaquePointer
    ) throws {
        guard let commandBuffer = SDL_AcquireGPUCommandBuffer(device) else {
            throw GPUError.commandBufferAcquisitionFailed(String(cString: SDL_GetError()))
        }
        
        self.commandBuffer = commandBuffer
        self.targetFormat = SDL_GetGPUSwapchainTextureFormat(device, window)
        
        var swapchainTexture: OpaquePointer?
        var width: UInt32 = 0
        var height: UInt32 = 0
        
        // wait for and acquire the swapchain texture
        guard SDL_WaitAndAcquireGPUSwapchainTexture(commandBuffer, window, &swapchainTexture, &width, &height) else {
            // clean up the command buffer on failure
            SDL_CancelGPUCommandBuffer(commandBuffer)
            throw GPUError.swapchainAcquisitionFailed(String(cString: SDL_GetError()))
        }
        
        self.swapchainTexture = swapchainTexture
        self.width = width
        self.height = height
    }
    
    /// whether the frame has a valid swapchain texture (window not minimized)
    public var hasSwapchainTexture: Bool { swapchainTexture != nil }
    
    /// begins a render pass targeting the swapchain
    public func beginRenderPass(
        clearColor: Color = Color(0, 0, 0, 1)
    ) throws -> RenderEncoder {
        guard let swapchainTexture else {
            throw GPUError.windowMinimized
        }
        
        let clear = clearColor.linearValue
        var colorTarget = SDL_GPUColorTargetInfo()
        colorTarget.texture = swapchainTexture
        colorTarget.load_op = SDL_GPU_LOADOP_CLEAR
        colorTarget.store_op = SDL_GPU_STOREOP_STORE
        colorTarget.clear_color = SDL_FColor(r: clear.x, g: clear.y, b: clear.z, a: clear.w)
        
        guard let renderPass = SDL_BeginGPURenderPass(commandBuffer, &colorTarget, 1, nil) else {
            throw GPUError.passBeginFailed(String(cString: SDL_GetError()))
        }
        
        return RenderEncoder(
            commandBuffer: commandBuffer,
            renderPass: renderPass,
            width: width,
            height: height,
            targetFormat: targetFormat
        )
    }
    
    /// begins a render pass targeting an offscreen render target
    ///
    /// pass 'emissive' to render into a second colour target as well. the
    /// emissive target is cleared to black and feeds the bloom extractor,
    /// letting geometry glow independently of its visible colour
    public func beginRenderPass(
        to target: RenderTarget,
        emissive: RenderTarget? = nil,
        clearColor: Color = Color(0, 0, 0, 0)
    ) throws -> RenderEncoder {
        let clear = clearColor.linearValue

        var targets: [SDL_GPUColorTargetInfo] = []

        var colorTarget = SDL_GPUColorTargetInfo()
        colorTarget.texture = target.texture.handle
        colorTarget.load_op = SDL_GPU_LOADOP_CLEAR
        colorTarget.store_op = SDL_GPU_STOREOP_STORE
        colorTarget.clear_color = SDL_FColor(r: clear.x, g: clear.y, b: clear.z, a: clear.w)
        targets.append(colorTarget)

        if let emissive {
            var emissiveTarget = SDL_GPUColorTargetInfo()
            emissiveTarget.texture = emissive.texture.handle
            emissiveTarget.load_op = SDL_GPU_LOADOP_CLEAR
            emissiveTarget.store_op = SDL_GPU_STOREOP_STORE
            emissiveTarget.clear_color = SDL_FColor(r: 0, g: 0, b: 0, a: 0)
            targets.append(emissiveTarget)
        }

        guard let renderPass = SDL_BeginGPURenderPass(
            commandBuffer,
            targets.withUnsafeBufferPointer { $0.baseAddress },
            UInt32(targets.count),
            nil
        ) else {
            throw GPUError.passBeginFailed(String(cString: SDL_GetError()))
        }
        
        return RenderEncoder(
            commandBuffer: commandBuffer,
            renderPass: renderPass,
            width: target.width,
            height: target.height,
            targetFormat: target.format.nativeValue,
            emissiveTargetFormat: emissive?.format.nativeValue
        )
    }
    
    /// submits the command buffer to the GPU
    public func submit() throws {
        guard SDL_SubmitGPUCommandBuffer(commandBuffer) else {
            throw GPUError.commandBufferSubmitFailed(String(cString: SDL_GetError()))
        }
    }
    
    /// cancels the command buffer without submitting
    public func cancel() {
        SDL_CancelGPUCommandBuffer(commandBuffer)
    }
}