/*
体积云模块编译探针：调用云坐标、密度采样、光照、步进与云影贴图。
调用位置：`omni-gfx/build.py spirv` 逐模块编译；探针只验证，不进入光影包。
设计原因与取舍：结构体全部用字面量填满，三维纹理只声明不绑定；步数取小值加快编译。
*/
Sampler3D probeBase; // 基础云噪声。
Sampler3D probeDetail; // 细节云噪声。
Sampler2D probeCurl; // 卷曲噪声。

#include "../../../src/cloud/volume.slang"

[shader("fragment")]
float4 probeMain(float4 position : SV_Position) : SV_Target
{
    float t = position.x * 0.001 + 0.25; // 随像素变化的输入。
    OgxCumulusMedia media; // 一层云的参数。
    media.wind = float3(t, 0.0, 0.0); // 风向。
    media.camera_position = float3(0.0, 100.0, 0.0); // 相机位置。
    media.light_color = float3(1.0, 0.95, 0.9); // 直射光。
    media.sky_color = float3(0.4, 0.5, 0.7); // 天空光。
    media.lightning_position = float3(0.0); // 没有闪电。
    media.altitude = float2(200.0, 400.0); // 云层高度。
    media.lighting_strength = float2(1.0, 1.0); // 光照强度。
    media.planet_radius = 6360000.0; // 行星半径。
    media.cloud_scale = 1.0; // 云块尺度。
    media.density_option = 1.0; // 密度倍率。
    media.coverage = 0.4; // 云量。
    media.wetness = 0.0; // 干燥。
    media.bottom_brightness = 0.2; // 云底亮度。
    media.outscatter_factor = 1.0; // 外散射指数。
    media.lightning_intensity = 0.0; // 没有闪电事件。
    media.lightning_strength = 1.0; // 闪电亮度。
    float4 cloudPos = ogxCumulusSetPos(float3(0.0, 300.0, 0.0), media); // 云坐标。
    float2 density = ogxCumulusSampleDensity(cloudPos, media, true, media.coverage, probeBase, probeDetail, probeCurl, 1.0, 0.0, 1.0, 1.0); // 密度采样。
    float3 hitOffset; // 平均命中位置。
    float4 layer = ogxCumulusMarch(normalize(float3(t, 0.2, 0.8)), media, float2(t, 0.5), hitOffset, probeBase, probeDetail, probeCurl, 4.0, 0.5, normalize(float3(0.3, 0.2, -0.9)), 1.0, 0.0, 1.0, 1.0); // 步进。
    float shadow = ogxCumulusShadowTex(float2(t, t), media, normalize(float3(0.3, 0.2, -0.9)), 1000.0, probeBase, probeCurl, 1.0, 0.0, 1.0, 1.0); // 云影。
    float3 c = ogxCumulusLightning(hitOffset, media, 400.0, -10.0) + ogxCurve01(t) * density.y; // 闪电与曲线。
    return float4(layer.rgb + c + float3(shadow), layer.a); // 有输出即可。
}
