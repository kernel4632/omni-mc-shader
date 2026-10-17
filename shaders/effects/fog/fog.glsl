/*
雾与空气：照 iterationT `Lib/IndividualFounctions/VolumetricFog.glsl`、`UnderwaterVolumetricFog.glsl`
与 `Lib/BasicFounctions/VanillaComposite.glsl` 的 `VanillaFog` 一比一移植。
职责分成四块：
  一、选项与内部常数：体积雾、水下体积雾、地面大气散射、原版雾开关与体积光照步数，全项目只在这里定义一次；
  二、体积雾：`VolumetricFog` 沿视线与光方向在雾里步进，算出体积雾颜色与透射率；
  三、水下体积雾：`UnderwaterVolumetricFog` 在水下沿视线步进阴影可见性并叠焦散，画出蓝色光柱；
  四、地面大气散射与原版雾：`LandAtmosphericScattering` 补地表方向的空气散射，`VanillaFog` 处理失明、黑暗与岩浆雪盲。
调用位置：
  `rendering/composite.glsl` 的 `composite2` 程序在反射里补体积雾与地表散射；
  `rendering/composite.glsl` 的 `composite5` 程序对整幅画面补体积雾、水下体积雾、地表散射与原版雾。
可复制示例：
  `VolumetricFog(color, vec3(0.0), rayWorldPos, worldDir, globalCloudShadow, fogTimeFactor, fogTransmittance);`
  `LandAtmosphericScattering(color, waterDist, vec3(0.0), rayWorldPos, worldDir, materialMask.sky > 0.5);`
  `VanillaFog(color, waterDist);`
调用前提（按 iterationT 原程序的引用顺序，由绘制主体先声明这些全局量）：
  `worldShadowVector`、`worldSunVector`、`colorSkylight`、`colorShadowlight`、`cameraPosition`、
  `gbufferModelViewInverse`、`wetness`、`isEyeInWater`、`eyeBrightnessSmoothCurved`、`timeNoon`、`timeMidnight`、
  `screenSize`、`pixelSize`、`colortex7`、`shadowtex0`、`shadowtex1` 由合成主程序声明；
  `OMNI_SKYLIGHT_INTENSITY`、`OMNI_SUNLIGHT_INTENSITY`、`OMNI_CAVE_MODE` 由 `effects/lighting/sunlight.glsl` 提供，绘制主体需在本文件之前引入它；
  `OMNI_UNDERWATER_FOG`、`OMNI_WATERFOG_DENSITY` 由 `effects/water/water.glsl` 提供，本文件已在函数定义之后引入它。
关键设计原因与取舍：
  `VFOG_LQ` 由 `composite2` 程序自己打开，体积雾在那一步只用三步，省下反射通道的开销，本文件保留原宏名；
  `GetWavesNormalFromTex` 与 `CalculateWaterCaustics` 已由 `effects/shadow/shadow.glsl` 提供，本文件不重复定义；水下体积雾需要的那份焦散与阴影文件不同名，按合同改名为 `CalculateUnderwaterCaustics` 并记入偏离记录；
  原版雾的失明与黑暗只在加载器给出对应状态时才生效，默认关闭，画面与 iterationT 一致。
*/
#ifndef OMNI_FOG_INCLUDED // 只引入一次，避免选项与函数重复定义。
#define OMNI_FOG_INCLUDED // 置上标记，后续再次引用直接跳过。

