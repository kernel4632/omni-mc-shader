/*
效果文件 `effects/sky/stars.glsl`：玩家选项、宿主参数换算、阶段组合与说明集中在这里，菜单由 options.py 扫描本文件生成。
调用位置：`rendering/` 下的绘制主体按需引用本文件；同目录的其它效果文件补充分阶段实现。
可复制示例：`#include "/effects/sky/stars.glsl"`，随后调用下方保留原名的效果入口。
设计原因与取舍：选项、参数换算与阶段组合同属一个效果，放在一处才找得到、改得动；算式在生成的 `omni-gfx` 库，本文件不复制。
*/
#ifndef OMNI_SKY_STARS_INCLUDED
#define OMNI_SKY_STARS_INCLUDED
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
// 参考签名兼容层：Eclipse 的 `stars` 返回亮度并回填星色，亮度口径取本项目的选项。
float stars(vec3 viewPos, out vec3 starColor){
	starColor = vec3(1.0);
	float field = max(1.0 - ogxStarStableField(viewPos * 300.0, 0.99), 0.0);
	return OMNI_STARS_BRIGHTNESS * exp(field * -20.0 * (1.0 / OMNI_STARS_AMOUNT));
}
#endif // OMNI_SKY_STARS_INCLUDED
