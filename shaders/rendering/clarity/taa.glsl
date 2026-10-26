/*
时间抗锯齿：把相机速度、历史纹理与选项换成通用库参数，重投影只调用一次。
来源 iterationT `TAA.glsl`。
调用位置：由 `effects/clarity/antialiasing.glsl` 引入；程序主体 `WriteTaaHistory` 留在入口，
    调用这里的 `TaaCameraVelocity` 与 `TemporalReprojection`。
可复制示例：`vec4 taa = TemporalReprojection(coord, velocity, currDepthMin);`
设计原因与取舍：邻域统计、历史裁剪与时间混合在 `gfx/antialias.glsl`，这里只保留相机速度与
    选项换算；相机速度要区分远景、手与材质编号，属于宿主参数转换，仍留在效果层。
*/
#ifndef OMNI_TAA_CORE_INCLUDED
#define OMNI_TAA_CORE_INCLUDED // 置上标记，后续再次引用直接跳过。
#include "/gfx/antialias.glsl"

// 颜色空间转换的兼容入口：其他文件可能按旧名字调用。
vec3 RGB_To_YCoCg(vec3 color) { return gfx_rgb_to_ycocg(color); }
vec3 YCoCg_To_RGB(vec3 color) { return gfx_ycocg_to_rgb(color); }

// --- 深度取样与相机速度：宿主矩阵、深度图和材质编号在这里换成屏幕位移 ---
// 近景深度直接读零号深度图；有远景与没有远景都使用同一张，所以只写一次。
float SampleDepthFetch(ivec2 coord){ return texelFetch(depthtex0, coord, 0).x; }
// 近景三乘三邻域取最近深度，避免边缘把更远的深度带进来。
float SampleCurrDepthFetchClosest3x3(ivec2 coord){
	return min9(SampleDepthFetch(coord + ivec2(-1, -1)), SampleDepthFetch(coord + ivec2(0, -1)), SampleDepthFetch(coord + ivec2(1, -1)),
		SampleDepthFetch(coord + ivec2(-1, 0)), SampleDepthFetch(coord), SampleDepthFetch(coord + ivec2(1, 0)),
		SampleDepthFetch(coord + ivec2(-1, 1)), SampleDepthFetch(coord + ivec2(0, 1)), SampleDepthFetch(coord + ivec2(1, 1))); // 九点最小。
}

