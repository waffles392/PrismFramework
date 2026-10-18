import CSDL3
import Math

/// the GPU-side description of 'Vertex'
///
/// this is the single source of truth for the vertex memory layout used when
/// creating pipelines. 'SIMD4<Float>' is 16-byte aligned, so Swift inserts
/// padding between 'position' and 'color'; the offsets are therefore derived
/// from the actual stored-property offsets rather than assumed
internal enum VertexLayout {
    /// the number of bytes between consecutive vertices
    static var stride: UInt32 {
        UInt32(MemoryLayout<Vertex>.stride)
    }

    /// the vertex attributes, in 'location' order
    static var attributes: [VertexAttribute] {
        let colorOffset = UInt32(
            MemoryLayout<Vertex>.offset(of: \.color)
                ?? MemoryLayout<SIMD2<Float>>.stride
        )

        let emissiveOffset = UInt32(
            MemoryLayout<Vertex>.offset(of: \.emissive)
                ?? (Int(colorOffset) + MemoryLayout<SIMD4<Float>>.stride)
        )

        return [
            VertexAttribute(
                location: 0,
                bufferSlot: 0,
                format: SDL_GPU_VERTEXELEMENTFORMAT_FLOAT2,
                offset: 0
            ),
            VertexAttribute(
                location: 1,
                bufferSlot: 0,
                format: SDL_GPU_VERTEXELEMENTFORMAT_FLOAT4,
                offset: colorOffset
            ),
            VertexAttribute(
                location: 2,
                bufferSlot: 0,
                format: SDL_GPU_VERTEXELEMENTFORMAT_FLOAT4,
                offset: emissiveOffset
            ),
        ]
    }
}
