import Testing
import Prism

/// tolerance used for the float comparisons below
private let epsilon: Float = 1e-5

private func close(_ a: Float, _ b: Float, _ tolerance: Float = epsilon) -> Bool {
    abs(a - b) <= tolerance
}

private func isIdentity<Rows: VectorDimension, Cols: VectorDimension>(
    _ matrix: Matrix<Rows, Cols>
) -> Bool {
    guard Rows.dimension == Cols.dimension else { return false }
    for r in 0..<Rows.dimension {
        for c in 0..<Cols.dimension {
            let expected: Float = r == c ? 1 : 0
            if abs(matrix[r, c] - expected) > 1e-4 { return false }
        }
    }
    return true
}

// MARK: - element layout

@Test func labeledInitIsRowMajor() {
    let m = Matrix<Dim3, Dim3>(
        m11: 1, m12: 2, m13: 3,
        m21: 4, m22: 5, m23: 6,
        m31: 7, m32: 8, m33: 9
    )

    #expect(m[0, 0] == 1)
    #expect(m[0, 1] == 2)
    #expect(m[0, 2] == 3)
    #expect(m[1, 0] == 4)
    #expect(m[1, 1] == 5)
    #expect(m[2, 2] == 9)
}

@Test func labeledInitIsRowMajorForEverySize() {
    let two = Matrix<Dim2, Dim2>(m11: 1, m12: 2, m21: 3, m22: 4)
    #expect(two[0, 1] == 2)
    #expect(two[1, 0] == 3)

    let four = Matrix<Dim4, Dim4>(
        m11: 1, m12: 2, m13: 3, m14: 4,
        m21: 5, m22: 6, m23: 7, m24: 8,
        m31: 9, m32: 10, m33: 11, m34: 12,
        m41: 13, m42: 14, m43: 15, m44: 16
    )
    #expect(four[0, 3] == 4)
    #expect(four[3, 0] == 13)
    #expect(four[3, 3] == 16)
}

@Test func transposedSwapsIndices() {
    let m = Matrix<Dim3, Dim3>(
        m11: 1, m12: 2, m13: 3,
        m21: 4, m22: 5, m23: 6,
        m31: 7, m32: 8, m33: 9
    )
    let t = m.transposed()

    #expect(t[0, 1] == m[1, 0])
    #expect(t[2, 0] == m[0, 2])
    #expect(t.isIdentity == false)
}

@Test func columnMajorArrayIsColumnMajor() {
    let m = Matrix<Dim4, Dim4>(
        m11: 1, m12: 2, m13: 3, m14: 4,
        m21: 5, m22: 6, m23: 7, m24: 8,
        m31: 9, m32: 10, m33: 11, m34: 12,
        m41: 13, m42: 14, m43: 15, m44: 16
    )
    let array = m.columnMajorArray

    #expect(array.count == 16)
    #expect(array[0] == 1)
    #expect(array[1] == 5)
    #expect(array[4] == 2)
    #expect(array[15] == 16)
}

@Test func floatArrayRoundTripsInRowMajorOrder() {
    let values: [Float] = [1, 2, 3, 4, 5, 6, 7, 8, 9]
    let m = Matrix<Dim3, Dim3>(values)

    #expect(m.toFloatArray() == values)
    #expect(m[0, 1] == 2)
    #expect(m[1, 0] == 4)
}

// MARK: - 3×3 transforms

@Test func translationMatrixMovesPoints() {
    let m = Matrix<Dim3, Dim3>.translation(Vector2D(3, 4))
    let p = m.transformPoint(Vector2D(1, 1))

    #expect(close(p.x, 4))
    #expect(close(p.y, 5))
    #expect(m.translation == Vector2D(3, 4))
}

@Test func scaleMatrixScalesPoints() {
    let m = Matrix<Dim3, Dim3>.scale(Vector2D(2, 3))
    let p = m.transformPoint(Vector2D(1, 1))

    #expect(close(p.x, 2))
    #expect(close(p.y, 3))
    #expect(close(m.scale.x, 2))
    #expect(close(m.scale.y, 3))
}

@Test func rotationMatrixRotatesPoints() {
    let m = Matrix<Dim3, Dim3>.rotation(Angle(radians: Float.pi / 2))
    let p = m.transformPoint(Vector2D(1, 0))

    #expect(close(p.x, 0, 1e-4))
    #expect(close(p.y, 1, 1e-4))
    #expect(close(m.rotation.radians, Float.pi / 2, 1e-4))
}

@Test func trsAppliesScaleThenRotationThenTranslation() {
    let m = Matrix<Dim3, Dim3>.trs(
        translation: Vector2D(10, 0),
        rotation: Angle(radians: Float.pi / 2),
        scale: Vector2D(2, 2)
    )
    let p = m.transformPoint(Vector2D(1, 0))

    // scale → (2, 0), rotate 90° → (0, 2), translate → (10, 2)
    #expect(close(p.x, 10, 1e-4))
    #expect(close(p.y, 2, 1e-4))
}

