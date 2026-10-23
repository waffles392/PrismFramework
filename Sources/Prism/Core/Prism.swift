import Foundation
import Audio
import Events
import Graphics
import Input
import Math
import Scene
import Time
import UI
import Window
import CSDL3

/// SDL's event enum imports as UInt32 on Linux and as Int32 with MSVC,
/// so normalize its raw value before comparing it with 'SDL_Event.type'.
private extension SDL_EventType {
    var rawUInt32: UInt32 { UInt32(truncatingIfNeeded: rawValue) }
}

/// the engine entry point
///
/// 'Prism' owns every subsystem and drives the frame loop. create one, then
/// call a 'run(...)' overload; every overload funnels into 'run(drawPhase:)'
@MainActor
public final class Prism {

    // MARK: - Subsystems

    public let window: Window
    /// device, frame lifecycle and pipeline caches
    public let renderer: Renderer
    public let input: Input
    public let time: Time
    public let audio: Audio
    /// bundle-backed content store
    public let assets: AssetStore

    // MARK: - Events

    /// engine-wide pub/sub dispatcher
    public let events: EventDispatcher
    /// evaluates the active 'InputActionMap'; transitions are forwarded to
    /// 'events' as 'InputActionTriggeredEvent'
    public let inputManager: InputManager
    /// timer queue driven by scaled engine time
    public let scheduler = TimeScheduler()

    // MARK: - UI

    /// the engine-managed RmlUI context, or 'nil' when RmlUI is unavailable
    public private(set) var ui: UIContext?

    // MARK: - Meshes

    /// meshes prepared each frame by the run loops
    public private(set) var meshes: [Mesh] = []

    // MARK: - Run state

    /// what the active 'run(...)' overload draws
    private enum DrawPhase {
        case renderPass(@MainActor (RenderEncoder) -> Void)
        case context(@MainActor (Canvas2D) -> Void)
        case mesh(Mesh)
        case scene(Scene2D)
        case none
    }

    private var drawPhase: DrawPhase = .none
    private var activeScene: Scene2D?
    private var isRunning = false
    private var closeEventPublished = false
    private var lastTimeScale: Double = 1
    private var lastPaused = false
    private var lastWindowSize: (width: Int32, height: Int32) = (0, 0)

    // MARK: - Init

    public init(
        title: String = "Prism",
        width: Int32 = 800,
        height: Int32 = 600,
        flags: WindowFlags = .recommended,
        bundle: Bundle? = nil,
        fixedRate: Double? = nil,
        maxFixedSteps: Int = 8
    ) {
        let window = Window(title: title, width: width, height: height, flags: flags)
        self.window = window

        let windowHandle = window.handle

        let renderer: Renderer
        do { renderer = try Renderer(window: windowHandle, windowOwner: window) } 
        catch { fatalError("Failed to initialize Prism renderer: \(error)") }

        self.renderer = renderer

        let input = Input()
        self.input = input

        let time = Time(fixedRate: fixedRate, maxFixedSteps: maxFixedSteps)
        self.time = time

        self.audio = Audio()
        self.assets = AssetStore(bundle: bundle ?? .main)

        let events = EventDispatcher(timeProvider: { time.elapsedTime })
        self.events = events

        let inputManager = InputManager(
            keyboard: input.keyboard,
            mouse: input.mouse,
            gamepads: { input.gamepads }
        )
        inputManager.onActionTriggered = { [weak events] name, isPressed in
            events?.publish(InputActionTriggeredEvent(
                actionName: name,
                state: isPressed ? .pressed : .released
            ))
        }
        self.inputManager = inputManager

        renderer.printStartupBanner(title: title, width: width, height: height)
        renderer.device.forceShaderGuard = PrismEnvironment.forceShaderGuard
        setupUI(width: width, height: height)
    }

    /// creates an engine from a 'PrismConfig'
    public convenience init(config: PrismConfig) {
        self.init(
            title: config.title,
            width: config.width,
            height: config.height,
            flags: config.flags,
            bundle: config.bundle,
            fixedRate: config.fixedRate,
            maxFixedSteps: config.maxFixedSteps
        )
    }

    // MARK: - Lifecycle

    /// stops the loop; teardown runs in the loop's 'defer' block
    public func quit() { requestShutdown() }

    /// stops the loop and tears the GPU down immediately
    public func stop() {
        requestShutdown()
        renderer.shutdown()
    }

