import Foundation

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
