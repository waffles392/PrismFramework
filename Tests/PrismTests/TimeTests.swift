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

@Test func timeClampsScaledDeltaToMaximum() {
    var current: Double = 0
    let time = Time(maximumDeltaTime: 0.1, now: { current })

    time.timeScale = 2
    current = 1
    #expect(time.update() == 0.1)
    #expect(abs(time.elapsedTime - 0.1) < 0.0001)
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

@Test func timeReportsFixedStepsWhenConfigured() {
    var current: Double = 0
    let time = Time(maximumDeltaTime: 10, fixedRate: 0.25, now: { current })

    current = 0.6
    #expect(time.update() == 0.6)
    #expect(time.fixedDeltaTime == 0.25)
    #expect(time.fixedStepCount == 2)
    #expect(abs(time.interpolationAlpha - 0.4) < 0.0001)

    current = 0.8
    #expect(abs(time.update() - 0.2) < 0.0001)
    #expect(time.fixedStepCount == 1)
    #expect(abs(time.interpolationAlpha - 0.2) < 0.0001)
}

@Test func elapsedTimeRetainsPrecisionOverLongSessions() {
    var current: Double = 0
    let time = Time(maximumDeltaTime: 1, now: { current })

    for _ in 0..<100_000 {
        current += 0.001
        _ = time.update()
    }

    #expect(abs(time.elapsedTime - 100) < 0.000001)
}

@Test func timeWithoutFixedRateRunsNoSteps() {
    var current: Double = 0
    let time = Time(maximumDeltaTime: 10, now: { current })

    current = 5
    _ = time.update()
    #expect(time.fixedDeltaTime == 0)
    #expect(time.fixedStepCount == 0)
    #expect(time.interpolationAlpha == 1)
}

@Test func timePauseDoesNotAdvanceFixedSteps() {
    var current: Double = 0
    let time = Time(maximumDeltaTime: 10, fixedRate: 0.25, now: { current })

    time.paused = true
    current = 1
    #expect(time.update() == 0)
    #expect(time.fixedStepCount == 0)
    #expect(time.interpolationAlpha == 0)

    time.reset()
    #expect(time.fixedStepCount == 0)
    #expect(time.interpolationAlpha == 1)
}
