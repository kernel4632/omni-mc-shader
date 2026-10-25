/*
放大模块编译探针：调用边缘方向重采样、对比度自适应锐化与放大后锐化。
调用位置：`omni-gfx/build.py spirv` 逐模块编译；探针只验证，不进入光影包。
设计原因与取舍：画面尺寸用屏幕坐标构造，采样器只需要类型。
*/
Sampler2D probeTex2D; // 全局纹理声明：探针只需要类型，不需要真实绑定。
#include "../../src/upscale.slang"

[shader("fragment")]
float4 probeMain(float4 position : SV_Position) : SV_Target
{
    float t = position.x * 0.001 + 0.25; // 随像素变化的输入。
    int2 texel = int2(position.xy); // 纹素坐标。
    float3 easu = ogxFsrEasu(probeTex2D, float2(position.xy), float2(640.0, 360.0), float2(1280.0, 720.0)); // 边缘方向重采样。
    float3 cas = ogxCas(probeTex2D, easu, texel, 20.0, true); // 对比度自适应锐化。
    float3 shr = ogxFsr1(probeTex2D, texel, 30.0, false); // 放大后锐化。
    return float4(easu + cas + shr + t, 1.0); // 有输出即可。
}
