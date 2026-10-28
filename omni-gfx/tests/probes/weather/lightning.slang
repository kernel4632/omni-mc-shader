/*
Omni 通用图形库 weather/lightning 模块编译探针：覆盖该效果的主要入口。
调用位置：`omni-gfx/build.py spirv` 逐模块编译；探针只验证类型与函数调用，不进入光影包。
*/
#include "../../../src/weather/lightning.slang"

[shader("fragment")]
float4 probeMain(float4 position : SV_Position) : SV_Target
{
    float t = position.x * 0.001 + 0.25; // 随像素变化的输入。
    float3 light = ogxLightSourceColors(t, 1.0, float3(1.0), float3(0.5), float3(0.2), 1.0, false); // 末地光源颜色。
    return float4(light, 1.0); // 有输出即可。
}
