/*
天空的宿主接线：读取 Minecraft 输入、调用通用库并写出结果。
调用位置：原引用 `effects/sky/sky.glsl` 的程序改为引用本文件。
可复制示例：下方函数保留原有效果入口的签名，调用方式不变。
设计原因与取舍：选项留在效果层，算法在通用库，本文件只做宿主数据与算法之间的转换。
*/
#ifndef OMNI_RENDER_SKY_SKY_INCLUDED
#define OMNI_RENDER_SKY_SKY_INCLUDED
#include "/effects/sky/sky.glsl"
/*
天空：天空效果入口，集中定义全部天空、日月、星空相关选项与大气内部常数，并按依赖顺序引入同目录算法文件。
调用位置：延迟三号画天空像素时调用 `GetSkyRadiance`、`CalculateStars`、`RenderSunDisc`、`RenderMoonDisc`；
    三号把上半屏天空盒写成三维贴图时调用 `UnprojectSky` 与 `GetSkyRadiance`；
    合成阶段把世界方向投回天空盒坐标时调用 `ProjectSky`；
    合成顶点阶段算日月与环境光色时调用 `GetSunAndSkyIrradiance`；
    体积云与平面云算远处的空气透视时调用 `GetSkyRadianceToPoint`。
可复制示例（`camera` 是米制世界位置，`worldDir` 是单位世界方向）：
    `vec3 atmosphere = GetSkyRadiance(camera, worldDir, worldSunVector, worldMoonVector, horizon, transmittance, ray_r_mu_intersects_ground);`
    `vec3 sunIrradiance = GetSunAndSkyIrradiance(camera, worldSunVector, -worldSunVector, moonIrradiance, sunSkyIrradiance, moonSkyIrradiance);`
    `vec2 skyUv = ProjectSky(worldDir, tileSize);`
设计原因与取舍：
    本文件是天空效果入口，选项与内部常数只在这里定义一次，算法体按内容拆到同目录文件，引入顺序与拆分前一致：
    预计算大气 `effects/sky/atmosphere_model.glsl`；日月圆盘 `effects/sky/sun_moon.glsl`；
    月亮轨道、月食与月相 `effects/sky/moon_orbit.glsl`；星空 `effects/sky/stars.glsl`；天空盒投影 `effects/sky/skybox.glsl`。
    天空不是实时积分，而是读预计算大气三维贴图；加载器在延迟与合成阶段把八号画面换成那张数据，
    所以这里只做查表与相位函数组合，代价与分辨率无关。
    调用前提（iterationT 原样保留）：调用方必须先声明 `texelCoord`、`worldSunVector`、`worldMoonVector` 等全局量；
    这些量由绘制主体在引入本文件前给出，本文件不重复声明。
    天空散射系数（Eclipse 的 `Sky_Brightness` 与瑞利、米氏系数）放在 `effects/sky/skyscatter.glsl`：
    这里只把瑞利、米氏倍率与天空亮度乘进查表结果，默认全一、画面不变。
    月亮轨道、月食与月相来自 Eclipse：自定义轨道在顶点阶段由世界时间闭式算出，日月解耦后才可能月食；
    真实月亮模式需要的月亮贴图与法线贴图是 Eclipse 自带文件，本项目没有，缺少时退回程序圆盘。
    月亮颜色的三通道倍率来自 Eclipse `lib/settings.glsl:402-404`：Eclipse 把它直接当月亮色，
    本项目已有色温路径，这里改成乘在基础月亮色上的倍率，默认全一、画面不变。
    资源包天空与其它天文量不同：它不靠查表，而是让原版与资源包把天空几何画进零号画面再读回来，
    所以本文件只放选项；天空几何的分流在 `rendering/celestial.glsl`，底色读取与合成在 `effects/sky/skyrender.glsl`。
*/
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
// 太阳色与辐照：提供 `omniSunTint()`，给太阳直射与太阳圆盘做相对染色；默认取值下返回全一、不改画面。
#include "/rendering/sky/suncolor.glsl"
// 天空散射系数：提供 `omniSkyRayleighTint()` 与 `omniSkyMieTint()`，给瑞利与米氏散射做逐通道倍率；默认全一、不改画面。
#include "/rendering/sky/skyscatter.glsl"
// 预计算大气：球面几何、密度剖面、贴图查表、透过率、辐照度与天空辐射。
#include "/rendering/sky/atmosphere_model.glsl"
// 日月圆盘：把日月光点画成天空上的圆盘。
#include "/rendering/sky/sun_moon.glsl"
// 月亮轨道、月食与月相：自定义轨道、月相与真实月亮。
#include "/rendering/sky/moon_orbit.glsl"
// 星空：Eclipse 星场，供主世界与末地共用。
#include "/rendering/sky/stars.glsl"
// 天空盒投影：世界方向与天空盒图坐标的互逆换算。
#include "/rendering/sky/skybox.glsl"
#endif // OMNI_RENDER_SKY_SKY_INCLUDED
