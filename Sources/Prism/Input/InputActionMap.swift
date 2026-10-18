/// a container for a named set of input actions and axes
///
/// build one or more action maps (e.g. "Game", "UI", "Editor") and register
/// them with 'InputManager'. only one map is active at a time
///
/// ```swift
/// var gameMap = InputActionMap(name: "Game")
/// gameMap.addAction(InputAction(name: "Fire", keys: [.space], mouseButtons: [.left]))
/// gameMap.addAction(InputAction(name: "Dash", keys: [.leftShift]))
/// gameMap.addAxis2D(InputAxis2D(
///     name: "Move",
///     rightKeys: [.d], leftKeys: [.a],
///     upKeys: [.w], downKeys: [.s]
/// ))
/// inputManager.register(map: gameMap)
/// inputManager.activate(mapNamed: "Game")
/// ```
public struct InputActionMap: Sendable {
    public let name: String
    private var actions: [String: InputAction] = [:]
    private var axes1D: [String: InputAxis1D] = [:]
    private var axes2D: [String: InputAxis2D] = [:]

    public init(name: String) {
        precondition(!name.isEmpty, "InputActionMap name must not be empty")
        self.name = name
    }

    // MARK: - Mutations

    public mutating func addAction(_ action: InputAction) {
        actions[action.name] = action
    }

    public mutating func removeAction(named name: String) {
        actions.removeValue(forKey: name)
    }

    public mutating func addAxis1D(_ axis: InputAxis1D) {
        axes1D[axis.name] = axis
    }

    public mutating func removeAxis1D(named name: String) {
        axes1D.removeValue(forKey: name)
    }

    public mutating func addAxis2D(_ axis: InputAxis2D) {
        axes2D[axis.name] = axis
    }

    public mutating func removeAxis2D(named name: String) {
        axes2D.removeValue(forKey: name)
    }

    // MARK: - Queries

    /// returns the action definition for 'name', if registered
    public func action(named name: String) -> InputAction? {
        actions[name]
    }

    /// returns the 1D axis definition for 'name', if registered
    public func axis1D(named name: String) -> InputAxis1D? {
        axes1D[name]
    }

    /// returns the 2D axis definition for 'name', if registered
    public func axis2D(named name: String) -> InputAxis2D? {
        axes2D[name]
    }

    internal var allActions: Dictionary<String, InputAction>.Values { actions.values }
}
