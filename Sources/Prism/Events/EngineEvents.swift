import Input
import Math

// MARK: - Window Events

/// fired when the window is resized
public final class WindowResizedEvent: BaseEvent {
    public let width: Int
    public let height: Int
    public init(width: Int, height: Int, timestamp: Float = 0) {
        self.width = width
        self.height = height
        super.init(timestamp: timestamp)
    }
}

/// fired when the window is moved
public final class WindowMovedEvent: BaseEvent {
    public let position: Vector2D
    public init(position: Vector2D, timestamp: Float = 0) {
        self.position = position
        super.init(timestamp: timestamp)
    }
}

/// fired when the window gains or loses keyboard focus
public final class WindowFocusedEvent: BaseEvent {
    public let focused: Bool
    public init(focused: Bool, timestamp: Float = 0) {
        self.focused = focused
        super.init(timestamp: timestamp)
    }
}

/// fired when the window is minimized
public final class WindowMinimizedEvent: BaseEvent {}

/// fired when a minimized or maximized window is restored
public final class WindowRestoredEvent: BaseEvent {}

/// fired when the window is maximized
public final class WindowMaximizedEvent: BaseEvent {}

/// fired when a hidden window is shown
public final class WindowShownEvent: BaseEvent {}

/// fired when the window is hidden
public final class WindowHiddenEvent: BaseEvent {}

/// fired when the user requests the application to close
public final class WindowCloseEvent: BaseEvent {}

// MARK: - Keyboard Events

/// fired when a key is pressed down
public final class KeyPressedEvent: BaseEvent {
    public let key: Key
    public let isRepeat: Bool
    public init(key: Key, isRepeat: Bool, timestamp: Float = 0) {
        self.key = key
        self.isRepeat = isRepeat
        super.init(timestamp: timestamp)
    }
}

/// fired when a key is released
public final class KeyReleasedEvent: BaseEvent {
    public let key: Key
    public init(key: Key, timestamp: Float = 0) {
        self.key = key
        super.init(timestamp: timestamp)
    }
}

/// fired for every text character produced by the keyboard
public final class TextInputEvent: BaseEvent {
    public let text: String
    public init(text: String, timestamp: Float = 0) {
        self.text = text
        super.init(timestamp: timestamp)
    }
}

// MARK: - Mouse Events

/// fired when the mouse cursor moves
public final class MouseMovedEvent: BaseEvent {
    public let position: Vector2D
    public let delta: Vector2D
    public init(position: Vector2D, delta: Vector2D, timestamp: Float = 0) {
        self.position = position
        self.delta = delta
        super.init(timestamp: timestamp)
    }
}

/// fired when a mouse button is pressed
public final class MouseButtonPressedEvent: BaseEvent {
    public let button: MouseButton
    public let position: Vector2D
    public init(button: MouseButton, position: Vector2D, timestamp: Float = 0) {
        self.button = button
        self.position = position
        super.init(timestamp: timestamp)
    }
}

/// fired when a mouse button is released
public final class MouseButtonReleasedEvent: BaseEvent {
    public let button: MouseButton
    public let position: Vector2D
    public init(button: MouseButton, position: Vector2D, timestamp: Float = 0) {
        self.button = button
        self.position = position
        super.init(timestamp: timestamp)
    }
}

/// fired when the mouse wheel is scrolled
public final class MouseWheelEvent: BaseEvent {
    public let delta: Vector2D
    public init(delta: Vector2D, timestamp: Float = 0) {
        self.delta = delta
        super.init(timestamp: timestamp)
    }
}

// MARK: - Gamepad Events

/// fired when a gamepad is connected
public final class GamepadConnectedEvent: BaseEvent {
    /// the SDL joystick instance ID of the gamepad
    public let gamepadID: Int32
    public init(gamepadID: Int32, timestamp: Float = 0) {
        self.gamepadID = gamepadID
        super.init(timestamp: timestamp)
    }
}

/// fired when a gamepad is disconnected
public final class GamepadDisconnectedEvent: BaseEvent {
    /// the SDL joystick instance ID of the gamepad
    public let gamepadID: Int32
    public init(gamepadID: Int32, timestamp: Float = 0) {
        self.gamepadID = gamepadID
        super.init(timestamp: timestamp)
    }
}

/// fired when a gamepad button is pressed or released
public final class GamepadButtonEvent: BaseEvent {
    /// the SDL joystick instance ID of the gamepad
    public let gamepadID: Int32
    public let button: GamepadButton
    public let isDown: Bool
    public init(
        gamepadID: Int32,
        button: GamepadButton,
        isDown: Bool,
        timestamp: Float = 0
    ) {
        self.gamepadID = gamepadID
        self.button = button
        self.isDown = isDown
        super.init(timestamp: timestamp)
    }
}

/// fired when a gamepad axis moves beyond the deadzone
public final class GamepadAxisEvent: BaseEvent {
    /// the SDL joystick instance ID of the gamepad
    public let gamepadID: Int32
    public let axis: GamepadAxis
    /// the axis value in [-1, 1]
    public let value: Float
    public init(
        gamepadID: Int32,
        axis: GamepadAxis,
        value: Float,
        timestamp: Float = 0
    ) {
        self.gamepadID = gamepadID
        self.axis = axis
        self.value = value
        super.init(timestamp: timestamp)
    }
}

// MARK: - Time Events

/// fired once per frame by the engine run loop
public final class FrameTickEvent: BaseEvent {
    /// scaled delta time of this frame
    public let deltaTime: Float
    /// raw delta time of this frame (ignores timeScale and pause)
    public let unscaledDeltaTime: Float
    /// the engine's zero-based frame counter
    public let frameIndex: Int
    /// the number of fixed simulation steps run this frame
    ///
    /// zero when the clock is variable-timestep
    public let fixedStepCount: Int
    /// the fraction of a fixed step accumulated since the last step
    ///
    /// in '[0, 1)' under a fixed rate, and '[1]' when variable-timestep
    public let interpolationAlpha: Float
    public init(
        deltaTime: Float,
        unscaledDeltaTime: Float,
        frameIndex: Int,
        fixedStepCount: Int = 0,
        interpolationAlpha: Float = 1,
        timestamp: Float = 0
    ) {
        self.deltaTime = deltaTime
        self.unscaledDeltaTime = unscaledDeltaTime
        self.frameIndex = frameIndex
        self.fixedStepCount = fixedStepCount
        self.interpolationAlpha = interpolationAlpha
        super.init(timestamp: timestamp)
    }
}

/// fired when 'Time.timeScale' changes
public final class TimeScaleChangedEvent: BaseEvent {
    public let oldValue: Float
    public let newValue: Float
    public init(oldValue: Float, newValue: Float, timestamp: Float = 0) {
        self.oldValue = oldValue
        self.newValue = newValue
        super.init(timestamp: timestamp)
    }
}

/// fired when the engine clock pauses
public final class EnginePausedEvent: BaseEvent {}

/// fired when the engine clock resumes
public final class EngineResumedEvent: BaseEvent {}

// MARK: - Input Action Events

/// fired when a named input action is triggered (pressed/released)
public final class InputActionTriggeredEvent: BaseEvent {
    public enum TriggerState {
        case pressed
        case released
    }
    public let actionName: String
    public let state: TriggerState
    public init(actionName: String, state: TriggerState, timestamp: Float = 0) {
        self.actionName = actionName
        self.state = state
        super.init(timestamp: timestamp)
    }
}
