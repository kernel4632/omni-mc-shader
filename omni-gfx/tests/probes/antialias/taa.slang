/*
时间取样模块编译探针：调用远景深度到近景深度的换算入口。
调用位置：`omni-gfx/build.py spirv` 逐模块编译；探针只验证类型与分支，不进入光影包。
设计原因与取舍：用单位矩阵验证函数签名与单位换算，不构造完整历史缓冲。
*/
#include "../../../src/antialias/taa.slang"

[shader("fragment")]
float4 probeMain(float4 position : SV_Position) : SV_Target
{
    float t = position.x * 0.001 + 0.25; // 随像素变化的输入。
    float depth = ogxScreenDepthFromDistantScreenDepth(t, float4x4(1.0), float4x4(1.0)); // 远景深度换成近景尺度。
    return float4(depth, t, 0.0, 1.0); // 合成一个可编译的返回。
}
