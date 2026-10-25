/*
采样模块编译探针：调用全部公开函数，供 Slang 生成 SPIR-V 时检查纹理与阴影采样器类型。
调用位置：`omni-gfx/build.py spirv`；探针需要一张六十四像素噪声纹理与一张阴影图绑定。
设计原因与取舍：
    纹理声明只用于编译，探针不会运行；绑定编号固定为 Vulkan 的零组零号与一号。
    带导数的取样把导数当普通参数传入，探针因此不需要真实屏幕坐标。
*/
#include "../../src/sampling.slang"

[[vk::binding(0, 0)]]
Sampler2D probeNoise;  // 编译期纹理句柄，运行探针时由调用方绑定。

[[vk::binding(1, 0)]]
Sampler2DShadow probeShadow;  // 编译期阴影图句柄，只做比较采样的类型检查。

[shader("fragment")]
float4 probeMain(float4 position : SV_Position) : SV_Target
{
    int2 pixel = int2(position.xy);  // 屏幕像素坐标。
    float4 center = ogxTexelFetch(probeNoise, pixel, 0);  // 显式取像素。
    float2 blue = ogxBlueNoise(probeNoise, pixel);  // 静态蓝噪声。
    float2 temporal = ogxBlueNoiseTemporal(probeNoise, pixel, 7);  // 时间偏移。
    float bayer = ogxBayerTemporal(pixel, 11);  // 拜尔时间抖动。
    float2 resolution = float2(64.0, 64.0);  // 贴图边长。
    float4 smooth = ogxSmoothFilter(probeNoise, float2(0.5, 0.5), resolution);  // 平滑过滤。
    float shadow = ogxShadowSmoothFilter(probeShadow, float3(0.5, 0.5, 0.4), 1024.0);  // 阴影平滑过滤。
    float2 du = float2(0.01, 0.0);  // 假的横向导数。
    float2 dv = float2(0.0, 0.01);  // 假的纵向导数。
    float4 nearest = ogxSampleNearest(probeNoise, float2(0.5, 0.5), 1.0 / resolution, du, dv, float2(0.01, 0.01));  // 最近点取样。
    float4 rgss = ogxRgssSample(probeNoise, float2(0.5, 0.5), 1.0 / resolution, du, dv);  // 旋转网格超采样。
    float2 jitter = ogxTaaJitter(int(position.x), true);  // 抗锯齿抖动。
    float2 jitterLong = ogxTaaJitter(int(position.y), false);  // 八帧序列。
    float halton = ogxHalton2(int(position.x)) + ogxHalton3(int(position.y));  // Halton 低差异序列。
    return float4(center.rgb + float3(blue, temporal.x) + bayer + smooth.rgb + nearest.rgb + rgss.rgb + float3(shadow, jitter.x + jitterLong.y, jitter.y), 1.0);  // 汇总全部结果。
}
