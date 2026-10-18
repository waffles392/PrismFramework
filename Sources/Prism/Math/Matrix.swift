import Foundation

/// compile-time vector dimension constraint
public protocol VectorDimension: Sendable {
    static var dimension: Int { get }
}

public struct Dim2: VectorDimension { public static let dimension = 2 }
public struct Dim3: VectorDimension { public static let dimension = 3 }
public struct Dim4: VectorDimension { public static let dimension = 4 }

/// a generic column-major matrix with compile-time dimension checking
///
/// matrix multiplication is constrained to compatible shapes:
/// 'Matrix<R, C> * Matrix<C, D> -> Matrix<R, D>'
/// this ensures only compatible matrices can be multiplied
///
/// the sizes the engine uses are 'Matrix<Dim2, Dim2>' (2D linear transforms),
/// 'Matrix<Dim3, Dim3>' (2D affine transforms, the graphics transform stack)
/// and 'Matrix<Dim4, Dim4>' (3D transforms, quaternion rotation)
///
/// elements are stored column-major, so the subscript reads '[row, col]'. the
/// 'm11'/'m12' style labels of the labeled initialisers are row-major
/// ('m<row><col>'), matching how the matrices are written on paper
///
/// storage is a fixed 16-slot buffer, so a matrix is a value with no heap
/// allocation: the transform stack and the per-vertex path stay allocation-free
public struct Matrix<Rows: VectorDimension, Cols: VectorDimension>: Equatable, Sendable {
    /// column-major elements, 16 slots cover the largest size the engine uses
    @usableFromInline
    var storage: InlineArray<16, Float> = InlineArray(repeating: 0)
    
    /// zero-filled elements, to be filled in by the size-specific initialisers
    @usableFromInline
    init() {}
    
    public init(elements: [Float]) {
        precondition(
            elements.count == Rows.dimension * Cols.dimension,
            "Matrix requires exactly \(Rows.dimension * Cols.dimension) elements"
        )
        for i in 0..<elements.count {
            storage[i] = elements[i]
        }
    }
    
    /// creates a matrix from column vectors (arrays)
    public init(columns: [[Float]]) {
        precondition(columns.count == Cols.dimension, "Expected \(Cols.dimension) columns")
        for c in 0..<Cols.dimension {
            precondition(columns[c].count == Rows.dimension, "Column must have \(Rows.dimension) elements")
            for r in 0..<Rows.dimension {
                self[r, c] = columns[c][r]
            }
        }
    }
    
    /// creates a matrix from row vectors (arrays)
    public init(rows: [[Float]]) {
        precondition(rows.count == Rows.dimension, "Expected \(Rows.dimension) rows")
        for r in 0..<Rows.dimension {
            precondition(rows[r].count == Cols.dimension, "Row must have \(Cols.dimension) elements")
            for c in 0..<Cols.dimension {
                self[r, c] = rows[r][c]
            }
        }
    }
    
    // MARK: - Equality
    
    /// compares the elements in use, not the unused slots of the backing buffer
    @inlinable
    public static func == (lhs: Matrix<Rows, Cols>, rhs: Matrix<Rows, Cols>) -> Bool {
        for i in 0..<(Rows.dimension * Cols.dimension) {
            if lhs.storage[i] != rhs.storage[i] { return false }
        }
        return true
    }
    
    // MARK: - Access
    
    @inlinable
    @inline(__always)
    public subscript(row: Int, col: Int) -> Float {
        get {
            precondition(row < Rows.dimension && col < Cols.dimension, "Index out of bounds")
            return storage[row + col * Rows.dimension]
        }
        set {
            precondition(row < Rows.dimension && col < Cols.dimension, "Index out of bounds")
            storage[row + col * Rows.dimension] = newValue
        }
    }
    
    public func column(_ col: Int) -> [Float] {
        precondition(col < Cols.dimension, "Column index out of bounds")
        return (0..<Rows.dimension).map { self[$0, col] }
    }
    
