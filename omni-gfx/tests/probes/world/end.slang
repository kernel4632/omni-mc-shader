/*
iterationT 末地模块编译探针：调用星空、行星 BRDF 与云影查表，覆盖末地补充算法的主要入口。
调用位置：`omni-gfx/build.py spirv` 逐模块编译；探针只验证类型与函数调用，不进入光影包。
*/
#include "../../../src/world/end.slang"

[shader("fragment")]
float4 probeMain(float4 position : SV_Position) : SV_Target
{
    float t = position.x * 0.001 + 0.25; // 随像素变化的输入。
    float3 stars = ogxEndStars(normalize(float3(t, 0.3, 0.8)), float3(0.0, 0.2, 1.0), t * 60.0, 1, 1.0, 1.0); // 末地星空。
    float3 planet = ogxPlanetShading(float3(0.6, 0.4, 0.2), float3(0.0, 1.0, 0.0), float3(0.0, 0.0, 1.0),
        normalize(float3(0.3, 0.8, 0.5)), 1.0); // 行星 BRDF。
    return float4(stars + planet, 1.0); // 有输出即可。
}
