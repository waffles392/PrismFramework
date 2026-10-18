import Foundation

/// a unit quaternion for 3D rotations
///
/// stored as '(x, y, z, w)' - the scalar part is 'w' and the vector
/// part is '(x, y, z)'. all factory methods produce normalised
/// quaternions; consumer code should treat the type as always normalised
///
/// ```swift
/// let q = Quaternion(eulerDegrees: Vector3D(45, 0, 0))  // 45° pitch
/// let rotated = q.rotate(Vector3D(0, 1, 0))
/// let mat = q.matrix4x4
/// ```
public struct Quaternion: Equatable, Hashable, Sendable {

    public var x: Float
    public var y: Float
    public var z: Float
    /// the scalar (real) component
    public var w: Float

    // MARK: - Init

    public init(x: Float, y: Float, z: Float, w: Float) {
        self.x = x
        self.y = y
        self.z = z
        self.w = w
    }

    // MARK: - Constants

    /// the identity quaternion (no rotation)
    public static let identity = Quaternion(x: 0, y: 0, z: 0, w: 1)

    // MARK: - Factory: axis-angle

    /// creates a quaternion from an axis (must be unit length) and an angle
    public static func axisAngle(axis: Vector3D, angle: Angle) -> Quaternion {
        let halfAngle = angle.radians * 0.5
        let s = Float(sin(Double(halfAngle)))
        return Quaternion(
            x: axis.x * s,
            y: axis.y * s,
            z: axis.z * s,
            w: Float(cos(Double(halfAngle)))
        )
    }

    // MARK: - Factory: Euler angles (intrinsic X→Y→Z)

    /// creates a quaternion from Euler angles (in radians, intrinsic X-Y-Z order)
    public static func euler(pitch: Float, yaw: Float, roll: Float) -> Quaternion {
        let cx = Float(cos(Double(pitch * 0.5)))
        let sx = Float(sin(Double(pitch * 0.5)))
        let cy = Float(cos(Double(yaw   * 0.5)))
        let sy = Float(sin(Double(yaw   * 0.5)))
        let cz = Float(cos(Double(roll  * 0.5)))
        let sz = Float(sin(Double(roll  * 0.5)))

        return Quaternion(
            x: sx * cy * cz + cx * sy * sz,
            y: cx * sy * cz - sx * cy * sz,
            z: cx * cy * sz + sx * sy * cz,
            w: cx * cy * cz - sx * sy * sz
        )
    }

    /// creates a quaternion from Euler angles packed in a 'Vector3D'
    /// (x = pitch, y = yaw, z = roll), in radians
    public static func euler(_ angles: Vector3D) -> Quaternion {
        euler(pitch: angles.x, yaw: angles.y, roll: angles.z)
    }

    /// creates a quaternion from Euler angles in degrees
    public static func eulerDegrees(pitch: Float, yaw: Float, roll: Float) -> Quaternion {
        euler(
            pitch: pitch * (.pi / 180),
            yaw:   yaw   * (.pi / 180),
            roll:  roll  * (.pi / 180)
        )
    }

    /// creates a quaternion from Euler angles (in degrees) packed in a 'Vector3D'
    public static func eulerDegrees(_ degrees: Vector3D) -> Quaternion {
        eulerDegrees(pitch: degrees.x, yaw: degrees.y, roll: degrees.z)
    }

    // MARK: - Factory: look rotation

    /// creates a quaternion that rotates 'forward' (+Z) to face 'direction'
    /// - Parameters:
    ///   - direction: the target look direction (need not be normalised)
    ///   - up: the world up vector (default '+Y')
    public static func lookRotation(direction: Vector3D, up: Vector3D = .unitY) -> Quaternion {
        let f = direction.normalized
        guard f.length > Float.ulpOfOne else { return .identity }

        let r = up.cross(f).normalized
        let u = f.cross(r)

        // build the rotation matrix columns and convert to quaternion
        let trace = r.x + u.y + f.z

        if trace > 0 {
            let s = 0.5 / Float(sqrt(Double(trace + 1)))
            return Quaternion(
                x: (u.z - f.y) * s,
                y: (f.x - r.z) * s,
                z: (r.y - u.x) * s,
                w: 0.25 / s
            )
        } else if r.x > u.y && r.x > f.z {
            let s = 2 * Float(sqrt(Double(1 + r.x - u.y - f.z)))
            return Quaternion(x: 0.25 * s, y: (u.x + r.y) / s, z: (f.x + r.z) / s, w: (u.z - f.y) / s)
        } else if u.y > f.z {
            let s = 2 * Float(sqrt(Double(1 + u.y - r.x - f.z)))
            return Quaternion(x: (u.x + r.y) / s, y: 0.25 * s, z: (f.y + u.z) / s, w: (f.x - r.z) / s)
        } else {
            let s = 2 * Float(sqrt(Double(1 + f.z - r.x - u.y)))
            return Quaternion(x: (f.x + r.z) / s, y: (f.y + u.z) / s, z: 0.25 * s, w: (r.y - u.x) / s)
        }
    }

    // MARK: - Properties

    /// the squared length of the quaternion. should be 1 for unit quaternions
    public var lengthSquared: Float { x*x + y*y + z*z + w*w }
    public var length: Float { lengthSquared.squareRoot() }

    /// returns a normalised copy of this quaternion
    public var normalized: Quaternion {
        let mag = length
        guard mag > Float.ulpOfOne else { return .identity }
        let inv = 1 / mag
        return Quaternion(x: x * inv, y: y * inv, z: z * inv, w: w * inv)
    }

    /// the conjugate (inverse for unit quaternions)
    public var conjugate: Quaternion {
        Quaternion(x: -x, y: -y, z: -z, w: w)
    }

