/*
Eclipse 高光模块编译探针：构造体素射线任务并调用反射可见度与体素反射，覆盖主要纯计算入口。
调用位置：`omni-gfx/build.py spirv` 逐模块编译；探针只验证类型与函数调用，不进入光影包。
*/
#include "../../src/eclipse_specular.slang"

[shader("fragment")]
float4 probeMain(float4 position : SV_Position) : SV_Target
{
    float t = position.x * 0.001 + 0.25; // 随像素变化的输入。
    OgxEclipseRayJob job = ogxEclipseRayJob(float3(0.0), normalize(float3(t, 0.2, 1.0))); // 体素射线任务。
    float mask = 0.0; // 背景遮罩。
    float4 reflection = ogxEclipseVoxelReflection(job.direction, float3(0.0, 1.0, 0.0), float3(0.0, 1.0, 0.0),
        job.origin, t, mask, float3(1.0), float3(0.5)); // 体素反射。
    float visibility = ogxEclipseGetReflectionVisibility(t, t, 50.0); // 反射可见度。
    return float4(reflection.rgb + float3(visibility, mask, 0.0), 1.0); // 有输出即可。
}
