import CSDL3

/// SDL's event enum imports as `UInt32` on Linux and `Int32` with MSVC,
/// so normalize it before comparing with `SDL_Event.type`
extension SDL_EventType {
    fileprivate var rawUInt32: UInt32 { UInt32(truncatingIfNeeded: rawValue) }
}

// MARK: - SDL window flag constants

/// SDL window state flags from `SDL_video.h`
///
/// the headers expose these as `#define` macros over a `Uint64` typedef,
/// so they are re-declared here as raw `SDL_WindowFlags` values
private let sdlWindowHidden: SDL_WindowFlags = 0x0000_0000_0000_0008
private let sdlWindowBorderless: SDL_WindowFlags = 0x0000_0000_0000_0010
private let sdlWindowResizable: SDL_WindowFlags = 0x0000_0000_0000_0020
private let sdlWindowMinimized: SDL_WindowFlags = 0x0000_0000_0000_0040
private let sdlWindowMaximized: SDL_WindowFlags = 0x0000_0000_0000_0080
private let sdlWindowMouseGrabbed: SDL_WindowFlags = 0x0000_0000_0000_0100
private let sdlWindowInputFocus: SDL_WindowFlags = 0x0000_0000_0000_0200
private let sdlWindowHighPixelDensity: SDL_WindowFlags = 0x0000_0000_0000_2000
private let sdlWindowAlwaysOnTop: SDL_WindowFlags = 0x0000_0001_0000_0000

/// `SDL_WINDOWPOS_CENTERED` from `SDL_video.h`
///
/// the macro does not cross the C boundary, so its value is used directly
private let sdlWindowPosCentered: Int32 = 0x2FFF_0000

// MARK: - WindowFlags

/// flags for creating a `Window`
///
/// `vsync` is applied by the GPU swapchain; the rest map to SDL creation
/// flags or are applied right after the window exists
public struct WindowFlags: OptionSet, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    /// present with vsync through the GPU swapchain
    public static let vsync = WindowFlags(rawValue: 1 << 0)
    /// the user can resize the window
    public static let resizable = WindowFlags(rawValue: 1 << 1)
    /// use a high-density back buffer when the display supports it
    public static let highDPI = WindowFlags(rawValue: 1 << 2)
    /// no title bar or border
    public static let borderless = WindowFlags(rawValue: 1 << 3)
    /// stay above other windows
    public static let alwaysOnTop = WindowFlags(rawValue: 1 << 4)
    /// start minimized after creation
    public static let startMinimized = WindowFlags(rawValue: 1 << 5)
    /// start maximized after creation
    public static let startMaximized = WindowFlags(rawValue: 1 << 6)

    /// engine default: vsync on, user-resizable
    public static let recommended: WindowFlags = [.resizable, .vsync, .highDPI]

    /// the SDL creation flags
    ///
    /// `vsync`, `startMinimized` and `startMaximized` are not SDL creation
    /// flags; vsync is a GPU setting and the last two are applied after creation
    var sdlCreationFlags: SDL_WindowFlags {
        var flags: SDL_WindowFlags = 0
        if contains(.resizable) { flags |= sdlWindowResizable }
        if contains(.highDPI) { flags |= sdlWindowHighPixelDensity }
        if contains(.borderless) { flags |= sdlWindowBorderless }
        if contains(.alwaysOnTop) { flags |= sdlWindowAlwaysOnTop }
        return flags
    }
}

/// owns the SDL video subsystem and the app window
///
/// `Window` is `@MainActor` because SDL window and video calls must run on
/// the main thread
@MainActor
public final class Window {
    /// the current title
    public private(set) var title: String
    /// width in logical points
    public private(set) var width: Int32
    /// height in logical points
    public private(set) var height: Int32
    /// the underlying SDL handle
    public let handle: OpaquePointer

    /// the flags the window was requested with
    ///
    /// not live state: `vsync` goes to the GPU swapchain, and
    /// `startMinimized` / `startMaximized` are applied after creation
    public let flags: WindowFlags

    /// target frame rate for the engine's pacer
    ///
    /// `nil` means unlimited; `PrismEnvironment.lockFramerate` overrides it
    public var targetFPS: Int?

    /// drawable size in physical pixels
    ///
    /// differs from `width` / `height` on high-DPI displays
    public private(set) var pixelSize: (width: Int32, height: Int32)

    /// display scale (e.g. `2.0` on a Retina display)
    public private(set) var displayScale: Float

    public init(
        title: String = "Prism",
        width: Int32 = 800,
        height: Int32 = 600,
        flags: WindowFlags = .recommended
    ) {
        self.title = title
        self.width = width
        self.height = height
        self.flags = flags
        self.pixelSize = (width, height)
        self.displayScale = 1

        guard SDL_InitSubSystem(SDL_INIT_VIDEO) else {
            fatalError("SDL video initialization failed: \(String(cString: SDL_GetError()))")
        }

        guard let handle = SDL_CreateWindow(title, width, height, flags.sdlCreationFlags) else {
            SDL_QuitSubSystem(SDL_INIT_VIDEO)
            fatalError("SDL window creation failed: \(String(cString: SDL_GetError()))")
        }

        self.handle = handle
        refreshSize()

        // flags applied after creation
        if flags.contains(.startMinimized) { minimize() }
        if flags.contains(.startMaximized) { maximize() }
    }

