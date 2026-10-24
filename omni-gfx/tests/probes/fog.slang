/*
雾模块编译探针：调用雾密度、混合相位、粉末效应、沿视线积分与合成。
调用位置：`omni-gfx/build.py spirv` 逐模块编译；探针只验证，不进入光影包。
设计原因与取舍：输入用屏幕坐标构造，避免常量折叠掩盖类型问题；不追求画面正确。
*/
#include "../../src/fog.slang"

[shader("fragment")]
float4 probeMain(float4 position : SV_Position) : SV_Target
{
    float t = position.x * 0.001 + 0.25; // 随像素变化的输入。
    float2 uv = float2(t, position.y * 0.001); // 二维坐标。
    float3 direction = normalize(float3(t, 0.4, 0.8)); // 视线方向。
    float3 sunDirection = normalize(float3(0.3, 0.2, -0.9)); // 太阳方向。
    float3 sunColor = float3(1.0, 0.92, 0.82); // 太阳颜色。
    OgxFog fog = ogxFogDefault(); // 雾参数。
    float nu = dot(direction, sunDirection); // 视线与阳光夹角。
    float3 acc = ogxFogDensity(fog, float3(uv, 0.01)) * direction; // 雾密度。
    acc += ogxFogPhase(nu) * direction; // 混合相位。
    acc += ogxFogPowder(0.5, nu) * direction; // 粉末效应。
    float4 fogResult = ogxFogMarch(fog, float3(0.0, 0.03, 0.0), float3(uv, 0.02), sunDirection, sunColor, t, 8); // 雾积分。
    acc += ogxFogApply(sunColor, fogResult); // 雾合成。
    return float4(acc, 1.0); // 有输出即可。
}
