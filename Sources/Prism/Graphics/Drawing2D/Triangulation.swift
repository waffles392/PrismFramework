import Foundation
import Math

/// triangulation utilities for 2D polygons
public enum Triangulation {
    private static let epsilon: Float = 0.000001
    
    /// triangulates a simple polygon using ear clipping
    /// returns an array of triangles (each as 3 vertices)
    /// the input polygon must be simple (non-self-intersecting)
    public static func triangulate(_ points: [Vector2D]) -> [(Vector2D, Vector2D, Vector2D)] {
        let cleaned = removeCollinearVertices(cleanedPoints(points, closed: true))
        
        guard cleaned.count >= 3 else { return [] }
        
        let area = signedArea(cleaned)
        guard area.isFinite, abs(area) > epsilon else { return [] }
        
        let winding: Float = area > 0 ? 1 : -1
        
        var remaining = Array(cleaned.indices)
        var triangles: [(Vector2D, Vector2D, Vector2D)] = []
        triangles.reserveCapacity(cleaned.count - 2)
        
        let maxIterations = cleaned.count * cleaned.count
        var iterations = 0
        
        while remaining.count > 3 {
            iterations += 1
            guard iterations <= maxIterations else { return [] }
            
            var foundEar = false
            
            for slot in 0..<remaining.count {
                let previousSlot = (slot + remaining.count - 1) % remaining.count
                let nextSlot = (slot + 1) % remaining.count
                
                let previousIndex = remaining[previousSlot]
                let currentIndex = remaining[slot]
                let nextIndex = remaining[nextSlot]
                
                let a = cleaned[previousIndex]
                let b = cleaned[currentIndex]
                let c = cleaned[nextIndex]
                
                // the candidate must be convex in the polygon's winding
                let cross = (b - a).cross(c - b)
                guard cross * winding > epsilon else { continue }
                
                // the diagonal a-c must not contain another polygon vertex
                var containsPoint = false
                
                for index in remaining {
                    guard index != previousIndex, index != currentIndex, index != nextIndex else { continue }
                    
                    if point(cleaned[index], isInsideTriangle: (a, b, c), winding: winding) {
                        containsPoint = true
                        break
                    }
                }
                
                guard !containsPoint else { continue }
                
                triangles.append((a, b, c))
                remaining.remove(at: slot)
                foundEar = true
                break
            }
            
            guard foundEar else { return [] }
        }
        
        guard remaining.count == 3 else { return [] }
        
        let a = cleaned[remaining[0]]
        let b = cleaned[remaining[1]]
        let c = cleaned[remaining[2]]
        
        let finalCross = (b - a).cross(c - b)
        guard abs(finalCross) > epsilon else { return triangles }
        
        triangles.append((a, b, c))
        return triangles
    }
    
    /// removes duplicate and near-duplicate consecutive points
    static func cleanedPoints(_ points: [Vector2D], closed: Bool) -> [Vector2D] {
        guard !points.isEmpty else { return [] }
        
        var clean: [Vector2D] = []
        clean.reserveCapacity(points.count)
        
        for point in points {
            guard point.x.isFinite && point.y.isFinite else { continue }
            
            if clean.isEmpty {
                clean.append(point)
                continue
            }
            
            let distance = (point - clean[clean.count - 1]).length
            if distance > epsilon {
                clean.append(point)
            }
        }
        
        if closed, clean.count > 1 {
            let distance = (clean[0] - clean[clean.count - 1]).length
            if distance <= epsilon {
                clean.removeLast()
            }
        }
        
        return clean
    }
    
    /// removes collinear vertices from a polygon
    private static func removeCollinearVertices(_ points: [Vector2D]) -> [Vector2D] {
        guard points.count > 3 else { return points }
        
        var result = points
        var changed = true
        
        while changed && result.count > 3 {
            changed = false
            let n = result.count
            
            for i in 0..<n {
                let previous = result[(i + n - 1) % n]
                let current = result[i]
                let next = result[(i + 1) % n]
                
                let a = current - previous
                let b = next - current
                let cross = a.cross(b)
                
                guard abs(cross) <= epsilon else { continue }
                
                // only remove a vertex when it lies along the segment,
                // not when the polygon doubles back on itself
                let dot = a.x * b.x + a.y * b.y
                guard dot >= -epsilon else { continue }
                
                result.remove(at: i)
                changed = true
                break
            }
        }
        
        return result
    }
    
