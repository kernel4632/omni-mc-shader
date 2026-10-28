/*
Omni 通用图形库 shadow/eclipse 模块编译探针：覆盖该效果的主要入口。
调用位置：`omni-gfx/build.py spirv` 逐模块编译；探针只验证类型与函数调用，不进入光影包。
*/
#include "../sampler_alias.slang"
#include "../../../src/shadow/eclipse.slang"

[shader("fragment")]
float4 probeMain(float4 position : SV_Position) : SV_Target
{
    float t = position.x * 0.001 + 0.25; // 随像素变化的输入。
    float distort = ogxEclipseCalcDistort(float2(t, t), 0.9, 0.9, 1.0); // 阴影边缘压缩。
    return float4(distort, t, 0.0, 1.0); // 有输出即可。
}
