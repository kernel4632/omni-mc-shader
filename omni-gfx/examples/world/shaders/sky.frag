#version 330 core
// 天空阶段：主画面按屏幕坐标生成光线，立方体贴图按六个面生成光线。
// 调用位置：测试世界先渲染天空立方体贴图，再渲染主画面的天空背景。
// 设计原因与取舍：同一份天空函数服务两种输出，反射与背景不会出现色差。
#include "clouds.glsl"

uniform vec3 uForward;  // 相机前方向。
uniform vec3 uRight;  // 相机右方向。
uniform vec3 uUp;  // 相机上方向。
uniform float uTanHalfFov;  // 竖直视场角一半的正切。
uniform float uAspect;  // 画面宽高比。
uniform int uFace;  // 小于零表示主画面，否则是立方体贴图的六个面之一。
uniform vec2 uResolution;  // 主画面尺寸，用于把像素坐标变成零到一。
uniform float uFrame;  // 帧号，给云层抖动换相位。

out vec4 fragColor;  // 线性高动态范围天空颜色。

// 立方体贴图六个面的方向：u 与 v 都在负一到一之间。
vec3 cubeDirection(int face, vec2 uv)
{
    if (face == 0) return vec3(1.0, -uv.y, -uv.x);  // 正 X 面。
    if (face == 1) return vec3(-1.0, -uv.y, uv.x);  // 负 X 面。
    if (face == 2) return vec3(uv.x, 1.0, uv.y);  // 正 Y 面。
    if (face == 3) return vec3(uv.x, -1.0, -uv.y);  // 负 Y 面。
    if (face == 4) return vec3(uv.x, -uv.y, 1.0);  // 正 Z 面。
    return vec3(-uv.x, -uv.y, -1.0);  // 负 Z 面。
}

void main()
{
    vec3 direction;  // 当前像素对应的世界空间方向。
    if (uFace < 0)  // 主画面：由像素坐标和相机基向量构造光线。
    {
        vec2 ndc = gl_FragCoord.xy / uResolution * 2.0 - 1.0;  // 映射到负一到一。
        direction = normalize(uForward + uRight * ndc.x * uTanHalfFov * uAspect + uUp * ndc.y * uTanHalfFov);  // 针孔相机光线。
    }
    else  // 立方体贴图：像素坐标映射到当前面的局部坐标。
    {
        vec2 uv = gl_FragCoord.xy / uResolution * 2.0 - 1.0;  // 每个面都是同样大小的方形。
        direction = normalize(cubeDirection(uFace, uv));  // 面方向。
    }
    float jitter = ogxInterleavedGradientNoise(gl_FragCoord.xy + vec2(uFrame * 5.588238, uFrame * 3.17));  // 每帧变化的抖动。
    fragColor = vec4(skyRadiance(direction, jitter), 1.0);  // 天空颜色写入目标。
}