    /// calculates signed area of a polygon
    private static func signedArea(_ points: [Vector2D]) -> Float {
        guard points.count >= 3 else { return 0 }
        
        var area: Float = 0
        for i in 0..<points.count {
            area += points[i].cross(points[(i + 1) % points.count])
        }
        return area * 0.5
    }
    
    /// tests if a point is inside a triangle
    private static func point(_ point: Vector2D, isInsideTriangle triangle: (Vector2D, Vector2D, Vector2D), winding: Float) -> Bool {
        let (a, b, c) = triangle
        
        let ab = (b - a).cross(point - a) * winding
        let bc = (c - b).cross(point - b) * winding
        let ca = (a - c).cross(point - c) * winding
        
        return ab >= -epsilon && bc >= -epsilon && ca >= -epsilon
    }
}

/// stroke generation utilities for lines and outlines
public enum StrokeGenerator {
    private static let epsilon: Float = 0.000001
    /// miter limit used when the join style does not carry one
    private static let defaultMiterLimit: Float = 4

    /// the offset points a corner contributes, plus any outer-side fill
    ///
    /// 'incoming' is the offset for the edge arriving at the corner, 'outgoing'
    /// for the edge leaving it. the inner side is always the miter
    /// intersection, so it has neither a gap nor an overlap, and the join
    /// style only changes the outer side
    private struct Corner {
        var incomingLeft: Vector2D
        var outgoingLeft: Vector2D
        var incomingRight: Vector2D
        var outgoingRight: Vector2D
        var fill: [(Vector2D, Vector2D, Vector2D)] = []
    }

    // MARK: - Closed polygon

    /// generates triangle vertices for a closed polygon stroke
    public static func strokeClosedPolygon(
        _ points: [Vector2D],
        width: Float,
        color: Color,
        join: LineJoin = .miter()
    ) -> [Vertex] {
        let n = points.count
        let halfWidth = width * 0.5
        guard n >= 3, halfWidth > 0 else { return [] }

        // detect winding: positive = CCW, negative = CW
        let winding = polygonWinding(points)
        let flip = winding < 0

        var incomingLeft = [Vector2D](repeating: .zero, count: n)
        var outgoingLeft = [Vector2D](repeating: .zero, count: n)
        var incomingRight = [Vector2D](repeating: .zero, count: n)
        var outgoingRight = [Vector2D](repeating: .zero, count: n)
        var fill: [(Vector2D, Vector2D, Vector2D)] = []

        for i in 0..<n {
            let previous = points[(i + n - 1) % n]
            let current = points[i]
            let next = points[(i + 1) % n]

            let edgeA = current - previous
            let edgeB = next - current
            let lengthA = edgeA.length
            let lengthB = edgeB.length

            let normalA = safePerpendicular(lengthA > epsilon ? edgeA : edgeB)
            let normalB = safePerpendicular(lengthB > epsilon ? edgeB : edgeA)

            let corner = cornerPoints(
                at: current,
                normalA: normalA,
                normalB: normalB,
                halfWidth: halfWidth,
                join: join
            )

            // flipping keeps the emitted triangles on the input winding
            incomingLeft[i] = flip ? corner.incomingRight : corner.incomingLeft
            outgoingLeft[i] = flip ? corner.outgoingRight : corner.outgoingLeft
            incomingRight[i] = flip ? corner.incomingLeft : corner.incomingRight
            outgoingRight[i] = flip ? corner.outgoingLeft : corner.outgoingRight

            for triangle in corner.fill {
                fill.append(flip ? (triangle.0, triangle.2, triangle.1) : triangle)
            }
        }

        var vertices: [Vertex] = []
        vertices.reserveCapacity(n * 6 + fill.count * 3)

        let linearColor = color.linearValue

        for i in 0..<n {
            let next = (i + 1) % n

            // triangle 1: left[i] -> right[i] -> right[next] (CCW)
            vertices.append(Vertex(position: outgoingLeft[i], color: linearColor))
            vertices.append(Vertex(position: outgoingRight[i], color: linearColor))
            vertices.append(Vertex(position: incomingRight[next], color: linearColor))

            // triangle 2: left[i] -> left[next] -> right[next] (CCW)
            vertices.append(Vertex(position: outgoingLeft[i], color: linearColor))
            vertices.append(Vertex(position: incomingLeft[next], color: linearColor))
            vertices.append(Vertex(position: incomingRight[next], color: linearColor))
        }

        appendFill(fill, color: linearColor, to: &vertices)

        return vertices
    }

    // MARK: - Open polyline

