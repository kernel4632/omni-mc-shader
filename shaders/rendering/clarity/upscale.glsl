/*
放大与锐化的宿主接线：读取 Minecraft 输入、调用通用库并写出结果。
调用位置：原引用 `effects/clarity/upscale.glsl` 的程序改为引用本文件。
可复制示例：下方函数保留原有效果入口的签名，调用方式不变。
设计原因与取舍：选项留在效果层，算法在通用库，本文件只做宿主数据与算法之间的转换。
*/
#ifndef OMNI_RENDER_CLARITY_UPSCALE_INCLUDED
#define OMNI_RENDER_CLARITY_UPSCALE_INCLUDED
#include "/effects/clarity/upscale.glsl"
/*
最终放大与锐化：把内部分辨率渲染的合成画面放大到屏幕，并做一次边缘保持的锐化。
来源：边缘方向重采样照 iterationT `Lib/IndividualFounctions/FsrEASU.glsl` 的 `FsrEasu` 一比一移植；
  对比度自适应锐化与另一支放大照 iterationT `Lib/Programs/Final.glsl` 的 `FidelityFX_CAS`、`FidelityFX_FSR1` 一比一移植。
调用位置：
  合成十六号片元调用 `FsrEasu` 放大到八号画面；
  合成十五号片元调用 `FidelityFX_CAS` 锐化一号画面；
  final 片元在渲染比例低于一时调用 `FidelityFX_FSR1`，否则调用 `FidelityFX_CAS`。
可复制示例：
  `compositeOutput8 = vec4(FsrEasu(gl_FragCoord.xy, screenSize, ceil(screenSize / MC_RENDER_QUALITY)), 0.0);`
  `color = FidelityFX_CAS(color, texelCoord);`
  `color = FidelityFX_FSR1(texelCoord);`
调用前提（iterationT 原样保留）：`FsrEasu` 与 `FidelityFX_CAS` 读取一号画面，`FidelityFX_FSR1` 读取八号画面；
  八号画面在 final 阶段要按二维画面采样，绘制主体必须先打开 `COLORTEX8_2D` 让 `colortex8` 成为二维采样器。
设计原因与取舍：
  放大只用一张中间图做边缘方向重采样，不重建高分辨率细节，代价低但不如真正的超分清晰；
  两条削化都按邻域对比度自适应，平坦处几乎不动、边缘处更锐，减少放大后出现的锯齿与振铃。
*/
// 亮度、邻域最值等共享数学来自共用文件。
#include "/common/uniforms.glsl"
#include "/common/math.glsl"

// --- 边缘方向重采样：一支轻量的放大，按邻域亮度梯度估计边缘并沿边缘插值 ---
// 单个采样点按离重采样中心的距离给权重，超出钳位半径的样本不再增加贡献。
void FsrEasuTap(inout vec3 aC, inout float aW, vec2 off, vec2 dir, vec2 len, float lob, float clp, vec3 c){
	vec2 rotOff = vec2(dot(off, dir), dot(off, vec2(-dir.y, dir.x))); // 把偏移转到与边缘对齐的坐标系。
	rotOff *= len; // 按边缘方向拉伸，让各向异性核沿边缘铺得更长。
	float d2 = min(dot(rotOff, rotOff), clp); // 到中心的距离平方，夹在钳位半径内。
	float wB = 0.4 * d2 - 1.0; // 外层权重多项式的一步。
	float wA = lob * d2 - 1.0; // 内层权重多项式的一步。
	wB *= wB; // 外层权重取平方。
	wA *= wA; // 内层权重取平方。
	wB = 1.5625 * wB - 0.5625; // 外层权重成形。
	float w = wB * wA; // 内外层权重相乘得到最终权重；核在中心为一。
	aC += c * w; // 累加颜色。
	aW += w; // 累加权重。
}

// 用四组邻域估计边缘方向与长度，四组是四个子像素象限，权重是子像素面积。
void FsrEasuSet(inout vec2 dir, inout float len, float w, float lA, float lB, float lC, float lD, float lE){
	float lenX = 1.0 / max(abs(lD - lC), abs(lC - lB)); // 水平方向长度倒数，由相邻亮度差决定。
	float dirX = lD - lB; // 水平亮度梯度。
	dir.x += dirX * w; // 按子像素面积加权累加水平方向。
	lenX = saturate(abs(dirX) * lenX); // 梯度越大越像边缘。
	lenX *= lenX; // 平方让弱边缘更快衰减。
	len += lenX * w; // 累加水平长度。
	float lenY = 1.0 / max(abs(lE - lC), abs(lC - lA)); // 竖直方向长度倒数。
	float dirY = lE - lA; // 竖直亮度梯度。
	dir.y += dirY * w; // 按子像素面积加权累加竖直方向。
	lenY = saturate(abs(dirY) * lenY); // 梯度越大越像边缘。
	lenY *= lenY; // 平方。
	len += lenY * w; // 累加竖直长度。
}

