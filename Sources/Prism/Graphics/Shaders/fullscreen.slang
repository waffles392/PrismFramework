// shared fullscreen triangle vertex shader for all postprocess passes.
struct VertexInput {
    [[vk::location(0)]] float2 position;
    [[vk::location(1)]] float4 color;
};

struct VertexOutput {
    [[vk::location(0)]] float2 uv;
    float4 position : SV_Position;
};

[shader("vertex")]
VertexOutput vertexMain(VertexInput input) {
    VertexOutput output;
    output.position = float4(input.position, 0.0, 1.0);

    // sdl maps ndc +y upward, sampled textures use top-left origin.
    // flip y so every fullscreen pass preserves correct screen space orientation.
    
    output.uv = float2(input.position.x * 0.5 + 0.5, 0.5 - input.position.y * 0.5);
    return output;
}