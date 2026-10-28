/*
相机模块编译探针：调用深度还原、视空间与屏幕空间互转以及裁剪空间投影。
调用位置：`omni-gfx/build.py spirv` 逐模块编译；探针只验证类型与分支，不进入光影包。
设计原因与取舍：用单位矩阵和稳定的小参数覆盖重载，确保模块能被 Slang 编译器解析。
*/
#include "../../../src/common/camera.slang"

[shader("fragment")]
float4 probeMain(float4 position : SV_Position) : SV_Target
{
    float t = position.x * 0.001 + 0.25; // 随像素变化的输入。
    float4x4 m = float4x4(1.0); // 单位矩阵代替真实相机。
    float3 view = ogxViewPosFromScreenPos(float2(t, t), t, float2(0.0), 0.5, m, false); // 深度还原视空间位置。
    float3 screen = ogxScreenPosFromViewPos(view, float2(0.0), 0.5, m, false); // 视空间投回屏幕。
    float3 clip = ogxProjectAndDivide(m, view); // 裁剪空间投影。
    return float4(screen + clip, 1.0); // 合成一个可编译的返回。
}
