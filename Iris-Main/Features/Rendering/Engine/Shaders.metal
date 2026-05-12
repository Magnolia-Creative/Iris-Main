#include <metal_stdlib>
using namespace metal;

struct VertexIn {
    float2 position [[attribute(0)]];
    float2 texCoord [[attribute(1)]];
};

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

struct ColorAdjustments {
    float temperature;
    float tint;
    float exposure;
    float brightness;
    float contrast;
    float saturation;
    float highlights;
    float shadows;
    float opacity;
};

vertex VertexOut compositorVertex(
    VertexIn in [[stage_in]],
    constant float4x4 &transform [[buffer(1)]]
) {
    VertexOut out;
    out.position = transform * float4(in.position, 0.0, 1.0);
    out.texCoord = in.texCoord;
    return out;
}

fragment float4 compositorFragment(
    VertexOut in [[stage_in]],
    texture2d<float> sourceTexture [[texture(0)]],
    sampler textureSampler [[sampler(0)]],
    constant ColorAdjustments &adjustments [[buffer(0)]]
) {
    float4 color = sourceTexture.sample(textureSampler, in.texCoord);

    float alpha = color.a;
    if (alpha < 0.001) {
        return float4(0.0);
    }

    // Un-premultiply for correct color math
    float3 rgb = color.rgb / alpha;

    // Exposure (EV stops)
    rgb *= pow(2.0, adjustments.exposure);

    // Temperature and tint are normalized warm/cool and green/magenta shifts.
    rgb.r += adjustments.temperature * 0.10;
    rgb.b -= adjustments.temperature * 0.10;
    rgb.g += adjustments.tint * 0.08;
    rgb.r -= adjustments.tint * 0.04;
    rgb.b -= adjustments.tint * 0.04;

    // Brightness is an additive lift after white balance and exposure.
    rgb += adjustments.brightness;

    // Contrast (pivot at mid-gray)
    rgb = ((rgb - 0.5) * (1.0 + adjustments.contrast)) + 0.5;

    // Saturation (luminance-preserving)
    float luminance = dot(rgb, float3(0.2126, 0.7152, 0.0722));
    rgb = mix(float3(luminance), rgb, 1.0 + adjustments.saturation);

    // Highlight / shadow lift
    float lum = dot(rgb, float3(0.2126, 0.7152, 0.0722));
    float highlightWeight = smoothstep(0.5, 1.0, lum);
    float shadowWeight = 1.0 - smoothstep(0.0, 0.5, lum);
    rgb += adjustments.highlights * highlightWeight;
    rgb += adjustments.shadows * shadowWeight;

    rgb = clamp(rgb, 0.0, 1.0);

    // Re-premultiply with final opacity
    float finalAlpha = alpha * adjustments.opacity;
    return float4(rgb * finalAlpha, finalAlpha);
}
