/*
阴影模块编译探针：调用投影、边缘压缩、级联选择、PCSS 与软阴影。
调用位置：`omni-gfx/build.py spirv` 逐模块编译；探针只验证，不进入光影包。
设计原因与取舍：矩阵用单位阵与平移构造，输入随像素变化，避免常量折叠掩盖类型问题。
    采样器版本的函数只做类型检查（函数体在编译期全部检查），探针不真的采样。
*/
#include "../../../src/shadow/shadow.slang"

[shader("fragment")]
float4 probeMain(float4 position : SV_Position) : SV_Target
{
    float t = position.x * 0.001 + 0.25; // 随像素变化的输入。
    float4x4 view = float4x4(1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0); // 单位视图矩阵。
    view[3] = float4(4.0, 5.0, 6.0, 1.0); // 平移列，用来验证平移提取。
    float4x4 projection = float4x4(0.5, 0.0, 0.0, 0.0, 0.0, 0.5, 0.0, 0.0, 0.0, 0.0, -0.5, 0.0, 0.0, 0.0, 0.0, 1.0); // 正交投影。
    float3 worldPosition = float3(t, 1.0, 2.0); // 世界位置。
    float3 shadowPosition = ogxShadowScreenPos(worldPosition, view, projection); // 不做压缩的投影。
    float3 distorted = ogxShadowScreenPosDistorted(worldPosition, view, projection, 0.9); // 带边缘压缩的投影。
    float2 restored = ogxDistortShadowPos(distorted.xy, 0.9); // 读取端补压缩。
    float linearDepth = ogxShadowLinearDepth(0.5, view); // 屏幕深度换米制。
    OgxCascadeSelect cascade = ogxSelectCascade(t * 200.0, float3(32.0, 64.0, 128.0), 6.0); // 级联选择。
    float radius = ogxPcssFilterRadius(0.4, 0.5, 12.0, 40.0); // 半影半径。
    float3 result = shadowPosition + distorted + float3(restored, linearDepth);
    result += float3(float(cascade.index), float(cascade.next), cascade.weight); // 级联结果也参与输出。
    result += float3(radius, 0.0, 0.0); // 半影半径。
    return float4(result, 1.0); // 有输出即可。
}
