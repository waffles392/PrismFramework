import Foundation
import Math

// MARK: - Bloom

/// bloom settings
///
/// bloom is driven by authored emissive values rather than scene brightness:
/// the extractor reads the emissive buffer written by the scene pass, so a dim
/// or transparent primitive can glow. geometry with no emissive does not bloom
public struct BloomSettings: Sendable {
    public var isEnabled: Bool
    public var intensity: Float
    public var saturation: Float

    public init(
        isEnabled: Bool = false,
        intensity: Float = 0.75,
        saturation: Float = 1.1
    ) {
        self.isEnabled = isEnabled
        self.intensity = max(0, intensity)
        self.saturation = max(1, saturation)
    }
}

// MARK: - Color Grading

public struct ColorGradingSettings: Sendable {
    public var exposure: Float
    public var contrast: Float
    public var saturation: Float
    public var temperature: Float
    public var tint: Float
    public var lift: Float
    public var gamma: Float
    public var gain: Float
    public var vignette: Float

    public init(
        exposure: Float = 0,
        contrast: Float = 1.05,
        saturation: Float = 1.15,
        temperature: Float = 0,
        tint: Float = 0,
        lift: Float = 0,
        gamma: Float = 1,
        gain: Float = 1,
        vignette: Float = 0.35
    ) {
        self.exposure = exposure
        self.contrast = max(0, contrast)
        self.saturation = max(0, saturation)
        self.temperature = min(1, max(-1, temperature))
        self.tint = min(1, max(-1, tint))
        self.lift = lift
        self.gamma = max(0.001, gamma)
        self.gain = max(0, gain)
        self.vignette = min(1, max(0, vignette))
    }
}

// MARK: - VHS / Analog

public struct VHSSettings: Sendable {
    public var isEnabled: Bool
    public var scanlines: Float
    public var noise: Float
    public var chromaticAberration: Float
    public var distortion: Float

    public init(
        isEnabled: Bool = false,
        scanlines: Float = 0.06,
        noise: Float = 0.008,
        chromaticAberration: Float = 0.3,
        distortion: Float = 0.06
    ) {
        self.isEnabled = isEnabled
        self.scanlines = Self.unit(scanlines)
        self.noise = Self.unit(noise)
        self.chromaticAberration = Self.unit(chromaticAberration)
        self.distortion = Self.unit(distortion)
    }

    private static func unit(_ value: Float) -> Float {
        min(1, max(0, value))
    }
}

// MARK: - Aggregated settings

public struct PostProcessingSettings: Sendable {
    public var bloom = BloomSettings()
    public var colorGrading = ColorGradingSettings()
    public var vhs = VHSSettings()

    public init() {}
}

// MARK: - PostProcessor

@MainActor
public final class PostProcessor {

    /// when 'false', 'draw(frame:settings:elapsedTime:)'
    /// bypasses the bloom and grading pipeline and
    /// presents the scene target directly to the
    /// swapchain. wired to 'PrismEnvironment.disablePostProcessing'
    public var isEnabled: Bool = true

    private let renderer: Renderer

    private let fullscreenVertices: [Vertex] = [
        Vertex(
            position: Vector2D(-1, -1),
            color: SIMD4(1, 1, 1, 1)
        ),
        Vertex(
            position: Vector2D(3, -1),
            color: SIMD4(1, 1, 1, 1)
        ),
        Vertex(
            position: Vector2D(-1, 3),
            color: SIMD4(1, 1, 1, 1)
        )
    ]

    // MARK: - Surfaces (shader-backed materials, no textures)

    private let extractSurface: Surface
    private let blurSurface: Surface
    private let presentSurface: Surface

    // MARK: - Meshes (one per render pass; each mesh holds its own textures)

    private let extractMesh: Mesh

    private let hBlur0Mesh: Mesh
    private let vBlur0Mesh: Mesh

    private let hBlur1Mesh: Mesh
    private let vBlur1Mesh: Mesh

    private let hBlur2Mesh: Mesh
    private let vBlur2Mesh: Mesh

    private let presentMesh: Mesh

    // MARK: - Render targets

    private var sceneTarget: RenderTarget?

