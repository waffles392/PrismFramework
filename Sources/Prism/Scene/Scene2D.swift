import Graphics
import Math

/// a 2D scene: a root 'GameObject' plus 'Collection' groups of children
///
/// 'Scene2D' drives the full frame lifecycle for all its collections:
/// 'update' → 'prepare' → 'draw'. objects are traversed recursively
/// (honouring 'GameObject.isActive') so child hierarchies are handled
/// automatically
///
/// ### Scene Root
///
/// the scene has a 'root' GameObject that serves as the parent for all
/// top-level objects. add objects to the scene by adding them as children
/// of 'root', or by using 'addRootChild(_:)'. the root's transform is
/// applied to all objects in the scene
///
/// ### Camera support
///
/// set 'cameraTransform' to any 'Matrix<Dim3, Dim3>' to apply a world-to-view
/// transform before 2D rendering. the matrix is pushed onto the graphics
/// context's transform stack for the entire scene draw call and popped
/// afterwards - individual objects do not need to know about the camera
///
/// ```swift
/// // Follow a player object:
/// scene.cameraTransform = .translation(-player.worldPosition + screenCenter)
/// ```
///
/// ### Clear colour
///
/// set 'clearColor' and pass this scene to one of the 'run(scene:...)' helpers;
/// the run loop reads 'scene.clearColor' when calling 'frame.beginRenderPass'
@MainActor
public final class Scene2D {

    // MARK: - Root Object

    /// the scene's root object. all top-level game objects should be added
    /// as children of this root. the root itself is always active and at
    /// identity transform (position 0, angle 0, scale 1)
    public let root: GameObject = GameObject()

    // MARK: - Collections (legacy support)

    public private(set) var collections: [Collection]

    public init(collections: [Collection] = []) {
        self.collections = collections
    }

    public func add(_ collection: Collection) {
        collections.append(collection)
    }

    @discardableResult
    public func remove(_ collection: Collection) -> Bool {
        guard let index = collections.firstIndex(where: { $0 === collection }) else {
            return false
        }
        collections.remove(at: index)
        return true
    }

    public func removeAll() {
        collections.removeAll()
    }

    // MARK: - Root Hierarchy Management

    /// adds a child to the scene root
    public func addRootChild(_ child: GameObject) {
        root.addChild(child)
    }

    /// removes a child from the scene root
    @discardableResult
    public func removeRootChild(_ child: GameObject) -> Bool {
        root.removeChild(child)
    }

    /// removes all children from the scene root
    public func removeAllRootChildren() {
        root.removeAllChildren()
    }

    // MARK: - Camera

    /// world-to-view transform applied to the graphics context before drawing
    ///
    /// defaults to 'nil' (identity - no camera). assign a 'Matrix<Dim3, Dim3>' to
    /// scroll, zoom, or rotate the scene view
    public var cameraTransform: Matrix<Dim3, Dim3>?

    // MARK: - Clear colour

    /// the colour used to clear the render target at the start of each frame
    ///
    /// defaults to opaque black. the 'Prism.run(scene:...)' loop reads this
    /// value when opening the render pass
    public var clearColor: Color = Color(0, 0, 0, 1)

    // MARK: - Active gating

    /// when 'false' the entire scene is skipped by 'update', 'prepare', and 'draw'
    public var isActive: Bool = true

    // MARK: - Frame Lifecycle

    /// updates all active objects (root hierarchy + collections)
    public func update(deltaTime: Float) {
        guard isActive else { return }
        // update root hierarchy
        for child in root.children {
            child.traverseUpdate(deltaTime: deltaTime)
        }
        // update legacy collections
        for collection in collections {
            for object in collection.objects {
                object.traverseUpdate(deltaTime: deltaTime)
            }
        }
    }

    /// prepares GPU geometry for all active objects (root hierarchy + collections)
    public func prepare(renderer: Renderer, frame: Frame) {
        guard isActive else { return }
        // prepare root hierarchy
        for child in root.children {
            child.traversePrepare(renderer: renderer, frame: frame)
        }
        // prepare legacy collections
        for collection in collections {
            for object in collection.objects {
                object.traversePrepare(renderer: renderer, frame: frame)
            }
        }
    }

    /// draws all active objects into a render encoder (recursive)
    public func draw(in encoder: RenderEncoder) {
        guard isActive else { return }
        // draw root hierarchy
        for child in root.children {
            child.traverseDraw(in: encoder)
        }
        // draw legacy collections
        for collection in collections {
            for object in collection.objects {
                object.traverseDraw(in: encoder)
            }
        }
    }

    /// draws all active objects via the 2D canvas (recursive)
    ///
    /// if 'cameraTransform' is set, it is applied to the context's transform
    /// stack for the duration of the scene draw
    public func draw(in context: Canvas2D) {
        guard isActive else { return }

        if let cam = cameraTransform {
            context.pushTransform()
            context.setTransform(cam)
        }

        // draw root hierarchy
        for child in root.children {
            child.traverseDraw(in: context)
        }
        // draw legacy collections
        for collection in collections {
            for object in collection.objects {
                object.traverseDraw(in: context)
            }
        }

        if cameraTransform != nil {
            context.popTransform()
        }
    }
}
