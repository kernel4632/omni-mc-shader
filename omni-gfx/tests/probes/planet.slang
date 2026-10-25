/*
行星模块编译探针：调用末地行星本体、光环与大气。
调用位置：`omni-gfx/build.py spirv` 逐模块编译；探针只验证，不进入光影包。
设计原因与取舍：方向由屏幕坐标构造，噪声贴图只需要类型。
*/
Sampler2D probeTex2D; // 全局纹理声明：探针只需要类型，不需要真实绑定。
#include "../../src/planet.slang"

[shader("fragment")]
float4 probeMain(float4 position : SV_Position) : SV_Target
{
    float t = position.x * 0.001 + 0.25; // 随像素变化的输入。
    float3 color = float3(0.0); // 初始天空。
    float3 dir = normalize(float3(t, position.y * 0.001, 0.8)); // 视线方向。
    ogxPlanetEnd(color, float3(0.0, 0.0, 0.0), dir, normalize(float3(0.3, 0.2, -0.9)), dir, t * 10.0, 0.5, probeTex2D); // 行星本体。
    return float4(color, 1.0); // 有输出即可。
}