// @effect {"label":{"zh_cn":"雾与空气","en_us":"Fog & air"}}
// @option {"label":{"zh_cn":"体积雾","en_us":"Volumetric fog"},"description":{"zh_cn":"沿视线在空气里步进得到的体积雾与光柱。","en_us":"Volumetric fog and light shafts marched along the view."}}
#define OMNI_VFOG
// @option {"label":{"zh_cn":"体积雾噪声类型","en_us":"Volumetric fog noise"},"description":{"zh_cn":"仅高度衰减只有一层随高度变浓的雾，团雾用三维噪声造出雾团。","en_us":"Height-only gives one layer that thickens with altitude; Wispy uses 3D noise for fog banks."},"values":{"0":{"zh_cn":"仅高度衰减","en_us":"Height only"},"1":{"zh_cn":"团雾","en_us":"Wispy"}}}
#define OMNI_VFOG_NOISE_TYPE 0 // [0 1]
// @option {"label":{"zh_cn":"体积雾采样质量","en_us":"Volumetric fog quality"},"description":{"zh_cn":"体积雾与水下体积雾沿视线的采样次数，越高越干净也越慢。","en_us":"View samples for volumetric fog and underwater fog; higher is cleaner and slower."},"slider":true}
#define OMNI_VFOG_QUALITY 6 // [4 6 8 10 12 14 16 18 20 22 24 28 32 48 64 128]
// @option {"label":{"zh_cn":"体积雾密度","en_us":"Volumetric fog density"},"description":{"zh_cn":"噪声控制的雾团密度，越大雾越浓。","en_us":"Density of the noise-driven fog; larger is thicker."},"slider":true}
#define OMNI_VFOG_DENSITY 0.01 // [0.001 0.0015 0.002 0.003 0.005 0.007 0.01 0.015 0.02 0.03 0.05 0.07 0.1 0.15 0.2 0.3 0.5 0.7 1.0]
// @option {"label":{"zh_cn":"体积雾基础密度","en_us":"Volumetric fog base density"},"description":{"zh_cn":"不靠噪声的一张基础雾层密度，取零时只有噪声雾。","en_us":"Flat fog layer density independent of noise; zero leaves only the noise fog."},"slider":true}
#define OMNI_VFOG_DENSITY_BASE 1.0 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.2 1.4 1.6 1.8 2.0 3.0 5.0 7.0 10.0 15.0 20.0 30.0 50.0 70.0 100.0]
// @option {"label":{"zh_cn":"体积雾衰减高度","en_us":"Volumetric fog height"},"description":{"zh_cn":"仅高度衰减模式下两档高度之间最浓，超出后衰减；团雾模式下最高点落在较高的这一档。","en_us":"Height-only keeps peak density between the two heights; Wispy puts the peak at the higher one."},"slider":true}
#define OMNI_VFOG_HEIGHT 65.0 // [-100.0 -90.0 -80.0 -70.0 -60.0 -50.0 -40.0 -30.0 -20.0 -10.0 0.0 10.0 20.0 30.0 40.0 45.0 50.0 55.0 60.0 65.0 70.0 75.0 80.0 85.0 90.0 95.0 100.0 105.0 110.0 115.0 120.0 125.0 130.0 135.0 140.0 145.0 150.0 155.0 160.0 165.0 170.0 175.0 180.0 185.0 190.0 195.0 200.0 210.0 220.0 230.0 240.0 250.0 260.0 270.0 280.0 290.0 300.0 310.0 320.0 350.0 400.0 450.0 500.0 600.0 700.0 800.0 900.0 1000.0]
// @option {"label":{"zh_cn":"体积雾衰减高度二","en_us":"Volumetric fog height 2"},"description":{"zh_cn":"与上一档一起决定体积雾最浓的高度区间。","en_us":"With the other height, sets the band where volumetric fog is densest."},"slider":true}
#define OMNI_VFOG_HEIGHT_2 50.0 // [-100.0 -90.0 -80.0 -70.0 -60.0 -50.0 -40.0 -30.0 -20.0 -10.0 0.0 10.0 20.0 30.0 40.0 45.0 50.0 55.0 60.0 65.0 70.0 75.0 80.0 85.0 90.0 95.0 100.0 105.0 110.0 115.0 120.0 125.0 130.0 135.0 140.0 145.0 150.0 155.0 160.0 165.0 170.0 175.0 180.0 185.0 190.0 195.0 200.0 210.0 220.0 230.0 240.0 250.0 260.0 270.0 280.0 290.0 300.0 310.0 320.0 350.0 400.0 450.0 500.0 600.0 700.0 800.0 900.0 1000.0]
// @option {"label":{"zh_cn":"体积雾衰减距离","en_us":"Volumetric fog falloff"},"description":{"zh_cn":"体积雾离开最浓高度后衰减的快慢，越大衰减越慢。","en_us":"How fast fog fades away from its densest height; larger fades slower."},"slider":true}
#define OMNI_VFOG_FALLOFF 40.0 // [1.0 2.0 3.0 4.0 5.0 6.0 7.0 8.0 9.0 10.0 11.0 12.0 13.0 14.0 15.0 16.0 17.0 18.0 19.0 20.0 21.0 22.0 23.0 24.0 25.0 26.0 27.0 28.0 29.0 30.0 31.0 32.0 33.0 34.0 35.0 36.0 37.0 38.0 39.0 40.0 41.0 42.0 43.0 44.0 45.0 46.0 47.0 48.0 49.0 50.0 51.0 52.0 53.0 54.0 55.0 56.0 57.0 58.0 59.0 60.0 61.0 62.0 63.0 64.0 65.0 66.0 67.0 68.0 69.0 70.0 71.0 72.0 73.0 74.0 75.0 76.0 77.0 78.0 79.0 80.0 81.0 82.0 83.0 84.0 85.0 86.0 87.0 88.0 89.0 90.0 91.0 92.0 93.0 94.0 95.0 96.0 97.0 98.0 99.0 100.0]
// @option {"label":{"zh_cn":"体积雾全时段启用","en_us":"Volumetric fog all day"},"description":{"zh_cn":"关闭时白天降低体积雾密度，打开后全天保持。","en_us":"Off thins the fog during the day; on keeps it constant around the clock."}}
//#define OMNI_VFOG_IGNORE_WORLDTIME
// @option {"label":{"zh_cn":"体积雾半透明染色","en_us":"Volumetric fog stained light"},"description":{"zh_cn":"透过彩色玻璃的阳光会被染色；仅支持部分显卡，可能出现额外开销。","en_us":"Tints sunlight passing through stained glass; supported on some GPUs only."}}
//#define OMNI_VFOG_STAINED
// @option {"label":{"zh_cn":"体积雾云影遮蔽","en_us":"Volumetric fog cloud shadow"},"description":{"zh_cn":"云影也压暗体积雾的受光，让光柱与云影一致。","en_us":"Cloud shadows also darken the lit fog so shafts match the cloud shadow."}}
//#define OMNI_VFOG_CLOUD_SHADOW
// @option {"label":{"zh_cn":"体积雾阳光强度","en_us":"Volumetric fog sunlight"},"description":{"zh_cn":"体积雾里阳光散射的强度，决定光柱多亮。","en_us":"Strength of sun scattering in the fog; how bright the shafts are."},"slider":true}
#define OMNI_VFOG_SUNLIGHT_DENSITY 1.0 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.2 1.4 1.6 1.8 2.0 3.0 5.0 7.0 10.0 15.0 20.0 30.0 50.0 70.0 100.0]
// @option {"label":{"zh_cn":"体积雾环境光强度","en_us":"Volumetric fog ambient"},"description":{"zh_cn":"体积雾整体环境色的强度，决定雾本身多亮。","en_us":"Strength of the fog's ambient colour; how bright the fog itself is."},"slider":true}
#define OMNI_VFOG_FOG_DENSITY 1.0 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.2 1.4 1.6 1.8 2.0 3.0 5.0 7.0 10.0 15.0 20.0 30.0 50.0 70.0 100.0]
// @option {"label":{"zh_cn":"体积光照","en_us":"Volumetric lighting"},"description":{"zh_cn":"体积雾自身对光照的吸收，光柱内部更暗、边缘更亮。","en_us":"Self-absorption of light inside the fog; darkens shaft interiors."}}
#define OMNI_VFOG_VOLUMETRIC_LIGHTING
// @option {"label":{"zh_cn":"体积光照吸收率","en_us":"Volumetric absorption"},"description":{"zh_cn":"体积光照的吸光强度，越大吸收越明显。","en_us":"Absorption strength of volumetric lighting; larger is darker."},"slider":true}
#define OMNI_VFOG_SUNLIGHT_ABSORPTION 1.0 // [0.1 0.15 0.2 0.3 0.5 0.7 1.0 1.5 2.0 3.0 5.0 7.0 10.0]
// @option {"label":{"zh_cn":"水下体积雾","en_us":"Underwater fog"},"description":{"zh_cn":"水下的蓝色光柱，由阳光穿过水面缝隙汇聚而成。","en_us":"Blue light shafts underwater, focused through gaps in the water surface."}}
#define OMNI_UNDERWATER_VFOG
// @option {"label":{"zh_cn":"水下体积雾密度","en_us":"Underwater fog density"},"description":{"zh_cn":"水下光柱的强度。","en_us":"Strength of the underwater light shafts."},"slider":true}
#define OMNI_UNDERWATER_VFOG_DENSITY 1.0 // [0.1 0.15 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.2 1.4 1.6 1.8 2.0 3.0 5.0 7.0 10.0 15.0 20.0 30.0 50.0 70.0 100.0]
// @option {"label":{"zh_cn":"地面大气散射","en_us":"Land atmospheric scattering"},"description":{"zh_cn":"地表方向空气对阳光的散射，给远处地形加一层空气感。","en_us":"Scattering of sunlight by the air toward the surface, adding aerial haze to distant land."}}
#define OMNI_LANDSCATTERING
// @option {"label":{"zh_cn":"地面大气散射强度","en_us":"Land scattering strength"},"description":{"zh_cn":"地面大气散射的整体强度。","en_us":"Overall strength of land atmospheric scattering."},"slider":true}
#define OMNI_LANDSCATTERING_STRENGTH 2.0 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.5 1.7 2.0 2.5 3.0 5.0 7.0 10.0 15.0 20.0 30.0 50.0 100.0]
// @option {"label":{"zh_cn":"地面大气散射距离","en_us":"Land scattering distance"},"description":{"zh_cn":"地面大气散射沿视线的累积倍率，越大越浓。","en_us":"Multiplier on the optical length for land scattering; larger is hazier."},"slider":true}
#define OMNI_LANDSCATTERING_DISTANCE 0.003 // [0.001 0.002 0.003 0.005 0.007 0.01 0.15 0.2 0.3 0.5 0.7 1.0]
// @option {"label":{"zh_cn":"地面大气散射阴影遮蔽","en_us":"Land scattering shadow"},"description":{"zh_cn":"在阴影区降低地面大气散射，避免阴影里也泛白。","en_us":"Reduces land scattering in shadowed areas so they do not wash out."}}
//#define OMNI_LANDSCATTERING_SHADOW
// @option {"label":{"zh_cn":"阴影遮蔽采样质量","en_us":"Land scattering shadow quality"},"description":{"zh_cn":"地面大气散射阴影的采样次数，越高噪点越少也越慢。","en_us":"Samples for the land scattering shadow; higher is cleaner and slower."},"slider":true}
#define OMNI_LANDSCATTERING_SHADOW_QUALITY 6 // [4 6 8 10 12 14 16 18 20 22 24 28 32 48 64 128]
// @option {"label":{"zh_cn":"禁用光照衰减","en_us":"Disable fog falloff"},"description":{"zh_cn":"关闭体积雾与地表散射随天空光等级的衰减；关掉后暗处雾气可能过强。","en_us":"Disables the skylight falloff of fog and land scattering; off may be too foggy in the dark."}}
//#define OMNI_INDOOR_FOG
// @option {"label":{"zh_cn":"反射中渲染体积雾","en_us":"Volumetric fog in reflections"},"description":{"zh_cn":"在屏幕反射里也补体积雾，反射不再是干净的镜面。","en_us":"Adds volumetric fog inside reflections so they are not mirror-clean."}}
#define OMNI_VFOG_REFLECTION
// @option {"label":{"zh_cn":"折射后渲染体积雾","en_us":"Volumetric fog after refraction"},"description":{"zh_cn":"在彩色玻璃后方的折射画面里补体积雾。","en_us":"Adds volumetric fog to the refracted image behind stained glass."}}
//#define OMNI_VFOG_REFRACTION
// @option {"label":{"zh_cn":"反射中渲染地表散射","en_us":"Land scattering in reflections"},"description":{"zh_cn":"在屏幕反射里也补地表大气散射。","en_us":"Adds land atmospheric scattering inside reflections."}}
//#define OMNI_LANDSCATTERING_REFLECTION
// @option {"label":{"zh_cn":"折射后渲染地表散射","en_us":"Land scattering after refraction"},"description":{"zh_cn":"在彩色玻璃后方的折射画面里补地表大气散射。","en_us":"Adds land scattering to the refracted image behind stained glass."}}
//#define OMNI_LANDSCATTERING_REFRACTION
// @option {"label":{"zh_cn":"下界雾强度","en_us":"Nether fog density"},"description":{"zh_cn":"下界与末地空气的浑浊程度。","en_us":"How murky the Nether and End air is."},"slider":true}
#define OMNI_NETHERFOG_DENSITY 1.0 // [0.0 0.1 0.15 0.2 0.3 0.5 0.7 1.0 1.5 2.0 3.0 5.0 7.0 10.0 15.0 20.0 30.0 50.0 70.0 100.0]
// @option {"label":{"zh_cn":"限制体积雾渲染距离","en_us":"Limit volumetric fog distance"},"description":{"zh_cn":"把体积雾渲染范围限制在一百区块以内，防止远处质量严重下降；可能导致远处体积雾缺失。","en_us":"Limits fog rendering to about 100 chunks to avoid quality collapse; may cut fog in the far distance."}}
#define OMNI_DH_LIMIT_VFOG_DIST

