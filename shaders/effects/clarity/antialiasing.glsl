/*
时间抗锯齿：用上一帧画面按相机运动重投影到当前帧，再按邻域颜色范围裁剪后混合，抹平边缘与噪点。
来源：时间重投影、邻域裁剪、颜色空间转换与深度取样照 iterationT `Lib/BasicFounctions/TAA.glsl` 一比一移植；
  最终的边缘抗锯齿 `Fxaa` 照 iterationT `Lib/Programs/Final.glsl` 一比一移植。
调用位置：
  合成七号片元调用 `WriteTaaHistory`（本文件末尾，按 `OMNI_COMPOSITE7_PASS` 隔开），把重投影后的颜色写回七号画面作为下一帧历史；
  final 片元在关闭手或玩家抗锯齿时对被排除的像素调用 `Fxaa` 补一次边缘抗锯齿。
本文件的相机速度函数叫 `TaaCameraVelocity`：它同时回填重投影要用的深度，并区分玻璃与冰。
  同名用途在 `effects/lighting/ambient.glsl` 是 `GiCameraVelocity`、在 `effects/lens/lens.glsl` 是
  `MotionBlurCameraVelocity`，三份实现不同，按 iterationT 原程序各留一份，名字体现用途以区分。
可复制示例：
  `vec4 taa = TemporalReprojection(taaTexCoord, TaaCameraVelocity(depth, materialIDs), depth);`
  `color = Fxaa(color, taaTexCoord);`
  `compositeOutput7 = WriteTaaHistory();`  合成七号把历史写成七号画面的内容。
调用前提（iterationT 原样保留）：
  坐标换算函数按 `OMNI_TAA` 决定是否撤销本帧抖动，所以任何用到坐标换算的主体都必须先引入本文件；
  时间重投影依赖调用方先声明 `taaTexelCoord`、`taaTexCoord`，并让材质编号 `MATID_*` 可见；
  `Fxaa` 读取一号画面与 `pixelSize`。
设计原因与取舍：
  只有相机重投影，没有实体速度缓冲，动态物体会靠邻域裁剪与深度比较把过时历史挡掉；
  历史可信度由混合权重、运动量和深度差共同决定，任一项对不上就少用或不用历史，避免拖影。
  下界的时间抗锯齿与主世界不同（参考深度打包进七号画面透明度通道），按 `OMNI_NETHER` 分支在本文件内提供另一套取样、邻域统计与重投影；
  合成七号的主体 `WriteTaaHistory` 与算法合在本文件：它只做选项分派与写出，拆成另一个文件没有额外好处；
  按 `OMNI_COMPOSITE7_PASS` 隔开，因为本文件还被地形、阴影、延迟等程序引入，它们没有合成七号的输入。
*/
#ifndef OMNI_ANTIALIASING_INCLUDED // 只引入一次，避免宏与函数重复定义。
#define OMNI_ANTIALIASING_INCLUDED // 置上标记。
// @effect {"label":{"zh_cn":"时域抗锯齿","en_us":"Temporal AA"}}
// @option {"label": {"zh_cn": "时间抗锯齿", "en_us": "TAA"}, "description": {"zh_cn": "用上一帧历史把边缘和噪点叠平滑；开启前请先在着色器设置里打开抗锯齿。", "en_us": "Uses previous-frame history to smooth edges and noise; enable antialiasing in shader settings first."}}
#define OMNI_TAA
// @option {"label": {"zh_cn": "远景也参与抖动", "en_us": "Jitter distant terrain"}, "description": {"zh_cn": "远景地块随近景一起做逐帧抖动，交界处才和近景对齐；关掉后远景不抖、更稳，但交界可能与近景错半像素。默认开启。来源 Eclipse 的 DH_TAA_JITTER。", "en_us": "Lets distant chunks share the per-frame jitter with nearby terrain so the boundary stays aligned; off keeps distant terrain steadier but may misalign it by half a pixel. On by default. Ports Eclipse's DH_TAA_JITTER."}}
#define OMNI_DH_TAA_JITTER
// @option {"label": {"zh_cn": "历史混合权重", "en_us": "History Blend Weight"}, "slider": true, "description": {"zh_cn": "越高画面越稳、越容易留轻微拖影。", "en_us": "Higher is steadier but more prone to slight smearing."}}
#define OMNI_TAA_BLENDWEIGHT 0.97 // [0.9 0.91 0.92 0.93 0.94 0.95 0.96 0.97 0.98 0.99]
// @option {"label": {"zh_cn": "历史裁剪强度", "en_us": "History Clip Aggression"}, "slider": true, "description": {"zh_cn": "邻域裁剪的松紧，越大越容易拒绝历史、减少拖影。", "en_us": "Tightness of neighbourhood clipping; higher rejects more history and reduces smearing."}}
#define OMNI_TAA_AGGRESSION 2.0 // [1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 2.1 2.2 2.3 2.4 2.5 2.6 2.7 2.8 2.9 3.0 3.5 4.0 4.5 5.0 6.0 7.0 8.0 9.0 10.0]
// @option {"label": {"zh_cn": "关闭手部抗锯齿", "en_us": "Disable Hand TAA"}, "description": {"zh_cn": "手不参与时间抗锯齿，减少手的拖影；这类像素改用边缘抗锯齿。", "en_us": "Excludes the hand from TAA to reduce smearing; those pixels fall back to edge AA."}}
//#define OMNI_DISABLE_HAND_TAA
// @option {"label": {"zh_cn": "关闭玩家抗锯齿与动态模糊", "en_us": "Disable Player TAA & Motion Blur"}, "description": {"zh_cn": "玩家角色不参与时间抗锯齿和动态模糊，减少第三人称下的拖影。", "en_us": "Excludes the player from TAA and motion blur."}}
//#define OMNI_DISABLE_PLAYER_TAA_MOTION_BLUR
// @option {"label": {"zh_cn": "深度比较阈值", "en_us": "Depth Compare Threshold"}, "slider": true, "description": {"zh_cn": "判断历史点是否被遮挡的深度差上限；越小越容易判定为被遮挡、越少拖影。", "en_us": "Depth difference above which history is treated as occluded; smaller rejects more history and reduces smearing."}}
#define OMNI_TAA_DEPTH_COMPARE_THRESHOLD 0.0007 // [0.00002 0.00003 0.00005 0.00007 0.0001 0.00015 0.0002 0.0003 0.0005 0.0007 0.001 0.0015 0.002 0.003 0.005 0.007 0.01 0.015 0.02 0.03 0.05 0.07 0.1]

