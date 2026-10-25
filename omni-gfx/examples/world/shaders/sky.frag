#version 330 core
// 天空阶段：把 CC0 全景 HDR 映射到屏幕光线或立方体贴图的六个面。
// 调用位置：主画面的全分辨率背景、环境光与水面反射用的天空立方体贴图。
// 设计原因与取舍：
//   全景照片保留了真实的云层、日落色温和太阳高光，半分辨率程序化云很难达到同样细节。
//   同一条纹理既做背景又做立方体贴图，环境光、水面倒影与看到的天空不会各说各话。
//   等距柱状坐标与 `sky.py` 找太阳时使用的公式一致，旋转角也一致。
#include "world_shared.glsl"

uniform sampler2D uSkyHdri; // 等距柱状全景 HDR。
uniform vec2 uResolution; // 当前渲染目标尺寸。
uniform int uFace; // 小于零是主画面，否则是立方体贴图的面编号。
uniform vec3 uForward; // 主画面相机前方向。
uniform vec3 uRight; // 主画面相机右方向。
uniform vec3 uUp; // 主画面相机上方向。
uniform float uTanHalfFov; // 主画面视场角一半的正切。
uniform float uAspect; // 主画面宽高比。
uniform float uSkyRotation; // 天空绕纵轴的旋转角，弧度。
uniform float uSkyBackground; // 背景天空的亮度倍率，压低太阳高光保留颜色。
uniform float uSkyAmbient; // 立方体贴图的亮度倍率，给地面环境光与水面反射。

out vec4 fragColor; // 线性天空颜色。

void main()
{
    vec3 direction; // 当前像素对应的世界方向。
    if (uFace < 0)
    {
        direction = worldRayDirection(gl_FragCoord.xy, uResolution, uForward, uRight, uUp, uTanHalfFov, uAspect);
    }
    else
    {
        vec2 uv = gl_FragCoord.xy / uResolution * 2.0 - 1.0;
        direction = normalize(worldCubeDirection(uFace, uv));
    }
    // 旋转天空：太阳从原图的右后方转到画面左前方，阴影与天空亮部对得上。
    float cos_r = cos(uSkyRotation);
    float sin_r = sin(uSkyRotation);
    vec3 rotated = vec3(direction.x * cos_r - direction.z * sin_r, direction.y,
                        direction.x * sin_r + direction.z * cos_r);
    float u = atan(rotated.z, rotated.x) / 6.28318530718 + 0.5;
    // 地平线以下没有地面信息，统一取地平线一行；地形与水面会挡住这些方向。
    float v = acos(clamp(max(rotated.y, 0.0), 0.0, 1.0)) / 3.14159265359;
    vec3 sky = textureLod(uSkyHdri, vec2(u, v), 0.0).rgb;
    sky *= (uFace < 0) ? uSkyBackground : uSkyAmbient; // 背景与环境的亮度分开，太阳不会把天空推成白板。
    fragColor = vec4(sky, 1.0);
}
