/*
屏幕空间阴影：在屏幕里沿阳光方向找遮挡，补阴影图覆盖不到的近处细节。
来源 iterationT 阴影图之外的屏幕空间补充段。
调用位置：由 `effects/shadow/shadow.glsl` 引入；需要细碎阴影的程序调用 `ScreenSpaceShadow`。
可复制示例：`float shadow = ScreenSpaceShadow(viewPos, viewDir, normal, mask, shadowVector);`
设计原因与取舍：屏幕空间阴影是阴影图之外的补充手段，和阴影图坐标、可变半影分开成文件，便于按算法定位；阈值与抖动照 iterationT 原样。
*/
#ifndef OMNI_SCREEN_SHADOW_INCLUDED
#define OMNI_SCREEN_SHADOW_INCLUDED // 置上标记，后续再次引用直接跳过。
// --- 屏幕空间阴影：在屏幕里沿阳光方向找遮挡，补阴影图覆盖不到的近处细节 ---
// 输入是视空间位置、视线方向与视空间法线；沿阳光在屏幕上的投影方向步进，撞到比当前更近的几何就累加遮挡。
// 为什么叶片先用饱和放大：叶片的材质编号可能带小数，先归一到零或一，后面的取舍才稳定。
float ScreenSpaceShadow(vec3 viewPos, vec3 viewDir, vec3 normal, MaterialMask mask, vec3 shadowVector){
	mask.leaves = saturate(mask.leaves * 1e10); // 把叶片标记归一到零或一。

	float fov = mask.grass + mask.leaves > 0.5 ? 95.0 : atan(1.0 / gbufferProjection[1][1]) * 360.0 * rPI; // 草和叶片按较大视野估计，其余由投影反推真实视野。

	vec3 viewRayDir = shadowVector * max(-viewPos.z * 3e-5 * fov, 0.06 * shadowDistance / shadowMapResolution); // 每一步在屏幕上的推进量，随深度与视野缩放并留最小步长。

	vec3 start = viewPos; // 步进起点。

	if (mask.grass + mask.leaves < 0.1){ // 普通表面才做偏移，草和叶片的画面已经足够软。
		float pixelScale = max(pixelSize.x, pixelSize.y); // 一个像素的最大边长，用来把偏移量折算到屏幕。
		float NdotL = saturate(dot(shadowVector, normal)); // 阳光与法线的夹角。

		start += viewRayDir * (pixelScale * max(0.04 / max(dot(normal, -viewDir), 0.1), 1e3)); // 沿光线先跳过一段，避免刚出发就打到自己。
		start += normal * (8e-3 * fov * -viewPos.z * pixelScale / max(NdotL, 0.01)); // 再沿法线抬一点，掠射角抬得更多。
	}

	vec3 end = start + viewRayDir; // 一步的终点。

	start = vec3(vec2(gbufferProjection[0][0], gbufferProjection[1][1]) * start.xy, -start.z); // 起点投影到裁剪空间。
	end   = vec3(vec2(gbufferProjection[0][0], gbufferProjection[1][1]) * end.xy,   -end.z); // 终点同样投影。

	vec3 screenRayDir = (end - start); // 这一步在裁剪空间的位移。
	screenRayDir.xy *= 0.5; // 横纵方向换算到零到一坐标。

	start.xy += gbufferProjection[3].xy; // 补上投影的平移项。
	start.xy *= 0.5; // 裁剪空间转到零到一。

	start += screenRayDir * mask.grass; // 草的原点再前进一小段，减少草自身投出的错误阴影。

	float absorption = 0.0; // 一次遮挡的吸收量。
	absorption += 0.7 * mask.grass; // 草的吸收系数。
	absorption += 0.85 * mask.leaves; // 叶片的吸收更强。
	absorption = pow(absorption, sqrt(-viewPos.z) * 0.5); // 距离越远吸收越弱，远处几何不再压黑。

	#ifdef OMNI_TAA // 打开时间抗锯齿时用逐帧抖动。
		float noise = BlueNoiseTemporal().x; // 每帧变化的抖动。
		#ifdef OMNI_DISABLE_PLAYER_TAA_MOTION_BLUR
			if (mask.entityPlayer > 0.5) noise = BlueNoise().x; // 玩家像素改用固定噪声。
		#endif
		vec2 offsetCoord = 0.5 + taaJitter * 0.5; // 采样坐标补上本帧抖动。
	#else // 不开时间抗锯齿时固定噪声。
		float noise = BlueNoise().x; // 固定噪声。
		vec2 offsetCoord = vec2(0.5); // 不补抖动。
	#endif

	float shadow = 1.0; // 阴影可见度，初值全亮。
	float stepLength = 1.0; // 步长，逐步增大。
	float zThickness = 0.025 + 0.0125 * -viewPos.z; // 遮挡厚度阈值，距离越远越厚，避免远处噪点。

	for (int i = 0; i < 12; i++, start += screenRayDir * stepLength, stepLength += 0.3){ // 最多十二步，步长递增覆盖更远。
		vec3 samplePos = start + screenRayDir * noise * stepLength; // 加抖动的采样位置。
		samplePos.xy = samplePos.xy / samplePos.z + offsetCoord; // 透视除法得到屏幕坐标。

		if (saturate(samplePos.xy) != samplePos.xy) break; // 出了屏幕就停止，屏幕外没有可靠深度。

		#ifdef DISTANT_HORIZONS // 有远景时先看近景深度，近景是天空才查远景。
			float sampleDepth = textureLod(depthtex1, samplePos.xy, 0.0).x; // 近景深度。
			float sampleDist = 0.0; // 采样点距离。

			if (sampleDepth == 1.0){ // 近景是天空。
				sampleDepth = textureLod(dhDepthTex1, samplePos.xy, 0.0).x; // 改读远景深度。
				sampleDist = LinearDepth_From_ScreenDepth_DH(sampleDepth); // 远景深度换成距离。
			}else{
				sampleDist = LinearDepth_From_ScreenDepth(sampleDepth); // 近景深度换成距离。
			}
		#else
			float sampleDist = LinearDepth_From_ScreenDepth(textureLod(depthtex1, samplePos.xy, 0.0).x); // 直接把深度换成距离。
		#endif

		float depthDiff = samplePos.z - sampleDist; // 当前射线深度与几何深度之差，为正说明几何在前面。

		if (depthDiff > 0.0 && depthDiff < zThickness) shadow *= absorption; // 落在厚度阈值内才算遮挡。

		if (shadow < 0.01) break; // 已经足够暗，提前结束。
	}

	return shadow; // 返回可见度。
}

#endif // 文件守卫结束。
