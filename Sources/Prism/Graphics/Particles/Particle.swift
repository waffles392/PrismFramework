import Math

/// the vertex layout a 'ParticleSystem' emits
public struct ParticleVertex {
    /// position in world space
    public var position: Vector2D
    /// texture coordinate in the particle sprite
    public var uv: Vector2D
    /// premultiplied by the fade factor the system computes
    public var color: SIMD4<Float>

    public init(position: Vector2D, uv: Vector2D, color: SIMD4<Float>) {
        self.position = position
        self.uv = uv
        self.color = color
    }
}

/// one particle, simulated in CPU memory
public struct Particle {
    public var position: Vector2D
    public var velocity: Vector2D
    /// HDR colour - values above 1 glow, e.g. SIMD4(0.0, 3.0, 6.0, 1.0)
    public var color: SIMD4<Float>
    public var size: Float
    /// seconds lived so far; the particle dies at 'maxLife'
    public var life: Float
    public var maxLife: Float
}
