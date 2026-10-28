/*
Eclipse 漫反射模块编译探针：调用方块光合成与手电阴影参数，覆盖主要纯计算入口。
调用位置：`omni-gfx/build.py spirv` 逐模块编译；探针只验证类型与函数调用，不进入光影包。
*/
#include "../../../src/gi/blocklight.slang"

[shader("fragment")]
float4 probeMain(float4 position : SV_Position) : SV_Target
{
    float t = position.x * 0.001 + 0.25; // 随像素变化的输入。
    float3 blockLight = ogxBlockLightLighting(float3(1.0, 0.8, 0.6), t, float3(0.2), float3(0.1),
        float3(0.0), 32.0, 10.0, 1.0, false, true); // 方块光合成。
    return float4(blockLight, 1.0); // 有输出即可。
}