// --- 内部常数：原 `Settings.glsl` 里不进菜单的取值，名字保持原名 ---
#define VFOG_SUNLIGHT_STEPS 4 // 体积光照沿阳光方向的步数。
#define VFOG_SUNLIGHT_STEPLENGTH 5.0 // 体积光照沿阳光方向的起始步长，单位米，每步放大一点五倍。

// 数学提供相位函数与曲线，蓝噪声提供步进抖动，阴影提供阴影图坐标、焦散与波法线，天空云提供大气数据与云影，光照提供强度选项。
#include "/common/math.glsl"
#include "/common/noise.glsl"
#include "/effects/shadow/shadow.glsl"
#include "/effects/sky/sky.glsl"
#include "/effects/cloud/cloud.glsl"
#include "/effects/lighting/sunlight.glsl"
// 原版雾用失明与黑暗的调试开关 `OMNI_DISABLE_BLINDNESS_DARKNESS`，它的归属文件是颜色效果，这里引入才拿到定义。
#include "/effects/color/color.glsl"

// --- 体积雾：相位、噪声与密度 ---
// 粉末效应：光穿过一层薄雾时，正对光源方向更亮，背光方向的雾壁反而更暗，模拟粒子间的多次散射。
float PowderEffect(float absorption, float lightingAbsorption, float VdotL){
	return mix((1.0 - absorption) * (1.0 - lightingAbsorption), 1.0, VdotL * 0.5 + 0.5); // 采样点两侧的剩余光越少粉末效应越强。
}

