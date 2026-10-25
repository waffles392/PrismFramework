import Window

/// a snapshot of the metrics that drive 'WindowResizedEvent'
///
/// kept in the core run loop instead of the UI helper so resize events are
/// published whether or not RmlUI is available
struct WindowMetrics: Equatable {
    let width: Int
    let height: Int
    let pixelWidth: Int
    let pixelHeight: Int
    let displayScale: Float

    init(width: Int, height: Int, pixelWidth: Int, pixelHeight: Int, displayScale: Float) {
        self.width = width
        self.height = height
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.displayScale = displayScale
    }

    @MainActor
    init(window: Window) {
        width = Int(window.width)
        height = Int(window.height)
        pixelWidth = Int(window.pixelSize.width)
        pixelHeight = Int(window.pixelSize.height)
        displayScale = window.displayScale
    }
}
