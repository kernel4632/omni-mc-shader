/*
手持光模块编译探针：调用光斑形状、手电指向与漫反射权重。
调用位置：`omni-gfx/build.py spirv` 逐模块编译；探针只验证类型与分支，不进入光影包。
设计原因与取舍：用归一化方向与稳定的小参数覆盖主要入口，不构造完整相机状态。
*/
#include "sampler_alias.slang"
#include "../../src/heldlight.slang"

[shader("fragment")]
float4 probeMain(float4 position : SV_Position) : SV_Target
{
    float t = position.x * 0.001 + 0.25; // 随像素变化的输入。
    float shape = ogxSpotShape(t, 0.5); // 光斑形状。
    float3 aim = ogxFlashlightAimDirection(t, t * 0.5, 0.1, true); // 手电平滑指向。
    float3 diffuse = ogxDiffuseBurley(normalize(float3(t, 0.2, 0.8)), normalize(float3(-0.1, -0.2, -1.0)),
        normalize(float3(0.2, 0.4, -0.9)), 0.4) * aim; // 漫反射权重乘指向。
    return float4(diffuse + shape, 1.0); // 合成一个可编译的返回。
}
