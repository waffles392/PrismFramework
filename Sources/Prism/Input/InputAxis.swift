import Math

/// a binding of a single gamepad axis to a 1D axis value
///
/// when the axis magnitude reaches 'threshold', it
/// contributes 'sign' (scaled by its magnitude) to the
/// owning axis
public struct GamepadAxisBinding: Sendable, Hashable {
    /// the physical axis to read
    public var axis: GamepadAxis
    /// magnitude below which the axis is ignored
    public var threshold: Float
    /// the sign of this axis's contribution (+1 or -1)
    public var sign: Float

    public init(
        axis: GamepadAxis,
        threshold: Float = 0.1,
        sign: Float = 1
    ) {
        precondition(threshold >= 0, "Gamepad axis threshold must be non-negative")
        self.axis = axis
        self.threshold = threshold
        self.sign = sign == 0 ? 1 : (sign > 0 ? 1 : -1)
    }
}

/// a 1D scalar axis bound to positive and negative key
/// pairs, and optionally to gamepad axes
///
/// ```swift
/// let throttle = InputAxis1D(
///     name: "Throttle",
///     positiveKeys: [.w, .up],
///     negativeKeys: [.s, .down],
///     gamepadAxes: [GamepadAxisBinding(axis: .leftY, sign: -1)]
/// )
/// ```
public struct InputAxis1D: Sendable {
    public let name: String
    /// keys that contribute +1 to the axis value
    public var positiveKeys: Set<Key>
    /// keys that contribute -1 to the axis value
    public var negativeKeys: Set<Key>
    /// gamepad axes that contribute to the axis value
    public var gamepadAxes: [GamepadAxisBinding]
    /// values within [-deadzone, deadzone] are clamped to 0
    public var deadzone: Float

    public init(
        name: String,
        positiveKeys: Set<Key> = [],
        negativeKeys: Set<Key> = [],
        gamepadAxes: [GamepadAxisBinding] = [],
        deadzone: Float = 0.1
    ) {
        precondition(!name.isEmpty, "InputAxis1D name must not be empty")
        self.name = name
        self.positiveKeys = positiveKeys
        self.negativeKeys = negativeKeys
        self.gamepadAxes = gamepadAxes
        self.deadzone = max(0, deadzone)
    }
}

/// a 2D vector axis bound to key pairs for each component,
/// and optionally to gamepad axes
///
/// ```swift
/// let movement = InputAxis2D(
///     name: "Movement",
///     rightKeys: [.d, .right], leftKeys: [.a, .left],
///     upKeys: [.w, .up], downKeys: [.s, .down],
///     gamepadAxes: [
///         GamepadAxisBinding(axis: .leftX),
///         GamepadAxisBinding(axis: .leftY, sign: -1)
///     ]
/// )
/// ```
public struct InputAxis2D: Sendable {
    public let name: String
    public var rightKeys: Set<Key>
    public var leftKeys: Set<Key>
    public var upKeys: Set<Key>
    public var downKeys: Set<Key>
    /// gamepad axes bound to the X component
    public var gamepadXAxes: [GamepadAxisBinding]
    /// gamepad axes bound to the Y component
    public var gamepadYAxes: [GamepadAxisBinding]
    /// values with magnitude below the deadzone are zeroed
    public var deadzone: Float
    /// when true, the output vector is normalized to unit length (if non-zero)
    public var normalize: Bool

    public init(
        name: String,
        rightKeys: Set<Key> = [],
        leftKeys: Set<Key> = [],
        upKeys: Set<Key> = [],
        downKeys: Set<Key> = [],
        gamepadXAxes: [GamepadAxisBinding] = [],
        gamepadYAxes: [GamepadAxisBinding] = [],
        deadzone: Float = 0.1,
        normalize: Bool = true
    ) {
        precondition(!name.isEmpty, "InputAxis2D name must not be empty")
        self.name = name
        self.rightKeys = rightKeys
        self.leftKeys = leftKeys
        self.upKeys = upKeys
        self.downKeys = downKeys
        self.gamepadXAxes = gamepadXAxes
        self.gamepadYAxes = gamepadYAxes
        self.deadzone = max(0, deadzone)
        self.normalize = normalize
    }
}
