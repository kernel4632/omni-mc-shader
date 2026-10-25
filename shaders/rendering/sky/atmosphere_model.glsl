/*
预计算大气：把 iterationT `Lib/BasicFounctions/PrecomputedAtmosphere.glsl` 的查表接口留在阶段层，
    公式本身在 `gfx/atmosphere_model.glsl`。这里只把加载器输入、选项与贴图尺寸填进通用结构体。
调用位置：由 `rendering/sky/sky.glsl` 在选项与内部常数之后引入；延迟三号、七号、八号与合成顶点都经它查天空辐射。
可复制示例：
    `vec3 atmosphere = GetSkyRadiance(camera, worldDir, worldSunVector, worldMoonVector, horizon, transmittance, ray_r_mu_intersects_ground);`
    `vec3 sunIrradiance = GetSunAndSkyIrradiance(camera, worldSunVector, -worldSunVector, moonIrradiance, sunSkyIrradiance, moonSkyIrradiance);`
调用前提：`atmosphereModel_*` 常数与贴图尺寸常数由 `rendering/sky/sky.glsl` 定义；太阳色倍率由 `rendering/sky/suncolor.glsl` 提供；
    天空散射倍率由 `rendering/sky/skyscatter.glsl` 提供；当前天气湿润度 `wetness` 由加载器声明文件提供。
设计原因与取舍：读预计算三维贴图，不实时积分，代价与分辨率无关；本文件保持原函数名与签名，调用点无需改动。
    贴图在一点一六点五以后挂八号画面，更早版本挂二号深度，所以统一用 `OMNI_ATMO_LUT` 选一次采样器。
*/
#ifndef OMNI_RENDER_SKY_ATMOSPHERE_MODEL_INCLUDED
#define OMNI_RENDER_SKY_ATMOSPHERE_MODEL_INCLUDED
// 查表公式、球面几何与相位函数都在通用库；本文件只填参数与选贴图。
#include "/gfx/atmosphere_model.glsl"

// 一点一六点五以后大气数据挂在八号画面，更早的版本挂在二号深度上；只能整段选一个采样器。
#if MC_VERSION >= 11605
	#define OMNI_ATMO_LUT colortex8 // 新版本读八号画面的三维大气数据。
#else
	#define OMNI_ATMO_LUT depthtex2 // 旧版本读二号深度上的大气数据。
#endif

// 把当前阶段的常数与贴图尺寸打包成通用结构体：数值全部来自 `rendering/sky/sky.glsl`，不在这里另存一份默认值。
gfx_atmosphere_model omniAtmosphereModel(){
	gfx_atmosphere_model m; // 待填充的查表参数。
	m.bottom_radius = atmosphereModel_bottom_radius; // 行星底半径。
	m.top_radius = atmosphereModel_top_radius; // 大气层顶半径。
	m.sun_angular_radius = atmosphereModel_sun_angular_radius; // 太阳视半径。
	m.mie_phase_g = atmosphereModel_mie_phase_function_g; // 米氏相位集中程度。
	m.mu_s_min = atmosphereModel_mu_s_min; // 太阳高度角查表下限。
	m.solar_irradiance = atmosphereModel_solar_irradiance; // 太阳辐照度。
	m.rayleigh_scattering = atmosphereModel_rayleigh_scattering; // 瑞利散射系数。
	m.mie_scattering = atmosphereModel_mie_scattering; // 米氏散射系数。
	m.absorption_extinction = atmosphereModel_absorption_extinction; // 臭氧吸收系数，只影响透过率。
	m.density_rayleigh = atmosphereModel_densityProfile_rayleigh; // 瑞利密度剖面系数。
	m.density_mie = atmosphereModel_densityProfile_mie; // 米氏密度剖面系数。
	m.absorption_width = atmosphereModel_densityProfile_absorption_width; // 臭氧剖面转折高度。
	m.density_absorption = atmosphereModel_densityProfile_absorption; // 臭氧剖面系数。
	m.transmittance_width = TRANSMITTANCE_TEXTURE_WIDTH; // 透过率子图宽度。
	m.transmittance_height = TRANSMITTANCE_TEXTURE_HEIGHT; // 透过率子图高度。
	m.scattering_r = SCATTERING_TEXTURE_R_SIZE; // 散射子图半径尺寸。
	m.scattering_mu = SCATTERING_TEXTURE_MU_SIZE; // 散射子图高度角尺寸。
	m.scattering_mu_s = SCATTERING_TEXTURE_MU_S_SIZE; // 散射子图太阳高度角尺寸。
	m.scattering_nu = SCATTERING_TEXTURE_NU_SIZE; // 散射子图夹角尺寸。
	m.combined_width = COMBINED_TEXTURE_WIDTH; // 拼合大图宽度。
	m.combined_height = COMBINED_TEXTURE_HEIGHT; // 拼合大图高度。
	m.combined_depth = COMBINED_TEXTURE_DEPTH; // 拼合大图深度。
	m.irradiance_width = IRRADIANCE_TEXTURE_WIDTH; // 辐照度子图宽度。
	m.irradiance_height = IRRADIANCE_TEXTURE_HEIGHT; // 辐照度子图高度。
	return m; // 返回纯参数，通用库不需要知道来源。
}