    /// emissive buffer written alongside the scene target; the bloom extractor
    /// reads this instead of the scene colour
    private var emissiveTarget: RenderTarget?

    private var extractTarget: RenderTarget?

    private var hBlur0Target: RenderTarget?
    private var bloom0Target: RenderTarget?

    private var hBlur1Target: RenderTarget?
    private var bloom1Target: RenderTarget?

    private var hBlur2Target: RenderTarget?
    private var bloom2Target: RenderTarget?

    private var targetSize = SIMD2<UInt32>.zero

    // MARK: - Init

    public init(renderer: Renderer) throws {
        self.renderer = renderer

        let device = renderer.device
        let sampler = renderer.linearSampler

        let vertexShader = ShaderLoader.load("fullscreen.vert.spv")
        let extractShader = ShaderLoader.load("bloom_extract.frag.spv")
        let blurShader = ShaderLoader.load("bloom_blur.frag.spv")
        let presentShader = ShaderLoader.load("present.frag.spv")

        let zeroUniforms = Self.uniforms(.zero, .zero, .zero, .zero)

        // surfaces: pure shader-backed materials; samplerCount declares
        // how many textures the fragment shader expects
        extractSurface = Surface(
            vertexShader: vertexShader,
            fragmentShader: extractShader,
            samplerCount: 1
        )

        blurSurface = Surface(
            vertexShader: vertexShader,
            fragmentShader: blurShader,
            fragmentUniforms: zeroUniforms,
            samplerCount: 1
        )

        presentSurface = Surface(
            vertexShader: vertexShader,
            fragmentShader: presentShader,
            fragmentUniforms: zeroUniforms,
            samplerCount: 4
        )

        // each mesh is a separate draw call with its own texture bindings
        // textures are empty until the first frame when render targets are created
        // pipelines are created lazily per color-target format by 'Mesh'
        extractMesh = try Mesh(device: device, sampler: sampler, vertices: fullscreenVertices, surface: extractSurface)
        hBlur0Mesh  = try Mesh(device: device, sampler: sampler, vertices: fullscreenVertices, surface: blurSurface)
        vBlur0Mesh  = try Mesh(device: device, sampler: sampler, vertices: fullscreenVertices, surface: blurSurface)
        hBlur1Mesh  = try Mesh(device: device, sampler: sampler, vertices: fullscreenVertices, surface: blurSurface)
        vBlur1Mesh  = try Mesh(device: device, sampler: sampler, vertices: fullscreenVertices, surface: blurSurface)
        hBlur2Mesh  = try Mesh(device: device, sampler: sampler, vertices: fullscreenVertices, surface: blurSurface)
        vBlur2Mesh  = try Mesh(device: device, sampler: sampler, vertices: fullscreenVertices, surface: blurSurface)
        presentMesh = try Mesh(device: device, sampler: sampler, vertices: fullscreenVertices, surface: presentSurface)
    }

    // MARK: - Public API

    /// the offscreen scene target, resized to match the frame if needed
    ///
    /// throws if the target could not be allocated; the caller skips the frame
    public func sceneTarget(width: UInt32, height: UInt32) throws -> RenderTarget {
        try resizeIfNeeded(width: width, height: height)

        guard let target = sceneTarget else {
            throw GPUError.resourceCreationFailed(
                "scene target unavailable for a \(width)x\(height) frame"
            )
        }

        return target
    }

    /// the emissive buffer written alongside the scene target
    ///
    /// bind this as the second colour target of the scene pass. the bloom
    /// extractor reads it, so bloom comes from authored emissive values rather
    /// than scene brightness
    public func emissiveTarget(width: UInt32, height: UInt32) throws -> RenderTarget {
        try resizeIfNeeded(width: width, height: height)

        guard let target = emissiveTarget else {
            throw GPUError.resourceCreationFailed(
                "emissive target unavailable for a \(width)x\(height) frame"
            )
        }

        return target
    }

    public func prepare(frame: Frame) {
        for mesh in allMeshes {
            try? mesh.prepare(commandBuffer: frame.commandBuffer)
        }
    }

