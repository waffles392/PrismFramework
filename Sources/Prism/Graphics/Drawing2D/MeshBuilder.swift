import Foundation
import Math

/// stroke options for lines and outlines
public struct StrokeOptions: Sendable {
    public let width: Float
    public let color: Color
    public let join: LineJoin
    /// dash pattern, or nil for a solid line
    public let dash: DashPattern?
    /// emissive glow for the stroke, or nil to use the canvas's current state
    public let emissive: Color?

    public init(width: Float, color: Color, join: LineJoin = .miter(), dash: DashPattern? = nil, emissive: Color? = nil) {
        self.width = width
        self.color = color
        self.join = join
        self.dash = dash
        self.emissive = emissive
    }
}

/// fill options for shapes
public struct FillOptions: Sendable {
    public let color: Color
    /// emissive glow for the fill, or nil to use the canvas's current state
    public let emissive: Color?

    public init(color: Color, emissive: Color? = nil) {
        self.color = color
        self.emissive = emissive
    }
}

/// line join style
public enum LineJoin: Sendable {
    case miter(limit: Float = 4)
    case round
    case bevel
}

/// dash pattern for stroked paths
public struct DashPattern: Sendable {
    /// dash and gap lengths, alternating, starting with a dash
    public let pattern: [Float]
    /// distance into the pattern to start at
    public let phase: Float

    public init(pattern: [Float], phase: Float = 0) {
        self.pattern = pattern
        self.phase = phase
    }

    /// splits a path into the runs that should actually be drawn
    ///
    /// an odd number of lengths repeats the whole list, the way SVG does, so
    /// [4, 2] and [4, 2, 4, 2] describe the same dashes. an empty, all-zero or
    /// negative pattern leaves the path solid
    func segments(of points: [Vector2D], closed: Bool) -> [[Vector2D]] {
        let epsilon: Float = 0.000001

        var lengths = pattern
        // a negative length makes the whole pattern invalid, so the path stays
        // solid rather than silently drawing nothing
        guard lengths.allSatisfy({ $0 >= 0 }) else { return [points] }
        if lengths.count % 2 == 1 { lengths += lengths }

        let total = lengths.reduce(0, +)
        guard lengths.count >= 2, total > epsilon, points.count >= 2 else { return [points] }

        var index = 0
        var remaining = lengths[0]
        var drawing = true

        // zero-length entries consume no distance, so step over them
        func nextEntry() {
            index = (index + 1) % lengths.count
            remaining = lengths[index]
            drawing.toggle()
        }

        // find where the phase lands in the pattern
        var phaseLeft = phase.truncatingRemainder(dividingBy: total)
        if phaseLeft < 0 { phaseLeft += total }

        while phaseLeft > epsilon {
            if remaining <= epsilon {
                nextEntry()
                continue
            }

            let step = min(phaseLeft, remaining)
            remaining -= step
            phaseLeft -= step

            if remaining <= epsilon { nextEntry() }
        }

        var runs: [[Vector2D]] = []
        var run: [Vector2D] = []

        // a closed path walks the seam too, so dashes carry through it
        let vertices = closed ? points + [points[0]] : points

        for i in 0..<(vertices.count - 1) {
            let from = vertices[i]
            let delta = vertices[i + 1] - from
            let length = delta.length
            guard length > epsilon else { continue }

            let direction = delta / length
            var offset: Float = 0

            while offset < length - epsilon {
                if remaining <= epsilon {
                    nextEntry()
                    continue
                }

                let step = min(length - offset, remaining)
                let start = from + direction * offset
                let end = from + direction * (offset + step)

                if drawing {
                    if run.isEmpty { run.append(start) }
                    run.append(end)
                } else if !run.isEmpty {
                    runs.append(run)
                    run = []
                }

                offset += step
                remaining -= step

                if remaining <= epsilon { nextEntry() }
            }
        }

        if !run.isEmpty { runs.append(run) }

        // a run that reaches the seam and a run that leaves it are one dash
        if closed, runs.count > 1,
           let first = runs.first?.first,
           let last = runs.last?.last,
           (first - points[0]).length <= epsilon,
           (last - points[0]).length <= epsilon {
            runs[0] = runs.removeLast() + runs[0]
        }

        return runs
    }
}

