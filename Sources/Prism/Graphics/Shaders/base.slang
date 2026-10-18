struct VertexInput {
    [[vk::location(0)]] float2 position;
    [[vk::location(1)]] float4 color;
    [[vk::location(2)]] float4 emissive;
};

struct VertexOutput {
    [[vk::location(0)]] float4 color : COLOR0;
    [[vk::location(1)]] float4 emissive : COLOR1;
    float4 position : SV_Position;
};

// the scene pass writes two colour targets: the visible HDR colour and an
// emissive buffer consumed by the bloom extractor. every pipeline built from
// this shader must therefore declare two colour targets
struct FragmentOutput {
    float4 color : SV_Target0;
    float4 emissive : SV_Target1;
};

[shader("vertex")]
VertexOutput vertexMain(VertexInput input) {
    VertexOutput output;

    output.position = float4(input.position, 0.0, 1.0);
    output.color = input.color;
    output.emissive = input.emissive;

    return output;
}

[shader("fragment")]
FragmentOutput fragmentMain(VertexOutput input) {
    FragmentOutput output;

    output.color = input.color;

    // 'w' scales the bloom so a primitive can glow independently of how bright
    // or opaque it looks
    output.emissive = float4(input.emissive.rgb * input.emissive.w, input.emissive.w);

    return output;
}
