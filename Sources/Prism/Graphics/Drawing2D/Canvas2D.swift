import Foundation
import Math

/// immediate-mode 2D drawing context for mesh-based rendering
///
/// 'Canvas2D' accumulates drawing commands into batches, converts primitives
/// into triangle meshes, and submits them for rendering. it follows the
/// mesh-based rendering model where all geometry becomes triangles
@MainActor
public final class Canvas2D {
    // MARK: - Configuration
    
    public private(set) var size: Vector2D = .zero
    public var origin: Vector2D = .zero
    public var color: Color = Color(1, 1, 1, 1)
    /// emissive glow applied to subsequently drawn geometry
    ///
    /// 'rgb' is the glow colour and 'alpha' is the strength. bloom is driven by
    /// this value rather than by scene brightness, so a dim or transparent
    /// primitive still glows while 'emissive' is non-clear. the default,
    /// '.clear', disables glow
    public var emissive: Color = .clear
    
    // MARK: - State
    
    private var transformStack: [Matrix<Dim3, Dim3>] = [.identity]
    private var clipStack: [Rect2D] = []
    private var currentBlendMode: BlendMode = .normal
    
    // MARK: - Batching
    
    private struct Batch {
        var blendMode: BlendMode
        var vertices: [Vertex]
        var mesh: Mesh?
    }
    
    private var batches: [Batch] = []
    private var currentBatchIndex = -1

    /// the ordered draw stream for the frame
    ///
    /// ordinary 2D geometry is accumulated into 'batches'; GPU meshes
    /// submitted through 'submitMesh(_:instanceCount:vertexCount:firstVertex:)'
    /// are interleaved at the point they were requested so painter's order is
    /// preserved between canvas geometry and pre-packed meshes
    private enum DrawItem {
        case batch(Int)
        case mesh(mesh: Mesh, instanceCount: Int, vertexCount: Int, firstVertex: Int)
    }

    private var drawItems: [DrawItem] = []
    
    // MARK: - Statistics
    
    public private(set) var drawCallCount: Int = 0
    public private(set) var vertexCount: Int = 0
    public private(set) var triangleCount: Int = 0
    public private(set) var batchCount: Int = 0
    
    // MARK: - Dependencies
    
    private var renderer: Renderer?
    private var vertexShaderCode: Data = Data()
    private var fragmentShaderCode: Data = Data()
    private var surfaceCache: [BlendMode: Surface] = [:]
    
    public init() {}
    
    // MARK: - Configuration
    
    /// configures the canvas with a renderer and the shader bytecode used for
    /// all 2D geometry. call this once after creating the renderer
    ///
    /// one 'Surface' is cached per blend mode; the matching pipeline is built
    /// lazily by 'Mesh' for whichever color-target format the draw lands in
    public func configure(
        renderer: Renderer,
        vertexShaderCode: Data,
        fragmentShaderCode: Data
    ) throws {
        self.renderer = renderer
        self.vertexShaderCode = vertexShaderCode
        self.fragmentShaderCode = fragmentShaderCode
        self.surfaceCache.removeAll(keepingCapacity: true)
    }
    
    private func surface(for blendMode: BlendMode) -> Surface {
        if let cached = surfaceCache[blendMode] {
            return cached
        }
        let surface = Surface(
            vertexShader: vertexShaderCode,
            fragmentShader: fragmentShaderCode,
            blendMode: blendMode
        )
        surfaceCache[blendMode] = surface
        return surface
    }
    
    // MARK: - Transform Stack
    
    public var currentTransform: Matrix<Dim3, Dim3> {
        transformStack.last ?? .identity
    }
    
    public func pushTransform() {
        transformStack.append(currentTransform)
    }
    
    public func popTransform() {
        guard transformStack.count > 1 else { return }
        transformStack.removeLast()
    }
    
    public func translate(_ offset: Vector2D) {
        transformStack[transformStack.count - 1] = currentTransform * .translation(offset)
    }
    
    public func rotate(_ angle: Angle) {
        transformStack[transformStack.count - 1] = currentTransform * .rotation(angle)
    }
    
