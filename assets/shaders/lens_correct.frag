#include <flutter/runtime_effect.glsl>

precision highp float;

// ── 畸变校正参数（Lensfun poly5 模型）──
uniform float uK1;
uniform float uK2;
uniform float uK3;
uniform float uK4;
uniform float uK5;

// 光心归一化坐标（默认 0.5, 0.5 即图像中心）
uniform vec2  uOpticalCenter;

// 畸变校正开关
uniform float uDistortionEnabled;

// ── TCA ──
uniform float uCARed;
uniform float uCABlue;
uniform float uCAEnabled;

// ── 暗角校正（Lensfun poly3 模型）──
// k1/k2/k3 是自然暗角量（通常为负值），shader 内取倒数补偿
uniform float uVK1;
uniform float uVK2;
uniform float uVK3;
uniform float uVignettingEnabled;

uniform vec2  uSize;
uniform sampler2D uImage;

out vec4 fragColor;

void main() {
    vec2 uv = FlutterFragCoord().xy / uSize;

    // ── 宽高比补偿 ──
    // UV 空间 x/y 物理距离不同（3:2 时 x 0.5 ≠ y 0.5），
    // 先将 centered 拉伸到等比像素空间再求 r
    float aspect = uSize.x / uSize.y;
    vec2 centered = uv - uOpticalCenter;
    vec2 centeredAsp = centered * vec2(aspect, 1.0);
    float r2 = dot(centeredAsp, centeredAsp);
    float r = sqrt(r2);

    // ── Lensfun 归一化：r_max=1 对应半对角线 ──
    float halfDiag = 0.5 * sqrt(aspect * aspect + 1.0);
    float rNorm = r / max(halfDiag, 0.001);

    vec3 color = vec3(0.0);

    if (uDistortionEnabled > 0.5 || uCAEnabled > 0.5) {
        float k1 = uDistortionEnabled > 0.5 ? uK1 : 0.0;
        float k2 = uDistortionEnabled > 0.5 ? uK2 : 0.0;
        float k3 = uDistortionEnabled > 0.5 ? uK3 : 0.0;
        float k4 = uDistortionEnabled > 0.5 ? uK4 : 0.0;
        float k5 = uDistortionEnabled > 0.5 ? uK5 : 0.0;

        // 牛顿法逆向求解 r_src（Lensfun 归一化空间）
        float rSrcNorm = rNorm;
        if (rNorm > 0.001 && (abs(k1) + abs(k2) + abs(k3) + abs(k4) + abs(k5)) > 1e-6) {
            for (int iter = 0; iter < 3; iter++) {
                float rs2 = rSrcNorm * rSrcNorm;
                float rs4 = rs2 * rs2;
                float rs6 = rs4 * rs2;
                float rs8 = rs4 * rs4;
                float rs10 = rs6 * rs4;

                float f_r = rSrcNorm * (1.0 + k1*rs2 + k2*rs4 + k3*rs6 + k4*rs8 + k5*rs10) - rNorm;
                float fprime = 1.0 + 3.0*k1*rs2 + 5.0*k2*rs4 + 7.0*k3*rs6 + 9.0*k4*rs8 + 11.0*k5*rs10;

                if (abs(fprime) > 1e-6) {
                    rSrcNorm -= f_r / fprime;
                }
                rSrcNorm = max(rSrcNorm, 0.0);
            }
        }

        // 从 r_src 推算源 UV（等比空间 → UV 空间）
        vec2 srcCenteredAsp = centeredAsp * (rNorm > 0.001 ? (rSrcNorm / rNorm) : 1.0);
        vec2 srcCentered = srcCenteredAsp / vec2(aspect, 1.0);
        vec2 srcUV = uOpticalCenter + srcCentered;

        // TCA: R/B 通道缩放（2.0 - factor 取反方向用于校正）
        float caR = mix(1.0, uCARed, uCAEnabled);
        float caB = mix(1.0, uCABlue, uCAEnabled);
        vec2 srcUV_red  = uOpticalCenter + srcCentered * caR;
        vec2 srcUV_blue = uOpticalCenter + srcCentered * caB;

        float r_c = texture(uImage, clamp(srcUV_red,  0.0, 1.0)).r;
        float g_c = texture(uImage, clamp(srcUV,       0.0, 1.0)).g;
        float b_c = texture(uImage, clamp(srcUV_blue,  0.0, 1.0)).b;
        color = vec3(r_c, g_c, b_c);
    } else {
        color = texture(uImage, uv).rgb;
    }

    // ── 暗角校正：Lensfun 存的是自然暗角量（k1 通常为负），取倒数补偿 ──
    if (uVignettingEnabled > 0.5) {
        float vigPoly = 1.0 + uVK1 * rNorm * rNorm
                          + uVK2 * rNorm * rNorm * rNorm * rNorm
                          + uVK3 * rNorm * rNorm * rNorm * rNorm * rNorm * rNorm;
        // 避免除以零或接近零的值
        float gain = 1.0 / max(vigPoly, 0.01);
        color *= gain;
        color = clamp(color, 0.0, 1.0);
    }

    fragColor = vec4(color, 1.0);
}
