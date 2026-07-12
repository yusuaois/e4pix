#version 460 core
#include <flutter/runtime_effect.glsl>

uniform sampler2D uInput;
uniform sampler2D uMaskTexture;
uniform vec2 uResolution;

uniform float uMaskType;          // 0=linear, 1=radial
uniform float uMaskStartX;
uniform float uMaskStartY;
uniform float uMaskEndX;
uniform float uMaskEndY;
uniform float uMaskCenterX;
uniform float uMaskCenterY;
uniform float uMaskRadiusX;
uniform float uMaskRadiusY;
uniform float uMaskRotation;
uniform float uMaskFeather;
uniform float uMaskInverted;

uniform float uExposure;
uniform float uContrast;
uniform float uHighlights;
uniform float uShadows;
uniform float uWhites;
uniform float uBlacks;
uniform float uTemperatureShift;
uniform float uTint;
uniform float uSaturation;
uniform float uVibrance;

out vec4 fragColor;

vec3 srgbToLinear(vec3 c) {
    return mix(c / 12.92,
               pow(max((c + 0.055) / 1.055, vec3(0.0)), vec3(2.4)),
               step(0.04045, c));
}

vec3 linearToSrgb(vec3 c) {
    return mix(c * 12.92,
               1.055 * pow(max(c, vec3(0.0)), vec3(1.0/2.4)) - 0.055,
               step(0.0031308, c));
}

float maskAlphaLinear(vec2 uv) {
    vec2 start = vec2(uMaskStartX, uMaskStartY);
    vec2 end = vec2(uMaskEndX, uMaskEndY);
    vec2 dir = end - start;
    float lenSq = dot(dir, dir);
    if (lenSq < 1e-6) return 0.0;
    float t = dot(uv - start, dir) / lenSq;
    return smoothstep(0.0, 1.0, t);
}

float maskAlphaRadial(vec2 uv) {
    vec2 center = vec2(uMaskCenterX, uMaskCenterY);
    vec2 local = uv - center;
    float cs = cos(-uMaskRotation);
    float sn = sin(-uMaskRotation);
    local = vec2(cs*local.x - sn*local.y, sn*local.x + cs*local.y);
    float rx = max(uMaskRadiusX, 1e-4);
    float ry = max(uMaskRadiusY, 1e-4);
    float d = (local.x*local.x)/(rx*rx) + (local.y*local.y)/(ry*ry);
    float inside = 1.0 - smoothstep(1.0 - uMaskFeather, 1.0, d);
    return mix(inside, 1.0 - inside, uMaskInverted);
}

vec3 applyLocalParams(vec3 lin) {
    // exposure
    lin *= pow(2.0, uExposure);

    // temperature & tint (linear approx)
    float tx = uTemperatureShift * 0.0001;
    lin.r *= 1.0 + tx;
    lin.b *= 1.0 - tx;
    lin.g *= 1.0 + uTint * 0.005;

    // tone (highlights/shadows/whites/blacks)
    float lum = dot(lin, vec3(0.2126, 0.7152, 0.0722));
    float hi = smoothstep(0.5, 1.0, lum) * (uHighlights / 100.0);
    float sh = (1.0 - smoothstep(0.0, 0.5, lum)) * (uShadows / 100.0);
    float wh = smoothstep(0.85, 1.0, lum) * (uWhites / 100.0);
    float bl = (1.0 - smoothstep(0.0, 0.15, lum)) * (uBlacks / 100.0);
    lin *= 1.0 + (hi + sh + wh + bl) * 0.4;

    // contrast (around mid)
    lin = (lin - 0.5) * (1.0 + uContrast / 100.0) + 0.5;

    // saturation
    float lum2 = dot(lin, vec3(0.2126, 0.7152, 0.0722));
    vec3 gray = vec3(lum2);
    lin = mix(gray, lin, 1.0 + uSaturation / 100.0);

    // vibrance (effect reduced on already-saturated colors)
    float maxC = max(lin.r, max(lin.g, lin.b));
    float minC = min(lin.r, min(lin.g, lin.b));
    float satNow = (maxC - minC) / (maxC + 1e-4);
    float vibAmt = (1.0 - satNow) * (uVibrance / 100.0);
    lin = mix(gray, lin, 1.0 + vibAmt);

    return lin;
}

void main() {
    vec2 uv = FlutterFragCoord().xy / uResolution;
    vec3 srcColor = texture(uInput, uv).rgb;

    float alpha;
    if (uMaskType < 0.5) {
        alpha = maskAlphaLinear(uv);
    } else if (uMaskType < 1.5) {
        alpha = maskAlphaRadial(uv);
    } else {
        alpha = clamp(texture(uMaskTexture, uv).r, 0.0, 1.0);
    }

    vec3 lin = srgbToLinear(srcColor);
    vec3 adjusted = applyLocalParams(lin);
    vec3 adjustedSrgb = linearToSrgb(clamp(adjusted, 0.0, 1.0));

    vec3 finalRgb = mix(srcColor, adjustedSrgb, alpha);
    fragColor = vec4(finalRgb, 1.0);
}