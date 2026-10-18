import CSDL3
import Math

/// frame-based state for a single gamepad
///
/// a 'Gamepad' mirrors 'Keyboard' and 'Mouse': query the
/// current/previous frame state with 'isDown(_:)',
/// 'wasPressed(_:)', 'wasReleased(_:)', read analog axes
/// with 'value(of:)', and derive an eight-way hat direction
/// from the left stick with 'hat'
///
/// 'Gamepad' is '@unchecked Sendable' because its SDL handle and state are
/// only touched from the main thread, through 'Input'
public final class Gamepad: @unchecked Sendable {
    /// the SDL joystick instance ID
    public let id: SDL_JoystickID

    private var handle: OpaquePointer?
    private var down = Set<GamepadButton>()
    private var pressed = Set<GamepadButton>()
    private var released = Set<GamepadButton>()
    private var axisValues: [GamepadAxis: Float] = [:]

    /// values within ±'deadzone' report as zero
    public var deadzone: Float = 0.1

    /// whether the gamepad is currently connected
    public private(set) var isConnected: Bool = false

    /// the SDL-reported name of the gamepad
    public var name: String {
        guard isConnected else { return "" }
        return String(cString: SDL_GetGamepadNameForID(id))
    }

    init(id: SDL_JoystickID) {
        self.id = id
    }

    deinit {
        close()
    }

    // MARK: - Connection

    func open() {
        guard !isConnected else { return }
        guard let handle = SDL_OpenGamepad(id) else { return }
        self.handle = handle
        isConnected = true
        prime()
    }

    func close() {
        guard isConnected else { return }
        if let handle {
            SDL_CloseGamepad(handle)
        }
        handle = nil
        isConnected = false
        down.removeAll()
        pressed.removeAll()
        released.removeAll()
        axisValues.removeAll()
    }

    /// records the current state without marking anything
    /// pressed (used when a gamepad is first connected)
    private func prime() {
        guard let handle else { return }
        for button in GamepadButton.allCases {
            if SDL_GetGamepadButton(handle, button.sdlValue) {
                down.insert(button)
            }
        }
        for axis in GamepadAxis.allCases {
            axisValues[axis] = normalized(
                SDL_GetGamepadAxis(handle, axis.sdlValue)
            )
        }
    }

    // MARK: - State queries

    /// whether 'button' is currently held
    public func isDown(_ button: GamepadButton) -> Bool {
        down.contains(button)
    }

    /// whether 'button' transitioned to down this frame
    public func wasPressed(_ button: GamepadButton) -> Bool {
        pressed.contains(button)
    }

    /// whether 'button' transitioned to up this frame
    public func wasReleased(_ button: GamepadButton) -> Bool {
        released.contains(button)
    }

    /// the value of 'axis' in [-1, 1], deadzoned
    public func value(of axis: GamepadAxis) -> Float {
        let value = axisValues[axis] ?? 0
        return abs(value) < deadzone ? 0 : value
    }

    /// eight-way direction derived from the left stick,
    /// or 'nil' when the stick is within the deadzone
    public var hat: GamepadHatDirection? {
        let x = value(of: .leftX)
        let y = value(of: .leftY)

        let horizontal = abs(x) > 0.5
        let vertical = abs(y) > 0.5
        guard horizontal || vertical else { return nil }

        switch (horizontal, vertical) {
        case (true, true):
            if x > 0 { return y > 0 ? .downRight : .upRight }
            return y > 0 ? .downLeft : .upLeft
        case (true, false):
            return x > 0 ? .right : .left
        case (false, true):
            return y > 0 ? .down : .up
        default:
            return nil
        }
    }

    // MARK: - Frame lifecycle

    func beginFrame() {
        pressed.removeAll(keepingCapacity: true)
        released.removeAll(keepingCapacity: true)
    }

    /// re-reads all buttons and axes from SDL, updating
    /// pressed/released by diffing against the previous
    /// frame's state
    func refresh() {
        guard isConnected, let handle else { return }

        for button in GamepadButton.allCases {
            set(button, isDown: SDL_GetGamepadButton(handle, button.sdlValue))
        }
        for axis in GamepadAxis.allCases {
            axisValues[axis] = normalized(
                SDL_GetGamepadAxis(handle, axis.sdlValue)
            )
        }
    }

    func set(_ button: GamepadButton, isDown: Bool) {
        if isDown {
            if down.insert(button).inserted { pressed.insert(button) }
        } else if down.remove(button) != nil {
            released.insert(button)
        }
    }

    func set(_ axis: GamepadAxis, value: Float) {
        axisValues[axis] = value
    }

    /// normalizes a raw SDL axis value (-32768...32767) to [-1, 1]
    private func normalized(_ rawValue: Int16) -> Float {
        Float(rawValue) / 32768.0
    }
}