@Test func transformVectorIgnoresTranslation() {
    let m = Matrix<Dim3, Dim3>.translation(Vector2D(100, 100))
    let v = m.transformVector(Vector2D(1, 1))

    #expect(close(v.x, 1))
    #expect(close(v.y, 1))
}

@Test func transformRectProducesBounds() {
    let rect = Rect2D(origin: Vector2D(0, 0), size: Vector2D(2, 2))
    let moved = Matrix<Dim3, Dim3>.translation(Vector2D(5, 6)).transformRect(rect)

    #expect(close(moved.min.x, 5))
    #expect(close(moved.min.y, 6))
    #expect(close(moved.max.x, 7))
    #expect(close(moved.max.y, 8))
}

@Test func rotationAroundPivotKeepsPivotFixed() {
    let m = Matrix<Dim3, Dim3>.rotationAround(pivot: Vector2D(5, 5), angle: Angle(radians: 0.7))
    let p = m.transformPoint(Vector2D(5, 5))

    #expect(close(p.x, 5, 1e-4))
    #expect(close(p.y, 5, 1e-4))
}

@Test func matrixVectorProductMatchesTransformPoint() {
    let m = Matrix<Dim3, Dim3>.trs(
        translation: Vector2D(2, 3),
        rotation: Angle(radians: 0.4),
        scale: Vector2D(1.5, 0.5)
    )
    let point = Vector2D(0.25, -0.75)
    let viaOperator = m * point
    let viaMethod = m.transformPoint(point)

    #expect(close(viaOperator.x, viaMethod.x))
    #expect(close(viaOperator.y, viaMethod.y))
}

@Test func compositionMatchesSequentialTransforms() {
    let point = Vector2D(3, -2)
    let composed = Matrix<Dim3, Dim3>.translation(Vector2D(1, 1))
        * Matrix<Dim3, Dim3>.rotation(Angle(radians: 0.3))

    let sequential = Matrix<Dim3, Dim3>.rotation(Angle(radians: 0.3)).transformPoint(point)
    let viaComposed = composed.transformPoint(point)

    #expect(close(viaComposed.x, sequential.x + 1, 1e-4))
    #expect(close(viaComposed.y, sequential.y + 1, 1e-4))
}

// MARK: - determinants and inverses

@Test func determinantsMatchKnownValues() {
    #expect(close(Matrix<Dim2, Dim2>(m11: 2, m12: 0, m21: 0, m22: 3).determinant, 6))
    #expect(close(Matrix<Dim3, Dim3>(
        m11: 2, m12: 0, m13: 0,
        m21: 0, m22: 3, m23: 0,
        m31: 0, m32: 0, m33: 4
    ).determinant, 24))
}

@Test func inverseRoundTripsForEverySize() {
    let two = Matrix<Dim2, Dim2>(m11: 2, m12: 0.5, m21: -1, m22: 3)
    #expect(isIdentity(two * two.inverted()!))

    let three = Matrix<Dim3, Dim3>.trs(
        translation: Vector2D(4, -2),
        rotation: Angle(radians: 0.6),
        scale: Vector2D(2, 3)
    )
    #expect(isIdentity(three * three.inverted()!))

    let four = Matrix<Dim4, Dim4>.trs(
        translation: Vector3D(1, 2, 3),
        rotation: Quaternion(x: 0, y: 0, z: 0.3826834, w: 0.9238795),
        scale: Vector3D(2, 2, 2)
    )
    #expect(isIdentity(four * four.inverted()!))
}

@Test func singularMatricesHaveNoInverse() {
    let flat = Matrix<Dim3, Dim3>(
        m11: 1, m12: 2, m13: 3,
        m21: 2, m22: 4, m23: 6,
        m31: 0, m32: 0, m33: 1
    )
    #expect(flat.determinant == 0)
    #expect(flat.inverted() == nil)
}

// MARK: - identity and compound assignment

@Test func identityIsNeutralAndDetected() {
    let identity = Matrix<Dim3, Dim3>.identity

    #expect(identity.isIdentity)
    #expect(Matrix<Dim3, Dim3>.zero.isIdentity == false)

    let point = Vector2D(7, -3)
    let moved = identity.transformPoint(point)
    #expect(moved == point)
}

@Test func compoundAssignmentMatchesMultiplication() {
    var m = Matrix<Dim3, Dim3>.translation(Vector2D(1, 2))
    let rhs = Matrix<Dim3, Dim3>.scale(Vector2D(3, 3))
    m *= rhs

    let expected = Matrix<Dim3, Dim3>.translation(Vector2D(1, 2))
        * Matrix<Dim3, Dim3>.scale(Vector2D(3, 3))

    #expect(m == expected)
}

