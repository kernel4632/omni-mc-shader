/*
效果文件 `effects/shared/lightning.glsl`：真实闪电照明的开关、强度，以及表面与介质两种照亮函数。
调用位置：天空程序给天空像素叠氛围时、合成主体给固体表面补光时、体积云与体积雾给介质补光时。
可复制示例：
    `color = omniLightning(color, worldPos, skylight);`
    `color += omniLightningVolume(relPos, 400.0, -10.0);`
设计原因与取舍：闪电同时照亮表面、云和雾，光源属于全场共享输入，选项只定义一次；
    没有真实闪电事件时函数原样返回，默认关闭时连采样都不生成，默认画面与 iterationT 一致。
    固体表面按太阳可见度压制洞穴闪光，介质不做可见度衰减而由调用方按介质多少缩放，两者的差别写在函数里。
    读取加载器闪电位置需要 Iris；其它加载器没有该输入时整段不编译，效果自动回退为无闪电。
*/
#ifndef OMNI_SHARED_LIGHTNING_INCLUDED
#define OMNI_SHARED_LIGHTNING_INCLUDED
// @effect {"label":{"zh_cn":"闪电照明","en_us":"Lightning illumination"}}
// @option {"label":{"zh_cn":"闪电照明","en_us":"Lightning Illumination"},"description":{"zh_cn":"读取加载器实际闪电强度，在雷暴闪电瞬间给附近表面、体积云和体积雾叠一层冷色闪光；这是额外功能，默认关闭，关闭时默认画面与 iterationT 一致。","en_us":"Uses the loader lightning strength to flash nearby surfaces, volumetric clouds and volumetric fog during a strike; an extra feature, off by default so the default scene matches iterationT."}}
#define OMNI_LIGHTNING 0 // [0 1]
// @option {"label":{"zh_cn":"闪电强度","en_us":"Lightning Strength"},"description":{"zh_cn":"打雷时闪亮多强。","en_us":"How bright the lightning flash is."},"slider":true}
#define OMNI_LIGHTNING_STRENGTH 1.0 // [0.0 0.5 1.0 1.5 2.0]
#ifdef IS_IRIS // Iris 提供闪电的世界位置与强度。
uniform vec4 lightningBoltPosition; // 闪电的相机相对世界位置与强度。
#endif
// 闪电照亮固体表面：按到闪电的距离补冷色光，并用天光可见度抑制洞穴里的错误闪光。
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
#endif // OMNI_SHARED_LIGHTNING_INCLUDED
