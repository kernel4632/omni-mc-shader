/*
后期色调映射：`composite14` 程序的算法体，把一号颜色合并泛光、压暗角、乘曝光，再做色调映射与高级调色。
职责：按选项依次合并五号光晕、压暗四角、乘自动曝光、白平衡、按算子选 `ACES`、无压缩或 `AgX`，最后叠高级调色与潜行暗角。
调用位置：`rendering/post.glsl` 的 `OMNI_COMPOSITE14_PASS` 分支先引入共享声明与曝光、镜头、泛光文件，再引入本文件，
    最后 `void main(){ TonemapColor(); }` 调用；输出 `compositeOutput1` 由主文件的程序块声明。
可复制示例：`TonemapColor();`（要求调用方已提供 `texelCoord`、`texCoord`、`colortex1` 与各效果函数）。
设计原因与取舍：曝光、白平衡与三条色调映射曲线在 `effects/color/color.glsl`，暗角在 `effects/lens/lens.glsl`，
    合并泛光在 `effects/color/bloom.glsl`；本文件只做程序级的顺序排布，逐行照 `composite14.fsh`。
    原程序在这里另声明了一个局部 `texelCoord`，值与共享声明相同，这里直接用共享声明，行为不变。
*/
#ifndef OMNI_POST_TONEMAP_INCLUDED // 只引入一次，避免函数重复定义。
#define OMNI_POST_TONEMAP_INCLUDED // 置上标记，后续再次引用直接跳过。

void TonemapColor(){
	vec4 data1 = texelFetch(colortex1, texelCoord, 0); // 读一号画面，透明通道是泛光引导。
	vec3 color = CurveToLinear(data1.rgb); // 换成线性颜色。

	#ifdef OMNI_BLOOM // 开启泛光时先合并光晕。
		color = MergeBloom(color, 1.0 - data1.a); // 按引导强度把五号光晕混进来。
	#endif

	#ifdef OMNI_VIGNETTE // 开启暗角时压暗四角。
		color *= Vignette(texCoord, OMNI_VIGNETTE_FALLOFF, OMNI_VIGNETTE_ROUNDNESS); // 按到中心的距离压暗。
	#endif

	color *= GetExposureValue(); // 乘这一帧的曝光。

	color = WhiteBalance(color); // 白平衡：按色温给曝光后的线性颜色染色，默认中性时不做任何改动。

	#if OMNI_TONEMAP_OPERATOR == 1 // 序号一取 `ACES`。
		color = ACES(color); // 影院标准压缩曲线。
	#elif OMNI_TONEMAP_OPERATOR == 2 // 序号二取无压缩。
		color = None(color); // 只做伽马编码。
	#else // 其余（默认零）取 `AgX`。
		color = AgX(color); // 宽色域压缩，保住高光颜色。
	#endif

	#ifdef OMNI_ADVANCED_COLOR // 开启高级调色时做白光裁剪、亮度伽马与饱和度。
		color = AdvancedColor(color); // 一体化的调色函数。
	#endif

	#ifdef OMNI_SNEAKING_VIGNETTE // 潜行时画面下边缘再加一层暗角。
		color *= mix(1.0, Vignette(vec2(0.5, texCoord.y), 0.7, 0.0), isSneakingSmooth); // 按潜行强度混入。
	#endif

	compositeOutput1 = vec4(color, 0.0); // 写回一号画面。
}
#endif // 文件守卫结束。