    public func scale(_ factor: Vector2D) {
        transformStack[transformStack.count - 1] = currentTransform * .scale(factor)
    }
    
    public func setTransform(_ matrix: Matrix<Dim3, Dim3>) {
        transformStack[transformStack.count - 1] = matrix
    }
    
    public func resetTransform() {
        transformStack[transformStack.count - 1] = .identity
    }
    
    // MARK: - Clipping
    
    private var currentClip: Rect2D? {
        clipStack.last
    }
    
    public func pushClip(_ rect: Rect2D) {
        if let current = currentClip {
            clipStack.append(intersectRects(current, rect))
        } else {
            clipStack.append(rect)
        }
    }
    
    public func popClip() {
        guard !clipStack.isEmpty else { return }
        clipStack.removeLast()
    }
    
    public func intersectClip(_ rect: Rect2D) {
        guard let current = currentClip else {
            clipStack.append(rect)
            return
        }
        clipStack[clipStack.count - 1] = intersectRects(current, rect)
    }
    
    private func intersectRects(_ a: Rect2D, _ b: Rect2D) -> Rect2D {
        let minX = max(a.min.x, b.min.x)
        let minY = max(a.min.y, b.min.y)
        let maxX = min(a.max.x, b.max.x)
        let maxY = min(a.max.y, b.max.y)
        
        if minX >= maxX || minY >= maxY {
            return Rect2D(origin: .zero, size: .zero)
        }
        
        return Rect2D(origin: Vector2D(minX, minY), size: Vector2D(maxX - minX, maxY - minY))
    }
    
    // MARK: - Blend Mode
    
    public func setBlendMode(_ mode: BlendMode) {
        guard mode != currentBlendMode else { return }
        flushIfNeeded(newMode: mode)
        currentBlendMode = mode
    }
    
    public func resetBlendMode() {
        setBlendMode(.normal)
    }
    
    // MARK: - Color
    
    public func setColor(_ color: Color) {
        self.color = color
    }

    public func setEmissive(_ emissive: Color) {
        self.emissive = emissive
    }
    
    // MARK: - Frame Lifecycle
    
    /// begins a new frame
    public func begin(windowWidth: Int32, windowHeight: Int32) {
        size = Vector2D(Float(max(0, windowWidth)), Float(max(0, windowHeight)))
        
        batches.removeAll(keepingCapacity: true)
        drawItems.removeAll(keepingCapacity: true)
        transformStack = [.identity]
        clipStack.removeAll()
        currentBlendMode = .normal
        openNewBatch(mode: .normal)
        
        drawCallCount = 0
        vertexCount = 0
        triangleCount = 0
        batchCount = 0
    }
    
    /// prepares GPU resources for the frame
    public func prepare(frame: Frame) throws {
        guard let renderer else { return }

        var totalVertices = 0

        for index in batches.indices {
            let batchVertices = batches[index].vertices
            guard !batchVertices.isEmpty else { continue }

            if let existing = batches[index].mesh {
                try existing.update(vertices: batchVertices)
                try existing.prepare(commandBuffer: frame.commandBuffer)
            } else {
                let mesh = try Mesh(
                    device: renderer.device,
                    sampler: renderer.linearSampler,
                    vertices: batchVertices,
                    surface: surface(for: batches[index].blendMode)
                )
                try mesh.prepare(commandBuffer: frame.commandBuffer)
                batches[index].mesh = mesh
            }

            totalVertices += batchVertices.count
        }

        for item in drawItems {
            guard case .mesh(let mesh, _, _, _) = item else { continue }
            try mesh.prepare(commandBuffer: frame.commandBuffer)
        }

        vertexCount = totalVertices
        triangleCount = totalVertices / 3
    }