    public func row(_ row: Int) -> [Float] {
        precondition(row < Rows.dimension, "Row index out of bounds")
        return (0..<Cols.dimension).map { self[row, $0] }
    }
    
    // MARK: - Identity & Zero
    
    @inlinable
    public static var identity: Matrix<Rows, Cols> {
        precondition(Rows.dimension == Cols.dimension, "Identity matrix requires square dimensions")
        var result = Matrix<Rows, Cols>()
        for i in 0..<Rows.dimension {
            result[i, i] = 1
        }
        return result
    }
    
    @inlinable
    public static var zero: Matrix<Rows, Cols> {
        Matrix<Rows, Cols>()
    }
    
    // MARK: - Transpose
    
    @inlinable
    public func transposed() -> Matrix<Cols, Rows> {
        var result = Matrix<Cols, Rows>()
        for r in 0..<Rows.dimension {
            for c in 0..<Cols.dimension {
                result[c, r] = self[r, c]
            }
        }
        return result
    }
    
    // MARK: - Multiplication
    
    /// matrix multiplication: 'Matrix<R, C> * Matrix<C, D> -> Matrix<R, D>'
    @inlinable
    @inline(__always)
    public static func * <D: VectorDimension>(
        lhs: Matrix<Rows, Cols>,
        rhs: Matrix<Cols, D>
    ) -> Matrix<Rows, D> {
        var result = Matrix<Rows, D>()
        for r in 0..<Rows.dimension {
            for d in 0..<D.dimension {
                var sum: Float = 0
                for c in 0..<Cols.dimension {
                    sum += lhs[r, c] * rhs[c, d]
                }
                result[r, d] = sum
            }
        }
        return result
    }
    
    // MARK: - Vector Multiplication
    
    /// multiplies matrix by column vector (array): 'Matrix<R, C> * [C] -> [R]'
    public func multiply(_ vector: [Float]) -> [Float] {
        precondition(vector.count == Cols.dimension, "Vector dimension must match matrix columns")
        var result = [Float](repeating: 0, count: Rows.dimension)
        for r in 0..<Rows.dimension {
            var sum: Float = 0
            for c in 0..<Cols.dimension {
                sum += self[r, c] * vector[c]
            }
            result[r] = sum
        }
        return result
    }
    
    /// multiplies matrix by SIMD2 column vector
    public func multiply(_ vector: SIMD2<Float>) -> SIMD2<Float> where Rows == Dim2, Cols == Dim2 {
        SIMD2<Float>(
            self[0, 0] * vector.x + self[0, 1] * vector.y,
            self[1, 0] * vector.x + self[1, 1] * vector.y
        )
    }
    
    /// multiplies matrix by SIMD3 column vector
    public func multiply(_ vector: SIMD3<Float>) -> SIMD3<Float> where Rows == Dim3, Cols == Dim3 {
        SIMD3<Float>(
            self[0, 0] * vector.x + self[0, 1] * vector.y + self[0, 2] * vector.z,
            self[1, 0] * vector.x + self[1, 1] * vector.y + self[1, 2] * vector.z,
            self[2, 0] * vector.x + self[2, 1] * vector.y + self[2, 2] * vector.z
        )
    }
    
    /// multiplies matrix by SIMD4 column vector
    public func multiply(_ vector: SIMD4<Float>) -> SIMD4<Float> where Rows == Dim4, Cols == Dim4 {
        SIMD4<Float>(
            self[0, 0] * vector.x + self[0, 1] * vector.y + self[0, 2] * vector.z + self[0, 3] * vector.w,
            self[1, 0] * vector.x + self[1, 1] * vector.y + self[1, 2] * vector.z + self[1, 3] * vector.w,
            self[2, 0] * vector.x + self[2, 1] * vector.y + self[2, 2] * vector.z + self[2, 3] * vector.w,
            self[3, 0] * vector.x + self[3, 1] * vector.y + self[3, 2] * vector.z + self[3, 3] * vector.w
        )
    }
    
