#version 330 core
// 体积云阶段：全分辨率沿视线步进积云，输出预乘颜色与覆盖率，供模糊与时间抗锯齿去噪。
// 调用位置：主画面天空绘制之前；结果由 `cloud_blur.frag` 模糊后交给天空合成。
// 设计原因与取舍：
//   云边与塔身需要清晰轮廓，因此按全分辨率步进；真正的噪点来自步进起点抖动，交给时间抗锯齿抹平。
//   朝下的方向不步进，地平线以下被地形遮住，省下的时间留给云内光照步进。
#include "common.glsl"

uniform vec2 uResolution; // 全分辨率尺寸。
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
    vec2 noise = ogxBlueNoise(uBlueNoise, ivec2(gl_FragCoord.xy) + ivec2(int(uFrame) * 37, int(uFrame) * 53)); // 每帧换相位的蓝噪声。
    vec2 jitter = vec2(0.5) + (noise - vec2(0.5)) * 0.65; // 接近整步抖动；不做整步抖动，厚云会在固定高度留下横纹。
    vec4 cloud = lightingCloudMarch(direction, jitter, uCloudSteps); // 库的体积云步进。
    fragColor = cloud; // 预乘颜色与覆盖率。
}
