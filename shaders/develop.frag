#include <flutter/runtime_effect.glsl>

precision highp float;

// ---- 基础调整 (0-11) ----
uniform vec2  uSize;
uniform float uExposure;
uniform float uTempScale;
uniform float uTint;
uniform float uContrast;
uniform float uHighlights;
uniform float uShadows;
uniform float uWhites;
uniform float uBlacks;
uniform float uSaturation;
uniform float uVibrance;

// ---- HSL 8 段 (12-35) ----
// 顺序：红(R) 橙(O) 黄(Y) 绿(G) 青(C) 蓝(B) 紫(P) 品红(M)
uniform vec4  uHueROYG;     // 12-15
uniform vec4  uHueCBPM;     // 16-19
uniform vec4  uSatROYG;     // 20-23
uniform vec4  uSatCBPM;     // 24-27
uniform vec4  uLumROYG;     // 28-31
uniform vec4  uLumCBPM;     // 32-35

// ---- LUT A (36-38) ----
uniform float uLutIntensity;     // 36
uniform float uLutSize;          // 37
uniform float uHasLut;           // 38
// ---- LUT B (39-41) ----
uniform float uLutIntensityB;    // 39
uniform float uLutSizeB;         // 40
uniform float uHasLutB;          // 41

// ---- 曲线 (42) ----
uniform float uHasCurve;         // 42  >0.5 启用

uniform sampler2D uImage;        // sampler 0
uniform sampler2D uLut;          // sampler 1  (A)
uniform sampler2D uLutB;         // sampler 2  (B)
uniform sampler2D uCurve;        // sampler 3

out vec4 fragColor;

// ============================================================================
// 色彩空间
// ============================================================================
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

// ============================================================================
// HSL 转换
// ============================================================================
vec3 rgb2hsl(vec3 c) {
    float maxC = max(max(c.r, c.g), c.b);
    float minC = min(min(c.r, c.g), c.b);
    float d = maxC - minC;
    float l = (maxC + minC) * 0.5;
    float h = 0.0, s = 0.0;
    if (d > 1e-5) {
        s = (l < 0.5) ? d / (maxC + minC) : d / max(2.0 - maxC - minC, 1e-5);
        if (maxC == c.r)      h = (c.g - c.b) / d + (c.g < c.b ? 6.0 : 0.0);
        else if (maxC == c.g) h = (c.b - c.r) / d + 2.0;
        else                  h = (c.r - c.g) / d + 4.0;
        h /= 6.0;
    }
    return vec3(h, s, l);
}

float h2c(float p, float q, float t) {
    if (t < 0.0) t += 1.0;
    if (t > 1.0) t -= 1.0;
    if (t < 1.0/6.0) return p + (q - p) * 6.0 * t;
    if (t < 0.5)     return q;
    if (t < 2.0/3.0) return p + (q - p) * (2.0/3.0 - t) * 6.0;
    return p;
}

vec3 hsl2rgb(vec3 hsl) {
    if (hsl.y < 1e-5) return vec3(hsl.z);
    float q = hsl.z < 0.5 ? hsl.z * (1.0 + hsl.y) : hsl.z + hsl.y - hsl.z * hsl.y;
    float p = 2.0 * hsl.z - q;
    return vec3(h2c(p, q, hsl.x + 1.0/3.0),
                h2c(p, q, hsl.x),
                h2c(p, q, hsl.x - 1.0/3.0));
}

// 环形 hue 距离
float hueDist(float h, float c) {
    float d = abs(h - c);
    return min(d, 1.0 - d);
}

// 单段权重：在该色相中心附近平滑权重，灰色不响应
float bandWeight(float h, float s, float center) {
    const float RADIUS = 0.083; // ~30°
    float distW = 1.0 - smoothstep(0.0, RADIUS * 1.5, hueDist(h, center));
    float satW  = smoothstep(0.05, 0.3, s);
    return distW * satW;
}

// ============================================================================
// HSL 8 段应用
// ============================================================================
vec3 applyHsl8(vec3 rgb) {
    vec3 hsl = rgb2hsl(rgb);

    // 8 个色相中心
    float wR = bandWeight(hsl.x, hsl.y, 0.0);
    float wO = bandWeight(hsl.x, hsl.y, 0.0833);
    float wY = bandWeight(hsl.x, hsl.y, 0.1667);
    float wG = bandWeight(hsl.x, hsl.y, 0.3333);
    float wC = bandWeight(hsl.x, hsl.y, 0.5);
    float wB = bandWeight(hsl.x, hsl.y, 0.6667);
    float wP = bandWeight(hsl.x, hsl.y, 0.75);
    float wM = bandWeight(hsl.x, hsl.y, 0.9167);

    float hAdj = uHueROYG.x*wR + uHueROYG.y*wO + uHueROYG.z*wY + uHueROYG.w*wG
               + uHueCBPM.x*wC + uHueCBPM.y*wB + uHueCBPM.z*wP + uHueCBPM.w*wM;
    float sAdj = uSatROYG.x*wR + uSatROYG.y*wO + uSatROYG.z*wY + uSatROYG.w*wG
               + uSatCBPM.x*wC + uSatCBPM.y*wB + uSatCBPM.z*wP + uSatCBPM.w*wM;
    float lAdj = uLumROYG.x*wR + uLumROYG.y*wO + uLumROYG.z*wY + uLumROYG.w*wG
               + uLumCBPM.x*wC + uLumCBPM.y*wB + uLumCBPM.z*wP + uLumCBPM.w*wM;

    hsl.x = mod(hsl.x + hAdj * 0.083, 1.0);     // 最大 ±30°
    hsl.y = clamp(hsl.y * (1.0 + sAdj), 0.0, 1.0);
    hsl.z = clamp(hsl.z + lAdj * 0.3, 0.0, 1.0); // 最大 ±0.3 亮度

    return hsl2rgb(hsl);
}

