/*
效果文件 `effects/reflection/denoise.glsl`：玩家选项、宿主参数换算、阶段组合与说明集中在这里，菜单由 options.py 扫描本文件生成。
调用位置：`rendering/` 下的绘制主体按需引用本文件；同目录的其它效果文件补充分阶段实现。
可复制示例：`#include "/effects/reflection/denoise.glsl"`，随后调用下方保留原名的效果入口。
设计原因与取舍：选项、参数换算与阶段组合同属一个效果，放在一处才找得到、改得动；算式在生成的 `omni-gfx` 库，本文件不复制。
*/
#ifndef OMNI_REFLECTION_DENOISE_INCLUDED
#define OMNI_REFLECTION_DENOISE_INCLUDED
/*
反射小波滤波：把三号画面的反射数据、深度与法线图接进通用库，函数名与调用点保持不变。
来源 iterationT `composite3.fsh`、`composite4.fsh`。
调用位置：由 `effects/reflection/reflection.glsl` 引入；程序主体 `CompositeReflectionFilter()` 在
    `effects/reflection/composite_filter.glsl`，只为 composite3 / composite4 编译。
可复制示例：`AtrousWaveletFilter(reflectionData, viewPos, viewDir, normal, roughness, 40.0, vec2(0.0));`
设计原因与取舍：九点邻域的权重、亮度重整与边界保护都在 `gfx/reflection.glsl`；
    本文件只传反射图、深度图、法线图与像素大小，半径与是否抖动仍由调用方决定。
*/
// 反射小波滤波在通用库。
#include "/gfx/reflection.glsl"
// --- composite3 / composite4：反射小波滤波 ---
#if defined OMNI_COMPOSITE3_PASS || defined OMNI_COMPOSITE4_PASS
// 反射滤波：用九点小波核按法线与深度相似度加权，抹掉屏幕反射的噪点同时保住反射边界。
// 输入是反射数据、表面位置、视线方向、法线、粗糙度、滤波半径与抖动噪声；就地改写反射数据。
void AtrousWaveletFilter(inout vec4 reflectionData, vec3 viewPos, vec3 viewDir, vec3 normal, float roughness, float radius, vec2 noise){
	gfx_reflection_atrous_filter(reflectionData, viewPos, viewDir, normal, roughness, radius, noise, texCoord,
		colortex3, depthtex0, colortex4, pixelSize, gbufferProjectionInverse); // 一次调用完成九点加权滤波。
}
#endif // composite3 与 composite4 段结束。
#endif // OMNI_REFLECTION_DENOISE_INCLUDED
