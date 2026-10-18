import Foundation

// MARK: - Collision Shapes

/// a 2D circle collision shape
public struct CollisionCircle: Equatable, Sendable {
    public var center: Vector2D
    public var radius: Float
    
    public init(center: Vector2D, radius: Float) {
        self.center = center
        self.radius = radius
    }
    
    public func contains(_ point: Vector2D) -> Bool {
        center.distance(to: point) <= radius
    }
}

/// a 2D axis-aligned bounding box
public struct CollisionAABB: Equatable, Sendable {
    public var min: Vector2D
    public var max: Vector2D
    
    public init(min: Vector2D, max: Vector2D) {
        self.min = min
        self.max = max
    }
    
    public init(center: Vector2D, halfExtents: Vector2D) {
        self.min = center - halfExtents
        self.max = center + halfExtents
    }
    
    public var center: Vector2D { (min + max) * 0.5 }
    public var halfExtents: Vector2D { (max - min) * 0.5 }
    public var size: Vector2D { max - min }
    
    public func contains(_ point: Vector2D) -> Bool {
        point.x >= min.x && point.x <= max.x && point.y >= min.y && point.y <= max.y
    }
}

/// a 2D convex polygon collision shape
public struct CollisionPolygon: Equatable, Sendable {
    public var vertices: [Vector2D]
    public var center: Vector2D
    
    public init(vertices: [Vector2D]) {
        self.vertices = vertices
        // compute center as average of vertices
        var sum = Vector2D.zero
        for v in vertices { sum += v }
        self.center = vertices.isEmpty ? .zero : sum / Float(vertices.count)
    }
    
    public init(center: Vector2D, vertices: [Vector2D]) {
        self.center = center
        self.vertices = vertices
    }
    
    /// get world-space vertices
    public func worldVertices(at position: Vector2D, rotation: Angle = .zero, scale: Float = 1.0) -> [Vector2D] {
        vertices.map { position + ($0 * scale).rotated(by: rotation) }
    }
}

// MARK: - Collision Result

/// result of a collision query
public struct CollisionResult: Equatable, Sendable {
    public var collided: Bool
    public var penetration: Float
    public var normal: Vector2D  // Points from A to B (push A along this to separate)
    public var contactPoint: Vector2D
    
    public static let noCollision = CollisionResult(
        collided: false,
        penetration: 0,
        normal: .zero,
        contactPoint: .zero
    )
}

/// result of a boundary collision
public struct BoundaryCollisionResult: Equatable, Sendable {
    public var collided: Bool
    public var normal: Vector2D
    public var penetration: Float
    public var contactPoint: Vector2D
    public var boundarySide: BoundarySide
    
    public static let noCollision = BoundaryCollisionResult(
        collided: false,
        normal: .zero,
        penetration: 0,
        contactPoint: .zero,
        boundarySide: .none
    )
}

/// which side of the boundary was hit
public enum BoundarySide: Equatable, Sendable {
    case left, right, bottom, top, none
}

// MARK: - Collision Detection

public enum Collision {
    
    // MARK: - Circle vs Circle
    
    /// check collision between two circles
    public static func circleCircle(_ a: CollisionCircle, _ b: CollisionCircle) -> CollisionResult {
        let delta = b.center - a.center
        let distanceSquared = delta.lengthSquared
        let radiusSum = a.radius + b.radius
        let radiusSumSquared = radiusSum * radiusSum
        
        if distanceSquared >= radiusSumSquared {
            return .noCollision
        }
        
        let distance = distanceSquared.squareRoot()
        let penetration = radiusSum - distance
        
        // normal points from A to B
        let normal = distance > Float.ulpOfOne ? delta / distance : Vector2D(1, 0)
        let contactPoint = a.center + normal * a.radius
        
        return CollisionResult(
            collided: true,
            penetration: penetration,
            normal: normal,
            contactPoint: contactPoint
        )
    }
    
    // MARK: - Circle vs AABB
    
