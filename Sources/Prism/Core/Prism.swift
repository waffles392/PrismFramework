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

@MainActor
public final class Prism {
    public let window: Window

    /// the renderer: device, frame lifecycle, and pipeline caches
    public let renderer: Renderer

    public let input: Input
    public let time: Time
    public let audio: Audio
    /// bundle-backed local content store for the game
    public let assets: AssetStore

    // MARK: - Event System

    /// engine-wide pub/sub event dispatcher
    ///
    /// subscribe to typed events from anywhere in your game code:
    /// ```swift
    /// let token = prism.events.subscribe { (e: KeyPressedEvent) in
    ///     print("pressed: \(e.key)")
    /// }
    /// ```
    public let events: EventDispatcher

    /// evaluates the active 'InputActionMap' each frame. action transitions
    /// are forwarded to 'prism.events' as 'InputActionTriggeredEvent'
    public let inputManager: InputManager

    /// timer queue driven by scaled engine time
    /// advance it with the result of 'time.update()' each frame
    /// (the run loops do this automatically)
    public let scheduler = TimeScheduler()

    // MARK: - RmlUI

    /// the engine-managed RmlUI context. available immediately after 'init'
    /// use it to load documents, update element content, and render UI overlays
    ///
    /// RmlUI renders into the final swapchain pass (after post-processing) so
    /// it appears on top of all game graphics at native window resolution
    ///
    /// RmlUI is initialized automatically if the subsystem is available
    /// if initialization fails (e.g. missing renderer) this is 'nil'
    public private(set) var ui: UIContext?

    /// the meshes prepared each frame by the generic
    /// run loops. 'createMesh(...)' registers automatically;
    /// meshes can also be added and removed explicitly
    public private(set) var meshes: [Mesh] = []

    private var isRunning = false
    private var lastWindowSize: (width: Int32, height: Int32) = (0, 0)
    private var lastTimeScale: Float = 1
    private var lastPaused: Bool = false
    private var closeEventPublished = false

    /// the draw source selected by the active 'run(...)' overload
    private enum DrawPhase {
        /// draw into the render pass directly
        case renderPass(@MainActor (RenderEncoder) -> Void)
        /// draw through the immediate-mode 2D canvas
        case context(@MainActor (Canvas2D) -> Void)
        /// draw a single registered-style mesh
        case mesh(Mesh)
        /// draw a 'Scene2D'
        case scene(Scene2D)
        /// no scene drawing (UI only)
        case none
    }

    // MARK: - Lifecycle

    /// stops the active run loop and closes the application cleanly
    ///
    /// the loop unwinds through its 'defer' block (UI teardown and
    /// GPU shutdown). the close event is published at most once per run
    public func quit() {
        requestShutdown()
    }

    /// stops the run loop immediately and tears the GPU down
    ///
    /// unlike 'quit()', teardown is not deferred to the end of the
    /// run loop - the GPU shuts down as soon as 'stop()' is called.
    /// the close event is published at most once per run
    public func stop() {
        requestShutdown()
        renderer.shutdown()
    }

    /// requests loop shutdown and publishes 'WindowCloseEvent' the
    /// first time it is requested in a run
    private func requestShutdown() {
        isRunning = false
        if !closeEventPublished {
            closeEventPublished = true
            events.publish(WindowCloseEvent())
        }
        renderer.interrupt()
    }