    public func draw(
        frame: Frame,
        settings: PostProcessingSettings,
        elapsedTime: Float
    ) {
        guard
            let sceneTarget,
            let emissiveTarget,
            let extractTarget,

            let hBlur0Target,
            let bloom0Target,

            let hBlur1Target,
            let bloom1Target,

            let hBlur2Target,
            let bloom2Target
        else {
            return
        }

        // direct blit: present the scene target
        // unmodified (post-processing disabled)
        if !isEnabled {
            presentMesh.textures = [
                sceneTarget, sceneTarget,
                sceneTarget, sceneTarget
            ]
            presentSurface.fragmentUniforms = Self.uniforms(
                SIMD4(0, 1, 1, 0),
                SIMD4(0, 0, 0, 0),
                SIMD4(0, 0, 0, 1),
                SIMD4(1, 0, 0, 1)
            )

            guard let output = try? frame.beginRenderPass() else { return }
            presentMesh.draw(in: output)
            output.end()
            return
        }

        // texel sizes for each blur step, read back from the targets that
        // 'resizeIfNeeded' allocated so the two can never drift apart
        let w0 = extractTarget.width
        let h0 = extractTarget.height

        let w1 = bloom0Target.width
        let h1 = bloom0Target.height

        let w2 = bloom1Target.width
        let h2 = bloom1Target.height

        let bloomEnabled = settings.bloom.isEnabled && settings.bloom.intensity > 0

        // MARK: - Bloom Pipeline

        if bloomEnabled {

            // 1. downsample the emissive buffer into the bloom chain
            extractMesh.textures = [emissiveTarget]

            if let pass = try? frame.beginRenderPass(to: extractTarget) {
                extractMesh.draw(in: pass)
                pass.end()
            }

            // 2. bloom level 0 (1/4 scale)
            blurSurface.fragmentUniforms = Self.uniforms(
                SIMD4(1.0 / Float(w0), 0, 1.0, 0),
                .zero, .zero, .zero
            )
            hBlur0Mesh.textures = [extractTarget]

            if let pass = try? frame.beginRenderPass(to: hBlur0Target) {
                hBlur0Mesh.draw(in: pass)
                pass.end()
            }

            blurSurface.fragmentUniforms = Self.uniforms(
                SIMD4(0, 1.0 / Float(h0), 1.0, 0),
                .zero, .zero, .zero
            )
            vBlur0Mesh.textures = [hBlur0Target]

            if let pass = try? frame.beginRenderPass(to: bloom0Target) {
                vBlur0Mesh.draw(in: pass)
                pass.end()
            }

            // 3. bloom level 1 (1/8 scale)
            blurSurface.fragmentUniforms = Self.uniforms(
                SIMD4(1.0 / Float(w1), 0, 1.0, 0),
                .zero, .zero, .zero
            )
            hBlur1Mesh.textures = [bloom0Target]

            if let pass = try? frame.beginRenderPass(to: hBlur1Target) {
                hBlur1Mesh.draw(in: pass)
                pass.end()
            }

            blurSurface.fragmentUniforms = Self.uniforms(
                SIMD4(0, 1.0 / Float(h1), 1.0, 0),
                .zero, .zero, .zero
            )
            vBlur1Mesh.textures = [hBlur1Target]

            if let pass = try? frame.beginRenderPass(to: bloom1Target) {
                vBlur1Mesh.draw(in: pass)
                pass.end()
            }

            // 4. bloom level 2 (1/16 scale)
            blurSurface.fragmentUniforms = Self.uniforms(
                SIMD4(1.0 / Float(w2), 0, 1.0, 0),
                .zero, .zero, .zero
            )
            hBlur2Mesh.textures = [bloom1Target]

            if let pass = try? frame.beginRenderPass(to: hBlur2Target) {
                hBlur2Mesh.draw(in: pass)
                pass.end()
            }

            blurSurface.fragmentUniforms = Self.uniforms(
                SIMD4(0, 1.0 / Float(h2), 1.0, 0),
                .zero, .zero, .zero
            )
            vBlur2Mesh.textures = [hBlur2Target]

            if let pass = try? frame.beginRenderPass(to: bloom2Target) {
                vBlur2Mesh.draw(in: pass)
                pass.end()
            }

            // 5. present - combine scene with all bloom levels
            presentMesh.textures = [sceneTarget, bloom0Target, bloom1Target, bloom2Target]

        } else {
            // no bloom - feed the scene target into all sampler slots
            presentMesh.textures = [sceneTarget, sceneTarget, sceneTarget, sceneTarget]
        }

        // MARK: - Final Presentation pass

        let grade = settings.colorGrading
        let vhs = settings.vhs

        presentSurface.fragmentUniforms = Self.uniforms(
            SIMD4(grade.exposure, grade.saturation, grade.contrast, elapsedTime),
            SIMD4(
                vhs.isEnabled ? vhs.scanlines : 0,
                vhs.isEnabled ? vhs.noise : 0,
                vhs.isEnabled ? vhs.chromaticAberration : 0,
                bloomEnabled ? settings.bloom.intensity : 0
            ),
            SIMD4(grade.temperature, grade.tint, grade.lift, grade.gamma),
            SIMD4(
                grade.gain,
                vhs.isEnabled ? vhs.distortion : 0,
                grade.vignette,
                bloomEnabled ? settings.bloom.saturation : 1
            )
        )

        guard let output = try? frame.beginRenderPass() else { return }
        presentMesh.draw(in: output)
        output.end()
    }

