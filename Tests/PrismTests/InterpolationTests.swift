import Testing
import Prism

@Test func angleInterpolationUsesShortestPath() {
    let current = Angle(degrees: 179)
    let target = Angle(degrees: -179)
    let result = Interpolation.angle(current: current, target: target, deltaTime: 0.1, speed: 100)

    #expect(abs(result.normalized.degrees) > 179)
}

@Test func interpolationDoesNotOvershootScalar() {
    let result = Interpolation.scalar(current: 0, target: 1, deltaTime: 0.1, speed: 5)
    #expect(result > 0)
    #expect(result < 1)
}
