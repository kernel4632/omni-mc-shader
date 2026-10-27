/*
效果文件 `effects/shared/skyscatter.glsl`：保存天空散射的逐通道倍率与整体亮度选项，并提供倍率函数。
调用位置：`effects/shared/atmosphere.glsl` 在组合天空辐射时调用 `omniSkyRayleighTint` 与 `omniSkyMieTint`；
    天空页的效果文件只需引入共享大气，就能同时拿到这些倍率。
可复制示例：`vec3 rayleigh = sunScattering * omniSkyRayleighTint();`。
设计原因与取舍：预计算大气贴图把原始散射系数已经烘进数据，运行时只能用相对倍率近似调整；
    倍率属于“天空看起来多蓝、多亮”的共享输入，落到云、雾、光照与反射都会用到，因此与大气模型放在同一共享层。
    Eclipse 的实时天空密度、路径与极光兼容函数仍留在天空页，因为它们只服务天空自己的对照入口。
*/
#ifndef OMNI_SHARED_SKYSCATTER_INCLUDED
#define OMNI_SHARED_SKYSCATTER_INCLUDED
// @effect {"label":{"zh_cn":"天空散射","en_us":"Sky Scattering"}}
// @option {"label":{"zh_cn":"天空亮度","en_us":"Sky Brightness"},"description":{"zh_cn":"整个天空辐射的亮度倍率，默认一倍与现在一致；Eclipse 的天空亮度选项。","en_us":"Brightness multiplier for the whole sky radiance; default 1 matches the current look; Eclipse's Sky Brightness."},"slider":true}
#define OMNI_SKY_BRIGHTNESS 1.0 // [0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.75 0.8 0.85 0.9 0.95 1.0 1.5 2.0 3.0 4.0 5.0 6.0 10.0]
// @option {"label":{"zh_cn":"天空蓝色红","en_us":"Rayleigh R"},"description":{"zh_cn":"瑞利散射红通道相对当前大气的倍率，越大天空越偏红；默认一倍与现在一致。","en_us":"Red-channel multiplier for Rayleigh scattering relative to the current atmosphere; default 1 matches the current look."},"slider":true}
#define OMNI_SKY_RAYLEIGH_R 1.0 // [0.0 0.25 0.5 0.75 1.0 1.25 1.5 1.75 2.0 2.5 3.0 4.0 5.0]
// @option {"label":{"zh_cn":"天空蓝色绿","en_us":"Rayleigh G"},"description":{"zh_cn":"瑞利散射绿通道相对当前大气的倍率，越大天空越偏绿；默认一倍与现在一致。","en_us":"Green-channel multiplier for Rayleigh scattering relative to the current atmosphere; default 1 matches the current look."},"slider":true}
#define OMNI_SKY_RAYLEIGH_G 1.0 // [0.0 0.25 0.5 0.75 1.0 1.25 1.5 1.75 2.0 2.5 3.0 4.0 5.0]
// @option {"label":{"zh_cn":"天空蓝色蓝","en_us":"Rayleigh B"},"description":{"zh_cn":"瑞利散射蓝通道相对当前大气的倍率，越大天空越蓝；默认一倍与现在一致。","en_us":"Blue-channel multiplier for Rayleigh scattering relative to the current atmosphere; default 1 matches the current look."},"slider":true}
#define OMNI_SKY_RAYLEIGH_B 1.0 // [0.0 0.25 0.5 0.75 1.0 1.25 1.5 1.75 2.0 2.5 3.0 4.0 5.0]
// @option {"label":{"zh_cn":"太阳白光红","en_us":"Mie R"},"description":{"zh_cn":"米氏散射红通道相对当前大气的倍率，越大太阳红晕越强；默认一倍与现在一致。","en_us":"Red-channel multiplier for Mie scattering relative to the current atmosphere; default 1 matches the current look."},"slider":true}
#define OMNI_SKY_MIE_R 1.0 // [0.0 0.25 0.5 0.75 1.0 1.25 1.5 1.75 2.0 2.5 3.0 4.0 5.0]
// @option {"label":{"zh_cn":"太阳白光绿","en_us":"Mie G"},"description":{"zh_cn":"米氏散射绿通道相对当前大气的倍率，越大太阳绿晕越强；默认一倍与现在一致。","en_us":"Green-channel multiplier for Mie scattering relative to the current atmosphere; default 1 matches the current look."},"slider":true}
#define OMNI_SKY_MIE_G 1.0 // [0.0 0.25 0.5 0.75 1.0 1.25 1.5 1.75 2.0 2.5 3.0 4.0 5.0]
// @option {"label":{"zh_cn":"太阳白光蓝","en_us":"Mie B"},"description":{"zh_cn":"米氏散射蓝通道相对当前大气的倍率，越大太阳蓝晕越强；默认一倍与现在一致。","en_us":"Blue-channel multiplier for Mie scattering relative to the current atmosphere; default 1 matches the current look."},"slider":true}
#define OMNI_SKY_MIE_B 1.0 // [0.0 0.25 0.5 0.75 1.0 1.25 1.5 1.75 2.0 2.5 3.0 4.0 5.0]
// 瑞利散射倍率：把三个通道选项拼成一个向量，默认全一，乘到瑞利项上不改画面。
vec3 omniSkyRayleighTint(){
	return vec3(OMNI_SKY_RAYLEIGH_R, OMNI_SKY_RAYLEIGH_G, OMNI_SKY_RAYLEIGH_B); // 逐通道取选项值。
}
// 米氏散射倍率：同上，默认全一，乘到米氏项上不改画面。
vec3 omniSkyMieTint(){
	return vec3(OMNI_SKY_MIE_R, OMNI_SKY_MIE_G, OMNI_SKY_MIE_B); // 逐通道取选项值。
}
#endif // OMNI_SHARED_SKYSCATTER_INCLUDED
