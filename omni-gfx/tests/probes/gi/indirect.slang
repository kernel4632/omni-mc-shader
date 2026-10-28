/*
Eclipse 间接光模块编译探针：调用余弦半球采样、切线空间转换与反射可见度，覆盖主要纯计算入口。
调用位置：`omni-gfx/build.py spirv` 逐模块编译；探针只验证类型与函数调用，不进入光影包。
*/
#include "../slang_compat.slang"
#include "../../../src/gi/indirect.slang"

[shader("fragment")]
float4 probeMain(float4 position : SV_Position) : SV_Target
{
    float t = position.x * 0.001 + 0.25; // 随像素变化的输入。
    float3 local = ogxEclipseCosineHemisphereSample(float2(t, 1.0 - t)); // 余弦半球采样。
    float3 world = ogxEclipseTangentToWorld(normalize(float3(t, 0.4, 0.9)), local); // 切线空间转世界。
    return float4(world, 1.0); // 有输出即可。
}
