// Dodge/Burn shader — tonal range targeted lighten/darken.
//
// uImage:    source image (develop+mask output)
// uMask:     feathered brush mask (1.0 = full effect, 0.0 = no effect)
// uSize:     output dimensions
// uMode:     0.0 = dodge (lighten), 1.0 = burn (darken)
// uExposure: 0..1 strength multiplier (maps to PS exposure %)
// uRange:    0.0 = shadows, 0.5 = midtones, 1.0 = highlights
//
// Algorithm matches Photoshop's Dodge/Burn tool:
//   1. Compute pixel luminance
//   2. Build a range mask that limits the effect to the selected tonal range
//   3. Apply Screen (dodge) or Multiply (burn) blend modulated by range mask
//
// Calibration: 0.7 coefficient maps exposure [0..1] to PS-equivalent per-stroke
// intensity. At 50% exposure on neutral gray (lum=0.5) with midtones range:
//   s = 0.5 × 1.0 × 0.7 = 0.35
//   Dodge: 0.5 + 0.5 × 0.35 = 0.675 (+17%, matches PS)
//   Burn:  0.5 × (1 - 0.35) = 0.325 (-17%, matches PS)

#include <flutter/runtime_effect.glsl>

precision highp float;

uniform sampler2D uImage;
uniform sampler2D uMask;
uniform vec2 uSize;
uniform float uMode;
uniform float uExposure;
uniform float uRange;

out vec4 fragColor;

// ITU-R BT.709 luminance coefficients
float luminance(vec3 c) {
    return dot(c, vec3(0.2126, 0.7152, 0.0722));
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

    float lum = luminance(src.rgb);

    // Range mask — limits effect to the selected tonal range.
    // Wide transitions match Photoshop's Shadows / Midtones / Highlights:
    // shadows: peaks at lum=0, fades smoothly to 0 at lum=0.75
    // midtones: smooth bell curve, peak at lum=0.5
    // highlights: peaks at lum=1, fades smoothly to 0 at lum=0.25
    float rangeMask;
    if (uRange < 0.25) {
        rangeMask = 1.0 - smoothstep(0.0, 0.75, lum);
    } else if (uRange > 0.75) {
        rangeMask = smoothstep(0.25, 1.0, lum);
    } else {
        // Smooth bell curve — more natural than linear triangle wave
        float rise = smoothstep(0.0, 0.5, lum);
        float fall = 1.0 - smoothstep(0.5, 1.0, lum);
        rangeMask = rise * fall;
    }

    // Combined strength: brush mask × exposure × tonal range targeting × PS calibration
    // Clamp to 0.95 — Screen/Multiply are safe at s=1, but limiting max per-stroke
    // intensity prevents one-click-to-pure-white/black
    float s = clamp(mask * uExposure * rangeMask * 0.7, 0.0, 0.95);

    if (s < 0.002) {
        fragColor = src;
        return;
    }

    vec3 result;
    if (uMode < 0.5) {
        // Dodge: Screen blend — lightens toward white
        // result = src + (1 - src) × s
        // Safe at all s values; linear interpolation, no division
        result = src.rgb + (1.0 - src.rgb) * s;
    } else {
        // Burn: Multiply blend — darkens toward black
        // result = src × (1 - s)
        // Safe at all s values; linear darkening, no division
        result = src.rgb * (1.0 - s);
    }

    // Explicit clamp guards against floating-point precision issues
    fragColor = vec4(clamp(result, 0.0, 1.0), src.a);
}