/// vertex format for 2D mesh rendering
public struct Vertex: Sendable, Hashable {
    public let position: Vector2D
    public let color: SIMD4<Float>
    /// emissive glow, in linear space: 'rgb' is the glow colour and 'w' is the
    /// strength multiplied into it
    ///
    /// written to the emissive render target and consumed by the bloom
    /// extractor, so an object can glow independently of its visible colour and
    /// alpha. a fully transparent or very dim primitive still blooms while its
    /// emissive is non-zero. '.zero' means 'no glow'
    public let emissive: SIMD4<Float>
    
    public init(position: Vector2D, color: SIMD4<Float>, emissive: SIMD4<Float> = .zero) {
        self.position = position
        self.color = color
        self.emissive = emissive
    }
    
    public init(position: SIMD2<Float>, color: SIMD4<Float>, emissive: SIMD4<Float> = .zero) {
        self.init(position: Vector2D(position), color: color, emissive: emissive)
    }
    
    public static var stride: Int { MemoryLayout<Vertex>.stride }
}

/// a 2D mesh consisting of vertices and optional indices
public struct Mesh2D: Sendable {
    public let vertices: [Vertex]
    public let indices: [UInt32]?
    
    public init(vertices: [Vertex], indices: [UInt32]? = nil) {
        self.vertices = vertices
        self.indices = indices
    }
    
    public var vertexCount: Int { vertices.count }
    public var indexCount: Int { indices?.count ?? 0 }
    public var isIndexed: Bool { indices != nil }
    public var triangleCount: Int { isIndexed ? indexCount / 3 : vertexCount / 3 }
}

/// builds 2D mesh geometry from primitives
///
/// the mesh builder accumulates triangles and can optionally generate
/// index buffers for geometry reuse
public final class MeshBuilder {
    private var vertices: [Vertex] = []
    private var indices: [UInt32] = []
    private var useIndices = false
    private var vertexCache: [Vertex: UInt32] = [:]
    private let cacheEnabled: Bool
    
    public init(useIndices: Bool = true) {
        self.useIndices = useIndices
        self.cacheEnabled = useIndices
    }
    
    /// adds a triangle to the mesh
    @discardableResult
    public func addTriangle(_ a: Vertex, _ b: Vertex, _ c: Vertex) -> (UInt32, UInt32, UInt32) {
        if useIndices {
            let ia = addVertex(a)
            let ib = addVertex(b)
            let ic = addVertex(c)
            indices.append(ia)
            indices.append(ib)
            indices.append(ic)
            return (ia, ib, ic)
        } else {
            let base = UInt32(vertices.count)
            vertices.append(a)
            vertices.append(b)
            vertices.append(c)
            return (base, base + 1, base + 2)
        }
    }
    
    /// adds a quad as two triangles
    public func addQuad(_ a: Vertex, _ b: Vertex, _ c: Vertex, _ d: Vertex) {
        addTriangle(a, b, c)
        addTriangle(a, c, d)
    }
    
    /// adds a vertex, reusing existing identical vertices if caching is enabled
    private func addVertex(_ vertex: Vertex) -> UInt32 {
        if cacheEnabled, let cached = vertexCache[vertex] {
            return cached
        }
        let index = UInt32(vertices.count)
        vertices.append(vertex)
        if cacheEnabled {
            vertexCache[vertex] = index
        }
        return index
    }
    
    /// builds the final mesh
    public func build() -> Mesh2D {
        let mesh = Mesh2D(vertices: vertices, indices: useIndices && !indices.isEmpty ? indices : nil)
        reset()
        return mesh
    }
    
    /// resets the builder for reuse
    public func reset() {
        vertices.removeAll(keepingCapacity: true)
        indices.removeAll(keepingCapacity: true)
        vertexCache.removeAll(keepingCapacity: true)
    }
    
    /// current vertex count
    public var vertexCount: Int { vertices.count }
    
    /// current index count
    public var indexCount: Int { indices.count }
}