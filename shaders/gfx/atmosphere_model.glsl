/*
预计算大气查表适配层：坐标映射、透过率、组合散射、辐照度与天空辐射已迁到生成库。
调用位置：`rendering/sky/atmosphere_model.glsl` 的同名转发函数引用本文件；
    阶段层只保留行星常数、贴图尺寸、天气与选项，算式只在 `omni-gfx/src/atmosphere_model.slang` 一份。
可复制示例：`vec3 sky = gfx_atmo_sky_radiance(model, lut, camera, dir, sunDir, moonDir, horizon, rTint, mTint, night, wetness, brightness, false, transmittance, intersectsGround);`
设计原因与取舍：函数名、参数顺序与结构体字段保持原样，宿主几十处逐字段赋值与调用点都不用改；
    贴图由调用方传入，库不绑定中间画面，也不读取任何选项宏。
    结构体用宏接上生成库的类型名，字段名因此仍然可用。
*/
#ifndef GFX_ATMOSPHERE_MODEL_INCLUDED
#define GFX_ATMOSPHERE_MODEL_INCLUDED

// 球面几何、相位函数、亮度与迁移后的查表实现。
#include "/gfx/atmosphere.glsl"
#include "/gfx/math.glsl"
#include "/gfx/color.glsl"
#include "/omni-gfx/atmosphere_model.glsl"

// 旧结构体名接到生成库的类型上，字段名与顺序完全一致。
#define gfx_atmosphere_model OgxAtmosphereModel

// 色适应矩阵的旧名字接到生成库的常量上，合成程序的雾散射继续可用。
#define GFX_ATMO_LMS OGX_ATMO_LMS

