/*
水面折射与彩色透光吸收：把水下的采样按波法线偏移一次，再按水与玻璃的颜色吸收透过的光。
来源 iterationT 水面折射段与彩色玻璃吸收段。
调用位置：由 `effects/water/water.glsl` 引入；合成阶段处理半透明水面时调用 `RefractSampleOnce`、`TransparentAbsorption`。
可复制示例：
    `RefractSampleOnce(color, materialMask, normal, worldPos, viewPos);`
    `TransparentAbsorption(color, stainedGlassAlbedo, waterAbsorption);`
设计原因与取舍：折射与吸收都属“透过水看东西”，共用水的距离与颜色，放一起方便对照；
    折射会按体积雾与远景选项决定是否采样，保留 iterationT 的条件。
*/
#ifndef OMNI_WATER_REFRACTION_INCLUDED
#define OMNI_WATER_REFRACTION_INCLUDED // 置上标记，后续再次引用直接跳过。
// --- 水面折射：把采样坐标偏移一次再读回场景色 ---
// 调用位置：`rendering/composite.glsl`；先把采样点按水面法线偏移，再读一号画面的颜色。
// 对应 iterationT `composite5.fsh` 的 `WaterRefractionLite`，移植后改名以说明它只采样一次，避免含糊的 `Lite`。
// 防泄漏：偏移后的采样点若比当前水面更近，说明采到了前景物体，直接退回原位。
// 为什么分成水面与水外两条路：水面用波法线偏移更贴合，水外的玻璃等用整段折射方向偏移更准确。
// 为什么像素坐标由调用方传 `texelCoord`：渲染缩放或放大链下 `screenCoordInput` 与 `screenSize` 的口径可能不同，
//   用传入的整数像素坐标直接读深度，才与原程序一致，不会差出一个像素。
void RefractSampleOnce(inout vec3 color, MaterialMask mask, vec3 normal, vec3 worldPos, vec3 viewPos, float waterDist, float opaqueDist, float fogTimeFactor, float cloudShadow, vec2 screenCoordInput, ivec2 texelCoord){
	vec2 refractCoord = screenCoordInput; // 默认不折射，用原屏幕坐标。

	float waterDeep = opaqueDist - waterDist; // 水面到水底的厚度，越厚折射越强。

	if (mask.water > 0.5){ // 水面本身：用波法线偏移。
		float NdotU = dot(normal, gbufferModelView[1].xyz) + float(isEyeInWater == 1) * 2.0; // 法线朝向与水下判断。
		vec3 wavesNormal = GetWavesNormal(worldPos + cameraPosition, step(0.05, NdotU) * 18.0).xzy; // 求波法线并换到竖直轴朝上的坐标。
		vec4 wnv = gbufferModelView * vec4(wavesNormal.xyz, 0.0); // 波法线转到视空间。
		vec3 wavesNormalView = normalize(wnv.xyz); // 归一化。

		vec4 nv = gbufferModelView * vec4(0.0, 1.0, 0.0, 0.0); // 平水面法线转到视空间。
		nv.xyz = normalize(nv.xyz); // 归一化。

		refractCoord = nv.xy - wavesNormalView.xy; // 两种法线的差就是折射偏移方向。
		refractCoord *= saturate(waterDeep) * 0.5 / (waterDist + 0.0001); // 越深折射越强，除以距离避免远处偏移过大。
		refractCoord += screenCoordInput; // 加到原坐标上。
	}else{ // 玻璃等透明面：用整段折射方向。
		vec3 refractDir = refract(normalize(viewPos), normal, 0.66); // 视空间折射方向。
		refractDir = refractDir / saturate(dot(refractDir, -normal)); // 归一化到视线方向。
		refractDir *= saturate(waterDeep * 2.0) * 0.125; // 按厚度缩放。

		vec4 refractPos = vec4(viewPos + refractDir, 0.0); // 折射后的视空间位置。
		refractPos = gbufferProjection * refractPos; // 投影到裁剪空间。

		refractCoord = refractPos.xy / refractPos.w * 0.5 + 0.5; // 转成屏幕坐标。
	}

	float currentDepth = texelFetch(depthtex0, texelCoord, 0).x; // 当前像素的深度，直接用调用方传入的整数像素坐标，不靠屏幕坐标反推。
	float refractDepth = textureLod(depthtex1, refractCoord, 0.0).x; // 折射采样点的深度。
	if(refractDepth < currentDepth) refractCoord = screenCoordInput; // 采样点更近就是前景，退回原位防泄漏。

	refractCoord = mix(screenCoordInput, refractCoord, float(saturate(refractCoord) == refractCoord)); // 屏幕外的采样点也退回原位。

	color = CurveToLinear(textureLod(colortex1, refractCoord, 0.0).rgb); // 读回折射后的场景颜色。

	#if (defined OMNI_LANDSCATTERING && defined OMNI_LANDSCATTERING_REFRACTION) || (defined OMNI_VFOG && defined OMNI_VFOG_REFRACTION) // 只在同时开启地表散射或体积雾的折射时，给玻璃后面补雾。
		if (mask.stainedGlass > 0.5){ // 只处理彩色玻璃。
			float rDepth = textureLod(depthtex1, refractCoord, 0.0).x; // 折射点的深度。
			vec3 rViewPos = ViewPos_From_ScreenPos(refractCoord, rDepth); // 还原视空间位置。
			#ifdef DISTANT_HORIZONS // 有远景时，近景是天空就改用远景深度。
				if (rDepth == 1.0){ // 近景是天空。
					rDepth = textureLod(dhDepthTex1, refractCoord, 0.0).x; // 读远景深度。
					rViewPos = ViewPos_From_ScreenPos_DH(refractCoord, rDepth); // 远景还原位置。
				}
				float farDist = max(float(dhRenderDistance), far) * 1.4; // 远景可视距离。
				#ifdef OMNI_DH_LIMIT_VFOG_DIST
					farDist = min(2048.0, farDist); // 限制雾距离上限。
				#endif
			#else
				float farDist = far * 1.4; // 没有远景时用近景远裁剪面估计。
			#endif

			float rDist = min(length(rViewPos) + float(rDepth == 1.0) * 1e10, farDist); // 折射点距离，天空给很远。
			rDist = max(rDist - waterDist, 0.0); // 减去水面距离，只剩水体厚度。

			vec3 rWorldPos = mat3(gbufferModelViewInverse) * rViewPos; // 折射点转回相机相对世界。
			vec3 rWorldDir = normalize(rWorldPos); // 世界方向。

			vec3 endPos = rWorldDir * rDist; // 雾的终点。

			color *= MAIN_OUTPUT_FACTOR; // 换成管线线性单位，雾函数按此单位工作。

			#ifdef OMNI_LANDSCATTERING
				#ifdef OMNI_LANDSCATTERING_REFRACTION
					LandAtmosphericScattering(color, rDist, worldPos, endPos, rWorldDir, rDepth == 1.0); // 给折射后的场景补地表散射。
				#endif
			#endif

			#ifdef OMNI_VFOG
				#ifdef OMNI_VFOG_REFRACTION
					float fogTransmittance = 1.0; // 透射率占位，本处不返回。
					if (fogTimeFactor > 0.01 && isEyeInWater == 0) VolumetricFog(color, worldPos, endPos, rWorldDir, cloudShadow, fogTimeFactor, fogTransmittance); // 给折射后的场景补体积雾。
				#endif
			#endif

			color /= MAIN_OUTPUT_FACTOR; // 换回管线存储单位。
		}
	#endif
}

