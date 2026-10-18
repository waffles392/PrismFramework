/// a mouse button understood by the input wrapper
public enum MouseButton: UInt8, Hashable, Sendable {
    case left = 1
    case middle = 2
    case right = 3
    case x1 = 4
    case x2 = 5
    case other

    init(sdlRawValue: UInt8) {
        self = MouseButton(rawValue: sdlRawValue) ?? .other
    }
}
