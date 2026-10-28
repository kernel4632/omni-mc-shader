/*
反射模块编译探针：调用可见法线采样、深度换算、屏幕空间追踪、方向生成与小波滤波。
调用位置：`omni-gfx/build.py spirv` 逐模块编译；探针只验证，不进入光影包。
设计原因与取舍：输入随像素变化，避免常量折叠掩盖类型问题；采样器只做类型检查。
*/
#include "../../../src/reflection/reflection.slang"

Sampler2D gProbeTexture; // 探针用的占位纹理，只为让采样器参数通过类型检查。

[shader("fragment")]
float4 probeMain(float4 position : SV_Position) : SV_Target
{
    float t = position.x * 0.001 + 0.25; // 随像素变化的输入。
    float2 coord = float2(t, position.y * 0.002); // 画面坐标。
    float4x4 identity = float4x4(1.0); // 单位矩阵。
    float3 viewDir = normalize(float3(t, 0.2, 1.0)); // 视线方向。
    float3 normal = normalize(float3(0.0, 1.0, 0.1)); // 表面法线。
    float3 ggx = ogxSampleGgxVndf(viewDir, 0.4, float2(0.3, 0.6)); // 可见法线采样。
    float3 viewPos = ogxReflectionViewPos(coord, 0.5, identity); // 还原视空间位置。
    float3 screenPos = ogxReflectionScreenPos(viewPos + float3(0.0, 1.0, 1.0), identity); // 投到屏幕。
    float linear = ogxLinearDepthFromScreenDepth(0.5, identity); // 深度换米制。
    float screen = ogxScreenDepthFromLinearDepth(linear + 1.0, identity); // 换回深度。
    float dh = ogxScreenDepthFromDistantScreenDepth(0.5, identity, identity); // 远景深度换算。
    float3 dir = ogxReflectionDir(viewDir, normal, 0.2, float2(0.4, 0.5), false); // 反射方向。
    float3 scene = ogxReflectionSceneColor(gProbeTexture, coord); // 场景颜色。
    float facing = ogxReflectionSkyFacing(normal.y); // 天空朝向权重。
    float3 mixed = scene; // 混合结果。
    ogxSpecularReflectionMix(mixed, viewDir, normal, float3(0.3, 0.4, 0.2), 0.6, ggx, true, 0.0, 0.2, 0.04, 0.5, true); // 菲涅耳合并。
    float4 data = float4(scene, 0.5); // 反射数据。
    ogxReflectionAtrousFilter(data, viewPos, viewDir, normal, 0.2, 8.0, float2(0.5), coord, gProbeTexture, gProbeTexture, gProbeTexture, float2(0.001), identity); // 小波滤波。
    float3 result = ggx + screenPos + scene + dir + float3(linear + screen + dh + facing, 0.0, 0.0) + mixed + data.rgb; // 汇总输出。
    return float4(result, 1.0); // 有输出即可。
}
