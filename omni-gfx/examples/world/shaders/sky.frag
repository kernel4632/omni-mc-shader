#version 330 core
// 天空阶段：用生成的大气与云模块算主画面背景，也渲染水面反射用的立方体贴图。
// 调用位置：测试世界先渲染天空立方体贴图的六个面，再渲染主画面的天空背景。
// 设计原因与取舍：同一份天空函数服务两种输出，反射与背景不会出现色差。
#include "world_shared.glsl"

uniform vec3 uForward; // 相机前方向。
uniform vec3 uRight; // 相机右方向。
uniform vec3 uUp; // 相机上方向。
uniform float uTanHalfFov; // 竖直视场角一半的正切。
uniform float uAspect; // 画面宽高比。
uniform int uFace; // 小于零表示主画面，否则是立方体贴图的六个面之一。
uniform vec2 uResolution; // 主画面尺寸，用于把像素坐标变成零到一。
uniform float uFrame; // 帧号，给云层抖动换相位。
uniform vec3 uSunDirection; // 太阳方向，世界空间单位向量。
uniform vec3 uCameraPos; // 相机位置，米。
uniform float uTime; // 场景时间，推动云与雾。
uniform float uCloudCover; // 云量，零到一。

out vec4 fragColor; // 线性高动态范围天空颜色。

// 立方体贴图六个面的方向：u 与 v 都在负一到一之间。
vec3 cubeDirection(int face, vec2 uv)
{
    if (face == 0) return vec3(1.0, -uv.y, -uv.x); // 正 X 面。
    if (face == 1) return vec3(-1.0, -uv.y, uv.x); // 负 X 面。
    if (face == 2) return vec3(uv.x, 1.0, uv.y); // 正 Y 面。
    if (face == 3) return vec3(uv.x, -1.0, -uv.y); // 负 Y 面。
    if (face == 4) return vec3(uv.x, -uv.y, 1.0); // 正 Z 面。
    return vec3(-uv.x, -uv.y, -1.0); // 负 Z 面。
}

void main()
{
    vec3 direction; // 当前像素对应的世界空间方向。
    if (uFace < 0) // 主画面：由像素坐标和相机基向量构造光线。
    {
        vec2 ndc = gl_FragCoord.xy / uResolution * 2.0 - 1.0; // 映射到负一到一。
        direction = normalize(uForward + uRight * ndc.x * uTanHalfFov * uAspect + uUp * ndc.y * uTanHalfFov); // 针孔相机光线。
    }
    else // 立方体贴图：像素坐标映射到当前面的局部坐标。
    {
        vec2 uv = gl_FragCoord.xy / uResolution * 2.0 - 1.0; // 每个面都是同样大小的方形。
        direction = normalize(cubeDirection(uFace, uv)); // 面方向。
    }
    vec3 sunDirection = normalize(uSunDirection); // 太阳方向。
    float altitude = max(uCameraPos.y, 0.0) * 0.001; // 米换成公里。
    OgxAtmosphere air = ogxAtmosphereEarth(); // 地球大气常数。
    vec3 sky = ogxAtmosphereSky(air, altitude, direction, sunDirection, uFace < 0 ? 8 : 6); // 单次散射天空。
    vec3 sun = worldSunColor(); // 太阳色度。
    sky += sun * ogxSunDisc(direction, sunDirection, 5.5e-5, 3.2e4) * 18.0; // 太阳圆盘。
    float jitter = ogxInterleavedGradientNoise(gl_FragCoord.xy + vec2(uFrame * 5.588238, uFrame * 3.17)); // 每帧变化的抖动。
    OgxCloudLayer layer = worldCloudLayer(uTime, uCloudCover); // 本帧云层。
    vec4 clouds = ogxCloudMarch(layer, uCameraPos * 0.001, direction, sunDirection, sun * 1.8, sky * 0.35, jitter, uFace < 0 ? 24 : 12); // 体积云。
    float horizonFade = smoothstep(0.015, 0.12, direction.y); // 地平线附近淡出，避免云墙。
    sky = mix(sky, clouds.rgb, clouds.a * horizonFade); // 按覆盖率合成云。
    fragColor = vec4(sky, 1.0); // 写入线性高动态范围颜色。
}