// --- 内部常数：原 `Settings.glsl` 里不进菜单的时间抗锯齿开关 ---
#define TAA_CLOSEST_DEPTH // 向前重投影时取三乘三邻域里最近的深度，减少物体边缘把背景深度带偏。
#define TAA_BICUBIC_PREVIOUS // 读取历史画面时用三次采样，比双线性更锐利。
#define TAA_DEPTH_COMPARE // 用上一帧深度和当前深度比较，判断对应点是否被遮挡。
#define TAA_MICRO_BLUR // 历史权重很低时对当前帧做一次极轻的邻域平均，压掉抖动。
//#define TAA_BICUBIC_CURRENT // 原程序默认关闭：当前帧用双线性采样即可。
//#define TAA_CLIP_TO_CENTER // 原程序默认关闭：邻域裁剪默认用另一种做法。

// 加载器输入、共享数学先引入；坐标换算依赖本文件定义的 `OMNI_TAA`，所以放在选项之后。
#include "/common/uniforms.glsl"
#include "/common/math.glsl"
#include "/common/coordinates.glsl"
// 材质编号 `MATID_*` 由材质效果文件定义，本文件的速度函数要用，自己引入避免调用方漏引。
#include "/effects/ground/material.glsl"
// 本文件自己的像素坐标：不依赖调用程序声明的全局量，任何程序在任意阶段引入都能编译。
// 为什么自己取：邻域取样需要一个全局像素坐标，各程序各自声明的同名全局量不一定排在本文件之前。
// 为什么放在片元守卫里面：`gl_FragCoord` 只有片元阶段存在，顶点阶段不编译下面这些函数。
#ifdef OMNI_FRAGMENT
ivec2 taaTexelCoord = ivec2(gl_FragCoord.xy); // 整数像素坐标。
vec2 taaTexCoord = gl_FragCoord.xy * pixelSize; // 零到一屏幕坐标。

// --- 颜色空间：把颜色转到亮度与色度分离的空间，重投影时更稳 ---
// 转到该空间后亮度单独一维，色度两维，历史裁剪对色度的扰动更小，边缘不容易染色。
// 以下函数都在片元阶段运行：它们读 `taaTexelCoord`、`gl_FragCoord` 与各号画面，顶点阶段没有这些输入。
// 顶点阶段（例如合成零号的光色顶点）也会整段引入本文件，所以上面的阶段宏把整份实现隔开，顶点不会编译它们。
vec3 RGB_To_YCoCg(vec3 color) {
	return vec3(color.r * 0.25 + color.g * 0.5 + color.b * 0.25, color.r * 0.5 - color.b * 0.5, color.r * -0.25 + color.g * 0.5 + color.b * -0.25); // 一维亮度两维色度。
}

// 从亮度色度空间换回红绿蓝，与上面互逆。
vec3 YCoCg_To_RGB(vec3 color) {
	float temp = color.r - color.b; // 亮度与色度之差。
	return vec3(temp + color.g, color.r + color.b, temp - color.g); // 解回三个通道。
}

