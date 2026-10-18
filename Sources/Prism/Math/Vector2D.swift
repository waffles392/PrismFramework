import Foundation

/// a lightweight two-dimensional vector backed by 'SIMD2<Float>'
public struct Vector2D: Equatable, Hashable, Sendable, AdditiveArithmetic {
    public var x: Float {
        get { storage.x }
        set { storage.x = newValue }
    }

    public var y: Float {
        get { storage.y }
        set { storage.y = newValue }
    }

    /// the underlying SIMD value used by the graphics backend
    public var simdValue: SIMD2<Float> {
        get { storage }
        set { storage = newValue }
    }

    private var storage: SIMD2<Float>

    public init(x: Float, y: Float) {
        self.storage = SIMD2(x, y)
    }

    public init(_ x: Float, _ y: Float) {
        self.init(x: x, y: y)
    }

    public init(_ value: SIMD2<Float>) {
        self.storage = value
    }

    public static let zero = Vector2D(x: 0, y: 0)
    public static let one = Vector2D(x: 1, y: 1)
    public static let unitX = Vector2D(x: 1, y: 0)
    public static let unitY = Vector2D(x: 0, y: 1)

    // SIMD-accelerated scalar operations
    public var lengthSquared: Float { (storage * storage).sum() }
    public var length: Float { lengthSquared.squareRoot() }
    public var magnitude: Float { length }
    public var magnitudeSquared: Float { lengthSquared }
    public var isZero: Bool { storage == .zero }

    public func dot(_ other: Vector2D) -> Float { (storage * other.storage).sum() }
    public func cross(_ other: Vector2D) -> Float { x * other.y - y * other.x }
    public func distance(to other: Vector2D) -> Float { (self - other).length }

    public func normalized(or fallback: Vector2D = .zero) -> Vector2D {
        let magnitude = length
        return magnitude > Float.ulpOfOne ? self / magnitude : fallback
    }

    public var normalized: Vector2D { normalized(or: .zero) }

    public func rotated(by angle: Angle) -> Vector2D {
        let cosine = angle.radians.cosine
        let sine = angle.radians.sine
        return Vector2D(x: x * cosine - y * sine, y: x * sine + y * cosine)
    }

    public var angle: Angle { Angle(radians: Float(Foundation.atan2(Double(y), Double(x)))) }

    // MARK: - Operators

    public static func + (lhs: Vector2D, rhs: Vector2D) -> Vector2D { Vector2D(lhs.storage + rhs.storage) }
    public static func - (lhs: Vector2D, rhs: Vector2D) -> Vector2D { Vector2D(lhs.storage - rhs.storage) }
    public static prefix func - (value: Vector2D) -> Vector2D { Vector2D(-value.storage) }
    public static func * (lhs: Vector2D, rhs: Float) -> Vector2D { Vector2D(lhs.storage * rhs) }
    public static func * (lhs: Float, rhs: Vector2D) -> Vector2D { Vector2D(lhs * rhs.storage) }
    public static func / (lhs: Vector2D, rhs: Float) -> Vector2D { Vector2D(lhs.storage / rhs) }

    public static func += (lhs: inout Vector2D, rhs: Vector2D) {
        lhs.storage += rhs.storage
    }

    public static func -= (lhs: inout Vector2D, rhs: Vector2D) {
        lhs.storage -= rhs.storage
    }

    public static func *= (lhs: inout Vector2D, rhs: Float) {
        lhs.storage *= rhs
    }

    public static func /= (lhs: inout Vector2D, rhs: Float) {
        lhs.storage /= rhs
    }
}

private extension Float {
    var sine: Float { Float(Foundation.sin(Double(self))) }
    var cosine: Float { Float(Foundation.cos(Double(self))) }
}