    /// generates triangle vertices for an open polyline stroke
    public static func strokeOpenPolyline(
        _ points: [Vector2D],
        width: Float,
        color: Color,
        join: LineJoin = .miter()
    ) -> [Vertex] {
        let n = points.count
        let halfWidth = width * 0.5
        guard n >= 2, halfWidth > 0 else { return [] }

        // the butt caps need a real direction at each end
        let firstEdge = points[1] - points[0]
        let lastEdge = points[n - 1] - points[n - 2]
        guard firstEdge.length > epsilon, lastEdge.length > epsilon else { return [] }

        var incomingLeft = [Vector2D](repeating: .zero, count: n)
        var outgoingLeft = [Vector2D](repeating: .zero, count: n)
        var incomingRight = [Vector2D](repeating: .zero, count: n)
        var outgoingRight = [Vector2D](repeating: .zero, count: n)
        var fill: [(Vector2D, Vector2D, Vector2D)] = []

        // start cap
        do {
            let direction = firstEdge / firstEdge.length
            let normal = Vector2D(-direction.y, direction.x)
            outgoingLeft[0] = points[0] + normal * halfWidth
            outgoingRight[0] = points[0] - normal * halfWidth
        }

        // joined interior points
        for i in 1..<(n - 1) {
            let previous = points[i - 1]
            let current = points[i]
            let next = points[i + 1]

            let edgeA = current - previous
            let edgeB = next - current
            let lengthA = edgeA.length
            let lengthB = edgeB.length

            let normalA = safePerpendicular(lengthA > epsilon ? edgeA : edgeB)
            let normalB = safePerpendicular(lengthB > epsilon ? edgeB : edgeA)

            let corner = cornerPoints(
                at: current,
                normalA: normalA,
                normalB: normalB,
                halfWidth: halfWidth,
                join: join
            )

            incomingLeft[i] = corner.incomingLeft
            outgoingLeft[i] = corner.outgoingLeft
            incomingRight[i] = corner.incomingRight
            outgoingRight[i] = corner.outgoingRight
            fill.append(contentsOf: corner.fill)
        }

        // end cap
        do {
            let direction = lastEdge / lastEdge.length
            let normal = Vector2D(-direction.y, direction.x)
            incomingLeft[n - 1] = points[n - 1] + normal * halfWidth
            incomingRight[n - 1] = points[n - 1] - normal * halfWidth
        }

        var vertices: [Vertex] = []
        vertices.reserveCapacity((n - 1) * 6 + fill.count * 3)

        let linearColor = color.linearValue

        for i in 0..<(n - 1) {
            // triangle 1: left[i] -> right[i] -> right[i+1] (CCW)
            vertices.append(Vertex(position: outgoingLeft[i], color: linearColor))
            vertices.append(Vertex(position: outgoingRight[i], color: linearColor))
            vertices.append(Vertex(position: incomingRight[i + 1], color: linearColor))

            // triangle 2: left[i] -> left[i+1] -> right[i+1] (CCW)
            vertices.append(Vertex(position: outgoingLeft[i], color: linearColor))
            vertices.append(Vertex(position: incomingLeft[i + 1], color: linearColor))
            vertices.append(Vertex(position: incomingRight[i + 1], color: linearColor))
        }

        appendFill(fill, color: linearColor, to: &vertices)

        return vertices
    }

    // MARK: - Corners

    /// works out the four offset points of a corner and any fill it needs
    private static func cornerPoints(
        at point: Vector2D,
        normalA: Vector2D,
        normalB: Vector2D,
        halfWidth: Float,
        join: LineJoin
    ) -> Corner {
        let limit = miterLimit(join)

        // the inner side meets at the miter intersection, and so does a plain
        // miter join on the outer side
        let leftMiter = miterPoint(
            point: point,
            normalA: normalA,
            normalB: normalB,
            halfWidth: halfWidth,
            limit: limit
        )
        let rightMiter = miterPoint(
            point: point,
            normalA: normalA * -1,
            normalB: normalB * -1,
            halfWidth: halfWidth,
            limit: limit
        )

        var result = Corner(
            incomingLeft: leftMiter,
            outgoingLeft: leftMiter,
            incomingRight: rightMiter,
            outgoingRight: rightMiter
        )

        let turn = normalA.cross(normalB)
        guard abs(turn) > epsilon else { return result }

        // a plain miter already closes the outer side, so only 'round' and
        // 'bevel' replace it
        if case .miter(_) = join { return result }

        // a left turn opens the right side and a right turn opens the left one
        if turn > 0 {
            let incoming = point - normalA * halfWidth
            let outgoing = point - normalB * halfWidth
            result.incomingRight = incoming
            result.outgoingRight = outgoing
            result.fill = joinFill(
                point: point,
                from: incoming,
                to: outgoing,
                halfWidth: halfWidth,
                join: join
            )
        } else {
            let incoming = point + normalA * halfWidth
            let outgoing = point + normalB * halfWidth
            result.incomingLeft = incoming
            result.outgoingLeft = outgoing
            result.fill = joinFill(
                point: point,
                from: incoming,
                to: outgoing,
                halfWidth: halfWidth,
                join: join
            )
        }

        return result
    }

