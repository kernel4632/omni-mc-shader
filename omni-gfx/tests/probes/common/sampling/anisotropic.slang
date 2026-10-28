/*
Omni 通用图形库 sampling/anisotropic 模块编译探针：覆盖各向异性过滤入口。
调用位置：`omni-gfx/build.py spirv` 逐模块编译；探针只验证类型与函数调用，不进入光影包。
*/
Sampler2D probeTexture; // 编译期纹理句柄，由调用方绑定。

#include "../../slang_compat.slang"
#include "../../../../src/common/sampling/anisotropic.slang"

[shader("fragment")]
float4 probeMain(float4 position : SV_Position) : SV_Target
{
    float t = position.x * 0.001 + 0.25; // 随像素变化的输入。
    float3 normal = float3(0.0, 0.0, 1.0); // 切线法线输出。
    float4 specular = float4(1.0); // 材质输出。
    float materialAo = 1.0; // 材质遮蔽输出。
    float4 color = ogxSampleAnisotropic(probeTexture, probeTexture, probeTexture, float2(t, t),
        float2(0.01, 0.0), float2(0.0, 0.01), float2(256.0), 256.0, 4, true, true, true, true, normal, specular, materialAo); // 各向异性过滤。
    return float4(color.rgb + normal, 1.0); // 有输出即可。
}
