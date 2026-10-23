import Foundation

/// an immutable angle stored in radians
public struct Angle: Equatable, Hashable, Sendable, Comparable {
    /// the angle in radians
    public let radians: Float

    /// creates an angle from radians
    public init(radians: Float) { self.radians = radians }

    /// creates an angle from degrees
    public init(degrees: Float) { self.radians = degrees * .pi / 180 }

    /// the angle in degrees
    public var degrees: Float { radians * 180 / .pi }

    /// the equivalent angle in the range `(-pi, pi]`
    public var normalized: Angle {
        let twoPi = 2 * Float.pi
        var value = radians.truncatingRemainder(dividingBy: twoPi)
        if value <= -Float.pi { value += twoPi } else if value > Float.pi { value -= twoPi }
        return Angle(radians: value)
    }

    /// a unit vector pointing in this angle's direction
    public var vector: Vector2D { Vector2D(x: cos(radians), y: sin(radians)) }

    // MARK: - Constants
    public static let zero = Angle(radians: 0)
    /// a right angle (90 degrees)
    public static let right = Angle(degrees: 90)
    /// a half turn (180 degrees)
    public static let straight = Angle(degrees: 180)
    /// a full turn (360 degrees)
    public static let full = Angle(degrees: 360)
    /// a quarter turn (90 degrees)
    public static let quarterTurn = right
    /// a half turn (180 degrees)
    public static let halfTurn = straight

    // MARK: - Comparable
    public static func < (lhs: Angle, rhs: Angle) -> Bool { lhs.radians < rhs.radians }

    // MARK: - Arithmetic
    public static func + (lhs: Angle, rhs: Angle) -> Angle { Angle(radians: lhs.radians + rhs.radians) }
    public static func - (lhs: Angle, rhs: Angle) -> Angle { Angle(radians: lhs.radians - rhs.radians) }
    public static func * (lhs: Angle, rhs: Float) -> Angle { Angle(radians: lhs.radians * rhs) }
    public static func / (lhs: Angle, rhs: Float) -> Angle { Angle(radians: lhs.radians / rhs) }
}