// 雾的相位：前向与后向两个米氏相位加权，得到雾里比较均匀的散射方向性。
float FogPhase(float VdotL){
	return MiePhaseFunction(-0.4, VdotL) * 0.3 + MiePhaseFunction(0.5, VdotL) * 0.7; // 后向占三成、前向占七成。
}

// 多次散射相位：把相位按指数缩放的夹角重复四次，模拟光在雾里多次反弹后更均匀。
void MultiScatteringPhases(float VdotL, inout float phases[4]){
	float cn = 1.0; // 每一级的夹角缩放，从一倍开始逐级减半。

	for (int i = 0; i < 4; i++, cn *= 0.5){ // 四次，每次夹角缩放减半。
		phases[i] = FogPhase(VdotL * cn); // 记录这一级的相位。
	}
}

// 三维噪声：用噪声贴图的两通道做一次三线性插值，得到零到一的雾密度。
// 为什么用噪声贴图而不是实时噪声：贴图里已经烘好一层分布，采样代价低，也保证全屏可重复。
float Calculate3DNoise(vec3 position){
	vec3 p = floor(position); // 整数格。
	vec3 f = position - p; // 格内小数偏移。

	f = curve(f); // 用三次曲线平滑小数，插值更自然。

	vec2 uv = 17.0 * p.z + p.xy + f.xy; // 把三维格子映射到二维噪声坐标。
	vec2 n = textureLod(noisetex, uv * 0.015625 + 0.0078125, 0.0).zw; // 读噪声贴图后两通道。

	return mix(n.x, n.y, f.z); // 按高度在小数位置插值。
}

#if OMNI_VFOG_NOISE_TYPE == 0 // 仅高度衰减：只用高度决定密度。

// 雾密度：以两档衰减高度之间最浓，超出后按衰减距离指数下降。
float FogDensity(vec3 fogPos, vec3 wind){
	float maxHeight = max(OMNI_VFOG_HEIGHT, OMNI_VFOG_HEIGHT_2); // 两档高度里较高的。
	float minHeight = min(OMNI_VFOG_HEIGHT, OMNI_VFOG_HEIGHT_2); // 两档高度里较低的。

	float dh = max(fogPos.y - maxHeight, 0.0) + max(minHeight - fogPos.y, 0.0); // 到最浓高度区间外的距离。
	dh *= 2.0 / OMNI_VFOG_FALLOFF; // 按衰减距离归一化。
	float density = exp2(-dh * (1.0 - timeMidnight * 0.5)); // 指数下降，夜里衰减更慢雾更浓。

	return density * 0.1; // 缩到合理量级。
}

#else // 团雾：用三维噪声叠出雾团。

// 雾密度：先按高度算一个衰减包络，再乘多层噪声叠出的雾团。
float FogDensity(vec3 fogPos, vec3 wind){
	float dh = abs(fogPos.y - max(OMNI_VFOG_HEIGHT, OMNI_VFOG_HEIGHT_2)); // 到最高密度高度的距离。
	dh *= 1.0 / OMNI_VFOG_FALLOFF; // 按衰减距离归一化。
	float falloff = exp2(-dh * (1.0 - timeMidnight * 0.5)); // 高度衰减包络。
 
	float density = 0.0; // 累加的雾密度。
	fogPos = fogPos * 0.02 + wind; // 换到雾坐标并叠加风速。

	for (float stepAlpha = 0.5; stepAlpha >= 0.125; stepAlpha *= 0.5) { // 三层不同频率的噪声叠加。
		density += stepAlpha * Calculate3DNoise(fogPos); // 按权重累加这一层噪声。
		fogPos = (fogPos + wind) * 3.5; // 抬高频率并再叠一次风。
	}

	density *= falloff; // 乘高度衰减。

	density = density * density; // 平方拉开明暗。
	return density * density * 3.0; // 再平方并放大，得到清晰的雾团边界。
}

#endif

// 沿阳光方向估这一段雾对光的吸收：从雾采样点出发按逐步放大的步长前进，累加各处的原生密度。
// 输入是雾采样位置与风；就地推进 `fogPos`，返回沿光方向累计的密度（尚未乘选项、基础密度与时间因子）。
// 为什么步长逐步放大：靠近采样点的雾对光柱影响最大，远处用大步长近似即可，四步就能看出吸收差异。
float FogLightMarch(inout vec3 fogPos, vec3 wind){
	float lightingDensity = 0.0; // 沿光方向累计的密度。
	float lightingStepLength = VFOG_SUNLIGHT_STEPLENGTH; // 沿光方向起始步长。

	for (int i = 0; i < VFOG_SUNLIGHT_STEPS; i++, fogPos += worldShadowVector * lightingStepLength, lightingStepLength *= 1.5){ // 沿光方向步进，步长逐步放大。
		lightingDensity += FogDensity(fogPos, wind) * lightingStepLength; // 累加这一段的原生密度。
	}

	return lightingDensity; // 返回原始累计密度，供调用方乘吸收率与选项。
}

