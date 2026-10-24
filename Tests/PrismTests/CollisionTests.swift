import Testing
@testable import Math

// collision normals point in the direction that pushes the first shape away from
// the second

private func isClose(_ lhs: Vector2D, _ rhs: Vector2D, tolerance: Float = 0.0001) -> Bool {
    abs(lhs.x - rhs.x) <= tolerance && abs(lhs.y - rhs.y) <= tolerance
}

private func isClose(_ lhs: Float, _ rhs: Float, tolerance: Float = 0.0001) -> Bool {
    abs(lhs - rhs) <= tolerance
}

// MARK: - queries

@Test func circleCircleReportsPushDirection() {
    let a = CollisionCircle(center: .zero, radius: 1)
    let b = CollisionCircle(center: Vector2D(1.5, 0), radius: 1)

    let result = Collision.circleCircle(a, b)

    #expect(result.collided)
    #expect(isClose(result.penetration, 0.5))
    #expect(isClose(result.normal, Vector2D(-1, 0)))
    #expect(isClose(result.contactPoint, Vector2D(1, 0)))
}

@Test func circleCircleRejectsSeparatedCircles() {
    let a = CollisionCircle(center: .zero, radius: 1)
    let b = CollisionCircle(center: Vector2D(2, 0), radius: 1)

    #expect(!Collision.circleCircle(a, b).collided)
}

@Test func circleAABBReportsPushDirection() {
    let circle = CollisionCircle(center: .zero, radius: 1)
    let aabb = CollisionAABB(min: Vector2D(0.5, -1), max: Vector2D(2, 1))

    let result = Collision.circleAABB(circle, aabb)

    #expect(result.collided)
    #expect(isClose(result.penetration, 0.5))
    #expect(isClose(result.normal, Vector2D(-1, 0)))
    #expect(isClose(result.contactPoint, Vector2D(1, 0)))
}

@Test func circleAABBPushesOutOfNearestFaceWhenCenterIsInside() {
    let circle = CollisionCircle(center: Vector2D(1, 0.5), radius: 0.25)
    let aabb = CollisionAABB(min: .zero, max: Vector2D(2, 2))

    let result = Collision.circleAABB(circle, aabb)

    #expect(result.collided)
    #expect(isClose(result.penetration, 0.75))
    #expect(isClose(result.normal, Vector2D(0, -1)))
    #expect(isClose(result.contactPoint, Vector2D(1, 0)))
}

@Test func circleRectBoundaryUsesYDownSides() {
    let boundaryMin = Vector2D.zero
    let boundaryMax = Vector2D(10, 10)

    let top = Collision.circleRectBoundary(
        CollisionCircle(center: Vector2D(1, 0.5), radius: 1),
        boundaryMin: boundaryMin,
        boundaryMax: boundaryMax
    )
    #expect(top.boundarySide == .top)
    #expect(isClose(top.normal, Vector2D(0, 1)))
    #expect(isClose(top.penetration, 0.5))

    let bottom = Collision.circleRectBoundary(
        CollisionCircle(center: Vector2D(1, 9.5), radius: 1),
        boundaryMin: boundaryMin,
        boundaryMax: boundaryMax
    )
    #expect(bottom.boundarySide == .bottom)
    #expect(isClose(bottom.normal, Vector2D(0, -1)))
    #expect(isClose(bottom.penetration, 0.5))

    let left = Collision.circleRectBoundary(
        CollisionCircle(center: Vector2D(0.5, 1), radius: 1),
        boundaryMin: boundaryMin,
        boundaryMax: boundaryMax
    )
    #expect(left.boundarySide == .left)
    #expect(isClose(left.normal, Vector2D(1, 0)))

    let right = Collision.circleRectBoundary(
        CollisionCircle(center: Vector2D(9.5, 1), radius: 1),
        boundaryMin: boundaryMin,
        boundaryMax: boundaryMax
    )
    #expect(right.boundarySide == .right)
    #expect(isClose(right.normal, Vector2D(-1, 0)))
}

@Test func aabbBoundaryUsesYDownSides() {
    let boundaryMin = Vector2D.zero
    let boundaryMax = Vector2D(10, 10)

    let top = Collision.aabbBoundary(
        CollisionAABB(min: Vector2D(1, -0.5), max: Vector2D(2, 0.5)),
        boundaryMin: boundaryMin,
        boundaryMax: boundaryMax
    )
    #expect(top.boundarySide == .top)
    #expect(isClose(top.normal, Vector2D(0, 1)))

    let bottom = Collision.aabbBoundary(
        CollisionAABB(min: Vector2D(1, 9.5), max: Vector2D(2, 10.5)),
        boundaryMin: boundaryMin,
        boundaryMax: boundaryMax
    )
    #expect(bottom.boundarySide == .bottom)
    #expect(isClose(bottom.normal, Vector2D(0, -1)))
}

