/*
水面模块编译探针：调用波法线、菲涅尔、吸收、折射偏移、泡沫与水面着色。
调用位置：`omni-gfx/build.py spirv` 逐模块编译；探针只验证，不进入光影包。
设计原因与取舍：输入用屏幕坐标构造，避免常量折叠掩盖类型问题；不追求画面正确。
*/
#include "../../src/water.slang"

[shader("fragment")]
float4 probeMain(float4 position : SV_Position) : SV_Target
{
    float t = position.x * 0.001 + 0.25; // 随像素变化的输入。
    float2 uv = float2(t, position.y * 0.001); // 二维坐标。
    float3 direction = normalize(float3(t, 0.4, 0.8)); // 视线方向。
    float3 sunDirection = normalize(float3(0.3, 0.2, -0.9)); // 太阳方向。
    float3 sunColor = float3(1.0, 0.92, 0.82); // 太阳颜色。
    OgxWater water = ogxWaterDefault(); // 水面参数。
    float3 normal = ogxWaterNormal(uv, t, 40.0, 1.0, 1.0); // 波法线。
    float alpha; // 水面透明度。
    float3 acc = normal + ogxWaterFresnel(0.7, 0.02) * direction; // 法线与菲涅尔。
    acc += ogxWaterAbsorption(water, 4.0); // 吸收。
    acc += float3(ogxWaterRefractionOffset(normal, 3.0, 40.0, water.refraction), 0.0); // 折射偏移。
    acc += ogxWaterFoam(0.3, ogxValueNoise2(uv)) * direction; // 泡沫。
    acc += ogxWaterShade(water, normal, direction, sunDirection, sunColor, sunColor, sunColor * 0.2, 4.0, 0.1, alpha); // 水面着色。
    return float4(acc, 1.0); // 有输出即可。
}
