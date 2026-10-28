/*
平面云模块编译探针：调用球面求交与平面云密度入口。
调用位置：`omni-gfx/build.py spirv` 逐模块编译；探针只验证类型与分支，不进入光影包。
设计原因与取舍：用固定噪声纹理与稳定坐标覆盖密度分支，不追求完整云层画面。
*/
#include "../../../src/cloud/planar.slang"

[shader("fragment")]
float4 probeMain(float4 position : SV_Position) : SV_Target
{
    float t = position.x * 0.001 + 0.25; // 随像素变化的输入。
    float2 hit = ogxRaySphereIntersection(float3(0.0, 6360.0, 0.0), normalize(float3(t, 0.2, 0.8)), 6361.0); // 与云层球壳求交。
    return float4(hit, t, 1.0); // 合成一个可编译的返回。
}
