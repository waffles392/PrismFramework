import CSDL3

/// a standard gamepad button (SDL gamepad layout)
///
/// trigger buttons are exposed as axes ('GamepadAxis.triggerLeft'
/// / '.triggerRight'), not as buttons
public enum GamepadButton: Int, CaseIterable, Hashable, Sendable {
    /// bottom face button (Xbox A / PS Cross)
    case south
    /// right face button (Xbox B / PS Circle)
    case east
    /// left face button (Xbox X / PS Square)
    case west
    /// top face button (Xbox Y / PS Triangle)
    case north
    /// back / select button
    case back
    /// guide (system) button
    case guide
    /// start / menu button
    case start
    /// left stick press
    case leftStick
    /// right stick press
    case rightStick
    /// left shoulder (LB / L1)
    case leftShoulder
    /// right shoulder (RB / R1)
    case rightShoulder
    /// d-pad up
    case dpadUp
    /// d-pad down
    case dpadDown
    /// d-pad left
    case dpadLeft
    /// d-pad right
    case dpadRight
    /// additional button (share, microphone, capture)
    case misc1

    var sdlValue: SDL_GamepadButton {
        switch self {
        case .south: SDL_GAMEPAD_BUTTON_SOUTH
        case .east: SDL_GAMEPAD_BUTTON_EAST
        case .west: SDL_GAMEPAD_BUTTON_WEST
        case .north: SDL_GAMEPAD_BUTTON_NORTH
        case .back: SDL_GAMEPAD_BUTTON_BACK
        case .guide: SDL_GAMEPAD_BUTTON_GUIDE
        case .start: SDL_GAMEPAD_BUTTON_START
        case .leftStick: SDL_GAMEPAD_BUTTON_LEFT_STICK
        case .rightStick: SDL_GAMEPAD_BUTTON_RIGHT_STICK
        case .leftShoulder: SDL_GAMEPAD_BUTTON_LEFT_SHOULDER
        case .rightShoulder: SDL_GAMEPAD_BUTTON_RIGHT_SHOULDER
        case .dpadUp: SDL_GAMEPAD_BUTTON_DPAD_UP
        case .dpadDown: SDL_GAMEPAD_BUTTON_DPAD_DOWN
        case .dpadLeft: SDL_GAMEPAD_BUTTON_DPAD_LEFT
        case .dpadRight: SDL_GAMEPAD_BUTTON_DPAD_RIGHT
        case .misc1: SDL_GAMEPAD_BUTTON_MISC1
        }
    }

    /// creates a button from an SDL gamepad button raw value
    init?(sdlRawValue: Int32) {
        guard let button = GamepadButton.allCases.first(
            where: { $0.sdlValue.rawValue == sdlRawValue }
        ) else { return nil }
        self = button
    }
}
