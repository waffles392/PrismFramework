import Testing
import Prism

private let tolerance: Float = 1e-4

private func close(_ a: Vector2D, _ b: Vector2D) -> Bool {
    abs(a.x - b.x) <= tolerance && abs(a.y - b.y) <= tolerance
}

private func positions(_ vertices: [Vertex]) -> [Vector2D] {
    vertices.map(\.position)
}

// these pin the miter stroke output as it stands, so the join rework cannot
// quietly move every outline the engine draws

// MARK: - open polyline, miter

@Test func openStraightSegmentProducesOneQuad() {
    let vertices = StrokeGenerator.strokeOpenPolyline(
        [Vector2D(0, 0), Vector2D(10, 0)],
        width: 2,
        color: .white
    )

    #expect(vertices.count == 6)

    let p = positions(vertices)
    #expect(close(p[0], Vector2D(0, 1)))
    #expect(close(p[1], Vector2D(0, -1)))
    #expect(close(p[2], Vector2D(10, -1)))
    #expect(close(p[3], Vector2D(0, 1)))
    #expect(close(p[4], Vector2D(10, 1)))
    #expect(close(p[5], Vector2D(10, -1)))
}

@Test func openRightAngleKeepsMiterCorner() {
    let vertices = StrokeGenerator.strokeOpenPolyline(
        [Vector2D(0, 0), Vector2D(10, 0), Vector2D(10, 10)],
        width: 2,
        color: .white
    )

    #expect(vertices.count == 12)

    let p = positions(vertices)

    // edge 0: left[0], right[0], right[1] then left[0], left[1], right[1]
    #expect(close(p[0], Vector2D(0, 1)))
    #expect(close(p[1], Vector2D(0, -1)))
    #expect(close(p[2], Vector2D(11, -1)))
    #expect(close(p[3], Vector2D(0, 1)))
    #expect(close(p[4], Vector2D(9, 1)))
    #expect(close(p[5], Vector2D(11, -1)))

    // edge 1 shares the corner: left[1] = (9, 1), right[1] = (11, -1),
    // then the end cap at (10, 10)
    #expect(close(p[6], Vector2D(9, 1)))
    #expect(close(p[7], Vector2D(11, -1)))
    #expect(close(p[8], Vector2D(11, 10)))
    #expect(close(p[9], Vector2D(9, 1)))
    #expect(close(p[10], Vector2D(9, 10)))
    #expect(close(p[11], Vector2D(11, 10)))
}

// MARK: - closed polygon, miter

@Test func closedSquareKeepsMiterCorners() {
    let square = [
        Vector2D(0, 0),
        Vector2D(10, 0),
        Vector2D(10, 10),
        Vector2D(0, 10)
    ]
    let vertices = StrokeGenerator.strokeClosedPolygon(square, width: 2, color: .white)

    #expect(vertices.count == 24)

    let p = positions(vertices)

    // corner 0 sits at (0, 0), so its miter point is the diagonal offset
    #expect(close(p[0], Vector2D(1, 1)))
    #expect(close(p[1], Vector2D(-1, -1)))
    #expect(close(p[2], Vector2D(11, -1)))
    #expect(close(p[3], Vector2D(1, 1)))
    #expect(close(p[4], Vector2D(9, 1)))
    #expect(close(p[5], Vector2D(11, -1)))
}

@Test func miterStrokeStaysWithinTheHalfWidthLimit() {
    // a very sharp spike, miter limit 1, must not shoot off to infinity
    let vertices = StrokeGenerator.strokeOpenPolyline(
        [Vector2D(0, 0), Vector2D(10, 0), Vector2D(0.5, 0.2)],
        width: 2,
        color: .white,
        join: .miter(limit: 1)
    )

    #expect(!vertices.isEmpty)
    for vertex in vertices {
        #expect(vertex.position.x.isFinite)
        #expect(vertex.position.y.isFinite)
    }
}

// MARK: - bevel

