import Foundation

/// frame-pacing math for the engine run loop
///
/// given a target frame duration and the time already
/// spent on the current frame, computes how long the
/// thread should sleep before presenting the next frame
/// the millisecond granularity of 'SDL_Delay' is fine for
/// targets up to ~120 FPS; sub-millisecond pacing is
/// not attempted
struct Pacer {
    /// the target frame rate, or 'nil' for unlimited
    let targetFPS: Int?

    init(targetFPS: Int?) {
        self.targetFPS = targetFPS
    }

    /// whether pacing is active
    var isActive: Bool {
        targetFPS != nil && targetFPS! > 0
    }

    /// the duration of one frame at the target rate
    var frameDuration: Float {
        1 / Float(targetFPS ?? 1)
    }

    /// the number of milliseconds to sleep before the next
    /// frame. returns '0' when the frame already consumed
    /// its entire duration (no catch-up sleep)
    func remainingDelay(frameDuration: Float, elapsed: Float) -> UInt32 {
        let remaining = frameDuration - elapsed
        return remaining > 0 ? UInt32(remaining * 1000) : 0
    }
}