    // MARK: - Debug
    
    public func toArray() -> [Float] {
        (0..<(Rows.dimension * Cols.dimension)).map { storage[$0] }
    }
}

// MARK: - Square matrices

public extension Matrix where Rows == Cols {
    /// composes in place: 'lhs = lhs * rhs'
    @inlinable
    static func *= (lhs: inout Matrix<Rows, Cols>, rhs: Matrix<Rows, Cols>) {
        lhs = lhs * rhs
    }
    
    /// whether the matrix is the identity
    @inlinable
    var isIdentity: Bool { self == .identity }
}

// MARK: - 2×2

public extension Matrix where Rows == Dim2, Cols == Dim2 {
    init(m11: Float, m12: Float, m21: Float, m22: Float) {
        self[0, 0] = m11; self[0, 1] = m12
        self[1, 0] = m21; self[1, 1] = m22
    }
    
    /// creates a 2D scale matrix
    static func scale(_ factor: SIMD2<Float>) -> Matrix<Dim2, Dim2> {
        Matrix(m11: factor.x, m12: 0, m21: 0, m22: factor.y)
    }
    
    /// creates a 2D rotation matrix
    static func rotation(radians: Float) -> Matrix<Dim2, Dim2> {
        let c = cos(radians)
        let s = sin(radians)
        return Matrix(m11: c, m12: -s, m21: s, m22: c)
    }
    
    /// determinant of the matrix
    var determinant: Float {
        self[0, 0] * self[1, 1] - self[0, 1] * self[1, 0]
    }
    
    /// returns the inverse of this matrix, or 'nil' if it is singular
    func inverted() -> Matrix<Dim2, Dim2>? {
        let det = determinant
        guard abs(det) > Float.ulpOfOne else { return nil }
        let inv = 1 / det
        return Matrix(
            m11: self[1, 1] * inv, m12: -self[0, 1] * inv,
            m21: -self[1, 0] * inv, m22: self[0, 0] * inv
        )
    }
}

// MARK: - 3×3

public extension Matrix where Rows == Dim3, Cols == Dim3 {
    @inlinable
    init(
        m11: Float, m12: Float, m13: Float,
        m21: Float, m22: Float, m23: Float,
        m31: Float, m32: Float, m33: Float
    ) {
        self[0, 0] = m11; self[0, 1] = m12; self[0, 2] = m13
        self[1, 0] = m21; self[1, 1] = m22; self[1, 2] = m23
        self[2, 0] = m31; self[2, 1] = m32; self[2, 2] = m33
    }
    
    init(columns: (SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)) {
        self.init(
            m11: columns.0.x, m12: columns.1.x, m13: columns.2.x,
            m21: columns.0.y, m22: columns.1.y, m23: columns.2.y,
            m31: columns.0.z, m32: columns.1.z, m33: columns.2.z
        )
    }
    
    /// creates a matrix from nine values in row-major order
    init(_ values: [Float]) {
        precondition(values.count == 9, "Matrix<Dim3, Dim3> requires exactly 9 values")
        self.init(
            m11: values[0], m12: values[1], m13: values[2],
            m21: values[3], m22: values[4], m23: values[5],
            m31: values[6], m32: values[7], m33: values[8]
        )
    }
    
    // MARK: - Factory methods
    
    /// creates a 2D translation matrix (3x3 homogeneous)
    @inlinable
    @inline(__always)
    static func translation(_ offset: Vector2D) -> Matrix<Dim3, Dim3> {
        Matrix(
            m11: 1, m12: 0, m13: offset.x,
            m21: 0, m22: 1, m23: offset.y,
            m31: 0, m32: 0, m33: 1
        )
    }
    
    /// creates a 2D translation matrix (3x3 homogeneous)
    static func translation(_ offset: SIMD2<Float>) -> Matrix<Dim3, Dim3> {
        Matrix(
            m11: 1, m12: 0, m13: offset.x,
            m21: 0, m22: 1, m23: offset.y,
            m31: 0, m32: 0, m33: 1
        )
    }
    
