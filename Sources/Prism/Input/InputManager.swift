import Math

/// evaluates the active 'InputActionMap' each frame, translating raw
/// 'InputEvent' streams into named action and axis queries
///
/// reports press/release transitions through 'onActionTriggered'; the engine
/// forwards these to the event bus as 'InputActionTriggeredEvent' so game
/// systems can react declaratively without polling
///
/// usage:
/// ```swift
/// let inputManager = InputManager(keyboard: input.keyboard, mouse: input.mouse)
/// var gameMap = InputActionMap(name: "Game")
/// gameMap.addAction(InputAction(name: "Fire", keys: [.space]))
/// gameMap.addAxis2D(InputAxis2D(name: "Move", rightKeys: [.d], leftKeys: [.a], upKeys: [.w], downKeys: [.s]))
/// inputManager.register(map: gameMap)
/// inputManager.activate(mapNamed: "Game")
///
/// // In update:
/// if inputManager.isActionJustPressed("Fire") { ... }
/// let move: Vector2D = inputManager.axis2D("Move")
/// ```
@MainActor
public final class InputManager {
    private var maps: [String: InputActionMap] = [:]
    private var activeMap: InputActionMap?

    /// called when an action transitions between down and up, with the
    /// action's name and its new state
    public var onActionTriggered: (@MainActor (_ actionName: String, _ isPressed: Bool) -> Void)?

    /// per-action state tracked across frames
    private var actionState: [String: Bool] = [:]       // current isDown
    private var prevActionState: [String: Bool] = [:]   // previous frame isDown

    private let keyboard: Keyboard
    private let mouse: Mouse
    /// supplies the currently connected gamepads
    private let gamepads: () -> [Gamepad]

    public init(
        keyboard: Keyboard,
        mouse: Mouse,
        gamepads: @escaping () -> [Gamepad] = { [] }
    ) {
        self.keyboard = keyboard
        self.mouse = mouse
        self.gamepads = gamepads
    }

    // MARK: - Map registration

    public func register(map: InputActionMap) {
        maps[map.name] = map
    }

    public func unregister(mapNamed name: String) {
        maps.removeValue(forKey: name)
        if activeMap?.name == name { activeMap = nil }
    }

    public func activate(mapNamed name: String) {
        activeMap = maps[name]
        actionState.removeAll()
        prevActionState.removeAll()
    }

    public func deactivateCurrentMap() {
        activeMap = nil
        actionState.removeAll()
        prevActionState.removeAll()
    }

    // MARK: - Per-frame update

    /// call once per frame after 'Input.update()' to evaluate the active map
    /// reports press/release transitions through 'onActionTriggered'
    public func update() {
        guard let map = activeMap else { return }
        prevActionState = actionState

        for action in map.allActions {
            let isDown = isActionDown(action)
            actionState[action.name] = isDown

            let wasDown = prevActionState[action.name] ?? false
            if isDown && !wasDown {
                onActionTriggered?(action.name, true)
            } else if !isDown && wasDown {
                onActionTriggered?(action.name, false)
            }
        }
    }

    // MARK: - Action queries

    /// 'true' while all of the action's bound keys/buttons are held down
    public func isActionDown(_ name: String) -> Bool {
        guard let map = activeMap, let action = map.action(named: name) else { return false }
        return isActionDown(action)
    }

    /// 'true' only on the frame the action transitioned from released to pressed
    public func isActionJustPressed(_ name: String) -> Bool {
        let current = actionState[name] ?? false
        let previous = prevActionState[name] ?? false
        return current && !previous
    }

    /// 'true' only on the frame the action transitioned from pressed to released
    public func isActionJustReleased(_ name: String) -> Bool {
        let current = actionState[name] ?? false
        let previous = prevActionState[name] ?? false
        return !current && previous
    }

    // MARK: - Axis queries

    /// returns the current scalar value of a 1D axis in [-1, 1]
    public func axis1D(_ name: String) -> Float {
        guard let map = activeMap, let axis = map.axis1D(named: name) else { return 0 }
        var value: Float = 0
        for key in axis.positiveKeys where keyboard.isDown(key) { value += 1 }
        for key in axis.negativeKeys where keyboard.isDown(key) { value -= 1 }
        for binding in axis.gamepadAxes {
            value += gamepadAxisContribution(binding)
        }
        value = value.clamped(to: -1...1)
        return abs(value) < axis.deadzone ? 0 : value
    }

    /// returns the current vector value of a 2D axis
    /// optionally normalized to unit length when the axis has 'normalize = true'
    public func axis2D(_ name: String) -> Vector2D {
        guard let map = activeMap, let axis = map.axis2D(named: name) else { return .zero }
        var x: Float = 0
        var y: Float = 0
        for key in axis.rightKeys where keyboard.isDown(key) { x += 1 }
        for key in axis.leftKeys  where keyboard.isDown(key) { x -= 1 }
        for key in axis.upKeys    where keyboard.isDown(key) { y += 1 }
        for key in axis.downKeys  where keyboard.isDown(key) { y -= 1 }
        for binding in axis.gamepadXAxes {
            x += gamepadAxisContribution(binding)
        }
        for binding in axis.gamepadYAxes {
            y += gamepadAxisContribution(binding)
        }
        var vector = Vector2D(x, y)
        if vector.length < axis.deadzone { return .zero }
        if axis.normalize && vector.length > Float.ulpOfOne { vector = vector.normalized }
        return vector
    }

    // MARK: - Private helpers

    /// sum of the signed contributions of 'binding' across all
    /// connected gamepads whose axis magnitude reaches the threshold
    private func gamepadAxisContribution(_ binding: GamepadAxisBinding) -> Float {
        var total: Float = 0
        for gamepad in gamepads() {
            let value = gamepad.value(of: binding.axis)
            if abs(value) >= binding.threshold {
                total += binding.sign * min(1, abs(value))
            }
        }
        return total
    }

    private func isActionDown(_ action: InputAction) -> Bool {
        for key in action.keys where keyboard.isDown(key) { return true }
        for button in action.mouseButtons where mouse.isDown(button) { return true }
        for gamepad in gamepads() {
            for button in action.gamepadButtons where gamepad.isDown(button) { return true }
        }
        return false
    }
}

private extension Float {
    func clamped(to range: ClosedRange<Float>) -> Float {
        min(range.upperBound, max(range.lowerBound, self))
    }
}
