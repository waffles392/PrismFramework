struct FragmentInput {
    [[vk::location(0)]] float2 uv;
    float4 position : SV_Position;
};

[[vk::binding(0, 2)]] Sampler2D<float4> emissiveTexture;

[shader("fragment")]
float4 fragmentMain(FragmentInput input) : SV_Target0 {
    // bloom is driven purely by authored emissive values, so a primitive can
    // glow independently of how bright or opaque it looks. there is no
    // luminance threshold: dim and transparent objects bloom if they emit
    float3 emissive = max(emissiveTexture.Sample(input.uv).rgb, 0.0);

    return float4(emissive, 1.0);
}