    /// draws the accumulated geometry
    public func draw(in encoder: RenderEncoder) {
        var calls = 0

        for item in drawItems {
            switch item {
            case .batch(let index):
                let batch = batches[index]
                guard let mesh = batch.mesh, !batch.vertices.isEmpty else { continue }
                mesh.draw(in: encoder)
                calls += 1

            case .mesh(let mesh, let instanceCount, let vertexCount, let firstVertex):
                mesh.draw(
                    in: encoder,
                    instanceCount: instanceCount,
                    vertexCount: vertexCount,
                    firstVertex: firstVertex
                )
                calls += 1
            }
        }

        drawCallCount = calls
        batchCount = batches.count
    }

    /// submits a pre-packed GPU mesh into the canvas draw stream
    ///
    /// the mesh is drawn at the current painter's-order position: everything
    /// drawn before this call stays underneath it, and subsequent canvas
    /// geometry lands on top. geometries drawn this way use their own
    /// 'Surface' (shaders, uniforms, blend mode, topology) rather than the
    /// canvas's 2D material
    public func submitMesh(
        _ mesh: Mesh,
        instanceCount: Int,
        vertexCount: Int,
        firstVertex: Int = 0
    ) {
        guard instanceCount > 0, vertexCount > 0 else { return }

        // record the mesh draw, then start a fresh batch so any geometry drawn
        // afterwards is emitted after the mesh instead of joining the batch
        // that precedes it
        drawItems.append(
            .mesh(
                mesh: mesh,
                instanceCount: instanceCount,
                vertexCount: vertexCount,
                firstVertex: firstVertex
            )
        )
        openNewBatch(mode: currentBlendMode)
    }
    
    // MARK: - Drawing Primitives
    
    public func triangle(_ a: Vector2D, _ b: Vector2D, _ c: Vector2D, color: Color? = nil, emissive: Color? = nil) {
        guard valid(a), valid(b), valid(c) else { return }
        addTriangle(a, b, c, color: color ?? self.color, emissive: emissive)
    }
    
    public func line(from start: Vector2D, to end: Vector2D, width: Float = 1, color: Color? = nil, emissive: Color? = nil) {
        guard valid(start), valid(end), width > 0 else { return }
        
        let delta = end - start
        let length = delta.length
        guard length > 0.000001 else { return }
        
        let normal = Vector2D(-delta.y, delta.x).normalized * (width * 0.5)
        let a = start + normal
        let b = start - normal
        let c = end - normal
        let d = end + normal
        
        addTriangle(a, b, c, color: color ?? self.color, emissive: emissive)
        addTriangle(a, c, d, color: color ?? self.color, emissive: emissive)
    }
    
    public func polyline(
        _ points: [Vector2D],
        width: Float = 1,
        color: Color? = nil,
        emissive: Color? = nil,
        closed: Bool = false,
        join: LineJoin = .miter(),
        dash: DashPattern? = nil
    ) {
        guard points.count >= 2, width > 0 else { return }
        
        let clean = cleanedPoints(points, closed: closed)
        
        if closed {
            guard clean.count >= 3 else { return }
        } else {
            guard clean.count >= 2 else { return }
        }
        
        strokePolyline(clean, width: width, color: color ?? self.color, closed: closed, join: join, dash: dash, emissive: emissive)
    }
    
    public func rectangle(_ rect: Rect2D, filled: Bool = true, lineWidth: Float = 1, color: Color? = nil, emissive: Color? = nil) {
        let c = color ?? self.color
        let a = rect.origin
        let b = Vector2D(rect.max.x, rect.origin.y)
        let c2 = rect.max
        let d = Vector2D(rect.origin.x, rect.max.y)
        
        if filled {
            addTriangle(a, b, c2, color: c, emissive: emissive)
            addTriangle(a, c2, d, color: c, emissive: emissive)
        }
        
        if lineWidth > 0 {
            strokePolyline([a, b, c2, d], width: lineWidth, color: c, closed: true, emissive: emissive)
        }
    }
    
