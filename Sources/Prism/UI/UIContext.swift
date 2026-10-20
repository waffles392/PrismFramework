import CRmlUI

/// 'RawHandle' is '@unchecked Sendable' because it wraps a pointer that is
/// set once at init and only read on the main actor
///
/// internal so 'UIDocument' can share it
struct RawHandle: @unchecked Sendable {
    var pointer: UnsafeMutableRawPointer?
}

@MainActor
public final class UIContext {
    private var handle: RawHandle

    public init?(
        name: String,
        width: Int,
        height: Int
    ) {
        guard let ctx = name.withCString({
            rmlui_create_context(
                $0,
                Int32(width),
                Int32(height)
            )
        }) else {
            return nil
        }

        self.handle = RawHandle(pointer: ctx)
    }

    public func setDimensions(
        width: Int,
        height: Int
    ) {
        guard let ptr = handle.pointer else {
            return
        }

        rmlui_set_dimensions(
            ptr,
            Int32(width),
            Int32(height)
        )
    }

    public func loadDocument(
        filePath: String
    ) -> UIDocument? {
        guard let ptr = handle.pointer else {
            return nil
        }

        guard let doc = filePath.withCString({
            rmlui_load_document(
                ptr,
                $0
            )
        }) else {
            return nil
        }

        return UIDocument(
            handle: doc
        )
    }

    public func loadDocument(rml: String) -> UIDocument? {
        guard let ptr = handle.pointer else {
            return nil
        }

        guard let doc = rml.withCString({
            rmlui_load_document_from_memory(
                ptr,
                $0
            )
        }) else {
            return nil
        }

        return UIDocument(handle: doc)
    }

    public func update() {
        guard let ptr = handle.pointer else {
            return
        }

        rmlui_update_context(ptr)
    }

    public func render() {
        guard let ptr = handle.pointer else {
            return
        }

        rmlui_render_context(ptr)
    }

    public func processSDLEvent(
        window: OpaquePointer?,
        event: UnsafeMutableRawPointer
    ) -> Bool {
        guard let ptr = handle.pointer,
              let window
        else {
            return false
        }

        return rmlui_process_event(
            ptr,
            UnsafeMutableRawPointer(window),
            event
        )
    }

    deinit {
        if let ptr = handle.pointer {
            rmlui_destroy_context(ptr)
        }
    }
}
