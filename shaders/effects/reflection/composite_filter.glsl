/*
合成三号与四号反射小波滤波：对三号画面的反射做两遍不同半径的小波滤波，是 iterationT `composite3.fsh`、`composite4.fsh` 的算法体一比一移植。
职责：读回三号画面反射数据，按程序选择半径四十或二十调用 `AtrousWaveletFilter`，再写回三号画面。
调用位置：`rendering/composite.glsl` 的 `OMNI_COMPOSITE3_PASS`、`OMNI_COMPOSITE4_PASS` 分支引入反射文件后引入本文件，
    两者都调用 `void main(){ CompositeReflectionFilter(); }`。
可复制示例：`CompositeReflectionFilter();`（要求调用方已提供 `texelCoord`、`texCoord` 与 `colortex3` 等）。
设计原因与取舍：两个程序只是半径与抖动不同，共用一个函数名，靠 `OMNI_COMPOSITE3_PASS`、`OMNI_COMPOSITE4_PASS` 分分支。
*/
#ifndef OMNI_COMPOSITE_FILTER_INCLUDED // 只引入一次，避免函数重复定义。
#define OMNI_COMPOSITE_FILTER_INCLUDED // 置上标记，后续再次引用直接跳过。

#if defined OMNI_COMPOSITE3_PASS // 合成三号：大半径滤波，不加抖动。
// 大半径小波滤波：半径四十，覆盖更广的反射细节（来自 `composite3.fsh`）。
void CompositeReflectionFilter(){
	GbufferData gbuffer = GetGbufferData(); // 读回本像素的完整表面数据。

	vec3 viewPos = ViewPos_From_ScreenPos(texCoord, gbuffer.depthW); // 半透明表面视空间位置。
	vec3 viewDir = normalize(viewPos); // 视线方向。

	vec4 reflectionData = texelFetch(colortex3, texelCoord, 0); // 读三号画面的反射数据。

	if (gbuffer.material.reflectionStrength > 0.0 && reflectionData.a > 0.0001){ // 有反射才滤波。
		AtrousWaveletFilter(reflectionData, viewPos, viewDir, gbuffer.normalW, gbuffer.material.roughness, 40.0, vec2(0.0)); // 大半径小波滤波，不加抖动。
	}

	compositeOutput3 = reflectionData; // 写回三号画面。
}
#elif defined OMNI_COMPOSITE4_PASS // 合成四号：小半径滤波，逐帧抖动。
// 小半径小波滤波：半径二十，配蓝噪声抖动（来自 `composite4.fsh`）。
void CompositeReflectionFilter(){
	GbufferData gbuffer = GetGbufferData(); // 读回本像素的完整表面数据。

	vec3 viewPos = ViewPos_From_ScreenPos(texCoord, gbuffer.depthW); // 半透明表面视空间位置。
	vec3 viewDir = normalize(viewPos); // 视线方向。

	vec4 reflectionData = texelFetch(colortex3, texelCoord, 0); // 读三号画面的反射数据。

	if (gbuffer.material.reflectionStrength > 0.0 && reflectionData.a > 0.0001){ // 有反射才滤波。
		#ifdef OMNI_TAA
			vec2 noise = BlueNoiseTemporal() - 0.5; // 逐帧抖动，噪点被时间平均掉。
		#else
			vec2 noise = BlueNoise() - 0.5; // 固定抖动。
		#endif
		AtrousWaveletFilter(reflectionData, viewPos, viewDir, gbuffer.normalW, gbuffer.material.roughness, 20.0, noise); // 小半径小波滤波。
	}

	compositeOutput3 = reflectionData; // 写回三号画面。
}
#endif // 程序分支结束。
#endif // 文件守卫结束。
