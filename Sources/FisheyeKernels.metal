#include <metal_stdlib>
#include <CoreImage/CoreImage.h>
using namespace metal;

/// Real lens-accurate fisheye warp: source is a normal rectilinear (tangent) projection,
/// output is remapped to an equisolid-angle projection — the same math a real fisheye
/// lens produces (r = 2f·sin(θ/2)) instead of a generic radial "bump" that only looks
/// vaguely similar. `strength` (0...1) controls how much of the field of view the bulge
/// covers; at 0 the image is passed through unchanged.
extern "C" float2 fisheyeWarp(float2 position, float width, float height, float strength) {
    float2 center = float2(width, height) * 0.5;
    float2 d = position - center;
    float maxR = length(center); // corner distance — the normalizing radius
    if (maxR < 1.0 || strength < 0.001) {
        return position;
    }

    float r = length(d) / maxR; // 0 at center, ~1 at the frame edge
    if (r < 0.0001) {
        return position;
    }
    float2 dir = d / (r * maxR);

    // Field of view covered by the effect grows with strength, up to ~150°.
    float fov = strength * 2.6179939; // 150° in radians
    float halfFov = fov * 0.5;

    // Equisolid target angle for this destination radius (r in 0...1 maps to 0...halfFov).
    float theta = r * halfFov;

    // Where a true rectilinear (tangent-projection) source image holds that same real-world
    // angle theta — this is the inverse of what a normal lens does, so replaying that angle
    // through fisheye math is what actually pushes the center out and curls the edges in.
    float srcR = tan(theta) / tan(halfFov);
    srcR = clamp(srcR, 0.0, 4.0); // guard the tan() blow-up near 90°

    float2 srcPos = center + dir * srcR * maxR;
    return srcPos;
}

/// Chromatic aberration (color fringing) + vignette, both scaled by distance from center —
/// exactly the two artifacts that make a distortion read as "real glass" instead of a filter.
extern "C" float4 fisheyeGrade(coreimage::sample_t s, coreimage::sampler src, float2 position,
                                float width, float height, float chromaAmt, float vignetteAmt) {
    float2 center = float2(width, height) * 0.5;
    float2 d = position - center;
    float maxR = length(center);
    float r = maxR > 1.0 ? length(d) / maxR : 0.0;
    float2 dir = maxR > 1.0 ? d / maxR : float2(0.0, 0.0);

    // Sample red slightly further out, blue slightly further in, green unshifted —
    // the classic lateral chromatic aberration fringe that grows toward the edges.
    float shift = chromaAmt * r * r * 0.012 * maxR;
    float2 coordR = position + dir * shift;
    float2 coordB = position - dir * shift;

    float4 cR = src.sample(coordR);
    float4 cG = s;
    float4 cB = src.sample(coordB);
    float4 color = float4(cR.r, cG.g, cB.b, cG.a);

    float vignette = 1.0 - vignetteAmt * pow(r, 2.2) * 0.55;
    color.rgb *= clamp(vignette, 0.0, 1.0);

    return color;
}
