struct FragmentInput
{
    [[vk::location(0)]] float2 uv;
    float4 position : SV_Position;
};

[[vk::binding(0, 2)]]
Sampler2D<float4> sourceTexture;

[[vk::binding(0, 3)]]
cbuffer BlurUniforms
{
    float4 params;
};

[shader("fragment")]
float4 fragmentMain(FragmentInput input) : SV_Target0
{
    float2 step = params.xy * max(params.z, 1.0);

    float4 result =
        sourceTexture.Sample(input.uv) * 0.40;

    result += sourceTexture.Sample(
        input.uv + step * 1.5
    ) * 0.25;

    result += sourceTexture.Sample(
        input.uv - step * 1.5
    ) * 0.25;

    result += sourceTexture.Sample(
        input.uv + step * 3.0
    ) * 0.05;

    result += sourceTexture.Sample(
        input.uv - step * 3.0
    ) * 0.05;

    return result;
}