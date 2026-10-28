/*
层状体积云模块的编译探针：调用哈希、旋度、行星阴影与相函数。
调用位置：`omni-gfx/build.py spirv` 逐模块编译；不进入光影包，也不单独运行。
设计原因与取舍：只调用少量入口，确认模块能被 Slang 编译器解析并生成 SPIR-V。
*/
#include "../../../src/cloud/layers.slang"

[shader("fragment")]
float4 probeMain(float4 position : SV_Position) : SV_Target
{
    float t = position.x * 0.001 + 0.25; // 取一个稳定的小参数。
    float2 hash = ogxLayersHash2(float2(t, t * 2.0)); // 哈希入口。
    float2 curl = ogxLayersCurl2D(float2(t, t * 3.0)); // 旋度入口。
    float planet = ogxLayersGetPlanetShadow(float3(t, 10.0, 0.0), normalize(float3(0.2, 0.5, 0.3))); // 行星阴影入口。
    float phase = ogxLayersPhaseCloud(t, 0.6, 0); // 相函数入口。
    return float4(hash + curl + planet + phase, 1.0); // 合成一个可编译的返回。
}
