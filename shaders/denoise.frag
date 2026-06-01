#include <flutter/runtime_effect.glsl>
precision highp float;

uniform vec2  uSize;        // 渲染分辨率（目标尺寸）
uniform float uLuma;        // 明度降噪 0-1
uniform float uColor;       // 颜色降噪 0-1

uniform sampler2D uImage;   // sampler 0：sourceImage

out vec4 fragColor;

void main() {
    vec2 uv = FlutterFragCoord().xy / uSize;
    // 占位
    fragColor = vec4(texture(uImage, uv).rgb, 1.0);
}