/*
Omni 通用图形库 reflection/specular 模块编译探针：覆盖该效果的主要入口。
调用位置：`omni-gfx/build.py spirv` 逐模块编译；探针只验证类型与函数调用，不进入光影包。
*/
#include "../slang_compat.slang"
#include "../sampler_alias.slang"
#include "../../../src/reflection/specular.slang"

[shader("fragment")]
float4 probeMain(float4 position : SV_Position) : SV_Target
{
    float t = position.x * 0.001 + 0.25; // 随像素变化的输入。
    float visibility = ogxReflectionVisibility(t, t, 50.0); // 反射可见度。
    return float4(visibility, t, 0.0, 1.0); // 有输出即可。
}
