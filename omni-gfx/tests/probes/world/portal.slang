/*
Omni 通用图形库 world/portal 模块编译探针：覆盖该效果的主要入口。
调用位置：`omni-gfx/build.py spirv` 逐模块编译；探针只验证类型与函数调用，不进入光影包。
*/
#include "../../../src/world/portal.slang"

[shader("fragment")]
float4 probeMain(float4 position : SV_Position) : SV_Target
{
    float t = position.x * 0.001 + 0.25; // 随像素变化的输入。
    float4x4 portal = ogxEndPortalLayer(3.0, t * 100.0); // 传送门层矩阵。
    return float4(portal[3].xyz, 1.0); // 有输出即可。
}
