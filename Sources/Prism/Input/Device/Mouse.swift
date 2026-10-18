import CSDL3
import Math

/// frame-based mouse state
///
/// the mouse tracks position, per-frame delta, wheel and button state. cursor
/// visibility is a global (not per-window) SDL setting and lives here in
/// 'hideCursor()' / 'showCursor()'; relative mode and grab are per-window and
/// live on 'Window' - 'setMouseRelativeMode(_:)' and 'setMouseGrab(_:)'
///
/// 'Mouse' is '@unchecked Sendable' because its state is mutated and read
/// only from the main thread, through 'Input'
public final class Mouse: @unchecked Sendable {
    public private(set) var position = Vector2D.zero
    public private(set) var delta = Vector2D.zero
    public private(set) var wheel = Vector2D.zero

    /// whether the cursor is inside the application window
    public private(set) var isInsideWindow = true

    private var down = Set<MouseButton>()
    private var pressed = Set<MouseButton>()
    private var released = Set<MouseButton>()

    public func isDown(_ button: MouseButton) -> Bool { down.contains(button) }
    public func wasPressed(_ button: MouseButton) -> Bool { pressed.contains(button) }
    public func wasReleased(_ button: MouseButton) -> Bool { released.contains(button) }

    /// hides the mouse cursor (global SDL setting)
    public static func hideCursor() {
        SDL_HideCursor()
    }

    /// shows the mouse cursor (global SDL setting)
    public static func showCursor() {
        SDL_ShowCursor()
    }

    /// whether the mouse cursor is currently visible
    public static var isCursorVisible: Bool {
        SDL_CursorVisible()
    }

    func beginFrame() {
        delta = .zero
        wheel = .zero
        pressed.removeAll(keepingCapacity: true)
        released.removeAll(keepingCapacity: true)
    }

    func move(to position: Vector2D, delta: Vector2D) {
        self.position = position
        self.delta = self.delta + delta
    }

    func setInsideWindow(_ inside: Bool) {
        isInsideWindow = inside
    }

    func set(_ button: MouseButton, isDown: Bool) {
        if isDown {
            if down.insert(button).inserted { pressed.insert(button) }
        } else if down.remove(button) != nil {
            released.insert(button)
        }
    }

    func addWheel(_ amount: Vector2D) { wheel = wheel + amount }
}
