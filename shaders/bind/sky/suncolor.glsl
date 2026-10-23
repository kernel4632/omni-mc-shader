/*
太阳色与辐照的宿主接线：读取 Minecraft 输入、调用通用库并写出结果。
调用位置：原引用 `effects/sky/suncolor.glsl` 的程序改为引用本文件。
可复制示例：下方函数保留原有效果入口的签名，调用方式不变。
设计原因与取舍：选项留在效果层，算法在通用库，本文件只做宿主数据与算法之间的转换。
*/
#ifndef OMNI_BIND_SKY_SUNCOLOR_INCLUDED
#define OMNI_BIND_SKY_SUNCOLOR_INCLUDED
#include "/effects/sky/suncolor.glsl"
/*
太阳色与辐照：给太阳的直射光与太阳圆盘一个可调的色温、RGB 颜色与辐照度倍率。
来源：Eclipse `lib/settings.glsl:392-450`（`colortype`、`Sun_temp`、`sunColorR/G/B`、`sun_illuminance`）
  与 `lib/util.glsl:95-109`（`blackbody`）；本项目复用已有的等价黑体色函数 `common/math.glsl` 的 `Blackbody`。
调用位置：天空程序把太阳侧颜色算好后，乘上 `omniSunTint()`。两处最直接的接入点：
  `effects/sky/atmosphere_model.glsl` 的 `GetSunAndSkyIrradiance`：`vec3 sun_irradiance = atmosphereModel_solar_irradiance;` 改成乘 `omniSunTint()`；
  `effects/sky/sun_moon.glsl` 的 `RenderSunDisc`：`return vec3(1.1114, 0.9756, 0.9133) * disc;` 改成再乘 `omniSunTint()`。
  这两处由主助手统一接线；本文件只提供选项与 `omniSunTint()`。
可复制示例：
  `vec3 sunLightColor = atmosphereModel_solar_irradiance * omniSunTint();` // 太阳直射色。
  `vec3 sunDiscColor  = vec3(1.1114, 0.9756, 0.9133) * disc * omniSunTint();` // 太阳圆盘色。
设计原因与取舍：
  Eclipse 直接把黑体色温或 RGB 当作太阳色，再乘一个绝对辐照度 `sun_illuminance`（默认 128000）；
  Omni 的大气管线用物理光谱辐照度 `atmosphereModel_solar_irradiance`（约 1.8）作为太阳基色，量纲与 Eclipse 不同，
  所以这里把两个选项做成“相对当前太阳色的染色 + 相对当前辐照度的倍率”，`omniSunTint()` 在默认取值下返回 `vec3(1.0)`，不改变当前画面。
  色温模式以 6300K 为中性基准做比值，改变色温只会染色调而不会顺带改变整体亮度；想看到 Eclipse 那种偏暖的太阳，
  把色温调离 6300 即可。月亮侧颜色不在本文件，沿用 `sky.glsl` 已有的 `OMNI_MOON_TEMP` 与 `OMNI_MOON_ILLUMINANCE`。
*/
// 黑体色来自共用数学，显式引入而不依赖调用顺序。
#include "/common/math.glsl"
// 太阳色与辐照：返回一个“相对当前太阳色”的倍率向量，默认取值下为全一，乘到太阳侧颜色上不改画面。
vec3 omniSunTint(){
	vec3 tint = vec3(1.0); // 默认中性：保持现状，不染色。
	#if OMNI_SUN_COLOR_TYPE == 1 // 色温模式。
		tint = Blackbody(OMNI_SUN_TEMP) / Blackbody(6300.0); // 以 6300K 为中性基准的比值，只改色调、不额外改亮度。
	#elif OMNI_SUN_COLOR_TYPE == 2 // RGB 模式。
		tint = vec3(OMNI_SUN_COLOR_R, OMNI_SUN_COLOR_G, OMNI_SUN_COLOR_B); // 直接取三个颜色分量。
	#endif
	return tint * OMNI_SUN_ILLUMINANCE; // 再乘辐照度倍率，默认倍率为一。
}
#endif // OMNI_BIND_SKY_SUNCOLOR_INCLUDED
