import Foundation
import CRmlUI
import Math

/// 'RawHandle' is '@unchecked Sendable' because it wraps a pointer that is
/// set once at init and only read on the main actor
private struct RawHandle: @unchecked Sendable {
    var pointer: UnsafeMutableRawPointer?
}

// MARK: - Animation event bridge

/// 'AnimationEventBox' is '@unchecked Sendable' because it is immutable and
/// only holds a '@MainActor' handler
private final class AnimationEventBox: @unchecked Sendable {
    let handler: @MainActor (String, String) -> Void

    init(
        handler: @escaping @MainActor (String, String) -> Void
    ) {
        self.handler = handler
    }
}

/// 'ClickEventBox' is '@unchecked Sendable' because it is immutable and only
/// holds a '@MainActor' handler
private final class ClickEventBox: @unchecked Sendable {
    let handler: @MainActor () -> Void
    init(handler: @escaping @MainActor () -> Void) { self.handler = handler }
}

private func rmluiClickTrampoline(_ userData: UnsafeMutableRawPointer?) {
    guard let userData else { return }
    let box = Unmanaged<ClickEventBox>.fromOpaque(userData).takeUnretainedValue()
    MainActor.assumeIsolated { box.handler() }
}

private func rmluiAnimationEndTrampoline(
    _ elementID: UnsafePointer<CChar>?,
    _ property: UnsafePointer<CChar>?,
    _ userData: UnsafeMutableRawPointer?
) {
    guard let userData else {
        return
    }

    let box = Unmanaged<AnimationEventBox>
        .fromOpaque(userData)
        .takeUnretainedValue()

    let elementIDString =
        elementID.map(String.init(cString:)) ?? ""

    let propertyString =
        property.map(String.init(cString:)) ?? ""

    // RmlUI is driven from UIContext.update(), which is @MainActor
    MainActor.assumeIsolated {
        box.handler(
            elementIDString,
            propertyString
        )
    }
}

// MARK: - UIDocument

@MainActor
public final class UIDocument {

    private let handle: RawHandle

    // RmlUI stores a raw user_data pointer, so the Swift box has to stay
    // alive here for as long as the matching listener exists
    private var animationEventBoxes: [
        String: AnimationEventBox
    ] = [:]
    private var clickEventBoxes: [String: ClickEventBox] = [:]

    internal init(
        handle: UnsafeMutableRawPointer
    ) {
        self.handle = RawHandle(
            pointer: handle
        )
    }

    // MARK: - Lifecycle

    public func show() {
        guard let ptr = handle.pointer else {
            return
        }

        rmlui_show_document(ptr)
    }

    public func close() {
        guard let ptr = handle.pointer else {
            return
        }

        let ids =
            Array(animationEventBoxes.keys)

        for elementID in ids {
            _ = elementID.withCString {
                rmlui_remove_animation_end_listener(
                    ptr,
                    $0
                )
            }
        }

        animationEventBoxes.removeAll()
        for elementID in clickEventBoxes.keys {
            _ = elementID.withCString { rmlui_remove_click_listener(ptr, $0) }
        }
        clickEventBoxes.removeAll()

        rmlui_close_document(
            ptr
        )
    }

    @discardableResult
    public func addClickListener(elementID: String, handler: @escaping @MainActor () -> Void) -> Bool {
        guard let ptr = handle.pointer else { return false }
        _ = removeClickListener(elementID: elementID)
        let box = ClickEventBox(handler: handler)
        let result = elementID.withCString {
            rmlui_add_click_listener(ptr, $0, rmluiClickTrampoline,
                Unmanaged.passUnretained(box).toOpaque())
        }
        if result { clickEventBoxes[elementID] = box }
        return result
    }

    @discardableResult
    public func removeClickListener(elementID: String) -> Bool {
        guard let ptr = handle.pointer else { return false }
        let removed = elementID.withCString { rmlui_remove_click_listener(ptr, $0) }
        clickEventBoxes.removeValue(forKey: elementID)
        return removed
    }

    // MARK: - Classes

    @discardableResult
    public func setElementClass(
        id: String,
        name: String,
        enabled: Bool
    ) -> Bool {
        guard let ptr = handle.pointer else {
            return false
        }

        return id.withCString { idCStr in
            name.withCString { nameCStr in
                rmlui_set_element_class(
                    ptr,
                    idCStr,
                    nameCStr,
                    enabled
                )
            }
        }
    }

