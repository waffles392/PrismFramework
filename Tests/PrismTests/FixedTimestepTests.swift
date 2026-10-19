import Testing
@testable import Time

@Test func fixedTimestepAccumulatesSubStepRemainder() {
    var clock = FixedTimestep(rate: 0.25)

    #expect(clock.step(deltaTime: 0.1) == 0)
    #expect(abs(clock.alpha - 0.4) < 0.0001)

    #expect(clock.step(deltaTime: 0.1) == 0)
    #expect(abs(clock.alpha - 0.8) < 0.0001)

    #expect(clock.step(deltaTime: 0.1) == 1)
    #expect(abs(clock.alpha - 0.2) < 0.0001)
}

@Test func fixedTimestepRunsExactMultiplesWithZeroAlpha() {
    var clock = FixedTimestep(rate: 0.25)

    #expect(clock.step(deltaTime: 0.5) == 2)
    #expect(clock.alpha == 0)
}

@Test func fixedTimestepCapsStepsAndDropsBacklog() {
    var clock = FixedTimestep(rate: 0.25, maxSteps: 2)

    // one full second is four steps of work, but the cap is two
    #expect(clock.step(deltaTime: 1.0) == 2)
    // the backlog is dropped, leaving a clean remainder below one step
    #expect(clock.alpha == 0)

    // and the clock keeps working from there
    #expect(clock.step(deltaTime: 0.125) == 0)
    #expect(abs(clock.alpha - 0.5) < 0.0001)
}

@Test func fixedTimestepIgnoresZeroAndNegativeDelta() {
    var clock = FixedTimestep(rate: 0.25)

    #expect(clock.step(deltaTime: 0) == 0)
    #expect(clock.step(deltaTime: -5) == 0)
    #expect(clock.alpha == 0)

    #expect(clock.step(deltaTime: 0.3) == 1)
    #expect(abs(clock.alpha - 0.05 / 0.25) < 0.0001)
}

@Test func fixedTimestepAlphaStaysInUnitRange() {
    var clock = FixedTimestep(rate: 1.0 / 120)

    for _ in 0..<1000 {
        _ = clock.step(deltaTime: 0.016)
        #expect(clock.alpha >= 0)
        #expect(clock.alpha < 1)
    }
}

@Test func fixedTimestepResetClearsAccumulator() {
    var clock = FixedTimestep(rate: 0.25)

    _ = clock.step(deltaTime: 0.1)
    #expect(clock.alpha > 0)

    clock.reset()
    #expect(clock.alpha == 0)
}
