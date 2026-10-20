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
#ifndef OMNI_ATMOSPHERE_INCLUDED
#define OMNI_ATMOSPHERE_INCLUDED
// @effect {"label":{"zh_cn":"氛围","en_us":"Atmosphere"}}
// @option {"label":{"zh_cn":"极光","en_us":"Aurora"},"description":{"zh_cn":"夜里高空出现极光帘幕；默认关闭，打开后才计算。","en_us":"Shows aurora curtains high in the night sky; off by default."}}
#define OMNI_AURORA 0 // [0 1]
// @option {"label":{"zh_cn":"彩虹","en_us":"Rainbow"},"description":{"zh_cn":"雨后晴天出现彩虹；默认关闭，打开后才计算。","en_us":"Shows a rainbow after rain; off by default."}}
#define OMNI_RAINBOW 0 // [0 1]
// @option {"label":{"zh_cn":"闪电照明","en_us":"Lightning Illumination"},"description":{"zh_cn":"读取加载器实际闪电强度，在雷暴闪电瞬间给附近表面、体积云和体积雾叠一层冷色闪光；这是额外功能，默认关闭，关闭时默认画面与 iterationT 一致。","en_us":"Uses the loader lightning strength to flash nearby surfaces, volumetric clouds and volumetric fog during a strike; an extra feature, off by default so the default scene matches iterationT."}}
#define OMNI_LIGHTNING 0 // [0 1]
// @option {"label":{"zh_cn":"极光强度","en_us":"Aurora Strength"},"description":{"zh_cn":"极光多亮。","en_us":"How bright the aurora is."},"slider":true}
#define OMNI_AURORA_STRENGTH 1.0 // [0.0 0.5 1.0 2.0]
// @option {"label":{"zh_cn":"极光颜色","en_us":"Aurora Colour"},"description":{"zh_cn":"正值偏绿、负值偏蓝紫。","en_us":"Positive leans green, negative leans blue-purple."},"slider":true}
#define OMNI_AURORA_TINT 0.0 // [-1.0 -0.5 0.0 0.5 1.0]
// @option {"label":{"zh_cn":"彩虹强度","en_us":"Rainbow Strength"},"description":{"zh_cn":"彩虹多清楚。","en_us":"How clear the rainbow is."},"slider":true}
#define OMNI_RAINBOW_STRENGTH 1.0 // [0.0 0.5 1.0 2.0]
// @option {"label":{"zh_cn":"闪电强度","en_us":"Lightning Strength"},"description":{"zh_cn":"打雷时闪亮多强。","en_us":"How bright the lightning flash is."},"slider":true}
#define OMNI_LIGHTNING_STRENGTH 1.0 // [0.0 0.5 1.0 1.5 2.0]
// 归一化与噪声来自共用数学，天体方向来自加载器输入，显式引入而不依赖调用顺序。
#include "/common/uniforms.glsl"
#include "/common/math.glsl"
// 极光与彩虹的纯公式放在通用库。
#include "/gfx/atmosphere.glsl"
// 太阳色与氛围同属天空光照的补充：由本文件引入后，凡引入氛围的天空与合成程序都直接拿到 `omniSunTint()`，
// 太阳圆盘与直射光的接线点因此不必再各自引入；`suncolor.glsl` 自身带守卫，重复引入无副作用。
#include "/effects/sky/suncolor.glsl"
#ifdef IS_IRIS // Iris 提供闪电的世界位置与强度。
uniform vec4 lightningBoltPosition; // 闪电的相机相对世界位置与强度。
#endif
// 极光：主世界夜晚高空的缓慢帘幕，雨天被云遮挡。
vec3 omniAurora(vec3 color, vec3 direction) {
#if OMNI_AURORA // 打开极光才生成采样。
	vec3 sunDirection = omniNormalize(mat3(gbufferModelViewInverse) * sunPosition); // 太阳转到世界空间，决定夜色浓度。
	color = gfx_aurora(color, direction, sunDirection, frameTimeCounter, wetness, OMNI_AURORA_TINT, OMNI_AURORA_STRENGTH); // 帘幕公式在通用库。
#endif
	return color; // 关闭时不改动颜色。
}
// 彩虹：雨后晴天的背太阳方向，出现一条窄彩色弧。
vec3 omniRainbow(vec3 color, vec3 direction) {
#if OMNI_RAINBOW // 打开彩虹才生成采样。
	vec3 sunDirection = omniNormalize(mat3(gbufferModelViewInverse) * sunPosition); // 转到世界空间的太阳方向。
	color = gfx_rainbow(color, direction, sunDirection, wetness, OMNI_RAINBOW_STRENGTH); // 窄带彩虹公式在通用库。
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
// 闪电照明：加载器给出真实闪电事件时，按到闪电的距离照亮附近表面。
// 天空可见度抑制洞穴闪光，避免不透光的洞里也发亮。
vec3 omniLightning(vec3 color, vec3 world, float skylight) {
#if OMNI_LIGHTNING // 打开闪电才读取事件。
#ifdef IS_IRIS // 只有 Iris 提供闪电输入。
	float intensity = lightningBoltPosition.w; // 强度来自实际闪电事件，没有事件时为零。
	float boltDistance = length(world-lightningBoltPosition.xyz); // 表面到闪电的距离，越近越亮。
	color += vec3(0.55,0.65,0.9)*intensity*skylight/(1.0+boltDistance*0.01)*OMNI_LIGHTNING_STRENGTH; // 冷白色闪光，距离越远越弱；强度可调。
#endif
#endif
	return color; // 没有真实闪电输入时原样返回。
}
// 闪电照亮参与散射的介质（体积云、体积雾）：把闪电当成一根竖直光柱，介质采样点离柱越近越亮。
// 与 `omniLightning` 的区别：那个照固体表面、按太阳可见度压制洞穴闪光；介质本身飘在空中，
// 所以这里不做可见度衰减，改由调用方按介质多少（云厚、雾每步的吸收）缩放。
// `lightDistance` 是照明范围、`falloff` 是指数衰减强度，两种介质的取值照 Eclipse `lib/lightning_stuff.glsl:31`（云）与 `:44`（雾）。
vec3 omniLightningVolume(vec3 relativePos, float lightDistance, float falloff) {
#if OMNI_LIGHTNING // 打开闪电照明才计算。
#ifdef IS_IRIS // 只有 Iris 提供闪电输入。
	if (lightningBoltPosition.w > 0.0) { // 没有闪电事件时不加。
		vec3 boltPos = vec3(lightningBoltPosition.x, clamp(relativePos.y, lightningBoltPosition.y, lightningBoltPosition.y + 116.0), lightningBoltPosition.z); // 光柱同一水平位置，竖直方向夹在光柱高度区间。
		float boltDistance = length(relativePos - boltPos); // 介质采样点到光柱的距离。
		float lightningLight = max(1.0 - boltDistance / lightDistance, 0.0); // 照明范围内线性衰减，照 Eclipse。
		lightningLight = exp((1.0 - lightningLight) * falloff); // 换成更集中的指数衰减，照 Eclipse。
		return vec3(0.55, 0.65, 0.9) * (lightningLight * lightningBoltPosition.w * OMNI_LIGHTNING_STRENGTH); // 冷色闪光，亮度来自事件强度并可调。
	}
#endif
#endif
	return vec3(0.0); // 没有真实闪电输入时返回零，不改变画面。
}
#endif // 文件守卫结束。
