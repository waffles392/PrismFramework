import Graphics
import Math

/// the base type for all scene objects
///
/// 'GameObject' provides a full 2D transform hierarchy:
/// - Local 'position', 'angle', 'scale'
/// - Computed 'worldTransform' that concatenates up the parent chain
/// - Hierarchical parenting via 'addChild'/'removeChild'; children draw
///   after their parent and inherit its world transform
/// - Active gating: inactive objects skip 'update', 'prepare', and 'draw'
///
/// override the hook methods rather than the parent lifecycle calls:
///
/// ```swift
/// class Bullet: GameObject {
///     override func update(deltaTime: Float) {
///         position += velocity * deltaTime
///     }
///     override func draw(in context: any Canvas2D) {
///         context.circle(at: position, radius: 4, segments: 16, filled: true, color: .white)
///     }
/// }
/// ```
@MainActor
open class GameObject {

    // MARK: - Identity

    /// optional human-readable tag for debugging
    public var name: String = ""

    // MARK: - Active state

    /// when 'false' this object (and all its children) are skipped by the
    /// scene traversal: 'update', 'prepare', and 'draw' are not called
    public var isActive: Bool = true

    // MARK: - 2D Transform

    /// local position relative to the parent (or to the scene root if no parent)
    public var position: Vector2D = .zero

    /// local rotation angle
    public var angle: Angle = .zero

    /// local scale factor
    public var scale: Vector2D = .one

    // MARK: - Hierarchy

    /// the parent of this object in the scene hierarchy, if any
    public private(set) weak var parent: GameObject?

    /// the ordered list of direct children
    public private(set) var children: [GameObject] = []

    // MARK: - Init

    public init() {}

    // MARK: - World transform

    /// the composed world transform (parent world × local TRS)
    ///
    /// computed on demand by walking up the parent chain
    public var worldTransform: Matrix<Dim3, Dim3> {
        let local = Matrix<Dim3, Dim3>.trs(translation: position, rotation: angle, scale: scale)
        guard let parent else { return local }
        return parent.worldTransform * local
    }

    /// world-space position derived from 'worldTransform'
    public var worldPosition: Vector2D {
        worldTransform.translation
    }

    /// world-space rotation angle derived from 'worldTransform'
    public var worldAngle: Angle {
        worldTransform.rotation
    }

    /// world-space scale derived from 'worldTransform'
    public var worldScale: Vector2D {
        worldTransform.scale
    }

    // MARK: - Hierarchy management

    /// adds 'child' as a direct child of this object
    ///
    /// - If 'child' already has a parent, it is removed from it first
    /// - Circular parenting is not permitted (asserted in debug builds)
    public func addChild(_ child: GameObject) {
        assert(!isAncestor(of: child), "addChild: would create a cycle in the scene hierarchy")
        if let oldParent = child.parent {
            oldParent.removeChild(child)
        }
        child.parent = self
        children.append(child)
    }

    /// removes 'child' from this object's children
    /// - Returns: 'true' if the child was found and removed
    @discardableResult
    public func removeChild(_ child: GameObject) -> Bool {
        guard let index = children.firstIndex(where: { $0 === child }) else { return false }
        children[index].parent = nil
        children.remove(at: index)
        return true
    }

    /// detaches this object from its parent
    public func removeFromParent() {
        parent?.removeChild(self)
    }

    /// removes all children from this object
    public func removeAllChildren() {
        for child in children { child.parent = nil }
        children.removeAll()
    }

    /// returns 'true' if this object is an ancestor of 'other' in the hierarchy
    public func isAncestor(of other: GameObject) -> Bool {
        var current: GameObject? = other.parent
        while let node = current {
            if node === self { return true }
            current = node.parent
        }
        return false
    }

    // MARK: - Override hooks

    /// called once per frame, before drawing. override to update game logic
    open func update(deltaTime: Float) {}

    /// called once per frame to upload geometry to the GPU before rendering
    open func prepare(renderer: Renderer, frame: Frame) {}

    /// called to draw this object using a render encoder
    open func draw(in encoder: RenderEncoder) {}

    /// called to draw this object via the 2D canvas
    open func draw(in context: Canvas2D) {}

    // MARK: - Internal: full traversal used by Scene2D

    /// recursively updates this node and all active children
    func traverseUpdate(deltaTime: Float) {
        guard isActive else { return }
        update(deltaTime: deltaTime)
        for child in children { child.traverseUpdate(deltaTime: deltaTime) }
    }

    /// recursively prepares this node and all active children
    func traversePrepare(renderer: Renderer, frame: Frame) {
        guard isActive else { return }
        prepare(renderer: renderer, frame: frame)
        for child in children { child.traversePrepare(renderer: renderer, frame: frame) }
    }

    /// recursively draws this node and all active children (render encoder variant)
    func traverseDraw(in encoder: RenderEncoder) {
        guard isActive else { return }
        draw(in: encoder)
        for child in children { child.traverseDraw(in: encoder) }
    }

    /// recursively draws this node and all active children (2D canvas variant)
    func traverseDraw(in context: Canvas2D) {
        guard isActive else { return }
        context.pushTransform()
        context.translate(position)
        context.rotate(angle)
        context.scale(scale)
        draw(in: context)
        for child in children { child.traverseDraw(in: context) }
        context.popTransform()
    }
}