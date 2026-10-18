/*
反射阴影图全局光：从阴影图里可见表面反弹补光，并做时间滤波与空间滤波抑制噪点。
来源 iterationT 全局光系列。
调用位置：由 `effects/lighting/ambient.glsl` 引入；延迟一号（主世界）/ 延迟二号（末地）做时间滤波，
    延迟二号（主世界）/ 延迟四号（末地）做空间滤波，整段只在这些程序里编译。
可复制示例：
    `vec4 gi = GI_TemporalFilter();`
    `vec3 filtered = GI_SpatialFilter(dist, normal, viewDir);`
设计原因与取舍：全局光的时间滤波与空间滤波共享采样约定与历史数据，放同一文件；
    地平线遮蔽是另一套算法、另有开关，拆到 `effects/lighting/gtao.glsl`。
*/
#ifndef OMNI_GI_INCLUDED
#define OMNI_GI_INCLUDED // 置上标记，后续再次引用直接跳过。
#ifdef OMNI_GI_RSM // 只有打开全局光才需要下面的函数。
// --- 反射阴影图反弹与全局光时间滤波：主世界在延迟一号、末地在延迟二号 ---
#if (defined OMNI_DEFERRED1_PASS && !defined OMNI_END) || (defined OMNI_END && defined OMNI_DEFERRED2_PASS) // 主世界在延迟一号、末地在延迟二号做反射阴影图与时间滤波。
// 反射阴影图反弹：从阴影图里可见的表面取光照与底色，按法线朝向和距离估计给当前点补一份光。
vec3 RSM(vec3 viewPos, vec3 normal){
	vec3 worldPos = mat3(gbufferModelViewInverse) * viewPos + gbufferModelViewInverse[3].xyz; // 视空间位置换到世界空间。
	vec3 shadowPosition = ShadowScreenPos_From_WorldPos_WithoutZScaling(worldPos); // 世界位置投到阴影图坐标。
	#ifdef OMNI_END // 末地用末地版阴影相机。
		vec3 shadowNormal = mat3(shadowModelViewEnd) * mat3(gbufferModelViewInverse) * normal; // 法线转到末地阴影相机空间。
	#else // 主世界与下界用主阴影相机。
		vec3 shadowNormal = mat3(shadowModelView) * mat3(gbufferModelViewInverse) * normal; // 法线转到阴影相机空间。
	#endif
	float pixelOffset = OMNI_GI_RADIUS * shadowProjection[0][0]; // 搜索半径换成阴影图像素。
	float zScale = 1.0 / shadowProjection[0][0]; // 阴影深度的缩放系数。
	vec2 noise = BlueNoiseTemporal(); // 每帧变化的蓝噪声，用来抖动采样方向。
	const mat2 rotMat = mat2(cos(goldenAngle), sin(goldenAngle), -sin(goldenAngle), cos(goldenAngle)); // 螺旋采样旋转矩阵。
	float angle = noise.x * TAU; // 起始旋转角。
	vec2 rot = vec2(cos(angle), sin(angle)); // 起始方向。
	const float steps = OMNI_GI_QUALITY; // 采样次数。
	const float rSteps = 1.0 / steps; // 采样次数倒数。
	vec3 rsm = vec3(0.0); // 累积的反弹颜色。
	for (float i = 0.0; i < steps; i++){ // 螺旋逐点采样。
		rot *= rotMat; // 每步旋转一点。
		float r = (i + noise.y) * rSteps; // 归一化半径。
		vec2 offset = rot * r * pixelOffset; // 屏幕偏移。
		vec2 offsetPosition = shadowPosition.xy + offset; // 采样点的阴影图坐标。
		vec2 sampleCoord = DistortShadowScreenPos(offsetPosition); // 还原畸变后的坐标。
		ivec2 sampleTexelcoord = ivec2(shadowMapResolution * sampleCoord); // 换成纹素。
		#ifdef MC_GL_VENDOR_NVIDIA // 英伟达用一号阴影深度。
			float sampleDepth = texelFetch(shadowtex1, sampleTexelcoord, 0).x; // 读一号深度。
		#else // 其他显卡用零号阴影深度。
			float sampleDepth = texelFetch(shadowtex0, sampleTexelcoord, 0).x; // 读零号深度。
		#endif
		if (sampleDepth == 0.0 || sampleDepth >= 1.0) continue; // 没有几何或超出范围就跳过。
		vec3 sampleVector = vec3(offsetPosition, sampleDepth) - shadowPosition; // 采样点相对当前点。
		sampleVector *= vec3(zScale, zScale, -zScale * 2.0); // 修正到统一的深度尺度。
		vec3 sampleDir = normalize(sampleVector); // 采样方向。
		float NdotV = dot(sampleDir, shadowNormal); // 当前点法线与采样方向的夹角余弦。
		if (NdotV <= 0.0) continue; // 背对采样点不接收。
		vec4 sampleData = texelFetch(shadowcolor1, sampleTexelcoord, 0); // 读阴影图里的法线与天光。
		vec3 sampleNormal = sampleData.rgb * 2.0 - 1.0; // 还原采样点法线。
		float SNdotV = dot(-sampleDir, sampleNormal) * 1.004 - 0.004; // 采样点法线与入射方向的夹角余弦，留一点余量。
		if (SNdotV < 0.0) continue; // 背对方向不发光。
		vec3 sampleAlbedo = GammaToLinear(texelFetch(shadowcolor0, sampleTexelcoord, 0).rgb); // 采样点底色转线性。
		sampleVector.z *= 1.5; // 深度方向加权，避免细长表面贡献过大。
		float sampleDist = length(sampleVector); // 采样距离。
		float distFalloff = pow(sampleDist + 0.035, -OMNI_GI_FALLOFF) * fsqrt(1.0 - r); // 距离衰减与中心加权。
		#if defined OMNI_SUNLIGHT_LEAK_FIX && !defined OMNI_END // 主世界做阳光泄漏修正。
			float mcLightingMask = saturate(sampleData.a * 15.0 + float(isEyeInWater == 1)); // 只有接到天光或在水里才补光。
			rsm += sampleAlbedo * (NdotV * SNdotV * distFalloff * mcLightingMask); // 加一份受遮挡限制的反弹。
		#else // 末地或关闭修正时不做遮罩。
			rsm += sampleAlbedo * (NdotV * SNdotV * distFalloff); // 直接累加反弹。
		#endif
	}
	rsm *= rSteps * OMNI_GI_RADIUS * 0.1; // 平均并按半径缩放。
	return rsm; // 返回反弹颜色。
}
#ifdef DISTANT_HORIZONS // 有远景模组时相机速度要区分远景。
// 算这个像素相对上一帧的屏幕位移；远景像素用远景矩阵，近景像素用普通矩阵。
vec2 GiCameraVelocity(vec2 coord, float depth, bool isDH){
	vec3 screenPos = vec3(coord, depth); // 屏幕坐标加深度。
	vec3 projection = vec3(screenPos * 2.0 - 1.0); // 换到负一到一。
	if (isDH){ // 远景像素。
		projection = (vec3(vec2(dhProjectionInverse[0].x, dhProjectionInverse[1].y) * projection.xy, 0.0) + dhProjectionInverse[3].xyz) / (dhProjectionInverse[2].w * projection.z + dhProjectionInverse[3].w); // 远景逆投影到视空间。
		projection = mat3(gbufferModelViewInverse) * projection + gbufferModelViewInverse[3].xyz; // 视空间转世界。
		projection += cameraPosition - previousCameraPosition; // 加上相机的世界位移。
		projection = mat3(gbufferPreviousModelView) * projection + gbufferPreviousModelView[3].xyz; // 世界转上一帧视空间。
	}else{ // 近景像素。
		projection = (vec3(vec2(gbufferProjectionInverse[0].x, gbufferProjectionInverse[1].y) * projection.xy, 0.0) + gbufferProjectionInverse[3].xyz) / (gbufferProjectionInverse[2].w * projection.z + gbufferProjectionInverse[3].w); // 近景逆投影到视空间。
		#if defined OMNI_DISABLE_HAND_GI_VELOCITY && defined OMNI_DISABLE_PLAYER_GI_VELOCITY // 手和玩家都不参与重投影。
			float materialIDs = floor(texelFetch(colortex5, ivec2(floor(coord * screenSize)), 0).b * 255.0); // 读材质编号。
			if (depth >= 0.7 && materialIDs != MATID_ENTITIES_PLAYER){ // 非玩家且较远的像素。
				projection = mat3(gbufferModelViewInverse) * projection + gbufferModelViewInverse[3].xyz; // 视空间转世界。
				projection += cameraPosition - previousCameraPosition; // 加相机位移。
				projection = mat3(gbufferPreviousModelView) * projection + gbufferPreviousModelView[3].xyz; // 转上一帧视空间。
			}
		#elif defined OMNI_DISABLE_HAND_GI_VELOCITY // 只有手不参与。
			if (depth >= 0.7){ // 较远的像素才重投影。
				projection = mat3(gbufferModelViewInverse) * projection + gbufferModelViewInverse[3].xyz; // 视空间转世界。
				projection += cameraPosition - previousCameraPosition; // 加相机位移。
				projection = mat3(gbufferPreviousModelView) * projection + gbufferPreviousModelView[3].xyz; // 转上一帧视空间。
			}
		#elif defined OMNI_DISABLE_PLAYER_GI_VELOCITY // 只有玩家不参与。
			float materialIDs = floor(texelFetch(colortex5, ivec2(floor(coord * screenSize)), 0).b * 255.0); // 读材质编号。
			if (materialIDs != MATID_ENTITIES_PLAYER){ // 非玩家像素。
				if (depth < 0.7){ // 手部像素只加一个固定位移。
					projection += (gbufferPreviousModelView[3].xyz - gbufferModelView[3].xyz) * MC_HAND_DEPTH; // 手部固定深度偏移。
				}else{ // 其他近景像素正常重投影。
					projection = mat3(gbufferModelViewInverse) * projection + gbufferModelViewInverse[3].xyz; // 视空间转世界。
					projection += cameraPosition - previousCameraPosition; // 加相机位移。
					projection = mat3(gbufferPreviousModelView) * projection + gbufferPreviousModelView[3].xyz; // 转上一帧视空间。
				}
			}
		#else // 都参与重投影。
			if (depth < 0.7){ // 手部像素只加一个固定位移。
				projection += (gbufferPreviousModelView[3].xyz - gbufferModelView[3].xyz) * MC_HAND_DEPTH; // 手部固定深度偏移。
			}else{ // 其他近景像素正常重投影。
				projection = mat3(gbufferModelViewInverse) * projection + gbufferModelViewInverse[3].xyz; // 视空间转世界。
				projection += cameraPosition - previousCameraPosition; // 加相机位移。
				projection = mat3(gbufferPreviousModelView) * projection + gbufferPreviousModelView[3].xyz; // 转上一帧视空间。
			}
		#endif
	}
	projection = (vec3(gbufferPreviousProjection[0].x, gbufferPreviousProjection[1].y, gbufferPreviousProjection[2].z) * projection + gbufferPreviousProjection[3].xyz) / -projection.z * 0.5 + 0.5; // 投回上一帧屏幕坐标。
	return coord - projection.xy; // 返回屏幕位移。
}
#else // 没有远景模组时的简化版。
// 算这个像素相对上一帧的屏幕位移，不需要区分远景。
vec2 GiCameraVelocity(vec2 coord, float depth){
	vec3 projection = vec3(coord, depth) * 2.0 - 1.0; // 屏幕坐标换到负一到一。
	projection = (vec3(vec2(gbufferProjectionInverse[0].x, gbufferProjectionInverse[1].y) * projection.xy, 0.0) + gbufferProjectionInverse[3].xyz) / (gbufferProjectionInverse[2].w * projection.z + gbufferProjectionInverse[3].w); // 逆投影到视空间。
	#if defined OMNI_DISABLE_HAND_GI_VELOCITY && defined OMNI_DISABLE_PLAYER_GI_VELOCITY // 手和玩家都不参与。
		float materialIDs = floor(texelFetch(colortex5, ivec2(floor(coord * screenSize)), 0).b * 255.0); // 读材质编号。
		if (depth >= 0.7 && materialIDs != MATID_ENTITIES_PLAYER){ // 非玩家且较远。
			projection = mat3(gbufferModelViewInverse) * projection + gbufferModelViewInverse[3].xyz; // 视空间转世界。
			projection += cameraPosition - previousCameraPosition; // 加相机位移。
			projection = mat3(gbufferPreviousModelView) * projection + gbufferPreviousModelView[3].xyz; // 转上一帧视空间。
		}
	#elif defined OMNI_DISABLE_HAND_GI_VELOCITY // 只有手不参与。
		if (depth >= 0.7){ // 较远像素才重投影。
			projection = mat3(gbufferModelViewInverse) * projection + gbufferModelViewInverse[3].xyz; // 视空间转世界。
			projection += cameraPosition - previousCameraPosition; // 加相机位移。
			projection = mat3(gbufferPreviousModelView) * projection + gbufferPreviousModelView[3].xyz; // 转上一帧视空间。
		}
	#elif defined OMNI_DISABLE_PLAYER_GI_VELOCITY // 只有玩家不参与。
		float materialIDs = floor(texelFetch(colortex5, ivec2(floor(coord * screenSize)), 0).b * 255.0); // 读材质编号。
		if (materialIDs != MATID_ENTITIES_PLAYER){ // 非玩家像素。
			if (depth < 0.7){ // 手部像素固定位移。
				projection += (gbufferPreviousModelView[3].xyz - gbufferModelView[3].xyz) * MC_HAND_DEPTH; // 手部固定深度偏移。
			}else{ // 其他像素正常重投影。
				projection = mat3(gbufferModelViewInverse) * projection + gbufferModelViewInverse[3].xyz; // 视空间转世界。
				projection += cameraPosition - previousCameraPosition; // 加相机位移。
				projection = mat3(gbufferPreviousModelView) * projection + gbufferPreviousModelView[3].xyz; // 转上一帧视空间。
			}
		}
	#else // 都参与。
		if (depth < 0.7){ // 手部像素固定位移。
			projection += (gbufferPreviousModelView[3].xyz - gbufferModelView[3].xyz) * MC_HAND_DEPTH; // 手部固定深度偏移。
		}else{ // 其他像素正常重投影。
			projection = mat3(gbufferModelViewInverse) * projection + gbufferModelViewInverse[3].xyz; // 视空间转世界。
			projection += cameraPosition - previousCameraPosition; // 加相机位移。
			projection = mat3(gbufferPreviousModelView) * projection + gbufferPreviousModelView[3].xyz; // 转上一帧视空间。
		}
	#endif
	projection = (vec3(gbufferPreviousProjection[0].x, gbufferPreviousProjection[1].y, gbufferPreviousProjection[2].z) * projection + gbufferPreviousProjection[3].xyz) / -projection.z * 0.5 + 0.5; // 投回上一帧屏幕坐标。
	return coord - projection.xy; // 返回屏幕位移。
}
#endif
// 上一帧全局光的四像素双线性插值：按法线与深度给每个历史像素加权，取回历史反弹颜色。
// 输入是本帧法线、本帧到相机距离、相机速度与上一帧纹素坐标；`out weightSum` 回传权重和供调用方混合。
// 为什么用一个循环枚举四个纹素：原来嵌套两层循环把滤波深度堆高，这里用下标拼出四个角，读数一样但更平。
vec3 GiHistorySample(vec3 currNormal, float currDist, vec3 cameraVelocity, vec2 prevCoord, out float weightSum){
	vec2 prevTexel = floor(prevCoord); // 历史纹素整数部分。
	vec3 prevGi = vec3(0.0); // 累积的历史反弹。
	weightSum = 0.0; // 权重和。

	for (int k = 0; k < 4; k++){ // 左下、右下、左上、右上四个历史纹素。
		vec2 sampleTexelcoord = prevTexel + vec2(float(k >> 1), float(k & 1)); // 按下标拼出四个角的偏移。
		vec4 prevData = texelFetch(colortex2, ivec2(sampleTexelcoord.x + OMNI_GI_RENDER_RESOLUTION * screenSize.x, sampleTexelcoord.y), 0); // 读历史法线深度。
		vec3 prevNormal = prevData.xyz * 2.0 - 1.0; // 还原历史法线。
		float normalWeight = float(dot(currNormal, prevNormal) > 0.5); // 法线相近才参与。
		float prevDist = prevData.a * 1000.0; // 历史距离。
		float depthWeight = max(abs(currDist - prevDist - cameraVelocity.z), 0.0); // 距离差。
		depthWeight = exp(-depthWeight / (currDist * 0.1 + 0.1)); // 差距越大权重越低。
		depthWeight = saturate(depthWeight * 2.0); // 放大后再收敛。
		float bilinearWeight = (1.0 - abs(prevCoord.x - sampleTexelcoord.x)) * (1.0 - abs(prevCoord.y - sampleTexelcoord.y)); // 双线性权重。
		bilinearWeight *= normalWeight * depthWeight; // 总权重。
		prevGi += CurveToLinear(texelFetch(colortex2, ivec2(sampleTexelcoord), 0).rgb) * bilinearWeight; // 累加解码后的历史反弹。
		weightSum += bilinearWeight; // 累加权重。
	}

	return prevGi; // 返回加权历史反弹（未归一化，调用方按权重和混合）。
}

