/*
天空：预计算大气散射、日月圆盘、星空与天空盒投影，供背景天空、屏幕外反射与光照共用。
调用位置：延迟三号主体画天空像素时调用 `GetSkyRadiance`、`CalculateStars`、`RenderSunDisc`、`RenderMoonDisc`；
    三号主体把上半屏天空盒写成三维贴图时调用 `UnprojectSky` 与 `GetSkyRadiance`；
    合成阶段把世界方向投回天空盒坐标时调用 `ProjectSky`；
    合成顶点阶段算日月与环境光色时调用 `GetSunAndSkyIrradiance`；
    体积云与平面云算远处的空气透视时调用 `GetSkyRadianceToPoint`。
可复制示例（`camera` 是米制世界位置，`worldDir` 是单位世界方向）：
    `vec3 atmosphere = GetSkyRadiance(camera, worldDir, worldSunVector, worldMoonVector, horizon, transmittance, ray_r_mu_intersects_ground);`
    `vec3 sunIrradiance = GetSunAndSkyIrradiance(camera, worldSunVector, -worldSunVector, moonIrradiance, sunSkyIrradiance, moonSkyIrradiance);`
    `vec2 skyUv = ProjectSky(worldDir, tileSize);`
设计原因与取舍：
    天空不是实时积分，而是读预计算大气三维贴图；加载器在延迟与合成阶段把八号画面换成那张数据，
    所以这里只做查表与相位函数组合，代价与分辨率无关。
    调用前提（iterationT 原样保留）：调用方必须先声明 `texelCoord`、`worldSunVector`、`worldMoonVector` 等全局量；
    这些量由绘制主体在引入本文件前给出，本文件不重复声明。
    本文件还承载原程序写在 `deferred3`、`CompositeVS`、`SSR` 里的天空相关小函数，见移植合同第九点五节的去重约定。
*/
#ifndef OMNI_SKY_INCLUDED
#define OMNI_SKY_INCLUDED
// @effect {"label":{"zh_cn":"天空","en_us":"Sky"}}
// @option {"label":{"zh_cn":"天空地平线","en_us":"Sky Horizon"},"description":{"zh_cn":"打开后地平线方向也算被行星表面挡住的大气，日出时地平线一带更真实。","en_us":"Also shades the horizon band below the eye as ground-lit atmosphere."}}
//#define OMNI_ATMO_HORIZON
// @option {"label":{"zh_cn":"反射天空盒地平线","en_us":"Skybox Horizon"},"description":{"zh_cn":"反射用的天空盒是否同样处理地平线方向。","en_us":"Whether the reflection skybox shades the horizon the same way."}}
#define OMNI_ATMO_REFLECTION_HORIZON
// @option {"label":{"zh_cn":"月亮纹理平滑","en_us":"Moon Texture Smoothing"},"description":{"zh_cn":"用双线性过滤读月亮贴图，低分辨率资源包会显得更糊。","en_us":"Reads the moon texture with bilinear filtering; low-resolution packs look softer."}}
//#define OMNI_BILINEAR_MOON_TEXTURE
// @option {"label":{"zh_cn":"天空盒纹理平滑","en_us":"Skybox Texture Smoothing"},"description":{"zh_cn":"用双线性过滤读天空盒贴图，低分辨率资源包会显得更糊。","en_us":"Reads the skybox texture with bilinear filtering; low-resolution packs look softer."}}
//#define OMNI_BILINEAR_SKYBOX_TEXTURE
// @option {"label":{"zh_cn":"月亮纹理","en_us":"Moon Texture"},"description":{"zh_cn":"用资源包的月亮贴图代替内置圆盘。","en_us":"Uses the resource pack moon texture instead of the built-in disc."}}
#define OMNI_MOON_TEXTURE
// @option {"label":{"zh_cn":"夜间亮度比值","en_us":"Night Brightness"},"description":{"zh_cn":"夜间环境光相对白天环境光的比值，越大夜里越亮。","en_us":"Night ambient light relative to day; larger makes nights brighter."},"slider":true}
#define OMNI_NIGHT_BRIGHTNESS 0.0003 // [0.0 0.0001 0.00015 0.0002 0.0003 0.0005 0.0007 0.001 0.0015 0.002 0.003 0.005 0.007 0.01 1.0]
// @option {"label":{"zh_cn":"天空盒纹理","en_us":"Skybox Texture"},"description":{"zh_cn":"用资源包的天空盒贴图叠在天空上。","en_us":"Overlays the resource pack skybox texture on the sky."}}
//#define OMNI_SKYBOX_TEXTURE
// @option {"label":{"zh_cn":"反射天空盒分辨率","en_us":"Skybox Resolution"},"description":{"zh_cn":"反射里天空贴图的边长，越高越清晰也越费性能。","en_us":"Side length of the reflected sky image; higher is sharper and costlier."},"values":{"32.0":{"zh_cn":"极低","en_us":"Lowest"},"64.0":{"zh_cn":"低","en_us":"Low"},"128.0":{"zh_cn":"中","en_us":"Medium"},"256.0":{"zh_cn":"高","en_us":"High"},"512.0":{"zh_cn":"极高","en_us":"Very high"}}}
#define OMNI_SKY_IMAGE_RESOLUTION 64.0 // [32.0 48.0 64.0 96.0 128.0 192.0 256.0 384.0 512.0]
// @option {"label":{"zh_cn":"纹理亮度","en_us":"Texture Brightness"},"description":{"zh_cn":"原版星星、月亮贴图和天空盒的亮度倍率。","en_us":"Brightness multiplier for vanilla stars, the moon texture and the skybox."},"slider":true}
#define OMNI_SKY_TEXTURE_BRIGHTNESS 1.0 // [0.0 0.05 0.1 0.15 0.2 0.3 0.5 0.7 1.0 1.5 2.0 3.0 5.0 7.0 10.0 15.0 20.0 30.0 50.0 70.0 100.0]
// @option {"label":{"zh_cn":"星星类型","en_us":"Star Type"},"description":{"zh_cn":"关为没有星星，点状为按方向生成的星点，原版为资源包星空贴图。","en_us":"Off has no stars, Dots draws procedural points, Vanilla uses the pack sky texture."},"values":{"0":{"zh_cn":"关","en_us":"Off"},"1":{"zh_cn":"点状","en_us":"Dots"},"2":{"zh_cn":"原版","en_us":"Vanilla"}}}
#define OMNI_STAR_TYPE 1 // [0 1 2]
// @option {"label":{"zh_cn":"日月倾角","en_us":"Sun Path Rotation"},"description":{"zh_cn":"日月运动轨迹相对原版轨迹的倾角，Iris 直接读取该原生常量。","en_us":"Tilt of the sun and moon path versus vanilla; Iris reads this native constant."}}
const float sunPathRotation = -30.0; // [-90.0 -89.0 -88.0 -87.0 -86.0 -85.0 -84.0 -83.0 -82.0 -81.0 -80.0 -79.0 -78.0 -77.0 -76.0 -75.0 -74.0 -73.0 -72.0 -71.0 -70.0 -69.0 -68.0 -67.0 -66.0 -65.0 -64.0 -63.0 -62.0 -61.0 -60.0 -59.0 -58.0 -57.0 -56.0 -55.0 -54.0 -53.0 -52.0 -51.0 -50.0 -49.0 -48.0 -47.0 -46.0 -45.0 -44.0 -43.0 -42.0 -41.0 -40.0 -39.0 -38.0 -37.0 -36.0 -35.0 -34.0 -33.0 -32.0 -31.0 -30.0 -29.0 -28.0 -27.0 -26.0 -25.0 -24.0 -23.0 -22.0 -21.0 -20.0 -19.0 -18.0 -17.0 -16.0 -15.0 -14.0 -13.0 -12.0 -11.0 -10.0 -9.0 -8.0 -7.0 -6.0 -5.0 -4.0 -3.0 -2.0 -1.0 0.0 1.0 2.0 3.0 4.0 5.0 6.0 7.0 8.0 9.0 10.0 11.0 12.0 13.0 14.0 15.0 16.0 17.0 18.0 19.0 20.0 21.0 22.0 23.0 24.0 25.0 26.0 27.0 28.0 29.0 30.0 31.0 32.0 33.0 34.0 35.0 36.0 37.0 38.0 39.0 40.0 41.0 42.0 43.0 44.0 45.0 46.0 47.0 48.0 49.0 50.0 51.0 52.0 53.0 54.0 55.0 56.0 57.0 58.0 59.0 60.0 61.0 62.0 63.0 64.0 65.0 66.0 67.0 68.0 69.0 70.0 71.0 72.0 73.0 74.0 75.0 76.0 77.0 78.0 79.0 80.0 81.0 82.0 83.0 84.0 85.0 86.0 87.0 88.0 89.0 90.0]
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
// 共用数学与加载器输入，显式引入而不依赖调用顺序。
#include "/common/uniforms.glsl"
#include "/common/math.glsl"
// 把半径夹进大气层范围内，越界时按最近的边界算。
float ClampRadius(float r){
	return clamp(r, atmosphereModel_bottom_radius, atmosphereModel_top_radius); // 下不低于地面、上不超过层顶。
}
// 安全开方：负零以下一律当零，避免判别式因浮点误差变负时出非数。
float SafeSqrt(float a){
	return sqrt(max(a, 0.0)); // 负数开到零。
}
// 太阳圆盘：视线越接近太阳方向越亮，边缘由平滑曲线收口。
vec3 RenderSunDisc(vec3 worldDir, vec3 sunDir){
	float d = dot(worldDir, sunDir); // 视线与太阳方向的夹角余弦。
	float size = 5e-5; // 圆盘角半径，越小圆盘越细。
	float hardness = 4e4; // 边缘硬度，越大边缘越陡。
	float disc = curve(saturate((d - (1.0 - size)) * hardness)); // 从中心到边缘的平滑遮罩。
	disc *= disc; // 平方让边缘更收。
	return vec3(1.1114, 0.9756, 0.9133) * disc; // 太阳偏暖的白色。
}
// 月亮圆盘：形状同太阳，但边缘更硬、亮度单独交给选项。
float RenderMoonDisc(vec3 worldDir, vec3 moonDir){
	float d = dot(worldDir, moonDir); // 视线与月亮方向的夹角余弦。
	float size = 5e-5; // 圆盘角半径。
	float hardness = 1e5; // 边缘硬度，比太阳更硬。
	float disc = curve(saturate((d - (1.0 - size)) * hardness)); // 月亮遮罩。
	return disc * disc; // 平方收口后返回零到一的亮度。
}
// 反射里的月亮圆盘：反射天空盒分辨率低，用更大的角半径换取可见。
float RenderMoonDiscReflection(vec3 worldDir, vec3 moonDir){
	float d = dot(worldDir, moonDir); // 夹角余弦。
	float size = 0.0025; // 反射用更大的角半径。
	float hardness = 300.0; // 边缘更软。
	float disc = curve(saturate((d - (1.0 - size)) * hardness)); // 反射月亮遮罩。
	return disc * disc; // 返回零到一亮度。
}
// 视线到大气层顶的距离，解视线与顶球面的方程取远根。
float DistanceToTopAtmosphereBoundary(
	float r,
	float mu
	){
		float discriminant = r * r * (mu * mu - 1.0) + atmosphereModel_top_radius * atmosphereModel_top_radius; // 交点判别式。
		return max(-r * mu + SafeSqrt(discriminant), 0.0); // 取朝向层顶一侧的根，负数归零。
}
// 视线到大气层底的距离，解视线与底球面的方程取近根。
float DistanceToBottomAtmosphereBoundary(
	float r,
	float mu
	){
		float discriminant = r * r * (mu * mu - 1.0) + atmosphereModel_bottom_radius * atmosphereModel_bottom_radius; // 球面交点判别式。
		return max(-r * mu - SafeSqrt(discriminant), 0.0); // 取靠近相机一侧的根。
}
// 判断一条朝下的视线是否真的打到地面球。
bool RayIntersectsGround(
	float r,
	float mu
	){
		return mu < 0.0 && r * r * (mu * mu - 1.0) + atmosphereModel_bottom_radius * atmosphereModel_bottom_radius >= 0.0; // 朝下且判别式非负才相交。
}
// 瑞利与米氏密度剖面：以二为底的指数衰减，系数已经积分好。
float GetProfileDensityRayleighMie(
	float exp_scale,
	float altitude
	){
		return exp2(exp_scale * altitude); // 高度越高密度越低。
}
// 臭氧密度剖面：在转折高度以下是一段斜线，以上是另一段斜线。
float GetProfileDensityAbsorption(
	float width,
	vec4 profile,
	float altitude
	){
		return altitude < width ? // 转折高度以下用前两个系数。
			profile.x * altitude + profile.y :
			profile.z * altitude + profile.w; // 以上用后两个系数。
}
// 把零到一的比例映射到贴图坐标的像素中心，避免采到子图交界。
float GetTextureCoordFromUnitRange(float x, float texture_size) {
	return 0.5 / texture_size + x * (1.0 - 1.0 / texture_size); // 内缩半像素。
}
// 把子图内部的比例映射到拼合大图上的坐标，子图在大图里也内缩半像素。
float GetCombinedTextureCoordFromUnitRange(float x, float original_texture_size, float combined_texture_size) {
	return 0.5 / combined_texture_size + x * (original_texture_size / combined_texture_size - 1.0 / combined_texture_size); // 按子图尺寸缩放。
}
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
		return sun_irradiance * LMS; // 太阳直射乘色适应矩阵后返回。
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
		vec3 rayleigh = sun_scattering * RayleighPhaseFunction(sun_nu) // 太阳侧瑞利散射乘瑞利相位。
					 + moon_scattering * RayleighPhaseFunction(moon_nu) * OMNI_NIGHT_BRIGHTNESS; // 月亮侧同理并按夜间亮度缩放。
		vec3 mie = sun_single_mie_scattering * MiePhaseFunction(atmosphereModel_mie_phase_function_g, sun_nu) // 太阳侧米氏散射乘米氏相位。
				+ moon_single_mie_scattering * MiePhaseFunction(atmosphereModel_mie_phase_function_g, moon_nu) * OMNI_NIGHT_BRIGHTNESS; // 月亮侧同理。
		rayleigh = mix(rayleigh, vec3(Luminance(rayleigh)) * atmosphereModel_solar_irradiance, wetness * 0.5); // 雨天把瑞利散射去色并按太阳谱重新染色。
		return (rayleigh + mie + groundDiffuse) * (1.0 - wetness * 0.4) * LMS; // 合成后按雨天压暗并转色适应空间。
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
		vec3 rayleigh = sun_scattering * RayleighPhaseFunction(sun_nu) // 太阳侧瑞利散射。
					 + moon_scattering * RayleighPhaseFunction(moon_nu) * OMNI_NIGHT_BRIGHTNESS; // 月亮侧瑞利散射。
		vec3 mie = sun_single_mie_scattering * MiePhaseFunction(atmosphereModel_mie_phase_function_g, sun_nu) // 太阳侧米氏散射。
				+ moon_single_mie_scattering * MiePhaseFunction(atmosphereModel_mie_phase_function_g, moon_nu) * OMNI_NIGHT_BRIGHTNESS; // 月亮侧米氏散射。
		rayleigh = mix(rayleigh, vec3(Luminance(rayleigh)) * atmosphereModel_solar_irradiance, wetness * 0.5); // 雨天把瑞利散射去色重染。
		return (rayleigh + mie) * (1.0 - wetness * 0.4) * LMS; // 合成后按雨天压暗并转色适应空间。
}
// 校次把球面方向绕太阳轴旋转，让星点跟着天体倾斜，再按方向切格撒星。
// 太阳方向作为参数传入：天空效果会被多个程序引入，直接在函数里读全局量会让不需要光色的程序编译失败。
vec3 CalculateStars(vec3 worldDir, vec3 sunVector){
	const float scale = 384.0; // 方向切格的密度，越大星星越密越小。
	const float coverage = 0.007; // 亮格占所有格子的比例。
	const float maxLuminance = 0.05; // 最亮的一颗星的亮度。
	const float minTemperature = 4000.0; // 星色温下限，偏橙。
	const float maxTemperature = 8000.0; // 星色温上限，偏蓝。
	float cosine = dot(sunVector,  vec3(0, 0, 1)); // 太阳轴与参考轴夹角余弦。
	vec3 axis = cross(sunVector,  vec3(0, 0, 1)); // 旋转轴。
	float cosecantSquared = 1.0 / dot(axis, axis); // 旋转公式里的比例因子。
	worldDir = cosine * worldDir + cross(axis, worldDir) + (cosecantSquared - cosecantSquared * cosine) * dot(axis, worldDir) * axis; // 按罗德里格公式旋转方向。
	vec3  p = worldDir * scale; // 缩放后切格。
	ivec3 i = ivec3(floor(p)); // 格子整数坐标。
	vec3  f = p - i; // 格内小数偏移。
	float r = dot(f - 0.5, f - 0.5); // 到格子中心的距离平方，用来收窄星点。
	vec3 i3 = fract(i * vec3(443.897, 441.423, 437.195)); // 逐格散列。
	i3 += dot(i3, i3.yzx + 19.19); // 再做一次混合。
	vec2 hash = fract((i3.xx + i3.yz) * i3.zy); // 得到两个零到一的散列值。
	hash.y = 2.0 * hash.y - 4.0 * hash.y * hash.y + 3.0 * hash.y * hash.y * hash.y; // 把色温分布压向中间。
	float c = remapSaturate(hash.x, 1.0 - coverage, 1.0); // 只有少量格子亮。
	return (maxLuminance * remapSaturate(r, 0.25, 0.0) * c * c) * Blackbody(mix(minTemperature, maxTemperature, hash.y)); // 亮度乘色温得到星点颜色。
}
// 把天空盒三维贴图上的一个纹素坐标反解成世界方向，与 `ProjectSky` 互为逆。
vec3 UnprojectSky(vec2 texel, float tileSize){
	float tileSizeDivide = 1.0 / (0.5 * tileSize - 1.5); // 纹素到方向的缩放系数。
	vec3 direction = vec3(0.0); // 待求的世界方向。
	if (texel.x < tileSize) { // 第一张面，朝 x 正负。
		direction.x = step(tileSize, texel.y) * 2.0 - 1.0; // 纵半决定正负。
		direction.y = (texel.x - tileSize * 0.5) * tileSizeDivide; // 横坐标映射到一个轴。
		direction.z = (texel.y - tileSize * (step(tileSize, texel.y) + 0.5)) * tileSizeDivide; // 纵坐标映射到另一个轴。
	} else if (texel.x < 2.0 * tileSize) { // 第二张面，朝 y 正负。
		direction.x = (texel.x - tileSize * 1.5) * tileSizeDivide; // 横坐标映射到一个轴。
		direction.y = step(tileSize, texel.y) * 2.0 - 1.0; // 纵半决定正负。
		direction.z = (texel.y - tileSize * (step(tileSize, texel.y) + 0.5)) * tileSizeDivide; // 纵坐标映射到另一个轴。
	} else { // 第三张面，朝 z 正负。
		direction.x = (texel.x - tileSize * 2.5) * tileSizeDivide; // 横坐标映射到一个轴。
		direction.y = (texel.y - tileSize * (step(tileSize, texel.y) + 0.5)) * tileSizeDivide; // 纵坐标映射到另一个轴。
		direction.z = step(tileSize, texel.y) * 2.0 - 1.0; // 纵半决定正负。
	}
	return normalize(direction); // 单位世界方向。
}
// 把一个世界方向投到天空盒三维贴图上，与 `UnprojectSky` 互为逆；原程序两处各写一份，按合同只保留这里一份。
// 调用前提：`screenSize` 与 `pixelSize` 已由绘制主体声明。
vec2 ProjectSky(vec3 dir, float tileSize){
	float tileSizeDivide = 0.5 * tileSize - 1.5; // 方向到纹素的缩放系数。
	vec3 adir = abs(dir); // 三个分量的绝对值，用来选主轴。
	vec2 texel; // 待求的纹素坐标。
	if (adir.x > adir.y && adir.x > adir.z){ // x 份量最大时用第一张面。
		dir /= adir.x; // 归一化主轴分量。
		texel.x = dir.y * tileSizeDivide + tileSize * 0.5; // 一个轴映射到横坐标。
		texel.y = dir.z * tileSizeDivide + tileSize * (step(0.0, dir.x) + 0.5); // 另一个轴映射到纵坐标，符号决定上下半。
	}else if (adir.y > adir.x && adir.y > adir.z){ // y 分量最大时用第二张面。
		dir /= adir.y; // 归一化主轴分量。
		texel.x = dir.x * tileSizeDivide + tileSize * 1.5; // 偏移到第二张面。
		texel.y = dir.z * tileSizeDivide + tileSize * (step(0.0, dir.y) + 0.5); // 符号决定上下半。
	}else{ // 否则用第三张面。
		dir /= adir.z; // 归一化主轴分量。
		texel.x = dir.x * tileSizeDivide + tileSize * 2.5; // 偏移到第三张面。
		texel.y = dir.y * tileSizeDivide + tileSize * (step(0.0, dir.z) + 0.5); // 符号决定上下半。
	}
	texel.y += ceil(screenSize.y * 0.5 + 1.0); // 天空盒贴图放在上半屏，纵坐标抬到上半屏起点。
	return texel * pixelSize; // 纹素坐标换成零到一的贴图坐标。
}
#endif // 文件守卫结束。