#ifdef DISTANT_HORIZONS // 有远景模组时区分远景。
// 直接读该像素的远景深度。
float SampleDepthDHFetch(ivec2 coord){ return texelFetch(dhDepthTex0, coord, 0).x; }
// 远景三乘三邻域取最近深度，边缘不让远处深度带进来。
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
	if (materialIDs == MATID_STAINEDGLASS || materialIDs == MATID_ICE) depth = texelFetch(depthtex1, taaTexelCoord, 0).x; // 玻璃和冰用不含半透明的深度。
	else{ // 其他表面按选项取最近邻或单点深度。
		#ifdef TAA_CLOSEST_DEPTH
			depth = SampleCurrDepthFetchClosest3x3(taaTexelCoord); // 三乘三最近深度。
		#else
			depth = SampleDepthFetch(taaTexelCoord); // 单点深度。
		#endif
	}
	vec3 velocity = vec3(0.0); // 默认零位移。
	if (materialIDs != MATID_END_PORTAL){ // 末地传送门不参与重投影。
		vec3 screenPos = vec3(taaTexCoord, depth); // 当前屏幕位置与深度。
		vec3 projection = vec3(0.0); // 上一帧投影结果。
		if (screenPos.z == 1.0){ // 深度为一时说明是远景像素。
			#ifdef TAA_CLOSEST_DEPTH
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
			if (depth < 0.7) projection += (gbufferPreviousModelView[3].xyz - gbufferModelView[3].xyz) * MC_HAND_DEPTH; // 手按固定深度偏移补偿相机位移。
			else{ // 普通世界表面。
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
#else // 没有远景模组时的简化版。
vec3 TaaCameraVelocity(out float depth, float materialIDs){
	if (materialIDs == MATID_STAINEDGLASS || materialIDs == MATID_ICE) depth = texelFetch(depthtex1, taaTexelCoord, 0).x; // 玻璃和冰用不含半透明的深度。
	else{ // 其他表面按选项取最近邻或单点深度。
		#ifdef TAA_CLOSEST_DEPTH
			depth = SampleCurrDepthFetchClosest3x3(taaTexelCoord); // 三乘三最近深度。
		#else
			depth = SampleDepthFetch(taaTexelCoord); // 单点深度。
		#endif
	}
	vec3 velocity = vec3(0.0); // 默认零位移。
	if (materialIDs != MATID_END_PORTAL){ // 末地传送门不参与重投影。
		vec3 screenPos = vec3(taaTexCoord, depth); // 当前屏幕位置与深度。
		vec3 projection = screenPos * 2.0 - 1.0; // 转负一到一。
		projection = (vec3(vec2(gbufferProjectionInverse[0].x, gbufferProjectionInverse[1].y) * projection.xy, 0.0) + gbufferProjectionInverse[3].xyz) / (gbufferProjectionInverse[2].w * projection.z + gbufferProjectionInverse[3].w); // 逆投影到视空间。
		if (depth < 0.7) projection += (gbufferPreviousModelView[3].xyz - gbufferModelView[3].xyz) * MC_HAND_DEPTH; // 手按固定深度偏移补偿。
		else{ // 普通世界表面。
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

// 时间重投影：通用库做邻域裁剪与历史混合，这里只选纹理、选项与是否打包参考深度。
vec4 TemporalReprojection(vec2 coord, vec3 velocity, float currDepthMin){
	#ifdef TAA_BICUBIC_CURRENT
		const bool bicubicCurrent = true; // 当前帧三次采样。
	#else
		const bool bicubicCurrent = false; // 当前帧双线性采样。
	#endif
	#ifdef TAA_BICUBIC_PREVIOUS
		const bool bicubicPrevious = true; // 历史三次采样。
	#else
		const bool bicubicPrevious = false; // 历史双线性采样。
	#endif
	#ifdef TAA_CLIP_TO_CENTER
		const bool clipToCenter = true; // 历史朝中心拉回。
	#else
		const bool clipToCenter = false; // 按分量裁剪。
	#endif
	#ifdef TAA_DEPTH_COMPARE
		const bool depthCompare = true; // 做深度一致性判断。
	#else
		const bool depthCompare = false; // 不做深度判断。
	#endif
	#ifdef TAA_MICRO_BLUR
		const bool microBlur = true; // 低权重时做微模糊。
	#else
		const bool microBlur = false; // 不做微模糊。
	#endif
	float reference = 0.0; // 普通维度不需要参考深度。
	return gfx_taa_reproject(coord, velocity, currDepthMin, colortex1, colortex7, screenSize, taaTexelCoord, gbufferProjectionInverse, far,
		taaJitter, OMNI_TAA_BLENDWEIGHT, OMNI_TAA_AGGRESSION, OMNI_TAA_DEPTH_COMPARE_THRESHOLD, bicubicCurrent, bicubicPrevious,
		clipToCenter, depthCompare, microBlur, false, reference); // 一次调用完成重投影。
}

// 下界重投影：历史透明度打包了两个参考深度，额外回传换回屏幕深度的参考值。
vec4 TemporalReprojection(vec2 coord, vec3 velocity, float currDepthMin, out float referenceDepth){
	#ifdef TAA_BICUBIC_CURRENT
		const bool bicubicCurrent = true; // 当前帧三次采样。
	#else
		const bool bicubicCurrent = false; // 当前帧双线性采样。
	#endif
	#ifdef TAA_BICUBIC_PREVIOUS
		const bool bicubicPrevious = true; // 历史三次采样。
	#else
		const bool bicubicPrevious = false; // 历史双线性采样。
	#endif
	#ifdef TAA_CLIP_TO_CENTER
		const bool clipToCenter = true; // 历史朝中心拉回。
	#else
		const bool clipToCenter = false; // 按分量裁剪。
	#endif
	#ifdef TAA_DEPTH_COMPARE
		const bool depthCompare = true; // 做深度一致性判断。
	#else
		const bool depthCompare = false; // 不做深度判断。
	#endif
	#ifdef TAA_MICRO_BLUR
		const bool microBlur = true; // 低权重时做微模糊。
	#else
		const bool microBlur = false; // 不做微模糊。
	#endif
	return gfx_taa_reproject(coord, velocity, currDepthMin, colortex1, colortex7, screenSize, taaTexelCoord, gbufferProjectionInverse, far,
		taaJitter, OMNI_TAA_BLENDWEIGHT, OMNI_TAA_AGGRESSION, OMNI_TAA_DEPTH_COMPARE_THRESHOLD, bicubicCurrent, bicubicPrevious,
		clipToCenter, depthCompare, microBlur, true, referenceDepth); // 一次调用完成下界重投影。
}

// --- 参考签名兼容层：iterationT 的 TAA 取样函数直接读固定画面 ---
// 这些重载保留参考文件名与签名，内部仍走通用库的同一套取样与颜色空间转换。
// 为什么需要：参考函数不带纹理参数，宿主层必须在同一编译单元里填入 colortex1/7 与屏幕尺寸。
vec3 SampleCurrColor(vec2 coord){ return RGB_To_YCoCg(textureLod(colortex1, coord, 0.0).rgb); } // 当前帧颜色，带深度时只取 rgb。
vec3 SampleCurrColorFetch(ivec2 coord){ return RGB_To_YCoCg(texelFetch(colortex1, coord, 0).rgb); } // 当前帧颜色，整数像素取样。
vec3 SampleCurrColorBicubic(vec2 coord){ return RGB_To_YCoCg(BicubicTexture(colortex1, coord, screenSize)); } // 当前帧三次采样后的颜色。
vec4 SampleCurr(vec2 coord){ vec4 curr = textureLod(colortex1, coord, 0.0); curr.rgb = RGB_To_YCoCg(curr.rgb); curr.a = LinearDepth_From_ScreenDepth(curr.a); return curr; } // 当前帧四通道，颜色与深度都换到参考空间。
vec4 SampleCurrFetch(ivec2 coord){ vec4 curr = texelFetch(colortex1, coord, 0); curr.rgb = RGB_To_YCoCg(curr.rgb); curr.a = LinearDepth_From_ScreenDepth(curr.a); return curr; } // 当前帧四通道，整数像素。
vec4 SampleCurrBicubic(vec2 coord){ vec4 curr = ogxBicubicTexture4(colortex1, coord, screenSize); curr.rgb = RGB_To_YCoCg(curr.rgb); curr.a = LinearDepth_From_ScreenDepth(curr.a); return curr; } // 当前帧四通道三次采样。
vec3 SamplePrevColor(vec2 coord){ return RGB_To_YCoCg(BicubicTexture(colortex7, coord, screenSize)); } // 历史颜色，三次采样。
float SamplePrevDepthFetch(ivec2 coord){ return texelFetch(colortex7, coord, 0).w; } // 历史深度，主世界存在透明度通道。
vec2 SamplePrevDepthMinMax3x3(vec2 prevCoord){ // 历史深度三乘三最小与最大，供邻域裁剪。
	ivec2 nearestTexel = ivec2(prevCoord * screenSize); // 历史坐标换成整数像素。
	float depth0 = SamplePrevDepthFetch(nearestTexel + ivec2(-1, -1)); // 左上。
	float depth1 = SamplePrevDepthFetch(nearestTexel + ivec2( 0, -1)); // 上。
	float depth2 = SamplePrevDepthFetch(nearestTexel + ivec2( 1, -1)); // 右上。
	float depth3 = SamplePrevDepthFetch(nearestTexel + ivec2(-1,  0)); // 左。
	float depth4 = SamplePrevDepthFetch(nearestTexel + ivec2( 0,  0)); // 中。
	float depth5 = SamplePrevDepthFetch(nearestTexel + ivec2( 1,  0)); // 右。
	float depth6 = SamplePrevDepthFetch(nearestTexel + ivec2(-1,  1)); // 左下。
	float depth7 = SamplePrevDepthFetch(nearestTexel + ivec2( 0,  1)); // 下。
	float depth8 = SamplePrevDepthFetch(nearestTexel + ivec2( 1,  1)); // 右下。
	return vec2(min9(depth0, depth1, depth2, depth3, depth4, depth5, depth6, depth7, depth8),
		max9(depth0, depth1, depth2, depth3, depth4, depth5, depth6, depth7, depth8)); // 返回最小与最大。
}
vec2 SamplePreviousDepthBilinear(vec2 coord){ // 历史深度双线性，下界把两个参考深度打包在透明度通道。
	coord = coord * screenSize - 0.5; // 换成像素中心坐标。
	vec2 f = fract(coord); // 小数部分做双线性权重。
	ivec2 texel = ivec2(coord); // 左上角整数像素。
	vec2 s0 = Unpack2x16(texelFetch(colortex7, texel, 0).a); // 左上。
	vec2 s1 = Unpack2x16(texelFetch(colortex7, texel + ivec2(1, 0), 0).a); // 右上。
	vec2 s2 = Unpack2x16(texelFetch(colortex7, texel + ivec2(0, 1), 0).a); // 左下。
	vec2 s3 = Unpack2x16(texelFetch(colortex7, texel + ivec2(1, 1), 0).a); // 右下。
	return mix(mix(s0, s1, f.x), mix(s2, s3, f.x), f.y); // 先横向再纵向插值。
}
vec4 SamplePrevious(vec2 coord){ // 下界历史：颜色三次采样，深度双线性后换成米制参考深度。
	vec3 prevColor = RGB_To_YCoCg(BicubicTexture(colortex7, coord, screenSize)); // 历史颜色。
	float prevReferenceDepth = LinearDepth_From_ScreenDepth(SamplePreviousDepthBilinear(coord).x); // 第一个打包深度。
	return vec4(prevColor, prevReferenceDepth); // 颜色与参考深度一起返回。
}
vec3 GetVariance3x3(ivec2 coord, vec3 currColor, out vec3 avgColor, out vec3 crossAvgColor){ // 九点颜色方差。
	vec3 color0 = SampleCurrColorFetch(coord + ivec2(-1, -1)); // 左上。
	vec3 color1 = SampleCurrColorFetch(coord + ivec2( 0, -1)); // 上。
	vec3 color2 = SampleCurrColorFetch(coord + ivec2( 1, -1)); // 右上。
	vec3 color3 = SampleCurrColorFetch(coord + ivec2(-1,  0)); // 左。
	vec3 color4 = SampleCurrColorFetch(coord + ivec2( 0,  0)); // 中。
	vec3 color5 = SampleCurrColorFetch(coord + ivec2( 1,  0)); // 右。
	vec3 color6 = SampleCurrColorFetch(coord + ivec2(-1,  1)); // 左下。
	vec3 color7 = SampleCurrColorFetch(coord + ivec2( 0,  1)); // 下。
	vec3 color8 = SampleCurrColorFetch(coord + ivec2( 1,  1)); // 右下。
	crossAvgColor = color1 + color3 + color4 + color5 + color7; // 十字五点。
	avgColor = (crossAvgColor + color0 + color2 + color6 + color8) / 9.0; // 九点平均。
	crossAvgColor *= 0.2; // 十字平均。
	vec3 m2 = (color0 * color0 + color1 * color1 + color2 * color2 + color3 * color3 + color4 * color4
		+ color5 * color5 + color6 * color6 + color7 * color7 + color8 * color8) / 9.0; // 二阶矩。
	vec3 variance = sqrt(m2 - avgColor * avgColor) * OMNI_TAA_AGGRESSION; // 方差按选项放大。
	vec3 minColor = min(avgColor - variance, currColor) * 0.5; // 下界。
	vec3 maxColor = max(avgColor + variance, currColor) * 0.5; // 上界。
	avgColor = minColor + maxColor; // 平均回到两界中点。
	return maxColor - minColor; // 返回范围宽度。
}

#endif // 文件守卫结束。
