#include <flutter/runtime_effect.glsl>
precision highp float;

uniform vec2  uSize;        // 渲染分辨率
uniform float uAmount;      // 0-1
uniform float uRadius;      // 像素
uniform float uMasking;     // 0-1

uniform sampler2D uImage;   // sampler 0：待锐化的图（develop 输出）

out vec4 fragColor;

float luma(vec3 c) { return dot(c, vec3(0.2126, 0.7152, 0.0722)); }

void main() {
    vec2 texel = 1.0 / uSize;
    vec2 uv = FlutterFragCoord().xy / uSize;

    vec3 orig = texture(uImage, uv).rgb;

    // —— 高斯模糊（3x3，按 radius 缩放采样偏移）——
    vec2 r = texel * uRadius;
    vec3 blur = vec3(0.0);
    blur += texture(uImage, uv + vec2(-r.x, -r.y)).rgb * 0.0625;
    blur += texture(uImage, uv + vec2( 0.0, -r.y)).rgb * 0.125;
    blur += texture(uImage, uv + vec2( r.x, -r.y)).rgb * 0.0625;
    blur += texture(uImage, uv + vec2(-r.x,  0.0)).rgb * 0.125;
    blur += texture(uImage, uv + vec2( 0.0,  0.0)).rgb * 0.25;
    blur += texture(uImage, uv + vec2( r.x,  0.0)).rgb * 0.125;
    blur += texture(uImage, uv + vec2(-r.x,  r.y)).rgb * 0.0625;
    blur += texture(uImage, uv + vec2( 0.0,  r.y)).rgb * 0.125;
    blur += texture(uImage, uv + vec2( r.x,  r.y)).rgb * 0.0625;

    vec3 detail = orig - blur;

    // —— 边缘掩蔽：用亮度梯度（Sobel 简化）——
    float l  = luma(orig);
    float lx = luma(texture(uImage, uv + vec2(r.x, 0.0)).rgb)
             - luma(texture(uImage, uv - vec2(r.x, 0.0)).rgb);
    float ly = luma(texture(uImage, uv + vec2(0.0, r.y)).rgb)
             - luma(texture(uImage, uv - vec2(0.0, r.y)).rgb);
    float grad = length(vec2(lx, ly));

    // masking=0 → 全图锐化(mask=1)；masking 越大 → 只在强边缘锐化
    // 用 masking 控制 smoothstep 的阈值范围
    float edge = smoothstep(0.0, mix(1.0, 0.15, uMasking), grad);
    float mask = mix(1.0, edge, uMasking);

    vec3 sharp = orig + uAmount * detail * mask;
    fragColor = vec4(clamp(sharp, 0.0, 1.0), 1.0);
}