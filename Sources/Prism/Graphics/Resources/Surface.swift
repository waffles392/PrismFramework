import Foundation

/// shader-backed material state for a mesh
///
/// a 'Surface' describes **how** geometry is shaded: which shaders run, what
/// uniform data they receive, the blend equation, and the primitive topology
/// it is intentionally **not** a container for textures or render targets -
/// those change per draw call and are bound at draw time via
/// 'Mesh.textures'
///
/// shader code must be compiled to SPIR-V for SDL GPU. uniform blocks are
/// pushed at slot zero and must follow std140 layout rules
public final class Surface {
    /// the vertex shader's SPIR-V bytecode
    public let vertexShader: Data

    /// the fragment shader's SPIR-V bytecode
    public let fragmentShader: Data

    /// vertex-stage uniform data (std140, slot 0). the byte count cannot
    /// change after creation
    public var vertexUniforms: Data {
        didSet {
            precondition(
                vertexUniforms.count == vertexUniformByteCount,
                "Surface vertex uniform block size cannot change after creation"
            )
        }
    }

    /// fragment-stage uniform data (std140, slot 0). the byte count cannot
    /// change after creation
    public var fragmentUniforms: Data {
        didSet {
            precondition(
                fragmentUniforms.count == fragmentUniformByteCount,
                "Surface fragment uniform block size cannot change after creation"
            )
        }
    }

    /// number of texture samplers the fragment shader declares. must match the
    /// number of render targets supplied through 'Mesh.textures'
    public let samplerCount: Int

    /// blend operation used while drawing this surface
    public let blendMode: BlendMode

    /// primitive assembly topology used by this surface's pipeline
    public let primitiveTopology: PrimitiveTopology

    private let vertexUniformByteCount: Int
    private let fragmentUniformByteCount: Int

    public init(
        vertexShader: Data,
        fragmentShader: Data,
        vertexUniforms: Data = Data(),
        fragmentUniforms: Data = Data(),
        samplerCount: Int = 0,
        blendMode: BlendMode = .alpha,
        primitiveTopology: PrimitiveTopology = .triangleList
    ) {
        precondition(!vertexShader.isEmpty, "Surface vertex shader cannot be empty")
        precondition(!fragmentShader.isEmpty, "Surface fragment shader cannot be empty")

        self.vertexShader = vertexShader
        self.fragmentShader = fragmentShader
        self.vertexUniforms = vertexUniforms
        self.fragmentUniforms = fragmentUniforms
        self.vertexUniformByteCount = vertexUniforms.count
        self.fragmentUniformByteCount = fragmentUniforms.count
        self.samplerCount = samplerCount
        self.blendMode = blendMode
        self.primitiveTopology = primitiveTopology
    }
}