// --- 当前帧取样 ---
// 主世界与末地把颜色与深度分开取；下界把颜色和线性深度打包进同一个四分量的结果。
// 为什么分两套：下界的时间抗锯齿要把本帧参考深度和历史参考深度一起重投影，取样就得连同深度一起带回来。
#ifndef OMNI_NETHER
// 双线性读当前帧颜色并转到亮度色度空间。
vec3 SampleCurrColor(vec2 coord){
	return RGB_To_YCoCg(textureLod(colortex1, coord, 0.0).rgb); // 连续坐标用双线性。
}
// 精确读某个纹素的当前帧颜色，邻域统计用。
vec3 SampleCurrColorFetch(ivec2 coord){
	return RGB_To_YCoCg(texelFetch(colortex1, coord, 0).rgb); // 整数坐标精确读取。
}
// 用三次采样读当前帧颜色，边缘比双线性更锐。
vec3 SampleCurrColorBicubic(vec2 coord){
	return RGB_To_YCoCg(BicubicTexture(colortex1, coord, screenSize)); // 三次采样来自共用数学。
}
// 读上一帧颜色；开启三次采样选项时用三次，否则双线性。
vec3 SamplePrevColor(vec2 coord){
	#ifdef TAA_BICUBIC_PREVIOUS // 原程序默认用三次采样。
		return RGB_To_YCoCg(BicubicTexture(colortex7, coord, screenSize)); // 三次采样历史。
	#else // 关闭时用双线性。
		return RGB_To_YCoCg(textureLod(colortex7, coord, 0.0).rgb); // 双线性历史。
	#endif
}
#else // 下界版：取样结果连线性深度一起返回。
// 用四次采样读一个四分量纹理，与上面的 `BicubicTexture` 同理，只是保留透明度通道。
vec4 BicubicTextureVec4(sampler2D texSampler, vec2 coord, vec2 texSize){
	vec2 texPixelSize = 1.0 / texSize; // 一个纹素的大小。
	coord = coord * texSize; // 换到像素坐标。

	vec2 p = floor(coord - 0.5) + 0.5; // 采样核中心。
	vec2 f = coord - p; // 中心偏移。
	vec2 f2 = f * f; // 平方。
	vec2 f3 = f * f2; // 立方。

	const float c = 0.5; // 三次核系数，与原程序一致。
	vec2 w0 =        -c  * f3 +  2.0 * c         * f2 - c * f; // 最左权重。
	vec2 w1 =  (2.0 - c) * f3 - (3.0 - c)        * f2         + 1.0; // 左权重。
	vec2 w2 = -(2.0 - c) * f3 + (3.0 -  2.0 * c) * f2 + c * f; // 右权重。
	vec2 w3 =         c  * f3 -                c * f2; // 最右权重。

	vec2 w12 = w1 + w2; // 左右权重和。
	vec2 tc12 = texPixelSize * (p + w2 / w12); // 左右两个采样点的混合坐标。
	vec2 tc0 = texPixelSize * (p - 1.0); // 最左采样点。
	vec2 tc3 = texPixelSize * (p + 2.0); // 最右采样点。

	vec4 color = textureLod(texSampler, vec2(tc12.x, tc0.y ), 0.0) * (w12.x * w0.y ) + // 五个采样点加权。
				 textureLod(texSampler, vec2(tc0.x,  tc12.y), 0.0) * (w0.x  * w12.y) +
				 textureLod(texSampler, vec2(tc12.x, tc12.y), 0.0) * (w12.x * w12.y) +
				 textureLod(texSampler, vec2(tc3.x,  tc12.y), 0.0) * (w3.x  * w12.y) +
				 textureLod(texSampler, vec2(tc12.x, tc3.y ), 0.0) * (w12.x * w3.y );
	return color / (w12.x * w0.y + w0.x * w12.y + w12.x * w12.y + w3.x * w12.y + w12.x * w3.y); // 除以权重和归一化。
}
// 双线性读当前帧，颜色转亮度色度空间，透明度换成线性深度。
vec4 SampleCurr(vec2 coord){
	vec4 curr = textureLod(colortex1, coord, 0.0); // 读当前帧颜色与深度。
	curr.rgb = RGB_To_YCoCg(curr.rgb); // 颜色转亮度色度空间。
	curr.a = LinearDepth_From_ScreenDepth(curr.a); // 深度换米制。
	return curr; // 返回四分量。
}
// 精确读某个纹素的当前帧，邻域统计用。
vec4 SampleCurrFetch(ivec2 coord){
	vec4 curr = texelFetch(colortex1, coord, 0); // 精确读当前帧。
	curr.rgb = RGB_To_YCoCg(curr.rgb); // 颜色转亮度色度空间。
	curr.a = LinearDepth_From_ScreenDepth(curr.a); // 深度换米制。
	return curr; // 返回四分量。
}
// 用四次采样读当前帧，边缘更锐；原程序默认关闭，本函数只在打开时被调用。
vec4 SampleCurrBicubic(vec2 coord){
	vec4 curr = BicubicTextureVec4(colortex1, coord, screenSize); // 四次采样当前帧。
	curr.rgb = RGB_To_YCoCg(curr.rgb); // 颜色转亮度色度空间。
	curr.a = LinearDepth_From_ScreenDepth(curr.a); // 深度换米制。
	return curr; // 返回四分量。
}
// 双线性读上一帧历史里打包的参考深度，位置存成两分量，横向纵向各插值一次。
vec2 SamplePreviousDepthBilinear(vec2 coord){
	coord = coord * screenSize - 0.5; // 换到纹素坐标并移到纹素中心。

	vec2 f = fract(coord); // 纹素内的小数偏移。
	ivec2 texel = ivec2(coord); // 左上角纹素。

	vec2 s0 = Unpack2x16(texelFetch(colortex7, texel, 0).a); // 左上角两个参考深度。
	vec2 s1 = Unpack2x16(texelFetch(colortex7, texel + ivec2(1, 0), 0).a); // 右上角。
	vec2 s2 = Unpack2x16(texelFetch(colortex7, texel + ivec2(0, 1), 0).a); // 左下角。
	vec2 s3 = Unpack2x16(texelFetch(colortex7, texel + ivec2(1, 1), 0).a); // 右下角。

	return mix(mix(s0, s1, f.x), mix(s2, s3, f.x), f.y); // 双向插值。
}
// 读上一帧历史：颜色转亮度色度空间，参考深度解包后换米制，第一个分量是上一帧参考深度。
vec4 SamplePrevious(vec2 coord){
	#ifdef TAA_BICUBIC_PREVIOUS // 原程序默认用三次采样。
		vec3 prevColor = RGB_To_YCoCg(BicubicTexture(colortex7, coord, screenSize)); // 三次采样历史颜色。
	#else // 关闭时用双线性。
		vec3 prevColor = RGB_To_YCoCg(textureLod(colortex7, coord, 0.0).rgb); // 双线性历史颜色。
	#endif
	float prevReferenceDepth = LinearDepth_From_ScreenDepth(SamplePreviousDepthBilinear(coord).x); // 解包并换米制的上一帧参考深度。
	return vec4(prevColor, prevReferenceDepth); // 返回颜色与参考深度。
}
#endif // 当前帧取样分支结束。

