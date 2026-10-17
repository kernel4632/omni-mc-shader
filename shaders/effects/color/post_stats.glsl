/*
后期统计像素：`composite8` 程序在二号画面顶行改写三个统计像素，供下一帧的自动曝光、云影与自动对焦取用。
职责：横坐标零写自动曝光统计；四十写全局云影；六十写自动对焦深度。三个像素各自用一条分支判断，其余像素原样保留。
调用位置：`rendering/post.glsl` 的 `OMNI_COMPOSITE8_PASS` 分支先引入共享声明与曝光、雾、景深文件，再引入本文件，
    最后在 `main()` 里 `compositeOutput2 = UpdateStatPixels(texelFetch(colortex2, texelCoord, 0));` 调用。
可复制示例：`vec4 data2 = UpdateStatPixels(texelFetch(colortex2, texelCoord, 0));`（要求 `screenSize`、`colortex5` 可用）。
设计原因与取舍：这三个统计量虽然分属曝光、云影与景深，但都由二号画面顶行同一批像素承载，是一套机制，所以放同一个文件。
    自动曝光统计要有曝光文件，云影要有雾与云文件，自动对焦要有景深文件；它们都由主程序块提前引入，与原程序顺序一致。
*/
#ifndef OMNI_POST_STATS_INCLUDED // 只引入一次，避免函数重复定义。
#define OMNI_POST_STATS_INCLUDED // 置上标记，后续再次引用直接跳过。

vec4 UpdateStatPixels(vec4 data2){
	vec2 texel = floor(gl_FragCoord.xy); // 当前像素的整数坐标。

	if (texel == vec2(0.0, screenSize.y - 1.0)){ // 顶行横坐标零：自动曝光统计。
		float avgExposure = GetExposureTiles(); // 按分块平均亮度算目标曝光。
		#ifdef OMNI_SMOOTH_EXPOSURE // 开启平滑时按帧时间向前一帧过渡。
			float prevAvgExposure = data2.a; // 上一帧的曝光统计。
			float frameTimeFixed = frameTime + step(frameTime, 0.0) * 5.0; // 帧时间为零时给一个兜底值。
			float exposureTime = saturate((step(avgExposure, prevAvgExposure) * 2.0 + 1.0) * frameTimeFixed / OMNI_EXPOSURE_TIME); // 变暗比变快慢一倍。
			avgExposure = mix(prevAvgExposure, avgExposure, exposureTime); // 混合过去。
		#endif
		data2.a = avgExposure; // 写进透明通道。
	}

	#if defined OMNI_VOLUMETRIC_CLOUDS && defined OMNI_CLOUD_SHADOW // 顶行横坐标四十：全局云影。
		if (texel == vec2(40.0, screenSize.y - 1.0)){ // 只有这一个像素。
			data2.a = mix(data2.a, CloudShadowFromTex(vec3(0.0), worldShadowVector), 2.0 * frameTime); // 从云影贴图读原点的云影并按帧时间平滑。
		}
	#endif

	#if defined OMNI_DOF && OMNI_CAMERA_FOCUS_MODE == 0 // 顶行横坐标六十：自动对焦深度。
		if (texel == vec2(60.0, screenSize.y - 1.0)){ // 只有这一个像素。
			ivec2 centerTexelCoord = ivec2(screenSize * 0.5); // 屏幕中心像素。
			float prevCenterDepth = data2.a * 0.125 + 0.875; // 解码上一帧保存的中心深度。
			float centerDepth = texelFetch(depthtex0, centerTexelCoord, 0).x; // 读当前屏幕中心深度。
			#ifdef DISTANT_HORIZONS // 有远景模组时中心是远景像素就改用远景深度。
				if (centerDepth == 1.0){ // 深度为一说明近处没有几何。
					centerDepth = texelFetch(dhDepthTex0, centerTexelCoord, 0).x; // 读远景深度。
					centerDepth = ScreenDepth_From_DHScreenDepth(centerDepth); // 换到近景深度尺度。
				}
			#endif
			centerDepth = max(centerDepth, 0.875); // 近处下限，避免对焦距离趋近零。
			float f = exp2(-frameTime * 10.0 / OMNI_DOF_DEPTH_SMOOTH_HALFLIFE); // 对焦深度的平滑因子。
			float centerMaterialID = floor(texelFetch(colortex5, centerTexelCoord, 0).b * 255.0); // 中心的材质编号。
			#ifdef OMNI_DOF_FOCUS_IGNORE_HAND_PARTICLE // 中心是手或粒子时不动焦点。
				if (heldItemId != 358.0 && centerMaterialID == MATID_HAND || centerMaterialID == MATID_PARTICLE) f = 1.0; // 直接用上一帧深度。
			#endif
			data2.a = saturate(mix(centerDepth, prevCenterDepth, f) * 8.0 - 7.0); // 编码后写进透明通道。
		}
	#endif

	return data2; // 其余像素原样保留。
}
#endif // 文件守卫结束。