    public func roundedRect(_ rect: Rect2D, cornerRadius: Float, filled: Bool = true, lineWidth: Float = 1, color: Color? = nil, emissive: Color? = nil) {
        let c = color ?? self.color
        let r = min(cornerRadius, min(rect.size.x, rect.size.y) * 0.5)
        
        guard r > 0 else {
            rectangle(rect, filled: filled, lineWidth: lineWidth, color: c, emissive: emissive)
            return
        }
        
        let segments = max(4, Int(r * 0.5))
        var points: [Vector2D] = []
        points.reserveCapacity(segments * 4)
        
        // top-left
        for i in 0..<segments {
            let angle = Float.pi + Float(i) / Float(segments) * (Float.pi * 0.5)
            points.append(Vector2D(rect.min.x + r, rect.min.y + r) + Vector2D(cos(angle), sin(angle)) * r)
        }
        
        // top-right
        for i in 0..<segments {
            let angle = Float.pi * 1.5 + Float(i) / Float(segments) * (Float.pi * 0.5)
            points.append(Vector2D(rect.max.x - r, rect.min.y + r) + Vector2D(cos(angle), sin(angle)) * r)
        }
        
        // bottom-right
        for i in 0..<segments {
            let angle = Float(i) / Float(segments) * (Float.pi * 0.5)
            points.append(Vector2D(rect.max.x - r, rect.max.y - r) + Vector2D(cos(angle), sin(angle)) * r)
        }
        
        // bottom-left
        for i in 0..<segments {
            let angle = Float.pi * 0.5 + Float(i) / Float(segments) * (Float.pi * 0.5)
            points.append(Vector2D(rect.min.x + r, rect.max.y - r) + Vector2D(cos(angle), sin(angle)) * r)
        }
        
        if filled, points.count >= 3 {
            for i in 2..<points.count {
                addTriangle(points[0], points[i - 1], points[i], color: c, emissive: emissive)
            }
        }
        
        if lineWidth > 0 {
            strokePolyline(points, width: lineWidth, color: c, closed: true, emissive: emissive)
        }
    }
    
    /// draws a circle, filled or outlined
    ///
    /// 'lineWidth' is a world-space width that does not scale with 'radius',
    /// so the default is a hairline
    public func circle(at center: Vector2D, radius: Float, segments: Int = 32, filled: Bool = true, lineWidth: Float = 0.006, color: Color? = nil, emissive: Color? = nil) {
        let c = color ?? self.color
        guard radius > 0, valid(center) else { return }
        
        let count = min(256, max(3, segments))
        
        if filled {
            var previous = center + Vector2D(cos(0), sin(0)) * radius
            
            for i in 1...count {
                let angle = Float(i) / Float(count) * 2 * Float.pi
                let point = center + Vector2D(cos(angle), sin(angle)) * radius
                addTriangle(center, previous, point, color: c, emissive: emissive)
                previous = point
            }
        } else {
            var points: [Vector2D] = []
            points.reserveCapacity(count)
            
            for i in 0..<count {
                let angle = Float(i) / Float(count) * 2 * Float.pi
                points.append(center + Vector2D(cos(angle), sin(angle)) * radius)
            }
            
            strokePolyline(points, width: lineWidth, color: c, closed: true, emissive: emissive)
        }
    }
    
    /// draws an arc between two angles, filled or outlined
    ///
    /// 'lineWidth' is a world-space width that does not scale with 'radius',
    /// so the default is a hairline
    public func arc(center: Vector2D, radius: Float, startAngle: Angle, endAngle: Angle, segments: Int = 32, filled: Bool = true, lineWidth: Float = 0.006, color: Color? = nil, emissive: Color? = nil) {
        let c = color ?? self.color
        guard radius > 0, valid(center) else { return }
        
        let start = startAngle.radians
        let end = endAngle.radians
        var sweep = end - start
        
        while sweep < 0 { sweep += 2 * Float.pi }
        while sweep > 2 * Float.pi { sweep -= 2 * Float.pi }
        
        let count = min(256, max(3, segments))
        
        if filled {
            var previous = center + Vector2D(cos(start), sin(start)) * radius
            
            for i in 1...count {
                let t = Float(i) / Float(count)
                let angle = start + sweep * t
                let point = center + Vector2D(cos(angle), sin(angle)) * radius
                addTriangle(center, previous, point, color: c, emissive: emissive)
                previous = point
            }
        } else {
            var points: [Vector2D] = []
            points.reserveCapacity(count + 1)
            
            for i in 0...count {
                let t = Float(i) / Float(count)
                let angle = start + sweep * t
                points.append(center + Vector2D(cos(angle), sin(angle)) * radius)
            }
            
            strokePolyline(points, width: lineWidth, color: c, closed: false, emissive: emissive)
        }
    }
    