    // MARK: - Animation playback

    /// adds a trigger class and restarts all RCSS animations
    /// currently defined on this element
    ///
    /// repeated calls are safe even while the animation is
    /// already running
    @discardableResult
    public func playAnimation(
        id: String,
        className: String
    ) -> Bool {
        guard let ptr = handle.pointer else {
            return false
        }

        return id.withCString { idCStr in
            className.withCString { classCStr in
                rmlui_trigger_animation(
                    ptr,
                    idCStr,
                    classCStr
                )
            }
        }
    }

    /// restarts the current RCSS animations on an element
    ///
    /// useful for child elements whose animation comes from
    /// a selector on an ancestor
    @discardableResult
    public func restartAnimations(
        id: String
    ) -> Bool {
        guard let ptr = handle.pointer else {
            return false
        }

        return id.withCString { idCStr in
            rmlui_restart_animations(
                ptr,
                idCStr
            )
        }
    }

    // MARK: - Animation events

    /// observes completion of CSS animations on this element
    ///
    /// the 'property' argument is the property whose animation
    /// completed, e.g. "transform", "opacity", "color"
    @discardableResult
    public func addAnimationEndListener(
        elementID: String,
        handler: @escaping @MainActor (String, String) -> Void
    ) -> Bool {
        guard let ptr = handle.pointer else {
            return false
        }

        // replace any existing listener for the same element
        if animationEventBoxes[elementID] != nil {
            _ = removeAnimationEndListener(
                elementID: elementID
            )
        }

        let box = AnimationEventBox(
            handler: handler
        )

        let userData =
            Unmanaged
                .passUnretained(box)
                .toOpaque()

        let result = elementID.withCString {
            rmlui_add_animation_end_listener(
                ptr,
                $0,
                rmluiAnimationEndTrampoline,
                userData
            )
        }

        if result {
            animationEventBoxes[elementID] = box
        }

        return result
    }

    @discardableResult
    public func removeAnimationEndListener(
        elementID: String
    ) -> Bool {
        guard let ptr = handle.pointer else {
            return false
        }

        let result = elementID.withCString {
            rmlui_remove_animation_end_listener(
                ptr,
                $0
            )
        }

        if result {
            animationEventBoxes.removeValue(
                forKey: elementID
            )
        }

        return result
    }

    // MARK: - Elements

    @discardableResult
    public func setElementInnerRML(
        id: String,
        rml: String
    ) -> Bool {
        guard let ptr = handle.pointer else {
            return false
        }

        return id.withCString { idCStr in
            rml.withCString { rmlCStr in
                rmlui_set_element_inner_rml(
                    ptr,
                    idCStr,
                    rmlCStr
                )
            }
        }
    }

    @discardableResult
    public func setElementProperty(
        id: String,
        name: String,
        value: String
    ) -> Bool {
        guard let ptr = handle.pointer else {
            return false
        }

        return id.withCString { idCStr in
            name.withCString { nameCStr in
                value.withCString { valueCStr in
                    rmlui_set_element_property(
                        ptr,
                        idCStr,
                        nameCStr,
                        valueCStr
                    )
                }
            }
        }
    }

    @discardableResult
    public func setElementAttribute(
        id: String,
        name: String,
        value: String
    ) -> Bool {
        guard let ptr = handle.pointer else {
            return false
        }

        return id.withCString { idCStr in
            name.withCString { nameCStr in
                value.withCString { valueCStr in
                    rmlui_set_element_attribute(
                        ptr,
                        idCStr,
                        nameCStr,
                        valueCStr
                    )
                }
            }
        }
    }
}

// MARK: - UIContext

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

        self.handle = RawHandle(
            pointer: ctx
        )
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

    public func loadDocument(
        rml: String
    ) -> UIDocument? {
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

        return UIDocument(
            handle: doc
        )
    }

    public func update() {
        guard let ptr = handle.pointer else {
            return
        }

        rmlui_update_context(
            ptr
        )
    }

    public func render() {
        guard let ptr = handle.pointer else {
            return
        }

        rmlui_render_context(
            ptr
        )
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
            rmlui_destroy_context(
                ptr
            )
        }
    }

    // MARK: - Static subsystem control

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

// MARK: - UILayer

@MainActor
public protocol UILayer: AnyObject {

    func setup(
        in context: UIContext
    )

    func teardown()
}
