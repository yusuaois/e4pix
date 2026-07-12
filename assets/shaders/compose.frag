// Compose pass — blends brush layers onto develop output using per-pixel
// comparison to detect which pixels each layer actually modified.
//
// Each brush layer is independently rendered against the same base
// (develop+mask output). For pixels a brush did NOT modify, the layer
// pixel value equals the base exactly. For modified pixels, the value
// differs. The compose pass checks `layer.rgb != base.rgb` and only
// replaces pixels that were actually changed.
//
// Layers are applied in registration order. Later layers overwrite
// earlier ones where both modified the same pixel (last-write-wins).

#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uLayerCount;

// Per-layer active flags (0.0 or 1.0)
uniform float uActive0;
uniform float uActive1;
uniform float uActive2;
uniform float uActive3;
uniform float uActive4;
uniform float uActive5;
uniform float uActive6;
uniform float uActive7;

uniform sampler2D uBase;     // developOutput
uniform sampler2D uLayer0;
uniform sampler2D uLayer1;
uniform sampler2D uLayer2;
uniform sampler2D uLayer3;
uniform sampler2D uLayer4;
uniform sampler2D uLayer5;
uniform sampler2D uLayer6;
uniform sampler2D uLayer7;

out vec4 fragColor;

void main() {
    vec2 uv = FlutterFragCoord().xy / uSize;
    vec4 result = texture(uBase, uv);
    vec3 baseRgb = result.rgb;

    // For each active layer, compare the layer pixel with baseRgb.
    // If they differ, the brush modified this pixel — apply the change.
    // If they match, this pixel was untouched — leave it alone.
    // This prevents later layers from overwriting earlier layers'
    // modifications with stale "unmodified" pixels.
    if (uActive0 > 0.5) {
        vec4 l0 = texture(uLayer0, uv);
        if (any(notEqual(l0.rgb, baseRgb))) result = l0;
    }
    if (uActive1 > 0.5) {
        vec4 l1 = texture(uLayer1, uv);
        if (any(notEqual(l1.rgb, baseRgb))) result = l1;
    }
    if (uActive2 > 0.5) {
        vec4 l2 = texture(uLayer2, uv);
        if (any(notEqual(l2.rgb, baseRgb))) result = l2;
    }
    if (uActive3 > 0.5) {
        vec4 l3 = texture(uLayer3, uv);
        if (any(notEqual(l3.rgb, baseRgb))) result = l3;
    }
    if (uActive4 > 0.5) {
        vec4 l4 = texture(uLayer4, uv);
        if (any(notEqual(l4.rgb, baseRgb))) result = l4;
    }
    if (uActive5 > 0.5) {
        vec4 l5 = texture(uLayer5, uv);
        if (any(notEqual(l5.rgb, baseRgb))) result = l5;
    }
    if (uActive6 > 0.5) {
        vec4 l6 = texture(uLayer6, uv);
        if (any(notEqual(l6.rgb, baseRgb))) result = l6;
    }
    if (uActive7 > 0.5) {
        vec4 l7 = texture(uLayer7, uv);
        if (any(notEqual(l7.rgb, baseRgb))) result = l7;
    }

    fragColor = result;
}
