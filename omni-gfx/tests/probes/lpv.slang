/*
光传播体积模块编译探针：调用取样解码、写入编码、亮度曲线、坐标映射、边缘淡出与合成。
调用位置：`omni-gfx/build.py spirv` 逐模块编译；探针只验证类型与算式，不进入光影包。
设计原因与取舍：
    输入随像素变化，避免常量折叠把类型错误藏起来；模块不碰纹理，探针也就不需要绑定。
    编码与解码成对调用，任何一边改了签名都会在这里编译失败。
*/
#include "sampler_alias.slang"
#include "../../src/lpv.slang"

[shader("fragment")]
float4 probeMain(float4 position : SV_Position) : SV_Target
{
    float t = position.x * 0.001 + 0.25; // 随像素变化的时间量。
    float4 stored = float4(t, 0.5, 0.25, 0.75); // 假装从三维图取到的一个样本。
    float4 decoded = ogxLpvDecodeSample(stored, float2(15.0, 24.0)); // 片元取样解码。
    float4 encoded = ogxLpvEncode(decoded, float2(15.0, 24.0)); // 写入端编码。
    float4 again = ogxLpvDecode(encoded, float2(15.0, 24.0)); // 传播阶段读回解码。
    float3 block = ogxLpvBlockLight(decoded); // 彩色方块光。
    float sky = ogxLpvSkyLight(decoded); // 天光。
    float3 pos = ogxLpvPosition(float3(t, 0.0, 0.0), float3(0.5), 32.0); // 搬进体积中心。
    float3 uvw = ogxLpvUvw(pos, 64.0); // 归一化纹理坐标。
    float falloff = ogxLpvRangeFalloff(pos, 64.0, 10.0); // 边缘淡出。
    float3 light = ogxLpvApply(block, again, falloff, 1.0); // 混回方块光。
    return float4(light + float3(sky, uvw.x, ogxLpvCurve(t)), 1.0); // 汇总全部结果。
}