    /// creates a 2D scale matrix (3x3 homogeneous)
    @inlinable
    @inline(__always)
    static func scale(_ factor: Vector2D) -> Matrix<Dim3, Dim3> {
        Matrix(
            m11: factor.x, m12: 0, m13: 0,
            m21: 0, m22: factor.y, m23: 0,
            m31: 0, m32: 0, m33: 1
        )
    }
    
    /// creates a 2D scale matrix (3x3 homogeneous)
    static func scale(_ factor: SIMD2<Float>) -> Matrix<Dim3, Dim3> {
        Matrix(
            m11: factor.x, m12: 0, m13: 0,
            m21: 0, m22: factor.y, m23: 0,
            m31: 0, m32: 0, m33: 1
        )
    }
    
    /// creates a 2D rotation matrix (3x3 homogeneous)
    @inlinable
    @inline(__always)
    static func rotation(radians: Float) -> Matrix<Dim3, Dim3> {
        let c = cos(radians)
        let s = sin(radians)
        return Matrix(
            m11: c, m12: -s, m13: 0,
            m21: s, m22: c, m23: 0,
            m31: 0, m32: 0, m33: 1
        )
    }
    
    /// creates a 2D rotation matrix from an 'Angle'
    static func rotation(_ angle: Angle) -> Matrix<Dim3, Dim3> {
        rotation(radians: angle.radians)
    }
    
    /// combined TRS matrix (translate * rotate * scale)
    @inlinable
    @inline(__always)
    static func trs(translation: Vector2D, rotation: Angle, scale: Vector2D) -> Matrix<Dim3, Dim3> {
        Self.translation(translation) * Self.rotation(rotation) * Self.scale(scale)
    }
    
    /// combined TRS matrix (translate * rotate * scale)
    @inlinable
    @inline(__always)
    static func trs(translation: SIMD2<Float>, rotation: Float, scale: SIMD2<Float>) -> Matrix<Dim3, Dim3> {
        Self.translation(translation) * Self.rotation(radians: rotation) * Self.scale(scale)
    }
    
    /// rotation around a pivot point
    static func rotationAround(pivot: Vector2D, angle: Angle) -> Matrix<Dim3, Dim3> {
        Self.translation(pivot) * Self.rotation(angle) * Self.translation(-pivot)
    }
    
    /// rotation around a pivot point
    static func rotationAround(pivot: SIMD2<Float>, angle: Float) -> Matrix<Dim3, Dim3> {
        Self.translation(pivot) * Self.rotation(radians: angle) * Self.translation(SIMD2(-pivot.x, -pivot.y))
    }
    
    /// scale around a pivot point
    static func scaleAround(pivot: Vector2D, scale: Vector2D) -> Matrix<Dim3, Dim3> {
        Self.translation(pivot) * Self.scale(scale) * Self.translation(-pivot)
    }
    
    /// scale around a pivot point
    static func scaleAround(pivot: SIMD2<Float>, scale: SIMD2<Float>) -> Matrix<Dim3, Dim3> {
        Self.translation(pivot) * Self.scale(scale) * Self.translation(SIMD2(-pivot.x, -pivot.y))
    }
    
    // MARK: - Properties
    
    /// determinant of the matrix
    @inlinable
    var determinant: Float {
        self[0, 0] * (self[1, 1] * self[2, 2] - self[1, 2] * self[2, 1])
            - self[0, 1] * (self[1, 0] * self[2, 2] - self[1, 2] * self[2, 0])
            + self[0, 2] * (self[1, 0] * self[2, 1] - self[1, 1] * self[2, 0])
    }
    
    /// translation vector extracted from the matrix
    @inlinable
    var translation: Vector2D {
        Vector2D(self[0, 2], self[1, 2])
    }
    
    /// scale vector extracted from the matrix
    @inlinable
    var scale: Vector2D {
        Vector2D(
            sqrt(self[0, 0] * self[0, 0] + self[1, 0] * self[1, 0]),
            sqrt(self[0, 1] * self[0, 1] + self[1, 1] * self[1, 1])
        )
    }
    
