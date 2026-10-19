/*
通用图形库颜色模块：与引擎无关的线性颜色、亮度、伽马和强光压缩。
调用位置：任何需要把线性高动态范围颜色映射到显示空间的程序；本仓库由 `effects/color/color.glsl` 引入。
可复制示例：
    vec3 a = gfx_aces(linearColor, true);
    vec3 b = gfx_agx(linearColor, 13.0, true);
    vec3 c = gfx_tonemap_none(linearColor);
设计原因与取舍：
    这里只接收显式参数，不读取任何 Minecraft、Iris 或全局 uniform，因此可以直接复制到其他 OpenGL 项目。
    函数名统一使用 `gfx_` 前缀，避免与宿主工程的同名函数冲突。
    伽马使用二点二近似，与 iterationT 原程序一致；不在这里做 sRGB 分段曲线，保持迁移前后画面相同。
*/
#ifndef GFX_COLOR_INCLUDED
#define GFX_COLOR_INCLUDED

const vec3 GFX_LUMA_WEIGHTS = vec3(0.2125, 0.7154, 0.0721); // 人眼对绿最敏感、蓝最不敏感的亮度权重。

// 线性颜色转显示伽马空间。
vec3 gfx_linear_to_gamma(vec3 color){
	return pow(color, vec3(1.0 / 2.2)); // 二点二伽马，和原管线一致。
}

// 显示伽马空间转回线性。
vec3 gfx_gamma_to_linear(vec3 color){
	return pow(color, vec3(2.2)); // 与上一函数互为逆运算。
}

// 按人眼权重求亮度，用于曝光、去饱和和暗视觉。
float gfx_luminance(vec3 color){
	return dot(color, GFX_LUMA_WEIGHTS); // 只取一个标量，后续计算更便宜。
}

// ACES 压缩曲线里的有理式，负责把中间亮度拉直、两端压住。
vec3 gfx_rrt_odt_fit(vec3 value){
	vec3 a = value * (value + 0.0245786) - 0.000090537; // 分子多项式。
	vec3 b = value * (value + 0.4329510) + 0.238081; // 分母多项式。
	return a / b; // 有理式压缩。
}

// 影院标准 ACES 近似：转工作色域、压缩、再转回显示色域。
// `abney` 为真时附加一次很小的色域修正，抵消加亮造成的色相偏移。
vec3 gfx_aces(vec3 color, bool abney){
	color *= 1.4; // 整体提亮，贴近影院观感。
	if (abney){
		color *= mat3(0.99999976, -1.26657e-7, -1.29064e-9, 1.67316e-8, 0.99999976, -5.32026e-9, -0.00725587, 6.47740e-9, 1.00725580); // 阿布尼校正矩阵。
	}
	color *= mat3(0.59719, 0.35458, 0.04823, 0.07600, 0.90834, 0.01566, 0.02840, 0.13383, 0.83777); // 转 AP1 工作色域。
	color = gfx_rrt_odt_fit(color); // 压缩动态范围。
	color *= mat3(1.60475, -0.53108, -0.07367, -0.10208, 1.10813, -0.00605, -0.00327, -0.07276, 1.07602); // 转回显示色域。
	return gfx_linear_to_gamma(color); // 输出显示伽马空间。
}

// AgX 对比度曲线，用六次多项式近似原查找表，省掉一张纹理。
vec3 gfx_agx_contrast(vec3 x){
	return (((((15.5 * x - 40.14) * x + 31.96) * x - 6.868) * x + 0.4298) * x + 0.1191) * x - 0.00232;
}

// AgX 强光压缩：先把曝光夹进承认范围，再用 S 曲线成形，尽量保住高光色相。
// `ev` 是承认的动态范围，`abney` 与 ACES 版本含义相同。
vec3 gfx_agx(vec3 color, float ev, bool abney){
	color *= 2.3; // 整体提亮，和原程序一致。
	if (abney){
		color *= mat3(0.99999976, -1.26657e-7, -1.29064e-9, 1.67316e-8, 0.99999976, -5.32026e-9, -0.00725587, 6.47740e-9, 1.00725580); // 阿布尼校正矩阵。
	}
	color *= mat3(0.842479062253094, 0.0784335999999992, 0.0792237451477643, 0.0423282422610123, 0.878468636469772, 0.0791661274605434, 0.0423756549057051, 0.0784336, 0.879142973793104); // 转宽色域工作空间。
	float hev = ev * 0.5; // 承认范围的一半。
	const float middleGrey = 0.18; // 十八灰是摄影里的中间调基准。
	color = clamp(log2(color / middleGrey), -hev, hev); // 以中间灰为基准取对数并夹住。
	color = (color + hev) / ev; // 归一到零到一。
	color = gfx_agx_contrast(color); // S 曲线成形。
	color *= mat3(1.19687900512017, -0.0980208811401368, -0.0990297440797205, -0.0528968517574562, 1.15190312990417, -0.0989611768448433, -0.0529716355144438, -0.0980434501171241, 1.15107367264116); // 转回显示原色。
	return color;
}

// 无压缩：只做伽马编码，保留全部高光，代价是容易硬剪切。
vec3 gfx_tonemap_none(vec3 color){
	return pow(color, vec3(1.0 / 2.2)); // 与显示伽马相同。
}

#endif