// 体积雾主体：沿视线一步步在雾里前进，同时沿光方向估遮挡，累加雾色与阳光散射。
// 输入是待修改颜色、起点、终点、世界方向、全局云影、时间因子；输出透射率，颜色就地叠加雾。
// 为什么步长用指数递增：近处雾细节重要、远处可以粗，指数步长把采样集中在前段。
void VolumetricFog(inout vec3 color, vec3 startPos, vec3 endPos, vec3 worldDir, float globalCloudShadow, float fogTimeFactor, out float transmittance){
	#if OMNI_VFOG_NOISE_TYPE == 0 // 仅高度衰减模式夜晚雾更浓，时间因子再按夜晚放大。
		fogTimeFactor *= timeMidnight * 2.0 + 1.0;
	#endif

	#ifdef OMNI_TAA // 打开时间抗锯齿时用逐帧抖动。
		float noise = BlueNoiseTemporal().y; // 用蓝噪声另一个通道避免与反射抖动相关。
	#else
		float noise = bayer64(gl_FragCoord.xy); // 固定拜尔抖动。
	#endif

	float VdotL = dot(worldDir, worldShadowVector); // 视线与阳光方向夹角，供相位与粉末效应使用。

	#ifdef VFOG_LQ // `composite2` 打开低质量宏时体积雾只用三步。
		const float steps = 3.0;
	#else
		const float steps = OMNI_VFOG_QUALITY; // 否则用选项里的采样质量。
	#endif
	const float rSteps = 1.0 / steps; // 步数倒数。

	vec3 start = startPos + gbufferModelViewInverse[3].xyz; // 起点补上相机位置换成世界坐标。
	vec3 end = endPos + gbufferModelViewInverse[3].xyz; // 终点同样换成世界坐标。

	vec3 rayVector = end - start; // 从起点到终点的矢量。
	float rayLength = length(rayVector) * rSteps * 0.23979; // 每步的基础长度，零点二三九七九是原程序的归一化常数。

	vec3 shadowStart = ShadowScreenPos_From_WorldPos(start); // 起点投到阴影图。
	vec3 shadowEnd = ShadowScreenPos_From_WorldPos(end); // 终点投到阴影图。

	vec3 shadowRayVector = shadowEnd - shadowStart; // 阴影图里的步进矢量。

	start += cameraPosition; // 起点换成绝对世界坐标，供云影采样。

	#ifdef DISTANT_HORIZONS
		float baseDensity = OMNI_VFOG_DENSITY_BASE * (timeMidnight * 0.25 + 0.25) / clamp(float(dhRenderDistance), 512.0, 2048.0); // 基础密度按远景渲染距离归一化。
	#else
		float baseDensity = OMNI_VFOG_DENSITY_BASE * (timeMidnight * 0.1 + 0.05) / max(far, 100.0); // 没有远景时按近景远裁剪面归一化。
	#endif
	#ifndef OMNI_INDOOR_FOG // 默认让体积雾随天空光等级衰减，暗处雾更淡。
		baseDensity *= eyeBrightnessSmoothCurved; // 乘天空光曲线平滑值。
	#endif

	#ifdef OMNI_VFOG_VOLUMETRIC_LIGHTING // 打开体积光照时用多级相位，否则用单一相位。
		float phases[4]; // 四级散射相位。
		MultiScatteringPhases(VdotL, phases); // 一次算好四级相位。
	#else
		float phases = MiePhaseFunction(0.5, VdotL) * 0.7 + 0.05; // 单级前向相位。
	#endif

	#if OMNI_VFOG_NOISE_TYPE > 0 // 团雾模式要按风移动。
		float windTimer = (frameTimeCounter * OMNI_CLOUD_SPEED + 10.0 * OMNI_FTC_OFFSET) * 0.0025; // 风速时间，与云速一致。
		vec3 wind = vec3(-1.0, -0.05, 0.6) * windTimer; // 固定的风方向。
	#else // 仅高度衰减模式不用风。
		vec3 wind = vec3(0.0); // 给一个零值，让密度与光照步进共用一个调用写法。
	#endif


	transmittance = 1.0; // 透射率从全透开始。
	float fogDensity = 0.0; // 环境雾累计量。
	float rayDensity = 0.0; // 阳光散射累计量。

	#ifdef MC_GL_VENDOR_NVIDIA // 只有部分显卡支持给半透明玻璃染色。
		#ifdef OMNI_VFOG_STAINED
			vec3 translucentColor = vec3(0.0); // 透过半透明方块的染色光。
		#endif
	#endif

	for (float i = 0.0; i < steps; i++){ // 沿视线逐步前进。
		float exponential = pow(11.0, (i + noise) * rSteps); // 指数步长因子。
		float stepLength = exponential * 0.1 - 0.1; // 这一步在视线上的归一化位置。
		float stepDensity = exponential * rayLength * 1.442695; // 这一步的光学厚度，一点四四二六九五由以二为底换算而来。

		vec3 fogPos = start + stepLength * rayVector; // 这一步的雾采样位置。
		vec3 shadowPos = shadowStart + stepLength * shadowRayVector; // 这一步的阴影图坐标。

		float density = FogDensity(fogPos, wind); // 算这一点的雾密度，仅高度衰减模式忽略风。
		density = (density * OMNI_VFOG_DENSITY + baseDensity) * fogTimeFactor; // 噪声密度乘选项再加基础密度，再乘时间因子。
		float absorption = exp2(-density * stepDensity); // 这一步吸收掉的光。

		#ifdef OMNI_VFOG_VOLUMETRIC_LIGHTING // 体积光照：沿阳光方向估吸收。
			float lightingDensity = FogLightMarch(fogPos, wind); // 沿光方向累计密度，并就地推进 `fogPos`。

			lightingDensity = (lightingDensity * OMNI_VFOG_SUNLIGHT_ABSORPTION * OMNI_VFOG_DENSITY + baseDensity) * fogTimeFactor; // 乘吸收率与选项再算总密度。
			float lightingAbsorption = exp2(-lightingDensity * stepDensity); // 光方向上的吸收。

			float stepRayDensity = 0.0; // 这一步的阳光散射量。
			float order = 1.0; // 多级相位的权重，从一倍开始逐级减半。
			for (int j = 0; j < 4; j++, order *= 0.5){ // 四级散射加权求和。
				stepRayDensity += exp(-lightingDensity * order) * phases[j] * order; // 按级数与权重累加。
			}
			stepRayDensity *= PowderEffect(absorption, lightingAbsorption, VdotL); // 乘粉末效应。
		#endif


		shadowPos.xy = DistortShadowScreenPos(shadowPos.xy); // 阴影图坐标补上边缘压缩。

		float shadow = 1.0; // 这一点受不受阳光，默认受光。

		#ifdef OMNI_VFOG_STAINED
			vec3 shadowColorSample = vec3(1.0); // 该点半透明染色，默认白色。
		#endif

		if (saturate(shadowPos.xy) == shadowPos.xy && shadowPos.z < 1.0){ // 坐标落在阴影图内才采样。
			#ifdef MC_GL_VENDOR_NVIDIA // 支持遮挡贴图的显卡用实心与半透明两张图。
				float solidDepth = textureLod(shadowtex1, shadowPos.xy, 0).x; // 读实心深度。
				shadow *= step(shadowPos.z, solidDepth); // 射线在遮挡物前面才受光。

				#ifdef OMNI_VFOG_STAINED
					float transparentDepth = textureLod(shadowtex0, shadowPos.xy, 0).x; // 读半透明深度。
					shadowColorSample = GammaToLinear(textureLod(shadowcolor0, shadowPos.xy, 0).rgb); // 读半透明颜色。
					float transparentShadow = step(transparentDepth, shadowPos.z) * shadow; // 半透明遮挡量。

					shadowColorSample *= transparentShadow; // 颜色按遮挡量缩放。
					shadow -= transparentShadow; // 从受光里扣掉半透明遮挡。
				#endif
			#else
				float solidDepth = textureLod(shadowtex0, shadowPos.xy, 0).x; // 只读一张遮挡图。
				shadow *= step(shadowPos.z, solidDepth); // 射线在遮挡物前面才受光。
			#endif
		}


		#ifdef OMNI_VOLUMETRIC_CLOUDS // 有体积云时云影也能压体积雾。
			#ifdef OMNI_CLOUD_SHADOW
				#ifdef OMNI_VFOG_CLOUD_SHADOW
					float cloudShadow = CloudShadowFromTex(fogPos - cameraPosition, worldShadowVector); // 读该点云影，世界坐标要减去相机位置。
				#endif
			#endif
		#endif

		
		float integral = transmittance - absorption * transmittance; // 这一段吸收掉的光量。
		#ifdef OMNI_VFOG_VOLUMETRIC_LIGHTING
			stepRayDensity *= integral; // 散射量按这一段吸收缩放。
		#else
			float stepRayDensity = integral * phases; // 单向散射直接用相位乘吸收。
		#endif

		#if defined OMNI_VOLUMETRIC_CLOUDS && defined OMNI_CLOUD_SHADOW && defined OMNI_VFOG_CLOUD_SHADOW // 有云影时雾色也按云影压暗。
			stepRayDensity *= mix(cloudShadow, 1.0, wetness * 0.1 + 0.03); // 散射按云影压暗。
			fogDensity += integral * mix(cloudShadow, 1.0, wetness * 0.3 + 0.7); // 环境雾按云影压暗。
		#else
			fogDensity += integral; // 没有云影时直接累加。
		#endif

		rayDensity += stepRayDensity * shadow; // 散射只在受光处累加。

		#ifdef MC_GL_VENDOR_NVIDIA
			#ifdef OMNI_VFOG_STAINED
				translucentColor += stepRayDensity * shadowColorSample; // 累加染色散射。
			#endif
		#endif
		
		
		transmittance *= absorption; // 透射率逐步衰减。
	}


	vec3 skylight = colorSkylight; // 雾的环境色以天光为主。
	vec3 skySunLight = colorShadowlight * 0.03; // 雾里的一点点直射光。
	skylight += skySunLight * (1.0 + (1.0 - globalCloudShadow) * (1.0 - wetness)); // 云影越浅这里补得越多。

	skylight = mix(skylight, skySunLight, wetness * 0.7); // 雨天偏向直射色，雾更灰。

	vec3 fogColor = skylight         * fogDensity; // 环境雾色。
	vec3 rayColor = colorShadowlight * rayDensity; // 阳光散射色。

	#ifdef MC_GL_VENDOR_NVIDIA
		#ifdef OMNI_VFOG_STAINED
			rayColor += colorShadowlight * translucentColor; // 叠上透过半透明方块的染色光。
		#endif
	#endif

	fogColor *= 0.32 * OMNI_VFOG_FOG_DENSITY      * OMNI_SKYLIGHT_INTENSITY; // 环境雾按强度选项与天光强度缩放。
	rayColor *= 0.7  * OMNI_VFOG_SUNLIGHT_DENSITY * OMNI_SUNLIGHT_INTENSITY; // 散射按强度选项与阳光强度缩放。
	#if !defined OMNI_VOLUMETRIC_CLOUDS || !defined OMNI_CLOUD_SHADOW || !defined OMNI_VFOG_CLOUD_SHADOW // 没有云影时在这里压散射。
		rayColor *= mix(globalCloudShadow, 1.0, wetness * 0.1); // 全局云影压散射。
	#endif

	#ifndef OMNI_INDOOR_FOG // 默认体积雾随天空光等级衰减。
		fogColor *= eyeBrightnessSmoothCurved; // 环境雾按天空光衰减。
		#ifdef OMNI_CAVE_MODE // 洞穴模式下散射也衰减，避免洞口过亮。
			rayColor *= eyeBrightnessSmoothCurved;
		#endif
		transmittance = mix(1.0, transmittance, eyeBrightnessSmoothCurved); // 透射率也按天空光拉回，暗处雾更淡。
	#endif

	color = transmittance * color; // 场景色先被雾吸收。
	color += fogColor + rayColor; // 再叠上雾色与散射。
}




