import Foundation

/// a three-dimensional vector backed by 'SIMD3<Float>'
///
/// 'Vector3D' is used for 3D positions, directions, and scaling in
/// world-space (e.g., 3D particle systems, camera look-at targets,
/// quaternion euler angles). all arithmetic operations are SIMD-accelerated
public struct Vector3D: Equatable, Hashable, Sendable, AdditiveArithmetic {

    public var x: Float {
        get { storage.x }
        set { storage.x = newValue }
    }
    public var y: Float {
        get { storage.y }
        set { storage.y = newValue }
    }
    public var z: Float {
        get { storage.z }
        set { storage.z = newValue }
    }

    /// the backing 'SIMD3<Float>', for call sites that work in simd types
    public var simdValue: SIMD3<Float> {
        get { storage }
        set { storage = newValue }
    }

    private var storage: SIMD3<Float>

    // MARK: - Init
    public init(_ x: Float, _ y: Float, _ z: Float) { self.storage = SIMD3(x, y, z) }
    public init(x: Float, y: Float, z: Float) { self.storage = SIMD3(x, y, z) }
    public init(_ value: SIMD3<Float>) { self.storage = value }
    public init(repeating scalar: Float) { self.storage = SIMD3(repeating: scalar) }

    // MARK: - Constants
    public static let zero   = Vector3D(0, 0, 0)
    public static let one    = Vector3D(1, 1, 1)
    public static let unitX  = Vector3D(1, 0, 0)
    public static let unitY  = Vector3D(0, 1, 0)
    public static let unitZ  = Vector3D(0, 0, 1)
    public static let up     = Vector3D(0, 1, 0)
    public static let right  = Vector3D(1, 0, 0)
    public static let forward = Vector3D(0, 0, -1)

    // MARK: - Geometric properties
    public var lengthSquared: Float { (storage * storage).sum() }
    public var length: Float { lengthSquared.squareRoot() }
    public var magnitude: Float { length }
    public var magnitudeSquared: Float { lengthSquared }
    public var isZero: Bool { storage == .zero }

    public func normalized(or fallback: Vector3D = .zero) -> Vector3D {
        let mag = length
        return mag > Float.ulpOfOne ? self / mag : fallback
    }
    public var normalized: Vector3D { normalized(or: .zero) }

    // MARK: - Arithmetic (AdditiveArithmetic)
    // 'zero' (required by AdditiveArithmetic) is the
    // static constant declared above
    public static func + (lhs: Vector3D, rhs: Vector3D) -> Vector3D { Vector3D(lhs.storage + rhs.storage) }
    public static func - (lhs: Vector3D, rhs: Vector3D) -> Vector3D { Vector3D(lhs.storage - rhs.storage) }
    public static func += (lhs: inout Vector3D, rhs: Vector3D) { lhs = lhs + rhs }
    public static func -= (lhs: inout Vector3D, rhs: Vector3D) { lhs = lhs - rhs }
    public static func * (lhs: Vector3D, rhs: Float) -> Vector3D { Vector3D(lhs.storage * rhs) }
    public static func * (lhs: Float, rhs: Vector3D) -> Vector3D { Vector3D(lhs * rhs.storage) }
    public static func / (lhs: Vector3D, rhs: Float) -> Vector3D { Vector3D(lhs.storage / rhs) }
    public static prefix func - (v: Vector3D) -> Vector3D { Vector3D(-v.storage) }

    // MARK: - Vector operations
    public func dot(_ other: Vector3D) -> Float { (storage * other.storage).sum() }
    public func cross(_ other: Vector3D) -> Vector3D { Vector3D(y * other.z - z * other.y, z * other.x - x * other.z, x * other.y - y * other.x) }

    public func distance(to other: Vector3D) -> Float { (self - other).length }
    public func distanceSquared(to other: Vector3D) -> Float { (self - other).lengthSquared }

    // MARK: - Interpolation
    public static func lerp(_ a: Vector3D, _ b: Vector3D, t: Float) -> Vector3D { Vector3D(a.storage + (b.storage - a.storage) * t) }
    public static func slerp(_ a: Vector3D, _ b: Vector3D, t: Float) -> Vector3D {
        let dot = Swift.max(-1, Swift.min(1, a.normalized.dot(b.normalized)))
        let theta = Float(acos(Double(dot))) * t
        let relative = (b - a * dot).normalized
        return a * Float(cos(Double(theta))) + relative * Float(sin(Double(theta)))
    }

    // MARK: - Component-wise helpers
    public func min(_ other: Vector3D) -> Vector3D {
        Vector3D(
            Swift.min(x, other.x),
            Swift.min(y, other.y),
            Swift.min(z, other.z)
        )
    }

    public func max(_ other: Vector3D) -> Vector3D {
        Vector3D(
            Swift.max(x, other.x),
            Swift.max(y, other.y),
            Swift.max(z, other.z)
        )
    }

    public func clamped(min minVec: Vector3D, max maxVec: Vector3D) -> Vector3D {
        Vector3D(
            Swift.max(minVec.x, Swift.min(x, maxVec.x)),
            Swift.max(minVec.y, Swift.min(y, maxVec.y)),
            Swift.max(minVec.z, Swift.min(z, maxVec.z))
        )
    }

    public func abs() -> Vector3D { Vector3D(Swift.abs(x), Swift.abs(y), Swift.abs(z)) }

    // MARK: - Projection
    /// projects 'self' onto 'other'
    public func projected(onto other: Vector3D) -> Vector3D {
        let d = other.lengthSquared
        guard d > Float.ulpOfOne else { return .zero }
        return other * (dot(other) / d)
    }

    /// returns the component of 'self' perpendicular to 'normal'
    public func rejected(from normal: Vector3D) -> Vector3D { self - projected(onto: normal) }

    /// reflects 'self' about 'normal' (normal must be unit length)
    public func reflected(off normal: Vector3D) -> Vector3D { self - normal * (2 * dot(normal)) }
}

// MARK: - CustomStringConvertible
extension Vector3D: CustomStringConvertible {
    public var description: String {
        String(format: "Vector3D(%.4f, %.4f, %.4f)", x, y, z)
    }
}