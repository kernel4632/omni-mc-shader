/*
日月圆盘：预计算大气之外的太阳与月亮圆盘遮罩，供天空把日月光点叠加到天空上。
调用位置：由 `effects/sky/sky.glsl` 引入；`RenderSunDisc`、`RenderMoonDisc` 在 `effects/sky/skyrender.glsl` 的主天空里调用，
    `RenderMoonDiscReflection` 在反射天空盒里用更软的圆盘。
可复制示例：
    `vec3 sunDisc = RenderSunDisc(worldDir, worldSunVector);`
    `float moonDisc = RenderMoonDisc(worldDir, worldMoonVector);`
设计原因与取舍：圆盘不是几何，而是视线与日月方向夹角的平滑遮罩；反射天空盒分辨率低，用更大的角半径换取可见。
    真实月亮模式改用 Eclipse 的尺寸档位；月面法线贴图本项目没有，缺少时退回程序圆盘不额外调制。
    太阳圆盘最后乘 `omniSunTint()`，太阳色与辐照倍率由 `effects/sky/suncolor.glsl` 提供。
*/
#ifndef OMNI_SKY_SUN_MOON_INCLUDED
#define OMNI_SKY_SUN_MOON_INCLUDED
// 太阳圆盘：视线越接近太阳方向越亮，边缘由平滑曲线收口。
vec3 RenderSunDisc(vec3 worldDir, vec3 sunDir){
	float d = dot(worldDir, sunDir); // 视线与太阳方向的夹角余弦。
	float size = 5e-5; // 圆盘角半径，越小圆盘越细。
	float hardness = 4e4; // 边缘硬度，越大边缘越陡。
	float disc = curve(saturate((d - (1.0 - size)) * hardness)); // 从中心到边缘的平滑遮罩。
	disc *= disc; // 平方让边缘更收。
	return vec3(1.1114, 0.9756, 0.9133) * disc * omniSunTint(); // 太阳偏暖的白底再乘太阳色与辐照倍率，默认全一不改画面。
}
// 月亮圆盘：形状同太阳，但边缘更硬、亮度单独交给选项。
// 真实月亮模式改用 Eclipse 的尺寸档位：角半径由 `OMNI_MOON_SIZE_SETTING` 换算，来源 `composite1.fsh:1785-1786`。
float RenderMoonDisc(vec3 worldDir, vec3 moonDir){
	float d = dot(worldDir, moonDir); // 视线与月亮方向的夹角余弦。
	#ifdef OMNI_REALMOON
		float moonSize = 0.999 + (10.0 - OMNI_MOON_SIZE_SETTING) * 0.0001; // 档位越大圆盘越大。
		float disc = curve(saturate((d - moonSize) / (1.0 - moonSize))); // 从圆盘中心到边缘的遮罩。
		#ifdef OMNI_MOON_NORMALS
			// 起伏明暗需要 Eclipse 自带的月面法线贴图，本项目没有该贴图，退回程序圆盘不额外调制。
			disc *= 1.0; // 保留现有遮罩。
		#endif
		return disc * disc; // 平方收口后返回零到一的亮度。
	#else
		float size = 5e-5; // 圆盘角半径。
		float hardness = 1e5; // 边缘硬度，比太阳更硬。
		float disc = curve(saturate((d - (1.0 - size)) * hardness)); // 月亮遮罩。
		return disc * disc; // 平方收口后返回零到一的亮度。
	#endif
}
// 反射里的月亮圆盘：反射天空盒分辨率低，用更大的角半径换取可见。
float RenderMoonDiscReflection(vec3 worldDir, vec3 moonDir){
	float d = dot(worldDir, moonDir); // 夹角余弦。
	float size = 0.0025; // 反射用更大的角半径。
	float hardness = 300.0; // 边缘更软。
	float disc = curve(saturate((d - (1.0 - size)) * hardness)); // 反射月亮遮罩。
	return disc * disc; // 返回零到一亮度。
}
#endif // 文件守卫结束。
