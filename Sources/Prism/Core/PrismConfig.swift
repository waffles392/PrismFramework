import Foundation
import Graphics
import Window

/// configuration for 'Prism.init(config:)'
///
/// 'PrismConfig' is the sugar over the individual
/// 'Prism' initializers; every field is also available
/// as a direct parameter
///
/// ```swift
/// let prism = Prism(config: PrismConfig(
///     title: "My Game",
///     width: 1280,
///     height: 720,
///     flags: [.vsync, .resizable, .highDPI]
/// ))
/// ```
public struct PrismConfig: Sendable {
    /// the window title
    public var title: String
    /// the window width in logical points
    public var width: Int32
    /// the window height in logical points
    public var height: Int32
    /// window creation and presentation flags
    public var flags: WindowFlags
    /// the bundle used to load assets. 'nil' uses the
    /// engine resource bundle
    public var bundle: Bundle?
    /// fixed simulation step in seconds, or 'nil' for a variable timestep
    public var fixedRate: Double?
    /// the most fixed steps run per frame (a spiral-of-death cap)
    public var maxFixedSteps: Int

    public init(
        title: String = "Prism",
        width: Int32 = 800,
        height: Int32 = 600,
        flags: WindowFlags = .recommended,
        bundle: Bundle? = nil,
        fixedRate: Double? = nil,
        maxFixedSteps: Int = 8
    ) {
        self.title = title
        self.width = width
        self.height = height
        self.flags = flags
        self.bundle = bundle
        self.fixedRate = fixedRate
        self.maxFixedSteps = maxFixedSteps
    }
}