// 把合成一号画面按边缘方向重采样放大到目标分辨率，返回放大后的颜色。
// `fragCoord` 是输出像素坐标，`inputScreenSize` 是输入画面尺寸，`outputScreenSize` 是输出尺寸。
// 为什么按边缘方向：直接双线性放大在斜边会出现阶梯，沿边缘拉长核能把阶梯抹平。
vec3 FsrEasu(vec2 fragCoord, vec2 inputScreenSize, vec2 outputScreenSize){
	vec2 sizeRatio = inputScreenSize / outputScreenSize; // 输入相对输出的比例，用于把输出坐标映射回输入。
	vec2 subPixelOffset = fragCoord * sizeRatio - 0.5; // 输出像素落在输入像素网格里的位置。
	vec2 sampleCenter = floor(subPixelOffset); // 最近的低分辨率整数像素。
	subPixelOffset -= sampleCenter; // 去掉整数部分，只留子像素偏移。
	ivec2 texelCoordF = ivec2(sampleCenter); // 中心纹素坐标。
	vec3 sampleB = texelFetch(colortex1, texelCoordF + ivec2( 0, -1), 0).rgb; // 四周十二个邻域样本。
	vec3 sampleC = texelFetch(colortex1, texelCoordF + ivec2( 1, -1), 0).rgb; // 右上邻域。
	vec3 sampleE = texelFetch(colortex1, texelCoordF + ivec2(-1,  0), 0).rgb; // 左侧邻域。
	vec3 sampleF = texelFetch(colortex1, texelCoordF + ivec2( 0,  0), 0).rgb; // 中心样本。
	vec3 sampleG = texelFetch(colortex1, texelCoordF + ivec2( 1,  0), 0).rgb; // 右侧邻域。
	vec3 sampleH = texelFetch(colortex1, texelCoordF + ivec2( 2,  0), 0).rgb; // 右侧隔一个的邻域。
	vec3 sampleI = texelFetch(colortex1, texelCoordF + ivec2(-1,  1), 0).rgb; // 左下邻域。
	vec3 sampleJ = texelFetch(colortex1, texelCoordF + ivec2( 0,  1), 0).rgb; // 下方邻域。
	vec3 sampleK = texelFetch(colortex1, texelCoordF + ivec2( 1,  1), 0).rgb; // 右下邻域。
	vec3 sampleL = texelFetch(colortex1, texelCoordF + ivec2( 2,  1), 0).rgb; // 右下隔一个的邻域。
	vec3 sampleN = texelFetch(colortex1, texelCoordF + ivec2( 0,  2), 0).rgb; // 下方隔一个的邻域。
	vec3 sampleO = texelFetch(colortex1, texelCoordF + ivec2( 1,  2), 0).rgb; // 右下再隔一个的邻域。
	float luminanceB = Luminance(sampleB); // 各邻域亮度，用于估计边缘。
	float luminanceC = Luminance(sampleC); // 右上亮度。
	float luminanceE = Luminance(sampleE); // 左侧亮度。
	float luminanceF = Luminance(sampleF); // 中心亮度。
	float luminanceG = Luminance(sampleG); // 右侧亮度。
	float luminanceH = Luminance(sampleH); // 右二亮度。
	float luminanceI = Luminance(sampleI); // 左下亮度。
	float luminanceJ = Luminance(sampleJ); // 下方亮度。
	float luminanceK = Luminance(sampleK); // 右下亮度。
	float luminanceL = Luminance(sampleL); // 右二下亮度。
	float luminanceN = Luminance(sampleN); // 下二亮度。
	float luminanceO = Luminance(sampleO); // 右下二亮度。
	vec2 dir = vec2(0.0); // 边缘方向。
	float len = 0.0; // 边缘长度。
	FsrEasuSet(dir, len, (1.0 - subPixelOffset.x) * (1.0 - subPixelOffset.y), luminanceB, luminanceE, luminanceF, luminanceG, luminanceJ); // 左下子像素象限。
	FsrEasuSet(dir, len,        subPixelOffset.x  * (1.0 - subPixelOffset.y), luminanceC, luminanceF, luminanceG, luminanceH, luminanceK); // 右下子像素象限。
	FsrEasuSet(dir, len, (1.0 - subPixelOffset.x) *        subPixelOffset.y , luminanceF, luminanceI, luminanceJ, luminanceK, luminanceN); // 左上子像素象限。
	FsrEasuSet(dir, len,        subPixelOffset.x  *        subPixelOffset.y , luminanceG, luminanceJ, luminanceK, luminanceL, luminanceO); // 右上子像素象限。
	vec2 dir2 = dir * dir; // 方向各分量平方。
	float dirR = dir2.x + dir2.y; // 方向长度平方。
	bool zro = dirR < (1.0 / 32768.0); // 极小的方向视为没有边缘。
	dirR = inversesqrt(dirR); // 方向长度倒数。
	dirR = zro ? 1.0 : dirR; // 没有边缘时用一，避免除零。
	dir.x = zro ? 1.0 : dir.x; // 没有边缘时默认水平方向。
	dir *= vec2(dirR); // 归一化方向。
	len = len * 0.5; // 长度取一半。
	len *= len; // 平方。
	float stretch = dot(dir, dir) / (max(abs(dir.x), abs(dir.y))); // 边缘各向异性比例。
	vec2 len2 = vec2(1.0 + (stretch - 1.0) * len, 1.0 - 0.5 * len); // 沿边缘与垂直方向的不同拉伸。
	float lob = 0.5 - 0.29 * len; // 核宽度参数。
	float clp = 1.0 / lob; // 核钳位半径。
	vec3 min4 = min4(sampleF, sampleG, sampleJ, sampleK); // 中心四邻最小值，限制重采样范围。
	vec3 max4 = max4(sampleF, sampleG, sampleJ, sampleK); // 中心四邻最大值。
	vec3 aC = vec3(0.0); // 加权颜色。
	float aW = 0.0; // 权重和。
	FsrEasuTap(aC, aW, vec2( 0.0, -1.0) - subPixelOffset, dir, len2, lob, clp, sampleB); // 上方样本。
	FsrEasuTap(aC, aW, vec2( 1.0, -1.0) - subPixelOffset, dir, len2, lob, clp, sampleC); // 右上样本。
	FsrEasuTap(aC, aW, vec2(-1.0,  0.0) - subPixelOffset, dir, len2, lob, clp, sampleE); // 左侧样本。
	FsrEasuTap(aC, aW, vec2( 0.0,  0.0) - subPixelOffset, dir, len2, lob, clp, sampleF); // 中心样本。
	FsrEasuTap(aC, aW, vec2( 1.0,  0.0) - subPixelOffset, dir, len2, lob, clp, sampleG); // 右侧样本。
	FsrEasuTap(aC, aW, vec2( 2.0,  0.0) - subPixelOffset, dir, len2, lob, clp, sampleH); // 右二样本。
	FsrEasuTap(aC, aW, vec2(-1.0,  1.0) - subPixelOffset, dir, len2, lob, clp, sampleI); // 左下样本。
	FsrEasuTap(aC, aW, vec2( 0.0,  1.0) - subPixelOffset, dir, len2, lob, clp, sampleJ); // 下方样本。
	FsrEasuTap(aC, aW, vec2( 1.0,  1.0) - subPixelOffset, dir, len2, lob, clp, sampleK); // 右下样本。
	FsrEasuTap(aC, aW, vec2( 2.0,  1.0) - subPixelOffset, dir, len2, lob, clp, sampleL); // 右二下样本。
	FsrEasuTap(aC, aW, vec2( 0.0,  2.0) - subPixelOffset, dir, len2, lob, clp, sampleN); // 下二样本。
	FsrEasuTap(aC, aW, vec2( 1.0,  2.0) - subPixelOffset, dir, len2, lob, clp, sampleO); // 右下二样本。
	return min(max4, max(min4, aC / aW)); // 归一化后夹在中心四邻范围内，抑制过冲。
}

