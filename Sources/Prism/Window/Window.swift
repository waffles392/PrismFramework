import CSDL3

// MARK: - SDL window flag constants

/// SDL window creation/state flags (SDL_video.h)
/// the SDL headers expose these as '#define' macros on a
/// 'Uint64' typedef, so they are re-declared here as
/// raw 'SDL_WindowFlags' (UInt64) values
private let sdlWindowHidden: SDL_WindowFlags = 0x0000000000000008
private let sdlWindowBorderless: SDL_WindowFlags = 0x0000000000000010
private let sdlWindowResizable: SDL_WindowFlags = 0x0000000000000020
private let sdlWindowMinimized: SDL_WindowFlags = 0x0000000000000040
private let sdlWindowMaximized: SDL_WindowFlags = 0x0000000000000080
private let sdlWindowMouseGrabbed: SDL_WindowFlags = 0x0000000000000100
private let sdlWindowInputFocus: SDL_WindowFlags = 0x0000000000000200
private let sdlWindowHighPixelDensity: SDL_WindowFlags = 0x0000000000002000
private let sdlWindowAlwaysOnTop: SDL_WindowFlags = 0x0000000100000000

/// 'SDL_WINDOWPOS_CENTERED' (SDL_video.h) - the
/// macro does not cross the C boundary, so the
/// computed value is used directly
private let sdlWindowPosCentered: Int32 = 0x2FFF0000

// MARK: - WindowFlags

/// configuration flags for a 'Window'
///
/// 'vsync' is applied through the GPU swapchain parameters (the engine
/// calls 'GPU.setVsync(true)' when the flag is present); the remaining
/// flags map directly onto SDL window creation flags or are applied
/// immediately after creation
public struct WindowFlags: OptionSet, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    /// present the swapchain with vertical sync (via the GPU device)
    public static let vsync = WindowFlags(rawValue: 1 << 0)
    /// the window can be resized by the user
    public static let resizable = WindowFlags(rawValue: 1 << 1)
    /// use a high pixel-density back buffer when the display supports it
    public static let highDPI = WindowFlags(rawValue: 1 << 2)
    /// the window has no title bar or border
    public static let borderless = WindowFlags(rawValue: 1 << 3)
    /// the window stays above other windows (creation flag)
    public static let alwaysOnTop = WindowFlags(rawValue: 1 << 4)
    /// the window starts minimized (applied post-creation)
    public static let startMinimized = WindowFlags(rawValue: 1 << 5)
    /// the window starts maximized (applied post-creation)
    public static let startMaximized = WindowFlags(rawValue: 1 << 6)

    /// the engine default: vsync on, user-resizable
    public static let recommended: WindowFlags = [.resizable, .highDPI]

    /// SDL creation flags. 'vsync', 'startMinimized' and
    /// 'startMaximized' are not SDL creation flags; the first is a GPU
    /// setting and the rest are applied after the window exists
    var sdlCreationFlags: SDL_WindowFlags {
        var flags: SDL_WindowFlags = 0
        if contains(.resizable) { flags |= sdlWindowResizable }
        if contains(.highDPI) { flags |= sdlWindowHighPixelDensity }
        if contains(.borderless) { flags |= sdlWindowBorderless }
        if contains(.alwaysOnTop) { flags |= sdlWindowAlwaysOnTop }
        return flags
    }
}

/// owns an SDL video subsystem and its application window
///
/// 'Window' is '@unchecked Sendable' because its SDL window handle and size
/// are only touched from the main thread
public final class Window: @unchecked Sendable {
    public let title: String
    public private(set) var width: Int32
    public private(set) var height: Int32
    public private(set) var handle: OpaquePointer?

    /// the flags the window was created with
    public private(set) var flags: WindowFlags

    /// target frame rate consumed by the engine's frame pacing
    /// 'nil' (the default) means unlimited; 'PrismEnvironment.lockFramerate'
    /// overrides this when set
    public var targetFPS: Int?

    /// the drawable size in physical pixels (differs from 'width'/'height'
    /// on high-DPI displays)
    public private(set) var pixelSize: (width: Int32, height: Int32)

    /// the window's display scale (e.g. 2.0 on a Retina display)
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

