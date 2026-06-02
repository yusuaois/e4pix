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

// 单段权重 高斯型衰减
float bandWeight(float h, float s, float center) {
    float dist = hueDist(h, center);
    float sigma = 0.09;
    float distW = exp(-(dist * dist) / (2.0 * sigma * sigma));
    float satW  = smoothstep(0.02, 0.20, s);
    return distW * satW;
}

// ============================================================================
// HSL 8 段应用
// ============================================================================
// 红 橙 黄 绿 青 蓝 紫 品红
const float HC0 = 0.0;     // R   0°
const float HC1 = 0.0833;  // O   30°
const float HC2 = 0.1667;  // Y   60°
const float HC3 = 0.3333;  // G   120°
const float HC4 = 0.5;     // C   180°
const float HC5 = 0.6667;  // B   240°
const float HC6 = 0.792;    // P   285°
const float HC7 = 0.903;  // M   325°

// 按索引(0..7)从两个 vec4 取分量:0-3=ROYG, 4-7=CBPM
float pickBand(vec4 a, vec4 b, int i) {
    if (i == 0) return a.x;
    if (i == 1) return a.y;
    if (i == 2) return a.z;
    if (i == 3) return a.w;
    if (i == 4) return b.x;
    if (i == 5) return b.y;
    if (i == 6) return b.z;
    return b.w;
}

vec3 applyHsl8(vec3 rgb) {
    vec3 hsl = rgb2hsl(rgb);
    float h = hsl.x;

    int iA; int iB; float t;
    if      (h < HC1) { iA = 0; iB = 1; t = (h - HC0) / (HC1 - HC0); }
    else if (h < HC2) { iA = 1; iB = 2; t = (h - HC1) / (HC2 - HC1); }
    else if (h < HC3) { iA = 2; iB = 3; t = (h - HC2) / (HC3 - HC2); }
    else if (h < HC4) { iA = 3; iB = 4; t = (h - HC3) / (HC4 - HC3); }
    else if (h < HC5) { iA = 4; iB = 5; t = (h - HC4) / (HC5 - HC4); }
    else if (h < HC6) { iA = 5; iB = 6; t = (h - HC5) / (HC6 - HC5); }
    else if (h < HC7) { iA = 6; iB = 7; t = (h - HC6) / (HC7 - HC6); }
    else              { iA = 7; iB = 0; t = (h - HC7) / (1.0  - HC7); }

    // 相邻两段权重 (1-t)、t
    float hAdj = mix(pickBand(uHueROYG, uHueCBPM, iA),
                    pickBand(uHueROYG, uHueCBPM, iB), t);
    float sAdj = mix(pickBand(uSatROYG, uSatCBPM, iA),
                    pickBand(uSatROYG, uSatCBPM, iB), t);
    float lAdj = mix(pickBand(uLumROYG, uLumCBPM, iA),
                    pickBand(uLumROYG, uLumCBPM, iB), t);

    hsl.x = mod(hsl.x + hAdj * 0.083, 1.0);          // 色相 ±~30°
    hsl.y = clamp(hsl.y * (1.0 + sAdj), 0.0, 1.0);   // 饱和度
    hsl.z = clamp(hsl.z + lAdj * 0.3,  0.0, 1.0);    // 明度

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

// 曲线 LUT，输入亮度 v∈[0,1] → 输出
float sampleCurveRow(float v, float row) {
    return texture(uCurve, vec2(clamp(v, 0.0, 1.0), (row + 0.5) / 5.0)).r;
}
vec3 applyCurve(vec3 c) {
    // 1 R/G/B 各曲线
    float r = sampleCurveRow(c.r, 1.0);
    float g = sampleCurveRow(c.g, 2.0);
    float b = sampleCurveRow(c.b, 3.0);
    // 2 主曲线
    vec3 rgb = vec3(
        sampleCurveRow(r, 0.0),
        sampleCurveRow(g, 0.0),
        sampleCurveRow(b, 0.0)
    );
    // 3 明度曲线
    float y = luma(rgb);
    if (y > 1e-4) {
        float y2 = sampleCurveRow(y, 4.0);
        rgb *= (y2 / y);
    }
    return clamp(rgb, 0.0, 1.0);
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