import Testing
@testable import Prism
@testable import Math

@Test func vectorOperations() {
    let vector = Vector2D(3, 4)

    #expect(vector.length == 5)
    #expect(vector.normalized == Vector2D(0.6, 0.8))
    #expect(vector.dot(Vector2D(2, 1)) == 10)
    let rotated = Vector2D.unitX.rotated(by: .right)
    #expect(abs(rotated.x) < 0.0001)
    #expect(abs(rotated.y - 1) < 0.0001)
}

@Test func anglesAndGeometry() {
    #expect(Angle(degrees: 180).radians == Float.pi)
    #expect(abs(Angle(degrees: 450).normalized.radians - Angle(degrees: 90).radians) < 0.0001)

    let rectangle = Rect2D(x: 0, y: 0, width: 10, height: 8)
    #expect(rectangle.contains(Vector2D(5, 4)))
    #expect(!rectangle.contains(Vector2D(11, 4)))

    let segment = LineSegment2D(start: .zero, end: Vector2D(10, 0))
    #expect(segment.closestPoint(to: Vector2D(4, 3)) == Vector2D(4, 0))
}

@Test func keysPreserveScancodes() {
    #expect(Key.w.rawValue == 26)
    #expect(Key(rawValue: 26) == .w)
    #expect(Key.letter("W") == .w)

    let unknown = Key(rawValue: 999)
    #expect(unknown == .unknown(999))
    #expect(unknown.rawValue == 999)
}
