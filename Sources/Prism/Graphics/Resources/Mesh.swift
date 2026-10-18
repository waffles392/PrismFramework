import CSDL3
import Foundation

/// a renderable list of vertices using a shader-backed surface (material)
///
/// textures are supplied per-mesh (not stored on 'Surface') so that the same
/// material can be shared across many meshes while each carries its own
/// sampled inputs
///
/// pipelines are created lazily, one per colour-target configuration, because
/// the fragment output formats are part of the pipeline state. A mesh can
/// therefore be drawn into both the two-target HDR scene pass and the
/// single-target swapchain
///
/// most meshes use the standard 2D 'Vertex' layout, but a mesh can also wrap
/// arbitrary, pre-packed vertex data (for example 4D points consumed by a
/// custom vertex stage). in that case the caller supplies the vertex stride
/// and attribute descriptions explicitly
public final class Mesh {
    private let device: GPUDevice
    private let sampler: Sampler

    private var vertexBuffer: GPUBuffer
    /// capacity of 'vertexBuffer', in bytes
    private var vertexCapacity: Int
    /// CPU-side vertex bytes, re-uploaded when 'isUploaded' is false
    private var vertexData: Data
    /// the number of bytes between consecutive vertices
    private let vertexStride: Int
    private let vertexAttributes: [VertexAttribute]
    /// the number of vertices in 'vertexData'
    public private(set) var vertexCount: Int
    private let surface: Surface

    private var pipelines: [(
        format: SDL_GPUTextureFormat,
        emissiveFormat: SDL_GPUTextureFormat?,
        pipeline: Pipeline
    )] = []
    private var isUploaded = false

    /// render targets sampled by the fragment shader on this mesh. must match
    /// 'surface.samplerCount' when non-empty
    public var textures: [RenderTarget] {
        didSet {
            precondition(
                textures.isEmpty || textures.count == surface.samplerCount,
                "Mesh.textures count must match the surface's samplerCount (\(surface.samplerCount))"
            )
        }
    }

    /// creates a mesh from raw shader bytecode using the standard 2D 'Vertex'
    /// layout
    public convenience init(
        device: GPUDevice,
        sampler: Sampler,
        vertices: [Vertex],
        vertexShaderCode: Data,
        fragmentShaderCode: Data,
        textures: [RenderTarget] = []
    ) throws {
        try self.init(
            device: device,
            sampler: sampler,
            vertices: vertices,
            surface: Surface(
                vertexShader: vertexShaderCode,
                fragmentShader: fragmentShaderCode
            ),
            textures: textures
        )
    }

    /// creates a mesh from vertices using the standard 2D 'Vertex' layout
    public convenience init(
        device: GPUDevice,
        sampler: Sampler,
        vertices: [Vertex],
        surface: Surface,
        textures: [RenderTarget] = []
    ) throws {
        precondition(!vertices.isEmpty, "A mesh must contain at least one vertex")

        let data = vertices.withUnsafeBytes { raw -> Data in
            guard let base = raw.baseAddress else { return Data() }
            return Data(bytes: base, count: raw.count)
        }

        try self.init(
            device: device,
            sampler: sampler,
            vertexData: data,
            vertexStride: MemoryLayout<Vertex>.stride,
            vertexAttributes: VertexLayout.attributes,
            surface: surface,
            textures: textures
        )
    }

    /// creates a mesh from caller-packed vertex data with a custom layout
    ///
    /// - Parameters:
    ///   - vertexData: the raw vertex bytes, laid out according to
    ///     'vertexAttributes' and 'vertexStride'
    ///   - vertexStride: the number of bytes between consecutive vertices
    ///   - vertexAttributes: the per-attribute descriptions used to build the
    ///     input layout (locations must match the vertex shader)
    public init(
        device: GPUDevice,
        sampler: Sampler,
        vertexData: Data,
        vertexStride: Int,
        vertexAttributes: [VertexAttribute],
        surface: Surface,
        textures: [RenderTarget] = []
    ) throws {
        precondition(!vertexData.isEmpty, "A mesh must contain at least one vertex")
        precondition(vertexStride > 0, "A mesh vertex stride must be positive")
        precondition(
            vertexData.count % vertexStride == 0,
            "Vertex data size (\(vertexData.count)) must be a multiple of the vertex stride (\(vertexStride))"
        )
        precondition(
            textures.isEmpty || textures.count == surface.samplerCount,
            "Mesh textures count must match surface.samplerCount (\(surface.samplerCount))"
        )

        self.device = device
        self.sampler = sampler
        self.vertexData = vertexData
        self.vertexStride = vertexStride
        self.vertexAttributes = vertexAttributes
        self.vertexCount = vertexData.count / vertexStride
        self.surface = surface
        self.textures = textures
        self.vertexCapacity = vertexData.count
        self.vertexBuffer = try GPUDevice.makeVertexBuffer(
            device: device,
            byteCount: vertexData.count
        )
    }

    /// uploads the CPU-side geometry to the GPU. safe to call every frame; the
    /// upload only happens once per geometry change
    public func prepare(commandBuffer: OpaquePointer) throws {
        guard !isUploaded, !vertexData.isEmpty else { return }

        let byteCount = vertexData.count
        let transferBuffer = try GPUTransferBuffer(
            device: device,
            size: UInt32(byteCount)
        )

        try vertexData.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            try transferBuffer.write(from: base, byteCount: byteCount)
        }

        try transferBuffer.upload(
            to: vertexBuffer,
            size: UInt32(byteCount),
            commandBuffer: commandBuffer
        )