// --- 深度取样 ---
// 精确读当前帧某个像素的深度。
float SampleDepthFetch(ivec2 coord){
	return texelFetch(depthtex0, coord, 0).x; // 整数坐标精确读取。
}
// 取当前帧三乘三邻域里最近的深度，作为该像素的代表深度，减少边缘把远处深度带入。
float SampleCurrDepthFetchClosest3x3(ivec2 coord){
	float depth0 = SampleDepthFetch(coord + ivec2(-1, -1)); // 左上。
	float depth1 = SampleDepthFetch(coord + ivec2( 0, -1)); // 上方。
	float depth2 = SampleDepthFetch(coord + ivec2( 1, -1)); // 右上。
	float depth3 = SampleDepthFetch(coord + ivec2(-1,  0)); // 左侧。
	float depth4 = SampleDepthFetch(coord + ivec2( 0,  0)); // 中心。
	float depth5 = SampleDepthFetch(coord + ivec2( 1,  0)); // 右侧。
	float depth6 = SampleDepthFetch(coord + ivec2(-1,  1)); // 左下。
	float depth7 = SampleDepthFetch(coord + ivec2( 0,  1)); // 下方。
	float depth8 = SampleDepthFetch(coord + ivec2( 1,  1)); // 右下。
	return min9(depth0, depth1, depth2, depth3, depth4, depth5, depth6, depth7, depth8); // 取最近。
}
// 读上一帧历史深度。主世界与末地把线性深度直接存在七号画面透明通道；下界把两个参考深度打包进透明通道。
#ifndef OMNI_NETHER
float SamplePrevDepthFetch(ivec2 coord){
	return texelFetch(colortex7, coord, 0).w; // 透明度通道保存历史深度。
}
#else
float SamplePrevDepthFetch(ivec2 coord){
	return Unpack2x16(texelFetch(colortex7, coord, 0).a).y; // 解包后第二个分量是上一帧深度。
}
#endif // 历史深度分支结束。
// 取上一帧三乘三邻域的历史深度最小与最大值，用于深度比较的时间一致性判断。
vec2 SamplePrevDepthMinMax3x3(vec2 prevCoord){
	ivec2 nearestTexel = ivec2(prevCoord * screenSize); // 上一帧坐标换成最近纹素。
	float depth0 = SamplePrevDepthFetch(nearestTexel + ivec2(-1, -1)); // 左上。
	float depth1 = SamplePrevDepthFetch(nearestTexel + ivec2( 0, -1)); // 上方。
	float depth2 = SamplePrevDepthFetch(nearestTexel + ivec2( 1, -1)); // 右上。
	float depth3 = SamplePrevDepthFetch(nearestTexel + ivec2(-1,  0)); // 左侧。
	float depth4 = SamplePrevDepthFetch(nearestTexel + ivec2( 0,  0)); // 中心。
	float depth5 = SamplePrevDepthFetch(nearestTexel + ivec2( 1,  0)); // 右侧。
	float depth6 = SamplePrevDepthFetch(nearestTexel + ivec2(-1,  1)); // 左下。
	float depth7 = SamplePrevDepthFetch(nearestTexel + ivec2( 0,  1)); // 下方。
	float depth8 = SamplePrevDepthFetch(nearestTexel + ivec2( 1,  1)); // 右下。
	float depthMin = min9(depth0, depth1, depth2, depth3, depth4, depth5, depth6, depth7, depth8); // 最小值。
	float depthMax = max9(depth0, depth1, depth2, depth3, depth4, depth5, depth6, depth7, depth8); // 最大值。
	return vec2(depthMin, depthMax); // 返回范围。
}

// --- 当前帧邻域颜色范围 ---
// 用当前帧三乘三邻域求颜色均值、十字均值与方差，再由方差得到历史颜色的接纳范围。
// `avgColor` 与 `crossAvgColor` 由输出参数带回，前者给裁剪用，后者给微模糊用。
// 下界版额外带回邻域参考深度的最小与最大值，深度比较用它判断对应点是否被遮挡。
#ifndef OMNI_NETHER
vec3 GetVariance3x3(ivec2 coord, vec3 currColor, out vec3 avgColor, out vec3 crossAvgColor){
	vec3 color0 = SampleCurrColorFetch(coord + ivec2(-1, -1)); // 左上当前帧颜色。
	vec3 color1 = SampleCurrColorFetch(coord + ivec2( 0, -1)); // 上方当前帧颜色。
	vec3 color2 = SampleCurrColorFetch(coord + ivec2( 1, -1)); // 右上当前帧颜色。
	vec3 color3 = SampleCurrColorFetch(coord + ivec2(-1,  0)); // 左侧当前帧颜色。
	vec3 color4 = SampleCurrColorFetch(coord + ivec2( 0,  0)); // 中心当前帧颜色。
	vec3 color5 = SampleCurrColorFetch(coord + ivec2( 1,  0)); // 右侧当前帧颜色。
	vec3 color6 = SampleCurrColorFetch(coord + ivec2(-1,  1)); // 左下当前帧颜色。
	vec3 color7 = SampleCurrColorFetch(coord + ivec2( 0,  1)); // 下方当前帧颜色。
	vec3 color8 = SampleCurrColorFetch(coord + ivec2( 1,  1)); // 右下当前帧颜色。
	crossAvgColor = color1 + color3 + color4 + color5 + color7; // 十字五点的和。
	avgColor = (crossAvgColor + color0 + color2 + color6 + color8) / 9.0; // 九点均值。
	crossAvgColor *= 0.2; // 十字均值。
	vec3 m2 = (color0 * color0 + color1 * color1 + color2 * color2 + color3 * color3 + color4 * color4 + color5 * color5 + color6 * color6 + color7 * color7 + color8 * color8) / 9.0; // 二阶矩。
	vec3 variance = sqrt(m2 - avgColor * avgColor) * OMNI_TAA_AGGRESSION; // 标准差乘裁剪强度得到范围半径。
	vec3 minColor = min(avgColor - variance, currColor) * 0.5; // 范围下界，至少要把当前颜色包进去。
	vec3 maxColor = max(avgColor + variance, currColor) * 0.5; // 范围上界。
	avgColor = minColor + maxColor; // 输出范围中心。
	return maxColor - minColor; // 输出范围半径。
}
#else
vec3 GetVariance3x3(ivec2 coord, vec3 currColor, out vec3 avgColor, out vec3 crossAvgColor, out vec2 referenceDepthMinMax){
	vec4 data0 = SampleCurrFetch(coord + ivec2(-1, -1)); // 左上当前帧颜色与深度。
	vec4 data1 = SampleCurrFetch(coord + ivec2( 0, -1)); // 上方。
	vec4 data2 = SampleCurrFetch(coord + ivec2( 1, -1)); // 右上。
	vec4 data3 = SampleCurrFetch(coord + ivec2(-1,  0)); // 左侧。
	vec4 data4 = SampleCurrFetch(coord + ivec2( 0,  0)); // 中心。
	vec4 data5 = SampleCurrFetch(coord + ivec2( 1,  0)); // 右侧。
	vec4 data6 = SampleCurrFetch(coord + ivec2(-1,  1)); // 左下。
	vec4 data7 = SampleCurrFetch(coord + ivec2( 0,  1)); // 下方。
	vec4 data8 = SampleCurrFetch(coord + ivec2( 1,  1)); // 右下。
	crossAvgColor = data1.rgb + data3.rgb + data4.rgb + data5.rgb + data7.rgb; // 十字五点的和。
	avgColor = (crossAvgColor + data0.rgb + data2.rgb + data6.rgb + data8.rgb) / 9.0; // 九点均值。
	crossAvgColor *= 0.2; // 十字均值。
	vec3 m2 = (data0.rgb * data0.rgb + data1.rgb * data1.rgb + data2.rgb * data2.rgb + data3.rgb * data3.rgb + data4.rgb * data4.rgb + data5.rgb * data5.rgb + data6.rgb * data6.rgb + data7.rgb * data7.rgb + data8.rgb * data8.rgb) / 9.0; // 二阶矩。
	vec3 variance = sqrt(m2 - avgColor * avgColor) * OMNI_TAA_AGGRESSION; // 标准差乘裁剪强度得到范围半径。
	vec3 minColor = min(avgColor - variance, currColor) * 0.5; // 范围下界。
	vec3 maxColor = max(avgColor + variance, currColor) * 0.5; // 范围上界。
	referenceDepthMinMax = vec2(min9(data0.a, data1.a, data2.a, data3.a, data4.a, data5.a, data6.a, data7.a, data8.a), // 邻域最小参考深度。
								max9(data0.a, data1.a, data2.a, data3.a, data4.a, data5.a, data6.a, data7.a, data8.a)); // 邻域最大参考深度。
	avgColor = minColor + maxColor; // 输出范围中心。
	return maxColor - minColor; // 输出范围半径。
}
#endif // 邻域范围分支结束。