    /// rotation angle extracted from the matrix
    @inlinable
    var rotation: Angle {
        Angle(radians: atan2(self[1, 0], self[0, 0]))
    }
    
    // MARK: - Vector transform
    
    /// transforms a point (with translation)
    @inlinable
    @inline(__always)
    func transformPoint(_ point: Vector2D) -> Vector2D {
        Vector2D(
            self[0, 0] * point.x + self[0, 1] * point.y + self[0, 2],
            self[1, 0] * point.x + self[1, 1] * point.y + self[1, 2]
        )
    }
    
    /// transforms a direction vector (without translation)
    @inlinable
    func transformVector(_ vector: Vector2D) -> Vector2D {
        Vector2D(
            self[0, 0] * vector.x + self[0, 1] * vector.y,
            self[1, 0] * vector.x + self[1, 1] * vector.y
        )
    }
    
    /// transforms a rectangle and returns its axis-aligned bounding box
    func transformRect(_ rect: Rect2D) -> Rect2D {
        let corners = [
            rect.min,
            Vector2D(rect.max.x, rect.min.y),
            rect.max,
            Vector2D(rect.min.x, rect.max.y)
        ].map(transformPoint)
        
        var minX = corners[0].x, maxX = corners[0].x
        var minY = corners[0].y, maxY = corners[0].y
        
        for c in corners.dropFirst() {
            minX = min(minX, c.x)
            maxX = max(maxX, c.x)
            minY = min(minY, c.y)
            maxY = max(maxY, c.y)
        }
        
        return Rect2D(origin: Vector2D(minX, minY), size: Vector2D(maxX - minX, maxY - minY))
    }
    
    /// multiplies matrix by a homogeneous 2D point
    @inlinable
    static func * (lhs: Matrix<Dim3, Dim3>, rhs: Vector2D) -> Vector2D {
        Vector2D(
            lhs[0, 0] * rhs.x + lhs[0, 1] * rhs.y + lhs[0, 2],
            lhs[1, 0] * rhs.x + lhs[1, 1] * rhs.y + lhs[1, 2]
        )
    }
    
    // MARK: - Inverse
    
    /// returns the inverse of this matrix, or 'nil' if it is singular
    @inlinable
    func inverted() -> Matrix<Dim3, Dim3>? {
        let det = determinant
        guard abs(det) > Float.ulpOfOne else { return nil }
        let invDet = 1 / det
        
        return Matrix(
            m11: (self[1, 1] * self[2, 2] - self[1, 2] * self[2, 1]) * invDet,
            m12: (self[0, 2] * self[2, 1] - self[0, 1] * self[2, 2]) * invDet,
            m13: (self[0, 1] * self[1, 2] - self[0, 2] * self[1, 1]) * invDet,
            
            m21: (self[1, 2] * self[2, 0] - self[1, 0] * self[2, 2]) * invDet,
            m22: (self[0, 0] * self[2, 2] - self[0, 2] * self[2, 0]) * invDet,
            m23: (self[0, 2] * self[1, 0] - self[0, 0] * self[1, 2]) * invDet,
            
            m31: (self[1, 0] * self[2, 1] - self[1, 1] * self[2, 0]) * invDet,
            m32: (self[0, 1] * self[2, 0] - self[0, 0] * self[2, 1]) * invDet,
            m33: (self[0, 0] * self[1, 1] - self[0, 1] * self[1, 0]) * invDet
        )
    }
    
    // MARK: - Interpolation
    
    /// element-wise linear interpolation between two matrices
    static func lerp(_ a: Matrix<Dim3, Dim3>, _ b: Matrix<Dim3, Dim3>, t: Float) -> Matrix<Dim3, Dim3> {
        var result = a
        for r in 0..<3 {
            for c in 0..<3 {
                result[r, c] = a[r, c] + (b[r, c] - a[r, c]) * t
            }
        }
        return result
    }
    
