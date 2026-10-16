/*
时间抗锯齿：用上一帧画面按相机运动重投影到当前帧，再按邻域颜色范围裁剪后混合，抹平边缘与噪点。
来源：时间重投影、邻域裁剪、颜色空间转换与深度取样照 iterationT `Lib/BasicFounctions/TAA.glsl` 一比一移植；
  最终的边缘抗锯齿 `Fxaa` 照 iterationT `Lib/Programs/Final.glsl` 一比一移植。
调用位置：
  合成七号片元读取材质编号、算相机速度后调用 `TemporalReprojection`，写回七号画面作为下一帧历史；
  final 片元在关闭手或玩家抗锯齿时对被排除的像素调用 `Fxaa` 补一次边缘抗锯齿。
可复制示例：
  `vec4 taa = TemporalReprojection(taaTexCoord, CalculateCameraVelocity(depth, materialIDs), depth);`
  `color = Fxaa(color, taaTexCoord);`
调用前提（iterationT 原样保留）：
  坐标换算函数按 `OMNI_TAA` 决定是否撤销本帧抖动，所以任何用到坐标换算的主体都必须先引入本文件；
  时间重投影依赖调用方先声明 `taaTexelCoord`、`taaTexCoord`，并让材质编号 `MATID_*` 可见；
  `Fxaa` 读取一号画面与 `pixelSize`。
设计原因与取舍：
  只有相机重投影，没有实体速度缓冲，动态物体会靠邻域裁剪与深度比较把过时历史挡掉；
  历史可信度由混合权重、运动量和深度差共同决定，任一项对不上就少用或不用历史，避免拖影。
  下界的时间抗锯齿与主世界不同（参考深度打包进七号画面透明度通道），由己片在本文件内按 `OMNI_NETHER` 分支补齐。
*/
#ifndef OMNI_ANTIALIASING_INCLUDED // 只引入一次，避免宏与函数重复定义。
#define OMNI_ANTIALIASING_INCLUDED // 置上标记。
// @effect {"label":{"zh_cn":"时域抗锯齿","en_us":"Temporal AA"}}
// @option {"label": {"zh_cn": "时间抗锯齿", "en_us": "TAA"}, "description": {"zh_cn": "用上一帧历史把边缘和噪点叠平滑；开启前请先在着色器设置里打开抗锯齿。", "en_us": "Uses previous-frame history to smooth edges and noise; enable antialiasing in shader settings first."}}
#define OMNI_TAA
// @option {"label": {"zh_cn": "历史混合权重", "en_us": "History Blend Weight"}, "slider": true, "description": {"zh_cn": "越高画面越稳、越容易留轻微拖影。", "en_us": "Higher is steadier but more prone to slight smearing."}}
#define OMNI_TAA_BLENDWEIGHT 0.97 // [0.9 0.91 0.92 0.93 0.94 0.95 0.96 0.97 0.98 0.99]
// @option {"label": {"zh_cn": "历史裁剪强度", "en_us": "History Clip Aggression"}, "slider": true, "description": {"zh_cn": "邻域裁剪的松紧，越大越容易拒绝历史、减少拖影。", "en_us": "Tightness of neighbourhood clipping; higher rejects more history and reduces smearing."}}
#define OMNI_TAA_AGGRESSION 2.0 // [1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 2.1 2.2 2.3 2.4 2.5 2.6 2.7 2.8 2.9 3.0 3.5 4.0 4.5 5.0 6.0 7.0 8.0 9.0 10.0]
// @option {"label": {"zh_cn": "关闭手部抗锯齿", "en_us": "Disable Hand TAA"}, "description": {"zh_cn": "手不参与时间抗锯齿，减少手的拖影；这类像素改用边缘抗锯齿。", "en_us": "Excludes the hand from TAA to reduce smearing; those pixels fall back to edge AA."}}
//#define OMNI_DISABLE_HAND_TAA
// @option {"label": {"zh_cn": "关闭玩家抗锯齿与动态模糊", "en_us": "Disable Player TAA & Motion Blur"}, "description": {"zh_cn": "玩家角色不参与时间抗锯齿和动态模糊，减少第三人称下的拖影。", "en_us": "Excludes the player from TAA and motion blur."}}
//#define OMNI_DISABLE_PLAYER_TAA_MOTION_BLUR

// --- 内部常数：原 `Settings.glsl` 里不进菜单的时间抗锯齿开关与阈值 ---
#define TAA_CLOSEST_DEPTH // 向前重投影时取三乘三邻域里最近的深度，减少物体边缘把背景深度带偏。
#define TAA_BICUBIC_PREVIOUS // 读取历史画面时用三次采样，比双线性更锐利。
#define TAA_DEPTH_COMPARE // 用上一帧深度和当前深度比较，判断对应点是否被遮挡。
#define TAA_MICRO_BLUR // 历史权重很低时对当前帧做一次极轻的邻域平均，压掉抖动。
#define TAA_DEPTH_COMPARE_THRESHOLD 0.0007 // 深度比较阈值；越远阈值越小，因为远处深度变化本来就大。
//#define TAA_BICUBIC_CURRENT // 原程序默认关闭：当前帧用双线性采样即可。
//#define TAA_CLIP_TO_CENTER // 原程序默认关闭：邻域裁剪默认用另一种做法。

// 加载器输入、共享数学先引入；坐标换算依赖本文件定义的 `OMNI_TAA`，所以放在选项之后。
#include "/common/uniforms.glsl"
#include "/common/math.glsl"
#include "/common/coordinates.glsl"
// 材质编号 `MATID_*` 由材质效果文件定义，本文件的速度函数要用，自己引入避免调用方漏引。
#include "/effects/material.glsl"
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
// 读上一帧历史深度；历史深度存在七号画面的透明度通道。
float SamplePrevDepthFetch(ivec2 coord){
	return texelFetch(colortex7, coord, 0).w; // 透明度通道保存历史深度。
}
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
		float threshold = max(TAA_DEPTH_COMPARE_THRESHOLD - currDist / far * 0.2 * TAA_DEPTH_COMPARE_THRESHOLD, 1e-5); // 距离越远阈值越小，避免远处误判。
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

// --- 相机速度：算出当前像素相对上一帧的屏幕位移 ---
// 远景与近景、手与世界分别用各自的矩阵重投影，任一步失败就返回零位移，让历史权重自然降低。
#ifdef DISTANT_HORIZONS // 有远景模组时区分远景。
vec3 CalculateCameraVelocity(out float depth, float materialIDs){
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
vec3 CalculateCameraVelocity(out float depth, float materialIDs){
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
#endif // 片元阶段结束。
#endif // 文件守卫结束。