@Test func twoByTwoHelpersWork() {
    let m = Matrix<Dim2, Dim2>.rotation(radians: Float.pi / 2)
    let v = m.multiply(SIMD2<Float>(1, 0))

    #expect(close(v.x, 0, 1e-4))
    #expect(close(v.y, 1, 1e-4))
    #expect(close(Matrix<Dim2, Dim2>.scale(SIMD2<Float>(2, 4))[1, 1], 4))
}

// MARK: - 4×4 helpers

@Test func orthographicMapsRangeToClipSpace() {
    let m = Matrix<Dim4, Dim4>.orthographic(
        left: 0, right: 10,
        bottom: 0, top: 10,
        near: 1, far: 11
    )
    let middle = m.transformPoint(Vector3D(5, 5, 1))
    let corner = m.transformPoint(Vector3D(0, 0, 1))

    #expect(close(middle.x, 0))
    #expect(close(middle.y, 0))
    #expect(close(corner.x, -1))
    #expect(close(corner.y, -1))
}

@Test func perspectiveKeepsRowMajorLayout() {
    let m = Matrix<Dim4, Dim4>.perspective(
        fovY: Angle(radians: Float.pi / 2),
        aspect: 1,
        near: 1,
        far: 11
    )

    #expect(close(m[0, 0], 1))
    #expect(close(m[2, 2], -1.1))
    #expect(close(m[2, 3], -1.1))
    #expect(close(m[3, 2], -1))
}

@Test func axisRotationsMatchTheirDefinitions() {
    let x = Matrix<Dim4, Dim4>.rotationX(Angle(radians: Float.pi / 2))
    let aroundX = x.transformVector(Vector3D(0, 1, 0))
    #expect(close(aroundX.y, 0, 1e-4))
    #expect(close(aroundX.z, 1, 1e-4))

    let z = Matrix<Dim4, Dim4>.rotationZ(Angle(radians: Float.pi / 2))
    let aroundZ = z.transformVector(Vector3D(1, 0, 0))
    #expect(close(aroundZ.x, 0, 1e-4))
    #expect(close(aroundZ.y, 1, 1e-4))
}

@Test func quaternionMatrixRotatesVectors() {
    // 90° around z
    let rotation = Quaternion(x: 0, y: 0, z: 0.70710678, w: 0.70710678)
    let m = Matrix<Dim4, Dim4>.rotation(rotation)
    let rotated = m.transformVector(Vector3D(1, 0, 0))

    #expect(close(rotated.x, 0, 1e-4))
    #expect(close(rotated.y, 1, 1e-4))
    #expect(close(rotated.z, 0, 1e-4))
    #expect(m.translation3D == Vector3D(0, 0, 0))
}

@Test func translation3DExtractsOffset() {
    let m = Matrix<Dim4, Dim4>.translation(Vector3D(4, 5, 6))
    let moved = m.transformPoint(Vector3D(0, 0, 0))

    #expect(moved == Vector3D(4, 5, 6))
    #expect(m.translation3D == Vector3D(4, 5, 6))
}

@Test func uniformScaleMatchesVectorScale() {
    #expect(Matrix<Dim4, Dim4>.scale(uniform: 3) == Matrix<Dim4, Dim4>.scale(Vector3D(3, 3, 3)))
}

@Test func fourByFourLerpInterpolatesElements() {
    let a = Matrix<Dim4, Dim4>.identity
    let b = Matrix<Dim4, Dim4>.scale(uniform: 3)
    let half = Matrix<Dim4, Dim4>.lerp(a, b, t: 0.5)

    #expect(close(half[0, 0], 2))
    #expect(close(half[3, 3], 1))
}

@Test func threeByThreeLerpInterpolatesElements() {
    let a = Matrix<Dim3, Dim3>.identity
    let b = Matrix<Dim3, Dim3>.scale(Vector2D(3, 3))
    let half = Matrix<Dim3, Dim3>.lerp(a, b, t: 0.5)

    #expect(close(half[0, 0], 2))
    #expect(close(half[2, 2], 1))
}

// MARK: - SIMD access

@Test func columnAndRowAccessors() {
    let m = Matrix<Dim3, Dim3>(
        m11: 1, m12: 2, m13: 3,
        m21: 4, m22: 5, m23: 6,
        m31: 7, m32: 8, m33: 9
    )

    #expect(m.column(0) == [1, 4, 7])
    #expect(m.row(0) == [1, 2, 3])
    #expect(m.columns.1 == SIMD3<Float>(2, 5, 8))
    #expect(m.rows.2 == SIMD3<Float>(7, 8, 9))
    #expect(m.toArray().count == 9)
}
