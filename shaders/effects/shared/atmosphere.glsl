/*
效果文件 `effects/shared/atmosphere.glsl`：预计算大气的贴图尺寸、物理常数与查表接口。
调用位置：天空页、云、雾、光照与反射都经本文件查天空辐射与日月辐照；它不负责画天空，只负责把同一份大气数据解释正确。
可复制示例：
    `vec3 atmosphere = GetSkyRadiance(camera, worldDir, worldSunVector, worldMoonVector, horizon, transmittance, ray_r_mu_intersects_ground);`
    `vec3 sunIrradiance = GetSunAndSkyIrradiance(camera, worldSunVector, -worldSunVector, moonIrradiance, sunSkyIrradiance, moonSkyIrradiance);`
设计原因与取舍：大气是所有室外效果共用的光源，贴图尺寸与散射常数只能有一份；
    太阳色倍率与散射倍率也一起放在共享层，云、雾、反射看到的天空才会和主天空一致。
    查表公式在 `omni-gfx/atmosphere_model.glsl`，本文件只把加载器输入、选项与尺寸填进通用结构体。
    一点一六点五以后大气数据挂八号画面，更早版本挂二号深度，所以统一用 `OMNI_ATMO_LUT` 选一次采样器。
*/
#ifndef OMNI_SHARED_ATMOSPHERE_INCLUDED
#define OMNI_SHARED_ATMOSPHERE_INCLUDED
// @effect {"label":{"zh_cn":"大气模型","en_us":"Atmosphere model"}}
// @option {"label":{"zh_cn":"地平线","en_us":"Sky Horizon"},"description":{"zh_cn":"打开后地平线方向也算被行星表面挡住的大气，日出时地平线一带更真实。","en_us":"Also shades the horizon band below the eye as ground-lit atmosphere."}}
//#define OMNI_ATMO_HORIZON
// @option {"label":{"zh_cn":"夜间亮度比值","en_us":"Night Brightness"},"description":{"zh_cn":"夜间环境光相对白天环境光的比值，越大夜里越亮。","en_us":"Night ambient light relative to day; larger makes nights brighter."},"slider":true}
#define OMNI_NIGHT_BRIGHTNESS 0.0003 // [0.0 0.0001 0.00015 0.0002 0.0003 0.0005 0.0007 0.001 0.0015 0.002 0.003 0.005 0.007 0.01 1.0]
// --- 内部常数：原 `Settings.glsl` 里不进菜单的取值，名字保持原名 ---
#define ATMO_MIN_ALTITUDE 500.0 // 相机大气高度下限，低于它按这个高度算，避免贴地时大气几何退化。
#define ATMO_SKYBOX_MIN_ALTITUDE 500.0 - wetness * 300.0 // 反射天空盒的相机高度下限，雨天云更厚所以再压低一点。
// 预计算大气三维贴图的排布尺寸，读表时要按这些尺寸算坐标。
#define TRANSMITTANCE_TEXTURE_WIDTH 256.0 // 透过率子图宽度，单位像素。
#define TRANSMITTANCE_TEXTURE_HEIGHT 64.0 // 透过率子图高度。
#define SCATTERING_TEXTURE_R_SIZE 32.0 // 散射子图的半径方向尺寸，拼进深度方向。
#define SCATTERING_TEXTURE_MU_SIZE 128.0 // 散射子图的高度角方向尺寸。
#define SCATTERING_TEXTURE_MU_S_SIZE 32.0 // 散射子图的太阳高度角方向尺寸。
#define SCATTERING_TEXTURE_NU_SIZE 16.0 // 散射子图的视线与太阳夹角方向尺寸。
#define COMBINED_TEXTURE_WIDTH 512.0 // 拼合后大图宽度。
#define COMBINED_TEXTURE_HEIGHT 128.0 // 拼合后大图高度。
#define COMBINED_TEXTURE_DEPTH 33.0 // 拼合后大图深度。
#define IRRADIANCE_TEXTURE_WIDTH 64.0 // 辐照度子图宽度。
#define IRRADIANCE_TEXTURE_HEIGHT 16.0 // 辐照度子图高度。
// 大气物理常数，长度单位公里，亮度单位辐射亮度；与 iterationT 完全一致。
#define atmosphereModel_solar_irradiance 		vec3(1.68194, 1.85149, 1.91198) // 太阳辐照度，决定大气散射的基准亮度。
#define atmosphereModel_sun_angular_radius 		0.005 // 太阳视半径，日落时用它对太阳方向做渐隐。
#define atmosphereModel_bottom_radius 			6360.0 // 行星底半径，越过它就算被地面挡住。
#define atmosphereModel_top_radius 				6420.0 // 大气层顶半径，视线到这里离开大气。
#define atmosphereModel_rayleigh_scattering 	vec3(0.008396, 0.014590, 0.033100) // 瑞利散射系数，蓝光最强，天空因此偏蓝。
#define atmosphereModel_mie_scattering 			vec3(0.003996) // 米氏散射系数，气溶胶造成太阳附近的白晕。
#define atmosphereModel_mie_extinction 			vec3(0.004440) // 米氏消光系数，比散射略大，差额被吸收。
#define atmosphereModel_mie_phase_function_g 	0.8 // 米氏相位的前向集中程度。
#define atmosphereModel_absorption_extinction 	vec3(0.0020031, 0.0016555, 0.0000847) // 臭氧吸收系数。
#define atmosphereModel_ground_albedo 			vec3(0.1) // 地面反照率，地平线方向算一次地面反弹。
#define atmosphereModel_mu_s_min 				-0.5 // 太阳高度角的查表下限。
#define atmosphereModel_densityProfile_rayleigh 			-0.1803369 // 瑞利密度剖面的指数系数。
#define atmosphereModel_densityProfile_mie 					-1.2022459 // 米氏密度剖面的指数系数。
#define atmosphereModel_densityProfile_absorption_width 	25.0 // 臭氧三角剖面的转折高度。
#define atmosphereModel_densityProfile_absorption 			vec4(0.09617967, -0.9617967, -0.09617967, 3.847187) // 臭氧剖面分段线性系数。
// 共用数学与加载器输入，显式引入而不依赖调用顺序；太阳色与散射倍率同属共享大气输入。
#include "/common/uniforms.glsl"
#include "/common/math.glsl"
#include "/effects/shared/suncolor.glsl"
#include "/effects/shared/skyscatter.glsl"
// 查表公式、球面几何与相位函数都在通用库；本文件只填参数与选贴图。
#include "/omni-gfx/atmosphere_model.glsl"

