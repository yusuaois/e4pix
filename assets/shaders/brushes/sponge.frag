// Sponge shader — saturate/desaturate brush.
//
// uImage:    source image (develop+mask output)
// uMask:     feathered brush mask (1.0 = full effect, 0.0 = no effect)
// uSize:     output dimensions
// uMode:     0.0 = saturate, 1.0 = desaturate
// uFlow:     0..1 strength multiplier
//
// Algorithm:
//   1. Convert RGB to HSL
//   2. Adjust saturation by uFlow * mask (positive for saturate, negative for desaturate)
//   3. Convert back to RGB
//
// Edge blending via brush mask feathering ensures smooth strokes.

#include <flutter/runtime_effect.glsl>

precision highp float;

uniform sampler2D uImage;
uniform sampler2D uMask;
uniform vec2 uSize;
uniform float uMode;
uniform float uFlow;

out vec4 fragColor;

// RGB → HSL: returns vec3(h, s, l)
// h in [0..1], s in [0..1], l in [0..1]
vec3 rgb2hsl(vec3 c) {
    float maxC = max(max(c.r, c.g), c.b);
    float minC = min(min(c.r, c.g), c.b);
    float l = (maxC + minC) * 0.5;

    if (maxC - minC < 0.0001) return vec3(0.0, 0.0, l);

    float d = maxC - minC;
    float s = l > 0.5 ? d / (2.0 - maxC - minC) : d / (maxC + minC);

    float h;
    if (maxC == c.r) {
        h = (c.g - c.b) / d + (c.g < c.b ? 6.0 : 0.0);
    } else if (maxC == c.g) {
        h = (c.b - c.r) / d + 2.0;
    } else {
        h = (c.r - c.g) / d + 4.0;
    }
    h /= 6.0;

    return vec3(h, s, l);
}

// HSL → RGB helper: hue to RGB component
float hue2rgb(float p, float q, float t) {
    if (t < 0.0) t += 1.0;
    if (t > 1.0) t -= 1.0;
    if (t < 1.0/6.0) return p + (q - p) * 6.0 * t;
    if (t < 1.0/2.0) return q;
    if (t < 2.0/3.0) return p + (q - p) * (2.0/3.0 - t) * 6.0;
    return p;
}

vec3 hsl2rgb(vec3 hsl) {
    float h = hsl.x, s = hsl.y, l = hsl.z;
    if (s < 0.0001) return vec3(l);

    float q = l < 0.5 ? l * (1.0 + s) : l + s - l * s;
    float p = 2.0 * l - q;

    return vec3(hue2rgb(p, q, h + 1.0/3.0),
                hue2rgb(p, q, h),
                hue2rgb(p, q, h - 1.0/3.0));
}

void main() {
    vec2 uv = FlutterFragCoord().xy / uSize;
    vec4 src = texture(uImage, uv);
    float mask = texture(uMask, uv).r;

    // Outside brush — pass through unchanged
    if (mask < 0.005) {
        fragColor = src;
        return;
    }

    vec3 hsl = rgb2hsl(src.rgb);

    // Adjust saturation: +flow for saturate, -flow for desaturate
    float satDelta = uFlow * mask;
    if (uMode > 0.5) satDelta = -satDelta;

    hsl.y = clamp(hsl.y + satDelta, 0.0, 1.0);

    vec3 result = hsl2rgb(hsl);

    fragColor = vec4(clamp(result, 0.0, 1.0), src.a);
}