// 把半径夹进大气层范围内，越界时按最近的边界算。
float gfx_atmo_clamp_radius(gfx_atmosphere_model m, float r) { return ogxAtmoClampRadius(m, r); } // 实现在生成库。
// 视线到大气层顶的距离，解视线与顶球面的方程取远根。
float gfx_atmo_distance_to_top(gfx_atmosphere_model m, float r, float mu) { return ogxAtmoDistanceToTop(m, r, mu); } // 实现在生成库。
// 视线到大气层底的距离，解视线与底球面的方程取近根。
float gfx_atmo_distance_to_bottom(gfx_atmosphere_model m, float r, float mu) { return ogxAtmoDistanceToBottom(m, r, mu); } // 实现在生成库。
// 判断一条朝下的视线是否真的打到地面球。
bool gfx_atmo_ray_intersects_ground(gfx_atmosphere_model m, float r, float mu) { return ogxAtmoRayIntersectsGround(m, r, mu); } // 实现在生成库。
// 瑞利与米氏密度剖面：以二为底的指数衰减。
float gfx_atmo_density_rayleigh_mie(float exp_scale, float altitude) { return ogxAtmoDensityRayleighMie(exp_scale, altitude); } // 实现在生成库。
// 臭氧密度剖面：转折高度以下一段斜线，以上另一段斜线。
float gfx_atmo_density_absorption(float width, vec4 profile, float altitude) { return ogxAtmoDensityAbsorption(width, profile, altitude); } // 实现在生成库。
// 把零到一的比例映射到贴图像素中心，避免采到子图交界。
float gfx_atmo_texture_coord(float x, float texture_size) { return ogxAtmoTextureCoord(x, texture_size); } // 实现在生成库。
// 把子图内部比例映射到拼合大图坐标，子图在大图里也内缩半像素。
float gfx_atmo_combined_texture_coord(float x, float original_texture_size, float combined_texture_size) { return ogxAtmoCombinedTextureCoord(x, original_texture_size, combined_texture_size); } // 实现在生成库。
// 把半径与几个角度换成散射三维贴图的四维坐标。
vec4 gfx_atmo_scattering_uvwz(gfx_atmosphere_model m, float r, float mu, float mu_s, float nu, bool ray_r_mu_intersects_ground) { return ogxAtmoScatteringUvwz(m, r, mu, mu_s, nu, ray_r_mu_intersects_ground); } // 实现在生成库。
// 把半径与高度角换成透过率子图坐标。
vec2 gfx_atmo_transmittance_uv(gfx_atmosphere_model m, float r, float mu) { return ogxAtmoTransmittanceUv(m, r, mu); } // 实现在生成库。
// 查到层顶的透过率：透过率存在拼合大图的同一深度层上。
vec3 gfx_atmo_transmittance_to_top(gfx_atmosphere_model m, sampler3D lut, float r, float mu) { return ogxAtmoTransmittanceToTop(m, lut, r, mu); } // 实现在生成库。
// 两点之间的透过率：由两端到层顶的透过率相除得到，地面相交时用镜像方向。
vec3 gfx_atmo_transmittance(gfx_atmosphere_model m, sampler3D lut, float r, float mu, float d, bool ray_r_mu_intersects_ground) { return ogxAtmoTransmittance(m, lut, r, mu, d, ray_r_mu_intersects_ground); } // 实现在生成库。
// 从某点朝太阳方向到层顶的透过率，太阳贴地时按太阳视半径留一段过渡。
vec3 gfx_atmo_transmittance_to_sun(gfx_atmosphere_model m, sampler3D lut, float r, float mu_s) { return ogxAtmoTransmittanceToSun(m, lut, r, mu_s); } // 实现在生成库。
// 从拼合散射数据反推单次米氏散射：按通道比例还原。
vec3 gfx_atmo_extrapolated_mie(gfx_atmosphere_model m, vec4 scattering) { return ogxAtmoExtrapolatedMie(m, scattering); } // 实现在生成库。
// 查组合散射：先在夹角方向插值两片，再拆出单次米氏散射。
vec3 gfx_atmo_combined_scattering(gfx_atmosphere_model m, sampler3D lut, float r, float mu, float mu_s, float nu, bool ray_r_mu_intersects_ground, out vec3 single_mie_scattering) { return ogxAtmoCombinedScattering(m, lut, r, mu, mu_s, nu, ray_r_mu_intersects_ground, single_mie_scattering); } // 实现在生成库。
// 查辐照度：给出某个高度朝上接到的太阳与环境辐照度。
vec3 gfx_atmo_irradiance(gfx_atmosphere_model m, sampler3D lut, float r, float mu_s) { return ogxAtmoIrradiance(m, lut, r, mu_s); } // 实现在生成库。
// 算某点的太阳、月亮与天空辐照度：太阳和月亮各出一份直射与一份环境。
vec3 gfx_atmo_sun_sky_irradiance(gfx_atmosphere_model m, sampler3D lut, vec3 point, vec3 sun_direction, vec3 moon_direction,
		float night_brightness, vec3 sun_tint, out vec3 moon_irradiance,
		out vec3 sun_sky_irradiance, out vec3 moon_sky_irradiance) {
	return ogxAtmoSunSkyIrradiance(m, lut, point, sun_direction, moon_direction, night_brightness, sun_tint,
		moon_irradiance, sun_sky_irradiance, moon_sky_irradiance); // 实现在生成库。
}
// 算某个视线方向的天空辐射亮度：日月散射、可选的地面反弹，再乘天气修正。
vec3 gfx_atmo_sky_radiance(gfx_atmosphere_model m, sampler3D lut, vec3 camera, vec3 view_ray, vec3 sun_direction,
		vec3 moon_direction, bool horizon, vec3 rayleigh_tint, vec3 mie_tint,
		float night_brightness, float wetness, float sky_brightness, bool ground_bounce,
		out vec3 transmittance, out bool ray_r_mu_intersects_ground) {
	return ogxAtmoSkyRadiance(m, lut, camera, view_ray, sun_direction, moon_direction, horizon, rayleigh_tint,
		mie_tint, night_brightness, wetness, sky_brightness, ground_bounce, transmittance, ray_r_mu_intersects_ground); // 实现在生成库。
}
// 算相机到某个世界点之间的天空辐射亮度，体积云与平面云算空气透视时用。
vec3 gfx_atmo_sky_radiance_to_point(gfx_atmosphere_model m, sampler3D lut, vec3 camera, vec3 point, vec3 sun_direction,
		vec3 moon_direction, bool local_lighting, vec3 rayleigh_tint, vec3 mie_tint,
		float night_brightness, float wetness, float sky_brightness, out vec3 transmittance) {
	return ogxAtmoSkyRadianceToPoint(m, lut, camera, point, sun_direction, moon_direction, local_lighting,
		rayleigh_tint, mie_tint, night_brightness, wetness, sky_brightness, transmittance); // 实现在生成库。
}

// 简化的单次散射：沿阳光方向取四段估光学厚度，算出这段空气加到视线上的散射色。
vec3 gfx_atmo_simple_scattering(gfx_atmosphere_model m, vec3 camera, vec3 world_dir, float dist, float shadow_dist, vec3 light_vector) {
	return ogxAtmoSimpleScattering(m, camera, world_dir, dist, shadow_dist, light_vector); // 实现在生成库。
}

#endif