    /// re-reads size, pixel size and display scale from SDL
    ///
    /// updates the cached metrics only; it does not publish
    /// `WindowResizedEvent` - the engine calls it once per frame
    package func refreshSize() {
        var width: Int32 = 0
        var height: Int32 = 0
        guard SDL_GetWindowSize(handle, &width, &height) else { return }
        self.width = width
        self.height = height

        var pixelWidth: Int32 = 0
        var pixelHeight: Int32 = 0
        if SDL_GetWindowSizeInPixels(handle, &pixelWidth, &pixelHeight) {
            pixelSize = (pixelWidth, pixelHeight)
        }

        displayScale = Float(SDL_GetWindowDisplayScale(handle))
    }

    /// sets the size in logical points
    public func setSize(width: Int32, height: Int32) {
        guard SDL_SetWindowSize(handle, width, height) else { return }
        self.width = width
        self.height = height
        refreshSize()
    }

    // MARK: - Sizing Constraints

    /// sets the minimum size the user can resize to
    public func setMinimumSize(width: Int32, height: Int32) {
        SDL_SetWindowMinimumSize(handle, width, height)
    }

    /// sets the maximum size the user can resize to
    public func setMaximumSize(width: Int32, height: Int32) {
        SDL_SetWindowMaximumSize(handle, width, height)
    }

    // MARK: - Position & Focus

    /// centers the window on the primary display
    public func center() { move(x: sdlWindowPosCentered, y: sdlWindowPosCentered) }

    /// moves the window to `(x, y)`
    public func move(x: Int32, y: Int32) { SDL_SetWindowPosition(handle, x, y) }

    /// window position in screen coordinates
    public var position: (x: Int32, y: Int32) {
        var x: Int32 = 0
        var y: Int32 = 0
        SDL_GetWindowPosition(handle, &x, &y)
        return (x, y)
    }

    /// sets the title and updates the cached value when SDL accepts it
    public func setTitle(_ title: String) {
        guard SDL_SetWindowTitle(handle, title) else { return }
        self.title = title
    }

    /// raises the window and gives it input focus
    public func focus() { SDL_RaiseWindow(handle) }

    /// asks the window to close, like the window-manager close button
    ///
    /// the run loop sees it as a `WindowCloseEvent`
    public func close() {
        var event = SDL_Event()
        event.type = SDL_EVENT_QUIT.rawUInt32
        event.quit.timestamp = SDL_GetTicksNS()
        SDL_PushEvent(&event)
    }

    /// minimizes the window
    public func minimize() { SDL_MinimizeWindow(handle) }

    /// restores a minimized or maximized window
    public func restore() { SDL_RestoreWindow(handle) }

    /// maximizes the window
    public func maximize() { SDL_MaximizeWindow(handle) }

    /// shows a hidden window
    public func show() { SDL_ShowWindow(handle) }

    /// hides the window; it stays alive and can be shown again
    public func hide() { SDL_HideWindow(handle) }

    // MARK: - State

    /// whether the window has keyboard focus
    public var isFocused: Bool { (windowFlags & sdlWindowInputFocus) != 0 }
    /// whether the window is minimized
    public var isMinimized: Bool { (windowFlags & sdlWindowMinimized) != 0 }
    /// whether the window is maximized
    public var isMaximized: Bool { (windowFlags & sdlWindowMaximized) != 0 }
    /// whether the window is visible
    public var isVisible: Bool { (windowFlags & sdlWindowHidden) == 0 }
    /// whether the mouse is grabbed
    public var isMouseGrabbed: Bool { (windowFlags & sdlWindowMouseGrabbed) != 0 }

    private var windowFlags: SDL_WindowFlags { SDL_GetWindowFlags(handle) }

    // MARK: - Mouse Mode

    /// whether relative mouse mode is on
    public var isMouseRelativeMode: Bool { SDL_GetWindowRelativeMouseMode(handle) }

    /// turns relative mouse mode on or off
    ///
    /// the cursor is hidden and motion comes in as deltas
    public func setMouseRelativeMode(_ enabled: Bool) {
        SDL_SetWindowRelativeMouseMode(handle, enabled)
    }

    /// turns mouse grab on or off (cursor stays inside the window)
    public func setMouseGrab(_ grabbed: Bool) { SDL_SetWindowMouseGrab(handle, grabbed) }

    /// destroys the SDL window on the main actor
    isolated deinit {
        SDL_DestroyWindow(handle)
        SDL_QuitSubSystem(SDL_INIT_VIDEO)
    }
}
