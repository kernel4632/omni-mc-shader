/*
效果文件 `effects/sky/sun_moon.glsl`：玩家选项、宿主参数换算、阶段组合与说明集中在这里，菜单由 options.py 扫描本文件生成。
调用位置：`rendering/` 下的绘制主体按需引用本文件；同目录的其它效果文件补充分阶段实现。
可复制示例：`#include "/effects/sky/sun_moon.glsl"`，随后调用下方保留原名的效果入口。
设计原因与取舍：选项、参数换算与阶段组合同属一个效果，放在一处才找得到、改得动；算式在生成的 `omni-gfx` 库，本文件不复制。
*/
#ifndef OMNI_SKY_SUN_MOON_INCLUDED
#define OMNI_SKY_SUN_MOON_INCLUDED
/*
日月圆盘：预计算大气之外的太阳与月亮圆盘遮罩，供天空把日月光点叠加到天空上。
调用位置：由 `effects/sky/sky.glsl` 引入；`RenderSunDisc`、`RenderMoonDisc` 在 `effects/sky/skyrender.glsl` 的主天空里调用，
    `RenderMoonDiscReflection` 在反射天空盒里用更软的圆盘。
可复制示例：
    `vec3 sunDisc = RenderSunDisc(worldDir, worldSunVector);`
    `float moonDisc = RenderMoonDisc(worldDir, worldMoonVector);`
设计原因与取舍：圆盘不是几何，而是视线与日月方向夹角的平滑遮罩；反射天空盒分辨率低，用更大的角半径换取可见。
    圆盘形状与常数已经迁到 `shaders/gfx/atmosphere.glsl`，本文件只保留太阳色、尺寸档位分支与同名转发。
    真实月亮模式改用 Eclipse 的尺寸档位；月面法线贴图本项目没有，缺少时退回程序圆盘不额外调制。
    太阳圆盘最后乘 `omniSunTint()`，太阳色与辐照倍率由 `effects/sky/suncolor.glsl` 提供。
*/
// 日月圆盘的纯形状计算放在通用库，这里只传方向与尺寸档位。
#include "/gfx/atmosphere.glsl"

// 太阳圆盘：视线越接近太阳方向越亮，边缘由平滑曲线收口。
vec3 RenderSunDisc(vec3 worldDir, vec3 sunDir){
	return vec3(1.1114, 0.9756, 0.9133) * gfx_sun_disc(worldDir, sunDir) * omniSunTint(); // 太阳偏暖的白底再乘太阳色与辐照倍率，默认全一不改画面。
}
// 月亮圆盘：形状同太阳，但边缘更硬、亮度单独交给选项。
// 真实月亮模式改用 Eclipse 的尺寸档位：角半径由 `OMNI_MOON_SIZE_SETTING` 换算，来源 `composite1.fsh:1785-1786`。
float RenderMoonDisc(vec3 worldDir, vec3 moonDir){
	#ifdef OMNI_REALMOON
		float disc = gfx_moon_disc_real(worldDir, moonDir, OMNI_MOON_SIZE_SETTING); // 档位越大圆盘越大。
		#ifdef OMNI_MOON_NORMALS
			// 起伏明暗需要 Eclipse 自带的月面法线贴图，本项目没有该贴图，退回程序圆盘不额外调制。
			disc *= 1.0; // 保留现有遮罩。
		#endif
		return disc; // 返回零到一的亮度。
	#else
		return gfx_moon_disc_default(worldDir, moonDir); // 默认的小而硬的圆盘。
	#endif
}
// 反射里的月亮圆盘：反射天空盒分辨率低，用更大的角半径换取可见。
float RenderMoonDiscReflection(vec3 worldDir, vec3 moonDir){
	return gfx_moon_disc_reflection(worldDir, moonDir); // 转发到通用库。
}
// --- Eclipse 日月绘制兼容层：参考直接返回带颜色的光斑并压暗星点 ---
vec3 drawMoon(vec3 worldSunVec, vec3 playerPos, vec3 color, inout vec3 occludeStars){
	float shape = min(max(dot(worldSunVec, playerPos)-0.9994, 0.0) / (1.0-0.9994), 1.0);
	occludeStars *= max(1.0 - shape * 5.0, 0.0);
	return shape * color * 40.0;
}
vec3 drawRealMoon(vec3 worldSunVec, vec3 playerPos, vec3 color, inout vec3 occludeStars, float size){
	float shape = min(max(dot(worldSunVec, playerPos) - size, 0.0) / (1.0 - size), 1.0);
	shape = pow(shape, 0.15);
	occludeStars *= max(1.0 - shape * 50.0, 0.0);
	return color / 750.0 * shape;
}

#endif // 文件守卫结束。

// 严格对照补充说明：
// Eclipse 的日月绘制函数直接读太阳方向、玩家位置与星点遮挡量。
// 这些量由调用方显式传入，函数本身不读相机矩阵或天气缓冲。
// 月亮与真实月亮只差一个角半径与亮度标度，常数照参考保留。
// 星点遮挡量是就地修改的宿主状态，调用方负责保存与继续传递。
// 兼容重载不改变圆盘形状，只补上参考的签名与常数。

// 补充说明：日月绘制的兼容重载只补签名与常数。
// 太阳方向、玩家位置与星点遮挡量都由调用方传入。
// 月亮形状与真实月亮形状的角半径不同，常数照参考保留。
// 这些函数不读取相机矩阵，也不修改宿主缓冲。
