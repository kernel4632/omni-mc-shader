/*
采样模块编译探针：调用全部公开函数，供 Slang 生成 SPIR-V 时检查纹理类型。
调用位置：`omni-gfx/build.py spirv`；探针需要一张六十四像素噪声纹理绑定。
设计原因与取舍：
    纹理声明只用于编译，探针不会运行；绑定编号固定为 Vulkan 的零组零号。
*/
#include "../../src/sampling.slang"

[[vk::binding(0, 0)]]
Sampler2D probeNoise;  // 编译期纹理句柄，运行探针时由调用方绑定。

[shader("fragment")]
float4 probeMain(float4 position : SV_Position) : SV_Target
{
    int2 pixel = int2(position.xy);  // 屏幕像素坐标。
    float4 center = ogxTexelFetch(probeNoise, pixel, 0);  // 显式取像素。
    float2 blue = ogxBlueNoise(probeNoise, pixel);  // 静态蓝噪声。
    float2 temporal = ogxBlueNoiseTemporal(probeNoise, pixel, 7);  // 时间偏移。
    float bayer = ogxBayerTemporal(pixel, 11);  // 拜尔时间抖动。
    return float4(center.rgb + float3(blue, temporal.x) + bayer, 1.0);  // 汇总全部结果。
}
