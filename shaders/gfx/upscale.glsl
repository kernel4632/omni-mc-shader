/*
放大与锐化模块适配层：边缘方向重采样、对比度自适应锐化与放大后锐化已迁到生成库。
调用位置：`rendering/clarity/upscale.glsl` 引用本文件；合成十五号、十六号与 final 阶段使用，
    效果层只保留画质选项换算，算式只在 `omni-gfx/src/upscale.slang` 一份。
可复制示例：
    `vec3 color = gfx_fsr_easu(colortex1, gl_FragCoord.xy, screenSize, ceil(screenSize / quality));`
    `vec3 sharp = gfx_cas(colortex1, centerColor, texelCoord, 20.0, true);`
设计原因与取舍：函数名、参数顺序与采样器类型保持原样，调用点无需改动，默认画面不会漂移；
    旧实现依赖宿主的 `saturate` 宏，现在由生成库自己的夹紧函数提供，边界更干净。
*/
#ifndef GFX_UPSCALE_INCLUDED
#define GFX_UPSCALE_INCLUDED

// 迁移后的放大与锐化实现。
// 每行只做一次转发，方便对照旧签名与生成库里的实现。
#include "/omni-gfx/upscale.glsl"

// 单个采样点按离重采样中心的距离给权重，超出钳位半径的样本不再增加贡献。
void gfx_fsr_easu_tap(inout vec3 aC, inout float aW, vec2 off, vec2 dir, vec2 len, float lob, float clp, vec3 c) {
	ogxFsrEasuTap(aC, aW, off, dir, len, lob, clp, c); // 实现在生成库。
}

// 用四组邻域估计边缘方向与长度，四组是四个子像素象限。
void gfx_fsr_easu_set(inout vec2 dir, inout float len, float w, float lA, float lB, float lC, float lD, float lE) {
	ogxFsrEasuSet(dir, len, w, lA, lB, lC, lD, lE); // 实现在生成库。
}

// 把输入画面按边缘方向重采样放大到目标分辨率。
vec3 gfx_fsr_easu(sampler2D inputTex, vec2 fragCoord, vec2 inputScreenSize, vec2 outputScreenSize) {
	return ogxFsrEasu(inputTex, fragCoord, inputScreenSize, outputScreenSize); // 实现在生成库。
}

// 对比度自适应锐化：按十字邻域的对比度决定锐化强度，平坦处几乎不动。
vec3 gfx_cas(sampler2D colorTex, vec3 sampleE, ivec2 texelCoord, float sharpness, bool denoise) {
	return ogxCas(colorTex, sampleE, texelCoord, sharpness, denoise); // 实现在生成库。
}

// 放大后的锐化：邻域布局与上面相同，样本取自放大输出画面。
vec3 gfx_fsr1(sampler2D upscaledTex, ivec2 texelCoord, float sharpness, bool denoise) {
	return ogxFsr1(upscaledTex, texelCoord, sharpness, denoise); // 实现在生成库。
}

#endif
