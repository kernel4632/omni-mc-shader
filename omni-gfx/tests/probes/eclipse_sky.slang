/*
Eclipse 天空模块编译探针：调用太阳圆盘、球面映射与极光，覆盖该模块的主要纯计算入口。
调用位置：`omni-gfx/build.py spirv` 逐模块编译；探针只验证类型与函数调用，不进入光影包。
*/
#include "../../src/eclipse_sky.slang"

[shader("fragment")]
float4 probeMain(float4 position : SV_Position) : SV_Target
{
    float t = position.x * 0.001 + 0.25; // 随像素变化的输入。
    float3 sun = ogxEclipseDrawSun(t, float3(1.0, 0.9, 0.8)); // 太阳圆盘。
    float2 uv = ogxEclipseSphereMap(float2(t, 1.0 - t)); // 球面屏幕映射。
    float3 aurora = ogxEclipseAurora(normalize(float3(t, 0.4, 0.8)), 4, t, 0.2, -0.5, t * 60.0,
        float3(0.0), 1.0, 1.0, float3(0.1, 0.8, 0.3), false, false); // 极光。
    return float4(sun + float3(uv, 0.0) + aurora, 1.0); // 有输出即可。
}