    /// check collision between circle and AABB
    public static func circleAABB(_ circle: CollisionCircle, _ aabb: CollisionAABB) -> CollisionResult {
        // find closest point on AABB to circle center
        let closestX = max(aabb.min.x, min(circle.center.x, aabb.max.x))
        let closestY = max(aabb.min.y, min(circle.center.y, aabb.max.y))
        let closestPoint = Vector2D(closestX, closestY)
        
        let delta = circle.center - closestPoint
        let distanceSquared = delta.lengthSquared
        
        if distanceSquared >= circle.radius * circle.radius {
            return .noCollision
        }
        
        let distance = distanceSquared.squareRoot()
        let penetration = circle.radius - distance
        
        // normal points from AABB to circle
        let normal = distance > Float.ulpOfOne ? delta.normalized : Vector2D(1, 0)
        let contactPoint = circle.center - normal * circle.radius
        
        return CollisionResult(
            collided: true,
            penetration: penetration,
            normal: normal,
            contactPoint: contactPoint
        )
    }
    
    // MARK: - Circle vs Boundary (circular boundary)
    
    /// check collision between circle and circular boundary
    /// returns collision if circle is OUTSIDE the boundary
    public static func circleBoundary(_ circle: CollisionCircle, boundaryCenter: Vector2D, boundaryRadius: Float) -> BoundaryCollisionResult {
        let delta = circle.center - boundaryCenter
        let distance = delta.length
        let maxDistance = boundaryRadius - circle.radius
        
        if distance <= maxDistance {
            return .noCollision
        }
        
        let penetration = distance - maxDistance
        let normal = distance > Float.ulpOfOne ? delta.normalized : Vector2D(1, 0)
        let contactPoint = boundaryCenter + normal * boundaryRadius
        
        // determine boundary side
        let side: BoundarySide
        if abs(delta.x) > abs(delta.y) {
            side = delta.x > 0 ? .right : .left
        } else {
            side = delta.y > 0 ? .top : .bottom
        }
        
        return BoundaryCollisionResult(
            collided: true,
            normal: -normal, // Points inward (pushes circle back inside)
            penetration: penetration,
            contactPoint: contactPoint,
            boundarySide: side
        )
    }
    
    // MARK: - AABB vs Boundary (rectangular boundary)
    
    /// check collision between AABB and rectangular boundary
    public static func aabbBoundary(_ aabb: CollisionAABB, boundaryMin: Vector2D, boundaryMax: Vector2D) -> BoundaryCollisionResult {
        var maxPenetration: Float = 0
        var collisionNormal = Vector2D.zero
        var collisionPoint = Vector2D.zero
        var hitSide: BoundarySide = .none
        var collided = false
        
        // check left
        if aabb.min.x < boundaryMin.x {
            let penetration = boundaryMin.x - aabb.min.x
            if penetration > maxPenetration {
                maxPenetration = penetration
                collisionNormal = Vector2D(1, 0)
                collisionPoint = Vector2D(boundaryMin.x, aabb.center.y)
                hitSide = .left
                collided = true
            }
        }
        
        // check right
        if aabb.max.x > boundaryMax.x {
            let penetration = aabb.max.x - boundaryMax.x
            if penetration > maxPenetration {
                maxPenetration = penetration
                collisionNormal = Vector2D(-1, 0)
                collisionPoint = Vector2D(boundaryMax.x, aabb.center.y)
                hitSide = .right
                collided = true
            }
        }
        
        // check bottom
        if aabb.min.y < boundaryMin.y {
            let penetration = boundaryMin.y - aabb.min.y
            if penetration > maxPenetration {
                maxPenetration = penetration
                collisionNormal = Vector2D(0, 1)
                collisionPoint = Vector2D(aabb.center.x, boundaryMin.y)
                hitSide = .bottom
                collided = true
            }
        }
        
        // check top
        if aabb.max.y > boundaryMax.y {
            let penetration = aabb.max.y - boundaryMax.y
            if penetration > maxPenetration {
                maxPenetration = penetration
                collisionNormal = Vector2D(0, -1)
                collisionPoint = Vector2D(aabb.center.x, boundaryMax.y)
                hitSide = .top
                collided = true
            }
        }
        
        if !collided {
            return .noCollision
        }
        
        return BoundaryCollisionResult(
            collided: true,
            normal: collisionNormal,
            penetration: maxPenetration,
            contactPoint: collisionPoint,
            boundarySide: hitSide
        )
    }
    