// --- 把历史颜色夹进当前帧范围 ---
// 落在范围外的历史说明对应点已经变化，按两种做法之一把它拉回范围，避免旧颜色拖影。
vec3 clipAABB(vec3 avgColor, vec3 variance, vec3 prevColor){
	#ifdef TAA_CLIP_TO_CENTER // 原程序默认关闭的裁剪做法：朝范围中心拉。
		const float eps = 1e-20; // 极小量，避免除零。
		vec3 p_clip = avgColor; // 范围中心。
		vec3 e_clip = variance - eps; // 范围半径。
		vec3 v_clip = prevColor - p_clip; // 历史相对中心的偏移。
		vec3 v_unit = v_clip.xyz / e_clip; // 相对半径的偏移。
		vec3 a_unit = abs(v_unit); // 各分量绝对值。
		float ma_unit = max3(a_unit.x, a_unit.y, a_unit.z); // 最大的越界比例。
		if (ma_unit > 1.0) // 超出范围才夹回。
			return p_clip + v_clip / ma_unit; // 沿原方向拉回边界。
		else // 没超出就原样保留。
			return prevColor; // 历史可用。
	#else // 原程序默认做法：按分量分别裁剪。
		vec3 diff = prevColor - avgColor; // 历史相对中心的偏移。
		vec3 clipMax = mix(vec3(1.0), variance / diff, greaterThan(diff, variance)); // 超出上界的分量按比例缩小。
		vec3 clipMin = mix(vec3(1.0), -variance / diff, lessThan(diff, -variance)); // 超出下界的分量按比例缩小。
		diff *= clipMax.x * clipMax.y * clipMax.z * clipMin.x * clipMin.y * clipMin.z; // 三个分量一次性缩到范围里。
		return avgColor + diff; // 返回夹好的历史颜色。
	#endif
}

