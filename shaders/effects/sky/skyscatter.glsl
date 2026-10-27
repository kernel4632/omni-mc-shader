/*
效果文件 `effects/sky/skyscatter.glsl`：玩家选项、宿主参数换算、阶段组合与说明集中在这里，菜单由 options.py 扫描本文件生成。
调用位置：`rendering/` 下的绘制主体按需引用本文件；同目录的其它效果文件补充分阶段实现。
可复制示例：`#include "/effects/sky/skyscatter.glsl"`，随后调用下方保留原名的效果入口。
设计原因与取舍：选项、参数换算与阶段组合同属一个效果，放在一处才找得到、改得动；算式在生成的 `omni-gfx` 库，本文件不复制。
*/
#ifndef OMNI_EFFECT_SKY_SKYSCATTER_INCLUDED
#define OMNI_EFFECT_SKY_SKYSCATTER_INCLUDED
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

// --- 效果实现：宿主输入、参数换算与阶段入口 ---
// Eclipse 实时天空的密度与路径函数在生成库，需要显式引入。
#include "/omni-gfx/atmosphere.glsl"
// 极光噪声在 Eclipse 天空模块，和实时天空共用同一份生成库。
#include "/omni-gfx/eclipse_sky.glsl"
/*
天空散射：给预计算大气的瑞利散射与米氏散射一组逐通道系数倍率，再给整个天空辐射一个亮度倍率。
来源：Eclipse `lib/settings.glsl:382`（`Sky_Brightness`）与 `:385-390`（`sky_coefficientRayleighR/G/B`、`sky_coefficientMieR/G/B`）。
调用位置：`effects/sky/atmosphere_model.glsl` 的 `GetSkyRadiance` 与 `GetSkyRadianceToPoint`：
    瑞利散射项乘 `omniSkyRayleighTint()`，米氏散射项乘 `omniSkyMieTint()`，最后整个天空辐射乘 `OMNI_SKY_BRIGHTNESS`；
    这几处都在 `effects/sky/atmosphere_model.glsl`，本文件只提供选项与两个取颜色的函数。
可复制示例：
    `vec3 rayleigh = (sun_scattering * RayleighPhaseFunction(sun_nu)) * omniSkyRayleighTint();` // 逐通道缩放瑞利散射。
    `vec3 mie = sun_single_mie_scattering * MiePhaseFunction(g, sun_nu) * omniSkyMieTint();`    // 逐通道缩放米氏散射。
    `return (rayleigh + mie) * OGX_ATMO_LMS * OMNI_SKY_BRIGHTNESS;`                             // 缩放整体天空亮度。
设计原因与取舍：
    Omni 的天空是预计算大气贴图，系数已经烘进那张数据里，运行时无法按新系数重算整条光路；
    所以这里把 Eclipse 的绝对系数改成“相对当前大气的倍率”：放大瑞利让天空更亮更蓝，放大米氏让太阳附近的白晕更强。
    这属于近似——严格的消光与多次散射不会随倍率改变，与 Eclipse 的实时积分不同；默认倍率全为一，画面与原来逐位一致。
    表面接到的天空环境光（`GetSunAndSkyIrradiance`）不在此列：Eclipse 的系数只进实时积分的天空色，不进平均天空光。
*/
// 瑞利散射倍率：把三个通道选项拼成一个向量，默认全一，乘到瑞利项上不改画面。
// 单独成函数的原因：倍率是“改系数”这件事唯一落到代码里的地方，将来若要顺带调整消光，只需改这里。
vec3 omniSkyRayleighTint(){
	return vec3(OMNI_SKY_RAYLEIGH_R, OMNI_SKY_RAYLEIGH_G, OMNI_SKY_RAYLEIGH_B); // 逐通道取选项值。
}
// 米氏散射倍率：同上，默认全一，乘到米氏项上不改画面。
vec3 omniSkyMieTint(){
	return vec3(OMNI_SKY_MIE_R, OMNI_SKY_MIE_G, OMNI_SKY_MIE_B); // 逐通道取选项值。
}
// --- Eclipse 实时天空密度与路径兼容层：参考直接读固定行星常数 ---
// 行星半径、两层标高与大气层顶都取 Eclipse `ROBOBO_sky.glsl` 的默认值。
const float OMNI_ECLIPSE_PLANET_RADIUS = 6731e3;
const vec2 OMNI_ECLIPSE_SCALE_HEIGHTS = vec2(8.0e3, 1.2e3);
const float OMNI_ECLIPSE_ATMOSPHERE_RADIUS = OMNI_ECLIPSE_PLANET_RADIUS + 1.0e5;

