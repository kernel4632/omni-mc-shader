/*
云影贴图与模糊：把地表坐标沿光方向投到云层取云密度得到云影，并对云影贴图做三次模糊与横纵两次高斯模糊。
来源 iterationT `CloudShadow.glsl`。
调用位置：由 `effects/cloud/cloud.glsl` 引入；延迟四号、五号调用 `CloudShadowAxialBlur` 做横向、纵向模糊，
    合成阶段调用 `CloudShadowFromTex`、`GetSmoothCloudShadow`。
可复制示例：
    `float shadow = CloudShadowFromTex(worldPos, worldShadowVector);`
    `vec4 blurred = CloudShadowAxialBlur(texelCoord, ivec2(1, 0));`
调用前提：中间画面 `colortex2`、屏幕尺寸与湿度由绘制主体与加载器提供；云影范围、贴图尺寸与雨天阴影选项由 `effects/cloud/cloud.glsl` 定义。
设计原因与取舍：这些函数不依赖三维云密度，所以不随云密度阶段一起关闭，任何引入云的程序都能编译；
    原程序横纵两个程序各写一份、只差采样轴，按合同合并成一个 `CloudShadowAxialBlur`，用轴参数区分。
*/
#ifndef OMNI_CLOUD_SHADOW_INCLUDED
#define OMNI_CLOUD_SHADOW_INCLUDED
// --- 云影三次采样：与共用数学里的同名函数返回类型和参数都不同，按合同留在云影这里一份 ---
// 读一张二维纹理的十六像素三次模糊，返回第一个通道，`texSize` 是纹理尺寸。
float CloudBicubicBlurTexture(sampler2D texSampler, vec2 coord, vec2 texSize){
	vec2 texPixelSize = 1.0 / texSize; // 一个像素的坐标大小。
	coord = coord * texSize - 0.5; // 换成以像素为单位的坐标。
	vec2 p = floor(coord); // 整数像素。
	vec2 f = coord - p; // 小数偏移。
	vec2 ff = f * f; // 偏移平方。
	vec4 w0; // 两个方向的前两个权重。
	vec4 w1; // 两个方向的后两个权重。
	w0.xz = 1.0 - f; w0.xz *= w0.xz * w0.xz; // 第一个权重是反向偏移的立方。
	w1.yw = ff * f; // 第四个权重是偏移立方。
	w1.xz = 3.0 * w1.yw + 4.0 - 6.0 * ff; // 第三个权重。
	w0.yw = 6.0 - w1.xz - w1.yw - w0.xz; // 第二个权重由总和为六推出。
	vec4 s = w0 + w1; // 每对权重和。
	vec4 c = p.xxyy + vec2(-0.5, 1.5).xyxy + w1 / s; // 每对合并成一次双线性采样的位置。
	c *= texPixelSize.xxyy; // 换回零到一坐标。
	vec2 m = s.xz / (s.xz + s.yw); // 两次采样之间的混合比例。
	return mix(mix(textureLod(texSampler, c.yw, 0.0).x, textureLod(texSampler, c.xw, 0.0).x, m.x),
			   mix(textureLod(texSampler, c.yz, 0.0).x, textureLod(texSampler, c.xz, 0.0).x, m.x),
			   m.y); // 四次双线性采样得到十六像素的三次模糊，取红通道。
}
// 云影贴图取值：把世界坐标投到云影贴图，采样后按天气在晴天与雨天两档之间混合。
// 调用前提：全局量 `worldShadowVector` 已声明，云影贴在二号画面右上角。
float CloudShadowFromTex(vec3 worldPos, vec3 shadowLightVector){
	#ifdef NO_COMPOSITE_VS // 没有合成顶点阶段时退回按阴影相机方向投影。
		vec3 worldShadowVector = shadowModelViewInverse[2].xyz; // 用阴影相机视线方向作为光方向。
	#endif
	vec2 coord = worldPos.xz - shadowLightVector.xz * ((worldPos.y + cameraPosition.y) / shadowLightVector.y); // 沿光方向投到云影贴图平面。
	coord = coord * (1.0 / OMNI_CLOUD_SHADOW_RANGE) + 0.5; // 换成零到一的贴图坐标。
	float cloudShadow = 1.0 - wetness; // 雨天默认的云影底值。
	if (saturate(coord) == coord){ // 只有落在贴图范围内才采样。
		float shadowTexSize = floor(min(screenSize.y * 0.45, OMNI_CLOUD_SHADOWTEX_SIZE)); // 云影贴图实际边长。
		vec2 shadowTexel = screenSize - coord * shadowTexSize; // 贴图贴在画面右上角，坐标要翻转。
		vec2 fade = saturate(5.9 - abs(coord - 0.5) * 12.0); // 贴图边缘淡出，避免硬边界。
		cloudShadow = mix(cloudShadow, CloudBicubicBlurTexture(colortex2, shadowTexel * pixelSize, screenSize), fade.x * fade.y); // 三次采样并淡出。
	}
	#if OMNI_CLOUD_SHADOW_FADE // 打开淡出时，太阳越贴地云影越淡。
		float fadeAngle = smoothstep(0.06, 0.18, abs(shadowLightVector.y)); // 光方向越平越淡。
		cloudShadow = mix(1.0 - wetness, cloudShadow, fadeAngle * fadeAngle); // 按淡出权重混合。
	#endif
	return ((OMNI_RAIN_SHADOW - 1.0) * wetness + 1.0) * cloudShadow + (wetness - OMNI_RAIN_SHADOW * wetness); // 晴天与雨天两档之间插值。
}
// 全局云影：给整个场景用的一个粗粒度云影值，来自二号画面顶行的统计像素。
float GetSmoothCloudShadow(){
	#if defined OMNI_VOLUMETRIC_CLOUDS && defined OMNI_CLOUD_SHADOW // 有体积云和云影时读统计像素。
		float globalCloudShadow = mix(texelFetch(colortex2, ivec2(40, screenSize.y - 1.0), 0).a, 1.0, 0.03 - wetness * 0.015); // 顶行四十号像素存全局云影。
	#else // 否则用纯天气估一个值。
		float globalCloudShadow = 1.0 - wetness * (OMNI_RAIN_SHADOW * 0.985); // 雨天按雨天阴影压暗。
	#endif
	return globalCloudShadow; // 返回全局云影。
}
// 云影三次采样：原程序横纵两个程序各写一份只差采样轴，按合同合并成一个函数，名字加云影前缀。
// 调用前提：`colortex2` 与 `screenSize` 已声明；`axis` 取值横向 `(1,0)` 或纵向 `(0,1)`。
vec4 CloudShadowAxialBlur(ivec2 texelCoord, ivec2 axis){
	ivec4 shadowTexBorder = ivec4(screenSize - floor(min(screenSize.y * 0.45, OMNI_CLOUD_SHADOWTEX_SIZE)), screenSize - 1.0); // 云影贴图的边界，采样要夹在里面。
	vec4 blur = vec4(0.0); // 模糊结果。
	ivec2 sampleCoord = clamp(texelCoord - 3 * axis, shadowTexBorder.xy, shadowTexBorder.zw); // 第三个负向样本。
	blur.r += texelFetch(colortex2, sampleCoord, 0).r * 0.054543; // 按高斯权重累加。
	sampleCoord = clamp(texelCoord - 2 * axis, shadowTexBorder.xy, shadowTexBorder.zw); // 第二个负向样本。
	blur.r += texelFetch(colortex2, sampleCoord, 0).r * 0.099384; // 累加。
	sampleCoord = clamp(texelCoord - 1 * axis, shadowTexBorder.xy, shadowTexBorder.zw); // 第一个负向样本。
	blur.r += texelFetch(colortex2, sampleCoord, 0).r * 0.181090; // 累加。
	vec4 data2 = texelFetch(colortex2, texelCoord, 0); // 中心样本。
	blur.r += data2.r * 0.329966; // 中心权重最大。
	blur.gba += data2.gba; // 其余通道原样带过。
	sampleCoord = clamp(texelCoord + 1 * axis, shadowTexBorder.xy, shadowTexBorder.zw); // 第一个正向样本。
	blur.r += texelFetch(colortex2, sampleCoord, 0).r * 0.181090; // 累加。
	sampleCoord = clamp(texelCoord + 2 * axis, shadowTexBorder.xy, shadowTexBorder.zw); // 第二个正向样本。
	blur.r += texelFetch(colortex2, sampleCoord, 0).r * 0.099384; // 累加。
	sampleCoord = clamp(texelCoord + 3 * axis, shadowTexBorder.xy, shadowTexBorder.zw); // 第三个正向样本。
	blur.r += texelFetch(colortex2, sampleCoord, 0).r * 0.054543; // 累加。
	return blur; // 返回模糊后的云影贴图。
}
#endif // 文件守卫结束。
