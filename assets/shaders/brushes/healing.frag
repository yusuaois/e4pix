#include <flutter/runtime_effect.glsl>

precision highp float;

uniform sampler2D uImage;
uniform sampler2D uMarkData; // MAX_MARKS*3 x 1 RGBA8, width from Dart via uMarkDataWidth
uniform vec2 uSize;
uniform float uMarkCount;
uniform float uMarkDataWidth;

// Mark data texture layout (MAX_MARKS*3 x 1 RGBA8):
//   Each mark = 6 floats packed into 3 texels (2 floats per texel via 16-bit encoding)
//   mark i: texel i*3 = (srcX, srcY), texel i*3+1 = (tgtX, tgtY), texel i*3+2 = (radius, hardness)
//   16-bit decode: float = (R*65280 + G*255) / 65535 for RG pair, (B*65280 + A*255) / 65535 for BA pair
//   Texture width passed as uniform from Dart — no manual sync when _kMaxMarks changes
#define MAX_MARKS 128

// Decode a 16-bit value stored across two 8-bit channels
// raw: normalized [0,1] from texture sampler
// Maps [0,1] → [-1.0, 2.0] to match _packFloat16 extended range
float unpack16(vec2 raw) {
    return (raw.x * 65280.0 + raw.y * 255.0) / 65535.0 * 3.0 - 1.0;
}

// Read mark 'idx' from uMarkData texture, writing results to out parameters
void readMark(int idx, out vec2 src, out vec2 tgt, out float r, out float h) {
    float base = float(idx) * 3.0;
    float invW = 1.0 / uMarkDataWidth;
    float y = 0.5; // single-row texture

    vec4 t0 = texture(uMarkData, vec2((base + 0.5) * invW, y));
    src = vec2(unpack16(t0.rg), unpack16(t0.ba));

    vec4 t1 = texture(uMarkData, vec2((base + 1.5) * invW, y));
    tgt = vec2(unpack16(t1.rg), unpack16(t1.ba));

    vec4 t2 = texture(uMarkData, vec2((base + 2.5) * invW, y));
    r = unpack16(t2.rg);
    h = unpack16(t2.ba);
}

out vec4 fragColor;

// Boundary-matched healing (PS-style).
//
// Samples clean background colour from the brush boundary (outside the
// defect at the target centre, and the equivalent at the source centre),
// then clones source pixels with a global illumination correction.
//
// Algorithm:
//   srcBg = average of 12 samples around source centre at radius r
//   tgtBg = average of 12 samples around target centre at radius r
//   colourShift = tgtBg - srcBg       (illumination compensation)
//   corrected = srcPixel + colourShift (clone + colour-match target)
//   output = mix(original, corrected, hardness blend)
//
// Centre pixel output ≈ clone → WYSIWYG with overlay preview.

// Average of 12 equiangular samples on the circle boundary at radius r
// around centre. Clamps OOB samples to the image edge (safe default).
vec4 sampleBoundary(vec2 centre, float r, vec2 imgSize) {
    float aspect = imgSize.x / imgSize.y;
    float rx = r;
    float ry = r * aspect;

    vec4 sum = vec4(0.0);

    // 0°     1.0000  0.0000
    vec2 sp = clamp(centre + vec2( rx,  0.0), 0.0, 1.0); sum += texture(uImage, sp);
    // 30°    0.8660  0.5000
    sp = clamp(centre + vec2( 0.8660254 * rx,  0.5 * ry), 0.0, 1.0); sum += texture(uImage, sp);
    // 60°    0.5000  0.8660
    sp = clamp(centre + vec2( 0.5 * rx,  0.8660254 * ry), 0.0, 1.0); sum += texture(uImage, sp);
    // 90°    0.0000  1.0000
    sp = clamp(centre + vec2( 0.0,  ry), 0.0, 1.0); sum += texture(uImage, sp);
    // 120°  -0.5000  0.8660
    sp = clamp(centre + vec2(-0.5 * rx,  0.8660254 * ry), 0.0, 1.0); sum += texture(uImage, sp);
    // 150°  -0.8660  0.5000
    sp = clamp(centre + vec2(-0.8660254 * rx,  0.5 * ry), 0.0, 1.0); sum += texture(uImage, sp);
    // 180°  -1.0000  0.0000
    sp = clamp(centre + vec2(-rx,  0.0), 0.0, 1.0); sum += texture(uImage, sp);
    // 210°  -0.8660 -0.5000
    sp = clamp(centre + vec2(-0.8660254 * rx, -0.5 * ry), 0.0, 1.0); sum += texture(uImage, sp);
    // 240°  -0.5000 -0.8660
    sp = clamp(centre + vec2(-0.5 * rx, -0.8660254 * ry), 0.0, 1.0); sum += texture(uImage, sp);
    // 270°   0.0000 -1.0000
    sp = clamp(centre + vec2( 0.0, -ry), 0.0, 1.0); sum += texture(uImage, sp);
    // 300°   0.5000 -0.8660
    sp = clamp(centre + vec2( 0.5 * rx, -0.8660254 * ry), 0.0, 1.0); sum += texture(uImage, sp);
    // 330°   0.8660 -0.5000
    sp = clamp(centre + vec2( 0.8660254 * rx, -0.5 * ry), 0.0, 1.0); sum += texture(uImage, sp);

    return sum / 12.0;
}

vec4 applyHeal(vec4 col, vec2 uv, vec2 src, vec2 tgt, float r, float h, float enabled, vec2 imgSize) {
    if (enabled < 0.5) return col;

    float aspect = imgSize.x / imgSize.y;
    vec2 roughDiff = abs(uv - tgt);
    if (roughDiff.x > r || roughDiff.y > r * aspect) return col;

    vec2 diff = uv - tgt;
    diff.x *= aspect;
    float d = length(diff);
    float r_corrected = r * aspect;

    float inner = r_corrected * h;
    float blend = (h >= 0.999)
        ? (1.0 - step(r_corrected, d))
        : (1.0 - smoothstep(inner, r_corrected, d));
    if (blend < 0.001) return col;

    vec2 sampleUV = uv - tgt + src;
    if (sampleUV.x < -0.001 || sampleUV.x > 1.001 ||
        sampleUV.y < -0.001 || sampleUV.y > 1.001) {
        return col;
    }

    // Sample clean boundary colours (outside defect radius)
    vec4 srcBg = sampleBoundary(src, r, imgSize);
    vec4 tgtBg = sampleBoundary(tgt, r, imgSize);

    // Global illumination correction
    vec3 colourShift = tgtBg.rgb - srcBg.rgb;

    // Clone source pixel + match target illumination
    vec4 srcPixel = texture(uImage, sampleUV);
    vec3 corrected = clamp(srcPixel.rgb + colourShift, 0.0, 1.0);

    return mix(col, vec4(corrected, col.a), blend);
}

void main() {
    vec2 uv = FlutterFragCoord().xy / uSize;
    vec4 color = texture(uImage, uv);

    int count = int(uMarkCount);
    for (int i = 0; i < MAX_MARKS; i++) {
        if (i >= count) break;
        vec2 src, tgt; float r, h;
        readMark(i, src, tgt, r, h);
        color = applyHeal(color, uv, src, tgt, r, h, 1.0, uSize);
    }

    fragColor = color;
}
