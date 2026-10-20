/// a handle returned by 'TimeScheduler.run(after:every:)'
///
/// pass the token back to 'TimeScheduler.cancel(_:)' to stop the
/// timer. tokens are value types: they identify a timer by its
/// ID and do not keep the scheduler alive
public struct TimerToken: Hashable {
    let id: UInt64

    /// creates a token referring to the timer with 'id' on a
    /// scheduler. created by 'TimeScheduler'; not meant to be
    /// constructed directly
    public init(id: UInt64) {
        self.id = id
    }
}

/// a one-shot and repeating timer queue driven by scaled engine
/// time. timers only advance while the engine is unpaused -
/// 'TimeScheduler.tick(deltaTime:)' receives the scaled delta
/// time from 'Time', so a paused or scaled-down clock slows or
/// stops timers accordingly
///
/// ```swift
/// let scheduler = TimeScheduler()
/// scheduler.run(after: 1.0) { tick in
///     print("fired once after one second")
/// }
/// scheduler.run(after: 0.5, every: 2.0) { tick in
///     print("repeating, fired \(tick) times")
/// }
/// scheduler.tick(deltaTime: frameDelta)   // called once per frame
/// ```
@MainActor
public final class TimeScheduler {
    private struct Timer {
        let id: UInt64
        /// seconds remaining until the next fire
        var deadline: Double
        /// repeating interval; '0' means one-shot
        let interval: Double
        /// number of times the timer has fired
        var tick: Int
        let handler: @MainActor (Int) -> Void
    }

    private var timers: [Timer] = []
    /// IDs cancelled while a handler was executing; compacted on
    /// the next 'tick(deltaTime:)' so a handler can cancel itself
    private var cancelledIDs: Set<UInt64> = []
    /// prevents a handler from re-entering 'tick(deltaTime:)'
    private var isTicking = false
    private var nextID: UInt64 = 0

    public init() {}

    /// schedules 'handler' to fire after 'delay' seconds of
    /// (scaled, unpaused) engine time. with 'interval > 0' the
    /// handler repeats every 'interval' seconds after the first
    /// fire. the handler receives 'tick' - the number of times
    /// the timer has fired
    ///
    /// - Returns: A token that cancels the timer
    @discardableResult
    public func run(
        after delay: Double,
        every interval: Double = 0,
        _ handler: @escaping @MainActor (Int) -> Void
    ) -> TimerToken {
        let id = nextID
        nextID &+= 1
        timers.append(
            Timer(
                id: id,
                deadline: max(0, delay),
                interval: max(0, interval),
                tick: 0,
                handler: handler
            )
        )
        return TimerToken(id: id)
    }

    /// cancels the timer identified by 'token', if it is still
    /// pending. safe to call from inside a handler
    public func cancel(_ token: TimerToken) {
        cancelledIDs.insert(token.id)
        timers.removeAll { $0.id == token.id }
    }

    /// whether no timers are pending
    public var isIdle: Bool {
        timers.isEmpty
    }

    /// advances every pending timer by 'deltaTime' seconds,
    /// firing timers whose deadline passes. A repeating timer
    /// whose interval divides the frame delta fires more than
    /// once. does nothing when 'deltaTime <= 0' (pause-safe)
    ///
    /// timers scheduled from inside a handler are kept and begin
    /// on the next tick. re-entrant calls to 'tick(deltaTime:)'
    /// are ignored
    public func tick(deltaTime: Double) {
        guard deltaTime > 0, !isTicking else { return }
        isTicking = true
        defer { isTicking = false }

        // fire order: earliest deadline first, then insertion order.
        // IDs increase monotonically, so sorting by ID makes equal
        // deadlines deterministic instead of relying on sort stability
        let scheduledIDs = Set(timers.map(\.id))
        let ordered = timers.sorted {
            if $0.deadline == $1.deadline {
                return $0.id < $1.id
            }
            return $0.deadline < $1.deadline
        }
        var remaining: [Timer] = []

        for var timer in ordered {
            if cancelledIDs.contains(timer.id) { continue }

            timer.deadline -= deltaTime
            guard timer.deadline <= 0 else {
                remaining.append(timer)
                continue
            }

            // fire; a repeating timer may fire multiple times
            // when a frame delta spans several intervals
            repeat {
                timer.tick += 1
                timer.handler(timer.tick)
                timer.deadline += timer.interval
            } while timer.interval > 0 && timer.deadline <= 0

            if timer.interval > 0, !cancelledIDs.contains(timer.id) {
                remaining.append(timer)
            }
        }

        // timers created by a handler are not in 'ordered'; keep them.
        // cancel() removes from 'timers', so a timer that was cancelled
        // during this tick is not restored here either
        let addedDuringTick = timers.filter { !scheduledIDs.contains($0.id) }
        timers = remaining.filter { !cancelledIDs.contains($0.id) } + addedDuringTick
        cancelledIDs.removeAll(keepingCapacity: true)
    }
}
