/// GPU device capabilities and limits
///
/// SDL_GPU publishes no per-device feature or limit queries: compute
/// pipelines, storage buffers and indirect draws are part of the base API and
/// are present on every backend, and numeric limits are not reported at all
/// these values therefore describe the SDL_GPU contract the engine relies on
/// rather than a specific adapter, and are conservative on every supported
/// backend
public struct GPUCapabilities: Sendable {
    /// largest texture edge the engine assumes (pixels)
    public let maxTextureSize: Int
    /// largest uniform buffer the engine assumes (bytes)
    public let maxUniformBufferSize: Int
    /// largest storage buffer the engine assumes (bytes)
    public let maxStorageBufferSize: Int
    /// upper bound on frames the engine will keep in flight
    public let maxFramesInFlight: Int
    /// whether compute pipelines are available
    public let supportsCompute: Bool
    /// whether storage buffers are available
    public let supportsStorageBuffers: Bool
    /// whether indirect draws are available
    public let supportsIndirectDraw: Bool
    /// frames in flight SDL is configured to allow by default
    public let preferredFramesInFlight: Int

    /// the baseline capabilities guaranteed by any SDL_GPU backend
    public static let standard = GPUCapabilities(
        maxTextureSize: 16384,
        maxUniformBufferSize: 65536,
        maxStorageBufferSize: 134_217_728,
        maxFramesInFlight: 3,
        supportsCompute: true,
        supportsStorageBuffers: true,
        supportsIndirectDraw: true,
        preferredFramesInFlight: 2
    )
}
