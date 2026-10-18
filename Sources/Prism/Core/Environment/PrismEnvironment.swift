import Foundation

/// environment-variable switches for engine-wide diagnostics and behaviour
///
/// lives in the Core module (not the 'Prism' umbrella) so the engine's own
/// subsystems can read it; the umbrella re-exports it via Core
///
/// all flags are read from the process environment once at launch:
///
/// | variable | meaning |
/// |---|---|
/// | 'PRISM_DISABLE_RASTERIZATION' | skip UI-overlay rasterization |
/// | 'PRISM_DISABLE_POSTPROCESSING' | bypass the post-processing pass |
/// | 'PRISM_FORCE_SHADER_GUARD' | validate SPIR-V before creating shaders |
/// | 'PRISM_DUMP_EVENTS' | log every dispatched engine event to stderr. |
/// | 'PRISM_LOCK_FRAMERATE' | target frame rate the run loop paces towards. |
public enum PrismEnvironment {
    private static let env: [String : String] = ProcessInfo.processInfo.environment

    private static func isEnabled(_ key: String) -> Bool {
        guard let value = env[key]?.lowercased() else { return false }
        return value == "1" || value == "true" || value == "yes"
    }

    public static var disableRasterization: Bool { isEnabled("PRISM_DISABLE_RASTERIZATION") }
    public static var disablePostProcessing: Bool { isEnabled("PRISM_DISABLE_POSTPROCESSING") }
    public static var forceShaderGuard: Bool { isEnabled("PRISM_FORCE_SHADER_GUARD") }
    public static var dumpEvents: Bool { isEnabled("PRISM_DUMP_EVENTS") }

    /// the target frame rate the run loop paces towards, if set
    public static var lockFramerate: Int? {
        env["PRISM_LOCK_FRAMERATE"].flatMap(Int.init)
    }
}
