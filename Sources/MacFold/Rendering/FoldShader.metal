#include <metal_stdlib>
using namespace metal;

struct VertexOut { float4 position [[position]]; float2 uv; };
struct FoldUniforms {
    float progress; float perspective; float compression; float darkening;
    float4 material; // x: frost enabled
};

vertex VertexOut foldVertex(uint id [[vertex_id]]) {
    const float2 positions[3] = { float2(-1, -1), float2(3, -1), float2(-1, 3) };
    VertexOut out;
    out.position = float4(positions[id], 0, 1);
    out.uv = float2((positions[id].x + 1) * 0.5, (1 - positions[id].y) * 0.5);
    return out;
}

fragment float4 foldFragment(VertexOut in [[stage_in]],
                             texture2d<float> sharp [[texture(0)]],
                             texture2d<float> soft [[texture(1)]],
                             texture2d<float> medium [[texture(2)]],
                             texture2d<float> frosted [[texture(3)]],
                             constant FoldUniforms &u [[buffer(0)]]) {
    constexpr sampler sampleImage(coord::normalized, address::clamp_to_edge, filter::linear);
    float p = saturate(u.progress);
    if (p == 0.0) return float4(sharp.sample(sampleImage, in.uv).rgb, 1.0);
    float travel = p * p * (3.0 - 2.0 * p);
    float softness = sqrt(travel);
    float hingeDistance = 1.0 - in.uv.y;

    // Compensate for the panel moving toward the viewer. Unlike shrinking a
    // quad, this stretches the image up the panel while its lower edge stays
    // fixed. The finite denominator keeps the horizon stable at every angle.
    float tilt = travel * u.compression * 1.20;
    float depth = u.perspective * 0.24 * sin(travel * 1.35);
    // Distribute the stretch along the panel instead of transforming it as a
    // single rigid card. The rational mapping stays monotonic near closure.
    float projection = 1.0 / (1.0 - depth * hingeDistance * hingeDistance);
    float stretch = 1.0 / cos(tilt) - 1.0;
    float2 uv = float2(0.5 + (in.uv.x - 0.5) * projection,
                      1.0 - hingeDistance * projection / (1.0 + stretch * hingeDistance));

    // Frost develops away from the keyboard first. Interpolate actual Gaussian
    // blur levels rather than dissolving a sharp image into one uniform blur.
    float lateral = abs(in.uv.x * 2.0 - 1.0);
    float cornerField = lateral * lateral * hingeDistance * hingeDistance;
    float frost = saturate(pow(travel, 0.8) * (mix(0.08, 1.0, smoothstep(0.05, 0.90, hingeDistance))
                                    + 0.22 * cornerField));
    float3 color;
    if (frost < 0.20) {
        color = mix(sharp.sample(sampleImage, uv).rgb, soft.sample(sampleImage, uv).rgb, smoothstep(0.0, 0.20, frost));
    } else if (frost < 0.50) {
        color = mix(soft.sample(sampleImage, uv).rgb, medium.sample(sampleImage, uv).rgb, smoothstep(0.20, 0.50, frost));
    } else {
        color = mix(medium.sample(sampleImage, uv).rgb, frosted.sample(sampleImage, uv).rgb, smoothstep(0.50, 1.0, frost));
    }

    // The uncovered region is black, never a clamp-to-edge copy of desktop
    // pixels. Feather inward from the perspective boundary, especially near
    // the far corners, while keeping the keyboard edge comparatively stable.
    float sideWidth = max(fwidth(uv.x), softness * mix(0.035, 0.20, hingeDistance));
    float sideFog = max(0.0, 1.0 - min(uv.x, 1.0 - uv.x) / sideWidth);
    float bottomWidth = max(fwidth(in.uv.y), 0.025 * travel);
    float bottom = smoothstep(0.0, bottomWidth, 1.0 - in.uv.y);

    // A descending dark horizon follows the projected top edge. Most of the
    // transition extends into the image, so the area above is truly black and
    // the top dissolves over a much broader band than the side edges.
    float horizon = 1.0 - cos(tilt) / (1.0 + depth);
    float topWidth = max(fwidth(in.uv.y), softness * (0.32 + 0.12 * u.compression));
    float blackBoundary = 0.60 * horizon + 0.08 * travel * lateral * lateral;
    float topFog = max(0.0, 1.0 - (in.uv.y - blackBoundary) / topWidth);
    // Merge top and side extinction as one rounded field. Multiplying two
    // rectangular masks leaves recognizable corners even with wide feathers.
    float fog = saturate(length(float2(sideFog, topFog)));
    float extinction = fog * fog * fog * (fog * (fog * 6.0 - 15.0) + 10.0);
    float edge = (1.0 - extinction) * bottom;
    float shade = u.darkening * travel * mix(0.20, 1.0, hingeDistance * hingeDistance);
    color *= 1.0 - shade;
    // A restrained neutral lift gives the frost translucency without washing
    // out the desktop. It disappears exactly at the open and closed endpoints.
    color += 0.012 * u.material.x * frost * (1.0 - travel);
    float closure = 1.0 - smoothstep(0.86, 1.0, p);
    return float4(color * edge * closure, 1.0);
}
