/*
大气查表模块编译探针：调用坐标映射、透过率、散射、辐照度与简化散射。
调用位置：`omni-gfx/build.py spirv` 逐模块编译；探针只验证，不进入光影包。
设计原因与取舍：结构体全部用字面量填满，避免依赖宿主常数；三维贴图只声明不绑定。
*/
Sampler3D probeLut; // 全局纹理声明：探针只需要类型。

#include "../../src/atmosphere_model.slang"

[shader("fragment")]
float4 probeMain(float4 position : SV_Position) : SV_Target
{
    float t = position.x * 0.001 + 0.25; // 随像素变化的输入。
    OgxAtmosphereModel m; // 查表参数。
    m.bottom_radius = 6360.0; // 行星底半径。
    m.top_radius = 6420.0; // 大气层顶。
    m.sun_angular_radius = 0.01; // 太阳视半径。
    m.mie_phase_g = 0.8; // 米氏集中程度。
    m.mu_s_min = -0.2; // 太阳高度角下限。
    m.solar_irradiance = float3(1.0, 0.98, 0.96); // 太阳辐照度。
    m.rayleigh_scattering = float3(0.0058, 0.0135, 0.0331); // 瑞利散射。
    m.mie_scattering = float3(0.004, 0.004, 0.004); // 米氏散射。
    m.absorption_extinction = float3(0.00065, 0.00188, 0.000085); // 臭氧吸收。
    m.density_rayleigh = -1.0 / 8.0; // 瑞利密度衰减。
    m.density_mie = -1.0 / 1.2; // 米氏密度衰减。
    m.absorption_width = 25.0; // 臭氧转折高度。
    m.density_absorption = float4(1.0, 0.0, 0.0, 0.0); // 臭氧剖面。
    m.transmittance_width = 256.0; // 透过率子图宽度。
    m.transmittance_height = 64.0; // 透过率子图高度。
    m.scattering_r = 32.0; // 半径方向尺寸。
    m.scattering_mu = 63.0; // 高度角尺寸。
    m.scattering_mu_s = 32.0; // 太阳高度角尺寸。
    m.scattering_nu = 8.0; // 夹角尺寸。
    m.combined_width = 1024.0; // 拼合大图宽度。
    m.combined_height = 256.0; // 拼合大图高度。
    m.combined_depth = 32.0; // 拼合大图深度。
    m.irradiance_width = 64.0; // 辐照度子图宽度。
    m.irradiance_height = 16.0; // 辐照度子图高度。
    float3 origin = float3(0.0, 6360.03, 0.0); // 相机在行星正上方。
    float3 dir = normalize(float3(t, 0.4, 0.8)); // 视线方向。
    float3 sun = normalize(float3(0.3, 0.2, -0.9)); // 太阳方向。
    float3 moon = -sun; // 月亮方向。
    float3 transmittance; // 透过率输出。
    bool intersectsGround; // 是否打到地面。
    float3 acc = ogxAtmoTransmittanceToTop(m, probeLut, 6360.03, 0.4); // 到层顶的透过率。
    acc += ogxAtmoIrradiance(m, probeLut, 6360.03, 0.2); // 辐照度。
    acc += ogxAtmoSkyRadiance(m, probeLut, origin, dir, sun, moon, true, float3(1.0), float3(1.0), 0.2, 0.0, 1.0, false, transmittance, intersectsGround); // 天空辐射。
    acc += ogxAtmoSkyRadianceToPoint(m, probeLut, origin, origin + dir * 2.0, sun, moon, false, float3(1.0), float3(1.0), 0.2, 0.0, 1.0, transmittance); // 到点辐射。
    acc += ogxAtmoSimpleScattering(m, origin, dir, 1.0, 1.0, sun); // 简化散射。
    return float4(acc, 1.0); // 有输出即可。
}
