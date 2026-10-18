struct FragmentInput
{
    [[vk::location(0)]] float2 uv;
    float4 position : SV_Position;
};

[[vk::binding(0, 2)]] Sampler2D<float4> sourceTexture;
[[vk::binding(1, 2)]] Sampler2D<float4> bloom0Texture;
[[vk::binding(2, 2)]] Sampler2D<float4> bloom1Texture;
[[vk::binding(3, 2)]] Sampler2D<float4> bloom2Texture;

[[vk::binding(0, 3)]]
cbuffer PresentUniforms
{
    float4 params0;
    float4 params1;
    float4 params2;
    float4 params3;
};

float3 tonemapACES(float3 x)
{
    const float a = 2.51;
    const float b = 0.03;
    const float c = 2.43;
    const float d = 0.59;
    const float e = 0.14;

    return saturate((x * (a * x + b)) / (x * (c * x + d) + e));
}

float3 linearToSRGB(float3 lin)
{
    float3 low = lin * 12.92;
    float3 high = 1.055 * pow(max(lin, 0.0), 1.0 / 2.4) - 0.055;
    return lerp(low, high, step(0.0031308, lin));
}

float3 applyTemperature(float3 color, float temperature)
{
    color.r += temperature * 0.10;
    color.g += temperature * 0.02;
    color.b -= temperature * 0.10;
    return color;
}

float3 applyTint(float3 color, float tint)
{
    color.r -= tint * 0.05;
    color.g += tint * 0.05;
    color.b -= tint * 0.05;
    return color;
}

float hash21(float2 p)
{
    p = frac(p * float2(123.34, 456.21));
    p += dot(p, p + 19.19);
    return frac(p.x * p.y);
}

float randomNoise(float2 coord, float time)
{
    return hash21(coord + time * 17.37);
}

float vignetteFactor(float2 uv, float strength)
{
    float2 c = uv - 0.5;
    float r = dot(c, c);
    float vig = cos(r * 3.14159 * 0.5);
    return lerp(1.0, saturate(vig), strength * 1.5);
}

[shader("fragment")]
float4 fragmentMain(FragmentInput input) : SV_Target0
{
    float2 uv = input.uv;

    float time           = params0.w;
    float exposure       = params0.x;
    float saturation     = params0.y;
    float contrast       = params0.z;

    float scanStrength   = params1.x;
    float noiseStrength  = params1.y;
    float aberration     = params1.z;
    float bloomIntensity = params1.w;

    float temperature    = params2.x;
    float tint           = params2.y;
    float lift           = params2.z;
    float gamma          = params2.w;

    float gain           = params3.x;
    float distortion     = params3.y;
    float vignetteStr    = params3.z;
    float bloomSat       = params3.w;

    // 1. Analog UV Distortion
    if (distortion > 0.0)
    {
        uv.x += sin(uv.y * 90.0 + time * 1.7) * 0.004 * distortion;
        uv.y += sin(uv.x * 18.0 + time * 0.7) * 0.001 * distortion;
    }

    // 2. Chromatic Aberration
    float2 center = uv - 0.5;
    float3 scene;
    if (aberration > 0.0)
    {
        scene.r = sourceTexture.Sample(uv + center * aberration * 0.015).r;
        scene.g = sourceTexture.Sample(uv).g;
        scene.b = sourceTexture.Sample(uv - center * aberration * 0.015).b;
    }
    else
    {
        scene = sourceTexture.Sample(uv).rgb;
    }

    // 3. Multi-Scale Bloom Summation (with premultiplied alpha)
    float4 bloom0 = bloom0Texture.Sample(uv);
    float4 bloom1 = bloom1Texture.Sample(uv);
    float4 bloom2 = bloom2Texture.Sample(uv);

    float4 bloom = bloom0 * 0.50 + bloom1 * 0.35 + bloom2 * 0.15;

    // Bloom Saturation (Unconditional, preserves premultiplied alpha)
    float bloomLuma = dot(bloom.rgb, float3(0.2126, 0.7152, 0.0722));
    bloom.rgb = lerp(bloomLuma.xxx, bloom.rgb, bloomSat);

    // 4. HDR Composition & Exposure (additive bloom with premultiplied alpha)
    // Map bloom such that it never exceeds bloomIntensity, acting as a maximum cap
    bloom.rgb = (1.0 - exp(-bloom.rgb)) * bloomIntensity;
    float3 color = scene + bloom.rgb;
    color *= exp2(exposure);

    // 5. White Balance
    color = applyTemperature(color, temperature);
    color = applyTint(color, tint);
    color = max(color, 0.0);

    // 6. ACES Tonemapping
    color = tonemapACES(color);

    // 7. Post-Tonemap Color Grading
    color = max(color * gain + lift, 0.0);
    color = pow(color, 1.0 / max(gamma, 0.001));

    float luma = dot(color, float3(0.2126, 0.7152, 0.0722));
    color = lerp(luma.xxx, color, saturation);
    color = saturate((color - 0.5) * contrast + 0.5);

    // 8. Vignette & Scanlines & Grain
    color *= vignetteFactor(input.uv, vignetteStr);

    if (scanStrength > 0.0)
    {
        float scan = 1.0 - scanStrength * (0.5 + 0.5 * sin(input.position.y * 3.14159));
        color *= scan;
    }

    if (noiseStrength > 0.0)
    {
        float noise = (randomNoise(input.position.xy, time) - 0.5) * noiseStrength;
        color += noise;
    }

    // 9. Output sRGB
    color = saturate(linearToSRGB(saturate(color)));
    return float4(color, 1.0);
}