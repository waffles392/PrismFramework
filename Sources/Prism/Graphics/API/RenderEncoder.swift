import CSDL3
import Foundation
import Math

/// encodes draw commands into a render pass
///
/// the render encoder provides a safe, typed API for binding pipelines,
/// buffers, textures, and issuing draw commands within a render pass
public struct RenderEncoder {
    internal let commandBuffer: OpaquePointer
    internal let renderPass: OpaquePointer
    public let width: UInt32
    public let height: UInt32

    /// the color-target format of the pass this encoder writes into
    ///
    /// pipelines must match this format exactly, so draw code (e.g. 'Mesh')
    /// uses it to select the correct pipeline
    public let targetFormat: SDL_GPUTextureFormat

    /// the format of the second (emissive) color target, when the pass writes
    /// one. 'nil' for single-target passes
    public let emissiveTargetFormat: SDL_GPUTextureFormat?

    internal init(
        commandBuffer: OpaquePointer,
        renderPass: OpaquePointer,
        width: UInt32,
        height: UInt32,
        targetFormat: SDL_GPUTextureFormat,
        emissiveTargetFormat: SDL_GPUTextureFormat? = nil
    ) {
        self.commandBuffer = commandBuffer
        self.renderPass = renderPass
        self.width = width
        self.height = height
        self.targetFormat = targetFormat
        self.emissiveTargetFormat = emissiveTargetFormat
        
        // set default viewport
        guard width > 0 && height > 0 else { return }
        var viewport = SDL_GPUViewport()
        viewport.x = 0
        viewport.y = 0
        viewport.w = Float(width)
        viewport.h = Float(height)
        viewport.min_depth = 0
        viewport.max_depth = 1
        SDL_SetGPUViewport(renderPass, &viewport)
    }
    
    /// sets the viewport for the render pass
    public func setViewport(x: Float, y: Float, width: Float, height: Float, minDepth: Float = 0, maxDepth: Float = 1) {
        var viewport = SDL_GPUViewport()
        viewport.x = x
        viewport.y = y
        viewport.w = width
        viewport.h = height
        viewport.min_depth = minDepth
        viewport.max_depth = maxDepth
        SDL_SetGPUViewport(renderPass, &viewport)
    }
    
    /// sets the scissor rectangle for the render pass
    public func setScissor(x: UInt32, y: UInt32, width: UInt32, height: UInt32) {
        var scissor = SDL_Rect()
        scissor.x = Int32(x)
        scissor.y = Int32(y)
        scissor.w = Int32(width)
        scissor.h = Int32(height)
        SDL_SetGPUScissor(renderPass, &scissor)
    }
    
    /// binds a graphics pipeline
    public func bindPipeline(_ pipeline: Pipeline) {
        SDL_BindGPUGraphicsPipeline(renderPass, pipeline.handle)
    }
    
    /// binds a vertex buffer at the given slot
    public func bindVertexBuffer(_ buffer: GPUBuffer, slot: UInt32 = 0, offset: UInt32 = 0) {
        var binding = SDL_GPUBufferBinding()
        binding.buffer = buffer.handle
        binding.offset = offset
        SDL_BindGPUVertexBuffers(renderPass, slot, &binding, 1)
    }
    
    /// binds an index buffer
    public func bindIndexBuffer(_ buffer: GPUBuffer, indexElementSize: SDL_GPUIndexElementSize, offset: UInt32 = 0) {
        var binding = SDL_GPUBufferBinding()
        binding.buffer = buffer.handle
        binding.offset = offset
        SDL_BindGPUIndexBuffer(renderPass, &binding, indexElementSize)
    }
    
    /// pushes vertex uniform data (slot 0)
    public func pushVertexUniforms<T>(_ data: T) {
        withUnsafeBytes(of: data) { bytes in
            SDL_PushGPUVertexUniformData(commandBuffer, 0, bytes.baseAddress, UInt32(bytes.count))
        }
    }
    
    /// pushes fragment uniform data (slot 0)
    public func pushFragmentUniforms<T>(_ data: T) {
        withUnsafeBytes(of: data) { bytes in
            SDL_PushGPUFragmentUniformData(commandBuffer, 0, bytes.baseAddress, UInt32(bytes.count))
        }
    }
    
    /// pushes vertex uniform data from raw bytes
    public func pushVertexUniforms(bytes: UnsafeRawPointer, size: UInt32) {
        SDL_PushGPUVertexUniformData(commandBuffer, 0, bytes, size)
    }
    
    /// pushes fragment uniform data from raw bytes
    public func pushFragmentUniforms(bytes: UnsafeRawPointer, size: UInt32) {
        SDL_PushGPUFragmentUniformData(commandBuffer, 0, bytes, size)
    }
    
    /// binds fragment sampler textures
    public func bindFragmentSamplers(_ textures: [GPUTexture], sampler: Sampler, firstSlot: UInt32 = 0) {
        guard !textures.isEmpty else { return }
        
        let bindings = textures.map { texture -> SDL_GPUTextureSamplerBinding in
            var binding = SDL_GPUTextureSamplerBinding()
            binding.texture = texture.handle
            binding.sampler = sampler.handle
            return binding
        }
        
        bindings.withUnsafeBufferPointer { buffer in
            SDL_BindGPUFragmentSamplers(renderPass, firstSlot, buffer.baseAddress, UInt32(buffer.count))
        }
    }
    
    /// draws primitives (non-indexed)
    public func drawPrimitives(vertexCount: Int, instanceCount: Int = 1, firstVertex: Int = 0, firstInstance: Int = 0) {
        guard vertexCount > 0 else { return }
        SDL_DrawGPUPrimitives(
            renderPass,
            UInt32(vertexCount),
            UInt32(instanceCount),
            UInt32(firstVertex),
            UInt32(firstInstance)
        )
    }
    
    /// draws indexed primitives
    public func drawIndexedPrimitives(indexCount: Int, instanceCount: Int = 1, firstIndex: Int = 0, vertexOffset: Int = 0, firstInstance: Int = 0) {
        guard indexCount > 0 else { return }
        SDL_DrawGPUIndexedPrimitives(
            renderPass,
            UInt32(indexCount),
            UInt32(instanceCount),
            UInt32(firstIndex),
            Int32(vertexOffset),
            UInt32(firstInstance)
        )
    }
    
    /// draws primitives indirectly from a buffer
    public func drawPrimitivesIndirect(_ buffer: GPUBuffer, offset: UInt32 = 0, drawCount: UInt32 = 1) {
        SDL_DrawGPUPrimitivesIndirect(renderPass, buffer.handle, offset, drawCount)
    }
    
    /// draws indexed primitives indirectly from a buffer
    public func drawIndexedPrimitivesIndirect(_ buffer: GPUBuffer, offset: UInt32 = 0, drawCount: UInt32 = 1) {
        SDL_DrawGPUIndexedPrimitivesIndirect(renderPass, buffer.handle, offset, drawCount)
    }
    
    /// ends the render pass
    public func end() {
        SDL_EndGPURenderPass(renderPass)
    }
}