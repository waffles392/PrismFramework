import CRmlUI
import Foundation

// Process-wide RmlUI setup and frame hooks. These are static members rather
// than instance state, so they live apart from UIContext's per-context API.

extension UIContext {

    public static func initialize(
        device: OpaquePointer,
        window: OpaquePointer
    ) -> Bool {
        rmlui_init(
            UnsafeMutableRawPointer(device),
            UnsafeMutableRawPointer(window)
        )
    }

    public static func shutdown() {
        rmlui_shutdown()
    }

    @discardableResult
    public static func loadFont(
        filePath: String,
        isFallback: Bool = false
    ) -> Bool {
        filePath.withCString {
            rmlui_load_font(
                $0,
                isFallback
            )
        }
    }

    @discardableResult
    public static func loadFont(
        named name: String,
        withExtension ext: String = "ttf",
        subdirectory: String? = nil,
        in bundle: Bundle = .main,
        isFallback: Bool = false
    ) -> Bool {
        guard let url = bundle.url(
            forResource: name,
            withExtension: ext,
            subdirectory: subdirectory
        ) else {
            print("[prism] font not found in bundle: \(name).\(ext)")
            return false
        }

        return loadFont(
            filePath: url.path,
            isFallback: isFallback
        )
    }

    public static func beginFrame(
        commandBuffer: OpaquePointer,
        texture: OpaquePointer,
        width: Int,
        height: Int
    ) {
        rmlui_begin_frame(
            UnsafeMutableRawPointer(commandBuffer),
            UnsafeMutableRawPointer(texture),
            Int32(width),
            Int32(height)
        )
    }

    public static func endFrame() {
        rmlui_end_frame()
    }
}
