import Math

/// a raw input event, drained from SDL before it is mapped to an engine event
///
/// kept separate from 'EngineEvent' so the Input module never depends on
/// Events. 'Prism.publishInputEvent' does the translation
public enum InputEvent: Equatable, Sendable {
    case quit
    case keyDown(Key, isRepeat: Bool)
    case keyUp(Key)
    case mouseMoved(position: Vector2D, delta: Vector2D)
    case mouseButtonDown(MouseButton, position: Vector2D)
    case mouseButtonUp(MouseButton, position: Vector2D)
    case mouseWheel(Vector2D)
    case mouseEnteredWindow
    case mouseLeftWindow
    case textInput(String)
    case gamepadConnected(Int32)
    case gamepadDisconnected(Int32)
    case gamepadButtonDown(Int32, GamepadButton)
    case gamepadButtonUp(Int32, GamepadButton)
    case gamepadAxis(Int32, GamepadAxis, Float)
}
