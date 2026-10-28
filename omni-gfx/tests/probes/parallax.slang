/*
视差模块编译探针：调用高度采样、两套步进与法线处理。
调用位置：`omni-gfx/build.py spirv` 逐模块编译；探针只验证，不进入光影包。
设计原因与取舍：切线基用单位轴，输入用屏幕坐标构造；只验证类型与分支，不追求画面。
*/
Sampler2D probeTex2D; // 全局纹理声明：探针只需要类型。

#include "../../src/parallax.slang"

[shader("fragment")]
float4 probeMain(float4 position : SV_Position) : SV_Target
{
    float t = position.x * 0.001 + 0.25; // 随像素变化的输入。
    int2 base = int2(0, 0); // 图块左上角。
    float height = ogxBilinearHeightSample(float2(t, t), base, 16.0, 15, true, probeTex2D); // 双线性高度。
    float3 normal = ogxHeightBasedNormal(float2(t, t), base, 16.0, 15, true, probeTex2D, 40.0); // 高度场法线。
    float3 tangent = float3(1.0, 0.0, 0.0); // 切线。
    float3 bitangent = float3(0.0, 1.0, 0.0); // 副切线。
    float3 axis = float3(0.0, 0.0, 1.0); // 法线。
    float3 viewPos = float3(0.0, 0.0, 4.0); // 视空间位置。
    float2 duv1 = float2(0.01, 0.0); // 纹理坐标的横向导数。
    float2 duv2 = float2(0.0, 0.01); // 纹理坐标的纵向导数。
    float shadow = 1.0; // 阴影初值。
    int2 texel = ogxParallaxSmooth(float2(t, t), tangent, bitangent, axis, float3(0.2, 0.2, -1.0), duv1, duv2, viewPos,
        probeTex2D, probeTex2D, float2(256.0, 256.0), 16.0, true, 40.0, 12, 4, 20, true, true, false, int2(0, 0), 1, 1, normal, shadow); // 平滑步进入口。
    int2 sharpTexel = ogxParallaxSharp(float2(t, t), tangent, bitangent, axis, float3(0.2, 0.2, -1.0), duv1, duv2, viewPos,
        probeTex2D, float2(256.0, 256.0), 16.0, true, 40.0, 12, 20, true, true, 1, normal, shadow); // 锐利步进入口。
    float3 c = normal + float3(height) + ogxParallaxHitNormal(probeTex2D, texel, normal, 1.0, true, 1); // 法线处理。
    return float4(c + float3(float2(texel), 0.0) + float3(float2(sharpTexel), 0.0), 1.0); // 有输出即可。
}