    /// requests shutdown and publishes 'WindowCloseEvent' at most once per run
    private func requestShutdown() {
        isRunning = false
        if !closeEventPublished {
            closeEventPublished = true
            events.publish(WindowCloseEvent())
        }
        renderer.interrupt()
    }

    // MARK: - Meshes

    /// creates a mesh from shader bytecode and registers it with the engine
    public func createMesh(
        vertices: [Vertex],
        vertexShaderCode: Data,
        fragmentShaderCode: Data
    ) throws -> Mesh {
        let mesh = try Mesh(
            device: renderer.device,
            sampler: renderer.linearSampler,
            vertices: vertices,
            vertexShaderCode: vertexShaderCode,
            fragmentShaderCode: fragmentShaderCode
        )
        addMesh(mesh)
        return mesh
    }

    /// creates a mesh from a shader-backed material and registers it
    public func createMesh(vertices: [Vertex], surface: Surface) throws -> Mesh {
        let mesh = try Mesh(
            device: renderer.device,
            sampler: renderer.linearSampler,
            vertices: vertices,
            surface: surface
        )
        addMesh(mesh)
        return mesh
    }

    /// creates a mesh whose shader pair is loaded from this instance's asset
    /// bundle, and registers it. each mesh owns its 'Surface', so uniforms,
    /// textures and blend mode are configured per object
    public func createMesh(
        vertices: [Vertex],
        vertexShaderName: String,
        fragmentShaderName: String,
        subdirectory: String? = nil,
        blendMode: BlendMode = .alpha
    ) throws -> Mesh {
        let vertexShader = try assets.loadData(named: vertexShaderName, subdirectory: subdirectory)
        let fragmentShader = try assets.loadData(named: fragmentShaderName, subdirectory: subdirectory)
        return try createMesh(
            vertices: vertices,
            surface: Surface(
                vertexShader: vertexShader,
                fragmentShader: fragmentShader,
                blendMode: blendMode
            )
        )
    }

    /// registers 'mesh' with the engine
    public func addMesh(_ mesh: Mesh) {
        guard !meshes.contains(where: { $0 === mesh }) else { return }
        meshes.append(mesh)
    }

    /// removes 'mesh' from the engine's mesh registry
    public func removeMesh(_ mesh: Mesh) { meshes.removeAll { $0 === mesh } }

    // MARK: - Run (full control)

    /// runs the game loop with direct render-pass drawing
    public func run(
        onFixedUpdate: @escaping @MainActor (Float) -> Void = { _ in },
        onUpdate: @escaping @MainActor (Float) -> Void = { _ in },
        onDraw: @escaping @MainActor (RenderEncoder) -> Void = { _ in },
        postProcessing: PostProcessingSettings = PostProcessingSettings()
    ) {
        run(
            drawPhase: .renderPass(onDraw),
            onFixedUpdate: onFixedUpdate,
            onUpdate: onUpdate,
            postProcessing: postProcessing
        )
    }

    // MARK: - Run (2D canvas)

    /// runs the game loop with a pixel-based 2D canvas
    public func run(
        draw: @escaping @MainActor (Canvas2D) -> Void,
        postProcessing: PostProcessingSettings = PostProcessingSettings(),
        onFixedUpdate: @escaping @MainActor (Float) -> Void = { _ in },
        onUpdate: @escaping @MainActor (Float) -> Void = { _ in }
    ) {
        run(
            drawPhase: .context(draw),
            onFixedUpdate: onFixedUpdate,
            onUpdate: onUpdate,
            postProcessing: postProcessing
        )
    }

    // MARK: - Run (single mesh)

    /// runs the game loop drawing a single mesh
    public func run(
        mesh: Mesh,
        onFixedUpdate: @escaping @MainActor (Float) -> Void = { _ in },
        onUpdate: @escaping @MainActor (Float) -> Void = { _ in },
        postProcessing: PostProcessingSettings = PostProcessingSettings()
    ) {
        run(
            drawPhase: .mesh(mesh),
            onFixedUpdate: onFixedUpdate,
            onUpdate: onUpdate,
            postProcessing: postProcessing
        )
    }

    // MARK: - Run (Scene2D)

    /// runs the game loop drawing a 'Scene2D'
    public func run(
        scene: Scene2D,
        postProcessing: PostProcessingSettings = PostProcessingSettings()
    ) {
        run(
            drawPhase: .scene(scene),
            onFixedUpdate: { _ in },
            onUpdate: { _ in },
            postProcessing: postProcessing
        )
    }