// 一点一六点五以后大气数据挂在八号画面，更早的版本挂在二号深度上；只能整段选一个采样器。
#if MC_VERSION >= 11605
	#define OMNI_ATMO_LUT colortex8 // 新版本读八号画面的三维大气数据。
#else
	#define OMNI_ATMO_LUT depthtex2 // 旧版本读二号深度上的大气数据。
#endif


// 把当前阶段的常数与贴图尺寸打包成通用结构体：数值全部来自 `rendering/sky/sky.glsl`，不在这里另存一份默认值。
OgxAtmosphereModel omniAtmosphereModel(){
	OgxAtmosphereModel m; // 待填充的查表参数。
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
float ClampRadius(float r) { return ogxAtmoClampRadius(omniAtmosphereModel(), r); }
// 安全开方：负零以下一律当零，避免判别式因浮点误差变负时出非数。
float SafeSqrt(float a) { return ogxSafeSqrt(a); }
// 视线到大气层顶的距离，解视线与顶球面的方程取远根。
float DistanceToTopAtmosphereBoundary(float r, float mu) { return ogxAtmoDistanceToTop(omniAtmosphereModel(), r, mu); }
// 视线到大气层底的距离，解视线与底球面的方程取近根。
float DistanceToBottomAtmosphereBoundary(float r, float mu) { return ogxAtmoDistanceToBottom(omniAtmosphereModel(), r, mu); }
// 判断一条朝下的视线是否真的打到地面球。
bool RayIntersectsGround(float r, float mu) { return ogxAtmoRayIntersectsGround(omniAtmosphereModel(), r, mu); }
// 瑞利与米氏密度剖面：以二为底的指数衰减，系数已经积分好。
float GetProfileDensityRayleighMie(float exp_scale, float altitude) { return ogxAtmoDensityRayleighMie(exp_scale, altitude); }
// 臭氧密度剖面：在转折高度以下是一段斜线，以上是另一段斜线。
float GetProfileDensityAbsorption(float width, vec4 profile, float altitude) { return ogxAtmoDensityAbsorption(width, profile, altitude); }
// 把零到一的比例映射到贴图坐标的像素中心，避免采到子图交界。
float GetTextureCoordFromUnitRange(float x, float texture_size) { return ogxAtmoTextureCoord(x, texture_size); }
// 把子图内部的比例映射到拼合大图上的坐标，子图在大图里也内缩半像素。
float GetCombinedTextureCoordFromUnitRange(float x, float original_texture_size, float combined_texture_size) {
	return ogxAtmoCombinedTextureCoord(x, original_texture_size, combined_texture_size);
}
// 把半径与几个角度换成散射三维贴图的四维坐标：前三维是坐标，第四维留给上层插值。
vec4 GetScatteringTextureUvwzFromRMuMuSNu(float r, float mu, float mu_s, float nu, bool ray_r_mu_intersects_ground) {
	return ogxAtmoScatteringUvwz(omniAtmosphereModel(), r, mu, mu_s, nu, ray_r_mu_intersects_ground);
}
// 把半径与高度角换成透过率子图坐标。
vec2 GetTransmittanceTextureUvFromRMu(float r, float mu) { return ogxAtmoTransmittanceUv(omniAtmosphereModel(), r, mu); }
// 查到层顶的透过率：透过率存在拼合大图的同一深度层上。
vec3 GetTransmittanceToTopAtmosphereBoundary(float r, float mu) {
	return ogxAtmoTransmittanceToTop(omniAtmosphereModel(), OMNI_ATMO_LUT, r, mu);
}
// 两点之间的透过率：由两端到层顶的透过率相除得到，地面相交时用镜像方向。
vec3 GetTransmittance(float r, float mu, float d, bool ray_r_mu_intersects_ground) {
	return ogxAtmoTransmittance(omniAtmosphereModel(), OMNI_ATMO_LUT, r, mu, d, ray_r_mu_intersects_ground);
}
// 从某点朝太阳方向到层顶的透过率，太阳贴地时按太阳视半径留一段过渡。
vec3 GetTransmittanceToSun(float r, float mu_s) {
	return ogxAtmoTransmittanceToSun(omniAtmosphereModel(), OMNI_ATMO_LUT, r, mu_s);
}
// 从拼合散射数据反推单次米氏散射：按通道比例还原。
vec3 GetExtrapolatedSingleMieScattering(vec4 scattering) { return ogxAtmoExtrapolatedMie(omniAtmosphereModel(), scattering); }
// 查组合散射：先在夹角方向插值两片，再拆出单次米氏散射。
vec3 GetCombinedScattering(float r, float mu, float mu_s, float nu, bool ray_r_mu_intersects_ground, out vec3 single_mie_scattering) {
	return ogxAtmoCombinedScattering(omniAtmosphereModel(), OMNI_ATMO_LUT, r, mu, mu_s, nu, ray_r_mu_intersects_ground, single_mie_scattering);
}
// 查辐照度：给出某个高度朝上接到的太阳与环境辐照度。
vec3 GetIrradiance(float r, float mu_s) { return ogxAtmoIrradiance(omniAtmosphereModel(), OMNI_ATMO_LUT, r, mu_s); }
// 算某点的太阳、月亮与天空辐照度：太阳和月亮各出一份直射与一份环境。
vec3 GetSunAndSkyIrradiance(vec3 point, vec3 sun_direction, vec3 moon_direction,
							out vec3 moon_irradiance, out vec3 sun_sky_irradiance, out vec3 moon_sky_irradiance) {
	return ogxAtmoSunSkyIrradiance(omniAtmosphereModel(), OMNI_ATMO_LUT, point, sun_direction, moon_direction,
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
	return ogxAtmoSkyRadiance(omniAtmosphereModel(), OMNI_ATMO_LUT, camera, view_ray, sun_direction, moon_direction,
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
	return ogxAtmoSkyRadianceToPoint(omniAtmosphereModel(), OMNI_ATMO_LUT, camera, point, sun_direction, moon_direction,
		local_lighting, omniSkyRayleighTint(), omniSkyMieTint(), OMNI_NIGHT_BRIGHTNESS, wetness, OMNI_SKY_BRIGHTNESS, transmittance);
}
#endif // OMNI_SHARED_ATMOSPHERE_INCLUDED
