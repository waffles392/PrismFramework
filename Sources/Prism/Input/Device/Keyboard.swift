import CSDL3

/// modifier-key flags derived from the current key state
public struct KeyModifiers: OptionSet, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let shift = KeyModifiers(rawValue: 1 << 0)
    public static let control = KeyModifiers(rawValue: 1 << 1)
    public static let alt = KeyModifiers(rawValue: 1 << 2)
    public static let gui = KeyModifiers(rawValue: 1 << 3)

    /// all modifiers
    public static let all: KeyModifiers = [.shift, .control, .alt, .gui]
}

/// frame-based keyboard state
///
/// the keyboard is scancode-first: keys are identified by
/// physical position (see 'Key'), so the same key produces
/// the same 'Key' value regardless of layout or modifier
///
/// 'Keyboard' is '@unchecked Sendable' because its state is mutated and read
/// only from the main thread, through 'Input'
public final class Keyboard: @unchecked Sendable {
    private var down = Set<Key>()
    private var pressed = Set<Key>()
    private var released = Set<Key>()

    /// whether 'key' is currently held
    public func isDown(_ key: Key) -> Bool { down.contains(key) }
    /// whether 'key' transitioned to down this frame
    public func wasPressed(_ key: Key) -> Bool { pressed.contains(key) }
    /// whether 'key' transitioned to up this frame
    public func wasReleased(_ key: Key) -> Bool { released.contains(key) }

    /// the modifier keys currently held (both halves of each
    /// pair are folded together)
    public var modifiers: KeyModifiers {
        var result: KeyModifiers = []
        if down.contains(.leftShift) || down.contains(.rightShift) {
            result.insert(.shift)
        }
        if down.contains(.leftControl) || down.contains(.rightControl) {
            result.insert(.control)
        }
        if down.contains(.leftAlt) || down.contains(.rightAlt) {
            result.insert(.alt)
        }
        if down.contains(.leftGUI) || down.contains(.rightGUI) {
            result.insert(.gui)
        }
        return result
    }

    /// a snapshot of every key currently held
    public var allPressed: Set<Key> { down }

    func beginFrame() {
        pressed.removeAll(keepingCapacity: true)
        released.removeAll(keepingCapacity: true)
    }

    func set(_ key: Key, isDown: Bool) {
        if isDown {
            if down.insert(key).inserted { pressed.insert(key) }
        } else if down.remove(key) != nil {
            released.insert(key)
        }
    }

    func syncFromSDL() {
        var count: Int32 = 0
        guard let states = SDL_GetKeyboardState(&count) else { return }

        for rawValue in 0..<Int(count) {
            let key = Key(rawValue: Int32(rawValue))
            if states[rawValue] { down.insert(key) } else { down.remove(key) }
        }
    }
}
