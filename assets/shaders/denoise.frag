#include <flutter/runtime_effect.glsl>
precision highp float;

uniform vec2  uSize;
uniform float uLuma;
uniform float uColor;

uniform sampler2D uImage;

out vec4 fragColor;

vec3 rgb2ycbcr(vec3 c) {
    float y  = dot(c, vec3(0.2126, 0.7152, 0.0722));
    float cb = (c.b - y) * 0.5389 + 0.5;
    float cr = (c.r - y) * 0.6350 + 0.5;
    return vec3(y, cb, cr);
}
vec3 ycbcr2rgb(vec3 ycc) {
    float y = ycc.x;
    float cb = ycc.y - 0.5;
    float cr = ycc.z - 0.5;
    float r = y + cr * 1.5748;
    float b = y + cb * 1.8556;
    float g = (y - 0.2126 * r - 0.0722 * b) / 0.7152;
    return vec3(r, g, b);
}

void main() {
    vec2 texel = 1.0 / uSize;
    vec2 uv = FlutterFragCoord().xy / uSize;

    vec3 centerRgb = texture(uImage, uv).rgb;
    vec3 centerYcc = rgb2ycbcr(centerRgb);

    if (uLuma < 0.001 && uColor < 0.001) {
        fragColor = vec4(centerRgb, 1.0);
        return;
    }

    // 明度降噪 5x5
    float outY = centerYcc.x;
    if (uLuma > 0.001) {
        float sigmaY = mix(0.004, 0.08, uLuma);
        const float spatialSigma2 = 4.0;
        float accY = 0.0;
        float sumWY = 0.0;
        const int R = 2; // 5x5
        for (int dy = -R; dy <= R; dy++) {
            for (int dx = -R; dx <= R; dx++) {
                vec2 off = vec2(float(dx), float(dy));
                vec3 sYcc = rgb2ycbcr(texture(uImage, uv + off * texel).rgb);
                float spatial = exp(-dot(off, off) / (2.0 * spatialSigma2));
                float dY = sYcc.x - centerYcc.x;
                float rangeY = exp(-(dY * dY) / (2.0 * sigmaY * sigmaY));
                float w = spatial * rangeY;
                accY += sYcc.x * w;
                sumWY += w;
            }
        }
        if (sumWY > 0.0) outY = mix(centerYcc.x, accY / sumWY, uLuma);
    }

    // 颜色降噪
    vec2 outC = centerYcc.yz;
    if (uColor > 0.001) {
        float sigmaC = mix(0.015, 0.30, uColor);
        // 半径随强度增大 强度满时 ±12 像素
        float radius = mix(4.0, 12.0, uColor);
        float spatialSigma2 = radius * radius * 0.35;
        vec2 accC = vec2(0.0);
        float sumWC = 0.0;
        // 步长随半径增大 7x7 个采样点
        const int STEPS = 3; // -3..3 = 7 个点每轴
        float step = radius / float(STEPS);
        for (int dy = -STEPS; dy <= STEPS; dy++) {
            for (int dx = -STEPS; dx <= STEPS; dx++) {
                vec2 off = vec2(float(dx), float(dy)) * step;
                vec3 sYcc = rgb2ycbcr(texture(uImage, uv + off * texel).rgb);
                float spatial = exp(-dot(off, off) / (2.0 * spatialSigma2));
                vec2 dC = sYcc.yz - centerYcc.yz;
                float rangeC = exp(-dot(dC, dC) / (2.0 * sigmaC * sigmaC));
                float w = spatial * rangeC;
                accC += sYcc.yz * w;
                sumWC += w;
            }
        }
        if (sumWC > 0.0) outC = mix(centerYcc.yz, accC / sumWC, uColor);
    }

    vec3 outRgb = ycbcr2rgb(vec3(outY, outC));
    fragColor = vec4(clamp(outRgb, 0.0, 1.0), 1.0);
}