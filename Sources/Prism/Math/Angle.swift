import Foundation

/// an immutable angle stored in radians
public struct Angle: Equatable, Hashable, Sendable, Comparable {
    public let radians: Float

    public init(radians: Float) { self.radians = radians }
    public init(degrees: Float) { self.radians = degrees * .pi / 180 }

    public var degrees: Float { radians * 180 / .pi }
    public var normalized: Angle {
        let twoPi = 2 * Float.pi
        var value = radians.truncatingRemainder(dividingBy: twoPi)
        if value <= -Float.pi { value += twoPi }
        if value > Float.pi { value -= twoPi }
        return Angle(radians: value)
    }

    // MARK: - Conversion to Vector2D

    /// unit direction vector for this angle - (cos, sin)
    public var vector: Vector2D {
        Vector2D(cos(radians), sin(radians))
    }

    public static let zero = Angle(radians: 0)
    public static let right = Angle(degrees: 90)
    public static let straight = Angle(degrees: 180)
    public static let full = Angle(degrees: 360)
    public static let quarterTurn = right
    public static let halfTurn = straight
    public static func < (lhs: Angle, rhs: Angle) -> Bool { lhs.radians < rhs.radians }
    public static func + (lhs: Angle, rhs: Angle) -> Angle { Angle(radians: lhs.radians + rhs.radians) }
    public static func - (lhs: Angle, rhs: Angle) -> Angle { Angle(radians: lhs.radians - rhs.radians) }
    public static func * (lhs: Angle, rhs: Float) -> Angle { Angle(radians: lhs.radians * rhs) }
}

public enum Angles {
    public static let zero = Angle.zero
    public static let right = Angle.right
    public static let straight = Angle.straight
    public static let full = Angle.full
    public static func degrees(_ value: Float) -> Angle { Angle(degrees: value) }
    public static func radians(_ value: Float) -> Angle { Angle(radians: value) } // named 'value' to avoid shadowing the 'radians' factory above
}

// MARK: - Vector2D Extension

extension Vector2D {
    /// unit direction vector for an angle
    public init(angle: Angle) {
        self.init(cos(angle.radians), sin(angle.radians))
    }
}