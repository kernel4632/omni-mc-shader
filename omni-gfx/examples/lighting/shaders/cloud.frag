#version 330 core
// 体积云阶段：半分辨率沿视线步进积云，输出预乘颜色与覆盖率，供时间累积去噪。
// 调用位置：主画面天空绘制之前；结果由 `cloud_accum.frag` 与历史混合。
// 设计原因与取舍：
//   云是半透明介质，半分辨率足够；真正的噪声来自步进起点抖动，交给时间累积抹平。
//   朝下的方向不步进，地平线以下被地形遮住，省下的时间留给云内光照步进。
#include "common.glsl"

uniform vec2 uResolution; // 半分辨率尺寸。
uniform vec3 uForward; // 相机前方向。
uniform vec3 uRight; // 相机右方向。
uniform vec3 uUp; // 相机上方向。
uniform float uTanHalfFov; // 视场角一半的正切。
uniform float uAspect; // 宽高比。
uniform int uCloudSteps; // 本帧步进数，调画面与帧时用。

out vec4 fragColor; // rgb 是预乘云颜色，a 是覆盖率。

void main()
{
    vec3 direction = lightingRayDirection(gl_FragCoord.xy, uResolution, uForward, uRight, uUp, uTanHalfFov, uAspect); // 当前像素方向。
    if (direction.y < -0.035) // 地平线以下的天空被地形挡住，不付云的成本。
    {
        fragColor = vec4(0.0); // 完全透明。
        return;
    }
    vec2 noise = ogxBlueNoise(uBlueNoise, ivec2(gl_FragCoord.xy)); // 固定空间蓝噪声，只用来轻微打散步进条带。
    vec2 jitter = vec2(0.5) + (noise - vec2(0.5)) * 0.02; // 抖动极小；云形与云内光照保持稳定，条带交给步进和模糊。
    vec4 cloud = lightingCloudMarch(direction, jitter, uCloudSteps); // 库的体积云步进。
    fragColor = cloud; // 预乘颜色与覆盖率。
}
