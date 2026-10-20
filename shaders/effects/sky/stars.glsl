/*
星空：把视线方向对齐到天球后，用 Eclipse `lib/stars.glsl` 的星场撒出星点，供延迟三号叠加到夜空。
调用位置：由 `effects/sky/sky.glsl` 引入；`CalculateStars` 在 `effects/sky/skyrender.glsl`（星点类型为点状时）
    与 `effects/world/end_sky.glsl`（末地转发）里调用。
可复制示例：
    `celestial += CalculateStars(worldDir, worldSunVector);`
设计原因与取舍：白色路径走稳定星场、彩色路径走星盒，由 `OMNI_STARS_COLORED` 开关，默认是白色。
    Eclipse 用自定义旋转摆星场，本项目沿用原有的绕日轴旋转对齐天球；Eclipse 在合成阶段乘十，
    本项目改用 `starScale` 对齐既有夜间曝光。太阳方向作为参数传入：天空会被多个程序引入，直接在函数里读全局量会让不需要光色的程序编译失败。
    星点散列、稳定星场与星盒的公式已经迁到 `shaders/gfx/atmosphere.glsl`，本文件只保留选项、编译分支与亮度口径。
*/
#ifndef OMNI_SKY_STARS_INCLUDED
#define OMNI_SKY_STARS_INCLUDED
// 星场纯计算放在通用库，这里只传亮度、密度与星色。
#include "/gfx/atmosphere.glsl"

// 星场总入口：按是否开启彩色星点选白色稳定星场或彩色星盒，再缩放成本项目亮度口径。
// 返回最终星点颜色；太阳方向只用于把星场对齐天球。
vec3 CalculateStars(vec3 worldDir, vec3 sunVector){
	worldDir = gfx_align_to_sun_axis(worldDir, sunVector); // 按罗德里格公式把星场对齐到太阳方向。

	#if OMNI_STARS_COLORED
		const float starScale = 0.05 / 75.0; // 彩色路径在 Eclipse 里带七十五倍系数，除回去，使两条路径最亮星一致。
		vec3 starColor; // 星场回填的星色。
		return starScale * gfx_stars_colored(worldDir, OMNI_STARS_BRIGHTNESS, OMNI_STARS_AMOUNT, starColor) * starColor; // 亮度乘星色。
	#else
		const float starScale = 0.05; // 与旧 `CalculateStars` 最亮星零点零五对齐，保持夜间曝光不变。
		return vec3(starScale * gfx_stars_stable(worldDir, OMNI_STARS_BRIGHTNESS, OMNI_STARS_AMOUNT)); // 白色路径没有星温，转成三分量。
	#endif
}
#endif // 文件守卫结束。