// --- 对比度自适应锐化：按十字邻域的对比度决定锐化量 ---
// 中心亮度在十字邻域最值之间时几乎不动，落在边缘一侧时按距离加强，所以平坦区不会放大噪点。
vec3 FidelityFX_CAS(vec3 sampleE, ivec2 texelCoord){
	// 邻域布局：上方 b、左 d、右 f、下方 h，中心是传入的 e。
	vec3 sampleB = texelFetch(colortex1, texelCoord + ivec2( 0, -1), 0).rgb; // 上方样本。
	vec3 sampleD = texelFetch(colortex1, texelCoord + ivec2(-1,  0), 0).rgb; // 左侧样本。
	vec3 sampleF = texelFetch(colortex1, texelCoord + ivec2( 1,  0), 0).rgb; // 右侧样本。
	vec3 sampleH = texelFetch(colortex1, texelCoord + ivec2( 0,  1), 0).rgb; // 下方样本。
	float luminanceB = Luminance(sampleB); // 上方亮度。
	float luminanceD = Luminance(sampleD); // 左侧亮度。
	float luminanceE = Luminance(sampleE); // 中心亮度。
	float luminanceF = Luminance(sampleF); // 右侧亮度。
	float luminanceH = Luminance(sampleH); // 下方亮度。
	float minCross = min5(luminanceB, luminanceD, luminanceE, luminanceF, luminanceH); // 十字邻域最小亮度。
	float maxCross = max5(luminanceB, luminanceD, luminanceE, luminanceF, luminanceH); // 十字邻域最大亮度。
	float weight = sqrt(saturate(min(minCross, 2.0 - maxCross) / maxCross)) * (-0.1 - OMNI_CAS_SHARPNESS * 0.01); // 对比度越低权重越接近零，锐化越弱。
	#if OMNI_CAS_DENOISE // 开启降噪时按十字噪声再压低一次。
		float noise = luminanceB * 0.25 + luminanceD * 0.25 + luminanceF * 0.25 + luminanceH * 0.25 - luminanceE; // 中心与四邻均值之差就是噪声估计。
		noise = saturate(abs(noise) / (maxCross - minCross)); // 归一化成零到一。
		weight *= 1.0 - 0.5 * noise; // 噪声越大锐化越弱。
	#endif
	vec3 sharpen = (sampleB * weight + sampleD * weight + sampleF * weight + sampleH * weight + sampleE) / (1.0 + 4.0 * weight); // 用中心减去的邻域平均做锐化。
	return max(sharpen, vec3(0.0)); // 去掉负值。
}

