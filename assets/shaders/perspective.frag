#include <flutter/runtime_effect.glsl>

precision highp float;

uniform vec2 uOutputSize;
uniform mat3 uInvHomography;  // 逆单应性矩阵（Dart 侧预计算）
uniform sampler2D uImage;

out vec4 fragColor;

void main() {
    // 目标像素的归一化坐标
    vec2 uv = FlutterFragCoord().xy / uOutputSize;

    // 通过逆单应性矩阵映射到源图像坐标
    vec3 src = uInvHomography * vec3(uv, 1.0);
    vec2 srcUV = src.xy / max(src.z, 1e-6);

    // 边缘 clamp（不做边界扩展，空白区域由 autoCrop 处理）
    vec2 clampedUV = clamp(srcUV, 0.0, 1.0);

    vec3 color = texture(uImage, clampedUV).rgb;

    // 超出源图范围的像素渲染为透明（alpha=0）
    float alpha = all(greaterThanEqual(srcUV, vec2(0.0))) &&
                  all(lessThanEqual(srcUV, vec2(1.0))) &&
                  src.z > 0.0 ? 1.0 : 0.0;

    fragColor = vec4(color, alpha);
}
