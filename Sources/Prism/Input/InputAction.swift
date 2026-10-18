/// a named digital input action bound to one or more keys,
/// mouse buttons, or gamepad buttons
///
/// ```swift
/// let fire = InputAction(name: "Fire", keys: [.space], mouseButtons: [.left], gamepadButtons: [.south])
/// ```
public struct InputAction: Sendable {
    public let name: String
    /// keyboard keys that trigger this action
    public var keys: Set<Key>
    /// mouse buttons that trigger this action
    public var mouseButtons: Set<MouseButton>
    /// gamepad buttons that trigger this action
    public var gamepadButtons: Set<GamepadButton>

    public init(
        name: String,
        keys: Set<Key> = [],
        mouseButtons: Set<MouseButton> = [],
        gamepadButtons: Set<GamepadButton> = []
    ) {
        precondition(!name.isEmpty, "InputAction name must not be empty")
        self.name = name
        self.keys = keys
        self.mouseButtons = mouseButtons
        self.gamepadButtons = gamepadButtons
    }
}