    public func polygon(
        _ points: [Vector2D],
        fill: Color?,
        lineWidth: Float,
        strokeColor: Color?,
        closed: Bool,
        join: LineJoin = .miter(),
        dash: DashPattern? = nil,
        emissive: Color? = nil
    ) {
        guard points.count >= 2 else { return }
        
        let clean = cleanedPoints(points, closed: closed)
        
        if let fill, clean.count >= 3 {
            for triangle in Triangulation.triangulate(clean) {
                addTriangle(triangle.0, triangle.1, triangle.2, color: fill, emissive: emissive)
            }
        }
        
        let stroke = strokeColor ?? fill
        guard let stroke, lineWidth > 0 else { return }
        
        strokePolyline(clean, width: lineWidth, color: stroke, closed: closed, join: join, dash: dash, emissive: emissive)
    }
    
    public func polygonOutline(
        _ points: [Vector2D],
        width: Float = 1,
        color: Color? = nil,
        emissive: Color? = nil,
        join: LineJoin = .miter(),
        dash: DashPattern? = nil
    ) {
        guard points.count >= 3, width > 0 else { return }
        
        let clean = cleanedPoints(points, closed: true)
        guard clean.count >= 3 else { return }
        
        strokePolyline(clean, width: width, color: color ?? self.color, closed: true, join: join, dash: dash, emissive: emissive)
    }
    
    public func ellipse(
        in rect: Rect2D,
        fill: Color?,
        lineWidth: Float,
        strokeColor: Color?,
        join: LineJoin = .miter(),
        dash: DashPattern? = nil,
        emissive: Color? = nil
    ) {
        let center = rect.center
        let radiusX = rect.size.x * 0.5
        let radiusY = rect.size.y * 0.5
        let segments = max(16, Int(max(radiusX, radiusY) * 0.5))
        
        var points: [Vector2D] = []
        points.reserveCapacity(segments)
        
        for i in 0..<segments {
            let angle = Float(i) / Float(segments) * 2 * Float.pi
            points.append(Vector2D(center.x + cos(angle) * radiusX, center.y + sin(angle) * radiusY))
        }
        
        if let fill {
            for i in 1..<segments - 1 {
                addTriangle(points[0], points[i], points[i + 1], color: fill, emissive: emissive)
            }
        }
        
        if let strokeColor, lineWidth > 0 {
            strokePolyline(points, width: lineWidth, color: strokeColor, closed: true, join: join, dash: dash, emissive: emissive)
        }
    }
    
    // MARK: - Debug Visualization
    
    public func drawBounds(_ bounds: Rect2D, color: Color) {
        rectangle(bounds, filled: false, lineWidth: 2, color: color)
    }
    
    // MARK: - Internal Helpers
    
    private func addTriangle(_ a: Vector2D, _ b: Vector2D, _ c: Vector2D, color: Color, emissive: Color? = nil) {
        let ta = transformPoint(a)
        let tb = transformPoint(b)
        let tc = transformPoint(c)
        
        if let clip = currentClip {
            if !clip.contains(ta) && !clip.contains(tb) && !clip.contains(tc) {
                return
            }
        }
        
        let linearColor = color.linearValue
        let linearEmissive = linearEmissive(emissive)
        
        currentBatch.vertices.append(Vertex(position: toNDC(ta), color: linearColor, emissive: linearEmissive))
        currentBatch.vertices.append(Vertex(position: toNDC(tb), color: linearColor, emissive: linearEmissive))
        currentBatch.vertices.append(Vertex(position: toNDC(tc), color: linearColor, emissive: linearEmissive))
    }