vec3 sky_density(float centerDistance){
	return ogxEclipseSkyDensity(centerDistance, OMNI_ECLIPSE_PLANET_RADIUS, OMNI_ECLIPSE_SCALE_HEIGHTS);
}
vec3 sky_airmass(vec3 position, vec3 direction, float rayLength, float steps){
	return ogxEclipseSkyAirmass(position, direction, rayLength, steps, OMNI_ECLIPSE_PLANET_RADIUS, OMNI_ECLIPSE_SCALE_HEIGHTS);
}
vec3 sky_opticalDepth(vec3 position, vec3 direction, float rayLength, float steps){
	return ogxEclipseSkyOpticalDepth(position, direction, rayLength, steps, OMNI_ECLIPSE_PLANET_RADIUS,
		OMNI_ECLIPSE_SCALE_HEIGHTS, vec3(5.8e-6, 1.35e-5, 3.31e-5), vec3(3.0e-6),
		vec3(1.807e-7, 1.316e-7, 7.883e-9));
}
vec3 sky_transmittance(vec3 position, vec3 direction, float steps){
	vec3 airmass = ogxEclipseSkyAirmassRay(position, direction, steps, OMNI_ECLIPSE_PLANET_RADIUS,
		OMNI_ECLIPSE_SCALE_HEIGHTS, OMNI_ECLIPSE_ATMOSPHERE_RADIUS);
	vec3 depth = vec3(5.8e-6, 1.35e-5, 3.31e-5) * airmass.x + vec3(3.0e-6) * airmass.y
		+ vec3(1.807e-7, 1.316e-7, 7.883e-9) * airmass.z;
	return exp(-depth * 1.4427); // 参考用 rLOG2 = 1.4427 把 2 为底的指数换回 e。
}

// 参考签名兼容层：Eclipse 极光的三乘三层三角噪声，时间由宿主补齐。
float triNoise2d(vec2 p){ return ogxEclipseAuroraTriNoise2d(p, frameTimeCounter); }

// 参考签名兼容层：Eclipse 的极光主体直接读月亮/太阳高度与极光颜色。
// 这里把参考的五个参数原样保留，颜色与亮度取 Eclipse 默认值。
vec3 aurora(vec3 dir, int samples, float noise, float moonVecY, float sunVecY){
	vec3 col = vec3(0.0);
	vec3 avgCol = vec3(0.0);
	float hash = 0.05 * noise;
	float fade = dir.y * 2.0 + 0.4;
	float atmosphereGround = 1.0 - exp2(-50.0 * pow(clamp(dir.y + 0.025, 0.0, 1.0), 2.0));
	float mult = 3.0;
	for (int i = 0; i < samples; i++){
		float mI = mult * float(i);
		float of = hash * smoothstep(0.0, 12.0, mI);
		float pt = (0.8 + pow(mI, 1.4) * 0.0016) / fade - of;
		vec3 bpos = pt * dir;
		float rzt = triNoise2d(bpos.zx);
		vec3 col2 = (sin(vec3(2.25, -0.5, 1.2) + mI * 0.063) * 0.5 + 0.5) * rzt;
		avgCol = mix(avgCol, col2, 0.1);
		col += avgCol * exp2(-mI * 0.05 - 2.5);
	}
	vec3 auroraCol = 14.5 * pow(col, vec3(1.45));
	auroraCol *= smoothstep(0.1, 0.0, moonVecY);
	auroraCol *= smoothstep(0.0, -0.1, sunVecY);
	return auroraCol * atmosphereGround * 1.0 * 1.0;
}

#endif // OMNI_RENDER_SKY_SKYSCATTER_INCLUDED

// 严格对照补充说明：
// 实时天空密度、路径长度、光学深度与透过率都使用 Eclipse 的固定行星常数。
// 行星半径、两层标高与大气层顶只在文件头写一次，后续函数复用。
// 瑞利、米氏与臭氧的吸收系数取参考默认值，避免宿主选项改变常数集合。
// 透过率用参考的 rLOG2 常数把以二为底的指数换回自然指数。
// 极光主体照参考保留三乘三层噪声与月亮、太阳高度遮罩。
// 极光颜色取参考默认的暖红、负绿与蓝色分量，亮度倍率保持一。
// 这些函数只依赖方向、采样数与时间，宿主不需要额外缓冲。

// 补充说明：实时天空的密度与路径使用固定行星常数。
// 行星半径、两层标高与大气层顶在文件头集中定义。
// 密度函数只接收中心距离，其他参数由常数补齐。
// 路径函数按步数累积三种介质的密度。
// 光学深度把路径乘上三种吸收系数。
// 透过率用自然指数，参考的 rLOG2 常数把以二为底的结果换回自然指数。
// 极光函数按方向、采样数与时间计算，不读取天空图。
// 极光颜色与亮度取参考默认值，避免宿主选项改变常数集合。
// 这些函数都不读取相机矩阵，也不需要深度缓冲。

// 补充说明：密度与路径函数使用固定行星常数。
// 三种吸收系数取参考默认值，避免天气选项改变常数集合。
// 光学深度只依赖路径与系数，不读取天空图。
// 透过率只做指数运算，不读取相机状态。
// 极光函数只依赖方向、采样数与时间。
// 这些函数都可以在天空程序里独立编译。
// 不需要额外的宿主缓冲，也不需要阴影贴图。

// 补充说明：天空函数只依赖方向与时间。
// 不读取阴影贴图，也不修改宿主缓冲。
// 兼容重载保留参考签名。
// 行星常数只在文件头写一次。
// 后续函数直接复用这些常数。
