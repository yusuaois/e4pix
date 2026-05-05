#include <flutter/runtime_effect.glsl>

precision highp float;

// 顺序必须与 Dart 端 setFloat 索引一致
uniform vec2  uSize;          // 0,1
uniform float uExposure;      // 2
uniform float uTempScale;     // 3
uniform float uTint;          // 4
uniform float uContrast;      // 5
uniform float uHighlights;    // 6
uniform float uShadows;       // 7
uniform float uWhites;        // 8
uniform float uBlacks;        // 9
uniform float uSaturation;    // 10
uniform float uVibrance;      // 11

uniform sampler2D uImage;     // sampler index 0

out vec4 fragColor;

// ----- 色彩空间 -----
vec3 srgbToLinear(vec3 c) {
    bvec3 cutoff = lessThanEqual(c, vec3(0.04045));
    vec3 lo = c / 12.92;
    vec3 hi = pow((c + 0.055) / 1.055, vec3(2.4));
    return mix(hi, lo, vec3(cutoff));
}
vec3 linearToSrgb(vec3 c) {
    c = clamp(c, 0.0, 1.0);
    bvec3 cutoff = lessThanEqual(c, vec3(0.0031308));
    vec3 lo = c * 12.92;
    vec3 hi = 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055;
    return mix(hi, lo, vec3(cutoff));
}
float luma(vec3 c) { return dot(c, vec3(0.2126, 0.7152, 0.0722)); }

// ----- 各算子 -----
vec3 applyWB(vec3 c, float t, float tint) {
    return c * vec3(1.0 + t * 0.4, 1.0 - tint * 0.2, 1.0 - t * 0.4);
}
vec3 applyExposure(vec3 c, float ev) { return c * pow(2.0, ev); }

vec3 applyWhitesBlacks(vec3 c, float w, float b) {
    float bp = b * 0.15;
    c = (c - bp) / max(1.0 - bp, 0.0001);
    return c * (1.0 + w * 0.3);
}

vec3 applyToneRegions(vec3 c, float hi, float sh) {
    float l = luma(c);
    float hiMask = smoothstep(0.5, 1.0, l);
    float shMask = 1.0 - smoothstep(0.0, 0.5, l);
    return c * pow(2.0, hi * 0.8 * hiMask) * pow(2.0, sh * 0.8 * shMask);
}

vec3 applyContrast(vec3 c, float k) {
    const float pivot = 0.18;
    return (c - pivot) * (1.0 + k) + pivot;
}

vec3 applySaturation(vec3 c, float s) {
    return mix(vec3(luma(c)), c, 1.0 + s);
}

vec3 applyVibrance(vec3 c, float v) {
    float maxC = max(max(c.r, c.g), c.b);
    float minC = min(min(c.r, c.g), c.b);
    float chroma = maxC - minC;
    float skin = clamp((c.r - max(c.g, c.b)) * 2.0, 0.0, 1.0);
    float amount = v * (1.0 - chroma) * (1.0 - skin * 0.5);
    return mix(vec3(luma(c)), c, 1.0 + amount);
}

void main() {
    vec2 uv = FlutterFragCoord().xy / uSize;
    vec3 src = texture(uImage, uv).rgb;

    vec3 c = srgbToLinear(src);
    c = applyWB(c, uTempScale, uTint);
    c = applyExposure(c, uExposure);
    c = applyWhitesBlacks(c, uWhites, uBlacks);
    c = applyToneRegions(c, uHighlights, uShadows);
    c = applyContrast(c, uContrast);

    vec3 disp = linearToSrgb(c);
    disp = applySaturation(disp, uSaturation);
    disp = applyVibrance(disp, uVibrance);

    fragColor = vec4(clamp(disp, 0.0, 1.0), 1.0);
}