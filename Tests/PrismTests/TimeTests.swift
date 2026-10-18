import Testing
@testable import Time

@Test func timeStartsAtZero() {
    let time = Time()

    #expect(time.deltaTime == 0)
    #expect(time.elapsedTime == 0)
}

@Test func timeUpdateIsBoundedAndResettable() {
    let time = Time(maximumDeltaTime: 0)

    #expect(time.update() == 0)
    #expect(time.elapsedTime == 0)

    time.reset()
    #expect(time.deltaTime == 0)
    #expect(time.elapsedTime == 0)
}
