import Math

/// 'FillOptions' / 'StrokeOptions' conveniences on top of the primitive
/// drawing API
@MainActor
public extension Canvas2D {

    /// draws a polygon with optional fill and stroke options
    func polygon(
        _ points: [Vector2D],
        fill: FillOptions?,
        stroke: StrokeOptions?
    ) {
        polygon(
            points,
            fill: fill?.color,
            lineWidth: stroke?.width ?? 0,
            strokeColor: stroke?.color,
            closed: true,
            join: stroke?.join ?? .miter(),
            dash: stroke?.dash,
            emissive: fill?.emissive ?? stroke?.emissive
        )
    }

    /// strokes a closed polygon outline using 'StrokeOptions'
    func polygonOutline(
        _ points: [Vector2D],
        options: StrokeOptions
    ) {
        polygon(
            points,
            fill: nil,
            lineWidth: options.width,
            strokeColor: options.color,
            closed: true,
            join: options.join,
            dash: options.dash,
            emissive: options.emissive
        )
    }

    /// draws a connected polyline (or polygon if 'closed') using
    /// 'StrokeOptions'
    func polyline(
        _ points: [Vector2D],
        options: StrokeOptions,
        closed: Bool
    ) {
        polygon(
            points,
            fill: nil,
            lineWidth: options.width,
            strokeColor: options.color,
            closed: closed,
            join: options.join,
            dash: options.dash,
            emissive: options.emissive
        )
    }

    /// draws an ellipse with optional fill and stroke options
    func ellipse(
        in rect: Rect2D,
        fill: FillOptions?,
        stroke: StrokeOptions?
    ) {
        ellipse(
            in: rect,
            fill: fill?.color,
            lineWidth: stroke?.width ?? 0,
            strokeColor: stroke?.color,
            join: stroke?.join ?? .miter(),
            dash: stroke?.dash,
            emissive: fill?.emissive ?? stroke?.emissive
        )
    }

    /// draws a cubic Bezier curve through 'points' (start, control1,
    /// control2, end), stroked with 'stroke'
    func bezierCurve(
        _ points: [Vector2D],
        segments: Int,
        stroke: StrokeOptions
    ) {
        guard points.count == 4, stroke.width > 0 else { return }

        let p0 = points[0], p1 = points[1], p2 = points[2], p3 = points[3]
        let count = max(2, segments)

        var curvePoints: [Vector2D] = []
        curvePoints.reserveCapacity(count + 1)

        for i in 0...count {
            let t = Float(i) / Float(count)
            let u = 1 - t
            let tt = t * t
            let uu = u * u
            let uuu = uu * u
            let ttt = tt * t

            curvePoints.append(
                p0 * uuu +
                p1 * (3 * uu * t) +
                p2 * (3 * u * tt) +
                p3 * ttt
            )
        }

        // stroked as one path, so 'join' and 'dash' cover the whole curve
        strokePolyline(
            curvePoints,
            width: stroke.width,
            color: stroke.color,
            closed: false,
            join: stroke.join,
            dash: stroke.dash,
            emissive: stroke.emissive
        )
    }
}