// 把半径夹进大气层范围内，越界时按最近的边界算。
float ClampRadius(float r) { return gfx_atmo_clamp_radius(omniAtmosphereModel(), r); }
// 安全开方：负零以下一律当零，避免判别式因浮点误差变负时出非数。
float SafeSqrt(float a) { return gfx_safe_sqrt(a); }
// 视线到大气层顶的距离，解视线与顶球面的方程取远根。
float DistanceToTopAtmosphereBoundary(float r, float mu) { return gfx_atmo_distance_to_top(omniAtmosphereModel(), r, mu); }
// 视线到大气层底的距离，解视线与底球面的方程取近根。
float DistanceToBottomAtmosphereBoundary(float r, float mu) { return gfx_atmo_distance_to_bottom(omniAtmosphereModel(), r, mu); }
// 判断一条朝下的视线是否真的打到地面球。
bool RayIntersectsGround(float r, float mu) { return gfx_atmo_ray_intersects_ground(omniAtmosphereModel(), r, mu); }
// 瑞利与米氏密度剖面：以二为底的指数衰减，系数已经积分好。
float GetProfileDensityRayleighMie(float exp_scale, float altitude) { return gfx_atmo_density_rayleigh_mie(exp_scale, altitude); }
// 臭氧密度剖面：在转折高度以下是一段斜线，以上是另一段斜线。
float GetProfileDensityAbsorption(float width, vec4 profile, float altitude) { return gfx_atmo_density_absorption(width, profile, altitude); }
// 把零到一的比例映射到贴图坐标的像素中心，避免采到子图交界。
float GetTextureCoordFromUnitRange(float x, float texture_size) { return gfx_atmo_texture_coord(x, texture_size); }
// 把子图内部的比例映射到拼合大图上的坐标，子图在大图里也内缩半像素。
float GetCombinedTextureCoordFromUnitRange(float x, float original_texture_size, float combined_texture_size) {
	return gfx_atmo_combined_texture_coord(x, original_texture_size, combined_texture_size);
}
// 把半径与几个角度换成散射三维贴图的四维坐标：前三维是坐标，第四维留给上层插值。
vec4 GetScatteringTextureUvwzFromRMuMuSNu(float r, float mu, float mu_s, float nu, bool ray_r_mu_intersects_ground) {
	return gfx_atmo_scattering_uvwz(omniAtmosphereModel(), r, mu, mu_s, nu, ray_r_mu_intersects_ground);
}
// 把半径与高度角换成透过率子图坐标。
vec2 GetTransmittanceTextureUvFromRMu(float r, float mu) { return gfx_atmo_transmittance_uv(omniAtmosphereModel(), r, mu); }
// 查到层顶的透过率：透过率存在拼合大图的同一深度层上。
vec3 GetTransmittanceToTopAtmosphereBoundary(float r, float mu) {
	return gfx_atmo_transmittance_to_top(omniAtmosphereModel(), OMNI_ATMO_LUT, r, mu);
}
// 两点之间的透过率：由两端到层顶的透过率相除得到，地面相交时用镜像方向。
vec3 GetTransmittance(float r, float mu, float d, bool ray_r_mu_intersects_ground) {
	return gfx_atmo_transmittance(omniAtmosphereModel(), OMNI_ATMO_LUT, r, mu, d, ray_r_mu_intersects_ground);
}
// 从某点朝太阳方向到层顶的透过率，太阳贴地时按太阳视半径留一段过渡。
vec3 GetTransmittanceToSun(float r, float mu_s) {
	return gfx_atmo_transmittance_to_sun(omniAtmosphereModel(), OMNI_ATMO_LUT, r, mu_s);
}
// 从拼合散射数据反推单次米氏散射：按通道比例还原。
vec3 GetExtrapolatedSingleMieScattering(vec4 scattering) { return gfx_atmo_extrapolated_mie(omniAtmosphereModel(), scattering); }
// 查组合散射：先在夹角方向插值两片，再拆出单次米氏散射。
vec3 GetCombinedScattering(float r, float mu, float mu_s, float nu, bool ray_r_mu_intersects_ground, out vec3 single_mie_scattering) {
	return gfx_atmo_combined_scattering(omniAtmosphereModel(), OMNI_ATMO_LUT, r, mu, mu_s, nu, ray_r_mu_intersects_ground, single_mie_scattering);
}
// 查辐照度：给出某个高度朝上接到的太阳与环境辐照度。
vec3 GetIrradiance(float r, float mu_s) { return gfx_atmo_irradiance(omniAtmosphereModel(), OMNI_ATMO_LUT, r, mu_s); }
// 算某点的太阳、月亮与天空辐照度：太阳和月亮各出一份直射与一份环境。
vec3 GetSunAndSkyIrradiance(vec3 point, vec3 sun_direction, vec3 moon_direction,
							out vec3 moon_irradiance, out vec3 sun_sky_irradiance, out vec3 moon_sky_irradiance) {
	return gfx_atmo_sun_sky_irradiance(omniAtmosphereModel(), OMNI_ATMO_LUT, point, sun_direction, moon_direction,
		OMNI_NIGHT_BRIGHTNESS, omniSunTint(), moon_irradiance, sun_sky_irradiance, moon_sky_irradiance); // 夜间亮度与太阳色由效果层提供。
}
// 算某个视线方向的天空辐射亮度：日月散射、可选的地面反弹，再乘天气修正。
vec3 GetSkyRadiance(vec3 camera, vec3 view_ray, vec3 sun_direction, vec3 moon_direction, bool horizon,
					out vec3 transmittance, out bool ray_r_mu_intersects_ground) {
	#ifdef OMNI_ATMO_HORIZON // 打开地平线时才计算地面反弹。
		bool ground_bounce = true; // 允许通用库算地面反弹。
	#else
		bool ground_bounce = false; // 关闭时整段地面反弹不参与计算。
	#endif
	return gfx_atmo_sky_radiance(omniAtmosphereModel(), OMNI_ATMO_LUT, camera, view_ray, sun_direction, moon_direction,
		horizon, omniSkyRayleighTint(), omniSkyMieTint(), OMNI_NIGHT_BRIGHTNESS, wetness, OMNI_SKY_BRIGHTNESS,
		ground_bounce, transmittance, ray_r_mu_intersects_ground); // 散射倍率、夜间亮度、湿润度与天空亮度全部显式传入。
}
// 算相机到某个世界点之间的天空辐射亮度，体积云与平面云算空气透视时用。
vec3 GetSkyRadianceToPoint(vec3 camera, vec3 point, vec3 sun_direction, vec3 moon_direction, out vec3 transmittance) {
	#ifdef CLOUD_LOCAL_LIGHTING // 云局部光照开启时也考虑地面相交。
		bool local_lighting = true; // 允许通用库判断地面相交。
	#else
		bool local_lighting = false; // 关闭时一律当作没打到地面。
	#endif
	return gfx_atmo_sky_radiance_to_point(omniAtmosphereModel(), OMNI_ATMO_LUT, camera, point, sun_direction, moon_direction,
		local_lighting, omniSkyRayleighTint(), omniSkyMieTint(), OMNI_NIGHT_BRIGHTNESS, wetness, OMNI_SKY_BRIGHTNESS, transmittance);
}
#endif // 阶段查表接口结束。