// 简化的单次散射：沿阳光方向取几段估光学厚度，算出这段空气加到视线上的散射色。
// 输入是相机、视线方向、散射距离、受光距离与光源方向；返回叠加的散射颜色。
// 为什么用球面求交取段长：每段沿阳光走多远由大气层厚度决定，固定步长会在高处取样过密、低处过疏。
vec3 simpleScattering(vec3 camera, vec3 worldDir, float dist, float shadowDist, vec3 lightVector){
	float ds = RaySphereIntersection(camera, lightVector, atmosphereModel_top_radius).y * 0.25; // 沿阳光到大层顶的距离，取四分之一为每段长度。
	vec3 opticalLength = ds * lightVector; // 每段的光程矢量。
	camera += 0.5 * opticalLength; // 相机先前移到第一段中点。

	vec3 opticalDepth = vec3(0.0); // 累加的光学厚度，三通道分别是瑞利、米氏与吸收。
	for (int i = 0; i < 4; i++, camera += opticalLength){ // 四段累加。
		float altitude = length(camera) - atmosphereModel_bottom_radius; // 该段所在高度。
		opticalDepth += vec3(GetProfileDensityRayleighMie(atmosphereModel_densityProfile_rayleigh, altitude), // 瑞利密度。
							 GetProfileDensityRayleighMie(atmosphereModel_densityProfile_mie, altitude), // 米氏密度。
							 GetProfileDensityAbsorption (atmosphereModel_densityProfile_absorption_width, atmosphereModel_densityProfile_absorption, altitude)); // 臭氧密度。
	}
	opticalDepth = opticalDepth * ds + dist; // 乘段长并加上视线本身的距离。

	vec3 attenuation = exp2(-opticalDepth.x * atmosphereModel_rayleigh_scattering // 瑞利消光。
		 				    -opticalDepth.y * atmosphereModel_mie_scattering // 米氏消光。
		 			   	    -opticalDepth.z * atmosphereModel_absorption_extinction); // 臭氧吸收。

	float nu = dot(worldDir, lightVector); // 视线与阳光的夹角。
	vec3 scattering = RayleighPhaseFunction(nu) * atmosphereModel_rayleigh_scattering * (dist * 0.25 + shadowDist * 0.75) // 瑞利散射，四分之一取距离、四分之三取受光距离。
					+ MiePhaseFunction(0.6, nu) * atmosphereModel_mie_scattering * shadowDist; // 米氏散射只算受光的部分。

	return scattering * atmosphereModel_solar_irradiance * attenuation * LMS; // 乘太阳辐照度、透过率与色适应矩阵。
}

