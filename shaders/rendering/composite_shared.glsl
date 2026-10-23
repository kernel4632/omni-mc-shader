/*
合成共享声明：六个合成程序（`composite` 到 `composite5`）共用的片元全局量，全项目只在这里声明一次。
调用位置：`rendering/composite.glsl` 在顶点阶段之后、各合成程序之前引入一次；只有片元阶段用到。
可复制示例：效果文件直接使用 `texelCoord`、`texCoord`、光色 varying 与表面数据，不需要自己再声明。
设计原因与取舍：
    原程序一个程序一个文件，每个文件各自重复声明这同一批全局量六到八次，改一个类型要同时改多处；
    这里收成一份。光色 varying 由顶点阶段 `rendering/lights.glsl` 输出，采样器与贴图由加载器提供。
    不是所有程序都读取这里的每个量（例如三号、四号只用坐标），未用到的声明会被编译器优化掉，不影响画面。
    `shadowtex1` 不在这里：它在末地与主世界合成零号按比较采样器读，在其余程序按普通深度读，类型随程序变化，
    留给各程序自己声明；只属于合成五号的 `sunCoord`、`sunVisibility` 也留在合成五号。
*/
#ifndef OMNI_COMPOSITE_SHARED_INCLUDED // 只引入一次，避免全局量与采样器重复声明。
#define OMNI_COMPOSITE_SHARED_INCLUDED // 置上标记，后续再次引用直接跳过。

#ifdef OMNI_FRAGMENT // 只有片元阶段需要这些声明；顶点阶段只做光色计算，不读屏幕与表面数据。
	// 加载器输入与共用数学：`gl_FragCoord`、画面尺寸、时间、相机矩阵与颜色曲线。
	#include "/common/uniforms.glsl"
	#include "/common/math.glsl"
	ivec2 texelCoord = ivec2(gl_FragCoord.xy); // 整数像素坐标，读回各号画面与阴影贴图用。
	vec2 texCoord = gl_FragCoord.xy * pixelSize; // 零到一屏幕坐标。
	in vec3 worldShadowVector; // 阴影相机对应的世界光方向，由顶点阶段传入。
	in vec3 shadowVector; // 上面那个方向在视空间的值。
	in vec3 worldSunVector; // 太阳的世界方向。
	in vec3 worldMoonVector; // 月亮的世界方向。
	in vec3 colorShadowlight; // 日月直射光色之和。
	in vec3 colorSunlight; // 太阳直射光色。
	in vec3 colorMoonlight; // 月亮直射光色。
	in vec3 colorSkylight; // 日月环境光色之和。
	in vec3 colorSunSkylight; // 太阳一侧的环境光色。
	in vec3 colorMoonSkylight; // 月亮一侧的环境光色。
	in vec3 colorTorchlight; // 火把光色。
	in float timeNoon; // 太阳高度因子。
	in float timeMidnight; // 月亮高度因子。
	uniform sampler2D shadowtex0; // 阴影遮挡图，受光判定与半透明遮挡用。
	uniform sampler2D shadowcolor0; // 彩色半影阴影颜色图，染色阴影用。
	uniform sampler2D gaux1; // 第一张涟漪动画贴图，雨点落水用。
	uniform sampler2D gaux2; // 第二张涟漪动画贴图，雨点落水用。
	uniform sampler2D gaux3; // 第三张涟漪动画贴图，雨点落水用。
	// 表面数据与材质掩码：读回颜色、法线、深度与材质编号。
	#include "/bind/ground/material.glsl"
	// 先定义 `OMNI_TAA`，后面的坐标换算与噪声按它选择采样方式。
	#include "/rendering/clarity/antialiasing.glsl"
	// 屏幕与视空间互转，各程序都用来还原表面位置。
	#include "/common/coordinates.glsl"
	// 蓝噪声，遮蔽、阴影与反射抖动共用。
	#include "/common/noise.glsl"
#endif // 片元阶段声明结束。
#endif // 文件守卫结束。