        isUploaded = true
    }

    /// replaces the CPU-side geometry while reusing the existing GPU buffer
    /// when it is large enough. uses the standard 2D 'Vertex' layout
    public func update(vertices: [Vertex]) throws {
        precondition(!vertices.isEmpty, "A mesh update must contain at least one vertex")

        let data = vertices.withUnsafeBytes { raw -> Data in
            guard let base = raw.baseAddress else { return Data() }
            return Data(bytes: base, count: raw.count)
        }

        try replaceVertexData(data)
    }

    /// replaces the CPU-side geometry with caller-packed bytes. the data size
    /// must be a multiple of this mesh's vertex stride
    public func update(vertexData: Data) throws {
        precondition(!vertexData.isEmpty, "A mesh update must contain at least one vertex")
        precondition(
            vertexData.count % vertexStride == 0,
            "Vertex data size (\(vertexData.count)) must be a multiple of the vertex stride (\(vertexStride))"
        )

        try replaceVertexData(vertexData)
    }

    private func replaceVertexData(_ data: Data) throws {
        if data.count > vertexCapacity {
            vertexBuffer = try GPUDevice.makeVertexBuffer(
                device: device,
                byteCount: data.count
            )
            vertexCapacity = data.count
        }

        self.vertexData = data
        vertexCount = data.count / vertexStride
        isUploaded = false
    }

    /// replaces the vertex-stage uniform block pushed when this mesh draws
    ///
    /// the byte count must match the one the 'surface' was created with
    public func setVertexUniforms(_ data: Data) {
        surface.vertexUniforms = data
    }

    /// binds this mesh's pipeline, geometry, uniforms, and textures, then
    /// draws 'instanceCount' instances
    ///
    /// - Parameters:
    ///   - instanceCount: the number of instances to draw (defaults to one)
    ///   - vertexCount: the number of vertices to draw. defaults to the whole
    ///     mesh; pass a smaller value to draw a prefix (e.g. an LOD range)
    ///   - firstVertex: the first vertex to draw
    public func draw(
        in encoder: RenderEncoder,
        instanceCount: Int = 1,
        vertexCount: Int? = nil,
        firstVertex: Int = 0
    ) {
        let count = vertexCount ?? self.vertexCount
        guard count > 0, instanceCount > 0 else { return }

        let format = encoder.targetFormat
        let emissiveFormat = encoder.emissiveTargetFormat

        let pipeline: Pipeline
        if let cached = pipelines.first(where: {
            $0.format == format && $0.emissiveFormat == emissiveFormat
        }) {
            pipeline = cached.pipeline
        } else if let created = try? makePipeline(
            targetFormat: format,
            emissiveFormat: emissiveFormat
        ) {
            pipelines.append((format, emissiveFormat, created))
            pipeline = created
        } else {
            return
        }

        encoder.bindPipeline(pipeline)
        encoder.bindVertexBuffer(vertexBuffer)

        if !surface.vertexUniforms.isEmpty {
            surface.vertexUniforms.withUnsafeBytes { bytes in
                guard let base = bytes.baseAddress else { return }
                encoder.pushVertexUniforms(bytes: base, size: UInt32(bytes.count))
            }
        }

        if !surface.fragmentUniforms.isEmpty {
            surface.fragmentUniforms.withUnsafeBytes { bytes in
                guard let base = bytes.baseAddress else { return }
                encoder.pushFragmentUniforms(bytes: base, size: UInt32(bytes.count))
            }
        }

        if !textures.isEmpty {
            encoder.bindFragmentSamplers(
                textures.map(\.texture),
                sampler: sampler
            )
        }

        encoder.drawPrimitives(
            vertexCount: count,
            instanceCount: instanceCount,
            firstVertex: firstVertex
        )
    }

    private func makePipeline(
        targetFormat: SDL_GPUTextureFormat,
        emissiveFormat: SDL_GPUTextureFormat?
    ) throws -> Pipeline {
        let vertexShader = try Shader(
            device: device,
            code: surface.vertexShader,
            stage: SDL_GPU_SHADERSTAGE_VERTEX,
            entrypoint: "main",
            uniformBufferCount: surface.vertexUniforms.isEmpty ? 0 : 1
        )

        let fragmentShader = try Shader(
            device: device,
            code: surface.fragmentShader,
            stage: SDL_GPU_SHADERSTAGE_FRAGMENT,
            entrypoint: "main",
            samplerCount: UInt32(surface.samplerCount),
            uniformBufferCount: surface.fragmentUniforms.isEmpty ? 0 : 1
        )

        return try Pipeline(
            device: device,
            vertexShader: vertexShader,
            fragmentShader: fragmentShader,
            vertexLayout: VertexBufferLayout(stride: UInt32(vertexStride)),
            vertexAttributes: vertexAttributes,
            targetFormatRaw: targetFormat,
            emissiveFormatRaw: emissiveFormat,
            blendMode: surface.blendMode,
            primitiveTopology: surface.primitiveTopology
        )
    }
}

extension GPUDevice {
    /// creates a vertex buffer sized for 'byteCount' bytes
    internal static func makeVertexBuffer(
        device: GPUDevice,
        byteCount: Int
    ) throws -> GPUBuffer {
        precondition(byteCount > 0, "Vertex buffer must contain at least one vertex")

        guard byteCount <= Int(UInt32.max) else {
            throw GPUError.resourceCreationFailed("Vertex buffer is too large")
        }

        return try GPUBuffer(
            device: device,
            size: UInt32(byteCount),
            usage: SDL_GPU_BUFFERUSAGE_VERTEX
        )
    }
}