// 地面大气散射：给地表方向的视线补一层空气散射，阴影区按选项削弱。
// 输入是待修改颜色、距离、起点、终点、世界方向与是否天空；就地把散射加到颜色里。
// 为什么把起点抬高到最低高度：贴地时大气几何退化，抬高保证散射计算稳定。
void LandAtmosphericScattering(inout vec3 color, in float dist, vec3 startPos, vec3 endPos, vec3 worldDir, bool isSky){
	float strength = max(OMNI_LANDSCATTERING_STRENGTH - float(isSky), 0.0); // 天空像素不重复加散射，强度减一。
	#ifdef OMNI_VFOG // 有体积雾时按白天缩放，避免和体积雾双重叠加。
		strength *= timeNoon;
	#endif
	#ifndef OMNI_INDOOR_FOG // 默认随天空光等级衰减。
		strength *= eyeBrightnessSmoothCurved;
	#endif

	if(strength > 0.001 && isEyeInWater == 0){ // 强度太低或不在空气中就不算。

		#ifdef OMNI_ATMO_HORIZON // 打开地平线时按选项高度算相机。
			vec3 camera = vec3(0.0, max(cameraPosition.y, ATMO_MIN_ALTITUDE) * 0.001 + atmosphereModel_bottom_radius, 0.0); // 高度换成公里并加星球半径。
		#else
			vec3 camera = vec3(0.0, max(cameraPosition.y, 63.0) * 0.001 + atmosphereModel_bottom_radius, 0.0); // 默认按海平面高度。
		#endif

		float shadowDist = dist; // 受光的距离，默认等于总距离。

		#ifdef OMNI_LANDSCATTERING_SHADOW // 打开阴影遮蔽时沿视线段查阴影图，按被挡的比例缩短受光距离。
			float rSteps = 1.0 / OMNI_LANDSCATTERING_SHADOW_QUALITY; // 采样数倒数。

			vec3 shadowStart = ShadowScreenPos_From_WorldPos(startPos + gbufferModelViewInverse[3].xyz); // 起点投到阴影图。
			vec3 shadowEnd = ShadowScreenPos_From_WorldPos(endPos + gbufferModelViewInverse[3].xyz); // 终点投到阴影图。

			#ifdef OMNI_TAA // 打开时间抗锯齿时用逐帧抖动。
				float noise = BayerTemporal();
			#else
				float noise = bayer64(gl_FragCoord.xy);
			#endif

			vec3 shadowIncrement = (shadowEnd - shadowStart) * rSteps; // 阴影图里的步进。
			vec3 shadowRayPosition = shadowIncrement * noise + shadowStart; // 起点加抖动。

			float shadowLength = 0.0; // 被遮挡的段数。

			for (int i = 0; i < OMNI_LANDSCATTERING_SHADOW_QUALITY; i++, shadowRayPosition += shadowIncrement){ // 沿视线段采样。
				vec3 shadowPos = shadowRayPosition; // 当前采样坐标。
				shadowPos.xy = DistortShadowScreenPos(shadowPos.xy); // 补边缘压缩。

				if (saturate(shadowPos.xy) == shadowPos.xy && shadowPos.z < 1.0){ // 落在阴影图内。
					float solidDepth = textureLod(shadowtex0, shadowPos.xy, 0).x; // 读遮挡深度。
					shadowLength += step(solidDepth, shadowPos.z); // 遮挡物在射线前面才算被挡。
				}
			}

			shadowDist = max(shadowDist - shadowLength * length((endPos - startPos) * rSteps), 0.0); // 按被挡比例缩短受光距离。
		#endif

		dist *= OMNI_LANDSCATTERING_DISTANCE; // 总距离乘距离倍率。
		shadowDist *= OMNI_LANDSCATTERING_DISTANCE; // 受光距离同样乘倍率。

		color += simpleScattering(camera, worldDir, dist, shadowDist, worldSunVector) // 算出这段空气的散射。
			   * (1.0 - wetness) // 雨天空气更均匀，去掉方向性散射。
			   * strength; // 乘最终强度。
	}
}


