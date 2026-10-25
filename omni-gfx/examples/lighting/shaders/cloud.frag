#version 330 core
// 体积云阶段：半分辨率沿视线步进积云，再与上一帧累积，输出预乘颜色与覆盖率。
// 调用位置：主画面天空绘制之前；结果由 `cloud_blur.frag` 模糊后交给天空合成。
// 设计原因与取舍：
//   半分辨率把最贵的体积步进成本压到四分之一，再用一次可分离模糊与时间累积还原边缘；
//   真正的噪点来自步进起点抖动，时间累积把每帧不同的抖动平均成柔和的云边。
//   朝下的方向不步进，地平线以下被地形遮住，省下的时间留给云内光照步进。
#include "common.glsl"

uniform vec2 uResolution; // 半分辨率尺寸。
uniform vec3 uForward; // 相机前方向。
uniform vec3 uRight; // 相机右方向。
uniform vec3 uUp; // 相机上方向。
uniform float uTanHalfFov; // 视场角一半的正切。
uniform float uAspect; // 宽高比。
uniform int uCloudSteps; // 本帧步进数，调画面与帧时用。
uniform sampler2D uCloudHistory; // 上一帧的累积云。
uniform float uCloudBlend; // 本帧权重；首帧为一，之后约零点一四。

out vec4 fragColor; // rgb 是预乘云颜色，a 是覆盖率。

void main()
{
    vec2 uv = gl_FragCoord.xy / uResolution; // 当前像素在半分辨率目标里的坐标。
    vec3 direction = lightingRayDirection(gl_FragCoord.xy, uResolution, uForward, uRight, uUp, uTanHalfFov, uAspect); // 当前像素方向。
    if (direction.y < -0.035) // 地平线以下的天空被地形挡住，不付云的成本。
    {
        fragColor = vec4(0.0); // 完全透明。
        return;
    }
    vec2 noise = ogxBlueNoise(uBlueNoise, ivec2(gl_FragCoord.xy) + ivec2(int(uFrame) * 37, int(uFrame) * 53)); // 每帧换相位的蓝噪声。
    vec2 jitter = vec2(0.5) + (noise - vec2(0.5)) * 0.85; // 接近整步抖动；不做整步抖动，厚云会在固定高度留下横纹。
    vec4 cloud = lightingCloudMarch(direction, jitter, uCloudSteps); // 库的体积云步进。
    vec4 history = texture(uCloudHistory, uv); // 上一帧同一像素。
    // 简单邻域夹紧：把历史限制在本帧颜色附近，移动相机时不会拖出一条旧云。
    history = clamp(history, cloud - vec4(0.18, 0.18, 0.18, 0.22), cloud + vec4(0.18, 0.18, 0.18, 0.22));
    fragColor = mix(history, cloud, clamp(uCloudBlend, 0.0, 1.0)); // 时间累积。
}
