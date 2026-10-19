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

@Test func timeAdvancesFromInjectedClock() {
    var current: Double = 100
    let time = Time(maximumDeltaTime: 10, now: { current })

    current += 0.5
    #expect(time.update() == 0.5)
    #expect(time.unscaledDeltaTime == 0.5)
    #expect(time.elapsedTime == 0.5)

    current += 0.25
    #expect(time.update() == 0.25)
    #expect(time.elapsedTime == 0.75)
}

@Test func timeScaleAndPauseLeaveUnscaledTimeAlone() {
    var current: Double = 0
    let time = Time(maximumDeltaTime: 10, now: { current })

    current = 1
    #expect(time.update() == 1)

    time.timeScale = 0.5
    current = 2
    #expect(time.update() == 0.5)
    #expect(time.unscaledDeltaTime == 1)

    time.paused = true
    current = 3
    #expect(time.update() == 0)
    #expect(time.unscaledDeltaTime == 1)
    #expect(time.elapsedTime == 1.5)
}

@Test func frameIndexIsZeroBased() {
    var current: Double = 0
    let time = Time(maximumDeltaTime: 10, now: { current })

    #expect(time.frameIndex == 0)
    #expect(time.frameCount == 0)

    current = 1
    _ = time.update()
    #expect(time.frameIndex == 0)
    #expect(time.frameCount == 1)

    current = 2
    _ = time.update()
    #expect(time.frameIndex == 1)
    #expect(time.frameCount == 2)

    time.reset()
    #expect(time.frameIndex == 0)
    #expect(time.frameCount == 0)
}