    // MARK: - Circle vs Boundary (rectangular)
    
    /// check collision between circle and rectangular boundary
    public static func circleRectBoundary(_ circle: CollisionCircle, boundaryMin: Vector2D, boundaryMax: Vector2D) -> BoundaryCollisionResult {
        var maxPenetration: Float = 0
        var collisionNormal = Vector2D.zero
        var collisionPoint = Vector2D.zero
        var hitSide: BoundarySide = .none
        var collided = false
        
        // check left
        if circle.center.x - circle.radius < boundaryMin.x {
            let penetration = boundaryMin.x - (circle.center.x - circle.radius)
            if penetration > maxPenetration {
                maxPenetration = penetration
                collisionNormal = Vector2D(1, 0)
                collisionPoint = Vector2D(boundaryMin.x, circle.center.y)
                hitSide = .left
                collided = true
            }
        }
        
        // check right
        if circle.center.x + circle.radius > boundaryMax.x {
            let penetration = (circle.center.x + circle.radius) - boundaryMax.x
            if penetration > maxPenetration {
                maxPenetration = penetration
                collisionNormal = Vector2D(-1, 0)
                collisionPoint = Vector2D(boundaryMax.x, circle.center.y)
                hitSide = .right
                collided = true
            }
        }
        
        // check bottom
        if circle.center.y - circle.radius < boundaryMin.y {
            let penetration = boundaryMin.y - (circle.center.y - circle.radius)
            if penetration > maxPenetration {
                maxPenetration = penetration
                collisionNormal = Vector2D(0, 1)
                collisionPoint = Vector2D(circle.center.x, boundaryMin.y)
                hitSide = .bottom
                collided = true
            }
        }
        
        // check top
        if circle.center.y + circle.radius > boundaryMax.y {
            let penetration = (circle.center.y + circle.radius) - boundaryMax.y
            if penetration > maxPenetration {
                maxPenetration = penetration
                collisionNormal = Vector2D(0, -1)
                collisionPoint = Vector2D(circle.center.x, boundaryMax.y)
                hitSide = .top
                collided = true
            }
        }
        
        if !collided {
            return .noCollision
        }
        
        return BoundaryCollisionResult(
            collided: true,
            normal: collisionNormal,
            penetration: maxPenetration,
            contactPoint: collisionPoint,
            boundarySide: hitSide
        )
    }
}

// MARK: - Collision Response

public enum CollisionResponse {
    
    /// reflect a velocity vector off a surface normal
    /// - Parameters:
    ///   - velocity: the incoming velocity
    ///   - normal: the surface normal (pointing outward from surface)
    ///   - restitution: bounciness (0 = no bounce, 1 = perfect bounce)
    /// - Returns: the reflected velocity
    public static func reflect(_ velocity: Vector2D, normal: Vector2D, restitution: Float = 1.0) -> Vector2D {
        let dot = velocity.dot(normal)
        if dot >= 0 { return velocity } // Moving away from surface
        return velocity - normal * dot * (1 + restitution)
    }
    
    /// resolve position overlap by pushing out along normal
    public static func resolvePosition(_ position: inout Vector2D, penetration: Float, normal: Vector2D) {
        position += normal * penetration
    }
    
    /// resolve position and velocity for a boundary collision
    /// - Parameters:
    ///   - position: current position (will be corrected)
    ///   - velocity: current velocity (will be reflected)
    ///   - result: boundary collision result
    ///   - restitution: bounciness factor
    public static func resolveBoundary(
        position: inout Vector2D,
        velocity: inout Vector2D,
        result: BoundaryCollisionResult,
        restitution: Float
    ) {
        if result.collided {
            // push position back inside
            position += result.normal * result.penetration
            // reflect velocity
            velocity = reflect(velocity, normal: -result.normal, restitution: restitution)
        }
    }
    
