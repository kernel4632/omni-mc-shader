/*
合成三号与四号的共用程序主体：两个程序都只做反射小波滤波，差别只在半径与抖动。
调用位置：`rendering/programs.json` 的 `composite3`、`composite4` 都指向本文件；
    入口分别定义 `OMNI_COMPOSITE3_PASS`、`OMNI_COMPOSITE4_PASS`，算法分支在 `composite_filter.glsl`。
可复制示例：入口写 `#define OMNI_FRAGMENT 1`、`#define OMNI_COMPOSITE4_PASS 1` 再引入本文件。
设计原因与取舍：两边的顶点、共享声明、输出与调用逐字相同，合成一个主体后只保留一份；
    半径与噪声仍由程序宏选择，画面与原来一致。
*/
#ifndef OMNI_COMPOSITE_BODY_INCLUDED // 只引入一次，避免 `main()` 与输出变量重复定义。
#define OMNI_COMPOSITE_BODY_INCLUDED // 置上标记。
#ifdef OMNI_VERTEX // 顶点阶段只做全屏三角形与光色计算。
	#include "/rendering/lights.glsl"
#endif
// 合成程序共用的片元全局量。
#include "/rendering/composite_shared.glsl"
#if defined OMNI_FRAGMENT
	/* DRAWBUFFERS:3 */
	layout(location = 0) out vec4 compositeOutput3; // 三号：滤波后的反射数据。
	// 反射小波滤波的通用入口。
	#include "/effects/reflection/reflection.glsl"
	// 按三号或四号宏选择半径与抖动。
	#include "/effects/reflection/composite_filter.glsl"
	void main(){ CompositeReflectionFilter(); } // 做一次小波滤波并写回三号。
#endif
#endif