    // MARK: - SIMD access
    
    var columns: (SIMD3<Float>, SIMD3<Float>, SIMD3<Float>) {
        (
            SIMD3(self[0, 0], self[1, 0], self[2, 0]),
            SIMD3(self[0, 1], self[1, 1], self[2, 1]),
            SIMD3(self[0, 2], self[1, 2], self[2, 2])
        )
    }
    
    var rows: (SIMD3<Float>, SIMD3<Float>, SIMD3<Float>) {
        (
            SIMD3(self[0, 0], self[0, 1], self[0, 2]),
            SIMD3(self[1, 0], self[1, 1], self[1, 2]),
            SIMD3(self[2, 0], self[2, 1], self[2, 2])
        )
    }
    
    /// flat array in row-major order
    func toFloatArray() -> [Float] {
        [
            self[0, 0], self[0, 1], self[0, 2],
            self[1, 0], self[1, 1], self[1, 2],
            self[2, 0], self[2, 1], self[2, 2]
        ]
    }
}

// MARK: - 4×4

public extension Matrix where Rows == Dim4, Cols == Dim4 {
    init(
        m11: Float, m12: Float, m13: Float, m14: Float,
        m21: Float, m22: Float, m23: Float, m24: Float,
        m31: Float, m32: Float, m33: Float, m34: Float,
        m41: Float, m42: Float, m43: Float, m44: Float
    ) {
        self[0, 0] = m11; self[0, 1] = m12; self[0, 2] = m13; self[0, 3] = m14
        self[1, 0] = m21; self[1, 1] = m22; self[1, 2] = m23; self[1, 3] = m24
        self[2, 0] = m31; self[2, 1] = m32; self[2, 2] = m33; self[2, 3] = m34
        self[3, 0] = m41; self[3, 1] = m42; self[3, 2] = m43; self[3, 3] = m44
    }
    
    // MARK: - Factory: translation
    
    /// creates a 4×4 translation matrix
    static func translation(_ offset: Vector3D) -> Matrix<Dim4, Dim4> {
        Matrix(
            m11: 1, m12: 0, m13: 0, m14: offset.x,
            m21: 0, m22: 1, m23: 0, m24: offset.y,
            m31: 0, m32: 0, m33: 1, m34: offset.z,
            m41: 0, m42: 0, m43: 0, m44: 1
        )
    }
    
    // MARK: - Factory: scale
    
    /// creates a 4×4 scale matrix
    static func scale(_ factor: Vector3D) -> Matrix<Dim4, Dim4> {
        Matrix(
            m11: factor.x, m12: 0, m13: 0, m14: 0,
            m21: 0, m22: factor.y, m23: 0, m24: 0,
            m31: 0, m32: 0, m33: factor.z, m34: 0,
            m41: 0, m42: 0, m43: 0, m44: 1
        )
    }
    
    /// creates a 4×4 uniform-scale matrix
    static func scale(uniform s: Float) -> Matrix<Dim4, Dim4> {
        Self.scale(Vector3D(s, s, s))
    }
    
    // MARK: - Factory: rotation
    
    /// creates a 4×4 rotation matrix from a unit quaternion
    static func rotation(_ q: Quaternion) -> Matrix<Dim4, Dim4> {
        q.matrix4x4
    }
    
    /// creates a 4×4 rotation matrix around the x axis
    static func rotationX(_ angle: Angle) -> Matrix<Dim4, Dim4> {
        let c = cos(angle.radians)
        let s = sin(angle.radians)
        return Matrix(
            m11: 1, m12: 0, m13: 0, m14: 0,
            m21: 0, m22: c, m23: -s, m24: 0,
            m31: 0, m32: s, m33: c, m34: 0,
            m41: 0, m42: 0, m43: 0, m44: 1
        )
    }
    
