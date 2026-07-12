#include <flutter/runtime_effect.glsl>

precision highp float;

uniform sampler2D uImage;
uniform sampler2D uSpotData; // MAX_SPOTS*3 x 1 RGBA8, width from Dart via uSpotDataWidth
uniform vec2 uSize;
uniform float uSpotCount;
uniform float uSpotDataWidth;

// Spot data texture layout (MAX_SPOTS*3 x 1 RGBA8):
//   Each spot = 6 floats packed into 3 texels (2 floats per texel via 16-bit encoding)
//   spot i: texel i*3 = (srcX, srcY), texel i*3+1 = (tgtX, tgtY), texel i*3+2 = (radius, hardness)
//   16-bit decode: float = (R*65280 + G*255) / 65535 for RG pair, (B*65280 + A*255) / 65535 for BA pair
//   Texture width passed as uniform from Dart — no manual sync when _kMaxSpots changes
#define MAX_SPOTS 128

// Decode a 16-bit value stored across two 8-bit channels
// raw: normalized [0,1] from texture sampler
// Maps [0,1] → [-1.0, 2.0] to match _packFloat16 extended range
// (covers brush radius OOB extension up to 1.0 beyond image bounds)
float unpack16(vec2 raw) {
    return (raw.x * 65280.0 + raw.y * 255.0) / 65535.0 * 3.0 - 1.0;
}

// Read spot 'idx' from uSpotData texture, writing results to out parameters
void readSpot(int idx, out vec2 src, out vec2 tgt, out float r, out float h) {
    float base = float(idx) * 3.0;
    float invW = 1.0 / uSpotDataWidth;
    float y = 0.5; // single-row texture

    vec4 t0 = texture(uSpotData, vec2((base + 0.5) * invW, y));
    src = vec2(unpack16(t0.rg), unpack16(t0.ba));

    vec4 t1 = texture(uSpotData, vec2((base + 1.5) * invW, y));
    tgt = vec2(unpack16(t1.rg), unpack16(t1.ba));

    vec4 t2 = texture(uSpotData, vec2((base + 2.5) * invW, y));
    r = unpack16(t2.rg);
    h = unpack16(t2.ba);
}

out vec4 fragColor;

// hardness: 1=hard edge (step), 0=soft edge (smoothstep full radius)
vec4 applySpot(vec4 col, vec2 uv, vec2 src, vec2 tgt, float r, float h, float enabled, vec2 imgSize) {
    // Early exit: spot is disabled (batch slot unused)
    if (enabled < 0.5) return col;
    float aspect = imgSize.x / imgSize.y;
    // Coarse AABB rejection before expensive length() and texture()
    vec2 roughDiff = abs(uv - tgt);
    if (roughDiff.x > r || roughDiff.y > r * aspect) return col;
    vec2 diff = uv - tgt;
    diff.x *= aspect;
    float d = length(diff);
    float r_corrected = r * aspect;
    // inner: higher hardness = inner closer to r = harder edge
    float inner = r_corrected * h;
    // h >= 0.999: inner == r_corrected, smoothstep(edge, edge, x) is undefined behavior
    // Use step to avoid GPU-dependent rendering artifacts
    float blend = (h >= 0.999)
        ? (1.0 - step(r_corrected, d))
        : (1.0 - smoothstep(inner, r_corrected, d));
    // Pixels fully outside the brush radius: skip texture fetch
    if (blend < 0.001) return col;
    vec2 sampleUV = uv - tgt + src;
    // Sample source entirely outside image -> skip pixel, keep original color (no edge stretching)
    if (sampleUV.x < -0.001 || sampleUV.x > 1.001 || sampleUV.y < -0.001 || sampleUV.y > 1.001) {
        return col;
    }
    return mix(col, texture(uImage, sampleUV), blend);
}

void main() {
    vec2 uv = FlutterFragCoord().xy / uSize;
    vec4 color = texture(uImage, uv);

    int count = int(uSpotCount);
    for (int i = 0; i < MAX_SPOTS; i++) {
        if (i >= count) break;
        vec2 src, tgt; float r, h;
        readSpot(i, src, tgt, r, h);
        color = applySpot(color, uv, src, tgt, r, h, 1.0, uSize);
    }

    fragColor = color;
}
