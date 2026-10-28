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
// FXAA 的算式在通用库，本文件只把当前画面、坐标与像素大小接过去。
#include "/omni-gfx/antialias/fxaa.glsl"
vec3 Fxaa(vec3 rgbM, vec2 coord){
	return ogxFxaa(rgbM, coord, pixelSize, colortex1); // 亮度梯度与边缘过滤在通用库。
}

#endif // OMNI_FXAA_INCLUDED