// --- 时间重投影 ---
// 把当前帧按相机重投影到上一帧，再用邻域范围、运动量、深度一致性共同决定历史权重，返回合成后的颜色与深度。
// `velocity` 是当前像素相对上一帧的屏幕位移；`currDepthMin` 是当前帧代表深度。
// 下界版额外返回重投影后的参考深度，写回历史时和当前深度一起打包，供下一帧的深度比较使用。
#ifndef OMNI_NETHER
vec4 TemporalReprojection(vec2 coord, vec3 velocity, float currDepthMin){
	vec2 unjitterCoord = coord + taaJitter * 0.5; // 撤销本帧抖动，取样才落在真实位置。
	#ifdef TAA_BICUBIC_CURRENT // 原程序默认关闭。
		vec3 currColor = SampleCurrColorBicubic(unjitterCoord); // 当前帧三次采样。
	#else // 默认用双线性。
		vec3 currColor = SampleCurrColor(unjitterCoord); // 当前帧双线性采样。
	#endif
	vec3 avgColor = currColor; // 邻域均值初值。
	vec3 crossAvgColor = currColor; // 十字均值初值。
	vec3 variance = GetVariance3x3(taaTexelCoord, currColor, avgColor, crossAvgColor); // 求邻域范围。
	coord -= velocity.xy; // 把坐标退回上一帧位置。
	vec3 prevColor = SamplePrevColor(coord); // 读上一帧颜色。
	prevColor = clipAABB(avgColor, variance, prevColor); // 把历史夹进当前范围。
	float blendWeight = OMNI_TAA_BLENDWEIGHT; // 历史基础权重。
	vec2 pixelVelocity = abs(fract(velocity.xy * screenSize) - 0.5) * 2.0; // 用像素为单位的运动量衡量抖动。
	blendWeight *= sqrt(pixelVelocity.x * pixelVelocity.y) * 0.25 + 0.75; // 运动越大历史权重越低。
	blendWeight *= float(saturate(coord) == coord); // 上一帧坐标在画面外时不用历史。
	#ifdef TAA_DEPTH_COMPARE // 深度比较通过才保留历史权重。
		vec2 prevDepth = SamplePrevDepthMinMax3x3(coord); // 上一帧深度范围。
		float currDist = LinearDepth_From_ScreenDepth(currDepthMin); // 当前帧换成米制距离。
		float threshold = max(OMNI_TAA_DEPTH_COMPARE_THRESHOLD - currDist / far * 0.2 * OMNI_TAA_DEPTH_COMPARE_THRESHOLD, 1e-5); // 距离越远阈值越小，避免远处误判。
		blendWeight *= step(prevDepth.x - currDepthMin + velocity.z, threshold); // 历史更深一侧的一致性判断。
		blendWeight *= step(currDepthMin - velocity.z - prevDepth.y, threshold); // 历史更浅一侧的一致性判断。
	#endif
	#ifdef TAA_MICRO_BLUR // 历史权重很低时对当前帧先做一次极轻的邻域平均。
		currColor = mix(crossAvgColor, currColor, saturate(blendWeight * 5.0 - 0.5)); // 权重低时更倾向十字均值。
	#endif
	currColor = mix(currColor, prevColor, blendWeight); // 按权重把历史混进当前帧。
	currColor = YCoCg_To_RGB(currColor); // 换回红绿蓝。
	return vec4(currColor, currDepthMin); // 返回颜色与代表深度。
}
#else
vec4 TemporalReprojection(vec2 coord, vec3 velocity, float currDepthMin, out float referenceDepth){
	vec2 unjitterCoord = coord + taaJitter * 0.5; // 撤销本帧抖动。
	#ifdef TAA_BICUBIC_CURRENT // 原程序默认关闭。
		vec4 currData = SampleCurrBicubic(unjitterCoord); // 当前帧四次采样，连深度一起取。
	#else // 默认用双线性。
		vec4 currData = SampleCurr(unjitterCoord); // 当前帧双线性采样。
	#endif
	vec3 currColor = currData.rgb; // 当前帧颜色。
	vec3 avgColor = currColor; // 邻域均值初值。
	vec3 crossAvgColor = currColor; // 十字均值初值。
	vec2 referenceDepthMinMax = vec2(0.0); // 邻域参考深度范围。
	vec3 variance = GetVariance3x3(taaTexelCoord, currData.rgb, avgColor, crossAvgColor, referenceDepthMinMax); // 求邻域范围与参考深度范围。
	coord -= velocity.xy; // 退回上一帧坐标。
	vec4 prevData = SamplePrevious(coord); // 读上一帧颜色与参考深度。
	vec3 prevColor = prevData.rgb; // 上一帧颜色。
	prevColor = clipAABB(avgColor, variance, prevColor); // 把历史夹进当前范围。
	const float depthThreshold = 2e-5; // 参考深度的容差，极小，避免抖出条纹。
	prevData.a = clamp(prevData.a + velocity.z, referenceDepthMinMax.x - depthThreshold, referenceDepthMinMax.y + depthThreshold); // 上一帧参考深度夹到邻域范围内。
	float blendWeight = OMNI_TAA_BLENDWEIGHT; // 历史基础权重。
	vec2 pixelVelocity = abs(fract(velocity.xy * screenSize) - 0.5) * 2.0; // 像素为单位的运动量。
	blendWeight *= sqrt(pixelVelocity.x * pixelVelocity.y) * 0.25 + 0.75; // 运动越大历史权重越低。
	blendWeight *= float(saturate(coord) == coord); // 上一帧坐标出屏时不用历史。
	#ifdef TAA_DEPTH_COMPARE // 深度比较通过才保留历史权重。
		vec2 prevDepth = SamplePrevDepthMinMax3x3(coord); // 上一帧深度范围。
		float currDist = LinearDepth_From_ScreenDepth(currDepthMin); // 当前帧换成米制。
		float threshold = max(OMNI_TAA_DEPTH_COMPARE_THRESHOLD - currDist / far * 0.2 * OMNI_TAA_DEPTH_COMPARE_THRESHOLD, 1e-5); // 越远阈值越小。
		blendWeight *= step(prevDepth.x - currDepthMin + velocity.z, threshold); // 历史更深一侧的一致性判断。
		blendWeight *= step(currDepthMin - velocity.z - prevDepth.y, threshold); // 历史更浅一侧的一致性判断。
	#endif
	#ifdef TAA_MICRO_BLUR // 历史权重很低时对当前帧做一次极轻的邻域平均。
		currColor = mix(crossAvgColor, currColor, saturate(blendWeight * 5.0 - 0.5)); // 权重低时更倾向十字均值。
	#endif
	currColor = mix(currColor, prevColor, blendWeight); // 按权重把历史混进当前帧。
	referenceDepth = mix(currData.a, prevData.a, blendWeight); // 参考深度也按权重混合。
	currColor = YCoCg_To_RGB(currColor); // 换回红绿蓝。
	referenceDepth = ScreenDepth_From_LinearDepth(referenceDepth); // 参考深度换回屏幕深度再打包。
	return vec4(currColor, currDepthMin); // 返回颜色与代表深度。
}
#endif // 时间重投影分支结束。