// --- 彩色玻璃吸收：按玻璃自身的颜色与不透明度吸收透过的光 ---
// 调用位置：`rendering/composite.glsl`；只影响彩色玻璃像素。
// 为什么把颜色归一化再乘回长度：贴图颜色可能很亮，先取方向与大致亮度，避免吸收过强或失效。
void TransparentAbsorption(inout vec3 color, vec4 stainedGlassAlbedo, float waterAbsorption){
	vec3 stainedGlassColor = normalize(stainedGlassAlbedo.rgb + 0.0001) * fsqrt(length(stainedGlassAlbedo.rgb)); // 归一化方向乘近似亮度。
	stainedGlassAlbedo.a = pow(stainedGlassAlbedo.a, 0.2); // 抬升不透明度曲线，让吸收更明显。

	#ifdef OMNI_UNDERWATER_FOG // 水下时玻璃吸收按水的吸收程度缩放。
		if (isEyeInWater == 1) stainedGlassAlbedo.a = mix(0.0, stainedGlassAlbedo.a, waterAbsorption); // 水越浅吸收越弱。
	#endif

	color *= GammaToLinear(mix(vec3(1.0), stainedGlassColor, stainedGlassAlbedo.a)); // 按不透明度在无吸收与玻璃色之间混合后吸收。
}
#endif // 文件守卫结束。