    /// creates a 4×4 rotation matrix around the y axis
    static func rotationY(_ angle: Angle) -> Matrix<Dim4, Dim4> {
        let c = cos(angle.radians)
        let s = sin(angle.radians)
        return Matrix(
            m11: c, m12: 0, m13: s, m14: 0,
            m21: 0, m22: 1, m23: 0, m24: 0,
            m31: -s, m32: 0, m33: c, m34: 0,
            m41: 0, m42: 0, m43: 0, m44: 1
        )
    }
    
    /// creates a 4×4 rotation matrix around the z axis
    static func rotationZ(_ angle: Angle) -> Matrix<Dim4, Dim4> {
        let c = cos(angle.radians)
        let s = sin(angle.radians)
        return Matrix(
            m11: c, m12: -s, m13: 0, m14: 0,
            m21: s, m22: c, m23: 0, m24: 0,
            m31: 0, m32: 0, m33: 1, m34: 0,
            m41: 0, m42: 0, m43: 0, m44: 1
        )
    }
    
    // MARK: - Factory: projection
    
    /// creates a perspective projection matrix (right-handed, [0,1] depth)
    ///
    /// - Parameters:
    ///   - fovY: vertical field of view
    ///   - aspect: viewport width / height
    ///   - near: near clip plane distance (> 0)
    ///   - far: far clip plane distance (> near)
    static func perspective(fovY: Angle, aspect: Float, near: Float, far: Float) -> Matrix<Dim4, Dim4> {
        let tanHalfFov = tan(fovY.radians * 0.5)
        return Matrix(
            m11: 1 / (aspect * tanHalfFov), m12: 0, m13: 0, m14: 0,
            m21: 0, m22: 1 / tanHalfFov, m23: 0, m24: 0,
            m31: 0, m32: 0, m33: far / (near - far), m34: -(far * near) / (far - near),
            m41: 0, m42: 0, m43: -1, m44: 0
        )
    }
    
    /// creates an orthographic projection matrix (right-handed, [0,1] depth)
    static func orthographic(
        left: Float, right: Float,
        bottom: Float, top: Float,
        near: Float, far: Float
    ) -> Matrix<Dim4, Dim4> {
        Matrix(
            m11: 2 / (right - left), m12: 0, m13: 0, m14: -(right + left) / (right - left),
            m21: 0, m22: 2 / (top - bottom), m23: 0, m24: -(top + bottom) / (top - bottom),
            m31: 0, m32: 0, m33: -1 / (far - near), m34: -near / (far - near),
            m41: 0, m42: 0, m43: 0, m44: 1
        )
    }
    
    // MARK: - Factory: TRS
    
    /// creates a combined translation × rotation × scale matrix
    static func trs(translation t: Vector3D, rotation r: Quaternion, scale s: Vector3D) -> Matrix<Dim4, Dim4> {
        Self.translation(t) * Self.rotation(r) * Self.scale(s)
    }
    
    // MARK: - Properties
    
    /// the translation component extracted from this matrix
    var translation3D: Vector3D {
        Vector3D(self[0, 3], self[1, 3], self[2, 3])
    }
    
    // MARK: - Vector transform
    
    /// transforms a homogeneous point (w=1) by this matrix
    func transformPoint(_ point: Vector3D) -> Vector3D {
        Vector3D(
            self[0, 0] * point.x + self[0, 1] * point.y + self[0, 2] * point.z + self[0, 3],
            self[1, 0] * point.x + self[1, 1] * point.y + self[1, 2] * point.z + self[1, 3],
            self[2, 0] * point.x + self[2, 1] * point.y + self[2, 2] * point.z + self[2, 3]
        )
    }
    
    /// transforms a direction vector (w=0) by this matrix
    func transformVector(_ vector: Vector3D) -> Vector3D {
        Vector3D(
            self[0, 0] * vector.x + self[0, 1] * vector.y + self[0, 2] * vector.z,
            self[1, 0] * vector.x + self[1, 1] * vector.y + self[1, 2] * vector.z,
            self[2, 0] * vector.x + self[2, 1] * vector.y + self[2, 2] * vector.z
        )
    }
    
