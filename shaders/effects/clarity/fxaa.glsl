/*
效果文件 `effects/clarity/fxaa.glsl`：玩家选项、宿主参数换算、阶段组合与说明集中在这里，菜单由 options.py 扫描本文件生成。
调用位置：`rendering/` 下的绘制主体按需引用本文件；同目录的其它效果文件补充分阶段实现。
可复制示例：`#include "/effects/clarity/fxaa.glsl"`，随后调用下方保留原名的效果入口。
设计原因与取舍：选项、参数换算与阶段组合同属一个效果，放在一处才找得到、改得动；算式在生成的 `omni-gfx` 库，本文件不复制。
*/
#ifndef OMNI_FXAA_INCLUDED
#define OMNI_FXAA_INCLUDED
/*
边缘抗锯齿 FXAA：在当前帧颜色上按亮度梯度找边缘并做一次混合，是不开时间抗锯齿时的兜底。
来源 iterationT `Final.glsl` 的 FXAA 段。
调用位置：由 `effects/clarity/antialiasing.glsl` 引入；需要 FXAA 的程序调用 `Fxaa`。
可复制示例：`color = Fxaa(color, texCoord);`
设计原因与取舍：FXAA 只读当前帧，与 TAA 的历史重投影无关，单独成文件避免和 TAA 混在一起；默认只在没开 TAA 时生效，判断留在调用方。
*/
// --- 边缘抗锯齿：手与玩家这类不参与时间抗锯齿的像素用它补一次 ---
// 沿边缘方向做几次带权重的颜色混合，边缘两侧各取几个样本，权衡后取更接近邻域范围的一支。
// `rgbM` 是中心颜色，`coord` 是屏幕坐标；样本都有直接从一号画面取。
vec3 Fxaa(vec3 rgbM, vec2 coord){
	#define FXAA_REDUCE_MIN   (1.0/64.0) // 方向衰减下限。
	#define FXAA_REDUCE_MUL   (1.0/8.0) // 方向衰减倍率。
	#define FXAA_SPAN_MAX     16.0 // 方向跨度上限。
	vec3 rgbNW = textureLod(colortex1, coord + pixelSize * vec2(-0.5, -0.5), 0.0).xyz; // 左上样本。
	vec3 rgbNE = textureLod(colortex1, coord + pixelSize * vec2( 0.5, -0.5), 0.0).xyz; // 右上样本。
	vec3 rgbSW = textureLod(colortex1, coord + pixelSize * vec2(-0.5,  0.5), 0.0).xyz; // 左下样本。
	vec3 rgbSE = textureLod(colortex1, coord + pixelSize * vec2( 0.5,  0.5), 0.0).xyz; // 右下样本。
	vec3 luma = vec3(0.299, 0.587, 0.114); // 感知亮度权重。
	float lumaNW = dot(rgbNW, luma); // 左上亮度。
	float lumaNE = dot(rgbNE, luma); // 右上亮度。
	float lumaSW = dot(rgbSW, luma); // 左下亮度。
	float lumaSE = dot(rgbSE, luma); // 右下亮度。
	float lumaM  = dot(rgbM,  luma); // 中心亮度。
	float lumaMin = min(lumaM, min(min(lumaNW, lumaNE), min(lumaSW, lumaSE))); // 五点亮度的最小值。
	float lumaMax = max(lumaM, max(max(lumaNW, lumaNE), max(lumaSW, lumaSE))); // 五点亮度的最大值。
	vec2 dir; // 边缘方向。
	dir.x = -((lumaNW + lumaNE) - (lumaSW + lumaSE)); // 水平方向估算。
	dir.y =  ((lumaNW + lumaSW) - (lumaNE + lumaSE)); // 竖直方向估算。
	float dirReduce = max((lumaNW + lumaNE + lumaSW + lumaSE) * (0.25 * FXAA_REDUCE_MUL), FXAA_REDUCE_MIN); // 方向衰减量。
	float rcpDirMin = 1.0/(min(abs(dir.x), abs(dir.y)) + dirReduce); // 方向长度倒数。
	dir = min(vec2( FXAA_SPAN_MAX,  FXAA_SPAN_MAX), max(vec2(-FXAA_SPAN_MAX, -FXAA_SPAN_MAX), dir * rcpDirMin)) * pixelSize; // 方向夹紧跨度后换算成屏幕偏移。
	vec3 rgbA = (1.0/2.0) * (textureLod(colortex1, coord + dir * vec2(1.0/3.0 - 0.5), 0.0).xyz + textureLod(colortex1, coord + dir * vec2(2.0/3.0 - 0.5), 0.0).xyz); // 内侧两点平均。
	vec3 rgbB = rgbA * (1.0/2.0) + (1.0/4.0) * (textureLod(colortex1, coord + dir * vec2(0.0/3.0 - 0.5), 0.0).xyz + textureLod(colortex1, coord + dir * vec2(3.0/3.0 - 0.5), 0.0).xyz); // 外侧再加两点。
	float lumaB = dot(rgbB, luma); // 外侧结果的亮度。
	if ((lumaB < lumaMin) || (lumaB > lumaMax)) { // 超出邻域范围说明取外支会过冲。
		return rgbA; // 用内侧结果。
	} else { // 在范围内则用更平滑的外侧结果。
		return rgbB; // 用外侧结果。
	}
}

#endif // OMNI_FXAA_INCLUDED
