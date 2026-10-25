/*
噪声模块编译探针：调用哈希、值噪声、分形与域扭曲，供 Slang 做完整类型检查。
调用位置：`omni-gfx/build.py spirv` 逐模块编译；探针只验证，不进入光影包。
设计原因与取舍：输入用屏幕坐标构造，避免常量折叠掩盖类型问题；不追求画面正确。
*/
#include "../../src/noise.slang"

[shader("fragment")]
float4 probeMain(float4 position : SV_Position) : SV_Target
{
    float t = position.x * 0.001 + 0.25; // 随像素变化的输入。
    float2 uv = float2(t, position.y * 0.001); // 二维坐标。
    float3 p = float3(uv, t); // 三维坐标。
    float3 acc = float3(ogxHash13(p), ogxHash12(uv), ogxHash13(p.yzx)); // 两种哈希。
    acc += float3(ogxValueNoise3(p), ogxValueNoise2(uv), 0.0); // 两种值噪声。
    acc += float3(ogxFbm2(uv, 4), ogxFbm3(p, 3), 0.0); // 两种分形。
    acc += ogxWarp3(p, 0.5); // 域扭曲。
    acc += float3(ogxWhiteNoise(uv), ogxWhiteNoiseTemporal(uv, t), ogxTriangleNoise(uv, t)); // 白噪声的三种用法。
    return float4(acc, 1.0); // 有输出即可。
}