// ============================================================================
// 基础调整算子
// ============================================================================
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
    return (c - 0.18) * (1.0 + k) + 0.18;
}
vec3 applySaturation(vec3 c, float s) { return mix(vec3(luma(c)), c, 1.0 + s); }
vec3 applyVibrance(vec3 c, float v) {
    float maxC = max(max(c.r, c.g), c.b);
    float minC = min(min(c.r, c.g), c.b);
    float chroma = maxC - minC;
    float skin = clamp((c.r - max(c.g, c.b)) * 2.0, 0.0, 1.0);
    float amount = v * (1.0 - chroma) * (1.0 - skin * 0.5);
    return mix(vec3(luma(c)), c, 1.0 + amount);
}

// ============================================================================
// 3D LUT (HALD-strip 布局：N×N tile 横向排列，宽 N², 高 N)
// 用 NEAREST 行为（手工对齐到 texel 中心）+ 手动 trilinear 插值
// ============================================================================
vec3 sampleLutCell(float r, float g, float b, float N) {
    vec2 cellPos = vec2(b * N + r, g);
    vec2 texSize = vec2(N * N, N);
    return texture(uLut, (cellPos + 0.5) / texSize).rgb;
}

vec3 sampleLut3D(vec3 c, float N) {
    c = clamp(c, 0.0, 1.0);
    vec3 idx = c * (N - 1.0);
    vec3 i0 = floor(idx);
    vec3 i1 = min(i0 + 1.0, vec3(N - 1.0));
    vec3 f  = idx - i0;

    vec3 c000 = sampleLutCell(i0.r, i0.g, i0.b, N);
    vec3 c100 = sampleLutCell(i1.r, i0.g, i0.b, N);
    vec3 c010 = sampleLutCell(i0.r, i1.g, i0.b, N);
    vec3 c110 = sampleLutCell(i1.r, i1.g, i0.b, N);
    vec3 c001 = sampleLutCell(i0.r, i0.g, i1.b, N);
    vec3 c101 = sampleLutCell(i1.r, i0.g, i1.b, N);
    vec3 c011 = sampleLutCell(i0.r, i1.g, i1.b, N);
    vec3 c111 = sampleLutCell(i1.r, i1.g, i1.b, N);

    vec3 c00 = mix(c000, c100, f.r);
    vec3 c10 = mix(c010, c110, f.r);
    vec3 c01 = mix(c001, c101, f.r);
    vec3 c11 = mix(c011, c111, f.r);
    vec3 c0  = mix(c00, c10, f.g);
    vec3 c1  = mix(c01, c11, f.g);
    return mix(c0, c1, f.b);
}

vec3 sampleLutCellB(float r, float g, float b, float N) {
    vec2 cellPos = vec2(b * N + r, g);
    vec2 texSize = vec2(N * N, N);
    return texture(uLutB, (cellPos + 0.5) / texSize).rgb;
}

vec3 sampleLut3DB(vec3 c, float N) {
    c = clamp(c, 0.0, 1.0);
    vec3 idx = c * (N - 1.0);
    vec3 i0 = floor(idx);
    vec3 i1 = min(i0 + 1.0, vec3(N - 1.0));
    vec3 f  = idx - i0;
    vec3 c000 = sampleLutCellB(i0.r, i0.g, i0.b, N);
    vec3 c100 = sampleLutCellB(i1.r, i0.g, i0.b, N);
    vec3 c010 = sampleLutCellB(i0.r, i1.g, i0.b, N);
    vec3 c110 = sampleLutCellB(i1.r, i1.g, i0.b, N);
    vec3 c001 = sampleLutCellB(i0.r, i0.g, i1.b, N);
    vec3 c101 = sampleLutCellB(i1.r, i0.g, i1.b, N);
    vec3 c011 = sampleLutCellB(i0.r, i1.g, i1.b, N);
    vec3 c111 = sampleLutCellB(i1.r, i1.g, i1.b, N);
    vec3 c00 = mix(c000, c100, f.r);
    vec3 c10 = mix(c010, c110, f.r);
    vec3 c01 = mix(c001, c101, f.r);
    vec3 c11 = mix(c011, c111, f.r);
    vec3 c0  = mix(c00, c10, f.g);
    vec3 c1  = mix(c01, c11, f.g);
    return mix(c0, c1, f.b);
}

// 一维曲线 LUT，输入亮度 v∈[0,1] → 输出
float sampleCurve1D(float v) {
    return texture(uCurve, vec2(clamp(v, 0.0, 1.0), 0.5)).r;
}
vec3 applyCurve(vec3 c) {
    // RGB 主曲线
    return vec3(sampleCurve1D(c.r), sampleCurve1D(c.g), sampleCurve1D(c.b));
}

// ============================================================================
// Main
// ============================================================================
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
    if (uHasCurve > 0.5) {
        disp = applyCurve(disp);
    }
    disp = applyHsl8(disp);
    disp = applySaturation(disp, uSaturation);
    disp = applyVibrance(disp, uVibrance);

    // ---- LUT 在 display-referred sRGB 上应用 ----
    if (uHasLut > 0.5 && uLutIntensity > 0.001) {
        vec3 graded = sampleLut3D(disp, uLutSize);
        disp = mix(disp, graded, uLutIntensity);
    }
    if (uHasLutB > 0.5 && uLutIntensityB > 0.001) {
        vec3 gradedB = sampleLut3DB(disp, uLutSizeB);
        disp = mix(disp, gradedB, uLutIntensityB);
    }

    fragColor = vec4(clamp(disp, 0.0, 1.0), 1.0);
}