    // MARK: - Private

    private var allMeshes: [Mesh] {
        [
            extractMesh,
            hBlur0Mesh, vBlur0Mesh,
            hBlur1Mesh, vBlur1Mesh,
            hBlur2Mesh, vBlur2Mesh,
            presentMesh
        ]
    }

    private func resizeIfNeeded(width: UInt32, height: UInt32) throws {
        guard width > 0, height > 0 else { return }
        guard targetSize.x != width || targetSize.y != height else { return }

        // bloom chain at 1/4 resolution (was 1/2) - 4x fewer fragments
        let w0 = max(1, width / 4)
        let h0 = max(1, height / 4)

        let w1 = max(1, width / 8)
        let h1 = max(1, height / 8)

        let w2 = max(1, width / 16)
        let h2 = max(1, height / 16)

        // every target is built before any is committed, so a failed allocation
        // leaves the previous chain (and 'targetSize') intact to retry next frame

        // scene target stays HDR for bloom extraction
        let newScene = try renderer.createRenderTarget(width: width, height: height, format: .rgba16Float)
        // emissive buffer shares the scene resolution and HDR format; the bloom
        // extractor is the only consumer
        let newEmissive = try renderer.createRenderTarget(width: width, height: height, format: .rgba16Float)
        // bloom chain uses RGBA8 - 2x bandwidth savings, negligible
        // visual loss for this art style
        let newExtract = try renderer.createRenderTarget(width: w0, height: h0, format: .rgba8Unorm)

        let newHBlur0 = try renderer.createRenderTarget(width: w0, height: h0, format: .rgba8Unorm)
        let newBloom0 = try renderer.createRenderTarget(width: w0, height: h0, format: .rgba8Unorm)

        let newHBlur1 = try renderer.createRenderTarget(width: w1, height: h1, format: .rgba8Unorm)
        let newBloom1 = try renderer.createRenderTarget(width: w1, height: h1, format: .rgba8Unorm)

        let newHBlur2 = try renderer.createRenderTarget(width: w2, height: h2, format: .rgba8Unorm)
        let newBloom2 = try renderer.createRenderTarget(width: w2, height: h2, format: .rgba8Unorm)

        sceneTarget = newScene
        emissiveTarget = newEmissive
        extractTarget = newExtract

        hBlur0Target = newHBlur0
        bloom0Target = newBloom0

        hBlur1Target = newHBlur1
        bloom1Target = newBloom1

        hBlur2Target = newHBlur2
        bloom2Target = newBloom2

        targetSize = SIMD2(width, height)
    }

    private static func uniforms(
        _ first: SIMD4<Float>,
        _ second: SIMD4<Float>,
        _ third: SIMD4<Float>,
        _ fourth: SIMD4<Float>
    ) -> Data {
        let vectors = [first, second, third, fourth]
        let values = vectors.flatMap { [$0.x, $0.y, $0.z, $0.w] }

        return values.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return Data() }

            return Data(
                bytes: base,
                count: buffer.count * MemoryLayout<Float>.stride
            )
        }
    }
}
