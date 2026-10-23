import Prism
import Testing

private let epsilon: Float = 1e-4

private func close(_ a: Float, _ b: Float) -> Bool {
    abs(a - b) <= epsilon
}

private func close(_ a: Angle, _ b: Angle) -> Bool {
    close(a.radians, b.radians)
}

/// compares directions, so 180 and -180 degrees count as equal
private func closeModuloTurn(_ a: Angle, _ b: Angle) -> Bool {
    let twoPi = 2 * Float.pi
    var delta = (a.radians - b.radians).truncatingRemainder(dividingBy: twoPi)
    if delta > Float.pi {
        delta -= twoPi
    } else if delta < -Float.pi {
        delta += twoPi
    }
    return abs(delta) <= epsilon
}

private func close(_ a: Vector2D, _ b: Vector2D) -> Bool {
    close(a.x, b.x) && close(a.y, b.y)
}

@Test func angleConvertsDegreesAndRadians() {
    let angle = Angle(degrees: 45)

    #expect(close(angle.radians, .pi / 4))
    #expect(close(angle.degrees, 45))
    #expect(close(Angle(radians: .pi).degrees, 180))
}

@Test func normalizedAngleUsesSignedHalfTurnRange() {
    #expect(closeModuloTurn(Angle(degrees: 450).normalized, Angle(degrees: 90)))
    #expect(closeModuloTurn(Angle(degrees: -450).normalized, Angle(degrees: -90)))
    #expect(closeModuloTurn(Angle(degrees: 540).normalized, Angle(degrees: 180)))
    #expect(closeModuloTurn(Angle(degrees: -540).normalized, Angle(degrees: 180)))
}

@Test func angleProducesUnitDirectionVectors() {
    #expect(close(Angle.zero.vector, .unitX))
    #expect(close(Angle.quarterTurn.vector, .unitY))
    #expect(close(Angle.halfTurn.vector, Vector2D(-1, 0)))
    #expect(close(Angle.full.vector, .unitX))
}

@Test func vectorAngleRoundTripsCardinalDirections() {
    #expect(close(Vector2D.unitX.angle, .zero))
    #expect(close(Vector2D.unitY.angle, .quarterTurn))
    #expect(close(Vector2D(-1, 0).angle, .halfTurn))
}

@Test func angleArithmeticAndComparison() {
    #expect(close(Angle(degrees: 30) + Angle(degrees: 60), Angle(degrees: 90)))
    #expect(close(Angle(degrees: 90) - Angle(degrees: 30), Angle(degrees: 60)))
    #expect(close(Angle(degrees: 30) * 2, Angle(degrees: 60)))
    #expect(close(Angle(degrees: 90) / 2, Angle(degrees: 45)))
    #expect(Angle(degrees: 30) < Angle(degrees: 60))
}