    // MARK: - The run loop

    /// the single loop every 'run(...)' overload funnels into. per frame:
    /// input → events → time (fixed steps + timers + 'FrameTickEvent') →
    /// update → render → UI overlay → present → pacing → stats
    private func run(
        drawPhase: DrawPhase,
        onFixedUpdate: @MainActor (Float) -> Void,
        onUpdate: @MainActor (Float) -> Void,
        postProcessing: PostProcessingSettings
    ) {
        self.drawPhase = drawPhase
        if case .scene(let scene) = drawPhase { activeScene = scene }

        let consoleStats = ConsoleStats()
        defer {
            consoleStats.finish()
            teardownUI()
            renderer.shutdown()
        }

        isRunning = true
        closeEventPublished = false
        lastTimeScale = time.timeScale
        lastPaused = time.paused
        events.logEnabled = PrismEnvironment.dumpEvents
        // vsync is applied through the GPU swapchain; Window only records it
        renderer.setVsync(window.flags.contains(.vsync))
        time.reset()

        let postProcessor: PostProcessor
        do { postProcessor = try PostProcessor(renderer: renderer) } 
        catch { fatalError("Failed to create post-processor: \(error)") }
        postProcessor.isEnabled = !PrismEnvironment.disablePostProcessing

        let canvas: Canvas2D? = {
            guard case .context = drawPhase else { return nil }
            let canvas = Canvas2D()
            do {
                try canvas.configure(
                    renderer: renderer,
                    vertexShaderCode: ShaderLoader.load("base.vert.spv"),
                    fragmentShaderCode: ShaderLoader.load("base.frag.spv")
                )} 
            catch { fatalError("Failed to configure 2D canvas: \(error)") }
            return canvas
        }()

        let pacer = Pacer(targetFPS: effectiveTargetFPS)

        while isRunning {
            let frameStart = DispatchTime.now()

            var rawEvents: [SDL_Event] = []
            let inputEvents = input.update(collectRaw: &rawEvents)
            processEvents(inputEvents: inputEvents, rawEvents: rawEvents)

            guard isRunning && !renderer.isInterrupted else { break }

            window.refreshSize()
            syncUISize()
            publishTimeStateEvents()

            let deltaTime = advanceTime(onFixedUpdate: onFixedUpdate)

            ui?.update()
            onUpdate(deltaTime)
            activeScene?.update(deltaTime: deltaTime)

            guard isRunning && !renderer.isInterrupted else { break }

            guard let frame = try? renderer.beginFrame() else { continue }
            guard frame.width > 0, frame.height > 0 else {
                renderer.endFrame(frame)
                continue
            }

            renderFrame(frame, postProcessor: postProcessor, canvas: canvas, postProcessing: postProcessing)
            renderUIOverlay(frame: frame)
            renderer.endFrame(frame)

            pace(frameStart: frameStart, pacer: pacer)
            consoleStats.frameCompleted()
        }
    }

    // MARK: - Frame steps

    /// flushes deferred events, publishes input and window events, and forwards
    /// raw SDL events to RmlUI
    private func processEvents(inputEvents: [InputEvent], rawEvents: [SDL_Event]) {
        events.flush()

        for event in inputEvents {
            if case .quit = event { requestShutdown() } 
            else { publishInputEvent(event) }
        }

        inputManager.update()
        handleWindowEvents(rawEvents)

        if let uiCtx = ui {
            let windowHandle = window.handle
            for var sdlEvent in rawEvents {
                withUnsafeMutablePointer(to: &sdlEvent) { ptr in
                    _ = uiCtx.processSDLEvent(
                        window: windowHandle,
                        event: UnsafeMutableRawPointer(ptr)
                    )
                }
            }
        }
    }

    /// advances the clock, runs the fixed steps, ticks timers and publishes
    /// 'FrameTickEvent'; returns this frame's delta time
    private func advanceTime(onFixedUpdate: @MainActor (Float) -> Void) -> Float {
        let timeDelta = time.update()
        let deltaTime = Float(timeDelta)
        let fixedDeltaTime = Float(time.fixedDeltaTime)

        // fixed steps run before update/draw so simulation stays deterministic
        for _ in 0..<time.fixedStepCount {
            onFixedUpdate(fixedDeltaTime)
            activeScene?.fixedUpdate(deltaTime: fixedDeltaTime)
        }

        scheduler.tick(deltaTime: timeDelta)
        events.publish(
            FrameTickEvent(
                deltaTime: timeDelta,
                unscaledDeltaTime: time.unscaledDeltaTime,
                frameIndex: time.frameIndex,
                fixedStepCount: time.fixedStepCount,
                interpolationAlpha: time.interpolationAlpha
            )
        )
        return deltaTime
    }

