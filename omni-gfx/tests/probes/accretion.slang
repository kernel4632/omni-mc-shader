/*
吸积盘模块编译探针：调用黑洞附近的步进积分。
调用位置：`omni-gfx/build.py spirv` 逐模块编译；探针只验证，不进入光影包。
设计原因与取舍：方向由屏幕坐标构造，噪声贴图只需要类型；只验证主循环能编译。
*/
Sampler2D probeTex2D; // 全局纹理声明：探针只需要类型，不需要真实绑定。
#include "../../src/accretion.slang"

[shader("fragment")]
float4 probeMain(float4 position : SV_Position) : SV_Target
{
    float t = position.x * 0.001 + 0.25; // 随像素变化的输入。
    float3 dir = normalize(float3(t, position.y * 0.001, 0.8)); // 视线方向。
    float4 disc = ogxAccretionDisc(dir, normalize(float3(0.3, 0.2, -0.9)), t, probeTex2D, t * 10.0, 8, 3.0, 4, false, true); // 吸积盘积分。
    return disc; // 返回盘颜色与透过率即可。
}
