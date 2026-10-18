/*
天空散射：给预计算大气的瑞利散射与米氏散射一组逐通道系数倍率，再给整个天空辐射一个亮度倍率。
来源：Eclipse `lib/settings.glsl:382`（`Sky_Brightness`）与 `:385-390`（`sky_coefficientRayleighR/G/B`、`sky_coefficientMieR/G/B`）。
调用位置：`effects/sky/atmosphere_model.glsl` 的 `GetSkyRadiance` 与 `GetSkyRadianceToPoint`：
    瑞利散射项乘 `omniSkyRayleighTint()`，米氏散射项乘 `omniSkyMieTint()`，最后整个天空辐射乘 `OMNI_SKY_BRIGHTNESS`；
    这几处都在 `effects/sky/atmosphere_model.glsl`，本文件只提供选项与两个取颜色的函数。
可复制示例：
    `vec3 rayleigh = (sun_scattering * RayleighPhaseFunction(sun_nu)) * omniSkyRayleighTint();` // 逐通道缩放瑞利散射。
    `vec3 mie = sun_single_mie_scattering * MiePhaseFunction(g, sun_nu) * omniSkyMieTint();`    // 逐通道缩放米氏散射。
    `return (rayleigh + mie) * LMS * OMNI_SKY_BRIGHTNESS;`                                       // 缩放整体天空亮度。
设计原因与取舍：
    Omni 的天空是预计算大气贴图，系数已经烘进那张数据里，运行时无法按新系数重算整条光路；
    所以这里把 Eclipse 的绝对系数改成“相对当前大气的倍率”：放大瑞利让天空更亮更蓝，放大米氏让太阳附近的白晕更强。
    这属于近似——严格的消光与多次散射不会随倍率改变，与 Eclipse 的实时积分不同；默认倍率全为一，画面与原来逐位一致。
    表面接到的天空环境光（`GetSunAndSkyIrradiance`）不在此列：Eclipse 的系数只进实时积分的天空色，不进平均天空光。
*/
#ifndef OMNI_SKYSCATTER_INCLUDED // 只引入一次，避免选项与函数重复定义。
#define OMNI_SKYSCATTER_INCLUDED // 置上标记。
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
// 单独成函数的原因：倍率是“改系数”这件事唯一落到代码里的地方，将来若要顺带调整消光，只需改这里。
vec3 omniSkyRayleighTint(){
	return vec3(OMNI_SKY_RAYLEIGH_R, OMNI_SKY_RAYLEIGH_G, OMNI_SKY_RAYLEIGH_B); // 逐通道取选项值。
}
// 米氏散射倍率：同上，默认全一，乘到米氏项上不改画面。
vec3 omniSkyMieTint(){
	return vec3(OMNI_SKY_MIE_R, OMNI_SKY_MIE_G, OMNI_SKY_MIE_B); // 逐通道取选项值。
}
#endif // 文件守卫结束。
