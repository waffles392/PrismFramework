import Foundation

/// a frame clock backed by the system's monotonic uptime clock
///
/// 'Time' tracks both scaled and unscaled time: 'deltaTime' and
/// 'elapsedTime' reflect 'timeScale' (and freeze while paused),
/// while unscaledDeltaTime and 'unscaledElapsedTime' always
/// advance in real time. both variants are clamped to
/// 'maximumDeltaTime'
///
/// 'Time' is '@unchecked Sendable' because it is mutated only from the main
/// thread by the run loop
public final class Time: @unchecked Sendable {
    /// scaled, clamped delta time of the most recent frame
    public private(set) var deltaTime: Float = 0
    /// raw, clamped delta time of the most recent frame
    public private(set) var unscaledDeltaTime: Float = 0
    /// scaled time elapsed since the clock started or was reset
    public private(set) var elapsedTime: Float = 0
    /// raw time elapsed since the clock started or was reset
    public private(set) var unscaledElapsedTime: Float = 0
    /// the number of frames observed by 'update()'
    public private(set) var frameCount: Int = 0

    /// multiplier applied to 'deltaTime'
    public var timeScale: Float = 1
    /// when true, 'deltaTime' reports zero and scaled time freezes
    public var paused: Bool = false
    /// upper bound for a single frame's delta (guards against hitches)
    public var maximumDeltaTime: Float

    private var lastTime: Double

    public init(maximumDeltaTime: Float = 0.25) {
        self.maximumDeltaTime = maximumDeltaTime
        self.lastTime = ProcessInfo.processInfo.systemUptime
    }

    /// advances the clock by one frame and returns the scaled delta time
    @discardableResult
    public func update() -> Float {
        let now: TimeInterval = ProcessInfo.processInfo.systemUptime
        let rawDelta: Float = Float(max(0, now - lastTime))

        lastTime = now
        unscaledDeltaTime = min(rawDelta, maximumDeltaTime)
        unscaledElapsedTime += unscaledDeltaTime
        frameCount += 1

        if paused {
            deltaTime = 0
            return 0
        }

        deltaTime = unscaledDeltaTime * timeScale
        elapsedTime += deltaTime
        return deltaTime
    }

    /// deprecated - scheduled timers are never ticked
    ///
    /// repeated callbacks are not driven by 'update()' yet, so this does nothing
    @available(*, deprecated, message: "scheduled timers are not ticked yet")
    public func every(interval: Float, callback: @escaping () -> Void) {}

    /// resets the clock to the initial state
    public func reset() {
        lastTime = ProcessInfo.processInfo.systemUptime

        deltaTime = 0
        unscaledDeltaTime = 0
        elapsedTime = 0
        unscaledElapsedTime = 0
        frameCount = 0
    }
}
