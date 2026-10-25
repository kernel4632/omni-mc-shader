/*
天气模块编译探针：调用雨雪偏移、季节上色、暴风噪声与颜色、每日天气哈希。
调用位置：`omni-gfx/build.py spirv` 逐模块编译；探针只验证，不进入光影包。
设计原因与取舍：输入用屏幕坐标构造，避免常量折叠掩盖类型问题；不追求画面正确。
*/
Sampler2D probeTex2D; // 全局纹理声明：探针只需要类型，不需要真实绑定。
#include "../../src/weather.slang"

[shader("fragment")]
float4 probeMain(float4 position : SV_Position) : SV_Target
{
    float t = position.x * 0.001 + 0.25; // 随像素变化的输入。
    float2 uv = float2(t, position.y * 0.001); // 二维坐标。
    float3 p = float3(t, uv.y, 0.5); // 三维位置。
    float3 c = float3(ogxRainWindOffset(p, p, t, uv, 0.05, 1.0), 0.0); // 雨雪偏移。
    c += ogxSeason(float3(0.4, 0.6, 0.3), float3(0.2, 0.9, 0.2), t, 0.2, true); // 季节上色。
    c += ogxFoliage(float3(0.2, 0.9, 0.2)); // 植被程度。
    c += ogxStormNoise(p, probeTex2D, 512.0); // 暴风噪声。
    c += ogxStormColor(0.4, 0.2); // 暴风颜色。
    c += ogxWeatherHash11(t * 20.0); // 每日天气哈希。
    return float4(c, 1.0); // 有输出即可。
}
