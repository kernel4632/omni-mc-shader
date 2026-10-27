/*
效果文件 `effects/sky/atmosphere.glsl`：玩家选项、宿主参数换算、阶段组合与说明集中在这里，菜单由 options.py 扫描本文件生成。
调用位置：`rendering/` 下的绘制主体按需引用本文件；同目录的其它效果文件补充分阶段实现。
可复制示例：`#include "/effects/sky/atmosphere.glsl"`，随后调用下方保留原名的效果入口。
设计原因与取舍：选项、参数换算与阶段组合同属一个效果，放在一处才找得到、改得动；算式在生成的 `omni-gfx` 库，本文件不复制。
*/
#ifndef OMNI_EFFECT_SKY_ATMOSPHERE_INCLUDED
#define OMNI_EFFECT_SKY_ATMOSPHERE_INCLUDED
// @effect {"label":{"zh_cn":"氛围","en_us":"Atmosphere"}}
// @option {"label":{"zh_cn":"极光","en_us":"Aurora"},"description":{"zh_cn":"夜里高空出现极光帘幕；默认关闭，打开后才计算。","en_us":"Shows aurora curtains high in the night sky; off by default."}}
#define OMNI_AURORA 0 // [0 1]
// @option {"label":{"zh_cn":"彩虹","en_us":"Rainbow"},"description":{"zh_cn":"雨后晴天出现彩虹；默认关闭，打开后才计算。","en_us":"Shows a rainbow after rain; off by default."}}
#define OMNI_RAINBOW 0 // [0 1]
// @option {"label":{"zh_cn":"极光强度","en_us":"Aurora Strength"},"description":{"zh_cn":"极光多亮。","en_us":"How bright the aurora is."},"slider":true}
#define OMNI_AURORA_STRENGTH 1.0 // [0.0 0.5 1.0 2.0]
// @option {"label":{"zh_cn":"极光颜色","en_us":"Aurora Colour"},"description":{"zh_cn":"正值偏绿、负值偏蓝紫。","en_us":"Positive leans green, negative leans blue-purple."},"slider":true}
#define OMNI_AURORA_TINT 0.0 // [-1.0 -0.5 0.0 0.5 1.0]
// @option {"label":{"zh_cn":"彩虹强度","en_us":"Rainbow Strength"},"description":{"zh_cn":"彩虹多清楚。","en_us":"How clear the rainbow is."},"slider":true}
#define OMNI_RAINBOW_STRENGTH 1.0 // [0.0 0.5 1.0 2.0]

// --- 效果实现：宿主输入、参数换算与阶段入口 ---
/*
氛围：在天空颜色上叠加极光和彩虹，并提供全场闪电照明；这三项是 Omni 额外功能，iterationT 没有对应实现，默认全部关闭。
调用位置：延迟三号主体算完 `GetSkyRadiance` 与云之后，对天空像素调用 `omniAtmosphere(skyColor, worldDir)`；
    合成主体对有真实深度与天光的表面调用 `omniLightning(color, worldPos, skylight)`；
    体积云在 `effects/cloud/cloud.glsl` 的 `CloudLighting` 里调用 `omniLightningVolume(...)`；
    体积雾在 `effects/fog/volumetric.glsl` 的 `VolumetricFog` 里调用 `omniLightningVolume(...)`。
可复制示例：
    `color = omniAtmosphere(color, worldDir);`        在天空上叠加氛围，夜间与雨后的效果各自带开关。
    `color = omniLightning(color, worldPos, skylight);` 再按真实闪电事件照亮附近表面。
    `color += omniLightningVolume(relPos, 400.0, -10.0);` 按真实闪电事件照亮一段体积云或体积雾。
设计原因与取舍：
    极光与彩虹各自独立成一个函数、各自带开关，默认关闭，关掉后连采样都不生成，默认画面与 iterationT 一致；
    大气散射已由 `effects/sky/atmosphere_model.glsl` 的预计算模型统一出图，这里不再重复叠一份；
    闪电只在加载器给出真实事件、并且玩家主动打开时才叠加；iterationT 不使用 `lightningBoltPosition`，所以默认关闭以免雷暴时多出一层闪光；
    闪电对表面用 `omniLightning`（按太阳可见度压制洞穴闪光），对参与散射的体积云与体积雾用 `omniLightningVolume`
    （闪电是一根竖直光柱，介质采样点离柱越近越亮），两种介质的范围与衰减常数照 Eclipse 的 `Iris_Lightningflash_VLcloud`/`_VLfog`；
    雨天判据用新管线的 `wetness`（平滑后的降雨），与 iterationT 保持一致。
*/
// 归一化与噪声来自共用数学，天体方向由绑定层转成世界空间，显式引入而不依赖调用顺序。
#include "/bind/time.glsl"
#include "/bind/weather.glsl"
#include "/bind/world.glsl"
#include "/common/math.glsl"
// 极光与彩虹的纯公式放在通用库。
#include "/omni-gfx/atmosphere/atmosphere.glsl"
// 共享大气同时带来太阳色、散射倍率与查表接口；闪电照明单独成共享文件，三个效果共用同一事件。
#include "/effects/shared/atmosphere.glsl"
#include "/effects/shared/lightning.glsl"
// 极光：主世界夜晚高空的缓慢帘幕，雨天被云遮挡。
vec3 omniAurora(vec3 color, vec3 direction) {
#if OMNI_AURORA // 打开极光才生成采样。
	vec3 sunDirection = bind_world().sunDirection; // 太阳方向由绑定层转到世界空间。
	color = ogxAurora(color, direction, sunDirection, bind_time().seconds, bind_weather().wetness, OMNI_AURORA_TINT, OMNI_AURORA_STRENGTH); // 帘幕公式在通用库。
#endif
	return color; // 关闭时不改动颜色。
}
// 彩虹：雨后晴天的背太阳方向，出现一条窄彩色弧。
vec3 omniRainbow(vec3 color, vec3 direction) {
#if OMNI_RAINBOW // 打开彩虹才生成采样。
	vec3 sunDirection = bind_world().sunDirection; // 世界空间的太阳方向。
	color = ogxRainbow(color, direction, sunDirection, bind_weather().wetness, OMNI_RAINBOW_STRENGTH); // 窄带彩虹公式在通用库。
#endif
	return color; // 关闭时不改动颜色。
}
// 天空氛围：主世界按选项叠加极光和彩虹，关闭的效果不生成计算。
// 为什么下界与末地不加：它们的天空已由各自的天空色接管，不需要这两层氛围。
vec3 omniAtmosphere(vec3 color, vec3 direction) {
#if !defined OMNI_NETHER && !defined OMNI_END // 只在主世界叠加。
	color = omniAurora(color,direction); // 叠加夜晚极光帘幕。
	color = omniRainbow(color,direction); // 叠加雨后彩虹。
#endif
	return color; // 关闭的效果不产生任何采样。
}
// 闪电照明函数在共享文件里，本文件只保留天空氛围的极光与彩虹。
#endif // OMNI_EFFECT_SKY_ATMOSPHERE_INCLUDED