#if MC_VERSION >= 11801 // 放大功能只在一点一八点一以后可用，因为需要较低的内部渲染比例。
// --- 另一支放大：与上面同理，但读取八号放大输出画面，并叠加放大后的锐化 ---
// 这里只移植 iterationT 当前启用的那一支实现，另一支被 `#if 1` 关掉，不在合同移植范围。
vec3 FidelityFX_FSR1(ivec2 texelCoord){
	// 邻域布局与上面的锐化相同，样本取自八号画面。
	vec3 sampleB = texelFetch(colortex8, texelCoord + ivec2( 0, -1), 0).rgb; // 上方样本。
	vec3 sampleD = texelFetch(colortex8, texelCoord + ivec2(-1,  0), 0).rgb; // 左侧样本。
	vec3 sampleE = texelFetch(colortex8, texelCoord + ivec2( 0,  0), 0).rgb; // 中心样本。
	vec3 sampleF = texelFetch(colortex8, texelCoord + ivec2( 1,  0), 0).rgb; // 右侧样本。
	vec3 sampleH = texelFetch(colortex8, texelCoord + ivec2( 0,  1), 0).rgb; // 下方样本。
	float luminanceB = Luminance(sampleB); // 上方亮度。
	float luminanceD = Luminance(sampleD); // 左侧亮度。
	float luminanceE = Luminance(sampleE); // 中心亮度。
	float luminanceF = Luminance(sampleF); // 右侧亮度。
	float luminanceH = Luminance(sampleH); // 下方亮度。
	float minCross = min5(luminanceB, luminanceD, luminanceE, luminanceF, luminanceH); // 十字邻域最小亮度。
	float maxCross = max5(luminanceB, luminanceD, luminanceE, luminanceF, luminanceH); // 十字邻域最大亮度。
	float weight = sqrt(saturate(min(minCross, 2.0 - maxCross) / maxCross)) * (-0.1 - OMNI_FSR_SHARPNESS * 0.01); // 对比度自适应权重，用放大锐化选项。
	#if OMNI_FSR_DENOISE // 开启降噪时按十字噪声再压低一次。
		float noise = luminanceB * 0.25 + luminanceD * 0.25 + luminanceF * 0.25 + luminanceH * 0.25 - luminanceE; // 噪声估计。
		noise = saturate(abs(noise) / (maxCross - minCross)); // 归一化。
		weight *= 1.0 - 0.5 * noise; // 噪声越大锐化越弱。
	#endif
	vec3 sharpen = (sampleB * weight + sampleD * weight + sampleF * weight + sampleH * weight + sampleE) / (1.0 + 4.0 * weight); // 加权锐化。
	return max(sharpen, vec3(0.0)); // 去掉负值。
}
#endif // 版本判断结束。
#endif // OMNI_RENDER_CLARITY_UPSCALE_INCLUDED
