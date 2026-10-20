/*
预计算大气：把 iterationT `Lib/BasicFounctions/PrecomputedAtmosphere.glsl` 的预计算大气模型整体搬来，
    提供球面几何、密度剖面、贴图坐标、透过率、组合散射、辐照度与天空辐射的查询函数。
调用位置：由 `effects/sky/sky.glsl` 在选项与内部常数之后引入；延迟三号、七号、八号与合成顶点都经它查天空辐射。
可复制示例：
    `vec3 atmosphere = GetSkyRadiance(camera, worldDir, worldSunVector, worldMoonVector, horizon, transmittance, ray_r_mu_intersects_ground);`
    `vec3 sunIrradiance = GetSunAndSkyIrradiance(camera, worldSunVector, -worldSunVector, moonIrradiance, sunSkyIrradiance, moonSkyIrradiance);`
调用前提：`atmosphereModel_*` 常数与贴图尺寸常数由 `effects/sky/sky.glsl` 定义；相位函数与亮度由 `common/math.glsl` 提供；
    太阳色倍率由 `effects/sky/suncolor.glsl` 提供；天空散射倍率与 `OMNI_SKY_BRIGHTNESS` 由 `effects/sky/skyscatter.glsl` 提供。
设计原因与取舍：读预计算三维贴图，不实时积分，代价与分辨率无关；`GetSkyRadianceToPoint` 供体积云与平面云算空气透视，
    与 `GetSkyRadiance` 共用同一份查表原语，二者放在一起，拆分前后逐行一致。
*/
#ifndef OMNI_SKY_ATMOSPHERE_MODEL_INCLUDED
#define OMNI_SKY_ATMOSPHERE_MODEL_INCLUDED
#include "/gfx/atmosphere.glsl"
// 把半径夹进大气层范围内，越界时按最近的边界算。
float ClampRadius(float r) { return gfx_clamp_radius(r, atmosphereModel_bottom_radius, atmosphereModel_top_radius); }
// 安全开方：负零以下一律当零，避免判别式因浮点误差变负时出非数。
float SafeSqrt(float a) { return gfx_safe_sqrt(a); }