@Test func bevelJoinBreaksTheOuterSideAndFillsTheNotch() {
    let vertices = StrokeGenerator.strokeOpenPolyline(
        [Vector2D(0, 0), Vector2D(10, 0), Vector2D(10, 10)],
        width: 2,
        color: .white,
        join: .bevel
    )

    // two edges, then one fill triangle for the corner
    #expect(vertices.count == 12 + 3)

    let p = positions(vertices)

    // the inner side still meets at the miter point, so it has no gap
    #expect(close(p[4], Vector2D(9, 1)))
    #expect(close(p[6], Vector2D(9, 1)))

    // the outer side breaks at the two edge offsets instead of the miter
    #expect(close(p[2], Vector2D(10, -1)))
    #expect(close(p[7], Vector2D(11, 0)))

    // and the notch between them is filled back to the corner point
    let fill = [p[12], p[13], p[14]]
    #expect(fill.contains { close($0, Vector2D(10, 0)) })
    #expect(fill.contains { close($0, Vector2D(10, -1)) })
    #expect(fill.contains { close($0, Vector2D(11, 0)) })
}

@Test func bevelJoinOnAClosedSquareFillsEveryCorner() {
    let square = [
        Vector2D(0, 0),
        Vector2D(10, 0),
        Vector2D(10, 10),
        Vector2D(0, 10)
    ]
    let vertices = StrokeGenerator.strokeClosedPolygon(square, width: 2, color: .white, join: .bevel)

    // four edges, then one fill triangle per corner
    #expect(vertices.count == 24 + 12)
}

// MARK: - round

@Test func roundJoinSweepsAnArcOfTheHalfWidth() {
    let corner = Vector2D(10, 0)
    let vertices = StrokeGenerator.strokeOpenPolyline(
        [Vector2D(0, 0), corner, Vector2D(10, 10)],
        width: 2,
        color: .white,
        join: .round
    )

    let fill = Array(positions(vertices)[12...])

    // a fan of triangles anchored on the corner, three vertices per step
    #expect(fill.count % 3 == 0)
    #expect(fill.count > 6)

    // every fan vertex is either the corner itself or sits on the arc
    for point in fill {
        let radius = (point - corner).length
        #expect(radius <= tolerance || abs(radius - 1) <= tolerance)
    }

    // the arc runs between the two edge offsets and bulges away from the shape
    #expect(fill.contains { close($0, Vector2D(10, -1)) })
    #expect(fill.contains { close($0, Vector2D(11, 0)) })
    for point in fill where (point - corner).length > tolerance {
        let offset = point - corner
        #expect(offset.x >= -tolerance)
        #expect(offset.y <= tolerance)
    }
}

@Test func joinStyleLeavesTheMiterOutlineUntouched() {
    let square = [
        Vector2D(0, 0),
        Vector2D(10, 0),
        Vector2D(10, 10),
        Vector2D(0, 10)
    ]
    let miter = StrokeGenerator.strokeClosedPolygon(square, width: 2, color: .white, join: .miter())
    let rounded = StrokeGenerator.strokeClosedPolygon(square, width: 2, color: .white, join: .round)

    // a miter stays exactly as it was, and a round join only adds geometry
    #expect(miter.count == 24)
    #expect(rounded.count > miter.count)

    // everything a round join adds sits on an arc of the half width
    for point in positions(rounded).dropFirst(24) {
        let nearest = square.map { (point - $0).length }.min() ?? .infinity
        #expect(nearest <= tolerance || abs(nearest - 1) <= tolerance)
    }
}

// MARK: - degenerate input

@Test func degenerateStrokesProduceNothing() {
    #expect(StrokeGenerator.strokeOpenPolyline([], width: 2, color: .white).isEmpty)
    #expect(StrokeGenerator.strokeOpenPolyline([Vector2D(1, 2)], width: 2, color: .white).isEmpty)
    #expect(
        StrokeGenerator.strokeOpenPolyline([Vector2D(1, 2), Vector2D(1, 2)], width: 2, color: .white).isEmpty
    )
    #expect(
        StrokeGenerator.strokeClosedPolygon([Vector2D(0, 0), Vector2D(1, 1)], width: 2, color: .white).isEmpty
    )
    #expect(
        StrokeGenerator.strokeClosedPolygon(
            [Vector2D(0, 0), Vector2D(10, 0), Vector2D(10, 10)],
            width: 0,
            color: .white
        ).isEmpty
    )
}
