import Math
import Foundation

/// a burst emitter for short-lived 2D particles
///
/// burst-only for now: there is no continuous emission mode. the system only
/// simulates positions, so nothing here touches the GPU until 'buildVertices()'
@MainActor
public final class ParticleSystem {
    private var particles: [Particle] = []
    
    public init() {}

    // burst spawn
    public func emitBurst(
        at position: Vector2D,
        count: Int,
        color: SIMD4<Float>, // pass super-bright colours, e.g. SIMD4(0, 4, 8, 1)
        speedRange: ClosedRange<Float> = 0.2...0.8,
        sizeRange: ClosedRange<Float> = 0.01...0.035,
        lifeRange: ClosedRange<Float> = 0.2...0.6
    ) {
        for _ in 0..<count {
            let angle = Float.random(in: 0..<(2 * .pi))
            let speed = Float.random(in: speedRange)
            let velocity = Vector2D(cos(angle) * speed, sin(angle) * speed)
            
            let particle = Particle(
                position: position,
                velocity: velocity,
                color: color,
                size: Float.random(in: sizeRange),
                life: 0,
                maxLife: Float.random(in: lifeRange)
            )
            particles.append(particle)
        }
    }

    // physics step
    public func update(deltaTime: Float) {
        var i = 0
        while i < particles.count {
            particles[i].life += deltaTime
            
            if particles[i].life >= particles[i].maxLife {
                particles.remove(at: i)
            } else {
                // motion plus a little drag (friction)
                // note: the 0.95 factor is per frame, not per second, so it is
                // frame-rate dependent
                particles[i].position.x += particles[i].velocity.x * deltaTime
                particles[i].position.y += particles[i].velocity.y * deltaTime
                particles[i].velocity.x *= 0.95
                particles[i].velocity.y *= 0.95
                i += 1
            }
        }
    }

    // build this frame's mesh
    public func buildVertices() -> [ParticleVertex] {
        var vertices: [ParticleVertex] = []
        vertices.reserveCapacity(particles.count * 6)

        for p in particles {
            // fade out near the end of life
            let lifeProgress = p.life / p.maxLife
            let alphaFade = 1.0 - lifeProgress
            let currentScale = p.size * alphaFade
            let pColor = SIMD4<Float>(p.color.x, p.color.y, p.color.z, p.color.w * alphaFade)

            let h = currentScale * 0.5
            let pos = p.position

            // the quad's four corners
            let topLeft     = Vector2D(pos.x - h, pos.y + h)
            let topRight    = Vector2D(pos.x + h, pos.y + h)
            let bottomLeft  = Vector2D(pos.x - h, pos.y - h)
            let bottomRight = Vector2D(pos.x + h, pos.y - h)

            // triangle 1
            vertices.append(ParticleVertex(position: topLeft,     uv: Vector2D(0, 0), color: pColor))
            vertices.append(ParticleVertex(position: bottomLeft,  uv: Vector2D(0, 1), color: pColor))
            vertices.append(ParticleVertex(position: topRight,    uv: Vector2D(1, 0), color: pColor))

            // triangle 2
            vertices.append(ParticleVertex(position: topRight,    uv: Vector2D(1, 0), color: pColor))
            vertices.append(ParticleVertex(position: bottomLeft,  uv: Vector2D(0, 1), color: pColor))
            vertices.append(ParticleVertex(position: bottomRight, uv: Vector2D(1, 1), color: pColor))
        }

        return vertices
    }
}