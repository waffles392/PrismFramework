/// an axis-aligned rectangle: a top-left origin and a size
public struct Rect2D: Equatable, Sendable {
    /// top-left corner
    public var origin: Vector2D
    /// width and height
    public var size: Vector2D
    public init(origin: Vector2D, size: Vector2D) { self.origin = origin; self.size = size }
    public init(x: Float, y: Float, width: Float, height: Float) { self.init(origin: Vector2D(x, y), size: Vector2D(width, height)) }
    /// top-left corner
    public var min: Vector2D { origin }
    /// bottom-right corner
    public var max: Vector2D { origin + size }
    /// midpoint of the rect
    public var center: Vector2D { origin + size * 0.5 }
    /// true when the point lies inside the rect, edges included
    public func contains(_ point: Vector2D) -> Bool { point.x >= min.x && point.y >= min.y && point.x <= max.x && point.y <= max.y }
    /// shrinks the rect by 'amount' on every side
    public func inset(by amount: Float) -> Rect2D { Rect2D(origin: origin + Vector2D(amount, amount), size: size - Vector2D(amount * 2, amount * 2)) }
}

/// a circle: a center and a radius
public struct Circle: Equatable, Sendable {
    public var center: Vector2D
    public var radius: Float
    public init(center: Vector2D, radius: Float) { self.center = center; self.radius = radius }
    /// true when the point lies within the radius, edge included
    public func contains(_ point: Vector2D) -> Bool { center.distance(to: point) <= radius }
}

/// a finite line between two points
public struct LineSegment2D: Equatable, Sendable {
    public var start: Vector2D
    public var end: Vector2D
    public init(start: Vector2D, end: Vector2D) { self.start = start; self.end = end }
    /// distance between the endpoints
    public var length: Float { start.distance(to: end) }
    /// point at normalised position 't' (0 = start, 1 = end)
    public func point(at t: Float) -> Vector2D { start + (end - start) * t }
    /// point on the segment closest to 'point', clamped to the endpoints
    public func closestPoint(to point: Vector2D) -> Vector2D {
        let delta = end - start
        let denominator = delta.lengthSquared
        guard denominator > Float.ulpOfOne else { return start }
        let t = max(0, min(1, (point - start).dot(delta) / denominator))
        return self.point(at: t)
    }
}

/// free-standing geometry helpers
public enum Geometry {
    /// linear interpolation between two points
    public static func lerp(_ a: Vector2D, _ b: Vector2D, t: Float) -> Vector2D { a + (b - a) * t }
    /// clamps 'value' into 'range'
    public static func clamp(_ value: Float, to range: ClosedRange<Float>) -> Float { min(max(value, range.lowerBound), range.upperBound) }
}