    public init(
        title: String = "Prism",
        width: Int32 = 800,
        height: Int32 = 600,
        flags: WindowFlags = .recommended,
        bundle: Bundle? = nil
    ) {
        let window = Window(
            title: title,
            width: width,
            height: height,
            flags: flags
        )
        self.window = window

        guard let windowHandle = window.handle else {
            fatalError("Failed to initialize Prism: the window has no SDL handle")
        }

        let renderer: Renderer
        do {
            renderer = try Renderer(window: windowHandle, windowOwner: window)
        } catch {
            fatalError("Failed to initialize Prism renderer: \(error)")
        }
        self.renderer = renderer

        let input = Input()
        self.input = input
        let time = Time()
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
        inputManager.onActionTriggered = { [weak events] actionName, isPressed in
            events?.publish(InputActionTriggeredEvent(
                actionName: actionName,
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
            bundle: config.bundle
        )
    }

    // MARK: - RmlUI Setup

    private func setupUI(width: Int32, height: Int32) {
        guard
            let device = renderer.deviceHandle,
            let windowHandle = window.handle
        else { return }

        let ok = UIContext.initialize(device: device, window: windowHandle)
        guard ok else {
            print("[prism] RmlUI initialization failed - UI overlay will be unavailable.")
            return
        }

        ui = UIContext(name: "main", width: Int(width), height: Int(height))
        lastWindowSize = (width, height)
    }

    // MARK: - Mesh registry

    /// creates a mesh and registers it with the engine
    /// (it is prepared each frame by the generic run loops)
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

    /// creates a mesh using a shader-backed material and
    /// registers it with the engine
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

    /// creates a mesh with its own shader pair loaded from this Prism
    /// instance's asset bundle, and registers it with the engine
    /// each mesh owns its 'Surface', so shader uniforms, textures, and
    /// blend mode can be configured independently per object
    public func createMesh(
        vertices: [Vertex],
        vertexShaderName: String,
        fragmentShaderName: String,
        subdirectory: String? = nil,
        blendMode: BlendMode = .alpha
    ) throws -> Mesh {
        let vertexShader = try assets.loadData(
            named: vertexShaderName,
            subdirectory: subdirectory
        )
        let fragmentShader = try assets.loadData(
            named: fragmentShaderName,
            subdirectory: subdirectory
        )
        return try createMesh(
            vertices: vertices,
            surface: Surface(
                vertexShader: vertexShader,
                fragmentShader: fragmentShader,
                blendMode: blendMode
            )
        )
    }

    /// registers 'mesh' with the engine; it is prepared
    /// each frame by the generic run loops
    public func addMesh(_ mesh: Mesh) {
        guard !meshes.contains(where: { $0 === mesh }) else { return }
        meshes.append(mesh)
    }

    /// removes 'mesh' from the engine's mesh registry
    public func removeMesh(_ mesh: Mesh) {
        meshes.removeAll { $0 === mesh }
    }

    // MARK: - Run (full control)

    /// runs the game loop with direct render-pass drawing
    public func run(
        onUpdate: @escaping @MainActor (Float) -> Void = { _ in },
        onDraw: @escaping @MainActor (
            RenderEncoder
        ) -> Void = { _ in },
        postProcessing: PostProcessingSettings = PostProcessingSettings()
    ) {
        run(
            drawPhase: .renderPass(onDraw),
            onUpdate: onUpdate,
            postProcessing: postProcessing
        )
    }

    // MARK: - Run (2D canvas)

    /// runs the game loop with a simple pixel-based 2D drawing canvas
    /// coordinates start at the top-left of the window content area, whose
    /// dimensions are available as 'canvas.size'
    public func run(
        draw: @escaping @MainActor (Canvas2D) -> Void,
        postProcessing: PostProcessingSettings = PostProcessingSettings(),
        onUpdate: @escaping @MainActor (Float) -> Void = { _ in }
    ) {
        run(
            drawPhase: .context(draw),
            onUpdate: onUpdate,
            postProcessing: postProcessing
        )
    }

    // MARK: - Run (single mesh)

    /// runs the game loop drawing a single mesh
    public func run(
        mesh: Mesh,
        onUpdate: @escaping @MainActor (Float) -> Void = { _ in },
        postProcessing: PostProcessingSettings = PostProcessingSettings()
    ) {
        run(
            drawPhase: .mesh(mesh),
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
            onUpdate: { _ in },
            postProcessing: postProcessing
        )
    }

    // MARK: - The run loop

    /// the single engine run loop. every public 'run(...)'
    /// overload funnels into this method; 'drawPhase' selects
    /// what is rendered into the scene pass
    ///
    /// frame phases, in order:
    ///  1. 'input.update(collectRaw:)' - raw events are always
    ///     collected so the UI subsystem receives them
    ///  2. 'events.flush()' + input-event publishing + window
    ///     events (moved/resized/focused/minimized/maximized/
    ///     restored/shown/hidden/close-requested)
    ///  3. 'time.update()' + 'scheduler.tick()' + 'FrameTickEvent'
    ///  4. user update callback / scene update
    ///  5. 'renderer.beginFrame', mesh registry prepare,
    ///     'postProcessor.prepare'
    ///  6. render pass: user draw callback / scene / mesh / 2D
    ///     canvas
    ///  7. 'postProcessor.draw' (a direct blit when
    ///     'PRISM_DISABLE_POSTPROCESSING' is set)
    ///  8. UI: 'ui?.update()' + overlay rendering (skipped when
    ///     'PRISM_DISABLE_RASTERIZATION' is set)
    ///  9. 'renderer.endFrame'
    /// 10. frame pacing: 'SDL_Delay' towards the effective
    ///     target FPS ('PRISM_LOCK_FRAMERATE', else
    ///     'window.targetFPS'; unlimited when unset)
    /// 11. 'ConsoleStats.frameCompleted()'
    private func run(
        drawPhase: DrawPhase,
        onUpdate: @MainActor (Float) -> Void,
        postProcessing: PostProcessingSettings
    ) {
        let consoleStats = ConsoleStats()
        defer { consoleStats.finish(); teardownUI(); renderer.shutdown() }

        isRunning = true
        closeEventPublished = false
        lastTimeScale = time.timeScale
        lastPaused = time.paused

        events.logEnabled = PrismEnvironment.dumpEvents

        // the window's vsync flag is applied through the GPU
        // swapchain parameters; Core owns the device, Window
        // only records the flag
        renderer.setVsync(window.flags.contains(.vsync))

        time.reset()

        let postProcessor: PostProcessor
        do {
            postProcessor = try PostProcessor(renderer: renderer)
        } catch {
            fatalError("Failed to create post-processor: \(error)")
        }
        postProcessor.isEnabled = !PrismEnvironment.disablePostProcessing

        let canvas: Canvas2D? = {
            guard case .context = drawPhase else { return nil }
            let canvas = Canvas2D()
            do {
                try canvas.configure(
                    renderer: renderer,
                    vertexShaderCode: ShaderLoader.load("base.vert.spv"),
                    fragmentShaderCode: ShaderLoader.load("base.frag.spv")
                )
            } catch {
                fatalError("Failed to configure 2D canvas: \(error)")
            }
            return canvas
        }()

        let pacer = Pacer(targetFPS: effectiveTargetFPS)

        while isRunning {
            let frameStart = DispatchTime.now()

            // MARK: - 1. Input
            // raw events are always collected for the UI layer

            var sdlEvents: [SDL_Event] = []
            let inputEvents = input.update(collectRaw: &sdlEvents)

            // MARK: - 2. Events + window events

            events.flush()

            for event in inputEvents {
                if case .quit = event {
                    requestShutdown()
                } else {
                    publishInputEvent(event)
                }
            }
            inputManager.update()
            handleWindowEvents(sdlEvents)

            // forward raw SDL events to the RmlUI context for
            // mouse/keyboard input
            if let uiCtx = ui, let windowHandle = window.handle {
                for var sdlEvent in sdlEvents {
                    withUnsafeMutablePointer(to: &sdlEvent) { ptr in
                        _ = uiCtx.processSDLEvent(
                            window: windowHandle,
                            event: UnsafeMutableRawPointer(ptr)
                        )
                    }
                }
            }

            guard isRunning && !renderer.isInterrupted else { break }

            window.refreshSize()
            syncUISize()

            publishTimeStateEvents()

            // MARK: - 3. Time

            let deltaTime = time.update()
            scheduler.tick(deltaTime: deltaTime)
            events.publish(
                FrameTickEvent(
                    deltaTime: deltaTime,
                    unscaledDeltaTime: time.unscaledDeltaTime,
                    frameIndex: max(0, time.frameCount - 1)
                )
            )

            // MARK: - 4. Update

            ui?.update()
            onUpdate(deltaTime)
            if case .scene(let scene) = drawPhase {
                scene.update(deltaTime: deltaTime)
            }

            guard isRunning && !renderer.isInterrupted else { break }

            // MARK: - 5. Frame

            guard let frame = try? renderer.beginFrame() else {
                continue
            }
            guard frame.width > 0, frame.height > 0 else {
                renderer.endFrame(frame)
                continue
            }

            // MARK: - 6. Render
            // skipped entirely when rasterization is disabled, in which
            // case the swapchain is presented as-is

            if !PrismEnvironment.disableRasterization {
                do {
                    // context-phase drawing happens before prepare
                    // because the immediate-mode canvas accumulates
                    // vertices during the callback
                    if let canvas, case .context(let draw) = drawPhase {
                        canvas.begin(
                            windowWidth: window.width,
                            windowHeight: window.height
                        )
                        draw(canvas)
                    }

                    switch drawPhase {
                    case .renderPass:
                        for mesh in meshes {
                            try mesh.prepare(commandBuffer: frame.commandBuffer)
                        }
                    case .context:
                        try canvas?.prepare(frame: frame)
                    case .mesh(let mesh):
                        try mesh.prepare(commandBuffer: frame.commandBuffer)
                    case .scene(let scene):
                        scene.prepare(renderer: renderer, frame: frame)
                    case .none:
                        break
                    }
                    postProcessor.prepare(frame: frame)

                    let sceneTarget = try postProcessor.sceneTarget(
                        width: frame.width,
                        height: frame.height
                    )
                    let emissiveTarget = try postProcessor.emissiveTarget(
                        width: frame.width,
                        height: frame.height
                    )
                    let renderPass = try frame.beginRenderPass(
                        to: sceneTarget,
                        emissive: emissiveTarget,
                        clearColor: Color(0, 0, 0, 1)
                    )

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
                    renderPass.end()

                    postProcessor.draw(
                        frame: frame,
                        settings: postProcessing,
                        elapsedTime: time.elapsedTime
                    )
                } catch {
                    print("[prism] frame skipped: \(error)")
                }
            }

            // MARK: - 7. UI overlay

            renderUIOverlay(frame: frame)

            // MARK: - 8. Present

            renderer.endFrame(frame)

            // MARK: - 9. Pacing
            // after present, never inside the pass

            if pacer.isActive {
                let elapsed = Float(
                    DispatchTime.now().uptimeNanoseconds
                    - frameStart.uptimeNanoseconds
                ) / 1_000_000_000
                let delay = pacer.remainingDelay(
                    frameDuration: pacer.frameDuration,
                    elapsed: elapsed
                )
                if delay > 0 {
                    SDL_Delay(delay)
                }
            }

            consoleStats.frameCompleted()
        }
    }

    /// the frame rate the run loop paces towards:
    /// 'PRISM_LOCK_FRAMERATE' overrides 'window.targetFPS';
    /// 'nil' (unlimited) when neither is set
    private var effectiveTargetFPS: Int? {
        PrismEnvironment.lockFramerate ?? window.targetFPS
    }

    // MARK: - Private helpers

    /// translates a raw 'InputEvent' into a typed 'EngineEvent'
    /// and publishes it
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
            case SDL_EVENT_WINDOW_MOVED.rawValue:
                events.publish(
                    WindowMovedEvent(
                        position: Vector2D(
                            Float(event.window.data1),
                            Float(event.window.data2)
                        )
                    )
                )
            case SDL_EVENT_WINDOW_FOCUS_GAINED.rawValue:
                events.publish(WindowFocusedEvent(focused: true))
            case SDL_EVENT_WINDOW_FOCUS_LOST.rawValue:
                events.publish(WindowFocusedEvent(focused: false))
            case SDL_EVENT_WINDOW_MINIMIZED.rawValue:
                events.publish(WindowMinimizedEvent())
            case SDL_EVENT_WINDOW_MAXIMIZED.rawValue:
                events.publish(WindowMaximizedEvent())
            case SDL_EVENT_WINDOW_RESTORED.rawValue:
                events.publish(WindowRestoredEvent())
            case SDL_EVENT_WINDOW_SHOWN.rawValue:
                events.publish(WindowShownEvent())
            case SDL_EVENT_WINDOW_HIDDEN.rawValue:
                events.publish(WindowHiddenEvent())
            case SDL_EVENT_WINDOW_CLOSE_REQUESTED.rawValue:
                requestShutdown()
            default:
                break
            }
        }
    }

    /// publishes 'TimeScaleChangedEvent', 'EnginePausedEvent'
    /// and 'EngineResumedEvent' when the clock's properties
    /// changed since the previous frame
    private func publishTimeStateEvents() {
        let timeScale = time.timeScale
        if timeScale != lastTimeScale {
            events.publish(
                TimeScaleChangedEvent(
                    oldValue: lastTimeScale,
                    newValue: timeScale
                )
            )
            lastTimeScale = timeScale
        }

        let paused = time.paused
        if paused != lastPaused {
            if paused {
                events.publish(EnginePausedEvent())
            } else {
                events.publish(EngineResumedEvent())
            }
            lastPaused = paused
        }
    }

    /// renders the RmlUI context as a swapchain-level overlay
    ///
    /// RmlUI requires 'BeginFrame → Render → EndFrame' on every frame even
    /// when no documents are shown, so we always call through when 'ui' exists
    private func renderUIOverlay(frame: Frame) {
        guard !PrismEnvironment.disableRasterization else { return }
        guard let uiCtx = ui else { return }
        // swapchainTexture can be nil when the window is minimised or occluded
        // skip the UI render entirely in that case
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
            ui = nil          // destroys the context (deinit calls rmlui_destroy_context)
            UIContext.shutdown()
        }
    }
}
