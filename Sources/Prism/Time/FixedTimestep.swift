/// helpers for running simulation at a fixed timestep
///
/// accumulate the scaled frame delta and ask 'step(_:deltaTime:fixed:)'
/// how many fixed updates to run this frame; the accumulator keeps
/// the remainder so no time is lost:
///
/// ```swift
/// var accumulator: Float = 0
/// func update(deltaTime: Float) {
///     let steps = FixedTimestep.step(&accumulator, deltaTime: deltaTime, fixed: 1 / 120)
///     for _ in 0..<steps { fixedUpdate(1 / 120) }
/// }
/// ```
public enum FixedTimestep {
    /// adds 'deltaTime' to 'accumulator' and returns how many
    /// fixed updates of length 'fixed' should run this frame
    /// the accumulator retains the sub-'fixed' remainder
    public static func step(
        _ accumulator: inout Float,
        deltaTime: Float,
        fixed: Float
    ) -> Int {
        precondition(fixed > 0, "Fixed timestep must be positive")
        accumulator += max(0, deltaTime)
        var count = 0
        while accumulator >= fixed {
            accumulator -= fixed
            count += 1
        }
        return count
    }
}
