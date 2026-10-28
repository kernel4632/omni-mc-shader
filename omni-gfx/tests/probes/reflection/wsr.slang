/*
Omni 通用图形库 reflection/wsr 模块编译探针：覆盖该效果的主要入口。
调用位置：`omni-gfx/build.py spirv` 逐模块编译；探针只验证类型与函数调用，不进入光影包。
*/
#include "../slang_compat.slang"
#include "../sampler_alias.slang"
#include "../../../src/reflection/wsr.slang"

[shader("fragment")]
float4 probeMain(float4 position : SV_Position) : SV_Target
{
    float t = position.x * 0.001 + 0.25; // 随像素变化的输入。
    OgxRayJob job = ogxRayJob(float3(0.0), normalize(float3(t, 0.2, 1.0))); // 体素射线任务。
    return float4(job.direction, 1.0); // 有输出即可。
}
