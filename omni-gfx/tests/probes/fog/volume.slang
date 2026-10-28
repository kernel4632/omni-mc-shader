/*
体积雾模块编译探针：调用云影、暴风密度、雾密度、主循环与水下光柱。
调用位置：`omni-gfx/build.py spirv` 逐模块编译；探针只验证，不进入光影包。
设计原因与取舍：结构体全部用字面量填满，步数取小值加快编译；雾照明与手持光钩子保持未定义。
*/
Sampler2D probeNoise; // 噪声贴图。
Sampler2D probeShadow0; // 零号阴影深度。
Sampler2D probeShadow1; // 一号阴影深度。
Sampler2D probeShadowColor; // 半透明阴影颜色。
Sampler2D probeCloudShadow; // 云影贴图。

#include "../sampler_alias.slang"
#include "../../../src/fog/volume.slang"

[shader("fragment")]
float4 probeMain(float4 position : SV_Position) : SV_Target
{
    float t = position.x * 0.001 + 0.25; // 随像素变化的输入。
    OgxFogMedia media; // 一帧雾参数。
    media.camera_position = float3(0.0, 64.0, 0.0); // 相机位置。
    media.light_vector = normalize(float3(0.3, 0.2, -0.9)); // 光方向。
    media.light_color = float3(1.0, 0.95, 0.9); // 直射光。
    media.sky_color = float3(0.4, 0.5, 0.7); // 天空光。
    media.storm_color = float3(1.0); // 暴风染色。
    media.biome_color = float3(1.0); // 群系雾色。
    media.lightning_position = float3(0.0); // 没有闪电。
    media.shadow_view = float4x4(1.0); // 阴影视图。
    media.shadow_projection = float4x4(1.0); // 阴影投影。
    media.cloud_shadow_screen = float2(1920.0, 1080.0); // 云影画面尺寸。
    media.cloud_shadow_texel = float2(1.0 / 1920.0, 1.0 / 1080.0); // 像素大小。
    media.wetness = 0.0; // 干燥。
    media.eye_skylight = 1.0; // 天光。
    media.time_midnight = 0.0; // 午夜强度。
    media.time_factor = 1.0; // 时间因子。
    media.density_scale = 1.0; // 密度标度。
    media.base_density = 0.001; // 基础密度。
    media.storm_strength = 0.0; // 没有暴风。
    media.snow_storm = 0.0; // 雪暴强度。
    media.daily_fog = 0.0; // 每日匀雾。
    media.storm_density = 1.0; // 暴风浓度。
    media.storm_height = 60.0; // 暴风起始高度。
    media.storm_time = t; // 暴风滚动时间。
    media.wind_time = t; // 团雾移动时间。
    media.global_cloud_shadow = 1.0; // 全局云影。
    media.shadow_map_resolution = 2048.0; // 阴影图边长。
    media.shadow_bias = 0.9; // 阴影边缘压缩。
    media.cloud_shadow_range = 1024.0; // 云影范围。
    media.cloud_shadow_tex_size = 512.0; // 云影贴图边长。
    media.rain_shadow = 1.0; // 雨天云影底值。
    media.biome_coverage = 0.0; // 群系覆盖。
    media.biome_height = 1.0; // 群系高度雾。
    media.biome_cloudy = 1.0; // 群系团雾。
    media.lightning_intensity = 0.0; // 没有闪电事件。
    media.lightning_strength = 1.0; // 闪电亮度。
    media.sky_intensity = 1.0; // 天光强度。
    media.sun_intensity = 1.0; // 阳光强度。
    media.fog_density_option = 1.0; // 环境雾强度。
    media.sun_density_option = 1.0; // 散射强度。
    float density = ogxFogDensity(float3(0.0, 64.0, 10.0), float3(0.0), false, 60.0, 70.0, 10.0, 0.0, probeNoise); // 高度雾密度。
    density += ogxFogStormDensity(float3(0.0, 64.0, 10.0), media, probeNoise); // 暴风密度。
    float shadow = ogxFogCloudShadow(float3(0.0, 64.0, 10.0), media, probeCloudShadow, true); // 云影。
    float3 color = float3(density, shadow, ogxFogLightning(float3(0.0), media, 150.0, -15.0).x); // 基础量。
    float transmittance; // 透射率输出。
    ogxVolumetricFog(color, float3(0.0), float3(0.0, 0.0, -40.0), normalize(float3(0.0, 0.0, -1.0)), media, probeNoise,
        probeShadow0, probeShadow1, probeShadowColor, probeCloudShadow, false, false, false, false, false, false, false,
        60.0, 70.0, 10.0, 1.0, 2, 2, 1.0, t, transmittance); // 主循环。
    color += ogxUnderwaterFog(float3(0.0, 0.0, -1.0), float3(0.0, 0.0, -4.0), normalize(float3(0.0, 0.0, -1.0)), 1.0,
        float3(0.0, 64.0, 0.0), normalize(float3(0.3, 0.2, -0.9)), probeShadow0, probeShadow1, false,
        media.shadow_view, media.shadow_projection, 0.9, probeNoise, float2(1.0 / 1920.0, 1.0 / 1080.0), float2(1920.0, 1080.0),
        1024.0, 1.2, float3(1.0, 0.95, 0.9), 1.0, 1.0, 2, t, true, 1.0, 1.0); // 水下光柱。
    color += ogxUnderwaterCaustics(float3(0.0, 63.0, 0.0), normalize(float3(0.3, 0.2, -0.9)), probeNoise,
        float2(1.0 / 1920.0, 1.0 / 1080.0), float2(1920.0, 1080.0), 1024.0, 1.2) * float3(1.0); // 水下焦散。
    return float4(color, transmittance); // 有输出即可。
}
