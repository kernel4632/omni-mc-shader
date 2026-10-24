#version 330 core
// 天空合成阶段（全分辨率）：把半分辨率的天空与云双边升采样到满屏，再补上太阳圆盘。
// 调用位置：每帧在天空累积之后、地形之前绘制，写满整个场景背景。
// 设计原因与取舍：普通双线性会把云边拉成一团雾，所以四个浮点纹素按亮度与覆盖率
// 加权，颜色相近的一侧权重大，云边仍然清楚；太阳圆盘只有几个像素，必须在全分辨率
// 单独加，否则降采样后会被抹掉。太阳被云挡住时圆盘按覆盖率淡出。
#include "world_shared.glsl"

uniform sampler2D uSky; // 半分辨率累积天空。
uniform vec2 uResolution; // 全分辨率画面尺寸。
uniform vec2 uSkyResolution; // 半分辨率天空尺寸。
uniform vec3 uForward; // 相机前方向。
uniform vec3 uRight; // 相机右方向。
uniform vec3 uUp; // 相机上方向。
uniform float uTanHalfFov; // 竖直视场角一半的正切。
uniform float uAspect; // 画面宽高比。
uniform vec3 uSunDirection; // 太阳方向。
uniform float uSunStrength; // 太阳辐照度倍率。

out vec4 fragColor; // 线性天空颜色。

// 双边升采样：四邻域按色差与覆盖率差加权，保留云边与天空的明暗分界。
vec4 upsampleSky(vec2 uv)
{
    vec2 offset = 0.5 / uSkyResolution; // 取样点落在四个纹素之间。
    vec4 center = texture(uSky, uv); // 中心样本，只用于比较色差。
    float centerLuma = ogxLuminance(center.rgb); // 中心亮度。
    vec4 samples[4]; // 四个邻域样本。
    float weights[4]; // 对应权重。
    vec2 positions[4] = vec2[4](vec2(-1.0, -1.0), vec2(1.0, -1.0), vec2(-1.0, 1.0), vec2(1.0, 1.0)); // 四个对角方向。
    float total = 0.0; // 权重和。
    for (int i = 0; i < 4; i++) // 逐个取样并算权重。
    {
        samples[i] = texture(uSky, uv + positions[i] * offset); // 双线性取样，硬件已经做了插值。
        float lumaDifference = abs(ogxLuminance(samples[i].rgb) - centerLuma); // 亮度差。
        float coverageDifference = abs(samples[i].a - center.a); // 云覆盖率差。
        weights[i] = 1.0 / (0.03 + lumaDifference * 3.0 + coverageDifference * 12.0); // 差得越多权重越小。
        total += weights[i]; // 累加权重的和。
    }
    vec4 result = vec4(0.0); // 加权结果。
    for (int i = 0; i < 4; i++) // 按权重混合。
    {
        result += samples[i] * (weights[i] / total); // 归一化后相加。
    }
    return result; // 返回升采样后的颜色与覆盖率。
}

void main()
{
    vec2 uv = gl_FragCoord.xy / uResolution; // 当前像素坐标。
    vec4 sky = upsampleSky(uv); // 双边升采样。
    vec3 direction = worldRayDirection(gl_FragCoord.xy, uResolution, uForward, uRight, uUp, uTanHalfFov, uAspect); // 世界方向。
    vec3 sunColor = worldSunColor(); // 太阳色度。
    // 太阳圆盘只有几个像素，必须在全分辨率相加；被云挡住的部分按覆盖率淡出。
    float disc = ogxSunDisc(direction, normalize(uSunDirection), 5.5e-5, 3.2e4); // 圆盘遮罩。
    vec3 color = sky.rgb + sunColor * disc * uSunStrength * 26.0 * (1.0 - sky.a); // 加上圆盘。
    fragColor = vec4(color, 1.0); // 背景是不透明的。
}
