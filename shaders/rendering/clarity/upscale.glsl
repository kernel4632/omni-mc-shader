/*
最终放大与锐化：把内部分辨率渲染的合成画面放大到屏幕，并做一次边缘保持的锐化。
来源：边缘方向重采样照 iterationT `Lib/IndividualFounctions/FsrEasu.glsl` 的 `FsrEasu` 一比一移植；
    对比度自适应锐化与另一支放大照 iterationT `Lib/Programs/Final.glsl` 的 `FidelityFX_CAS`、`FidelityFX_FSR1` 一比一移植。
调用位置：
    合成十六号片元调用 `FsrEasu` 放大到八号画面；
    合成十五号片元调用 `FidelityFX_CAS` 锐化一号画面；
    final 片元在渲染比例低于一时调用 `FidelityFX_FSR1`，否则调用 `FidelityFX_CAS`。
可复制示例：
    `compositeOutput8 = vec4(FsrEasu(gl_FragCoord.xy, screenSize, ceil(screenSize / MC_RENDER_QUALITY)), 0.0);`
    `color = FidelityFX_CAS(color, texelCoord);`
    `color = FidelityFX_FSR1(texelCoord);`
调用前提（iterationT 原样保留）：`FsrEasu` 与 `FidelityFX_CAS` 读取一号画面，`FidelityFX_FSR1` 读取八号画面。
    八号画面在 final 阶段要按二维画面采样，绘制主体必须先打开 `COLORTEX8_2D` 让 `colortex8` 成为二维采样器。
设计原因与取舍：放大核、锐化核与十字对比度判断都在 `gfx/upscale.glsl`，本文件只选画面与选项，函数名保持不变。
    放大只用一张中间图做边缘方向重采样，不重建高分辨率细节，代价低但不如真正的超分清晰。
*/
#ifndef OMNI_RENDER_CLARITY_UPSCALE_INCLUDED
#define OMNI_RENDER_CLARITY_UPSCALE_INCLUDED
#include "/effects/clarity/upscale.glsl"
// 亮度、邻域最值与放大核来自共用文件。
#include "/common/uniforms.glsl"
#include "/common/math.glsl"
#include "/gfx/upscale.glsl"
#include "/gfx/sampling.glsl"

// 参考签名兼容层：RGSS 旋转网格超采样在片元里自己取导数，宿主层补上贴图与像素大小。
vec4 sampleRGSS(sampler2D tex, vec2 uv, vec2 pixelSize){
	return ogxRgssSample(tex, uv, pixelSize, dFdx(uv), dFdy(uv));
}

// 参考签名兼容层：FSR 放大算法的每次邻域权重计算直接转发到通用库。
void FsrEasuSet(inout vec2 dir, inout float len, float w, float lA, float lB, float lC, float lD, float lE){
	ogxFsrEasuSet(dir, len, w, lA, lB, lC, lD, lE);
}

// 把合成一号画面按边缘方向重采样放大到目标分辨率，返回放大后的颜色。
vec3 FsrEasu(vec2 fragCoord, vec2 inputScreenSize, vec2 outputScreenSize) {
	return gfx_fsr_easu(colortex1, fragCoord, inputScreenSize, outputScreenSize); // 输入画面固定是一号，公式在通用库。
}
// 对比度自适应锐化：按十字邻域的对比度决定锐化强度，平坦区不会放大噪点。
vec3 FidelityFX_CAS(vec3 sampleE, ivec2 texelCoord) {
	return gfx_cas(colortex1, sampleE, texelCoord, OMNI_CAS_SHARPNESS, bool(OMNI_CAS_DENOISE)); // 画面与两个选项在这里传入。
}
#if MC_VERSION >= 11801 // 放大功能只在一点一八点一以后可用，因为需要较低的内部渲染比例。
// 放大后的锐化：读取八号放大输出画面，再叠一次对比度自适应锐化。
vec3 FidelityFX_FSR1(ivec2 texelCoord) {
	return gfx_fsr1(colortex8, texelCoord, OMNI_FSR_SHARPNESS, bool(OMNI_FSR_DENOISE)); // 画面与两个选项在这里传入。
}
#endif // 版本判断结束。
#endif // 阶段放大接口结束。

// 严格对照补充说明：
// FSR 放大、RGSS 采样与对比度锐化都只依赖调用方给的贴图、坐标与像素大小。
// 参考签名里的函数直接读固定画面，本文件把画面作为宿主状态显式传入。
// 这些兼容重载不改变放大核，只让参考函数名与签名能够在同一编译单元里被核对。