// 视线到大气层顶的距离，解视线与顶球面的方程取远根。
float DistanceToTopAtmosphereBoundary(
	float r,
	float mu
	){
		return gfx_distance_to_top(r, mu, atmosphereModel_top_radius); // 球面几何在通用库，层顶半径在这里传入。
}
// 视线到大气层底的距离，解视线与底球面的方程取近根。
float DistanceToBottomAtmosphereBoundary(
	float r,
	float mu
	){
		return gfx_distance_to_bottom(r, mu, atmosphereModel_bottom_radius); // 层底半径在这里传入。
}
// 判断一条朝下的视线是否真的打到地面球。
bool RayIntersectsGround(
	float r,
	float mu
	){
		return gfx_ray_intersects_ground(r, mu, atmosphereModel_bottom_radius); // 与地面球的相交判断在通用库。
}
// 瑞利与米氏密度剖面：以二为底的指数衰减，系数已经积分好。
float GetProfileDensityRayleighMie(
	float exp_scale,
	float altitude
	){
		return gfx_density_rayleigh_mie(exp_scale, altitude); // 指数密度剖面在通用库。
}
// 臭氧密度剖面：在转折高度以下是一段斜线，以上是另一段斜线。
float GetProfileDensityAbsorption(
	float width,
	vec4 profile,
	float altitude
	){
		return gfx_density_absorption(width, profile, altitude); // 两段线性剖面在通用库。
}
// 把零到一的比例映射到贴图坐标的像素中心，避免采到子图交界。
float GetTextureCoordFromUnitRange(float x, float texture_size) { return gfx_texture_coord(x, texture_size); }
// 把子图内部的比例映射到拼合大图上的坐标，子图在大图里也内缩半像素。
float GetCombinedTextureCoordFromUnitRange(float x, float original_texture_size, float combined_texture_size) { return gfx_combined_texture_coord(x, original_texture_size, combined_texture_size); }
// 把半径与几个角度换成散射三维贴图的四维坐标：前三维是坐标，第四维留给上层插值。
vec4 GetScatteringTextureUvwzFromRMuMuSNu(
	float r,
	float mu,
	float mu_s,
	float nu,
	bool ray_r_mu_intersects_ground
	){
		float H = sqrt(atmosphereModel_top_radius * atmosphereModel_top_radius - atmosphereModel_bottom_radius* atmosphereModel_bottom_radius); // 大气层顶相对地面的水平距离。
		float rho = SafeSqrt(r * r - atmosphereModel_bottom_radius* atmosphereModel_bottom_radius); // 相机到地心的水平投影。
		float u_r = GetCombinedTextureCoordFromUnitRange(rho / H, SCATTERING_TEXTURE_R_SIZE, COMBINED_TEXTURE_DEPTH); // 半径方向落到深度坐标。
		float r_mu = r * mu; // 半径乘高度角余弦，判别式里反复用到。
		float discriminant = r_mu * r_mu - r * r + atmosphereModel_bottom_radius* atmosphereModel_bottom_radius; // 是否打到地面的判别式。
		float u_mu; // 高度角方向的坐标，下面分两种情形算。
		if (ray_r_mu_intersects_ground){ // 打到地面：用近根，坐标落在下半段。
			float d = -r_mu - SafeSqrt(discriminant); // 到地面的距离。
			float d_min = r - atmosphereModel_bottom_radius; // 距离下限。
			float d_max = rho; // 距离上限。
			u_mu = 0.5 - 0.5 * GetTextureCoordFromUnitRange(float(d_max != d_min) * (d - d_min) / (d_max - d_min), SCATTERING_TEXTURE_MU_SIZE / 2.0); // 映射到下半张子图。
		}else{ // 没打到地面：用远根，坐标落在上半段。
			float d = -r_mu + SafeSqrt(discriminant + H * H); // 到层顶的距离。
			float d_min = atmosphereModel_top_radius - r; // 距离下限。
			float d_max = rho + H; // 距离上限。
			u_mu = 0.5 + 0.5 * GetTextureCoordFromUnitRange((d - d_min) / (d_max - d_min), SCATTERING_TEXTURE_MU_SIZE / 2.0); // 映射到上半张子图。
		}
		float d = DistanceToTopAtmosphereBoundary(atmosphereModel_bottom_radius, mu_s); // 太阳高度角对应的层顶距离。
		float d_min = atmosphereModel_top_radius - atmosphereModel_bottom_radius; // 距离下限。
		float d_max = H; // 距离上限。
		float a = (d - d_min) / (d_max - d_min); // 太阳高度角的归一化距离。
		float D = DistanceToTopAtmosphereBoundary(atmosphereModel_bottom_radius, atmosphereModel_mu_s_min); // 查表下限对应的距离。
		float A = (D - d_min) / (d_max - d_min); // 下限的归一化距离。
		float u_mu_s = GetTextureCoordFromUnitRange(max(1.0 - a / A, 0.0) / (1.0 + a), SCATTERING_TEXTURE_MU_S_SIZE); // 非线性映射到太阳高度角坐标。
		float u_nu = (nu + 1.0) / 2.0; // 视线与太阳夹角从负一到一转成零到一。
		return vec4(u_nu, u_mu_s, u_mu, u_r); // 返回四维坐标，供上层做夹角方向插值。
}
// 把半径与高度角换成透过率子图坐标。
vec2 GetTransmittanceTextureUvFromRMu(
	float r,
	float mu
	){
		float H = sqrt(atmosphereModel_top_radius * atmosphereModel_top_radius - atmosphereModel_bottom_radius* atmosphereModel_bottom_radius); // 大气层顶相对地面的水平距离。
		float rho = SafeSqrt(r * r - atmosphereModel_bottom_radius* atmosphereModel_bottom_radius); // 相机到地心的水平投影。
		float d = DistanceToTopAtmosphereBoundary(r, mu); // 到层顶的距离。
		float d_min = atmosphereModel_top_radius - r; // 距离下限。
		float d_max = rho + H; // 距离上限。
		float x_mu = (d - d_min) / (d_max - d_min); // 高度角方向的归一化位置。
		float x_r = rho / H; // 半径方向的归一化位置。
		return vec2(GetCombinedTextureCoordFromUnitRange(x_mu, TRANSMITTANCE_TEXTURE_WIDTH, COMBINED_TEXTURE_WIDTH), // 横坐标是高度角方向。
					GetCombinedTextureCoordFromUnitRange(x_r, TRANSMITTANCE_TEXTURE_HEIGHT, COMBINED_TEXTURE_HEIGHT)); // 纵坐标是半径方向。
}
// 查到层顶的透过率：透过率存在拼合大图的同一深度层上。
vec3 GetTransmittanceToTopAtmosphereBoundary(
	float r,
	float mu
	){
		vec2 uv = GetTransmittanceTextureUvFromRMu(r, mu); // 先算子图坐标。
		#if MC_VERSION >= 11605 // 一点一六点五以后大气数据挂在八号画面。
			return vec3(textureLod(colortex8, vec3(uv, 32.5 / 33.0), 0.0)); // 读固定深度层，取三通道颜色。
		#else // 更早版本挂在二号深度画面上。
			return vec3(textureLod(depthtex2, vec3(uv, 32.5 / 33.0), 0.0)); // 旧版本读二号深度画面。
		#endif
}
// 两点之间的透过率：由两端到层顶的透过率相除得到，地面相交时用镜像方向。
vec3 GetTransmittance(
	float r,
	float mu,
	float d,
	bool ray_r_mu_intersects_ground
	){
		float r_d = ClampRadius(sqrt(d * d + 2.0 * r * mu * d + r * r)); // 终点相对地心的半径。
		float mu_d = clamp((r * mu + d) / r_d, -1.0, 1.0); // 终点处的高度角余弦。
		if (ray_r_mu_intersects_ground) { // 打到地面时用负高度角镜像。
			return min(
				GetTransmittanceToTopAtmosphereBoundary(r_d, -mu_d) /
				GetTransmittanceToTopAtmosphereBoundary(r, -mu),
			vec3(1.0)); // 两端相除并封顶到一。
		} else { // 没打到地面直接用正高度角。
			return min(
				GetTransmittanceToTopAtmosphereBoundary(r, mu) /
				GetTransmittanceToTopAtmosphereBoundary(r_d, mu_d),
			vec3(1.0)); // 两端相除并封顶到一。
		}
}
// 从某点朝太阳方向到层顶的透过率，太阳贴地时按太阳视半径留一段过渡。
vec3 GetTransmittanceToSun(
	float r,
	float mu_s
	){
		float sin_theta_h = atmosphereModel_bottom_radius/ r; // 地平线方向的俯角正弦。
		float cos_theta_h = -sqrt(max(1.0 - sin_theta_h * sin_theta_h, 0.0)); // 地平线方向的余弦。
		return GetTransmittanceToTopAtmosphereBoundary(r, mu_s) * // 基础透过率。
			smoothstep(-sin_theta_h * atmosphereModel_sun_angular_radius, // 过渡带下沿。
					   sin_theta_h * atmosphereModel_sun_angular_radius, // 过渡带上沿。
					   mu_s - cos_theta_h); // 过渡带半宽由太阳视半径决定。
}
// 从拼合散射数据反推单次米氏散射：按通道比例还原。
vec3 GetExtrapolatedSingleMieScattering(
	vec4 scattering
	){
		if (scattering.r <= 0.0){ // 红通道为零说明没有数据。
			return vec3(0.0); // 直接返回零。
		}
		return scattering.rgb * scattering.a / scattering.r * // 按红通道比例缩放。
			(atmosphereModel_rayleigh_scattering.r / atmosphereModel_mie_scattering.r) * // 瑞利与米氏红通道比例。
			(atmosphereModel_mie_scattering / atmosphereModel_rayleigh_scattering); // 逐通道还原米氏散射。
}
// 查组合散射：先在夹角方向插值两片，再拆出单次米氏散射。
vec3 GetCombinedScattering(
	float r,
	float mu,
	float mu_s,
	float nu,
	bool ray_r_mu_intersects_ground,
	out vec3 single_mie_scattering
	){
		vec4 uvwz = GetScatteringTextureUvwzFromRMuMuSNu(r, mu, mu_s, nu, ray_r_mu_intersects_ground); // 四维查表坐标。
		float tex_coord_x = uvwz.x * (SCATTERING_TEXTURE_NU_SIZE - 1.0); // 夹角方向落在第几片。
		float tex_x = floor(tex_coord_x); // 前一片的编号。
		float lerp = tex_coord_x - tex_x; // 两片之间的插值比例。
		vec3 uvw0 = vec3((tex_x + uvwz.y) / SCATTERING_TEXTURE_NU_SIZE, uvwz.z, uvwz.w); // 前一片的三维坐标。
		vec3 uvw1 = vec3((tex_x + 1.0 + uvwz.y) / SCATTERING_TEXTURE_NU_SIZE, uvwz.z, uvwz.w); // 后一片的三维坐标。
		#if MC_VERSION >= 11605 // 一点一六点五以后大气数据挂在八号画面。
			vec4 combined_scattering = textureLod(colortex8, uvw0, 0.0) * (1.0 - lerp) + textureLod(colortex8, uvw1, 0.0) * lerp; // 两片之间线性插值。
		#else // 更早版本挂在二号深度画面上。
			vec4 combined_scattering = textureLod(depthtex2, uvw0, 0.0) * (1.0 - lerp) + textureLod(depthtex2, uvw1, 0.0) * lerp; // 旧版本两片插值。
		#endif
		vec3 scattering = vec3(combined_scattering); // 前三通道是组合散射。
		single_mie_scattering = GetExtrapolatedSingleMieScattering(combined_scattering); // 第四通道还原单次米氏散射。
		return scattering; // 返回组合散射。
}
// 查辐照度：给出某个高度朝上接到的太阳与环境辐照度。
vec3 GetIrradiance(
	float r,
	float mu_s
	){
		float x_r = (r - atmosphereModel_bottom_radius) / (atmosphereModel_top_radius - atmosphereModel_bottom_radius); // 半径方向归一化。
		float x_mu_s = mu_s * 0.5 + 0.5; // 太阳高度角从负一到一转成零到一。
		vec2 uv = vec2(GetCombinedTextureCoordFromUnitRange(x_mu_s, IRRADIANCE_TEXTURE_WIDTH, COMBINED_TEXTURE_WIDTH), // 横坐标是高度角方向。
					   GetCombinedTextureCoordFromUnitRange(x_r, IRRADIANCE_TEXTURE_HEIGHT, COMBINED_TEXTURE_HEIGHT) + TRANSMITTANCE_TEXTURE_HEIGHT / COMBINED_TEXTURE_HEIGHT); // 纵坐标要跳过透过率子图。
		#if MC_VERSION >= 11605 // 一点一六点五以后大气数据挂在八号画面。
			return vec3(textureLod(colortex8, vec3(uv, 32.5 / 33.0), 0.0)); // 读固定深度层的辐照度。
		#else // 更早版本挂在二号深度画面上。
			return vec3(textureLod(depthtex2, vec3(uv, 32.5 / 33.0), 0.0)); // 旧版本读二号深度画面。
		#endif
}
// 色适应矩阵：把物理辐照度的三刺激值转到本项目使用的原色空间。
const mat3 LMS = mat3(1.6858, -0.4624, -0.0069, -0.0374, 1.0598, -0.0742, -0.0283, -0.1119, 1.0491);
// 算某点的太阳、月亮与天空辐照度：太阳和月亮各出一份直射与一份环境。
vec3 GetSunAndSkyIrradiance(
	vec3 point,
	vec3 sun_direction,
	vec3 moon_direction,
	out vec3 moon_irradiance,
	out vec3 sun_sky_irradiance,
	out vec3 moon_sky_irradiance
	){
		float r = length(point); // 点到地心的距离。
		float sun_mu_s = dot(point, sun_direction) / r; // 太阳方向相对当地向上的余弦。
		float moon_mu_s = dot(point, moon_direction) / r; // 月亮方向相对当地向上的余弦。
		sun_sky_irradiance = GetIrradiance(r, sun_mu_s) * LMS; // 太阳侧的环境辐照度，乘色适应矩阵。
		moon_sky_irradiance = GetIrradiance(r, moon_mu_s) * OMNI_NIGHT_BRIGHTNESS * LMS; // 月亮侧环境辐照度，按夜间亮度缩放。
		vec3 sun_irradiance = atmosphereModel_solar_irradiance; // 太阳直射从标准辐照度出发。
		moon_irradiance = sun_irradiance * GetTransmittanceToSun(r, moon_mu_s) * OMNI_NIGHT_BRIGHTNESS * LMS; // 月亮直射等于太阳辐照度乘月光透过率，再按夜间亮度缩放。
		sun_irradiance *= GetTransmittanceToSun(r, sun_mu_s); // 太阳直射乘它自己的透过率。
		return sun_irradiance * LMS * omniSunTint(); // 只染太阳直射：月亮直射有独立的 `OMNI_MOON_TEMP`，若在上一行染色会把月亮一起带偏。
}
// 算某个视线方向的天空辐射亮度：日月散射、可选的地面反弹，再乘天气修正。
vec3 GetSkyRadiance(
	vec3 camera,
	vec3 view_ray,
	vec3 sun_direction,
	vec3 moon_direction,
	bool horizon,
	out vec3 transmittance,
	out bool ray_r_mu_intersects_ground
	){
		float r = length(camera); // 相机到地心的距离。
		float rmu = dot(camera, view_ray); // 相机位置与视线的点积。
		float distance_to_top_atmosphere_boundary = -rmu - sqrt(rmu * rmu - r * r + atmosphereModel_top_radius * atmosphereModel_top_radius); // 相机到层顶的负距离，正数表示相机在上方。
		if (distance_to_top_atmosphere_boundary > 0.0){ // 相机在大气内部时把起点推到层顶。
			camera = camera + view_ray * distance_to_top_atmosphere_boundary; // 沿视线外推到层顶。
			r = atmosphereModel_top_radius; // 起点半径等于层顶。
			rmu += distance_to_top_atmosphere_boundary; // 同步更新点积。
		} else if (r > atmosphereModel_top_radius) { // 相机在层顶之外时没有大气。
			transmittance = vec3(1.0); // 透过率为一。
			return vec3(0.0); // 没有散射。
		}
		float mu = rmu / r; // 起点的高度角余弦。
		float sun_mu_s = dot(camera, sun_direction) / r; // 太阳方向相对当地向上的余弦。
		float sun_nu = dot(view_ray, sun_direction); // 视线与太阳夹角余弦。
		float moon_mu_s = dot(camera, moon_direction) / r; // 月亮方向相对当地向上的余弦。
		float moon_nu = dot(view_ray, moon_direction); // 视线与月亮夹角余弦。
		ray_r_mu_intersects_ground = RayIntersectsGround(r, mu); // 视线是否打到地面。
		transmittance = ray_r_mu_intersects_ground ? vec3(0.0) : GetTransmittanceToTopAtmosphereBoundary(r, mu); // 打到地面时透过率为零。
		vec3 sun_single_mie_scattering; // 太阳侧的单次米氏散射。
		vec3 sun_scattering; // 太阳侧的组合散射。
		vec3 moon_single_mie_scattering; // 月亮侧的单次米氏散射。
		vec3 moon_scattering; // 月亮侧的组合散射。
		horizon = horizon && ray_r_mu_intersects_ground; // 只有打到地面才考虑地平线处理。
		sun_scattering = GetCombinedScattering(r, mu, sun_mu_s, sun_nu, horizon, sun_single_mie_scattering); // 查太阳侧组合散射。
		moon_scattering = GetCombinedScattering(r, mu, moon_mu_s, moon_nu, horizon, moon_single_mie_scattering); // 查月亮侧组合散射。
		vec3 groundDiffuse = vec3(0.0); // 地面反弹的散射。
		#ifdef OMNI_ATMO_HORIZON // 打开地平线时才算地面反弹。
		if (horizon){ // 只有打到地面的方向需要。
			vec3 planet_surface = camera + view_ray * DistanceToBottomAtmosphereBoundary(r, mu); // 视线与地面的交点。
			float r = length(planet_surface); // 交点到地心的距离。
			float sun_mu_s = dot(planet_surface, sun_direction) / r; // 交点处的太阳高度角余弦。
			float moon_mu_s = dot(planet_surface, moon_direction) / r; // 交点处的月亮高度角余弦。
			vec3 sky_irradiance = GetIrradiance(r, sun_mu_s); // 交点处的太阳侧环境辐照度。
			sky_irradiance += GetIrradiance(r, moon_mu_s) * OMNI_NIGHT_BRIGHTNESS; // 加上月亮侧环境辐照度。
			vec3 sun_irradiance = atmosphereModel_solar_irradiance * GetTransmittanceToSun(r, sun_mu_s); // 交点处的太阳直射辐照度。
			float d = distance(camera, planet_surface); // 相机到交点的距离。
			vec3 surface_transmittance = GetTransmittance(r, mu, d, ray_r_mu_intersects_ground); // 这段距离的透过率。
			groundDiffuse = mix(sky_irradiance * 0.1, sun_irradiance * 0.008, wetness * 0.6) * surface_transmittance; // 地面反弹按干湿在环境与直射之间插值。
		}
		#endif
		vec3 rayleigh = (sun_scattering * RayleighPhaseFunction(sun_nu) // 太阳侧瑞利散射乘瑞利相位。
					 + moon_scattering * RayleighPhaseFunction(moon_nu) * OMNI_NIGHT_BRIGHTNESS) // 月亮侧同理并按夜间亮度缩放。
					 * omniSkyRayleighTint(); // 再按散射系数选项逐通道缩放瑞利散射，默认全一不改画面。
		vec3 mie = (sun_single_mie_scattering * MiePhaseFunction(atmosphereModel_mie_phase_function_g, sun_nu) // 太阳侧米氏散射乘米氏相位。
				+ moon_single_mie_scattering * MiePhaseFunction(atmosphereModel_mie_phase_function_g, moon_nu) * OMNI_NIGHT_BRIGHTNESS) // 月亮侧同理。
				* omniSkyMieTint(); // 再按散射系数选项逐通道缩放米氏散射，默认全一不改画面。
		rayleigh = mix(rayleigh, vec3(Luminance(rayleigh)) * atmosphereModel_solar_irradiance, wetness * 0.5); // 雨天把瑞利散射去色并按太阳谱重新染色。
		return (rayleigh + mie + groundDiffuse) * (1.0 - wetness * 0.4) * LMS * OMNI_SKY_BRIGHTNESS; // 合成后按雨天压暗、转色适应空间，再乘天空亮度选项。
}
// 算相机到某个世界点之间的天空辐射亮度，体积云与平面云算空气透视时用。
vec3 GetSkyRadianceToPoint(
	vec3 camera,
	vec3 point,
	vec3 sun_direction,
	vec3 moon_direction,
	out vec3 transmittance
	){
		vec3 view_ray = normalize(point - camera); // 从相机指向目标点的方向。
		float r = length(camera); // 相机到地心的距离。
		float rmu = dot(camera, view_ray); // 相机位置与视线的点积。
		float distance_to_top_atmosphere_boundary = -rmu - sqrt(rmu * rmu - r * r + atmosphereModel_top_radius * atmosphereModel_top_radius); // 相机到层顶的负距离。
		if (distance_to_top_atmosphere_boundary > 0.0){ // 相机在大气内部时把起点推到层顶。
			camera = camera + view_ray * distance_to_top_atmosphere_boundary; // 沿视线外推到层顶。
			r = atmosphereModel_top_radius; // 起点半径等于层顶。
			rmu += distance_to_top_atmosphere_boundary; // 同步更新点积。
		}
		float mu = rmu / r; // 起点的高度角余弦。
		float sun_mu_s = dot(camera, sun_direction) / r; // 太阳方向相对当地向上的余弦。
		float sun_nu = dot(view_ray, sun_direction); // 视线与太阳夹角余弦。
		float moon_mu_s = dot(camera, moon_direction) / r; // 月亮方向相对当地向上的余弦。
		float moon_nu = dot(view_ray, moon_direction); // 视线与月亮夹角余弦。
		float d = length(point - camera); // 起点到目标点的距离。
		#ifdef CLOUD_LOCAL_LIGHTING // 云局部光照开启时也考虑地面相交。
			bool ray_r_mu_intersects_ground = RayIntersectsGround(r, mu); // 按视线是否打到地面判断。
		#else // 关闭时一律当作没打到地面。
			bool ray_r_mu_intersects_ground = false; // 常量假。
		#endif
		transmittance = GetTransmittance(r, mu, d, ray_r_mu_intersects_ground); // 起点到目标点的透过率。
		vec3 sun_single_mie_scattering; // 太阳侧单次米氏散射。
		vec3 sun_scattering = GetCombinedScattering(r, mu, sun_mu_s, sun_nu, ray_r_mu_intersects_ground, sun_single_mie_scattering); // 起点处太阳侧组合散射。
		vec3 moon_single_mie_scattering; // 月亮侧单次米氏散射。
		vec3 moon_scattering = GetCombinedScattering(r, mu, moon_mu_s, moon_nu, ray_r_mu_intersects_ground, moon_single_mie_scattering); // 起点处月亮侧组合散射。
		float r_p = ClampRadius(sqrt(d * d + 2.0 * r * mu * d + r * r)); // 目标点相对地心的半径。
		float mu_p = (r * mu + d) / r_p; // 目标点处的高度角余弦。
		float sun_mu_s_p = (r * sun_mu_s + d * sun_nu) / r_p; // 目标点处的太阳高度角余弦。
		float moon_mu_s_p = (r * moon_mu_s + d * moon_nu) / r_p; // 目标点处的月亮高度角余弦。
		vec3 sun_single_mie_scattering_p; // 目标点处太阳侧单次米氏散射。
		vec3 sun_scattering_p = GetCombinedScattering(r_p, mu_p, sun_mu_s_p, sun_nu, ray_r_mu_intersects_ground, sun_single_mie_scattering_p); // 目标点处太阳侧组合散射。
		vec3 moon_single_mie_scattering_p; // 目标点处月亮侧单次米氏散射。
		vec3 moon_scattering_p = GetCombinedScattering(r_p, mu_p, moon_mu_s_p, moon_nu, ray_r_mu_intersects_ground, moon_single_mie_scattering_p); // 目标点处月亮侧组合散射。
		sun_scattering = sun_scattering - transmittance * sun_scattering_p; // 两点之差的散射是这段空气的贡献。
		sun_single_mie_scattering = sun_single_mie_scattering - transmittance * sun_single_mie_scattering_p; // 米氏散射同样相减。
		moon_scattering = moon_scattering - transmittance * moon_scattering_p; // 月亮侧同理。
		moon_single_mie_scattering = moon_single_mie_scattering - transmittance * moon_single_mie_scattering_p; // 月亮侧米氏同样相减。
		sun_single_mie_scattering = sun_single_mie_scattering * smoothstep(0.0, 0.01, sun_mu_s); // 太阳很贴地时淡出米氏散射，避免出现断带。
		moon_single_mie_scattering = moon_single_mie_scattering * smoothstep(0.0, 0.01, moon_mu_s); // 月亮同样处理。
		vec3 rayleigh = (sun_scattering * RayleighPhaseFunction(sun_nu) // 太阳侧瑞利散射。
					 + moon_scattering * RayleighPhaseFunction(moon_nu) * OMNI_NIGHT_BRIGHTNESS) // 月亮侧瑞利散射。
					 * omniSkyRayleighTint(); // 按散射系数选项逐通道缩放，默认全一不改画面。
		vec3 mie = (sun_single_mie_scattering * MiePhaseFunction(atmosphereModel_mie_phase_function_g, sun_nu) // 太阳侧米氏散射。
				+ moon_single_mie_scattering * MiePhaseFunction(atmosphereModel_mie_phase_function_g, moon_nu) * OMNI_NIGHT_BRIGHTNESS) // 月亮侧米氏散射。
				* omniSkyMieTint(); // 按散射系数选项逐通道缩放，默认全一不改画面。
		rayleigh = mix(rayleigh, vec3(Luminance(rayleigh)) * atmosphereModel_solar_irradiance, wetness * 0.5); // 雨天把瑞利散射去色重染。
		return (rayleigh + mie) * (1.0 - wetness * 0.4) * LMS * OMNI_SKY_BRIGHTNESS; // 合成后按雨天压暗并转色适应空间，再乘天空亮度选项。
}
#endif // 文件守卫结束。