// --- 相机速度：算出当前像素相对上一帧的屏幕位移 ---
// 远景与近景、手与世界分别用各自的矩阵重投影，任一步失败就返回零位移，让历史权重自然降低。
#ifdef DISTANT_HORIZONS // 有远景模组时区分远景。
// 远景深度取单点：远景模组自己有深度贴图，近景的邻域取最近做法在远景里不适用。
float SampleDepthDHFetch(ivec2 coord){
	return texelFetch(dhDepthTex0, coord, 0).x; // 直接读该像素的远景深度。
}
// 远景三乘三邻域取最近深度，理由与近景版本相同：边缘不让远处深度带进来。
float SampleCurrDepthDHFetchClosest3x3(ivec2 coord){
	float depth0 = SampleDepthDHFetch(coord + ivec2(-1, -1)); // 左上。
	float depth1 = SampleDepthDHFetch(coord + ivec2( 0, -1)); // 上方。
	float depth2 = SampleDepthDHFetch(coord + ivec2( 1, -1)); // 右上。
	float depth3 = SampleDepthDHFetch(coord + ivec2(-1,  0)); // 左侧。
	float depth4 = SampleDepthDHFetch(coord + ivec2( 0,  0)); // 中心。
	float depth5 = SampleDepthDHFetch(coord + ivec2( 1,  0)); // 右侧。
	float depth6 = SampleDepthDHFetch(coord + ivec2(-1,  1)); // 左下。
	float depth7 = SampleDepthDHFetch(coord + ivec2( 0,  1)); // 下方。
	float depth8 = SampleDepthDHFetch(coord + ivec2( 1,  1)); // 右下。

	return min9(depth0, depth1, depth2, depth3, depth4, depth5, depth6, depth7, depth8); // 取九个里的最近。
}
vec3 TaaCameraVelocity(out float depth, float materialIDs){
	if (materialIDs == MATID_STAINEDGLASS || materialIDs == MATID_ICE){ // 玻璃和冰用不含半透明的深度。
		depth = texelFetch(depthtex1, taaTexelCoord, 0).x; // 读一号深度。
	}else{ // 其他表面按选项取最近邻或单点深度。
		#ifdef TAA_CLOSEST_DEPTH // 原程序默认取最近邻。
			depth = SampleCurrDepthFetchClosest3x3(taaTexelCoord); // 三乘三最近深度。
		#else // 关闭时只读单点。
			depth = SampleDepthFetch(taaTexelCoord); // 单点深度。
		#endif
	}
	vec3 velocity = vec3(0.0); // 默认零位移。
	if (materialIDs != MATID_END_PORTAL){ // 末地传送门不参与重投影。
		vec3 screenPos = vec3(taaTexCoord, depth); // 当前屏幕位置与深度。
		vec3 projection = vec3(0.0); // 上一帧投影结果。
		if (screenPos.z == 1.0){ // 深度为一时说明是远景像素。
			#ifdef TAA_CLOSEST_DEPTH // 同样取最近邻。
				screenPos.z = SampleCurrDepthDHFetchClosest3x3(taaTexelCoord); // 远景最近深度。
			#else
				screenPos.z = SampleDepthDHFetch(taaTexelCoord); // 远景单点深度。
			#endif
			projection = vec3(screenPos * 2.0 - 1.0); // 转负一到一。
			projection = (vec3(vec2(dhProjectionInverse[0].x, dhProjectionInverse[1].y) * projection.xy, 0.0) + dhProjectionInverse[3].xyz) / (dhProjectionInverse[2].w * projection.z + dhProjectionInverse[3].w); // 远景逆投影到视空间。
			projection = mat3(gbufferModelViewInverse) * projection + gbufferModelViewInverse[3].xyz; // 视空间转到世界空间。
			if (screenPos.z < 1.0) projection += cameraPosition - previousCameraPosition; // 有限深度才补相机位移。
			projection = mat3(gbufferPreviousModelView) * projection + gbufferPreviousModelView[3].xyz; // 用上一帧相机转到上一帧视空间。
			projection = (vec3(gbufferPreviousProjection[0].x, gbufferPreviousProjection[1].y, gbufferPreviousProjection[2].z) * projection + gbufferPreviousProjection[3].xyz) / -projection.z * 0.5 + 0.5; // 投到上一帧屏幕。
			screenPos.z = ScreenDepth_From_DHScreenDepth(screenPos.z); // 远景深度换到近景尺度。
			projection.z = ScreenDepth_From_DHScreenDepth(projection.z); // 上一帧深度同样换算。
			depth = saturate(screenPos.z); // 输出换算后的深度。
		}else{ // 近景像素。
			projection = vec3(screenPos * 2.0 - 1.0); // 转负一到一。
			projection = (vec3(vec2(gbufferProjectionInverse[0].x, gbufferProjectionInverse[1].y) * projection.xy, 0.0) + gbufferProjectionInverse[3].xyz) / (gbufferProjectionInverse[2].w * projection.z + gbufferProjectionInverse[3].w); // 近景逆投影到视空间。
			if (depth < 0.7){ // 深度很小说明是手。
				projection += (gbufferPreviousModelView[3].xyz - gbufferModelView[3].xyz) * MC_HAND_DEPTH; // 手按固定深度偏移补偿相机位移。
			}else{ // 普通世界表面。
				projection = mat3(gbufferModelViewInverse) * projection + gbufferModelViewInverse[3].xyz; // 视空间转世界。
				projection += cameraPosition - previousCameraPosition; // 补相机位移。
				projection = mat3(gbufferPreviousModelView) * projection + gbufferPreviousModelView[3].xyz; // 转到上一帧视空间。
			}
			projection = (vec3(gbufferPreviousProjection[0].x, gbufferPreviousProjection[1].y, gbufferPreviousProjection[2].z) * projection + gbufferPreviousProjection[3].xyz) / -projection.z * 0.5 + 0.5; // 投到上一帧屏幕。
		}
		velocity = screenPos - projection; // 位移等于当前位置减上一帧位置。
	}
	return velocity; // 返回屏幕位移。
}
// 没有远景模组时与上面同理，但不处理远景分支。
#else
vec3 TaaCameraVelocity(out float depth, float materialIDs){
	if (materialIDs == MATID_STAINEDGLASS || materialIDs == MATID_ICE){ // 玻璃和冰用不含半透明的深度。
		depth = texelFetch(depthtex1, taaTexelCoord, 0).x; // 读一号深度。
	}else{ // 其他表面按选项取最近邻或单点深度。
		#ifdef TAA_CLOSEST_DEPTH // 原程序默认取最近邻。
			depth = SampleCurrDepthFetchClosest3x3(taaTexelCoord); // 三乘三最近深度。
		#else // 关闭时只读单点。
			depth = SampleDepthFetch(taaTexelCoord); // 单点深度。
		#endif
	}
	vec3 velocity = vec3(0.0); // 默认零位移。
	if (materialIDs != MATID_END_PORTAL){ // 末地传送门不参与重投影。
		vec3 screenPos = vec3(taaTexCoord, depth); // 当前屏幕位置与深度。
		vec3 projection = screenPos * 2.0 - 1.0; // 转负一到一。
		projection = (vec3(vec2(gbufferProjectionInverse[0].x, gbufferProjectionInverse[1].y) * projection.xy, 0.0) + gbufferProjectionInverse[3].xyz) / (gbufferProjectionInverse[2].w * projection.z + gbufferProjectionInverse[3].w); // 逆投影到视空间。
		if (depth < 0.7){ // 手按固定深度偏移补偿。
			projection += (gbufferPreviousModelView[3].xyz - gbufferModelView[3].xyz) * MC_HAND_DEPTH; // 手的固定偏移。
		}else{ // 普通世界表面。
			projection = mat3(gbufferModelViewInverse) * projection + gbufferModelViewInverse[3].xyz; // 视空间转世界。
			if (depth < 1.0) projection += cameraPosition - previousCameraPosition; // 有限深度才补相机位移。
			projection = mat3(gbufferPreviousModelView) * projection + gbufferPreviousModelView[3].xyz; // 转到上一帧视空间。
		}
		projection = (vec3(gbufferPreviousProjection[0].x, gbufferPreviousProjection[1].y, gbufferPreviousProjection[2].z) * projection + gbufferPreviousProjection[3].xyz) / -projection.z * 0.5 + 0.5; // 投到上一帧屏幕。
		velocity = screenPos - projection; // 位移等于当前位置减上一帧位置。
	}
	return velocity; // 返回屏幕位移。
}
#endif // 远景分支结束。

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

