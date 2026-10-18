import Testing
import Math
@testable import Graphics

/// the GPU-side vertex layout must stay in lockstep with the stored 'Vertex'
/// layout, and 'emissive' must not have grown the vertex
@Test func vertexLayoutMatchesStoredLayout() {
    let attributes = VertexLayout.attributes

    #expect(attributes.count == 3)
    #expect(attributes.map(\.location) == [0, 1, 2])

    let positionOffset = MemoryLayout<Vertex>.offset(of: \.position) ?? -1
    let colorOffset = MemoryLayout<Vertex>.offset(of: \.color) ?? -1
    let emissiveOffset = MemoryLayout<Vertex>.offset(of: \.emissive) ?? -1

    #expect(attributes[0].offset == UInt32(max(0, positionOffset)))
    #expect(attributes[1].offset == UInt32(max(0, colorOffset)))
    #expect(attributes[2].offset == UInt32(max(0, emissiveOffset)))

    // 'color' and 'emissive' share the 4-component float format
    #expect(attributes[1].format == attributes[2].format)

    // position(8) + color(16) + emissive(16): 'emissive' reuses the slot the
    // removed 2.5D 'elevation' data occupied, so the vertex stays 48 bytes
    #expect(Vertex.stride == 48)
}

@Test func vertexEmissiveDefaultsToNoGlow() {
    let vertex = Vertex(position: Vector2D(1, 2), color: SIMD4(1, 1, 1, 1))
    #expect(vertex.emissive == SIMD4<Float>.zero)
}

@Test func drawOptionEmissiveDefaultsToNil() {
    #expect(FillOptions(color: .white).emissive == nil)
    #expect(StrokeOptions(width: 1, color: .white).emissive == nil)
}