@Test func circularBoundaryUsesYDownSides() {
    let top = Collision.circleBoundary(
        CollisionCircle(center: Vector2D(0, -11), radius: 1),
        boundaryCenter: .zero,
        boundaryRadius: 10
    )
    #expect(top.boundarySide == .top)
    #expect(isClose(top.normal, Vector2D(0, 1)))
    #expect(isClose(top.penetration, 2))

    let bottom = Collision.circleBoundary(
        CollisionCircle(center: Vector2D(0, 11), radius: 1),
        boundaryCenter: .zero,
        boundaryRadius: 10
    )
    #expect(bottom.boundarySide == .bottom)
    #expect(isClose(bottom.normal, Vector2D(0, -1)))
}

// MARK: - response

@Test func resolveBoundaryReflectsOutwardVelocity() {
    let result = Collision.circleRectBoundary(
        CollisionCircle(center: Vector2D(5, 0.5), radius: 1),
        boundaryMin: .zero,
        boundaryMax: Vector2D(10, 10)
    )
    var position = Vector2D(5, 0.5)
    var velocity = Vector2D(0, -2)

    CollisionResponse.resolveBoundary(
        position: &position,
        velocity: &velocity,
        result: result,
        restitution: 1
    )

    #expect(isClose(position, Vector2D(5, 1)))
    #expect(isClose(velocity, Vector2D(0, 2)))
}

@Test func resolveBoundaryLeavesInwardVelocityAlone() {
    let result = Collision.circleRectBoundary(
        CollisionCircle(center: Vector2D(5, 0.5), radius: 1),
        boundaryMin: .zero,
        boundaryMax: Vector2D(10, 10)
    )
    var position = Vector2D(5, 0.5)
    var velocity = Vector2D(0, 2)

    CollisionResponse.resolveBoundary(
        position: &position,
        velocity: &velocity,
        result: result,
        restitution: 1
    )

    #expect(isClose(position, Vector2D(5, 1)))
    #expect(isClose(velocity, Vector2D(0, 2)))
}

@Test func resolveCircleCircleSeparatesAndExchangesVelocity() {
    let a = CollisionCircle(center: .zero, radius: 1)
    let b = CollisionCircle(center: Vector2D(1.5, 0), radius: 1)
    let result = Collision.circleCircle(a, b)
    var positionA = Vector2D.zero
    var velocityA = Vector2D(1, 0)
    var positionB = Vector2D(1.5, 0)
    var velocityB = Vector2D.zero

    CollisionResponse.resolveCircleCircle(
        positionA: &positionA,
        velocityA: &velocityA,
        massA: 1,
        positionB: &positionB,
        velocityB: &velocityB,
        massB: 1,
        result: result,
        restitution: 1
    )

    #expect(isClose(positionA, Vector2D(-0.25, 0)))
    #expect(isClose(positionB, Vector2D(1.75, 0)))
    #expect(isClose(velocityA, .zero))
    #expect(isClose(velocityB, Vector2D(1, 0)))
}

@Test func resolveCircleCircleTreatsZeroMassAsStatic() {
    let a = CollisionCircle(center: .zero, radius: 1)
    let b = CollisionCircle(center: Vector2D(1.5, 0), radius: 1)
    let result = Collision.circleCircle(a, b)
    var positionA = Vector2D.zero
    var velocityA = Vector2D(1, 0)
    var positionB = Vector2D(1.5, 0)
    var velocityB = Vector2D.zero

    CollisionResponse.resolveCircleCircle(
        positionA: &positionA,
        velocityA: &velocityA,
        massA: 1,
        positionB: &positionB,
        velocityB: &velocityB,
        massB: 0,
        result: result,
        restitution: 1
    )

    #expect(isClose(positionA, Vector2D(-0.5, 0)))
    #expect(isClose(positionB, Vector2D(1.5, 0)))
    #expect(isClose(velocityA, Vector2D(-1, 0)))
    #expect(isClose(velocityB, .zero))
}

@Test func resolveCircleCircleDoesNothingForTwoStaticBodies() {
    let a = CollisionCircle(center: .zero, radius: 1)
    let b = CollisionCircle(center: Vector2D(1.5, 0), radius: 1)
    let result = Collision.circleCircle(a, b)
    var positionA = Vector2D.zero
    var velocityA = Vector2D(1, 0)
    var positionB = Vector2D(1.5, 0)
    var velocityB = Vector2D.zero

    CollisionResponse.resolveCircleCircle(
        positionA: &positionA,
        velocityA: &velocityA,
        massA: 0,
        positionB: &positionB,
        velocityB: &velocityB,
        massB: 0,
        result: result,
        restitution: 1
    )

    #expect(isClose(positionA, .zero))
    #expect(isClose(positionB, Vector2D(1.5, 0)))
    #expect(isClose(velocityA, Vector2D(1, 0)))
    #expect(isClose(velocityB, .zero))
}
