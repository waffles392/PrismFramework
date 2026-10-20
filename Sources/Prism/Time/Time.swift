import Foundation

/// a frame clock backed by an injectable monotonic time source
///
/// 'Time' tracks both scaled and unscaled time: 'deltaTime' and
/// 'elapsedTime' reflect 'timeScale' (and freeze while paused),
/// while unscaledDeltaTime and 'unscaledElapsedTime' always
/// advance in real time. both variants are clamped to
/// 'maximumDeltaTime'
///
/// the time source defaults to the system's monotonic uptime clock.
/// inject another 'now' - for example a test double - to drive the
/// clock deterministically
///
/// when a 'fixedRate' is configured, 'update()' also advances a
/// 'FixedTimestep' and reports how many fixed simulation steps the run
/// loop should execute this frame ('fixedStepCount') plus the render
/// interpolation factor ('interpolationAlpha'). without a fixed rate the
/// clock is variable-timestep only
///
/// 'Time' is '@unchecked Sendable' because it is mutated only from the main
/// thread by the run loop
public final class Time: @unchecked Sendable {
    /// scaled, clamped delta time of the most recent frame
    public private(set) var deltaTime: Double = 0
    /// raw, clamped delta time of the most recent frame
    public private(set) var unscaledDeltaTime: Double = 0
    /// scaled time elapsed since the clock started or was reset
    ///
    /// the clock uses 'Double' so elapsed time stays accurate over long
    /// sessions; the engine converts deltas to 'Float' at the simulation
    /// boundary because gameplay and rendering math is Float
    public private(set) var elapsedTime: Double = 0
    /// raw time elapsed since the clock started or was reset
    public private(set) var unscaledElapsedTime: Double = 0
    /// the number of frames observed by 'update()'
    public private(set) var frameCount: Int = 0
    /// zero-based index of the most recent frame
    ///
    /// equals 'frameCount - 1' after an 'update()', and stays at zero
    /// before the first update
    public private(set) var frameIndex: Int = 0

    /// seconds per fixed simulation step, or zero when no fixed rate is set
    public private(set) var fixedDeltaTime: Double = 0
    /// the number of fixed steps the run loop should run this frame
    public private(set) var fixedStepCount: Int = 0
    /// the fraction of a fixed step accumulated since the last step
    ///
    /// in '[0, 1)' under a fixed rate, and '[1]' when the clock is
    /// variable-timestep. render code interpolates between the previous and
    /// current simulation states by this factor
    public private(set) var interpolationAlpha: Double = 1

    /// multiplier applied to 'deltaTime'
    public var timeScale: Double = 1
    /// when true, 'deltaTime' reports zero and scaled time freezes
    public var paused: Bool = false
    /// upper bound for a single frame's delta (guards against hitches)
    public var maximumDeltaTime: Double

    private var lastTime: Double
    /// reads the current time, in seconds; injectable for testing
    private let now: () -> Double
    /// the fixed-step accumulator, or 'nil' when variable-timestep
    private var stepper: FixedTimestep?

    public init(
        maximumDeltaTime: Double = 0.25,
        fixedRate: Double? = nil,
        maxFixedSteps: Int = 8,
        now: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime }
    ) {
        self.maximumDeltaTime = maximumDeltaTime
        self.now = now
        self.lastTime = now()

        if let fixedRate {
            self.stepper = FixedTimestep(rate: fixedRate, maxSteps: maxFixedSteps)
        }
    }

    /// advances the clock by one frame and returns the scaled delta time
    @discardableResult
    public func update() -> Double {
        let current: TimeInterval = now()
        let rawDelta = max(0, current - lastTime)
        let deltaLimit = max(0, maximumDeltaTime)

        lastTime = current
        unscaledDeltaTime = min(rawDelta, deltaLimit)
        unscaledElapsedTime += unscaledDeltaTime
        frameCount += 1
        frameIndex = frameCount - 1

        if paused {
            deltaTime = 0
        } else {
            deltaTime = min(unscaledDeltaTime * timeScale, deltaLimit)
            elapsedTime += deltaTime
        }

        advanceFixed(deltaTime: deltaTime)
        return deltaTime
    }

    /// resets the clock to the initial state
    public func reset() {
        lastTime = now()

        deltaTime = 0
        unscaledDeltaTime = 0
        elapsedTime = 0
        unscaledElapsedTime = 0
        frameCount = 0
        frameIndex = 0

        stepper?.reset()
        fixedStepCount = 0
        interpolationAlpha = 1
    }

    /// advances the fixed stepper by the frame's scaled delta and records
    /// the step count and interpolation factor for the run loop
    private func advanceFixed(deltaTime: Double) {
        guard var stepper else {
            fixedDeltaTime = 0
            fixedStepCount = 0
            interpolationAlpha = 1
            return
        }

        fixedDeltaTime = stepper.rate
        fixedStepCount = stepper.step(deltaTime: deltaTime)
        interpolationAlpha = stepper.alpha
        self.stepper = stepper
    }
}
