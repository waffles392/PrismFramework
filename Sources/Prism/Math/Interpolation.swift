import Foundation

/// small, frame-rate independent interpolation helpers for simulation and
/// presentation state
public enum Interpolation {
    public static func scalar(
        current: Float,
        target: Float,
        deltaTime: Float,
        speed: Float
    ) -> Float {
        guard deltaTime > 0, speed > 0 else { return current }
        let amount = 1 - Foundation.exp(-Double(speed * deltaTime))
        return current + (target - current) * Float(amount)
    }

    public static func vector(
        current: Vector2D,
        target: Vector2D,
        deltaTime: Float,
        speed: Float
    ) -> Vector2D {
        Vector2D(
            scalar: scalar(current: current.x, target: target.x, deltaTime: deltaTime, speed: speed),
            scalarY: scalar(current: current.y, target: target.y, deltaTime: deltaTime, speed: speed)
        )
    }

    /// interpolates through the shortest path, including the -π/π boundary
    public static func angle(
        current: Angle,
        target: Angle,
        deltaTime: Float,
        speed: Float
    ) -> Angle {
        let difference = (target - current).normalized.radians
        let factor = Float(1 - Foundation.exp(-Double(speed * deltaTime)))
        let radians = current.radians + difference * factor
        return Angle(radians: radians).normalized
    }
}

private extension Vector2D {
    init(scalar x: Float, scalarY y: Float) {
        self.init(x: x, y: y)
    }
}