        // post-creation flags that SDL does not accept at creation time
        if flags.contains(.startMinimized) { minimize() }
        if flags.contains(.startMaximized) { maximize() }
    }

    /// re-reads the window size, pixel size and display scale from SDL
    public func refreshSize() {
        guard let handle else { return }
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

    /// sets the window size in logical points
    public func setSize(width: Int32, height: Int32) {
        guard let handle else { return }
        guard SDL_SetWindowSize(handle, width, height) else { return }
        self.width = width
        self.height = height
        refreshSize()
    }

    // MARK: - Sizing Constraints

    /// sets the minimum size the user can resize the window to
    public func setMinimumSize(width: Int32, height: Int32) {
        guard let handle else { return }
        SDL_SetWindowMinimumSize(handle, width, height)
    }

    /// sets the maximum size the user can resize the window to
    public func setMaximumSize(width: Int32, height: Int32) {
        guard let handle else { return }
        SDL_SetWindowMaximumSize(handle, width, height)
    }

    // MARK: - Position & Focus

    /// centers the window on the primary display
    public func center() {
        move(x: sdlWindowPosCentered, y: sdlWindowPosCentered)
    }

    /// moves the window to the given position
    public func move(x: Int32, y: Int32) {
        guard let handle else { return }
        SDL_SetWindowPosition(handle, x, y)
    }

    /// returns the window position in screen coordinates
    public var position: (x: Int32, y: Int32) {
        guard let handle else { return (0, 0) }
        var x: Int32 = 0
        var y: Int32 = 0
        SDL_GetWindowPosition(handle, &x, &y)
        return (x, y)
    }

    /// sets the window title
    public func setTitle(_ title: String) {
        guard let handle else { return }
        SDL_SetWindowTitle(handle, title)
    }

    /// raises the window and gives it input focus
    public func focus() {
        guard let handle else { return }
        SDL_RaiseWindow(handle)
    }

    /// requests the window be closed (equivalent to the
    /// window-manager close button; the engine loop observes
    /// it as a 'WindowCloseEvent')
    public func close() {
        var event = SDL_Event()
        event.type = SDL_EVENT_QUIT.rawValue
        event.quit.timestamp = SDL_GetTicksNS()
        SDL_PushEvent(&event)
    }

    /// minimizes the window
    public func minimize() {
        guard let handle else { return }
        SDL_MinimizeWindow(handle)
    }

    /// restores a minimized or maximized window to its normal state
    public func restore() {
        guard let handle else { return }
        SDL_RestoreWindow(handle)
    }

    /// maximizes the window
    public func maximize() {
        guard let handle else { return }
        SDL_MaximizeWindow(handle)
    }

    /// shows a hidden window
    public func show() {
        guard let handle else { return }
        SDL_ShowWindow(handle)
    }

    /// hides the window (it remains alive and can be shown again)
    public func hide() {
        guard let handle else { return }
        SDL_HideWindow(handle)
    }

    // MARK: - State

    /// whether the window currently has keyboard focus
    public var isFocused: Bool {
        (windowFlags & sdlWindowInputFocus) != 0
    }

    /// whether the window is minimized
    public var isMinimized: Bool {
        (windowFlags & sdlWindowMinimized) != 0
    }

    /// whether the window is maximized
    public var isMaximized: Bool {
        (windowFlags & sdlWindowMaximized) != 0
    }

    /// whether the window is visible (mapped and not hidden)
    public var isVisible: Bool {
        (windowFlags & sdlWindowHidden) == 0
    }

    /// whether the window has grabbed the mouse
    public var isMouseGrabbed: Bool {
        (windowFlags & sdlWindowMouseGrabbed) != 0
    }

    private var windowFlags: SDL_WindowFlags {
        guard let handle else { return 0 }
        return SDL_GetWindowFlags(handle)
    }

    // MARK: - Mouse Mode

    /// enables or disables relative mouse mode for this window
    /// (cursor hidden, motion deltas reported instead of positions)
    public func setMouseRelativeMode(_ enabled: Bool) {
        guard let handle else { return }
        SDL_SetWindowRelativeMouseMode(handle, enabled)
    }

    /// enables or disables mouse grab (cursor confined to the window)
    public func setMouseGrab(_ grabbed: Bool) {
        guard let handle else { return }
        SDL_SetWindowMouseGrab(handle, grabbed)
    }

    deinit {
        if let handle {
            SDL_DestroyWindow(handle)
        }
        SDL_QuitSubSystem(SDL_INIT_VIDEO)
    }
}