    /// draws the frame: 2D canvas callback, geometry prepare, the scene pass and
    /// post-processing. skipped when rasterization is disabled
    private func renderFrame(
        _ frame: Frame,
        postProcessor: PostProcessor,
        canvas: Canvas2D?,
        postProcessing: PostProcessingSettings
    ) {
        guard !PrismEnvironment.disableRasterization else { return }

        do {
            // context drawing runs before prepare because the immediate-mode
            // canvas accumulates vertices during the callback
            if let canvas, case .context(let draw) = drawPhase {
                canvas.begin(windowWidth: window.width, windowHeight: window.height)
                draw(canvas)
            }

            try prepareGeometry(frame: frame, canvas: canvas)
            postProcessor.prepare(frame: frame)

            let sceneTarget = try postProcessor.sceneTarget(width: frame.width, height: frame.height)
            let emissiveTarget = try postProcessor.emissiveTarget(width: frame.width, height: frame.height)
            let renderPass = try frame.beginRenderPass(
                to: sceneTarget,
                emissive: emissiveTarget,
                clearColor: Color(0, 0, 0, 1)
            )

            drawRenderPass(in: renderPass, canvas: canvas)
            renderPass.end()

            postProcessor.draw(
                frame: frame,
                settings: postProcessing,
                elapsedTime: Float(time.elapsedTime)
            )
        } catch {
            print("[prism] frame skipped: \(error)")
        }
    }

    /// uploads the geometry the active draw phase needs for this frame
    private func prepareGeometry(frame: Frame, canvas: Canvas2D?) throws {
        switch drawPhase {
        case .renderPass:
            for mesh in meshes { try mesh.prepare(commandBuffer: frame.commandBuffer) }
        case .context:
            try canvas?.prepare(frame: frame)
        case .mesh(let mesh):
            try mesh.prepare(commandBuffer: frame.commandBuffer)
        case .scene(let scene):
            scene.prepare(renderer: renderer, frame: frame)
        case .none:
            break
        }
    }

    /// records the active draw phase into the scene render pass
    private func drawRenderPass(in renderPass: RenderEncoder, canvas: Canvas2D?) {
        switch drawPhase {
        case .renderPass(let draw):
            draw(renderPass)
        case .context:
            canvas?.draw(in: renderPass)
        case .mesh(let mesh):
            mesh.draw(in: renderPass)
        case .scene(let scene):
            scene.draw(in: renderPass)
        case .none:
            break
        }
    }

    /// sleeps towards the effective target frame rate after present
    private func pace(frameStart: DispatchTime, pacer: Pacer) {
        guard pacer.isActive else { return }

        let elapsed = Float(
            DispatchTime.now().uptimeNanoseconds - frameStart.uptimeNanoseconds
        ) / 1_000_000_000
        let delay = pacer.remainingDelay(frameDuration: pacer.frameDuration, elapsed: elapsed)
        if delay > 0 { SDL_Delay(delay) }
    }

    /// 'PRISM_LOCK_FRAMERATE' overrides 'window.targetFPS'; unlimited (nil)
    /// when neither is set
    private var effectiveTargetFPS: Int? { PrismEnvironment.lockFramerate ?? window.targetFPS }

    // MARK: - Setup

    /// creates the RmlUI context, or leaves 'ui' nil when it is unavailable
    private func setupUI(width: Int32, height: Int32) {
        guard let device = renderer.deviceHandle else { return }
        let windowHandle = window.handle
        guard UIContext.initialize(device: device, window: windowHandle) else {
            print("[prism] RmlUI initialization failed - UI overlay will be unavailable.")
            return
        }
        ui = UIContext(name: "main", width: Int(width), height: Int(height))
        lastWindowSize = (width, height)
    }

    // MARK: - Event helpers

