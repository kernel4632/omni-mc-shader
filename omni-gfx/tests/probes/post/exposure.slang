/*
Omni 通用图形库 post/exposure 模块编译探针：覆盖该效果的主要入口。
调用位置：`omni-gfx/build.py spirv` 逐模块编译；探针只验证类型与函数调用，不进入光影包。
*/
Sampler2D probeTexture; // 编译期纹理句柄，由调用方绑定。

#include "../../../src/post/exposure.slang"

[shader("fragment")]
float4 probeMain(float4 position : SV_Position) : SV_Target
{
    float t = position.x * 0.001 + 0.25; // 随像素变化的输入。
    float ev = ogxGetExposureValue(probeTexture, int2(0), false, t, 1.0, 1.0, 1.0, 0.0, true, false, 0.0, 0.0, true); // 自动曝光值。
    return float4(ev, t, 0.0, 1.0); // 有输出即可。
}
