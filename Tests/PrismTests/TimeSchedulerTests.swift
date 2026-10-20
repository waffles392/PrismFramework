import Testing
@testable import Time

@MainActor
private final class TimerTokenBox {
    var token: TimerToken?
}

@MainActor
@Test func schedulerKeepsTimersScheduledDuringTick() {
    let scheduler = TimeScheduler()
    var events: [String] = []

    scheduler.run(after: 1) { _ in
        events.append("first")
        scheduler.run(after: 0) { _ in
            events.append("second")
        }
    }

    scheduler.tick(deltaTime: 1)
    #expect(events == ["first"])
    #expect(!scheduler.isIdle)

    scheduler.tick(deltaTime: 0.01)
    #expect(events == ["first", "second"])
    #expect(scheduler.isIdle)
}

@MainActor
@Test func schedulerHonorsCancellationBeforeTimerFires() {
    let scheduler = TimeScheduler()
    var fired = false

    let token = scheduler.run(after: 1) { _ in
        fired = true
    }
    scheduler.run(after: 0.5) { _ in
        scheduler.cancel(token)
    }

    scheduler.tick(deltaTime: 1)
    #expect(!fired)
    #expect(scheduler.isIdle)
}

@MainActor
@Test func schedulerRemovesCancelledRepeatingTimerFromPendingQueue() {
    let scheduler = TimeScheduler()
    var repeatingCount = 0

    let repeating = scheduler.run(after: 0.1, every: 0.1) { _ in
        repeatingCount += 1
    }
    scheduler.run(after: 0.2) { _ in
        scheduler.cancel(repeating)
    }

    scheduler.tick(deltaTime: 0.25)

    // the repeating timer fires twice before the one-shot cancels it
    #expect(repeatingCount == 2)
    #expect(scheduler.isIdle)
}

@MainActor
@Test func schedulerAllowsRepeatingTimerToCancelItself() {
    let scheduler = TimeScheduler()
    let box = TimerTokenBox()
    var count = 0

    box.token = scheduler.run(after: 0.5, every: 0.5) { _ in
        count += 1
        if let token = box.token {
            scheduler.cancel(token)
        }
    }

    scheduler.tick(deltaTime: 0.5)
    #expect(count == 1)
    #expect(scheduler.isIdle)
}

@MainActor
@Test func schedulerRunsEqualDeadlineTimersInInsertionOrder() {
    let scheduler = TimeScheduler()
    var order: [Int] = []

    for index in 0..<3 {
        scheduler.run(after: 1) { _ in
            order.append(index)
        }
    }

    scheduler.tick(deltaTime: 1)
    #expect(order == [0, 1, 2])
}