    // MARK: - Inverse
    
    /// returns the inverse of this matrix, or 'nil' if it is singular
    func inverted() -> Matrix<Dim4, Dim4>? {
        // standard cofactor expansion
        let a00 = self[0, 0], a01 = self[0, 1], a02 = self[0, 2], a03 = self[0, 3]
        let a10 = self[1, 0], a11 = self[1, 1], a12 = self[1, 2], a13 = self[1, 3]
        let a20 = self[2, 0], a21 = self[2, 1], a22 = self[2, 2], a23 = self[2, 3]
        let a30 = self[3, 0], a31 = self[3, 1], a32 = self[3, 2], a33 = self[3, 3]
        
        let b00 = a00 * a11 - a01 * a10
        let b01 = a00 * a12 - a02 * a10
        let b02 = a00 * a13 - a03 * a10
        let b03 = a01 * a12 - a02 * a11
        let b04 = a01 * a13 - a03 * a11
        let b05 = a02 * a13 - a03 * a12
        let b06 = a20 * a31 - a21 * a30
        let b07 = a20 * a32 - a22 * a30
        let b08 = a20 * a33 - a23 * a30
        let b09 = a21 * a32 - a22 * a31
        let b10 = a21 * a33 - a23 * a31
        let b11 = a22 * a33 - a23 * a32
        
        let det = b00 * b11 - b01 * b10 + b02 * b09 + b03 * b08 - b04 * b07 + b05 * b06
        guard abs(det) > Float.ulpOfOne else { return nil }
        let invDet = 1 / det
        
        return Matrix(
            m11: ( a11 * b11 - a12 * b10 + a13 * b09) * invDet,
            m12: (-a01 * b11 + a02 * b10 - a03 * b09) * invDet,
            m13: ( a31 * b05 - a32 * b04 + a33 * b03) * invDet,
            m14: (-a21 * b05 + a22 * b04 - a23 * b03) * invDet,
            
            m21: (-a10 * b11 + a12 * b08 - a13 * b07) * invDet,
            m22: ( a00 * b11 - a02 * b08 + a03 * b07) * invDet,
            m23: (-a30 * b05 + a32 * b02 - a33 * b01) * invDet,
            m24: ( a20 * b05 - a22 * b02 + a23 * b01) * invDet,
            
            m31: ( a10 * b10 - a11 * b08 + a13 * b06) * invDet,
            m32: (-a00 * b10 + a01 * b08 - a03 * b06) * invDet,
            m33: ( a30 * b04 - a31 * b02 + a33 * b00) * invDet,
            m34: (-a20 * b04 + a21 * b02 - a23 * b00) * invDet,
            
            m41: (-a10 * b09 + a11 * b07 - a12 * b06) * invDet,
            m42: ( a00 * b09 - a01 * b07 + a02 * b06) * invDet,
            m43: (-a30 * b03 + a31 * b01 - a32 * b00) * invDet,
            m44: ( a20 * b03 - a21 * b01 + a22 * b00) * invDet
        )
    }
    
    // MARK: - Interpolation
    
    /// element-wise linear interpolation between two matrices
    static func lerp(_ a: Matrix<Dim4, Dim4>, _ b: Matrix<Dim4, Dim4>, t: Float) -> Matrix<Dim4, Dim4> {
        var result = a
        for r in 0..<4 {
            for c in 0..<4 {
                result[r, c] = a[r, c] + (b[r, c] - a[r, c]) * t
            }
        }
        return result
    }
    
    // MARK: - GPU upload
    
    /// flat array in column-major order, suitable for GPU uniform upload
    var columnMajorArray: [Float] {
        [
            self[0, 0], self[1, 0], self[2, 0], self[3, 0],
            self[0, 1], self[1, 1], self[2, 1], self[3, 1],
            self[0, 2], self[1, 2], self[2, 2], self[3, 2],
            self[0, 3], self[1, 3], self[2, 3], self[3, 3]
        ]
    }
}
