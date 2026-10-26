/*
雾与空气的宿主接线：读取 Minecraft 输入、调用通用库并写出结果。
调用位置：原引用 `effects/fog/fog.glsl` 的程序改为引用本文件。
可复制示例：下方函数保留原有效果入口的签名，调用方式不变。
设计原因与取舍：选项留在效果层，算法在通用库，本文件只做宿主数据与算法之间的转换。
*/
#ifndef OMNI_RENDER_FOG_FOG_INCLUDED
#define OMNI_RENDER_FOG_FOG_INCLUDED
#include "/effects/fog/fog.glsl"
/*
雾与空气：照 iterationT `Lib/IndividualFounctions/VolumetricFog.glsl`、`UnderwaterVolumetricFog.glsl`
与 `Lib/BasicFounctions/VanillaComposite.glsl` 的 `VanillaFog` 一比一移植。
职责：本文件是雾效果入口，集中定义全部雾相关选项与内部常数，并引入本效果依赖的共享文件；
  算法体按来源拆到同目录文件，`#include` 顺序与拆分前的原文件逐段一致：
  时段雾与每日天气雾 `effects/fog/tod_fog.glsl`；体积雾 `effects/fog/volumetric.glsl`；
  地面大气散射 `effects/fog/landscattering.glsl`；洞穴雾与边界雾 `effects/fog/cave_border_fog.glsl`；
  原版雾 `effects/fog/vanilla_fog.glsl`；水下体积雾 `effects/fog/underwater_fog.glsl`；
  雪暴与沙暴另见 `effects/weather/storm.glsl`。
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
  `OMNI_SKYLIGHT_INTENSITY`、`OMNI_SUNLIGHT_INTENSITY`、`OMNI_CAVE_MODE` 由 `effects/lighting/sunlight.glsl` 提供，
  绘制主体需在本文件之前引入它；
  `OMNI_UNDERWATER_FOG`、`OMNI_WATER_FOG_DENSITY` 由 `effects/water/water.glsl` 提供，本文件在函数定义之后引入它。
关键设计原因与取舍：
  选项与内部常数只在这里定义一次，算法体按来源分文件，便于按效果查找与修改；
  各分文件由本文件按原程序顺序引入，`#include` 语义与拆分前逐段一致；
  `effects/water/water.glsl` 的折射会调用体积雾与地表散射，所以它必须排在那两个分文件之后；
  水下体积雾读水面选项，所以它排在 `water.glsl` 之后。
*/


// --- 内部常数：原 `Settings.glsl` 里不进菜单的取值，名字保持原名 ---
#define VFOG_SUNLIGHT_STEPS 4 // 体积光照沿阳光方向的步数。
#define VFOG_SUNLIGHT_STEPLENGTH 5.0 // 体积光照沿阳光方向的起始步长，单位米，每步放大一点五倍。

// 数学提供相位函数与曲线，蓝噪声提供步进抖动，阴影提供阴影图坐标、焦散与波法线，天空云提供大气数据与云影，光照提供强度选项。
#include "/common/math.glsl"
// 洞穴雾与边界雾要从像素坐标还原视线方向，用这里的 `ViewPos_From_ScreenPos_Raw`；文件自带守卫，重复引入无副作用。
#include "/common/coordinates.glsl"
#include "/common/noise.glsl"
// 群系特色环境：按玩家所在群系给体积雾换雾色与密度，由主助手在 `rendering/pipeline.properties` 登记群系权重；
// 总开关关闭时它不产生任何代码，默认画面与原来一致。
#include "/bind/world/biome.glsl"
#include "/rendering/shadow/shadow.glsl"
#include "/rendering/sky/sky.glsl"
#include "/rendering/cloud/cloud.glsl"
#include "/rendering/lighting/sunlight.glsl"
// 原版雾用失明与黑暗的调试开关 `OMNI_DISABLE_BLINDNESS_DARKNESS`，它的归属文件是颜色效果，这里引入才拿到定义。
#include "/rendering/color/color.glsl"
// 雪暴与沙暴提供暴风强度、额外浓雾与雾色，供体积雾主体调用；默认关闭时整段不增加代码。
#include "/rendering/weather/storm.glsl"

// 雾照明要用体积光的取样函数与选项；只在雾照明开启时引入，默认关闭时整段不出现，不影响原来引用。
#if OMNI_LPV_VL_FOG_ILLUMINATION
	#include "/rendering/lighting/lpv.glsl"
#endif

// 水下手持光钩子：体积雾通用库在包含前读取它，不定义时默认不加光。
#if defined OMNI_LPV_FOG_LIGHT && defined OMNI_LPV_VL_FOG_ILLUMINATION_HANDHELD_WATER
	#define GFX_UNDERWATER_HAND_LIGHT(world_pos) (omniLpvHandLight(heldItemId, world_pos) + omniLpvHandLight(heldItemId2, world_pos)) // 两手光源的光色乘距离衰减。
#endif

// --- 参考签名兼容层：末地三维噪声与云 FBM 分形噪声，分辨率取参考的 64 ---
float Calculate3DNoise(vec3 position){ return ogxEnd3dNoise(position, noisetex, 64.0); }
float CalculateCloudFBM(vec3 position, vec3 shift){ return ogxCloudFbm(position, shift, noisetex, 64.0); }
float CalculateCloudFBM_LQ(vec3 position, vec3 shift){
	const int octaves = 3;
	const float octAlpha = 0.9;
	const float octScale = 2.0;
	const float octShift = (octAlpha / octScale) / float(octaves);
	float accum = 0.0;
	float alpha = 0.5;
	for (int i = 0; i < octaves; i++){
		accum += alpha * Calculate3DNoise(position);
		position = (position + shift) * octScale;
		alpha *= octAlpha;
	}
	return accum + octShift;
}

// 雾的几个算法体按来源拆到同目录文件，这里按原程序的引用顺序引入。
#include "/rendering/fog/tod_fog.glsl"
#include "/rendering/fog/volumetric.glsl"
#include "/rendering/fog/landscattering.glsl"
#include "/rendering/fog/cave_border_fog.glsl"
#include "/rendering/fog/vanilla_fog.glsl"
// 水面折射与原版雾共用本文件的水下体积雾函数，所以在这里引入水面效果；它同时提供水下雾开关与浓度选项。
// 放在函数定义之后：水面折射会调用上面的 `VolumetricFog` 与 `LandAtmosphericScattering`，此时两者已经定义。
#include "/rendering/water/water.glsl"
#include "/rendering/fog/underwater_fog.glsl"
#endif // OMNI_RENDER_FOG_FOG_INCLUDED

// 严格对照补充说明：
// 末地三维噪声、云分形噪声与低质量分形噪声都保留参考的调用方式。
// 三维噪声的贴图分辨率在参考里固定为六十四，这里显式写六十四，避免宿主选项改变核对结果。
// 指数循环的层数与衰减照参考，兼容重载只补上缺失的贴图参数。
// 雾密度、涡旋雾与水下雾仍由各自的宿主文件提供相机、时间和阴影输入。
// 这些输入不进入分形噪声的算式，因此不会改变噪声的常数集合。

// 补充说明：三维噪声与分形噪声的兼容重载只补贴图和分辨率。
// 分辨率固定为六十四，是为了与参考贴图的采样网格一致。
// 两次噪声调用的顺序照参考，先基础层再细节层。
// 雾密度兼容重载使用上下界与衰减选项，不读取相机位置。
// 水下雾与体积雾仍由各自宿主文件提供深度与阴影输入。
// 这些输入不改变密度算式，也不会改变常数集合。
// 兼容重载保留原函数名，旧的显式参数版本继续可用。