    /// translates a raw 'InputEvent' into a typed 'EngineEvent'
    private func publishInputEvent(_ event: InputEvent) {
        switch event {
        case .keyDown(let key, let isRepeat):
            events.publish(KeyPressedEvent(key: key, isRepeat: isRepeat))
        case .keyUp(let key):
            events.publish(KeyReleasedEvent(key: key))
        case .mouseMoved(let position, let delta):
            events.publish(MouseMovedEvent(position: position, delta: delta))
        case .mouseButtonDown(let button, let position):
            events.publish(MouseButtonPressedEvent(button: button, position: position))
        case .mouseButtonUp(let button, let position):
            events.publish(MouseButtonReleasedEvent(button: button, position: position))
        case .mouseWheel(let delta):
            events.publish(MouseWheelEvent(delta: delta))
        case .textInput(let text):
            events.publish(TextInputEvent(text: text))
        case .gamepadConnected(let id):
            events.publish(GamepadConnectedEvent(gamepadID: id))
        case .gamepadDisconnected(let id):
            events.publish(GamepadDisconnectedEvent(gamepadID: id))
        case .gamepadButtonDown(let id, let button):
            events.publish(GamepadButtonEvent(gamepadID: id, button: button, isDown: true))
        case .gamepadButtonUp(let id, let button):
            events.publish(GamepadButtonEvent(gamepadID: id, button: button, isDown: false))
        case .gamepadAxis(let id, let axis, let value):
            events.publish(GamepadAxisEvent(gamepadID: id, axis: axis, value: value))
        case .mouseEnteredWindow, .mouseLeftWindow, .quit:
            break // state-only or handled separately
        }
    }

    /// maps SDL window events to engine events
    private func handleWindowEvents(_ sdlEvents: [SDL_Event]) {
        for event in sdlEvents {
            switch event.type {
            case SDL_EVENT_WINDOW_MOVED.rawUInt32:
                events.publish(WindowMovedEvent(position: Vector2D(Float(event.window.data1), Float(event.window.data2))))
            case SDL_EVENT_WINDOW_FOCUS_GAINED.rawUInt32:
                events.publish(WindowFocusedEvent(focused: true))
            case SDL_EVENT_WINDOW_FOCUS_LOST.rawUInt32:
                events.publish(WindowFocusedEvent(focused: false))
            case SDL_EVENT_WINDOW_MINIMIZED.rawUInt32:
                events.publish(WindowMinimizedEvent())
            case SDL_EVENT_WINDOW_MAXIMIZED.rawUInt32:
                events.publish(WindowMaximizedEvent())
            case SDL_EVENT_WINDOW_RESTORED.rawUInt32:
                events.publish(WindowRestoredEvent())
            case SDL_EVENT_WINDOW_SHOWN.rawUInt32:
                events.publish(WindowShownEvent())
            case SDL_EVENT_WINDOW_HIDDEN.rawUInt32:
                events.publish(WindowHiddenEvent())
            case SDL_EVENT_WINDOW_CLOSE_REQUESTED.rawUInt32:
                requestShutdown()
            default:
                break
            }
        }
    }

    /// publishes time-scale and pause events when the clock changed this frame
    private func publishTimeStateEvents() {
        let timeScale = time.timeScale
        if timeScale != lastTimeScale {
            events.publish(TimeScaleChangedEvent(oldValue: lastTimeScale, newValue: timeScale))
            lastTimeScale = timeScale
        }

        let paused = time.paused
        if paused != lastPaused {
            events.publish(paused ? EnginePausedEvent() : EngineResumedEvent())
            lastPaused = paused
        }
    }

    // MARK: - UI helpers

    /// renders the RmlUI context as a swapchain-level overlay
    private func renderUIOverlay(frame: Frame) {
        guard !PrismEnvironment.disableRasterization else { return }
        guard let uiCtx = ui else { return }
        // the swapchain texture is nil while minimised or occluded
        guard let swapchainTexture = frame.swapchainTexture else { return }

        UIContext.beginFrame(
            commandBuffer: frame.commandBuffer,
            texture: swapchainTexture,
            width: Int(frame.width),
            height: Int(frame.height)
        )
        uiCtx.render()
        UIContext.endFrame()
    }

    /// keeps the RmlUI context in sync with the window size
    private func syncUISize() {
        guard let uiCtx = ui else { return }
        let w = window.width, h = window.height
        guard w != lastWindowSize.width || h != lastWindowSize.height else { return }
        lastWindowSize = (w, h)
        uiCtx.setDimensions(width: Int(w), height: Int(h))
        events.publish(WindowResizedEvent(width: Int(w), height: Int(h)))
    }

    private func teardownUI() {
        if ui != nil {
            ui = nil          // deinit calls rmlui_destroy_context
            UIContext.shutdown()
        }
    }
}
