import CSDL3
import Math

/// SDL's event enum imports as UInt32 on Linux and as Int32 with MSVC,
/// so normalize its raw value before comparing it with 'SDL_Event.type'.
private extension SDL_EventType {
    var rawUInt32: UInt32 { UInt32(truncatingIfNeeded: rawValue) }
}

/// polls SDL input and maintains frame-based keyboard, mouse,
/// and gamepad state
///
/// 'Input' is '@unchecked Sendable' because it is polled from
/// the main thread only (the engine run loop is '@MainActor');
/// device state is not safe to read concurrently from other
/// actors
public final class Input: @unchecked Sendable {
    public let keyboard = Keyboard()
    public let mouse = Mouse()

    /// all connected gamepads, ordered by instance ID
    public var gamepads: [Gamepad] {
        gamepadsByID.values.sorted { $0.id < $1.id }
    }

    /// returns the gamepad with the given SDL joystick
    /// instance ID, if connected
    public func gamepad(_ id: Int32) -> Gamepad? {
        gamepadsByID[SDL_JoystickID(bitPattern: id)]
    }

    private var gamepadsByID: [SDL_JoystickID: Gamepad] = [:]

    public init() {
        SDL_InitSubSystem(SDL_INIT_GAMEPAD)
        enumerateConnectedGamepads()
    }

    deinit {
        for gamepad in gamepadsByID.values {
            gamepad.close()
        }
        gamepadsByID.removeAll()
        SDL_QuitSubSystem(SDL_INIT_GAMEPAD)
    }

    /// drains SDL's event queue. call once at the beginning of each frame
    @discardableResult
    public func update() -> [InputEvent] {
        var ignored: [SDL_Event] = []
        return update(collectRaw: &ignored)
    }

    /// drains SDL's event queue and, if 'rawOut' is provided, appends every
    /// raw 'SDL_Event' to it. this allows callers such as the UI subsystem to
    /// forward events to RmlUI without re-polling
    @discardableResult
    public func update(collectRaw rawOut: inout [SDL_Event]) -> [InputEvent] {
        keyboard.beginFrame()
        mouse.beginFrame()
        for gamepad in gamepadsByID.values {
            gamepad.beginFrame()
        }

        var events: [InputEvent] = []
        var event = SDL_Event()

        while SDL_PollEvent(&event) {
            rawOut.append(event)

            switch event.type {
            case SDL_EVENT_QUIT.rawUInt32:
                events.append(.quit)
            case SDL_EVENT_KEY_DOWN.rawUInt32:
                let key = Key(rawValue: Int32(event.key.scancode.rawValue))
                keyboard.set(key, isDown: true)
                events.append(.keyDown(key, isRepeat: event.key.repeat))
            case SDL_EVENT_KEY_UP.rawUInt32:
                let key = Key(rawValue: Int32(event.key.scancode.rawValue))
                keyboard.set(key, isDown: false)
                events.append(.keyUp(key))
            case SDL_EVENT_MOUSE_MOTION.rawUInt32:
                let position = Vector2D(event.motion.x, event.motion.y)
                let delta = Vector2D(event.motion.xrel, event.motion.yrel)
                mouse.move(to: position, delta: delta)
                events.append(.mouseMoved(position: position, delta: delta))
            case SDL_EVENT_MOUSE_BUTTON_DOWN.rawUInt32:
                let position = Vector2D(event.button.x, event.button.y)
                let button = MouseButton(sdlRawValue: event.button.button)
                mouse.set(button, isDown: true)
                events.append(.mouseButtonDown(button, position: position))
            case SDL_EVENT_MOUSE_BUTTON_UP.rawUInt32:
                let position = Vector2D(event.button.x, event.button.y)
                let button = MouseButton(sdlRawValue: event.button.button)
                mouse.set(button, isDown: false)
                events.append(.mouseButtonUp(button, position: position))
            case SDL_EVENT_MOUSE_WHEEL.rawUInt32:
                let amount = Vector2D(event.wheel.x, event.wheel.y)
                mouse.addWheel(amount)
                events.append(.mouseWheel(amount))
            case SDL_EVENT_TEXT_INPUT.rawUInt32:
                if let text = event.text.text {
                    events.append(.textInput(String(cString: text)))
                }
            case SDL_EVENT_WINDOW_MOUSE_ENTER.rawUInt32:
                mouse.setInsideWindow(true)
                events.append(.mouseEnteredWindow)
            case SDL_EVENT_WINDOW_MOUSE_LEAVE.rawUInt32:
                mouse.setInsideWindow(false)
                events.append(.mouseLeftWindow)
            case SDL_EVENT_GAMEPAD_ADDED.rawUInt32:
                let id = event.jdevice.which
                addGamepad(id)
                events.append(.gamepadConnected(Int32(bitPattern: id)))
            case SDL_EVENT_GAMEPAD_REMOVED.rawUInt32:
                let id = event.jdevice.which
                removeGamepad(id)
                events.append(.gamepadDisconnected(Int32(bitPattern: id)))
            case SDL_EVENT_GAMEPAD_BUTTON_DOWN.rawUInt32:
                let id = event.gbutton.which
                if let button = GamepadButton(sdlRawValue: Int32(event.gbutton.button)) {
                    gamepadsByID[id]?.set(button, isDown: true)
                    events.append(
                        .gamepadButtonDown(Int32(bitPattern: id), button)
                    )
                }
            case SDL_EVENT_GAMEPAD_BUTTON_UP.rawUInt32:
                let id = event.gbutton.which
                if let button = GamepadButton(sdlRawValue: Int32(event.gbutton.button)) {
                    gamepadsByID[id]?.set(button, isDown: false)
                    events.append(
                        .gamepadButtonUp(Int32(bitPattern: id), button)
                    )
                }
            case SDL_EVENT_GAMEPAD_AXIS_MOTION.rawUInt32:
                let id = event.gaxis.which
                if let axis = GamepadAxis(sdlRawValue: Int32(event.gaxis.axis)) {
                    let value = Float(event.gaxis.value) / 32768.0
                    gamepadsByID[id]?.set(axis, value: value)
                    events.append(
                        .gamepadAxis(Int32(bitPattern: id), axis, value)
                    )
                }
            default:
                break
            }
        }

        // re-read all connected gamepads so state stays correct
        // even if an event was missed
        for gamepad in gamepadsByID.values {
            gamepad.refresh()
        }
        keyboard.syncFromSDL()
        return events
    }

    // MARK: - Gamepad management

    private func enumerateConnectedGamepads() {
        var count: Int32 = 0
        guard let ids = SDL_GetGamepads(&count) else { return }
        for index in 0..<Int(count) {
            addGamepad(ids[index])
        }
    }

    private func addGamepad(_ id: SDL_JoystickID) {
        guard gamepadsByID[id] == nil else { return }
        let gamepad = Gamepad(id: id)
        gamepad.open()
        gamepadsByID[id] = gamepad
    }

    private func removeGamepad(_ id: SDL_JoystickID) {
        gamepadsByID[id]?.close()
        gamepadsByID.removeValue(forKey: id)
    }
}