    /// the inverse (conjugate normalised)
    public var inverse: Quaternion {
        let sq = lengthSquared
        guard sq > Float.ulpOfOne else { return .identity }
        let inv = 1 / sq
        return Quaternion(x: -x * inv, y: -y * inv, z: -z * inv, w: w * inv)
    }

    // MARK: - Derived angles

    /// Euler angles (pitch, yaw, roll) in radians derived from this quaternion
    public var eulerAngles: Vector3D {
        let sinPitchCosPitch = 2 * (w * x + y * z)
        let cosPitchCosPitch = 1 - 2 * (x * x + y * y)
        let pitch = Float(atan2(Double(sinPitchCosPitch), Double(cosPitchCosPitch)))

        let sinYaw = 2 * (w * y - z * x)
        let yaw: Float
        if abs(sinYaw) >= 1 {
            yaw = Float(copysign(.pi / 2, Double(sinYaw)))
        } else {
            yaw = Float(asin(Double(sinYaw)))
        }

        let sinRollCosRoll = 2 * (w * z + x * y)
        let cosRollCosRoll = 1 - 2 * (y * y + z * z)
        let roll = Float(atan2(Double(sinRollCosRoll), Double(cosRollCosRoll)))

        return Vector3D(pitch, yaw, roll)
    }

    /// Euler angles (pitch, yaw, roll) in degrees
    public var eulerDegrees: Vector3D {
        eulerAngles * (180 / .pi)
    }

    // MARK: - Rotation

    /// rotates a vector by this quaternion
    public func rotate(_ v: Vector3D) -> Vector3D {
        let qv = Vector3D(x, y, z)
        let uv = qv.cross(v)
        let uuv = qv.cross(uv)
        return v + (uv * (2 * w)) + (uuv * 2)
    }

    // MARK: - 4×4 matrix

    /// returns the equivalent 4×4 rotation matrix (column-major)
    public var matrix4x4: Matrix<Dim4, Dim4> {
        let x2 = x + x, y2 = y + y, z2 = z + z
        let xx = x * x2, xy = x * y2, xz = x * z2
        let yy = y * y2, yz = y * z2, zz = z * z2
        let wx = w * x2, wy = w * y2, wz = w * z2

        return Matrix<Dim4, Dim4>(
            m11: 1 - (yy + zz), m12: xy - wz,       m13: xz + wy,       m14: 0,
            m21: xy + wz,       m22: 1 - (xx + zz), m23: yz - wx,       m24: 0,
            m31: xz - wy,       m32: yz + wx,       m33: 1 - (xx + yy), m34: 0,
            m41: 0,             m42: 0,             m43: 0,             m44: 1
        )
    }

    // MARK: - Multiplication

    public static func * (lhs: Quaternion, rhs: Quaternion) -> Quaternion {
        Quaternion(
            x: lhs.w * rhs.x + lhs.x * rhs.w + lhs.y * rhs.z - lhs.z * rhs.y,
            y: lhs.w * rhs.y - lhs.x * rhs.z + lhs.y * rhs.w + lhs.z * rhs.x,
            z: lhs.w * rhs.z + lhs.x * rhs.y - lhs.y * rhs.x + lhs.z * rhs.w,
            w: lhs.w * rhs.w - lhs.x * rhs.x - lhs.y * rhs.y - lhs.z * rhs.z
        ).normalized
    }

    public static func *= (lhs: inout Quaternion, rhs: Quaternion) {
        lhs = lhs * rhs
    }

    // MARK: - Interpolation

    /// linearly interpolates between two quaternions (not normalised - use
    /// 'slerp' for arc-correct interpolation)
    public static func lerp(_ a: Quaternion, _ b: Quaternion, t: Float) -> Quaternion {
        let dot = a.x*b.x + a.y*b.y + a.z*b.z + a.w*b.w
        let b2  = dot < 0 ? Quaternion(x: -b.x, y: -b.y, z: -b.z, w: -b.w) : b
        return Quaternion(
            x: a.x + (b2.x - a.x) * t,
            y: a.y + (b2.y - a.y) * t,
            z: a.z + (b2.z - a.z) * t,
            w: a.w + (b2.w - a.w) * t
        ).normalized
    }

    /// spherically interpolates between two quaternions
    public static func slerp(_ a: Quaternion, _ b: Quaternion, t: Float) -> Quaternion {
        var dot = a.x*b.x + a.y*b.y + a.z*b.z + a.w*b.w
        let b2: Quaternion
        if dot < 0 {
            b2 = Quaternion(x: -b.x, y: -b.y, z: -b.z, w: -b.w)
            dot = -dot
        } else {
            b2 = b
        }

        if dot > 0.9995 {
            return lerp(a, b2, t: t)
        }

        let theta0 = Float(acos(Double(dot)))
        let theta  = theta0 * t
        let sinTheta  = Float(sin(Double(theta)))
        let sinTheta0 = Float(sin(Double(theta0)))

        let s1 = Float(cos(Double(theta))) - dot * sinTheta / sinTheta0
        let s2 = sinTheta / sinTheta0
        return Quaternion(
            x: a.x * s1 + b2.x * s2,
            y: a.y * s1 + b2.y * s2,
            z: a.z * s1 + b2.z * s2,
            w: a.w * s1 + b2.w * s2
        ).normalized
    }

    // MARK: - Dot

    public func dot(_ other: Quaternion) -> Float {
        x*other.x + y*other.y + z*other.z + w*other.w
    }
}

// MARK: - CustomStringConvertible

extension Quaternion: CustomStringConvertible {
    public var description: String {
        String(format: "Quaternion(%.4f, %.4f, %.4f, %.4f)", x, y, z, w)
    }
}
