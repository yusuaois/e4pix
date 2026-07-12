// Spot Heal shader — mask-based fill from boundary.
//
// uImage:  source image (develop+mask output)
// uMask:   binary mask (1.0 = inside region to fill, 0.0 = outside)
// uSize:   output dimensions
// uHardness: edge feather radius in pixels (from Dart side)
//
// For each pixel inside the mask, 16 rays are cast outward.
// The first pixel outside the mask (mask < 0.1) along each ray
// is sampled from uImage. All boundary samples are blended by
// inverse-distance-weighting (1/d²).

#include <flutter/runtime_effect.glsl>

precision highp float;

uniform sampler2D uImage;
uniform sampler2D uMask;
uniform vec2 uSize;
uniform float uHardness;   // 0..1 edge softness (0 = hard fill, 1 = fully feathered)

out vec4 fragColor;

const float PI = 3.14159265359;
const int N_RAYS = 16;       // number of search directions

void main() {
    vec2 uv = FlutterFragCoord().xy / uSize;
    vec4 src = texture(uImage, uv);
    float mask = texture(uMask, uv).r;

    // Outside mask — pass through unchanged
    if (mask < 0.1) {
        fragColor = src;
        return;
    }

    vec2 pxSize = 1.0 / uSize;

    // Feather: sample mask in a small neighbourhood.
    // A pixel near the mask edge has some neighbours with mask < 0.1.
    // blendFactor = fraction of neighbours outside mask = how much to blend.
    float outsideCount = 0.0;
    for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
            vec2 nUV = uv + vec2(float(dx), float(dy)) * pxSize;
            nUV = clamp(nUV, vec2(0.0), vec2(1.0));
            if (texture(uMask, nUV).r < 0.1) outsideCount += 1.0;
        }
    }
    float distToEdge = outsideCount / 9.0; // 0 = fully inside, 1 = at edge

    // Hardness: at uHardness=0 the fill is full everywhere;
    // at uHardness=1 the fill blends to source near the mask edge.
    float blendFactor = 1.0;
    if (uHardness > 0.001 && distToEdge > 0.001) {
        blendFactor = 1.0 - smoothstep(0.0, 1.0, distToEdge * (2.0 - uHardness * 1.5));
    }

    // Cast rays outward from this pixel to find boundary samples
    vec3 accumulated = vec3(0.0);
    float totalWeight = 0.0;

    for (int r = 0; r < N_RAYS; r++) {
        float angle = float(r) * (2.0 * PI / float(N_RAYS));
        vec2 dir = vec2(cos(angle), sin(angle));

        // Step outward until we find a pixel outside the mask
        float found = 0.0;
        float dist = 0.0;
        vec2 sampleUV = uv;

        for (int s = 1; s < 150; s++) {
            if (found > 0.5) break;
            sampleUV = uv + dir * float(s) * pxSize;
            sampleUV = clamp(sampleUV, vec2(0.001), vec2(0.999));
            if (texture(uMask, sampleUV).r < 0.1) {
                found = 1.0;
                dist = float(s);
            }
        }

        if (found > 0.5 && dist > 0.5) {
            vec3 bCol = texture(uImage, sampleUV).rgb;
            float dist2 = dist * dist;
            float w = 1.0 / max(dist2, 1.0); // 1/d² weight
            accumulated += bCol * w;
            totalWeight += w;
        }
    }

    if (totalWeight > 0.0) {
        vec3 fillCol = accumulated / totalWeight;
        fragColor = vec4(mix(src.rgb, fillCol, blendFactor), src.a);
    } else {
        fragColor = src;
    }
}
