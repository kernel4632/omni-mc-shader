#version 330 core
// 反射降噪阶段：半分辨率反射图上做九点邻域滤波，按法线与深度剔除不属于同一水面的邻居。
// 调用位置：反射阶段之后、水面合成之前。
// 设计原因与取舍：屏幕空间追踪在薄几何边缘会漏出孤立亮点，直接放大到全分辨率会变成
// 一排排小火星；九点滤波利用同一阶段写下的法线与深度，只合并朝向和距离都接近的邻居。
#include "world_shared.glsl"

uniform sampler2D uReflection; // 反射颜色与可信度。
uniform sampler2D uReflectionDepth; // 反射阶段写下的屏幕深度。
uniform sampler2D uReflectionNormal; // 反射阶段写下的编码法线。
uniform vec2 uResolution; // 半分辨率尺寸。
uniform mat4 uProjectionInverse; // 逆投影矩阵。
uniform float uFrame; // 帧号，给噪声换相位。

out vec4 fragColor; // 降噪后的反射。

void main()
{
    vec2 uv = gl_FragCoord.xy / uResolution; // 半分辨率坐标。
    vec4 data = texture(uReflection, uv); // 本像素的反射。
    float screenDepth = texture(uReflectionDepth, uv).r; // 本像素屏幕深度。
    if (screenDepth >= 1.0) // 没有水面像素时输出空反射，后续按可信度处理。
    {
        fragColor = vec4(0.0, 0.0, 0.0, 0.0);
        return;
    }
    vec3 viewPos = ogxReflectionViewPos(uv, screenDepth, uProjectionInverse); // 还原视空间位置。
    vec3 viewDir = normalize(-viewPos); // 从表面指向相机。
    vec3 normal = ogxDecodeNormal(texture(uReflectionNormal, uv).xy); // 还原世界法线。
    vec2 noise = vec2(ogxBayer8(gl_FragCoord.xy + vec2(uFrame * 0.37, uFrame * 0.71)),
                      ogxBayer8(gl_FragCoord.xy + vec2(17.0, uFrame * 0.29))); // 逐帧变化的抖动，方向不同以免拉出斜纹。
    float radius = mix(6.0, 16.0, smoothstep(40.0, 400.0, length(viewPos))); // 远处反射更模糊，滤波半径更大。
    ogxReflectionAtrousFilter(data, viewPos, viewDir, normal, 0.18, radius, noise, uv, uReflection,
                              uReflectionDepth, uReflectionNormal, 1.0 / uResolution, uProjectionInverse); // 九点滤波。
    fragColor = data; // 写回降噪结果。
}