    /// the per-vertex emissive value for a draw call
    ///
    /// 'override' falls back to the canvas's current 'emissive' state. the
    /// fragment shader multiplies the glow colour by the alpha strength, so the
    /// two are kept separate here
    private func linearEmissive(_ override: Color?) -> SIMD4<Float> {
        (override ?? emissive).linearValue
    }
    
    private func transformPoint(_ point: Vector2D) -> Vector2D {
        var p = point - origin
        p = currentTransform.transformPoint(p)
        return p
    }
    
    private func toNDC(_ point: Vector2D) -> Vector2D {
        guard size.x > 0, size.y > 0 else { return .zero }
        return Vector2D(x: point.x / size.x * 2 - 1, y: 1 - point.y / size.y * 2)
    }

    /// converts a world/canvas-space point to normalized device coordinates
    /// using the canvas's current camera transform
    ///
    /// custom GPU meshes that bypass the canvas pipeline (for example shaders
    /// that receive pre-projected instance centres) use this to stay aligned
    /// with the 2D geometry drawn around them
    public func worldToNDC(_ point: Vector2D) -> Vector2D {
        toNDC(transformPoint(point))
    }
    
    private func valid(_ point: Vector2D) -> Bool {
        point.x.isFinite && point.y.isFinite
    }
    
    /// appends already-transformed (NDC) vertices to the current batch
    ///
    /// used by callers that pre-bake geometry and re-transform it only when
    /// the camera or canvas size changes
    public func submitPreTransformedVertices(_ vertices: [Vertex]) {
        guard !vertices.isEmpty else { return }
        currentBatch.vertices.append(contentsOf: vertices)
    }
    
    private var currentBatch: Batch {
        get { batches[currentBatchIndex] }
        set { batches[currentBatchIndex] = newValue }
    }
    
    private func openNewBatch(mode: BlendMode) {
        batches.append(Batch(blendMode: mode, vertices: []))
        currentBatchIndex = batches.count - 1
        drawItems.append(.batch(currentBatchIndex))
    }
    
    private func flushIfNeeded(newMode: BlendMode) {
        guard !batches.isEmpty else {
            openNewBatch(mode: newMode)
            return
        }
        
        if currentBatch.blendMode == newMode { return }
        
        if currentBatch.vertices.isEmpty {
            currentBatch.blendMode = newMode
        } else {
            openNewBatch(mode: newMode)
        }
    }
    
    private func cleanedPoints(_ points: [Vector2D], closed: Bool) -> [Vector2D] {
        Triangulation.cleanedPoints(points, closed: closed)
    }
    
    func strokePolyline(
        _ points: [Vector2D],
        width: Float,
        color: Color,
        closed: Bool,
        join: LineJoin = .miter(),
        dash: DashPattern? = nil,
        emissive: Color? = nil
    ) {
        var vertices: [Vertex] = []

        if let dash {
            // every dash is its own open path, so joins still apply within one
            for run in dash.segments(of: points, closed: closed) where run.count >= 2 {
                vertices += StrokeGenerator.strokeOpenPolyline(run, width: width, color: color, join: join)
            }
        } else {
            vertices = closed
                ? StrokeGenerator.strokeClosedPolygon(points, width: width, color: color, join: join)
                : StrokeGenerator.strokeOpenPolyline(points, width: width, color: color, join: join)
        }

        guard !vertices.isEmpty else { return }

        // stroke vertices are generated in the same coordinate space as the
        // input points (world/canvas space), so they must go through the same
        // transform + world→NDC conversion as 'addTriangle'. appending them
        // raw left outlined geometry (polygonOutline, unfilled circles, etc.)
        // untransformed, so it ignored the canvas transform and moved/scaled
        // incorrectly
        currentBatch.vertices.reserveCapacity(currentBatch.vertices.count + vertices.count)

        let linearEmissive = linearEmissive(emissive)

        for vertex in vertices {
            let ndc = toNDC(transformPoint(vertex.position))
            currentBatch.vertices.append(
                Vertex(position: ndc, color: vertex.color, emissive: linearEmissive)
            )
        }
    }
}