/// a stateful fixed-timestep accumulator
///
/// feed it the (typically scaled) frame delta and it returns how many
/// fixed updates to run this frame, keeping the sub-step remainder so
/// no time is lost and the render phase can interpolate:
///
/// ```swift
/// var clock = FixedTimestep(rate: 1.0 / 120)
/// func update(deltaTime: Float) {
///     let steps = clock.step(deltaTime: deltaTime)
///     for _ in 0..<steps { fixedUpdate(clock.rate) }
///     let t = clock.alpha   // interpolate previous -> current
/// }
/// ```
///
/// a single instance is mutated in place; 'accumulator' always ends a
/// 'step' below 'rate', so 'alpha' stays in '[0, 1)'
public struct FixedTimestep {
    /// seconds per fixed step (1/120 ~= 0.00833)
    public let rate: Float
    /// the most fixed steps a single 'step(deltaTime:)' will run
    public let maxSteps: Int
    private var accumulator: Float = 0

    public init(rate: Float = 1 / 120, maxSteps: Int = 8) {
        precondition(rate > 0, "fixed rate must be positive")
        precondition(maxSteps > 0, "maxSteps must be positive")

        self.rate = rate
        self.maxSteps = maxSteps
    }

    /// adds 'deltaTime' and returns how many fixed steps to run this frame
    ///
    /// the remainder below one step is retained, so consecutive frames do
    /// not lose time. when the count reaches 'maxSteps' any backlog is
    /// dropped down to the remainder rather than spiralling
    public mutating func step(deltaTime: Float) -> Int {
        accumulator += max(0, deltaTime)
        var steps = 0

        while accumulator >= rate && steps < maxSteps {
            accumulator -= rate
            steps += 1
        }

        // if we hit the cap with backlog left, drop it rather than spiralling
        if accumulator >= rate { accumulator = accumulator.truncatingRemainder(dividingBy: rate) }
        return steps
    }

    /// the fraction of a step accumulated since the last fixed update
    ///
    /// in '[0, 1)'. render code uses it to interpolate between the previous
    /// and current simulation states
    public var alpha: Float { accumulator / rate }

    /// clears the accumulated fraction
    public mutating func reset() { accumulator = 0 }
}