// 全局光时间滤波：把本帧反射阴影图与历史帧按法线和深度做双向插值，抑制闪烁。
vec4 GI_TemporalFilter(){
	vec4 prev = texelFetch(colortex2, texelCoord, 0); // 先取历史像素。
	vec2 coord = texCoord / OMNI_GI_RENDER_RESOLUTION; // 全局光渲染分辨率下的坐标。
	if (saturate(coord) == coord){ // 只在有效范围内处理。
		ivec2 texel = ivec2(coord * screenSize); // 对应的屏幕纹素。
		float currDepth = texelFetch(depthtex1, texel, 0).x; // 本帧不透明深度。
		#ifdef DISTANT_HORIZONS // 有远景时天空像素改读远景深度。
			bool isDH = false; // 标记是否远景像素。
			#ifdef OMNI_DH_AO // 只有开启远景遮蔽才把远景当作有几何，关闭时远景像素按天空处理。
				if (currDepth == 1.0){ // 天空像素。
					currDepth = texelFetch(dhDepthTex0, texel, 0).x; // 改读远景深度。
					isDH = true; // 标记为远景。
				}
			#endif
		#endif
		if (currDepth < 1.0){ // 有几何才算反弹。
			vec4 data3 = texelFetch(colortex3, texel, 0); // 读法线光照图。
			vec3 currNormal = DecodeNormal(data3.xy); // 解出本帧法线。
			vec3 currViewPos = ViewPos_From_ScreenPos_Raw(coord, currDepth); // 还原视空间位置。
			#ifdef DISTANT_HORIZONS // 远景像素用远景还原。
				if (isDH) currViewPos = ViewPos_From_ScreenPos_Raw_DH(coord, currDepth); // 远景还原。
			#endif
			vec3 gi = vec3(0.0); // 本帧反弹。
			// 先把“这一点是否要做反弹”算成一个布尔量，再把反弹放在一整条 if 里，避免条件被预处理指令切成分开的几段。
			#if MC_VERSION >= 11605 // 新版本按天光标记决定是否反弹。
				#if defined OMNI_SUNLIGHT_LEAK_FIX && !defined OMNI_END // 主世界做泄漏修正。
					bool applyRSM = data3.w > 0.0 || isEyeInWater == 1; // 只有接到天光或在水里才反弹。
				#else // 末地或关闭修正。
					bool applyRSM = true; // 没有额外条件，总是反弹。
				#endif
			#else // 旧版本还要求像素足够远。
				#if defined OMNI_SUNLIGHT_LEAK_FIX && !defined OMNI_END // 主世界做泄漏修正。
					bool applyRSM = currDepth > 0.7 && (data3.w > 0.0 || isEyeInWater == 1); // 较远且接到天光。
				#else // 末地或关闭修正。
					bool applyRSM = currDepth > 0.7; // 只要求较远。
				#endif
			#endif
			if (applyRSM) gi = RSM(currViewPos, currNormal); // 满足条件才算一次反弹。
			#ifdef DISTANT_HORIZONS // 手机上算屏幕位移。
				vec2 velocity = GiCameraVelocity(coord, currDepth, isDH); // 远景版位移。
			#else // 近景版位移。
				vec2 velocity = GiCameraVelocity(coord, currDepth); // 近景版位移。
			#endif
			vec2 pcoord = coord - velocity; // 映射到上一帧坐标。
			vec2 prevCoord = clamp(pcoord, vec2(0.0), vec2(1.0) - pixelSize * 2.0); // 夹到画面内。
			if (prevCoord == pcoord){ // 历史坐标有效才做滤波。
				vec2 prevTexelCoord = prevCoord * OMNI_GI_RENDER_RESOLUTION * screenSize - 0.5; // 换成历史纹素坐标。
				float currDist = min(-currViewPos.z, 1000.0); // 本帧到相机的距离，限长避免远处权重异常。
				vec3 cameraVelocity = mat3(gbufferModelView) * (cameraPosition - previousCameraPosition); // 相机速度转到视空间。
				float weightSum = 0.0; // 权重和。
				vec3 prevGi = GiHistorySample(currNormal, currDist, cameraVelocity, prevTexelCoord, weightSum); // 取上一帧加权历史反弹。
				gi = mix(gi, prevGi, 0.95 * weightSum); // 与历史混合。
			}
			prev = vec4(LinearToCurve(gi), 0.0); // 编码回历史格式。
		}
	}
	coord.x -= 1.0; // 顶行左侧一格存法线与距离。
	if (saturate(coord) == coord){ // 只在有效范围内处理。
		ivec2 texel = ivec2(floor(coord * screenSize)); // 对应的屏幕纹素。
		float depth = texelFetch(depthtex1, texel, 0).x; // 不透明深度。
		#ifdef DISTANT_HORIZONS // 远景处理。
			bool isDH = false; // 远景标记。
			#ifdef OMNI_DH_AO // 只有开启远景遮蔽才把远景当作有几何。
				if (depth == 1.0){ // 天空像素。
					depth = texelFetch(dhDepthTex0, texel, 0).x; // 改读远景深度。
					isDH = true; // 标记远景。
				}
			#endif
		#endif
		if (depth < 1.0){ // 有几何才写历史数据。
			vec3 normal = DecodeNormal(texelFetch(colortex3, texel, 0).xy); // 解法线。
			float dist = LinearDepth_From_ScreenDepth(depth); // 深度换米制距离。
			#ifdef DISTANT_HORIZONS // 远景像素用远景换算。
				if(isDH) dist = LinearDepth_From_ScreenDepth_DH(depth); // 远景换算。
			#endif
			prev = vec4(normal * 0.5 + 0.5, dist * 0.001); // 法线压到零到一，距离缩小存进透明通道。
		}else{ // 天空像素没有有效历史。
			prev = vec4(vec3(0.5), 0.0); // 写入中性值。
		}
	}
	return prev; // 返回本帧要写回二号画面的数据。
}
#endif // 延迟一号结束。
// --- 全局光空间滤波：主世界在延迟二号、末地在延迟四号 ---
#if (defined OMNI_DEFERRED2_PASS && !defined OMNI_END) || (defined OMNI_END && defined OMNI_DEFERRED4_PASS) // 主世界在延迟二号、末地在延迟四号做全局光空间滤波。
// 全局光空间滤波：在七乘七邻域里按法线与深度加权平均，抑制半分辨率带来的噪点。
vec3 GI_SpatialFilter(float dist, vec3 normal, vec3 viewDir){
	const vec2 offset[49] = vec2[49]( // 七乘七邻域偏移表。
	vec2(-3.0, -3.0), vec2(-2.0, -3.0), vec2(-1.0, -3.0), vec2(0.0, -3.0), vec2(1.0, -3.0), vec2(2.0, -3.0), vec2(3.0, -3.0),
	vec2(-3.0, -2.0), vec2(-2.0, -2.0), vec2(-1.0, -2.0), vec2(0.0, -2.0), vec2(1.0, -2.0), vec2(2.0, -2.0), vec2(3.0, -2.0),
	vec2(-3.0, -1.0), vec2(-2.0, -1.0), vec2(-1.0, -1.0), vec2(0.0, -1.0), vec2(1.0, -1.0), vec2(2.0, -1.0), vec2(3.0, -1.0),
	vec2(-3.0,  0.0), vec2(-2.0,  0.0), vec2(-1.0,  0.0), vec2(0.0,  0.0), vec2(1.0,  0.0), vec2(2.0,  0.0), vec2(3.0,  0.0),
	vec2(-3.0,  1.0), vec2(-2.0,  1.0), vec2(-1.0,  1.0), vec2(0.0,  1.0), vec2(1.0,  1.0), vec2(2.0,  1.0), vec2(3.0,  1.0),
	vec2(-3.0,  2.0), vec2(-2.0,  2.0), vec2(-1.0,  2.0), vec2(0.0,  2.0), vec2(1.0,  2.0), vec2(2.0,  2.0), vec2(3.0,  2.0),
	vec2(-3.0,  3.0), vec2(-2.0,  3.0), vec2(-1.0,  3.0), vec2(0.0,  3.0), vec2(1.0,  3.0), vec2(2.0,  3.0), vec2(3.0,  3.0));
	vec2 coord = texCoord * OMNI_GI_RENDER_RESOLUTION; // 全局光分辨率下的坐标。
	float weights = 0.0; // 权重和。
	vec3 gi = vec3(0.0); // 累积的反弹颜色。
	float clampedDist = min(dist, 1000.0); // 距离限长。
	float b = clampedDist * 0.001 + 0.025; // 深度阈值里的中间量。
	float depthThreshold = min(0.1 + clampedDist * 0.05, 1.1) + saturate(1.0 - abs(dot(normal, viewDir)) / b) * 10.0; // 掠射角放宽深度阈值。
	vec2 border = vec2(OMNI_GI_RENDER_RESOLUTION) - pixelSize * 2.0; // 边界。
	vec2 offsetScale = pixelSize * 4.0 * OMNI_GI_RENDER_RESOLUTION; // 邻域步长。
	for (int i = 0; i < 49; i++){ // 遍历四十九个邻点。
		vec2 sampleCoord = coord + offset[i] * offsetScale; // 采样坐标。
		sampleCoord = clamp(sampleCoord, vec2(0.0), border); // 夹到有效范围。
		float weight = length(offset[i]); // 按到中心的距离算权重。
	  	weight = exp2(-weight * weight * 0.1); // 高斯权重。
		vec4 sampleData = textureLod(colortex2, sampleCoord + vec2(OMNI_GI_RENDER_RESOLUTION, 0.0), 0.0); // 读历史法线深度。
		vec3 sampleNormal = sampleData.xyz * 2.0 - 1.0; // 还原法线。
		float normalWeight = abs(dot(normal, sampleNormal)); // 法线相近度。
		normalWeight = pow(normalWeight, 64.0); // 高次方只保留很接近的。
		float depthWeight = saturate(-abs(sampleData.w * 1000.0 - clampedDist) + depthThreshold); // 深度相近度。
		weight = weight * normalWeight * depthWeight + 1e-20; // 总权重，加极小值避免全零。
		gi += CurveToLinear(textureLod(colortex2, sampleCoord, 0.0).rgb) * weight; // 累加解码后的反弹。
		weights += weight; // 累加权重。
	}
	gi /= weights; // 平均。
	return LinearToCurve(gi); // 编码后返回。
}
#endif // 延迟二号结束。
#endif // 全局光结束。
#endif // 文件守卫结束。
