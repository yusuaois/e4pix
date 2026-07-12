#include <flutter/runtime_effect.glsl>

precision highp float;

// uImage: current develop output (canvas to paint on)
// uHistory: history snapshot (source to sample from)
// uSpotData: mark data texture
uniform sampler2D uImage;
uniform sampler2D uHistory;
uniform sampler2D uSpotData;
uniform vec2 uSize;
uniform float uSpotCount;
uniform float uSpotDataWidth;

// Spot data texture layout (MAX_SPOTS*3 x 1 RGBA8):
//   Each mark = 6 floats packed into 3 texels
//   mark i: texel i*3 = (srcX, srcY), texel i*3+1 = (tgtX, tgtY), texel i*3+2 = (radius, hardness)
//   History Brush: src == tgt (no offset), so srcX/srcY fields are unused
#define MAX_SPOTS 128

// Decode a 16-bit value stored across two 8-bit channels
// Maps [0,1] → [-1.0, 2.0] to match _packFloat16 extended range
float unpack16(vec2 raw) {
    return (raw.x * 65280.0 + raw.y * 255.0) / 65535.0 * 3.0 - 1.0;
}

// Read mark 'idx' from uSpotData texture
void readSpot(int idx, out vec2 tgt, out float r, out float h) {
    float base = float(idx) * 3.0;
    float invW = 1.0 / uSpotDataWidth;
    float y = 0.5;

    // texel i*3: (srcX, srcY) — skip for History Brush
    // texel i*3+1: (tgtX, tgtY)
    vec4 t1 = texture(uSpotData, vec2((base + 1.5) * invW, y));
    tgt = vec2(unpack16(t1.rg), unpack16(t1.ba));

    // texel i*3+2: (radius, hardness)
    vec4 t2 = texture(uSpotData, vec2((base + 2.5) * invW, y));
    r = unpack16(t2.rg);
    h = unpack16(t2.ba);
}

out vec4 fragColor;

// Apply a History Brush mark: sample from uHistory at target position,
// blend onto uImage at the same position with radius/hardness feathering
vec4 applyMark(vec4 col, vec2 uv, vec2 tgt, float r, float h, float enabled, vec2 imgSize) {
    if (enabled < 0.5) return col;

    float aspect = imgSize.x / imgSize.y;

    // Coarse AABB rejection
    vec2 roughDiff = abs(uv - tgt);
    if (roughDiff.x > r || roughDiff.y > r * aspect) return col;

    vec2 diff = uv - tgt;
    diff.x *= aspect;
    float d = length(diff);
    float r_corrected = r * aspect;

    // Hardness feathering: inner closer to r_corrected = harder edge
    float inner = r_corrected * h;
    float blend = (h >= 0.999)
        ? (1.0 - step(r_corrected, d))
        : (1.0 - smoothstep(inner, r_corrected, d));

    if (blend < 0.001) return col;

    // Sample from history snapshot at the SAME position (no offset)
    // History Brush restores pixels from the frozen snapshot
    vec4 historySample = texture(uHistory, uv);
    return mix(col, historySample, blend);
}

void main() {
    vec2 uv = FlutterFragCoord().xy / uSize;
    vec4 color = texture(uImage, uv);

    int count = int(uSpotCount);
    for (int i = 0; i < MAX_SPOTS; i++) {
        if (i >= count) break;
        vec2 tgt; float r, h;
        readSpot(i, tgt, r, h);
        color = applyMark(color, uv, tgt, r, h, 1.0, uSize);
    }

    fragColor = color;
}