// --- 原版雾：处理失明、黑暗与岩浆、细雪等特殊视效 ---
// 输入是待修改颜色与距离；就地把画面往对应颜色混合。
// 为什么这些单独处理：它们来自原版药水与介质状态，不属于自定义雾，改动可能影响玩法判断，所以按原版逻辑照搬。
void VanillaFog(inout vec3 color, float dist){
	#ifndef OMNI_DISABLE_BLINDNESS_DARKNESS // 调试开关，关闭后不看失明与黑暗。
		if (darknessFactor > 0.0) color = mix(color, vec3(0.0), smoothstep(5.0, mix(far, 15.0, darknessFactor), dist) * darknessFactor); // 黑暗效果：越远越黑。
		if (blindness > 0.0) color = mix(color, vec3(0.0), smoothstep(1.5, mix(far, 4.5, blindness), dist) * blindness); // 失明效果：更近就开始变黑。
	#endif

	if (isEyeInWater == 3) color = mix(color, vec3(0.03), smoothstep(0.0, 2.0, dist)); // 细雪里画面压暗。
 
	if (isEyeInWater == 2) color = mix(color, vec3(0.3721, 0.0775, 0.0024) * OMNI_TORCHLIGHT_BRIGHTNESS, smoothstep(0.0, 1.0, dist)); // 岩浆里染成橙红。
}

// 水面折射与原版雾共用本文件的水下体积雾函数，所以在这里引入水面效果；它同时提供水下雾开关与浓度选项。
// 放在函数定义之后：水面折射会调用上面的 `VolumetricFog` 与 `LandAtmosphericScattering`，此时两者已经定义。
#include "/effects/water/water.glsl"

// --- 水下焦散：水下体积雾需要一份范围很窄的焦散值来收窄光柱 ---
// 说明：原 `UnderwaterVolumetricFog.glsl` 里的 `CalculateWaterCaustics` 与 `effects/shadow/shadow.glsl` 里的同名函数内容不同，
// 同名会冲突，按移植合同九点五节的处理方式改名，函数体保持不变；两份都记入偏离记录。
float CalculateUnderwaterCaustics(vec3 worldPos){
	worldPos.xyz += cameraPosition; // 相机相对世界位置补上相机位置，换成绝对坐标。

	vec3 lookupCenter = worldPos; // 从当前位置向上找波面。
	lookupCenter.y += 1.0; // 抬高一米到水面上方。

	vec3 wavesNormal = GetWavesNormalFromTex(lookupCenter, worldShadowVector).xzy; // 读波法线并换到竖直轴朝上的坐标。
	vec3 refractVector = refract(vec3(0.0, 1.0, 0.0), wavesNormal.xyz, 1.0); // 竖直光线被波面折射后的方向。
	vec3 collisionPoint = lookupCenter - refractVector / refractVector.y; // 光线与水平面的交点。

	float dist = distance(collisionPoint, worldPos); // 交点到当前点的距离。

	return dist * 2.8 + 0.2; // 距离越近焦散越强，返回一个零到一附近的值。
}


// 水下体积雾：在水下沿视线步进阴影可见性，乘焦散与水吸收，得到汇聚的蓝色光柱。
// 输入是起点、终点、世界方向与全局云影；返回光柱颜色。
// 为什么限制四十米：光柱来自水面缝隙，远处既看不清又贵，截断到四十米内。
vec3 UnderwaterVolumetricFog(vec3 startPos, vec3 endPos, vec3 worldDir, float globalCloudShadow){
	const float range = 40.0; // 光柱的累积范围。

	float startDist = length(startPos); // 起点到相机的距离。
	if(startDist > range) return vec3(0.0); // 起点已经在范围外，不画光柱。

	endPos = mix(worldDir * range, endPos, step(length(endPos), range)); // 终点超过范围就截断到范围内。

	float rayDist = distance(startPos, endPos); // 这条射线在范围里的长度。
	vec3 rayDir = (endPos - startPos) / rayDist; // 射线方向。

	const float steps = OMNI_VFOG_QUALITY; // 采样次数来自体积雾质量。
	const float stepLength = range / steps; // 每段长度。

	float noise = BlueNoiseTemporal().y; // 每帧变化的抖动。

	vec3 result = vec3(0.0); // 累加的光柱颜色。

	for (float i = 0.0; i < steps; i++){ // 沿视线逐步前进。
		float rayLength = (i + noise) * stepLength; // 当前位置，起点加抖动量。
		vec3 rayPos = startPos + rayDir * rayLength; // 世界位置。

		if(startDist + rayLength > range || rayLength > rayDist) break; // 超出范围就停止。

		vec3 shadowProjPos = ShadowScreenPos_From_WorldPos_Distorted(rayPos + gbufferModelViewInverse[3].xyz); // 投到阴影图，含边缘压缩。
		#ifdef MC_GL_VENDOR_NVIDIA
			vec3 shadow = vec3(step(shadowProjPos.z + 1e-06, textureLod(shadowtex1, shadowProjPos.xy, 0).x)); // 受光则由实心遮挡图判定。
		#else
			vec3 shadow = vec3(step(shadowProjPos.z + 1e-06, textureLod(shadowtex0, shadowProjPos.xy, 0).x)); // 受光则由遮挡图判定。
		#endif

		rayLength += startDist; // 距离补上起点偏移。

		float caustics = CalculateUnderwaterCaustics(rayPos); // 该点焦散强度。
		shadow *= caustics * caustics * caustics; // 三次方让焦散更集中。
		shadow /= max(3.0, rayLength * 0.1); // 越远越弱。
		#ifdef OMNI_UNDERWATER_FOG // 有水下雾时按水的分波段吸收衰减光柱。
			shadow *= pow(vec3(0.1, 0.6, 1.0) * 0.99, vec3(rayLength * 0.04 * OMNI_WATERFOG_DENSITY)); // 红衰减最快，光柱因此偏蓝。
		#endif

		result += shadow; // 累加。
	}
	result *= range / steps; // 取平均。

	vec3 lightVector = refract(worldShadowVector, vec3(0.0, -1.0, 0.0), 1.0 / 1.2); // 阳光向下穿过水面时弯折。
	float LdotV = dot(lightVector,worldDir); // 光方向与视线的夹角。
	float phace = MiePhaseFunction(0.7, LdotV); // 前向相位，正对阳光时更亮。

	result *= colorShadowlight * (0.04 * phace * OMNI_SUNLIGHT_INTENSITY * OMNI_UNDERWATER_VFOG_DENSITY); // 乘直射光色、相位与强度。

	#ifdef OMNI_UNDERWATER_FOG // 有水下雾时把光柱染成水色。
		result *= vec3(0.2, 0.65, 1.0);
	#endif

	result *= globalCloudShadow; // 按全局云影压暗。

	return result; // 返回光柱颜色。
}
#endif // 文件守卫结束。