// --- 合成七号主体：时间抗锯齿历史，逐行照 iterationT `composite7.fsh` ---
// 按选项排除手与玩家、算相机速度、做邻域裁剪重投影；下界额外把参考深度与当前深度打包进透明度通道。
// 为什么按程序宏隔开：只有合成七号需要它，本文件还被地形、阴影、延迟等程序引入，它们没有材质编号与七号输出。
// 为什么返回而不是直接写 `compositeOutput7`：本文件在被引入的程序声明输出之前就展开，返回让程序自己赋值。
#if defined OMNI_COMPOSITE7_PASS
vec4 WriteTaaHistory(){
	#ifdef OMNI_TAA // 开启时间抗锯齿才做重投影。
		float materialIDs = floor(texelFetch(colortex6, texelCoord, 0).b * 255.0); // 读当前像素的材质编号。
		float depth = 1.0; // 供相机速度函数回填的代表深度。
		vec3 velocity = TaaCameraVelocity(depth, materialIDs); // 算当前像素相对上一帧的屏幕位移，并回填深度。
		vec4 taa = vec4(0.0); // 重投影结果。
		#ifdef OMNI_NETHER // 下界重投影额外回填参考深度，写回历史时要一起打包。
			float referenceDepth = 0.0; // 重投影后的参考深度。
		#endif

		// 先算出这个像素要不要用历史：三条宏分支各把要排除的材质标记为假，其余像素保持为真。
		bool reproject = true; // 默认走重投影。
		#if defined OMNI_DISABLE_HAND_TAA && defined OMNI_DISABLE_PLAYER_TAA_MOTION_BLUR // 手与玩家都排除。
			if (materialIDs == MATID_HAND || materialIDs == MATID_ENTITIES_PLAYER) reproject = false; // 这两类像素不用历史。
		#elif defined OMNI_DISABLE_HAND_TAA // 只排除手。
			if (materialIDs == MATID_HAND) reproject = false; // 手不用历史。
		#elif defined OMNI_DISABLE_PLAYER_TAA_MOTION_BLUR // 只排除玩家。
			if (materialIDs == MATID_ENTITIES_PLAYER) reproject = false; // 玩家不用历史。
		#endif
		if (!reproject){ // 被排除的像素直接用当前帧颜色。
			taa = texelFetch(colortex1, texelCoord, 0); // 当前帧颜色。
		}else{ // 其余像素走时间重投影。
			#ifdef OMNI_NETHER // 下界用带参考深度的重投影。
				taa = TemporalReprojection(texCoord, velocity, depth, referenceDepth); // 邻域裁剪后把历史混进当前帧，并回填参考深度。
			#else // 其余维度用主世界版重投影。
				taa = TemporalReprojection(texCoord, velocity, depth); // 邻域裁剪后把历史混进当前帧。
			#endif
		}
	#else // 关闭时间抗锯齿时原样复制当前帧。
		vec4 taa = texelFetch(colortex1, texelCoord, 0); // 当前帧颜色与深度。
		#ifdef OMNI_NETHER // 下界直接沿用当前帧的深度当作参考深度。
			float referenceDepth = taa.a; // 当前帧深度就是参考深度。
		#endif
	#endif

	#ifdef OMNI_NETHER // 下界把参考深度与当前深度打包进七号画面透明度通道。
		return vec4(saturate(taa.rgb), Pack2x16(saturate(vec2(referenceDepth, taa.a)))); // 颜色加两个深度的打包值。
	#else // 其余维度直接交回。
		return taa; // 交回七号，作为下一帧的历史。
	#endif
}
#endif // 合成七号主体结束。
#endif // 片元阶段结束。
#endif // 文件守卫结束。