    /// geometry closing the outer side of a corner
    ///
    /// '.miter' adds none, because the miter point above already closes it
    private static func joinFill(
        point: Vector2D,
        from start: Vector2D,
        to end: Vector2D,
        halfWidth: Float,
        join: LineJoin
    ) -> [(Vector2D, Vector2D, Vector2D)] {
        switch join {
        case .miter(_):
            return []
        case .bevel:
            return [counterClockwise(point, start, end)]
        case .round:
            let startAngle = atan2(start.y - point.y, start.x - point.x)
            let endAngle = atan2(end.y - point.y, end.x - point.x)
            var sweep = endAngle - startAngle
            while sweep > .pi { sweep -= 2 * .pi }
            while sweep < -.pi { sweep += 2 * .pi }

            let maxAngle = Float.pi / 12
            let steps = max(1, Int((abs(sweep) / maxAngle - 0.0001).rounded(.up)))
            var triangles: [(Vector2D, Vector2D, Vector2D)] = []
            triangles.reserveCapacity(steps)

            var previous = start
            for step in 1...steps {
                let t = Float(step) / Float(steps)
                let angle = startAngle + sweep * t
                let current = point + Vector2D(cos(angle), sin(angle)) * halfWidth
                triangles.append(counterClockwise(point, previous, current))
                previous = current
            }
            return triangles
        }
    }

    private static func miterPoint(
        point: Vector2D,
        normalA: Vector2D,
        normalB: Vector2D,
        halfWidth: Float,
        limit: Float
    ) -> Vector2D {
        let summed = normalA + normalB
        let summedLength = summed.length

        if !summedLength.isFinite || summedLength <= epsilon {
            return point + normalA * halfWidth
        }

        let miter = summed / summedLength
        let denominator = miter.x * normalA.x + miter.y * normalA.y

        if !denominator.isFinite || abs(denominator) <= epsilon {
            return point + normalA * halfWidth
        }

        var distance = halfWidth / denominator
        let joinLimit = max(halfWidth * limit, halfWidth)

        if !distance.isFinite {
            distance = distance.sign == .minus ? -joinLimit : joinLimit
        } else {
            distance = max(-joinLimit, min(joinLimit, distance))
        }

        let result = point + miter * distance
        guard result.x.isFinite && result.y.isFinite else {
            return point + normalA * halfWidth
        }
        return result
    }

    private static func miterLimit(_ join: LineJoin) -> Float {
        if case .miter(let limit) = join { return limit }
        return defaultMiterLimit
    }

    /// orders a triangle so that its winding is counter-clockwise
    private static func counterClockwise(
        _ a: Vector2D,
        _ b: Vector2D,
        _ c: Vector2D
    ) -> (Vector2D, Vector2D, Vector2D) {
        let area = (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
        return area >= 0 ? (a, b, c) : (a, c, b)
    }

    private static func appendFill(
        _ triangles: [(Vector2D, Vector2D, Vector2D)],
        color: SIMD4<Float>,
        to vertices: inout [Vertex]
    ) {
        for triangle in triangles {
            vertices.append(Vertex(position: triangle.0, color: color))
            vertices.append(Vertex(position: triangle.1, color: color))
            vertices.append(Vertex(position: triangle.2, color: color))
        }
    }

    private static func safePerpendicular(_ vector: Vector2D) -> Vector2D {
        let length = vector.length
        guard length > epsilon, length.isFinite else { return Vector2D(0, 1) }
        return Vector2D(-vector.y, vector.x) / length
    }

    private static func polygonWinding(_ points: [Vector2D]) -> Float {
        var area: Float = 0
        let n = points.count
        for i in 0..<n {
            area += points[i].cross(points[(i + 1) % n])
        }
        return area >= 0 ? 1 : -1
    }
}