    /// resolve collision between two circles
    public static func resolveCircleCircle(
        positionA: inout Vector2D,
        velocityA: inout Vector2D,
        massA: Float,
        positionB: inout Vector2D,
        velocityB: inout Vector2D,
        massB: Float,
        result: CollisionResult,
        restitution: Float = 1.0
    ) {
        guard result.collided else { return }
        
        let totalMass = massA + massB
        let massRatioA = massB / totalMass
        let massRatioB = massA / totalMass
        
        // position correction
        positionA += result.normal * result.penetration * massRatioA
        positionB -= result.normal * result.penetration * massRatioB
        
        // velocity resolution
        let relativeVelocity = velocityA - velocityB
        let normalVelocity = relativeVelocity.dot(result.normal)
        
        if normalVelocity < 0 {
            let impulse = -(1 + restitution) * normalVelocity / (1/massA + 1/massB)
            let impulseVector = result.normal * impulse
            velocityA += impulseVector / massA
            velocityB -= impulseVector / massB
        }
    }
}

// MARK: - Boundary Configuration

/// configuration for boundary collision behavior
public struct BoundaryConfig: Equatable, Sendable {
    public var shape: BoundaryShape
    public var restitution: Float  // Bounciness
    public var friction: Float     // Tangential damping
    
    public init(shape: BoundaryShape, restitution: Float = 0.8, friction: Float = 0.0) {
        self.shape = shape
        self.restitution = restitution
        self.friction = friction
    }
}

/// shape of the boundary
public enum BoundaryShape: Equatable, Sendable {
    case circle(radius: Float, center: Vector2D = .zero)
    case rectangle(min: Vector2D, max: Vector2D)
    
    public static func makeCircle(radius: Float) -> BoundaryShape { .circle(radius: radius) }
    public static func makeRectangle(size: Vector2D, center: Vector2D = .zero) -> BoundaryShape {
        let half = size * 0.5
        return .rectangle(min: center - half, max: center + half)
    }
}

/// boundary collision system - handles collision with world bounds
public struct BoundaryCollision {
    public let config: BoundaryConfig
    
    public init(config: BoundaryConfig) {
        self.config = config
    }
    
    /// check and resolve collision for a circle-shaped entity
    public func checkAndResolve(
        position: inout Vector2D,
        velocity: inout Vector2D,
        radius: Float
    ) -> BoundaryCollisionResult {
        let circle = CollisionCircle(center: position, radius: radius)
        var result: BoundaryCollisionResult
        
        switch config.shape {
        case .circle(let radius, let center):
            result = Collision.circleBoundary(circle, boundaryCenter: center, boundaryRadius: radius)
        case .rectangle(let min, let max):
            result = Collision.circleRectBoundary(circle, boundaryMin: min, boundaryMax: max)
        }
        
        if result.collided {
            CollisionResponse.resolveBoundary(
                position: &position,
                velocity: &velocity,
                result: result,
                restitution: config.restitution
            )
            
            // apply tangential friction
            if config.friction > 0 {
                let tangent = Vector2D(-result.normal.y, result.normal.x)
                let tangentVel = velocity.dot(tangent)
                velocity -= tangent * tangentVel * config.friction
            }
        }
        
        return result
    }
    
    /// check collision without resolving (query only)
    public func check(
        position: Vector2D,
        radius: Float
    ) -> BoundaryCollisionResult {
        let circle = CollisionCircle(center: position, radius: radius)
        
        switch config.shape {
        case .circle(let radius, let center):
            return Collision.circleBoundary(circle, boundaryCenter: center, boundaryRadius: radius)
        case .rectangle(let min, let max):
            return Collision.circleRectBoundary(circle, boundaryMin: min, boundaryMax: max)
        }
    }
}