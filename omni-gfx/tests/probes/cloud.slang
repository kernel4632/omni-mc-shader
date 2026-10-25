/*
云模块编译探针：调用云层默认值、密度、光照、沿视线步进与云影。
调用位置：`omni-gfx/build.py spirv` 逐模块编译；探针只验证，不进入光影包。
设计原因与取舍：输入用屏幕坐标构造，避免常量折叠掩盖类型问题；不追求画面正确。
*/
#include "../../src/cloud.slang"

[shader("fragment")]
float4 probeMain(float4 position : SV_Position) : SV_Target
{
    float t = position.x * 0.001 + 0.25; // 随像素变化的输入。
    float2 uv = float2(t, position.y * 0.001); // 二维坐标。
    float3 direction = normalize(float3(t, 0.4, 0.8)); // 视线方向。
    float3 sunDirection = normalize(float3(0.3, 0.2, -0.9)); // 太阳方向。
    float3 sunColor = float3(1.0, 0.92, 0.82); // 太阳颜色。
    OgxCloudLayer layer = ogxCloudLayerDefault(); // 云层参数。
    layer.coverage = t; // 让云量随像素变化。
    float3 acc = ogxCloudDensity(layer, float3(uv, 0.18), true) * direction; // 云密度。
    acc += ogxCloudLight(layer, float3(uv, 0.18), sunDirection, 4) * direction; // 云光照。
    acc += ogxCloudMarch(layer, float3(0.0, 0.03, 0.0), direction, sunDirection, sunColor, sunColor * 0.2, t, 12).rgb; // 云步进。
    acc += ogxCloudShadow(layer, float3(uv, 0.02), sunDirection) * direction; // 云影。
    acc += ogxCloudRainDensity(t, 0.5, 0.2) * direction; // 降雨对云量的加成。
    return float4(acc, 1.0); // 有输出即可。
}
