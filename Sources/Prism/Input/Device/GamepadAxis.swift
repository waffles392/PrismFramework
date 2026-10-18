import CSDL3

/// a standard gamepad axis (SDL gamepad layout)
public enum GamepadAxis: Int, CaseIterable, Hashable, Sendable {
    /// left stick horizontal axis
    case leftX
    /// left stick vertical axis
    case leftY
    /// right stick horizontal axis
    case rightX
    /// right stick vertical axis
    case rightY
    /// left trigger (0...1 when pulled)
    case triggerLeft
    /// right trigger (0...1 when pulled)
    case triggerRight

    var sdlValue: SDL_GamepadAxis {
        switch self {
        case .leftX: SDL_GAMEPAD_AXIS_LEFTX
        case .leftY: SDL_GAMEPAD_AXIS_LEFTY
        case .rightX: SDL_GAMEPAD_AXIS_RIGHTX
        case .rightY: SDL_GAMEPAD_AXIS_RIGHTY
        case .triggerLeft: SDL_GAMEPAD_AXIS_LEFT_TRIGGER
        case .triggerRight: SDL_GAMEPAD_AXIS_RIGHT_TRIGGER
        }
    }

    /// creates an axis from an SDL gamepad axis raw value
    init?(sdlRawValue: Int32) {
        guard let axis = GamepadAxis.allCases.first(
            where: { $0.sdlValue.rawValue == sdlRawValue }
        ) else { return nil }
        self = axis
    }
}

/// eight-way direction of a gamepad hat (derived from
/// a stick axis pair)
public enum GamepadHatDirection: Hashable, Sendable {
    case centered
    case up
    case down
    case left
    case right
    case upLeft
    case upRight
    case downLeft
    case downRight
}
