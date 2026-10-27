/*
Omni 通用图形库 lens/lens 模块编译探针：覆盖该效果的主要入口。
调用位置：`omni-gfx/build.py spirv` 逐模块编译；探针只验证类型与函数调用，不进入光影包。
*/
#include "../../../src/lens/lens.slang"

[shader("fragment")]
float4 probeMain(float4 position : SV_Position) : SV_Target
{
    float t = position.x * 0.001 + 0.25; // 随像素变化的输入。
    float2 offset = ogxLensDistOffset(float2(t, t), float2(0.2, 0.1), 1.0); // 桶形光斑偏移。
    return float4(offset, t, 1.0); // 有输出即可。
}
